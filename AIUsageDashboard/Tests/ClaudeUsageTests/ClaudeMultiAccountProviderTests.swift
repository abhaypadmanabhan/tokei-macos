import XCTest
@testable import AIUsageDashboardCore

/// `ClaudeCodeProvider` across several `CLAUDE_CONFIG_DIR` accounts.
///
/// Aggregation rules under test, and why each is what it is:
/// - **tokens sum** — "how much work did I do on Claude" spans every account.
/// - **quota takes the account with the most headroom** — work can be sent to whichever
///   account you like, so available capacity is the *best* account's, not the worst's
///   and not an average.
/// - **per-account detail is preserved** — an orchestrator deciding where to fan out
///   needs to know *which* account is open, which an aggregate alone can't say.
final class ClaudeMultiAccountProviderTests: XCTestCase {
    private var home: URL!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        userDefaults = UserDefaults(suiteName: "com.AIUsageDashboard.ClaudeMultiAccountTests")!
        userDefaults.set(true, forKey: "claudeNetworkUsageEnabled")
    }

    override func tearDown() {
        userDefaults.removeObject(forKey: "claudeNetworkUsageEnabled")
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Creates `<home>/<name>/projects/proj/<session>.jsonl` with one assistant record.
    @discardableResult
    private func makeAccountDirectory(_ name: String, outputTokens: Int) throws -> ClaudeAccount {
        let dir = home.appendingPathComponent(name, isDirectory: true)
        let projectDir = dir.appendingPathComponent("projects/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let record = """
        {"type":"assistant","timestamp":"\(ISO8601DateFormatter().string(from: Date()))",\
        "message":{"id":"msg_\(name)","model":"claude-opus-5",\
        "usage":{"input_tokens":1,"output_tokens":\(outputTokens)}}}
        """
        try Data(record.utf8).write(to: projectDir.appendingPathComponent("session.jsonl"))
        return ClaudeAccount(configDirectory: dir, home: home)
    }

    private func weeklyWindow(used: Double) -> QuotaWindow {
        QuotaWindow(
            providerID: .claudeCode,
            type: .weekly,
            used: used,
            limit: 100,
            remaining: 100 - used,
            resetAt: Date().addingTimeInterval(86_400),
            confidence: .providerReported,
            source: "test"
        )
    }

    // MARK: - Tests

    func testEveryConfiguredAccountIsReportedSeparately() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 100)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 200)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { account in
                MockClaudeUsageClient(
                    behavior: .success([self.weeklyWindow(used: account.isDefault ? 90 : 10)])
                )
            },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.map(\.label), ["default", "account-1"])
    }

    func testTokenTotalsSumAcrossAccounts() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 100)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 200)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        // 100 + 200 output tokens, plus 1 input token each.
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 302)
    }

    /// The headline quota must describe the capacity actually available. With one account
    /// at 90% and another at 10%, Claude has room — reporting 90% would wrongly steer work
    /// away, and averaging would describe neither account.
    func testHeadlineQuotaComesFromTheAccountWithTheMostHeadroom() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 10)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 10)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { account in
                MockClaudeUsageClient(
                    behavior: .success([self.weeklyWindow(used: account.isDefault ? 90 : 10)])
                )
            },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotaWindows.first { $0.type == .weekly }?.used, 10)
    }

    /// Per-account windows must survive aggregation — this is the field that tells an
    /// orchestrator *which* account to point `CLAUDE_CONFIG_DIR` at.
    func testPerAccountQuotaIsPreserved() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 10)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 10)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { account in
                MockClaudeUsageClient(
                    behavior: .success([self.weeklyWindow(used: account.isDefault ? 90 : 10)])
                )
            },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        let byLabel = Dictionary(
            uniqueKeysWithValues: (snapshot.accounts ?? []).map { ($0.label, $0) }
        )
        XCTAssertEqual(byLabel["default"]?.quotaWindows.first?.used, 90)
        XCTAssertEqual(byLabel["account-1"]?.quotaWindows.first?.used, 10)
    }

    // MARK: - One identity, several config directories

    /// An identity signed in from two config directories owns the work done in both. The
    /// merged account's total is the sum of its directories' logs — nothing dropped because
    /// only the canonical directory was read, nothing doubled because both were.
    func testMergedAccountTotalsTheLogsOfEveryDirectoryItOwns() async throws {
        try makeAccountDirectory(".claude", outputTokens: 100)
        try makeAccountDirectory(".claude-account-2", outputTokens: 200)
        let merged = ClaudeAccount(
            configDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            additionalDirectories: [home.appendingPathComponent(".claude-account-2", isDirectory: true)],
            accountUUID: "uuid-a",
            home: home
        )

        let provider = ClaudeCodeProvider(
            accounts: [merged],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.count, 1, "one identity is one row")
        // (100 + 1) + (200 + 1), from both directories, under the single merged account.
        XCTAssertEqual(snapshot.accounts?.first?.todayUsage.totalTokens, 302)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 302)
    }

    /// The same records reachable through two directories — a session copied between them —
    /// must be counted once. Both directories are parsed in a single call precisely so the
    /// parser's dedupe can see across them.
    func testRecordsPresentInTwoOfAnAccountsDirectoriesAreCountedOnce() async throws {
        try makeAccountDirectory(".claude", outputTokens: 100)
        // Byte-identical log, same message id: the dedupe key is shared.
        let copy = home.appendingPathComponent(".claude-account-2/projects/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: home.appendingPathComponent(".claude/projects/proj/session.jsonl"),
            to: copy.appendingPathComponent("session.jsonl")
        )
        let merged = ClaudeAccount(
            configDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            additionalDirectories: [home.appendingPathComponent(".claude-account-2", isDirectory: true)],
            accountUUID: "uuid-a",
            home: home
        )

        let provider = ClaudeCodeProvider(
            accounts: [merged],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.todayUsage.totalTokens, 101, "the shared record counts once, not twice")
    }

    /// Only the canonical directory's credentials are fetched: the other directories are the
    /// same Anthropic account, so a second request would ask the same question twice and
    /// return the same shared quota.
    func testMergedAccountFetchesQuotaOncePerIdentity() async throws {
        try makeAccountDirectory(".claude", outputTokens: 10)
        try makeAccountDirectory(".claude-account-2", outputTokens: 10)
        let merged = ClaudeAccount(
            configDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            additionalDirectories: [home.appendingPathComponent(".claude-account-2", isDirectory: true)],
            accountUUID: "uuid-a",
            home: home
        )
        let client = MockClaudeUsageClient(behavior: .success([weeklyWindow(used: 50)]))

        let provider = ClaudeCodeProvider(
            accounts: [merged],
            usageClientFactory: { _ in client },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        let calls = await client.callCount()
        XCTAssertEqual(calls, 1, "two directories, one identity, one request")
        XCTAssertEqual(snapshot.quotaWindows.first { $0.type == .weekly }?.used, 50)
    }

    /// One account failing must not erase the other's reading.
    func testOneAccountFailingLeavesTheOtherReported() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 10)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 10)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { account in
                account.isDefault
                    ? MockClaudeUsageClient(behavior: .failure)
                    : MockClaudeUsageClient(behavior: .success([self.weeklyWindow(used: 42)]))
            },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotaWindows.first { $0.type == .weekly }?.used, 42)
    }
}
