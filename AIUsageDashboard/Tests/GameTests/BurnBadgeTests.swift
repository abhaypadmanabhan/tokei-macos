import XCTest
@testable import AIUsageDashboardCore

final class BurnBadgeTests: XCTestCase {
    func testEveryBadgeAtItsRuleBoundaryAndJustBelow() throws {
        let f = BurnFixtures()
        for badge in BurnBadge.allCases {
            func fixture(hit: Bool) -> (snapshot: BurnSnapshot, state: BurnState) {
                var days: [Int: Int] = [:]
                var samples: [QuotaSample] = []
                var agents: [ProviderSnapshot] = []
                switch badge {
                case .firstBurn: days = [0: hit ? 1 : 0]
                case .paidForItself: days = [0: hit ? 31_000_000 : 30_999_999]
                case .maxxing: days = [0: hit ? 62_000_000 : 61_999_999]
                case .goblinMode: days = [0: hit ? 155_000_000 : 154_999_999]
                case .millionDay: days = [0: hit ? 1_000_000 : 999_999]
                case .tenMillionDay: days = [0: hit ? 10_000_000 : 9_999_999]
                case .ranItDry: samples = [f.sample(used: hit ? 90 : 89.999)]
                case .fullWeek: samples = [f.sample(type: .weekly, used: hit ? 90 : 89.999)]
                case .streak3, .streak7, .streak30:
                    let target = badge == .streak3 ? 3 : badge == .streak7 ? 7 : 30
                    let count = hit ? target : target - 1
                    days = Dictionary(uniqueKeysWithValues: (0..<count).map { (-$0, 2_000_000) })
                case .fleet:
                    agents = [f.snapshot(.claudeCode, days: [0: 1]), f.snapshot(.cursor, days: [0: hit ? 1 : 0])]
                    days = [0: 1]
                case .nothingLeft:
                    samples = [f.sample(used: 100, account: "a"), f.sample(used: hit ? 80 : 79.999, account: "b")]
                }
                return f.evaluate([f.snapshot(days: days)] + agents, samples: samples)
            }
            let miss = fixture(hit: false)
            let locked = try XCTUnwrap(miss.snapshot.badges.first { $0.badge == badge })
            XCTAssertFalse(locked.isUnlocked, badge.rule)
            XCTAssertLessThan(try XCTUnwrap(locked.progress), 1, badge.rule)
            let hit = fixture(hit: true)
            let unlocked = try XCTUnwrap(hit.snapshot.badges.first { $0.badge == badge })
            XCTAssertEqual(unlocked.unlockedAt, f.now, badge.rule)
            XCTAssertEqual(unlocked.progress, 1, badge.rule)
            XCTAssertTrue(hit.snapshot.moments.isEmpty, "history seeds silently: \(badge)")
            let earned = f.evaluate([], state: hit.state)
            XCTAssertEqual(earned.snapshot.badges.first { $0.badge == badge }?.unlockedAt, f.now)
            XCTAssertTrue(earned.snapshot.moments.isEmpty)
            let later = f.evaluate([], state: miss.state)
            XCTAssertNil(later.snapshot.badges.first { $0.badge == badge }?.unlockedAt)
        }
    }

    func testBadgeUnlockMomentOnceAndTimestampSurvivesHistoryLoss() {
        let f = BurnFixtures()
        let seed = f.evaluate([f.snapshot(days: [0: 999_999])])
        let hit = f.evaluate([f.snapshot(days: [0: 1_000_000])], state: seed.state)
        XCTAssertEqual(hit.snapshot.moments.filter { $0 == .badge(.millionDay) }, [.badge(.millionDay)])
        let later = BurnFixtures(day: 10)
        let again = later.evaluate([], state: hit.state)
        XCTAssertEqual(again.snapshot.badges.first { $0.badge == .millionDay }?.unlockedAt, f.now)
        XCTAssertTrue(again.snapshot.moments.isEmpty)
    }

    func testSessionIsAFiveHourWindowAndFirstBurnNeedsAPlanNotItsPrice() {
        let f = BurnFixtures()
        let window = QuotaWindow(providerID: .codex, type: .session, used: 10, limit: 100,
                                 resetAt: f.now.addingTimeInterval(600), confidence: .providerReported, source: "fixture")
        let result = f.evaluate([f.snapshot(days: [0: 1], windows: [window])], plans: [:],
                                samples: [f.sample(type: .session)]).snapshot
        XCTAssertTrue(result.badges.first { $0.badge == .firstBurn }!.isUnlocked)
        XCTAssertTrue(result.badges.first { $0.badge == .ranItDry }!.isUnlocked)
    }

    func testNothingLeftNeedsACompletedNonemptyWeekAndAllAccounts() {
        let f = BurnFixtures()
        for samples in [[], [f.sample(used: 100, reset: f.day(0))],
                        [f.sample(used: 100, account: "a"), f.sample(used: 0, account: "b")]] {
            XCTAssertFalse(f.evaluate([], samples: samples).snapshot.badges.first { $0.badge == .nothingLeft }!.isUnlocked)
        }
    }
}
