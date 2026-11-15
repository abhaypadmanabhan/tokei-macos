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
        let tightWeekly = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                           quotaWindows: [snapshot(.claudeCode, used: 0, reset: 1_800, type: .session).quotaWindows[0],
                                                          snapshot(.claudeCode, used: 80).quotaWindows[0]],
                                           todayUsage: .unavailable, weekUsage: .unavailable)
        let tightModel = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                          quotaWindows: [snapshot(.claudeCode, used: 10).quotaWindows[0],
                                                         snapshot(.claudeCode, used: 95, type: .perModel).quotaWindows[0]],
                                          todayUsage: .unavailable, weekUsage: .unavailable)
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
             [.codex, .claudeCode], [], .codex),
            // P1: unknown monthly pace must not invent 100 points of elapsed time.
            ([snapshot(.cursor, used: 80, reset: 20 * 86_400, type: .monthly),
              snapshot(.claudeCode, used: 0, reset: 7 * 86_400 - 3_600)], [.claudeCode, .cursor], [], .claudeCode),
            // P2: the expiring session cannot spend more than the weekly pool leaves.
            ([tightWeekly, snapshot(.codex, used: 0)], [.codex, .claudeCode], [], .codex),
            // P3: a per-model limit is a binding constraint on the same plan.
            ([tightModel, snapshot(.codex, used: 50)], [.codex, .claudeCode], [], .codex)
        ]
        for (input, ranked, excluded, target) in cases {
            let result = RoutePlan.make(snapshots: input, now: now)
            XCTAssertEqual(result.rows.map(\.providerID), ranked)
            XCTAssertEqual(result.unknown.map(\.providerID), excluded)
            XCTAssertEqual(result.recommendation?.providerID, target)
            for policy in [RouteTargetPolicy.agent, .human] {
                let decision = policy.evaluate(UtilizationEngine.utilizations(from: input), now: now)
                let unknownIDs = Set(result.unknown.map(\.providerID))
                let avoided = Set(decision.avoid.map(\.providerID)).subtracting(unknownIDs)
                XCTAssertEqual(Set(result.rows.filter { $0.disposition == .avoid }.map(\.providerID)), avoided)
                XCTAssertTrue(Set(result.rows.filter { $0.disposition == .ready }.map(\.providerID)).isDisjoint(with: avoided))
                if let chosen = decision.routeTo {
                    XCTAssertEqual(chosen.providerID, result.rows.first?.providerID)
                }
                if policy == .agent, Set(result.rows.map(\.providerID)).count >= policy.minTrustedProviders || result.recommendation == nil {
                    XCTAssertEqual(decision.routeTo?.providerID, result.recommendation?.providerID)
                }
            }
        }
    }

    func testS1LegacyRecommendationStillSelectsTheEmptyPlanWhenMonthlyPaceIsUnknown() {
        let values = [snapshot(.cursor, used: 80, reset: 20 * 86_400, type: .monthly),
                      snapshot(.claudeCode, used: 0, reset: 7 * 86_400 - 3_600)]
        let publicSnapshot = AgentSnapshotWriter.buildSnapshot(from: values, generatedAt: now)
        XCTAssertEqual(publicSnapshot.recommendation?.routeTo, "claude_code")
        XCTAssertEqual(publicSnapshot.route?.rows.first?.provider, "claude_code")
    }

    func testS2ExpiryPriorityIsBoundedByEveryOtherLimitAtTheFinderFloor() throws {
        for (remaining, expiring) in [(24.0, false), (25.0, true), (26.0, true)] {
            let value = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                         quotaWindows: [snapshot(.claudeCode, used: 0, reset: 1_800, type: .session).quotaWindows[0],
                                                        snapshot(.claudeCode, used: 100 - remaining).quotaWindows[0]],
                                         todayUsage: .unavailable, weekUsage: .unavailable)
            let row = try XCTUnwrap(RoutePlan.make(snapshots: [value], now: now).rows.first)
            XCTAssertEqual(row.expiringAt != nil, expiring, "remaining \(remaining)")
        }
    }

    func testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown() {
        let value = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                     quotaWindows: [snapshot(.claudeCode, used: 30).quotaWindows[0],
                                                    snapshot(.claudeCode, used: 5, type: .perModel, confidence: .estimated).quotaWindows[0]],
                                     todayUsage: .unavailable, weekUsage: .unavailable)
        let plan = RoutePlan.make(snapshots: [value, snapshot(.codex, used: 50)], now: now)
        XCTAssertEqual(plan.rows.map(\.providerID), [.codex])
        XCTAssertEqual(plan.unknown.map(\.providerID), [.claudeCode])
        let decision = RouteTargetPolicy.agent.evaluate(UtilizationEngine.utilizations(from: [value, snapshot(.codex, used: 50)]), now: now)
        XCTAssertNil(decision.routeTo)
        XCTAssertEqual(decision.excluded.map(\.providerID), [.claudeCode])
    }

    func testS9CodexHeadlineAndRowsIgnoreTheSameUncomputableSessionShell() {
        let shell = QuotaWindow(providerID: .codex, type: .fiveHour, confidence: .unavailable, source: "fixture")
        let accounts = [
            ProviderAccountUsage(id: "/a", accountID: "codex:a", label: "A",
                                 quotaWindows: [snapshot(.codex, used: 10).quotaWindows[0], shell],
                                 todayUsage: .unavailable, quotaStatus: .eligible),
            ProviderAccountUsage(id: "/b", accountID: "codex:b", label: "B",
                                 quotaWindows: snapshot(.codex, used: 50).quotaWindows,
                                 todayUsage: .unavailable, quotaStatus: .eligible)
        ]
        let value = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                     todayUsage: .unavailable, weekUsage: .unavailable, accounts: accounts)
        XCTAssertEqual(RoutePlan.make(snapshots: [value], now: now).recommendation?.accountLabel, "A")
        XCTAssertEqual(AccountQuotaDecision.headline(among: accounts, providerID: .codex, now: now)?.account.accountID, "codex:a")
        XCTAssertEqual(AgentSnapshotWriter.buildSnapshot(from: [value], generatedAt: now).providers.first?.headlineAccountID, "codex:a")
    }

    func testCodexIndividualLimitBindsAccountRoutePolicyAndCLIWithoutRoutingToPaidCredits() throws {
        for used in [40.0, 90.0] {
            let limit = QuotaWindow(providerID: .codex, type: .credits, used: used, limit: 100,
                                    confidence: .providerReported, source: "fixture",
                                    label: "Monthly credit limit", bucketKey: "spend_control_individual_limit", observedAt: now)
            let paid = QuotaWindow(providerID: .codex, type: .credits, used: 100, limit: 100,
                                   confidence: .providerReported, source: "fixture", bucketKey: "credits", observedAt: now)
            let windows = snapshot(.codex, used: 20).quotaWindows + [limit, paid]
            let account = ProviderAccountUsage(id: "/fixture", accountID: "codex:fixture", label: "fixture",
                                               quotaWindows: windows, todayUsage: .unavailable, quotaStatus: .eligible)
            let value = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                         quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable, accounts: [account])
            let input = [value, snapshot(.claudeCode, used: 70)]
            let plan = RoutePlan.make(snapshots: input, now: now)
            let row = try XCTUnwrap(plan.rows.first { $0.providerID == .codex })
            XCTAssertEqual(row.remainingPercent, 100 - used)
            XCTAssertEqual(row.windowType, .monthly)
            XCTAssertEqual(row.disposition, used >= 85 ? .avoid : .ready)
            XCTAssertEqual(AccountQuotaDecision.evaluate(account, providerID: .codex, now: now).headroomPercent, 100 - used)
            let policy = RouteTargetPolicy.agent.evaluate(UtilizationEngine.utilizations(from: input), now: now)
            XCTAssertEqual(policy.routeTo?.providerID, plan.recommendation?.providerID)
            XCTAssertEqual(policy.avoid.map(\.providerID), plan.rows.filter { $0.disposition == .avoid }.map(\.providerID))
            let exported = AgentSnapshotWriter.buildSnapshot(from: input, generatedAt: now)
            XCTAssertEqual(exported.recommendation?.routeTo, plan.recommendation?.providerID.rawValue)
            XCTAssertEqual(exported.recommendation?.avoid, plan.rows.filter { $0.disposition == .avoid }.map { $0.providerID.rawValue })
            let output = RouteFormatting.output(exported, now: now)
            XCTAssertEqual(output.rows.first { $0.provider == "codex" }?.remainingPercent, 100 - used)
            XCTAssertTrue(output.unknown.isEmpty)
        }
    }

    func testCodexCapAloneIsNeverPlanCoverageForProviderOrAccount() {
        let cap = QuotaWindow(providerID: .codex, type: .credits, used: 20, limit: 100,
                              confidence: .providerReported, source: "fixture",
                              bucketKey: "spend_control_individual_limit", observedAt: now)
        let account = ProviderAccountUsage(id: "/fixture", accountID: "codex:fixture", label: "fixture",
                                           quotaWindows: [cap], todayUsage: .unavailable, quotaStatus: .eligible)
        let peer = snapshot(.claudeCode, used: 70)
        for accounts in [nil, [account]] as [[ProviderAccountUsage]?] {
            let value = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                         quotaWindows: [cap], todayUsage: .unavailable, weekUsage: .unavailable, accounts: accounts)
            let plan = RoutePlan.make(snapshots: [value], now: now)
            XCTAssertTrue(plan.rows.isEmpty)
            XCTAssertNil(plan.recommendation)
            XCTAssertNil(AccountQuotaDecision.headline(among: accounts ?? [], providerID: .codex, now: now))
            XCTAssertNil(AgentSnapshotWriter.buildSnapshot(from: [value], generatedAt: now).recommendation)
            let utilizations = UtilizationEngine.utilizations(from: [value, peer])
            XCTAssertFalse(UtilizationEngine.aggregate(from: [value, peer])?.coveredProviders.contains(.codex) ?? true)
            XCTAssertNil(RouteTargetPolicy.agent.evaluate(utilizations, now: now).routeTo,
                         "a cap alone cannot count as the second covered provider")
        }
    }

    func testCodexCapIdentitySurvivesUtilizationEncoding() throws {
        let cap = QuotaWindow(providerID: .codex, type: .credits, used: 20, limit: 100,
                              confidence: .providerReported, source: "fixture",
                              bucketKey: "spend_control_individual_limit", observedAt: now)
        let value = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                     quotaWindows: snapshot(.codex, used: 10).quotaWindows + [cap],
                                     todayUsage: .unavailable, weekUsage: .unavailable)
        let utilization = try XCTUnwrap(UtilizationEngine.utilizations(from: [value]).first { $0.window == .monthly })
        let data = try JSONEncoder().encode(utilization)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["bucketKey"] as? String, "spend_control_individual_limit")
        let decoded = try JSONDecoder().decode(Utilization.self, from: data)
        XCTAssertTrue(RouteTargetPolicy.agent.evaluate([decoded], now: now).peaks.isEmpty)
        object.removeValue(forKey: "bucketKey")
        XCTAssertNoThrow(try JSONDecoder().decode(Utilization.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testCodexCapResetSoonCannotChangePlanPolicyChipOrExportedOrdering() {
        for type in [QuotaWindowType.credits, .monthly] {
            let cap = QuotaWindow(providerID: .codex, type: type, used: 10, limit: 100,
                                  resetAt: now.addingTimeInterval(2 * 86_400), confidence: .providerReported,
                                  source: "fixture", bucketKey: "spend_control_individual_limit", observedAt: now)
            let codex = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                          quotaWindows: snapshot(.codex, used: 50, reset: 5 * 86_400).quotaWindows + [cap],
                                          todayUsage: .unavailable, weekUsage: .unavailable)
            let input = [codex, snapshot(.claudeCode, used: 30, reset: 5 * 86_400)]
            let plan = RoutePlan.make(snapshots: input, now: now)
            let utilizations = UtilizationEngine.utilizations(from: input)
            let exported = AgentSnapshotWriter.buildSnapshot(from: input, generatedAt: now)
            XCTAssertEqual(plan.recommendation?.providerID, .claudeCode)
            XCTAssertTrue(plan.rows.allSatisfy { $0.expiringAt == nil })
            XCTAssertEqual(RouteTargetPolicy.agent.routeTarget(in: utilizations, now: now)?.providerID, .claudeCode)
            let chipInput = utilizations.filter { $0.window != .credits }
            XCTAssertEqual(MaxxerMath.routeTarget(in: chipInput, now: now)?.providerID, .claudeCode)
            XCTAssertEqual(exported.recommendation?.routeTo, "claude_code")
            XCTAssertEqual(exported.recommendation?.avoid, [])
            XCTAssertEqual(exported.route?.rows.first?.provider, "claude_code")
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

    func testReportedMonthlyDurationRanksByActualPaceOnBothPaths() {
        let snapshots: [ProviderSnapshot] = [(.codex, 50.0, 10.0), (.claudeCode, 10.0, 29.0)].map { id, used, days in
            ProviderSnapshot(providerID: id, displayName: id.rawValue, authStatus: .authenticated,
                             quotaWindows: [QuotaWindow(providerID: id, type: .monthly, used: used, limit: 100,
                                                         resetAt: now.addingTimeInterval(days * 86_400), confidence: .providerReported,
                                                         source: "fixture", observedAt: now, windowDuration: 30 * 86_400)],
                             todayUsage: .unavailable, weekUsage: .unavailable)
        }
        XCTAssertEqual(RoutePlan.make(snapshots: snapshots, now: now).recommendation?.providerID, .codex)
        XCTAssertEqual(RouteTargetPolicy.agent.routeTarget(in: UtilizationEngine.utilizations(from: snapshots), now: now)?.providerID, .codex)
    }

    func testDurationPersistsAndOlderCacheEntriesDecodeWithoutIt() async throws {
        let utilization = Utilization(providerID: .codex, window: .monthly, usedPercent: 50, confidence: .providerReported,
                                       windowDuration: 30 * 86_400)
        let data = try JSONEncoder().encode(utilization)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["windowDuration"] as? Double, 30 * 86_400)
        object.removeValue(forKey: "windowDuration")
        let old = try JSONDecoder().decode(Utilization.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.windowDuration)
        XCTAssertEqual(old.providerID, .codex)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = UtilizationCache(directory: directory)
        await writer.store([utilization], for: .codex)
        let reader = UtilizationCache(directory: directory)
        let restored = await reader.lastGood(for: .codex)
        XCTAssertEqual(restored?.first?.windowDuration, 30 * 86_400)
    }
}
