import XCTest
@testable import AIUsageDashboardCore

/// WP-3 / handoff P4: with multi-account Claude live, "route to Claude Code (tightest
/// window 7%)" is ambiguous — 7% of *which* account? The reason must name the account
/// the headline number came from, in the form the reader has to export.
final class AgentRecommendationAccountTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let names: [ProviderID: String] = [
        .claudeCode: "Claude Code", .codex: "OpenAI Codex",
    ]

    private func util(_ providerID: ProviderID, _ percent: Double) -> Utilization {
        Utilization(providerID: providerID, window: .weekly, usedPercent: percent, confidence: .exact)
    }

    private func account(_ id: String, _ label: String, _ percent: Double?) -> AgentAccount {
        AgentAccount(
            id: id,
            label: label,
            windows: percent.map {
                [AgentWindow(type: "weekly", usedPercent: $0, resetsAt: nil,
                             confidence: "official", source: "test")]
            } ?? [],
            tokensToday: nil
        )
    }

    private func recommend(accounts: [ProviderID: [AgentAccount]]) -> AgentRecommendation? {
        AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 7), util(.codex, 62)],
            displayNames: names,
            accounts: accounts,
            now: now
        )
    }

    func testReasonNamesTheAccountTheHeadlineNumberCameFrom() {
        let reason = recommend(accounts: [.claudeCode: [
            account("/Users/me/.claude", "default", 64),
            account("/Users/me/.claude-account-1", "account-1", 7),
            account("/Users/me/.claude-account-2", "account-2", 41),
        ]])?.reason ?? ""

        XCTAssertTrue(reason.contains("route to Claude Code"), reason)
        XCTAssertTrue(reason.contains("account-1"), "should name the account, got: \(reason)")
        XCTAssertTrue(
            reason.contains("export CLAUDE_CONFIG_DIR=/Users/me/.claude-account-1"),
            "should tell the reader what to export, got: \(reason)"
        )
    }

    /// The named account mirrors `ClaudeCodeProvider.headlineQuotaWindows`: the account
    /// with the most headroom is the one whose windows became the provider headline, so
    /// it is the one that must be named. Accounts with no usable window are skipped
    /// rather than counted as 0%.
    func testAccountWithNoReadingIsNeverNamed() {
        let reason = recommend(accounts: [.claudeCode: [
            account("/Users/me/.claude-broken", "broken", nil),
            account("/Users/me/.claude-account-1", "account-1", 7),
        ]])?.reason ?? ""

        XCTAssertTrue(reason.contains("account-1"), reason)
        XCTAssertFalse(reason.contains("broken"), reason)
    }

    /// Nothing to disambiguate with one account — `CLAUDE_CONFIG_DIR` is just the
    /// default, so the clause would be noise.
    func testSingleAccountIsNotNamed() {
        let reason = recommend(accounts: [.claudeCode: [
            account("/Users/me/.claude", "default", 7),
        ]])?.reason ?? ""

        XCTAssertTrue(reason.contains("route to Claude Code (tightest window 7%)"), reason)
        XCTAssertFalse(reason.contains("CLAUDE_CONFIG_DIR"), reason)
    }

    /// The old three-argument call site must keep working and keep its old output.
    func testReasonIsUnchangedWhenNoAccountsArePassed() {
        let reason = AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 7), util(.codex, 62)],
            displayNames: names,
            now: now
        )?.reason ?? ""
        XCTAssertTrue(reason.contains("route to Claude Code (tightest window 7%)"), reason)
    }

    // MARK: - End to end through the snapshot writer

    /// The account breakdown has to actually reach the engine from the real caller,
    /// not just be reachable in principle.
    func testWriterFeedsAccountsIntoTheRecommendation() {
        let claude = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 7, limit: 100,
                                       confidence: .providerReported, source: "test")],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            accounts: [
                ProviderAccountUsage(
                    id: "/Users/me/.claude", label: "default",
                    quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 64,
                                               limit: 100, confidence: .providerReported,
                                               source: "test")],
                    todayUsage: .unavailable
                ),
                ProviderAccountUsage(
                    id: "/Users/me/.claude-account-1", label: "account-1",
                    quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 7,
                                               limit: 100, confidence: .providerReported,
                                               source: "test")],
                    todayUsage: .unavailable
                ),
            ]
        )
        let codex = ProviderSnapshot(
            providerID: .codex,
            displayName: "OpenAI Codex",
            authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .codex, type: .weekly, used: 62, limit: 100,
                                       confidence: .providerReported, source: "test")],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )

        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [claude, codex], generatedAt: now)
        let reason = snapshot.recommendation?.reason ?? ""
        XCTAssertEqual(snapshot.recommendation?.routeTo, "claude_code")
        XCTAssertTrue(
            reason.contains("export CLAUDE_CONFIG_DIR=/Users/me/.claude-account-1"),
            "writer must pass accounts through, got: \(reason)"
        )
    }
}
