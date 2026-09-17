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
        let auth = identity.map { #"{"tokens":{"account_id":"\#($0)"},"email":"never-export@example.com"}"# }
            ?? "{}"
        try Data(auth.utf8).write(to: root.appendingPathComponent("auth.json"))
        let line = codexEventLine(
            totalTokens: tokens,
            lastTokens: tokens,
            usedPercent: usedPercent,
            timestamp: timestamp
        )
        try Data(line.utf8).write(to: sessions.appendingPathComponent("session-\(tokens).jsonl"))
        return root
    }

    private func codexEventLine(
        totalTokens: Int,
        lastTokens: Int,
        usedPercent: Int,
        timestamp: String
    ) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{" +
            "\"type\":\"token_count\",\"info\":{\"total_token_usage\":{" +
            "\"input_tokens\":\(totalTokens),\"total_tokens\":\(totalTokens)},\"last_token_usage\":{" +
            "\"input_tokens\":\(lastTokens),\"total_tokens\":\(lastTokens)}},\"rate_limits\":{" +
            "\"plan_type\":\"pro\",\"primary\":{\"used_percent\":\(usedPercent)," +
            "\"limit_window_seconds\":604800,\"resets_at\":1789698141}}}}"
    }

    private func setIdentity(_ identity: String, for root: URL) throws {
        try Data(#"{"tokens":{"account_id":"\#(identity)"}}"#.utf8).write(
            to: root.appendingPathComponent("auth.json"),
            options: .atomic
        )
    }

    private func appendEvent(
        to root: URL,
        totalTokens: Int,
        lastTokens: Int,
        usedPercent: Int,
        timestamp: String
    ) throws {
        let file = root.appendingPathComponent("sessions/2026/09/17/session-10.jsonl")
        var data = try Data(contentsOf: file)
        data.append(0x0A)
        data.append(Data(codexEventLine(
            totalTokens: totalTokens,
            lastTokens: lastTokens,
            usedPercent: usedPercent,
            timestamp: timestamp
        ).utf8))
        try data.write(to: file, options: .atomic)
    }

    private func accountTokenSum(_ snapshot: ProviderSnapshot) -> Int {
        (snapshot.accounts ?? []).reduce(0) { $0 + ($1.todayUsage.totalTokens ?? 0) }
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

    func testR09_01_authenticTokensAccountIDInTwoRootsFoldsAndRetainsBothSessions() async throws {
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

    func testR09_02_emptyCodexIdentitiesNeverMergeOnWarmDiscovery() async throws {
        _ = try makeRoot(".codex", identity: "", tokens: 10, usedPercent: 20)
        let second = try makeRoot("codex-work", identity: "", tokens: 30, usedPercent: 70)
        let provider = provider(registered: [second])

        let cold = try await provider.fetchSnapshot()
        let warm = try await provider.fetchSnapshot()

        XCTAssertEqual(cold.accounts?.count, 2)
        XCTAssertEqual(warm.accounts?.count, 2)
        XCTAssertEqual(Set((warm.accounts ?? []).compactMap(\.accountID)).count, 2)
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

    func testR09_01_authenticTokensAccountIDChangeChangesStableAccountID() async throws {
        let root = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let provider = provider(registered: [])
        let first = try await provider.fetchSnapshot()

        try Data(#"{"tokens":{"account_id":"acct-c"}}"#.utf8).write(
            to: root.appendingPathComponent("auth.json"),
            options: .atomic
        )
        let switched = try await provider.fetchSnapshot()

        XCTAssertNotEqual(first.accounts?.first?.accountID, switched.accounts?.first?.accountID)
    }

    func testR09_07_reauthenticationRequiresNewQuotaObservationAndKeepsHistoricalTokens() async throws {
        let root = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let provider = provider(registered: [])
        let first = try await provider.fetchSnapshot()
        let oldAccountID = try XCTUnwrap(first.accounts?.first?.accountID)

        try setIdentity("acct-new-a", for: root)
        let switched = try await provider.fetchSnapshot()
        let newAccount = try XCTUnwrap(switched.accounts?.first { $0.accountID != oldAccountID })
        let oldAccount = try XCTUnwrap(switched.accounts?.first { $0.accountID == oldAccountID })
        let switchedDecision = AccountQuotaDecision.evaluate(
            newAccount,
            providerID: .codex,
            now: now
        )

        XCTAssertEqual(newAccount.quotaStatus, .unknown)
        XCTAssertNil(switchedDecision.headroomPercent)
        XCTAssertEqual(newAccount.todayUsage.totalTokens, 0)
        XCTAssertEqual(oldAccount.todayUsage.totalTokens, 10)

        _ = try makeRoot(
            ".codex",
            identity: "acct-new-a",
            tokens: 20,
            usedPercent: 35,
            timestamp: "2026-09-17T02:17:00Z"
        )
        now = ISO8601DateFormatter().date(from: "2026-09-17T02:17:00Z")!
        let refreshed = try await provider.fetchSnapshot()
        let refreshedNewAccount = try XCTUnwrap(
            refreshed.accounts?.first { $0.accountID == newAccount.accountID }
        )
        let refreshedDecision = AccountQuotaDecision.evaluate(
            refreshedNewAccount,
            providerID: .codex,
            now: now
        )

        XCTAssertEqual(refreshedNewAccount.quotaStatus, .eligible)
        XCTAssertTrue(refreshedDecision.isEligible)
        XCTAssertEqual(refreshedNewAccount.quotaWindows.first?.used, 35)
    }
}

extension CodexAccountDiscoveryTests {
    func testR09_07_transitionObservationRejectsOldIdentityEventBeforeReauth() async throws {
        now = ISO8601DateFormatter().date(from: "2026-09-17T02:14:00Z")!
        let root = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let provider = provider(registered: [])
        let first = try await provider.fetchSnapshot()
        let oldAccountID = try XCTUnwrap(first.accounts?.first?.accountID)

        try appendEvent(
            to: root,
            totalTokens: 20,
            lastTokens: 10,
            usedPercent: 5,
            timestamp: "2026-09-17T02:15:00Z"
        )
        try setIdentity("acct-b", for: root)
        now = ISO8601DateFormatter().date(from: "2026-09-17T02:16:40Z")!

        let switched = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(switched.accounts?.first { $0.accountID != oldAccountID })
        let quarantined = AccountQuotaDecision.evaluate(accountB, providerID: .codex, now: now)
        XCTAssertEqual(accountB.quotaStatus, .unknown)
        XCTAssertNil(quarantined.headroomPercent)

        try appendEvent(
            to: root,
            totalTokens: 30,
            lastTokens: 10,
            usedPercent: 35,
            timestamp: "2026-09-17T02:17:00Z"
        )
        now = ISO8601DateFormatter().date(from: "2026-09-17T02:17:00Z")!

        let refreshed = try await provider.fetchSnapshot()
        let refreshedB = try XCTUnwrap(
            refreshed.accounts?.first { $0.accountID == accountB.accountID }
        )
        let eligible = AccountQuotaDecision.evaluate(refreshedB, providerID: .codex, now: now)
        XCTAssertEqual(refreshedB.quotaStatus, .eligible)
        XCTAssertTrue(eligible.isEligible)
        XCTAssertEqual(eligible.headroomPercent, 65)
    }

    func testR09B_01_identityEpochsConserveTokensAcrossAtoBtoCWithoutNewUsage() async throws {
        let root = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let provider = provider(registered: [])

        let first = try await provider.fetchSnapshot()
        try setIdentity("acct-b", for: root)
        let second = try await provider.fetchSnapshot()
        try setIdentity("acct-c", for: root)
        let third = try await provider.fetchSnapshot()

        for snapshot in [first, second, third] {
            XCTAssertEqual(snapshot.todayUsage.totalTokens, 10)
            XCTAssertEqual(accountTokenSum(snapshot), 10)
        }
    }

    func testR09B_01_identityEpochsConserveTokensWhenSharedRootSplits() async throws {
        let firstRoot = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let secondRoot = try makeRoot("codex-work", identity: "acct-a", tokens: 30, usedPercent: 70)
        let provider = provider(registered: [secondRoot])

        let shared = try await provider.fetchSnapshot()
        let accountA = try XCTUnwrap(shared.accounts?.first?.accountID)
        try setIdentity("acct-b", for: firstRoot)
        let split = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(split.accounts?.first { $0.accountID != accountA }?.accountID)

        XCTAssertEqual(shared.todayUsage.totalTokens, 40)
        XCTAssertEqual(accountTokenSum(shared), 40)
        XCTAssertEqual(split.todayUsage.totalTokens, 40)
        XCTAssertEqual(accountTokenSum(split), 40)
        XCTAssertEqual(split.accounts?.first { $0.accountID == accountA }?.todayUsage.totalTokens, 40)
        XCTAssertEqual(split.accounts?.first { $0.accountID == accountB }?.todayUsage.totalTokens, 0)

        try appendEvent(
            to: firstRoot,
            totalTokens: 20,
            lastTokens: 10,
            usedPercent: 35,
            timestamp: "2026-09-17T02:17:00Z"
        )
        let grown = try await provider.fetchSnapshot()
        XCTAssertEqual(grown.todayUsage.totalTokens, 50)
        XCTAssertEqual(accountTokenSum(grown), 50)
        XCTAssertEqual(grown.accounts?.first { $0.accountID == accountA }?.todayUsage.totalTokens, 40)
        XCTAssertEqual(grown.accounts?.first { $0.accountID == accountB }?.todayUsage.totalTokens, 10)
    }

    func testR09B_01_identityEpochsDeriveTodayFromDatedRawTotalsAfterRollover() async throws {
        let root = try makeRoot(".codex", identity: "acct-a", tokens: 10, usedPercent: 20)
        let provider = provider(registered: [])
        let first = try await provider.fetchSnapshot()
        let accountA = try XCTUnwrap(first.accounts?.first?.accountID)

        try setIdentity("acct-b", for: root)
        let switched = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(switched.accounts?.first { $0.accountID != accountA }?.accountID)
        now = ISO8601DateFormatter().date(from: "2026-09-18T02:16:40Z")!
        try appendEvent(
            to: root,
            totalTokens: 15,
            lastTokens: 5,
            usedPercent: 35,
            timestamp: "2026-09-18T02:15:00Z"
        )

        let nextDay = try await provider.fetchSnapshot()
        XCTAssertEqual(nextDay.todayUsage.totalTokens, 5)
        XCTAssertEqual(accountTokenSum(nextDay), 5)
        XCTAssertEqual(nextDay.accounts?.first { $0.accountID == accountA }?.todayUsage.totalTokens, 0)
        XCTAssertEqual(nextDay.accounts?.first { $0.accountID == accountB }?.todayUsage.totalTokens, 5)
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
