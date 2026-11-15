import XCTest
@testable import AIUsageDashboardCore

final class RoutePlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(_ id: ProviderID, used: Double, reset: TimeInterval = 172_800,
                          type: QuotaWindowType = .weekly, age: TimeInterval = 0,
                          confidence: MetricConfidence = .providerReported) -> ProviderSnapshot {
        ProviderSnapshot(providerID: id, displayName: id.rawValue, authStatus: .authenticated,
                         quotaWindows: [QuotaWindow(providerID: id, type: type, used: used, limit: 100,
                                                     resetAt: now.addingTimeInterval(reset), confidence: confidence,
                                                     source: "fixture", observedAt: now.addingTimeInterval(-age))],
                         todayUsage: .unavailable, weekUsage: .unavailable)
    }

    func testTableOfRankingsAndUnknownStates() {
        let cases: [([ProviderSnapshot], [ProviderID], [ProviderID], ProviderID?)] = [
            ([], [], [], nil),
            ([snapshot(.codex, used: 20)], [.codex], [], .codex),
            ([snapshot(.codex, used: 100), snapshot(.claudeCode, used: 90)], [.claudeCode, .codex], [], nil),
            ([snapshot(.codex, used: 20, age: 1_801)], [], [.codex], nil),
            ([snapshot(.codex, used: 20, confidence: .estimated)], [], [.codex], nil),
            ([snapshot(.codex, used: 20, reset: -1)], [], [.codex], nil),
            ([snapshot(.codex, used: 20, age: -61)], [], [.codex], nil),
            ([snapshot(.codex, used: 20, type: .credits)], [], [], nil),
            ([snapshot(.codex, used: 20), snapshot(.claudeCode, used: 20)], [.claudeCode, .codex], [], .claudeCode),
            ([snapshot(.codex, used: 40, reset: 600, type: .fiveHour), snapshot(.claudeCode, used: 10)],
             [.codex, .claudeCode], [], .codex),
            ([snapshot(.codex, used: 40, reset: 600), snapshot(.claudeCode, used: 40, reset: 300)],
             [.claudeCode, .codex], [], .claudeCode),
            // Neither is expiring. Codex has spent less relative to elapsed time.
            ([snapshot(.codex, used: 50, reset: 172_800), snapshot(.claudeCode, used: 10, reset: 590_000)],
             [.codex, .claudeCode], [], .codex)
        ]
        for (input, ranked, excluded, target) in cases {
            let result = RoutePlan.make(snapshots: input, now: now)
            XCTAssertEqual(result.rows.map(\.providerID), ranked)
            XCTAssertEqual(result.unknown.map(\.providerID), excluded)
            XCTAssertEqual(result.recommendation?.providerID, target)
            for policy in [RouteTargetPolicy.agent, .human] {
                if let chosen = policy.routeTarget(in: UtilizationEngine.utilizations(from: input), now: now) {
                    XCTAssertEqual(chosen.providerID, result.rows.first?.providerID)
                }
            }
        }
    }

    func testRowsCarryDecidingWindowPaceResetAndOneSentence() throws {
        let plan = RoutePlan.make(snapshots: [snapshot(.codex, used: 40, reset: 600, type: .fiveHour)], now: now)
        let row = try XCTUnwrap(plan.recommendation)
        XCTAssertEqual(row.windowType, .fiveHour)
        XCTAssertEqual(row.remainingPercent, 60, accuracy: 0.001)
        XCTAssertEqual(row.secondsToReset, 600)
        XCTAssertEqual(row.paceState, .behind)
        XCTAssertEqual(row.reason, "Use this plan before unused capacity resets in 10m.")
        XCTAssertEqual(row.validUntil, now.addingTimeInterval(600))
    }

    func testOtherAccountLimitsCannotBeHiddenByExpiringCapacity() {
        let fresh = snapshot(.codex, used: 20, reset: 600, type: .fiveHour).quotaWindows[0]
        let blocked = snapshot(.codex, used: 98).quotaWindows[0]
        let stale = snapshot(.codex, used: 10, age: 1_801).quotaWindows[0]
        for (windows, count, disposition) in [([fresh, blocked], 1, RoutePlan.Disposition.avoid),
                                               ([fresh, stale], 0, .ready)] {
            let value = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                         quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable)
            let plan = RoutePlan.make(snapshots: [value], now: now)
            XCTAssertEqual(plan.rows.count, count)
            if count > 0 { XCTAssertEqual(plan.rows[0].disposition, disposition) }
            XCTAssertNil(plan.recommendation)
        }
    }

    func testAccountLabelsAreBoundedAndHeadlineUsesTheSameOrder() throws {
        let accounts = [
            ProviderAccountUsage(id: "/a", accountID: "codex:a", label: "person@example.com",
                                 quotaWindows: snapshot(.codex, used: 40, reset: 600, type: .fiveHour).quotaWindows,
                                 todayUsage: .unavailable, quotaStatus: .eligible),
            ProviderAccountUsage(id: "/b", accountID: "codex:b", label: "work",
                                 quotaWindows: snapshot(.codex, used: 10).quotaWindows,
                                 todayUsage: .unavailable, quotaStatus: .eligible)
        ]
        let value = ProviderSnapshot(providerID: .codex, displayName: "unsafe\nname", authStatus: .authenticated,
                                     todayUsage: .unavailable, weekUsage: .unavailable, accounts: accounts)
        let plan = RoutePlan.make(snapshots: [value], now: now)
        XCTAssertEqual(plan.rows.map(\.accountLabel), ["account 1", "work"])
        XCTAssertEqual(plan.rows.first?.providerName, "Codex")
        XCTAssertEqual(AccountQuotaDecision.headline(among: accounts, providerID: .codex, now: now)?.account.accountID, "codex:a")
    }
}
