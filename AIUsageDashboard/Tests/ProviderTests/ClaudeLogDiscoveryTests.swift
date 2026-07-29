import XCTest
@testable import AIUsageDashboardCore

/// The `LocalLogProvider.discoverLogSources()` contract for multi-account Claude.
///
/// Handoff P5: after `f725bac` made discovery union across accounts with `try?` per
/// account, a machine where *every* account's log directory was unreadable returned an
/// empty array — indistinguishable from a healthy machine that simply has no sessions yet.
final class ClaudeLogDiscoveryTests: XCTestCase {
    private var home: URL!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        userDefaults = UserDefaults(suiteName: "com.AIUsageDashboard.ClaudeLogDiscoveryTests")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    /// The production state on any machine that never installed Claude Code — which is most
    /// of them, since Tokei tracks eight tools. `ClaudeAccount.discover()` always manufactures
    /// the default `~/.claude` entry whether or not the directory exists, so discovery must
    /// treat that synthetic account as *absent*, not as a broken account.
    func testHomeWithNoClaudeInstallationReturnsEmptyWithoutThrowing() async throws {
        let accounts = ClaudeAccount.discover(home: home)
        XCTAssertEqual(accounts.map(\.label), ["default"], "discovery always yields the synthetic default")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: accounts[0].configDirectory.path),
            "and on this home it does not exist"
        )

        let sources = try await provider(accounts).discoverLogSources()

        XCTAssertTrue(sources.isEmpty)
    }

    func testEveryConfiguredAccountFailingThrowsRatherThanReportingNoLogs() async throws {
        // Both accounts exist, and both have a `projects` that is a regular file rather than a
        // directory — the shape of a genuinely broken install, not an absent one.
        let accounts = [try makeBrokenAccount(".claude"), try makeBrokenAccount(".claude-account-1")]

        do {
            let sources = try await provider(accounts).discoverLogSources()
            XCTFail("expected a throw, got \(sources.count) sources")
        } catch {
            // Expected: total failure must be distinguishable from "no logs".
        }
    }

    func testAbsentAccountsAreNotCountedAsFailures() async throws {
        // Explicitly configured but nonexistent roots. Nothing exists to fail, so this is the
        // same "nothing to read" as an uninstalled Claude — empty, not an error.
        let accounts = [account(".claude"), account(".claude-account-1")]

        let sources = try await provider(accounts).discoverLogSources()

        XCTAssertTrue(sources.isEmpty)
    }

    func testConfiguredAccountWithNoSessionsReturnsEmptyWithoutThrowing() async throws {
        let accounts = [try makeAccount(".claude", sessions: [])]

        let sources = try await provider(accounts).discoverLogSources()

        XCTAssertTrue(sources.isEmpty)
    }

    func testPartialFailureStillReturnsTheAccountsThatWorked() async throws {
        // One healthy account, one that exists but whose `projects` cannot be read.
        let healthy = try makeAccount(".claude", sessions: ["session-a"])
        let broken = try makeBrokenAccount(".claude-account-1")

        let sources = try await provider([healthy, broken]).discoverLogSources()

        XCTAssertEqual(sources.map(\.sessionID), ["session-a"])
    }

    // MARK: - Fixtures

    private func account(_ name: String) -> ClaudeAccount {
        ClaudeAccount(configDirectory: home.appendingPathComponent(name, isDirectory: true), home: home)
    }

    /// Creates `<home>/<name>/projects/proj/<session>.jsonl` for each session id.
    private func makeAccount(_ name: String, sessions: [String]) throws -> ClaudeAccount {
        let directory = home.appendingPathComponent(name, isDirectory: true)
        let projects = directory.appendingPathComponent("projects/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        for session in sessions {
            try Data("{}\n".utf8).write(to: projects.appendingPathComponent("\(session).jsonl"))
        }
        return ClaudeAccount(configDirectory: directory, home: home)
    }

    /// An account that is unmistakably *configured* and unmistakably *broken*: the config
    /// directory exists, but `projects` is a regular file, so enumerating it always fails.
    private func makeBrokenAccount(_ name: String) throws -> ClaudeAccount {
        let directory = home.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: directory.appendingPathComponent("projects"))
        return ClaudeAccount(configDirectory: directory, home: home)
    }

    private func provider(_ accounts: [ClaudeAccount]) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            accounts: accounts,
            usageClientFactory: { _ in UnusedClaudeUsageClient() },
            userDefaults: userDefaults
        )
    }
}

/// Log discovery never touches the network; a call here is a bug in the test.
private struct UnusedClaudeUsageClient: ClaudeUsageClient {
    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        XCTFail("discoverLogSources() must not fetch quota")
        return []
    }
}
