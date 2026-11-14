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
        let prior = BurnFixtures(month: 2, day: 28)
        let seed = prior.evaluate([prior.snapshot(days: [0: 2_000_000])])
        XCTAssertTrue(seed.snapshot.moments.isEmpty)
        XCTAssertEqual(seed.snapshot.records.bestDay?.value, 2)
        let f = BurnFixtures()
        let beat = f.evaluate([f.snapshot(days: [-9: 2_000_000, 0: 3_000_000])], state: seed.state)
        for kind in [BurnRecordKind.bestDay, .bestWeek, .bestMonthMultiple] {
            XCTAssertEqual(beat.snapshot.moments.filter { $0 == .record(kind) }.count, 1)
        }
        let growth = f.evaluate([f.snapshot(days: [-9: 2_000_000, 0: 3_100_000])], state: beat.state)
        XCTAssertTrue(growth.snapshot.moments.isEmpty)
        XCTAssertEqual(growth.snapshot.records.bestDay?.achievedAt, beat.snapshot.records.bestDay?.achievedAt)
        let again = f.evaluate([f.snapshot(days: [-9: 2_000_000, 0: 3_100_000])], state: growth.state)
        XCTAssertTrue(again.snapshot.moments.isEmpty)
        XCTAssertEqual(again.state, growth.state)
        let gone = f.evaluate([], state: growth.state)
        XCTAssertEqual(gone.snapshot.records, again.snapshot.records)
    }

    func testRecordGrowthWithinCurrentPeriodsAndHistoricalRepricingStaySilent() {
        let f = BurnFixtures()
        let seed = f.evaluate([f.snapshot(days: [-3: 2_000_000])])
        let beat = f.evaluate([f.snapshot(days: [-3: 2_000_000, 0: 2_500_000])], state: seed.state)
        XCTAssertTrue(beat.snapshot.moments.contains(.record(.bestDay)))
        XCTAssertTrue(beat.snapshot.moments.contains(.record(.bestWeek)))
        XCTAssertFalse(beat.snapshot.moments.contains(.record(.bestMonthMultiple)))
        let growth = f.evaluate([f.snapshot(days: [-3: 2_000_000, 0: 2_600_000])], state: beat.state)
        XCTAssertFalse(growth.snapshot.moments.contains { if case .record = $0 { return true }; return false })
        XCTAssertEqual(growth.snapshot.records.bestDay?.value, 2.6)
        let next = BurnFixtures(day: 10)
        let nextDay = next.evaluate([next.snapshot(days: [-4: 2_000_000, -1: 2_600_000, 0: 200_000])], state: growth.state)
        XCTAssertFalse(nextDay.snapshot.moments.contains { if case .record = $0 { return true }; return false })
        let repriced = next.evaluate([next.snapshot(days: [-4: 100_000_000, -1: 2_600_000, 0: 200_000])], state: nextDay.state)
        XCTAssertFalse(repriced.snapshot.moments.contains { if case .record = $0 { return true }; return false })
    }

    func testLongestStreakRecordUsesRunStartAndCelebratesOnlyANewRun() {
        let f = BurnFixtures()
        let seed = f.evaluate([f.snapshot(days: [-9: 2_000_000, -8: 2_000_000])])
        XCTAssertEqual(seed.snapshot.records.longestStreak?.achievedAt, f.day(-9))
        let beat = f.evaluate([f.snapshot(days: [-9: 2_000_000, -8: 2_000_000, -2: 2_000_000,
                                               -1: 2_000_000, 0: 2_000_000])], state: seed.state)
        XCTAssertEqual(beat.snapshot.records.longestStreak?.achievedAt, f.day(-2))
        XCTAssertEqual(beat.snapshot.moments.filter { $0 == .record(.longestStreak) }, [.record(.longestStreak)])
        let next = BurnFixtures(day: 10)
        let growth = next.evaluate([next.snapshot(days: [-10: 2_000_000, -9: 2_000_000, -3: 2_000_000,
                                                        -2: 2_000_000, -1: 2_000_000, 0: 2_000_000])], state: beat.state)
        XCTAssertEqual(growth.snapshot.records.longestStreak?.value, 4)
        XCTAssertEqual(growth.snapshot.records.longestStreak?.achievedAt, f.day(-2))
        XCTAssertFalse(growth.snapshot.moments.contains(.record(.longestStreak)))
    }

    func testJitteredResetSamplesProduceOneFinalOutcome() {
        let f = BurnFixtures()
        let reset = f.day(-1)
        let samples = [
            f.sample(used: 10, reset: reset, sampledAt: reset.addingTimeInterval(-4 * 3_600)),
            f.sample(used: 50, reset: reset.addingTimeInterval(1), sampledAt: reset.addingTimeInterval(-2 * 3_600)),
            f.sample(used: 95, reset: reset.addingTimeInterval(2), sampledAt: reset.addingTimeInterval(-600))
        ]
        let result = f.evaluate([], samples: samples).snapshot
        XCTAssertEqual(result.recentWindows.count, 1)
        XCTAssertEqual(result.recentWindows.first?.resetAt, reset.addingTimeInterval(2))
        XCTAssertEqual(result.recentWindows.first?.finalUsedPercent, 95)
        XCTAssertEqual(result.leftOnTablePercent, 5)
        XCTAssertTrue(result.badges.first { $0.badge == .nothingLeft }!.isUnlocked)
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
        ], plans: [.codex: 31, .claudeCode: 31, .cursor: 31], hidden: [.cline]).snapshot.leaderboard
        XCTAssertEqual(result.map(\.providerID), [.claudeCode, .codex, .cursor])
        XCTAssertEqual(result.map(\.rank), [1, 2, 3])
        XCTAssertEqual(result.map(\.tokens), [3_000_000, 2_000_000, 10_000_000])
        XCTAssertEqual(result[1].valueUSD, 2)
        XCTAssertNil(result[2].valueUSD)
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

    func testFractionalMultiProviderRecordsDoNotRefireOrRewriteOnIdenticalInputs() {
        let f = BurnFixtures()
        let snapshots = ProviderID.allCases.enumerated().map { index, id in
            f.snapshot(id, days: [-4: 11 + index, -3: 99 + index, -2: 17 + index, -1: 1 + index, 0: 33 + index])
        }
        let plans = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, 31.0) })
        let seed = f.evaluate(snapshots, plans: plans)
        for _ in 0..<50 {
            let result = f.evaluate(snapshots, plans: plans, state: seed.state)
            XCTAssertTrue(result.snapshot.moments.isEmpty)
            XCTAssertEqual(result.state, seed.state)
            XCTAssertEqual(result.snapshot.leaderboard, seed.snapshot.leaderboard)
            XCTAssertEqual(result.snapshot.today, seed.snapshot.today)
        }
    }

    func testFirstUsageAfterAnEmptySeedSetsARecordSilently() {
        let f = BurnFixtures()
        let seed = f.evaluate([])
        let result = f.evaluate([f.snapshot(days: [0: 2_000_000])], state: seed.state)
        XCTAssertEqual(result.snapshot.records.bestDay?.value, 2)
        XCTAssertFalse(result.snapshot.moments.contains(.record(.bestDay)), "no earlier record period to beat")
    }

    func testNinetyTwoDaysEightProvidersWithinGenerousTimingBound() {
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
        XCTAssertLessThan(elapsed, .milliseconds(250))
    }
}
