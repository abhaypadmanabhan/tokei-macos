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

    /// Writes the config JSON that names a directory's Anthropic identity — inside it
    /// (`CLAUDE_CONFIG_DIR` style) or beside it (`~/.claude.json`, the default account's,
    /// which is why it survives deleting `~/.claude`).
    private func writeIdentity(_ uuid: String, for name: String, inside: Bool) throws {
        let url = inside
            ? home.appendingPathComponent("\(name)/.claude.json")
            : home.appendingPathComponent("\(name).json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(#"{"oauthAccount":{"accountUuid":"\#(uuid)"}}"#.utf8).write(to: url)
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

    /// `discover()` lists `~/.claude` whether or not it exists, so a machine that has never
    /// run Claude Code hits this path on every refresh. A directory that is simply absent
    /// is not a failure worth a user-visible warning — and the warning displaced the
    /// accurate "Local logs only; quotas unavailable" that should be there instead.
    func testAbsentLogDirectoryProducesNoDiscoveryWarning() async throws {
        let missing = ClaudeAccount(
            configDirectory: home.appendingPathComponent(".claude-never-used", isDirectory: true),
            home: home
        )

        let provider = ClaudeCodeProvider(
            accounts: [missing],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertFalse(
            snapshot.warnings.contains { $0.message.contains("Failed to discover Claude logs") },
            "an absent directory is not a discovery failure, got: \(snapshot.warnings.map(\.message))"
        )
        XCTAssertEqual(snapshot.accounts?.first?.unreadableDirectories, [])
    }

    /// The snapshot must say *which* account the headline came from. A surface that wants to
    /// name it (the drill-in's "the gauge is one account — account-1") otherwise has to
    /// re-derive the rule, and a second implementation of "most headroom" is free to disagree
    /// with this one without any test noticing.
    func testHeadlineAccountIDNamesTheAccountTheHeadlineCameFrom() async throws {
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

        let named = (snapshot.accounts ?? []).first { $0.id == snapshot.headlineAccountID }
        XCTAssertEqual(named?.label, "account-1")
        // ...and it is the account those very windows belong to, not just the lowest number.
        XCTAssertEqual(named?.quotaWindows.first { $0.type == .weekly }?.used,
                       snapshot.quotaWindows.first { $0.type == .weekly }?.used)
    }

    /// No usable reading anywhere means there is no headline account to name — the field
    /// must stay `nil` rather than pointing at an account whose gauge says nothing.
    func testHeadlineAccountIDIsNilWithoutAnyUsableReading() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 10)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 10)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.headlineAccountID)
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

    /// The canonical directory of a merged identity is not guaranteed to exist: `discover()`
    /// always manufactures the `~/.claude` entry whether or not that directory is there, and
    /// identifies it from `~/.claude.json`, which lives *outside* `~/.claude` and survives
    /// `rm -rf ~/.claude`. When that identity matches a sibling that does exist, the synthetic
    /// directory wins the canonical pick — and an availability check that looks only at the
    /// canonical reports "not installed" for a machine whose logs this same provider is busy
    /// parsing. Availability is a property of the identity, so every directory it owns counts.
    func testAvailabilityIsInstalledWhenOnlyANonCanonicalDirectoryExists() async throws {
        try makeAccountDirectory(".claude-account-2", outputTokens: 100)
        try writeIdentity("uuid-x", for: ".claude", inside: false)
        try writeIdentity("uuid-x", for: ".claude-account-2", inside: true)

        let accounts = ClaudeAccount.discover(home: home)
        let provider = ClaudeCodeProvider(
            accounts: accounts,
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        XCTAssertEqual(accounts.count, 1, "one identity, two directories")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: accounts[0].configDirectory.path),
            "precondition: the canonical is the synthetic ~/.claude"
        )
        let availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 101, "and the logs really were read")
    }

    /// Live quota used to be fetched from the canonical directory's Keychain item and nowhere
    /// else. The state above needs no credential expiry to lose the reading: the canonical
    /// `~/.claude` does not exist, so `keychainService` resolves to the unsuffixed
    /// `Claude Code-credentials` while the only credentials on the machine belong to the
    /// sibling's suffixed item. Both directories authenticate to the same Anthropic account,
    /// so asking the sibling is the same question, not a different one.
    func testLiveQuotaFallsBackToASiblingWhenTheCanonicalHasNoCredentials() async throws {
        try makeAccountDirectory(".claude-account-2", outputTokens: 10)
        try writeIdentity("uuid-x", for: ".claude", inside: false)
        try writeIdentity("uuid-x", for: ".claude-account-2", inside: true)
        let canonical = MockClaudeUsageClient(behavior: .failure)
        let sibling = MockClaudeUsageClient(behavior: .success([weeklyWindow(used: 42)]))

        let provider = ClaudeCodeProvider(
            accounts: ClaudeAccount.discover(home: home),
            usageClientFactory: { account in
                account.configDirectory.lastPathComponent == ".claude-account-2" ? sibling : canonical
            },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.first?.quotaWindows.first?.used, 42)
        let canonicalCalls = await canonical.callCount()
        let siblingCalls = await sibling.callCount()
        XCTAssertEqual(canonicalCalls, 1, "the canonical is still tried first")
        XCTAssertEqual(siblingCalls, 1, "and the sibling only because it failed")
    }

    // MARK: - Per-account history

    /// The per-account daily series is the whole basis of "which account is spending more
    /// *over time*". It used to be computed and then thrown away in the provider-level merge,
    /// so each account must keep its own copy — and the merged total must still be the sum.
    func testEachAccountKeepsItsOwnDailySeries() async throws {
        let base = try makeAccountDirectory(".claude", outputTokens: 100)
        let one = try makeAccountDirectory(".claude-account-1", outputTokens: 200)

        let provider = ClaudeCodeProvider(
            accounts: [base, one],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        let byLabel = Dictionary(
            uniqueKeysWithValues: (snapshot.accounts ?? []).map { ($0.label, $0) }
        )
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(byLabel["default"]?.dailyTotals?[today], 101)
        XCTAssertEqual(byLabel["account-1"]?.dailyTotals?[today], 201)
        XCTAssertEqual(snapshot.dailyTotals?[today], 302, "the provider-level series is still the merge")
    }

    /// A merged identity's row has to be able to say *which* directories folded into it —
    /// otherwise three config directories listing as two accounts looks like a bug.
    func testAMergedAccountReportsEveryDirectoryItOwns() async throws {
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

        let directories = (snapshot.accounts?.first?.configDirectories ?? [])
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        XCTAssertEqual(directories, [".claude", ".claude-account-2"])
    }

    /// A directory that exists but refuses to be read leaves a hole in the account's totals.
    /// The row has to be able to say so — a confident number that silently omits most of an
    /// identity's usage is exactly the failure this surface is meant to make visible.
    func testAnUnreadableDirectoryIsNamedOnTheAccount() async throws {
        try makeAccountDirectory(".claude", outputTokens: 100)
        try makeAccountDirectory(".claude-account-2", outputTokens: 200)
        let blocked = home.appendingPathComponent(".claude-account-2/projects", isDirectory: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path)
        }
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
        let account = try XCTUnwrap(snapshot.accounts?.first)

        XCTAssertEqual(
            account.unreadableDirectories.map { URL(fileURLWithPath: $0).lastPathComponent },
            [".claude-account-2"]
        )
        XCTAssertEqual(account.todayUsage.totalTokens, 101, "and the readable directory still counts")
    }

    /// Absent is not broken. A directory that has simply never run a session has no `projects`
    /// folder, and marking that as unreadable would put a permanent warning on an ordinary
    /// machine — Tokei tracks eight tools and most of them are idle.
    func testAMissingProjectsDirectoryIsNotReportedAsUnreadable() async throws {
        try makeAccountDirectory(".claude", outputTokens: 100)
        let empty = home.appendingPathComponent(".claude-account-3", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let merged = ClaudeAccount(
            configDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            additionalDirectories: [empty],
            accountUUID: "uuid-a",
            home: home
        )

        let provider = ClaudeCodeProvider(
            accounts: [merged],
            usageClientFactory: { _ in MockClaudeUsageClient(behavior: .failure) },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.first?.unreadableDirectories, [])
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
