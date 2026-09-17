import XCTest
@testable import AIUsageDashboardCore

final class CodexAccountDiscoveryTests: XCTestCase {
    private var home: URL!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        now = ISO8601DateFormatter().date(from: "2026-09-17T02:16:40Z")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    private func makeRoot(
        _ name: String,
        identity: String?,
        tokens: Int,
        usedPercent: Int,
        timestamp: String = "2026-09-17T02:14:00Z"
    ) throws -> URL {
        let root = home.appendingPathComponent(name, isDirectory: true)
        let sessions = root.appendingPathComponent("sessions/2026/09/17", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let auth = identity.map { #"{"account":{"id":"\#($0)"},"email":"never-export@example.com"}"# }
            ?? "{}"
        try Data(auth.utf8).write(to: root.appendingPathComponent("auth.json"))
        let line = "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{" +
            "\"type\":\"token_count\",\"info\":{\"total_token_usage\":{" +
            "\"input_tokens\":\(tokens),\"total_tokens\":\(tokens)},\"last_token_usage\":{" +
            "\"input_tokens\":\(tokens),\"total_tokens\":\(tokens)}},\"rate_limits\":{" +
            "\"plan_type\":\"pro\",\"primary\":{\"used_percent\":\(usedPercent)," +
            "\"limit_window_seconds\":604800,\"resets_at\":1789698141}}}}"
        try Data(line.utf8).write(to: sessions.appendingPathComponent("session-\(tokens).jsonl"))
        return root
    }

    private func provider(registered: [URL]) -> CodexProvider {
        CodexProvider(
            parser: CodexJSONLParser(calendar: calendar, now: { self.now }),
            homeDirectory: home,
            registeredDirectories: registered,
            environment: [:],
            now: { self.now }
        )
    }

    func testA6_twoCodexIdentitiesKeepSessionsAndRateLimitsSeparate() async throws {
        _ = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let second = try makeRoot("codex-work", identity: "acct-b", tokens: 30, usedPercent: 70)
        let snapshot = try await provider(registered: [second]).fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.count, 2)
        let values = (snapshot.accounts ?? []).map {
            ($0.todayUsage.totalTokens, $0.quotaWindows.first?.used)
        }
        XCTAssertEqual(values.map(\.0), [10, 30])
        XCTAssertEqual(values.map(\.1), [20, 70])
    }

    func testA6_sameCodexIdentityInTwoRootsFoldsAndRetainsBothSessions() async throws {
        _ = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let retired = try makeRoot(
            "codex-retired",
            identity: "acct-a",
            tokens: 30,
            usedPercent: 70,
            timestamp: "2026-09-17T02:15:00Z"
        )
        let snapshot = try await provider(registered: [retired]).fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.count, 1)
        XCTAssertEqual(snapshot.accounts?.first?.todayUsage.totalTokens, 40)
        XCTAssertEqual(snapshot.accounts?.first?.configDirectories.count, 2)
        XCTAssertEqual(snapshot.accounts?.first?.quotaWindows.first?.used, 70)
    }

    func testA6_unknownCodexIdentitiesNeverMerge() async throws {
        _ = try makeRoot(".codex", identity: nil, tokens: 10, usedPercent: 20)
        let second = try makeRoot("codex-work", identity: nil, tokens: 30, usedPercent: 70)
        let snapshot = try await provider(registered: [second]).fetchSnapshot()

        XCTAssertEqual(snapshot.accounts?.count, 2)
        XCTAssertNotEqual(snapshot.accounts?[0].accountID, snapshot.accounts?[1].accountID)
    }

    func testA6_codexDiscoveryChangesWhenRegisteredRootAppearsAndDisappears() async throws {
        _ = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let future = home.appendingPathComponent("codex-future", isDirectory: true)
        let provider = provider(registered: [future])

        let first = try await provider.fetchSnapshot()
        _ = try makeRoot("codex-future", identity: "acct-b", tokens: 30, usedPercent: 70)
        let added = try await provider.fetchSnapshot()
        try FileManager.default.removeItem(at: future)
        let removed = try await provider.fetchSnapshot()

        XCTAssertEqual(first.accounts?.count, 1)
        XCTAssertEqual(added.accounts?.count, 2)
        XCTAssertEqual(removed.accounts?.count, 1)
    }

    func testA6_codexIdentitySwitchInvalidatesMetadataCacheOnRefresh() async throws {
        let root = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let provider = provider(registered: [])
        let first = try await provider.fetchSnapshot()

        try Data(#"{"account":{"id":"acct-c"}}"#.utf8).write(
            to: root.appendingPathComponent("auth.json"),
            options: .atomic
        )
        let switched = try await provider.fetchSnapshot()

        XCTAssertNotEqual(first.accounts?.first?.accountID, switched.accounts?.first?.accountID)
    }

    func testA6_codexParserCacheRetainsOtherRootsBetweenAccountSlices() async throws {
        let firstRoot = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let secondRoot = try makeRoot("codex-work", identity: "acct-b", tokens: 30, usedPercent: 70)
        let parser = CodexJSONLParser(calendar: calendar, now: { self.now })
        let provider = CodexProvider(
            parser: parser,
            homeDirectory: home,
            registeredDirectories: [secondRoot],
            environment: [:],
            now: { self.now }
        )

        _ = try await provider.fetchSnapshot()
        let readsAfterCold = await parser.fileReadCountForTesting()
        _ = try await provider.fetchSnapshot()
        let readsAfterWarm = await parser.fileReadCountForTesting()

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstRoot.path))
        XCTAssertEqual(readsAfterCold, 2)
        XCTAssertEqual(readsAfterWarm, readsAfterCold, "account slices must not evict each other")
    }
}
