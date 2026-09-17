import XCTest
@testable import AIUsageDashboardCore

final class ClaudeDynamicDiscoveryTests: XCTestCase {
    private var home: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "ClaudeDynamicDiscoveryTests.\(UUID().uuidString)")!
        defaults.set(false, forKey: "claudeNetworkUsageEnabled")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "")
        super.tearDown()
    }

    private func makeAccount(_ name: String, identity: String, tokens: Int) throws {
        let directory = home.appendingPathComponent(name, isDirectory: true)
        let projects = directory.appendingPathComponent("projects/p", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let configURL = name == ".claude"
            ? home.appendingPathComponent(".claude.json")
            : directory.appendingPathComponent(".claude.json")
        try Data(#"{"oauthAccount":{"accountUuid":"\#(identity)"}}"#.utf8).write(to: configURL)
        let line = "{\"type\":\"assistant\",\"timestamp\":\"2026-09-17T02:14:00Z\"," +
            "\"message\":{\"id\":\"\(name)\",\"usage\":{\"input_tokens\":\(tokens)," +
            "\"output_tokens\":0}}}"
        try Data(line.utf8).write(to: projects.appendingPathComponent("session.jsonl"))
    }

    func testA6_refreshAddsRemovesAndReidentifiesClaudeRootsWithoutRecreatingProvider() async throws {
        try makeAccount(".claude", identity: "uuid-a", tokens: 1)
        let provider = ClaudeCodeProvider(
            accounts: [],
            discoveryHome: home,
            userDefaults: defaults
        )

        let first = try await provider.fetchSnapshot()
        try makeAccount(".claude-account-1", identity: "uuid-b", tokens: 2)
        let added = try await provider.fetchSnapshot()
        try FileManager.default.removeItem(at: home.appendingPathComponent(".claude-account-1"))
        let removed = try await provider.fetchSnapshot()
        try Data(#"{"oauthAccount":{"accountUuid":"uuid-c"}}"#.utf8)
            .write(to: home.appendingPathComponent(".claude.json"), options: .atomic)
        let switched = try await provider.fetchSnapshot()

        XCTAssertEqual(first.accounts?.count, 1)
        XCTAssertEqual(added.accounts?.count, 2)
        XCTAssertEqual(removed.accounts?.count, 1)
        XCTAssertNotEqual(first.accounts?.first?.accountID, switched.accounts?.first?.accountID)
    }
}
