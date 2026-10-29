import XCTest
@testable import AIUsageDashboardCore

final class ExtraUsageRoutingTests: XCTestCase {
    func testExtraUsageNeverBindsAccountOrAvoidsProvider() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let windows = [
            QuotaWindow(providerID: .claudeCode, type: .session, used: 10, limit: 100,
                        resetAt: now.addingTimeInterval(9_000), confidence: .providerReported,
                        source: "fixture", observedAt: now),
            QuotaWindow(providerID: .claudeCode, type: .credits, used: 49.5, limit: 50,
                        confidence: .providerReported, source: "fixture disabled out_of_credits",
                        bucketKey: "claude_extra_usage", observedAt: now)
        ]
        let account = ProviderAccountUsage(id: "/fixture", accountID: "claude_code:fixture",
                                           label: "fixture", quotaWindows: windows,
                                           todayUsage: .unavailable, quotaStatus: .eligible)
        let decision = AccountQuotaDecision.evaluate(account, providerID: .claudeCode, now: now)
        XCTAssertEqual(decision.status, .eligible)
        XCTAssertEqual(decision.bindingWindowIndex, 0)
        XCTAssertEqual(decision.headroomPercent, 90)
        let provider = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude",
                                        authStatus: .authenticated, quotaWindows: windows,
                                        todayUsage: .unavailable, weekUsage: .unavailable,
                                        accounts: [account])
        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
        XCTAssertFalse(snapshot.recommendation?.avoid.contains("claude_code") ?? false)
        XCTAssertTrue(snapshot.recommendation?.avoidAccounts?.isEmpty ?? true)
    }
}
