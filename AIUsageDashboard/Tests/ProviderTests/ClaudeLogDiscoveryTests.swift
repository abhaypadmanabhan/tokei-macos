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

    func testEveryAccountFailingThrowsRatherThanReportingNoLogs() async {
        // Neither account has a `projects/` directory — every per-account read fails.
        let accounts = [account(".claude"), account(".claude-account-1")]

        do {
            let sources = try await provider(accounts).discoverLogSources()
            XCTFail("expected a throw, got \(sources.count) sources")
        } catch {
            // Expected: total failure must be distinguishable from "no logs".
        }
    }

    func testConfiguredAccountWithNoSessionsReturnsEmptyWithoutThrowing() async throws {
        let accounts = [try makeAccount(".claude", sessions: [])]

        let sources = try await provider(accounts).discoverLogSources()

        XCTAssertTrue(sources.isEmpty)
    }

    func testPartialFailureStillReturnsTheAccountsThatWorked() async throws {
        // One healthy account, one with no `projects/` directory at all.
        let healthy = try makeAccount(".claude", sessions: ["session-a"])
        let broken = account(".claude-account-1")

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
