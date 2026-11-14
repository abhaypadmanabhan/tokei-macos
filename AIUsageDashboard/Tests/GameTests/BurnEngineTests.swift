import XCTest
@testable import AIUsageDashboardCore

final class BurnEngineTests: XCTestCase {
    func testPureFixedClockUTCAndDSTAndCostViewParity() throws {
        for zone in ["UTC", "America/Los_Angeles"] {
            let f = BurnFixtures(zone: zone)
            let snapshots = [f.snapshot(days: [-2: 2_000_000, -1: 2_000_000, 0: 3_000_000]),
                             f.snapshot(.claudeCode, days: [0: 2_000_000])]
            let a = f.evaluate(snapshots, plans: [.codex: 31, .claudeCode: 62])
            let b = f.evaluate(snapshots, plans: [.codex: 31, .claudeCode: 62])
            XCTAssertEqual(a.snapshot, b.snapshot)
            XCTAssertEqual(a.state, b.state)
            XCTAssertEqual(a.snapshot.today.day, f.day(0))
            XCTAssertEqual(a.snapshot.today.goal, BurnGoal(unit: .usd, target: 3))
            XCTAssertEqual(try XCTUnwrap(a.snapshot.today.progress), 5.0 / 3, accuracy: 0.000_001)
            let cost = UsageAnalytics.costSummary(snapshots: snapshots, range: .today, pricing: f.pricing,
                                                  calendar: f.calendar, now: f.now)
            XCTAssertEqual(a.snapshot.today.valueUSD, cost.todayUSD)
            XCTAssertEqual(a.snapshot.today.valueUSD, 5)
        }
    }

    func testTokenMedianExcludesTodayZerosOldHistoryAndHiddenProviders() throws {
        let f = BurnFixtures()
        let snapshots = [f.snapshot(days: [-31: 999, -30: 10, -3: 20, -2: 0, -1: 30, 0: 100], priced: false),
                         f.snapshot(.cline, days: [-1: 1_000_000])]
        let result = f.evaluate(snapshots, plans: [:], hidden: [.cline]).snapshot
        XCTAssertEqual(result.today.goal, BurnGoal(unit: .tokens, target: 20))
        XCTAssertEqual(result.today.progress, 5)
        XCTAssertNil(f.evaluate([f.snapshot(days: [0: 100], priced: false)], plans: [:]).snapshot.today.goal)
        let even = f.evaluate([f.snapshot(days: [-2: 10, -1: 20], priced: false)], plans: [:]).snapshot
        XCTAssertEqual(even.today.goal?.target, 15)
    }

    func testMissingPricesStayUnknown() {
        let f = BurnFixtures()
        let result = f.evaluate([f.snapshot(days: [0: 2_000_000], priced: false)]).snapshot
        XCTAssertNil(result.today.valueUSD)
        XCTAssertNil(result.today.progress)
        XCTAssertFalse(result.today.goalHit)
    }

    func testStreakGapAtRiskMonthBoundaryAndPersistedLongest() {
        let f = BurnFixtures(zone: "America/Los_Angeles", month: 3, day: 2)
        let live = f.snapshot(days: [-5: 2_000_000, -4: 2_000_000, -2: 2_000_000, -1: 2_000_000])
        var state = BurnState()
        state.longestStreak = 12
        let result = f.evaluate([live], state: state).snapshot.streak
        XCTAssertEqual(result.current, 2)
        XCTAssertEqual(result.longest, 12)
        XCTAssertFalse(result.todayHit)
        XCTAssertTrue(result.atRisk)
        let hit = f.evaluate([f.snapshot(days: [-2: 2_000_000, -1: 2_000_000, 0: 2_000_000])]).snapshot.streak
        XCTAssertEqual(hit.current, 3)
        XCTAssertTrue(hit.todayHit)
        XCTAssertFalse(hit.atRisk)
    }

    func testRecordsSeedSilentlyBeatOnceAndKeepTheirDates() {
        let f = BurnFixtures()
        let seed = f.evaluate([f.snapshot(days: [0: 2_000_000])])
        XCTAssertTrue(seed.snapshot.moments.isEmpty)
        XCTAssertEqual(seed.snapshot.records.bestDay?.value, 2)
        let beat = f.evaluate([f.snapshot(days: [0: 3_000_000])], state: seed.state)
        for kind in [BurnRecordKind.bestDay, .bestWeek, .bestMonthMultiple] {
            XCTAssertEqual(beat.snapshot.moments.filter { $0 == .record(kind) }.count, 1)
        }
        let again = f.evaluate([f.snapshot(days: [0: 3_000_000])], state: beat.state)
        XCTAssertTrue(again.snapshot.moments.isEmpty)
        XCTAssertEqual(again.state, beat.state)
        let gone = f.evaluate([], state: beat.state)
        XCTAssertEqual(gone.snapshot.records, again.snapshot.records)
    }

