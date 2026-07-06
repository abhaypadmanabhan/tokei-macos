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
}
