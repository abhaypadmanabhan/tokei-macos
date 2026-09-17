import XCTest
@testable import AIUsageDashboardCore

/// A1/A5: the provider publishes the canonical headline account and the recommendation
/// projects that exact identity and selector instead of re-ranking accounts or emitting
/// a shell-shaped `export` recipe.
final class AgentRecommendationAccountTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let names: [ProviderID: String] = [
        .claudeCode: "Claude Code", .codex: "OpenAI Codex"
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
            tokensToday: nil,
            accountID: "claude_code:\(label)",
            selector: AccountSelector(env: ["CLAUDE_CONFIG_DIR": id]),
            quota: AgentAccountQuota(
                status: percent == nil ? "unknown" : "eligible",
                usedPercent: percent,
                headroomPercent: percent.map { 100 - $0 },
                bindingWindowIndex: percent == nil ? nil : 0,
                validUntil: percent == nil ? nil : now.addingTimeInterval(600)
            )
        )
    }

    private func recommend(accounts: [AgentAccount], headlineAccountID: String?) -> AgentRecommendation? {
        AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 7), util(.codex, 62)],
            displayNames: names,
            providers: [AgentProvider(
                id: "claude_code",
                displayName: "Claude Code",
                windows: [],
                tokensToday: nil,
                lastUpdated: nil,
                accounts: accounts,
                headlineAccountID: headlineAccountID
            )],
            now: now
        )
    }

    func testReasonNamesTheAccountTheHeadlineNumberCameFrom() {
        let accounts = [
            account("/Users/me/.claude", "default", 64),
            account("/Users/me/.claude-account-1", "account-1", 7),
            account("/Users/me/.claude-account-2", "account-2", 41)
        ]
        let recommendation = recommend(
            accounts: accounts,
            headlineAccountID: "claude_code:account-1"
        )
        let reason = recommendation?.reason ?? ""

        XCTAssertTrue(reason.contains("route to Claude Code"), reason)
        XCTAssertTrue(reason.contains("account-1"), "should name the account, got: \(reason)")
        XCTAssertFalse(reason.contains("export"), reason)
        XCTAssertEqual(recommendation?.target?.accountID, "claude_code:account-1")
        XCTAssertEqual(
            recommendation?.target?.selector?.env["CLAUDE_CONFIG_DIR"],
            "/Users/me/.claude-account-1"
        )
    }

    /// The named account mirrors `ClaudeCodeProvider.headlineQuotaWindows`: the account
    /// with the most headroom is the one whose windows became the provider headline, so
    /// it is the one that must be named. Accounts with no usable window are skipped
    /// rather than counted as 0%.
    func testAccountWithNoReadingIsNeverNamed() {
        let reason = recommend(accounts: [
            account("/Users/me/.claude-broken", "broken", nil),
            account("/Users/me/.claude-account-1", "account-1", 7)
        ], headlineAccountID: "claude_code:account-1")?.reason ?? ""

        XCTAssertTrue(reason.contains("account-1"), reason)
        XCTAssertFalse(reason.contains("broken"), reason)
    }

    /// Nothing to disambiguate with one account — `CLAUDE_CONFIG_DIR` is just the
    /// default, so the clause would be noise.
    func testSingleAccountIsNotNamed() {
        let reason = recommend(accounts: [
            account("/Users/me/.claude", "default", 7)
        ], headlineAccountID: "claude_code:default")?.reason ?? ""

        XCTAssertTrue(reason.contains("route to Claude Code (tightest window 7%)"), reason)
        XCTAssertFalse(reason.contains("account default"), reason)
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

    private func quotaWindow(
        _ used: Double,
        confidence: MetricConfidence = .providerReported,
        observedAt: Date,
        type: QuotaWindowType = .weekly
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .claudeCode,
            type: type,
            used: used,
            limit: 100,
            confidence: confidence,
            source: "fixture",
            observedAt: observedAt
        )
    }

    private func accountSnapshot(
        firstWindows: [QuotaWindow],
        secondWindows: [QuotaWindow]
    ) -> AgentSnapshot {
        let claude = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            accounts: [
                ProviderAccountUsage(
                    id: "/tmp/a",
                    accountID: "claude_code:a",
                    selector: AccountSelector(env: ["CLAUDE_CONFIG_DIR": "/tmp/a"]),
                    label: "A",
                    quotaWindows: firstWindows,
                    todayUsage: .unavailable,
                    quotaStatus: .eligible
                ),
                ProviderAccountUsage(
                    id: "/tmp/b",
                    accountID: "claude_code:b",
                    selector: AccountSelector(env: ["CLAUDE_CONFIG_DIR": "/tmp/b"]),
                    label: "B",
                    quotaWindows: secondWindows,
                    todayUsage: .unavailable,
                    quotaStatus: .eligible
                )
            ]
        )
        let codex = ProviderSnapshot(
            providerID: .codex,
            displayName: "OpenAI Codex",
            authStatus: .authenticated,
            quotaWindows: [QuotaWindow(
                providerID: .codex,
                type: .weekly,
                used: 70,
                limit: 100,
                confidence: .providerReported,
                source: "fixture",
                observedAt: now
            )],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
        return AgentSnapshotWriter.buildSnapshot(from: [claude, codex], generatedAt: now)
    }

    func testA1_estimatedTenOfficialFiftyCodexSeventyAllIdentifyB() throws {
        let snapshot = accountSnapshot(
            firstWindows: [quotaWindow(10, confidence: .estimated, observedAt: now)],
            secondWindows: [quotaWindow(50, observedAt: now)]
        )
        let claude = try XCTUnwrap(snapshot.providers.first { $0.id == "claude_code" })

        XCTAssertEqual(claude.headlineAccountID, "claude_code:b")
        XCTAssertEqual(claude.windows.first?.usedPercent, 50)
        XCTAssertEqual(snapshot.recommendation?.routeTo, "claude_code")
        XCTAssertEqual(snapshot.recommendation?.target?.accountID, "claude_code:b")
        XCTAssertTrue(snapshot.recommendation?.reason.contains("account B") == true)
        XCTAssertTrue(snapshot.recommendation?.reason.contains("50%") == true)
    }

    func testA2_staleLowAccountDoesNotHideFreshBFromRouting() {
        let snapshot = accountSnapshot(
            firstWindows: [quotaWindow(10, observedAt: now.addingTimeInterval(-1_801))],
            secondWindows: [quotaWindow(50, observedAt: now)]
        )

        XCTAssertEqual(snapshot.recommendation?.routeTo, "claude_code")
        XCTAssertEqual(snapshot.recommendation?.target?.accountID, "claude_code:b")
    }

    func testA2_mixedConfidenceLowAccountDoesNotHideFreshBFromRouting() {
        let snapshot = accountSnapshot(
            firstWindows: [
                quotaWindow(1, observedAt: now, type: .session),
                quotaWindow(10, confidence: .estimated, observedAt: now)
            ],
            secondWindows: [quotaWindow(50, observedAt: now)]
        )

        XCTAssertEqual(snapshot.recommendation?.routeTo, "claude_code")
        XCTAssertEqual(snapshot.recommendation?.target?.accountID, "claude_code:b")
    }

    /// The account breakdown has to actually reach the engine from the real caller,
    /// not just be reachable in principle.
    func testWriterFeedsAccountsIntoTheRecommendation() {
        let observedAt = now
        let claude = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 7, limit: 100,
                                       confidence: .providerReported, source: "test",
                                       observedAt: observedAt)],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            accounts: [
                ProviderAccountUsage(
                    id: "/Users/me/.claude", label: "default",
                    quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 64,
                                               limit: 100, confidence: .providerReported,
                                               source: "test", observedAt: observedAt)],
                    todayUsage: .unavailable,
                    quotaStatus: .eligible
                ),
                ProviderAccountUsage(
                    id: "/Users/me/.claude-account-1",
                    accountID: "claude_code:account-1",
                    selector: AccountSelector(env: [
                        "CLAUDE_CONFIG_DIR": "/Users/me/.claude-account-1"
                    ]),
                    label: "account-1",
                    quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 7,
                                               limit: 100, confidence: .providerReported,
                                               source: "test", observedAt: observedAt)],
                    todayUsage: .unavailable,
                    quotaStatus: .eligible
                )
            ]
        )
        let codex = ProviderSnapshot(
            providerID: .codex,
            displayName: "OpenAI Codex",
            authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .codex, type: .weekly, used: 62, limit: 100,
                                       confidence: .providerReported, source: "test",
                                       observedAt: observedAt)],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )

        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [claude, codex], generatedAt: now)
        let reason = snapshot.recommendation?.reason ?? ""
        XCTAssertEqual(snapshot.recommendation?.routeTo, "claude_code")
        XCTAssertTrue(reason.contains("account account-1"), reason)
        XCTAssertFalse(reason.contains("export"), reason)
        XCTAssertEqual(snapshot.recommendation?.target?.accountID, "claude_code:account-1")
    }
}