    func testBestWeekUsesCalendarWeekAndTokenFallback() {
        let f = BurnFixtures() // Monday, first weekday in this calendar.
        let result = f.evaluate([f.snapshot(days: [-2: 40, -1: 60, 0: 90], priced: false)], plans: [:]).snapshot
        XCTAssertEqual(result.records.bestDay?.value, 90)
        XCTAssertEqual(result.records.bestDay?.unit, .tokens)
        XCTAssertEqual(result.records.bestWeek?.value, 100)
        XCTAssertEqual(result.records.bestWeek?.achievedAt, f.day(-7))
    }

    func testLeaderboardUsesCalendarWeekVisibleProvidersUSDThenTokens() {
        let f = BurnFixtures()
        let result = f.evaluate([
            f.snapshot(.codex, days: [-1: 99_000_000, 0: 2_000_000]),
            f.snapshot(.claudeCode, days: [0: 3_000_000]),
            f.snapshot(.cursor, days: [0: 10_000_000], priced: false),
            f.snapshot(.cline, days: [0: 100_000_000])
        ], hidden: [.cline]).snapshot.leaderboard
        XCTAssertEqual(result.map(\.providerID), [.claudeCode, .codex, .cursor])
        XCTAssertEqual(result.map(\.rank), [1, 2, 3])
        XCTAssertEqual(result.map(\.tokens), [3_000_000, 2_000_000, 10_000_000])
        XCTAssertEqual(result[1].valueUSD, 2)
    }

    func testWindowOutcomesLastReadingBeforeResetNeverMixAccountsOrPaidWindows() {
        let f = BurnFixtures()
        let reset = f.day(-1)
        let samples = [f.sample(used: 10, account: "a", sampledAt: reset.addingTimeInterval(-100)),
                       f.sample(used: 95, account: "a"), f.sample(used: 30, account: "b"),
                       f.sample(used: 5, account: "a", sampledAt: reset.addingTimeInterval(1)),
                       f.sample(type: .credits, used: 100, account: "a"),
                       f.sample(type: .perModel, used: 100, account: "a"),
                       f.sample(used: 100), // Legacy headline is not another account.
                       f.sample(reset: f.day(-8)), f.sample(reset: f.day(1))]
        let result = f.evaluate([], samples: samples).snapshot.recentWindows
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: result.map { ($0.accountID!, $0.finalUsedPercent) }),
                       ["a": 95, "b": 30])
        XCTAssertEqual(f.evaluate([], samples: samples).snapshot.leftOnTablePercent, 37.5)
    }

    func testTierMatchesMaxxerAndOnlyRisesWithinSameMonth() throws {
        let f = BurnFixtures()
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plans = MaxxerPlanCostStore(defaults: defaults)
        plans.setMonthlyUSD(31, for: "codex")
        var previous = BurnState()
        for (tokens, expected) in [(1_000_000, MaxxerTier.idle), (10_000_000, .warming),
                                    (31_000_000, .breakEven), (62_000_000, .maxxing), (155_000_000, .goblinMode)] {
            let snapshot = f.snapshot(days: [0: tokens])
            let result = f.evaluate([snapshot], state: previous)
            let maxxer = MaxxerValueEngine.scorecard(snapshots: [snapshot], planCosts: plans, now: f.now, pricing: f.pricing)
            XCTAssertEqual(result.snapshot.monthValueMultiple, maxxer.totalValueMultiple)
            XCTAssertEqual(result.snapshot.tier, maxxer.tier)
            XCTAssertEqual(result.snapshot.tier, expected)
            XCTAssertEqual(result.snapshot.moments.contains(.tierUp(expected)), previous.initialized)
            previous = result.state
        }
        let april = BurnFixtures(month: 4, day: 1)
        previous.tier = MaxxerTier.idle.rawValue
        XCTAssertFalse(april.evaluate([april.snapshot(days: [0: 155_000_000])], state: previous)
            .snapshot.moments.contains(.tierUp(.goblinMode)))
    }

    func testNinetyTwoDaysEightProvidersWithinFiftyMilliseconds() {
        let f = BurnFixtures()
        let snapshots = ProviderID.allCases.map { id in
            f.snapshot(id, days: Dictionary(uniqueKeysWithValues: (-91...0).map { ($0, 2_000_000) }))
        }
        let plans = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, 31.0) })
        _ = f.evaluate(snapshots, plans: plans) // Warm process/framework initialization.
        let start = ContinuousClock.now
        _ = f.evaluate(snapshots, plans: plans)
        let elapsed = start.duration(to: .now)
        print("BURN_TIMING 92 days x 8 providers: \(elapsed)")
        XCTAssertLessThan(elapsed, .milliseconds(50))
    }
}
