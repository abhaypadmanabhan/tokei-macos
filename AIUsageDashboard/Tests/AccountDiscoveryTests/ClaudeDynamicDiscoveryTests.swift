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
            environment: [:],
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

    func testR09_06_removedRegisteredClaudeRootDisappearsOnRefresh() async throws {
        try makeAccount(".claude", identity: "uuid-a", tokens: 1)
        try makeAccount("registered", identity: "uuid-b", tokens: 2)
        let registered = home.appendingPathComponent("registered", isDirectory: true)
        let provider = ClaudeCodeProvider(
            accounts: [],
            discoveryHome: home,
            registeredDirectories: [registered],
            environment: [:],
            userDefaults: defaults
        )

        let beforeRemoval = try await provider.fetchSnapshot()
        try FileManager.default.removeItem(at: registered)
        let afterRemoval = try await provider.fetchSnapshot()

        XCTAssertEqual(beforeRemoval.accounts?.count, 2)
        XCTAssertEqual(afterRemoval.accounts?.count, 1)
    }

    func testR09_09_explicitInheritedClaudeRootIsTestedWithoutAmbientEnvironment() async throws {
        try makeAccount(".claude", identity: "uuid-a", tokens: 1)
        try makeAccount("inherited", identity: "uuid-b", tokens: 2)
        let inherited = home.appendingPathComponent("inherited", isDirectory: true)
        let provider = ClaudeCodeProvider(
            accounts: [],
            discoveryHome: home,
            environment: ["CLAUDE_CONFIG_DIR": inherited.path],
            userDefaults: defaults
        )

        let inheritedPresent = try await provider.fetchSnapshot()
        try FileManager.default.removeItem(at: inherited)
        let inheritedRemoved = try await provider.fetchSnapshot()

        XCTAssertEqual(inheritedPresent.accounts?.count, 2)
        XCTAssertEqual(inheritedRemoved.accounts?.count, 1)
    }

    func testR1_dynamicAccountOneKeepsThreeOfficialWindowsBesideExpiredDefault() async throws {
        try makeAccount(".claude", identity: "uuid-a", tokens: 1)
        try makeAccount(".claude-account-1", identity: "uuid-b", tokens: 2)
        defaults.set(true, forKey: "claudeNetworkUsageEnabled")
        let observedAt = Date()
        let windows: [QuotaWindow] = [
            (.session, 0, "session"),
            (.weekly, 88, "weekly_all"),
            (.perModel, 86, "weekly_scoped:Fable")
        ].map { type, used, bucketKey in
            QuotaWindow(
                providerID: .claudeCode,
                type: type,
                used: Double(used),
                limit: 100,
                remaining: Double(100 - used),
                resetAt: observedAt.addingTimeInterval(86_400),
                confidence: .providerReported,
                source: "fixture",
                bucketKey: bucketKey,
                observedAt: observedAt
            )
        }
        let provider = ClaudeCodeProvider(
            accounts: [],
            discoveryHome: home,
            environment: [:],
            usageClientFactory: { account in
                if account.isDefault { return R1ExpiredClaudeUsageClient() }
                return MockClaudeUsageClient(behavior: .success(windows))
            },
            userDefaults: defaults
        )

        let snapshot = try await provider.fetchSnapshot()
        let accountOne = try XCTUnwrap(snapshot.accounts?.first { $0.label == "account-1" })

        XCTAssertEqual(accountOne.quotaStatus, .eligible)
        XCTAssertEqual(accountOne.quotaWindows.count, 3)
        XCTAssertTrue(accountOne.quotaWindows.allSatisfy { $0.confidence == .providerReported })
        XCTAssertEqual(snapshot.headlineAccountID, accountOne.id)
    }
}

private struct R1ExpiredClaudeUsageClient: ClaudeUsageClient {
    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        throw ClaudeUsageError.expiredCredentials
    }
}
