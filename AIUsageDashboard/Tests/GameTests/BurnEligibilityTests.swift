import XCTest
@testable import AIUsageDashboardCore

final class BurnEligibilityTests: XCTestCase {
    private let f = BurnFixtures()
    private let apiProviders: [ProviderID] = [.cline, .opencode, .gemini]

    func testNoConfiguredPlanUsesExactlyTheFiveSubscriptionProducts() {
        let rule = BurnEligibility(monthlyPlanUSD: [:])
        XCTAssertEqual(rule.providers, [.claudeCode, .codex, .cursor, .antigravity, .copilot])
        XCTAssertTrue(rule.monthlyPlanUSD.isEmpty)
        for id in rule.providers {
            let result = f.evaluate([f.snapshot(id, days: [0: 1_000_000])], plans: [:]).snapshot
            XCTAssertEqual(result.today.tokens, 1_000_000, id.rawValue)
            XCTAssertEqual(result.today.valueUSD, 1, id.rawValue)
            XCTAssertTrue(result.badges.first { $0.badge == .firstBurn }!.isUnlocked, id.rawValue)
        }
    }

    func testOnlyFinitePositivePlanCostsConfigureEligibility() {
        let invalid: [ProviderID: Double] = [.codex: 0, .claudeCode: -1, .cursor: .nan,
                                           .gemini: .infinity, .opencode: -.infinity]
        let fallback = BurnEligibility(monthlyPlanUSD: invalid)
        XCTAssertEqual(fallback.providers, [.claudeCode, .codex, .cursor, .antigravity, .copilot])
        XCTAssertTrue(fallback.monthlyPlanUSD.isEmpty)
        let explicit = BurnEligibility(monthlyPlanUSD: invalid.merging([.cline: 31]) { _, new in new })
        XCTAssertEqual(explicit.providers, [.cline])
        XCTAssertEqual(explicit.monthlyPlanUSD, [.cline: 31])
    }

    func testUnplannedAPIProvidersCannotChangeAnyBurnNumber() {
        let base = f.snapshot(days: [-2: 2_000_000, -1: 2_000_000, 0: 2_000_000])
        let seed = f.evaluate([base], plans: [:])
        let expected = seed.snapshot
        for id in apiProviders {
            let extra = f.snapshot(id, days: [-3: 100_000_000, -2: 100_000_000, -1: 100_000_000, 0: 100_000_000],
                                   windows: [window(id)])
            let result = f.evaluate([base, extra], plans: [:], samples: [sample(id)]).snapshot
            XCTAssertEqual(result, expected, "\(id) without a configured plan must not affect any burn number")
            let onlyAPI = f.evaluate([extra], plans: [:], samples: [sample(id)]).snapshot
            XCTAssertEqual(onlyAPI, f.evaluate([], plans: [:]).snapshot, "\(id) alone is not plan burn")
            let refresh = f.evaluate([base, extra], plans: [:], samples: [sample(id)], state: seed.state)
            XCTAssertEqual(refresh.state, seed.state, "\(id) cannot change durable achievements")
            XCTAssertTrue(refresh.snapshot.moments.isEmpty, "\(id) cannot cause a celebration")
        }
    }

    func testUnplannedAPIProvidersCannotSupplyTokenFallbackHistory() {
        let base = f.snapshot(days: [-2: 10, -1: 30, 0: 100], priced: false)
        let expected = f.evaluate([base], plans: [:]).snapshot
        XCTAssertEqual(expected.today.goal, BurnGoal(unit: .tokens, target: 20))
        XCTAssertEqual(expected.today.progress, 5)
        for id in apiProviders {
            let extra = f.snapshot(id, days: [-4: 100_000_000, -3: 100_000_000, -2: 100_000_000, -1: 100_000_000,
                                              0: 100_000_000], priced: false)
            XCTAssertEqual(f.evaluate([base, extra], plans: [:]).snapshot, expected, "\(id) is not fallback history")
            let fresh = f.evaluate([f.snapshot(days: [0: 100], priced: false), extra], plans: [:]).snapshot
            XCTAssertNil(fresh.today.goal, "\(id) must not create a goal for a fresh subscription provider")
        }
    }

