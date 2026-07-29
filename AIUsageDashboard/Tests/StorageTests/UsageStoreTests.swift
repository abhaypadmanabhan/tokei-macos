import XCTest
@testable import AIUsageDashboardCore

final class UsageStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeSnapshot(
        providerID: ProviderID = .claudeCode,
        todayInput: Int? = nil,
        lifetimeInput: Int? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: todayInput, confidence: .localParsed),
            weekUsage: TokenUsage(inputTokens: 0, confidence: .localParsed),
            lifetimeUsage: TokenUsage(inputTokens: lifetimeInput, confidence: .localParsed)
        )
    }

    func testRoundTrip() async {
        let store1 = UsageStore(directory: tempDirectory)
        let snapshot = makeSnapshot(
            todayInput: 10,
            lifetimeInput: 1000
        )
        await store1.save(snapshot: snapshot)

        let store2 = UsageStore(directory: tempDirectory)
        let loaded = await store2.snapshot(providerID: .claudeCode)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.providerID, .claudeCode)
        XCTAssertEqual(loaded?.todayUsage.inputTokens, 10)
        XCTAssertEqual(loaded?.lifetimeUsage?.inputTokens, 1000)
    }

    func testRoundTripPreservesHourlyTotals() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let hour = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 10,
            hour: 9
        ))!
        let snapshot = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 42, confidence: .localParsed),
            weekUsage: TokenUsage(inputTokens: 42, confidence: .localParsed),
            hourlyTotals: [hour: 42]
        )

        let store1 = UsageStore(directory: tempDirectory)
        await store1.save(snapshot: snapshot)

        let store2 = UsageStore(directory: tempDirectory)
        let loaded = await store2.snapshot(providerID: .codex)
        XCTAssertEqual(loaded?.hourlyTotals?[hour], 42)
    }

    /// The per-account series must survive persistence, or a dashboard hydrated from disk
    /// would show "no per-account history" until the next live parse.
    func testRoundTripPreservesPerAccountHistory() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 7, day: 10
        ))!
        let snapshot = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 42, confidence: .localParsed),
            weekUsage: TokenUsage(inputTokens: 42, confidence: .localParsed),
            accounts: [
                ProviderAccountUsage(
                    id: "/Users/test/.claude",
                    label: "default",
                    quotaWindows: [],
                    todayUsage: TokenUsage(inputTokens: 42, confidence: .localParsed),
                    dailyTotals: [day: 42],
                    configDirectories: ["/Users/test/.claude", "/Users/test/.claude-account-2"],
                    unreadableDirectories: ["/Users/test/.claude-account-2"]
                )
            ]
        )

        let store1 = UsageStore(directory: tempDirectory)
        await store1.save(snapshot: snapshot)

        let store2 = UsageStore(directory: tempDirectory)
        let account = await store2.snapshot(providerID: .claudeCode)?.accounts?.first
        XCTAssertEqual(account?.dailyTotals?[day], 42)
        XCTAssertEqual(account?.configDirectories.count, 2)
        XCTAssertEqual(account?.unreadableDirectories, ["/Users/test/.claude-account-2"])
    }

    /// An account written before per-account history existed has none of those keys. It must
    /// still decode — the alternative is a user's whole cache being dropped on upgrade.
    func testAnAccountWrittenBeforePerAccountHistoryStillDecodes() throws {
        let legacy = """
        {"id":"/Users/test/.claude","label":"default","quotaWindows":[],\
        "todayUsage":{"inputTokens":42,"confidence":"localParsed"}}
        """

        let account = try JSONDecoder().decode(ProviderAccountUsage.self, from: Data(legacy.utf8))

        XCTAssertEqual(account.label, "default")
        XCTAssertEqual(account.todayUsage.inputTokens, 42)
        XCTAssertNil(account.dailyTotals)
        XCTAssertEqual(account.configDirectories, [])
        XCTAssertEqual(account.unreadableDirectories, [])
    }

    func testCorruptFileRecovery() async {
        let corruptURL = tempDirectory.appendingPathComponent("usage-store.json")
        try? "not valid json".write(to: corruptURL, atomically: true, encoding: .utf8)

        let store = UsageStore(directory: tempDirectory)
        let snapshot = await store.snapshot(providerID: .claudeCode)
        XCTAssertNil(snapshot)
        let all = await store.allSnapshots()
        XCTAssertTrue(all.isEmpty)

        await store.save(snapshot: makeSnapshot(todayInput: 5))

        let recovered = UsageStore(directory: tempDirectory)
        let recoveredSnapshot = await recovered.snapshot(providerID: .claudeCode)
        XCTAssertEqual(recoveredSnapshot?.todayUsage.inputTokens, 5)
    }

    func testMissingFileStartsEmpty() async {
        let store = UsageStore(directory: tempDirectory)
        let snapshot = await store.snapshot(providerID: .claudeCode)
        XCTAssertNil(snapshot)
        let all = await store.allSnapshots()
        XCTAssertTrue(all.isEmpty)
    }

    func testDailyRollupUpsert() async {
        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: makeSnapshot(todayInput: 1000, lifetimeInput: 9999))

        let history1 = await store.dailyHistory(providerID: .claudeCode)
        XCTAssertEqual(history1.count, 1)
        XCTAssertEqual(history1.first?.tokenUsage.inputTokens, 1000)
        XCTAssertEqual(history1.first?.providerID, .claudeCode)

        await store.save(snapshot: makeSnapshot(todayInput: 2000, lifetimeInput: 9999))

        let history2 = await store.dailyHistory(providerID: .claudeCode)
        XCTAssertEqual(history2.count, 1)
        XCTAssertEqual(history2.first?.tokenUsage.inputTokens, 2000)
    }

    func testDailyRollupSkipsUnavailableUsage() async {
        let store = UsageStore(directory: tempDirectory)
        let snapshot = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            authStatus: .unknown,
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
        await store.save(snapshot: snapshot)

        let history = await store.dailyHistory(providerID: .codex)
        XCTAssertTrue(history.isEmpty)
    }

    func testMultipleProvidersIsolated() async {
        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: makeSnapshot(providerID: .claudeCode, todayInput: 100))
        await store.save(snapshot: makeSnapshot(providerID: .codex, todayInput: 200))

        let claudeHistory = await store.dailyHistory(providerID: .claudeCode)
        let codexHistory = await store.dailyHistory(providerID: .codex)
        XCTAssertEqual(claudeHistory.first?.tokenUsage.inputTokens, 100)
        XCTAssertEqual(codexHistory.first?.tokenUsage.inputTokens, 200)
    }

    func testNewStoreFileCreatedWithOwnerOnlyPermissions() async {
        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: makeSnapshot(todayInput: 1))

        let fileURL = tempDirectory.appendingPathComponent("usage-store.json")
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attrs?[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600, "new store file should be readable only by the owner")
    }

    func testExistingStoreFilePermissionsAreNotChanged() async {
        let fileURL = tempDirectory.appendingPathComponent("usage-store.json")
        let existingJSON = "{\"snapshots\":{},\"dailyUsages\":{}}"
        try? existingJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: makeSnapshot(todayInput: 2))

        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attrs?[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o644, "existing store file permissions should not be modified")
    }
}
