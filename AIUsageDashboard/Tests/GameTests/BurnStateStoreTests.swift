import XCTest
@testable import AIUsageDashboardCore

final class BurnStateStoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testRoundTripPrivateModeAndUnchangedBytesDoNotWrite() async throws {
        let store = BurnStateStore(directory: directory)
        var state = BurnState()
        state.initialized = true
        state.longestStreak = 7
        state.badges[BurnBadge.streak7.rawValue] = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await store.save(state)
        XCTAssertTrue(first)
        let file = directory.appendingPathComponent("burn-state.json")
        let before = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((before[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        XCTAssertEqual(raw?["version"] as? Int, 1)
        let second = try await store.save(state)
        XCTAssertFalse(second)
        let after = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(before[.systemFileNumber] as? NSNumber, after[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        let reloaded = await BurnStateStore(directory: directory).load()
        XCTAssertEqual(reloaded, state)
    }

    func testCorruptAndFutureVersionArePreservedThenStartFresh() async throws {
        for bytes in [Data("broken json".utf8), Data("{\"version\":99,\"initialized\":true,\"longestStreak\":2,\"badges\":{},\"records\":{}}".utf8)] {
            let sub = directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let file = sub.appendingPathComponent("burn-state.json")
            try bytes.write(to: file)
            let store = BurnStateStore(directory: sub)
            let state = await store.load()
            XCTAssertEqual(state, BurnState())
            XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("corrupt")), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            try await store.save(state)
            let reloaded = await BurnStateStore(directory: sub).load()
            XCTAssertEqual(reloaded, state)
        }
    }

    func testDoesNotReplaceAnOlderCorruptFile() async throws {
        let file = directory.appendingPathComponent("burn-state.json")
        try Data("first".utf8).write(to: file.appendingPathExtension("corrupt"))
        try Data("second".utf8).write(to: file)
        _ = await BurnStateStore(directory: directory).load()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "corrupt" }.count, 2)
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("corrupt")), Data("first".utf8))
    }

    func testAllQuotaSamplesIncludesBothAccountsInsteadOfOnlyHeadline() async {
        let f = BurnFixtures()
        let window = QuotaWindow(providerID: .codex, type: .fiveHour, used: 90, limit: 100,
                                 resetAt: f.day(-1), confidence: .providerReported, source: "fixture")
        let accounts = ["a", "b"].map {
            ProviderAccountUsage(id: $0, accountID: $0, label: $0, quotaWindows: [window], todayUsage: .unavailable)
        }
        let snapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                        todayUsage: .unavailable, weekUsage: .unavailable, accounts: accounts,
                                        headlineAccountID: "a")
        let store = QuotaSeriesStore(now: { f.day(-1).addingTimeInterval(-60) }, directory: directory)
        await store.append(from: [snapshot])
        let samples = await store.allSamples()
        XCTAssertEqual(Set(samples.compactMap(\.accountID)), ["a", "b"])
        let headline = await store.samples(for: .codex, windowType: .fiveHour)
        XCTAssertEqual(headline.map(\.accountID), ["a"])
    }
}