    func testFleetAndTokenBadgesCountOnlyEligibleProviders() {
        let snapshots = [f.snapshot(.codex, days: [0: 1_000_000]), f.snapshot(.claudeCode, days: [0: 1_000_000])]
            + apiProviders.map { f.snapshot($0, days: [0: 100_000_000]) }
        let result = f.evaluate(snapshots, plans: [:]).snapshot
        XCTAssertEqual(result.today.tokens, 2_000_000)
        XCTAssertEqual(result.today.valueUSD, 2)
        XCTAssertEqual(Set(result.leaderboard.map(\.providerID)), [.codex, .claudeCode])
        XCTAssertEqual(result.badges.first { $0.badge == .fleet }?.progress, 2.0 / 3)
        XCTAssertFalse(result.badges.first { $0.badge == .fleet }!.isUnlocked)
        XCTAssertFalse(result.badges.first { $0.badge == .tenMillionDay }!.isUnlocked)
    }

    func testAConfiguredPlanMakesEachProviderCountAndReplacesTheFallback() {
        for id in ProviderID.allCases {
            let planned = f.snapshot(id, days: [-2: 2_000_000, -1: 2_000_000, 0: 2_000_000], windows: [window(id)])
            let other: ProviderID = id == .codex ? .claudeCode : .codex
            let unplanned = f.snapshot(other, days: [-2: 100_000_000, -1: 100_000_000, 0: 100_000_000],
                                       windows: [window(other)])
            let plans = [id: 31.0]
            let expected = f.evaluate([planned], plans: plans, samples: [sample(id)]).snapshot
            let result = f.evaluate([planned, unplanned], plans: plans, samples: [sample(id), sample(other)]).snapshot
            XCTAssertEqual(result, expected, "only explicitly planned \(id) counts")
            XCTAssertEqual(result.today.tokens, 2_000_000)
            XCTAssertEqual(result.today.valueUSD, 2)
            XCTAssertEqual(result.today.goal, BurnGoal(unit: .usd, target: 1))
            XCTAssertEqual(result.today.progress, 2)
            XCTAssertEqual(result.streak.current, 3)
            XCTAssertEqual(result.records.bestDay?.value, 2)
            XCTAssertEqual(result.records.bestWeek?.value, 4)
            XCTAssertEqual(result.leaderboard.map(\.providerID), [id])
            XCTAssertEqual(result.recentWindows.map(\.providerID), [id])
            XCTAssertEqual(result.expiring.map(\.providerID), [id])
            for badge in [BurnBadge.firstBurn, .millionDay, .streak3, .fullWeek] {
                XCTAssertTrue(result.badges.first { $0.badge == badge }!.isUnlocked, "\(id) with a plan: \(badge.rule)")
            }
            XCTAssertFalse(result.badges.first { $0.badge == .fleet }!.isUnlocked)
        }
    }

    func testHiddenOrMissingConfiguredProviderDoesNotReenableFallback() {
        let codex = f.snapshot(days: [0: 2_000_000], windows: [window(.codex)])
        let cline = f.snapshot(.cline, days: [0: 3_000_000], windows: [window(.cline)])
        let empty = f.evaluate([], plans: [.cline: 31]).snapshot
        XCTAssertEqual(f.evaluate([codex], plans: [.cline: 31], samples: [sample(.codex)]).snapshot, empty)
        XCTAssertEqual(f.evaluate([codex, cline], plans: [.cline: 31], samples: [sample(.codex), sample(.cline)],
                                  hidden: [.cline]).snapshot, empty)
    }

    func testCostParityUsesTheSameEligibleProviderSubset() {
        let codex = f.snapshot(days: [0: 2_000_000])
        let cline = f.snapshot(.cline, days: [0: 3_000_000])
        let result = f.evaluate([codex, cline], plans: [.cline: 31]).snapshot
        let cost = UsageAnalytics.costSummary(snapshots: [cline], range: .today, pricing: f.pricing,
                                              calendar: f.calendar, now: f.now)
        XCTAssertEqual(result.today.valueUSD, cost.todayUSD)
        XCTAssertEqual(result.today.valueUSD, 3)
        XCTAssertEqual(result.today.tokens, 3_000_000)
    }

    private func window(_ id: ProviderID) -> QuotaWindow {
        QuotaWindow(providerID: id, type: .fiveHour, used: 38, limit: 100,
                    resetAt: f.now.addingTimeInterval(600), confidence: .providerReported,
                    source: "fixture", observedAt: f.now)
    }

    private func sample(_ id: ProviderID) -> QuotaSample {
        QuotaSample(providerID: id, windowType: .weekly, bucketKey: "weekly", usedPercent: 90,
                    used: 90, limit: 100, resetAt: f.day(-1), sampledAt: f.day(-1).addingTimeInterval(-60))
    }
}
