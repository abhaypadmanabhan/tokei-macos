import XCTest
@testable import AIUsageDashboardCore

final class QuotaAccountSeriesTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func window(used: Double, reset: TimeInterval) -> QuotaWindow {
        QuotaWindow(providerID: .claudeCode, type: .weekly, used: used, limit: 100,
                    resetAt: now.addingTimeInterval(reset), confidence: .providerReported,
                    source: "fixture", bucketKey: "weekly_all")
    }

    private func snapshot(headline: String, bump: Double = 0) -> ProviderSnapshot {
        let accounts = [
            ProviderAccountUsage(id: "profile-a", accountID: "account-a", label: "A",
                                 quotaWindows: [window(used: 20 + bump, reset: 20_000)], todayUsage: .unavailable),
            ProviderAccountUsage(id: "profile-b", accountID: "account-b", label: "B",
                                 quotaWindows: [window(used: 30 + bump, reset: 10_000)], todayUsage: .unavailable)
        ]
        return ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                quotaWindows: accounts.first { $0.id == headline }!.quotaWindows,
                                todayUsage: .unavailable, weekUsage: .unavailable,
                                accounts: accounts, headlineAccountID: headline)
    }

    func testAccountSwitchReadsOnlyHeadlineHistoryAndPersistsBothAccounts() async throws {
        let store = QuotaSeriesStore(now: { self.now }, directory: directory)
        await store.append(from: [snapshot(headline: "profile-a")])
        await store.append(from: [snapshot(headline: "profile-b", bump: 1)])
        let samples = await store.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(samples.map(\.used), [30, 31])
        let reloaded = QuotaSeriesStore(directory: directory)
        let saved = await reloaded.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(saved.map(\.used), [30, 31])
        await store.append(from: [snapshot(headline: "profile-a", bump: 2)])
        let firstAccount = await store.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(firstAccount.map(\.used), [20, 21, 22])
        for series in [samples, firstAccount] {
            let resets = series.compactMap(\.resetAt)
            XCTAssertEqual(zip(resets, resets.dropFirst()).filter { $0 > $1 }.count, 0)
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("quota-series.json"))
        ) as? [String: Any])
        let rows = try XCTUnwrap(object["samples"] as? [[String: Any]])
        XCTAssertEqual(Set(rows.compactMap { $0["accountID"] as? String }), ["account-a", "account-b"])
        XCTAssertEqual(rows.count, 6)
    }

    func testLegacySamplesNeverBecomeAccountHistory() async {
        let store = QuotaSeriesStore(now: { self.now }, directory: directory)
        let legacy = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                      quotaWindows: [window(used: 99, reset: 50_000)],
                                      todayUsage: .unavailable, weekUsage: .unavailable)
        await store.append(from: [legacy])
        await store.append(from: [snapshot(headline: "profile-a")])
        let rows = await store.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(rows.map(\.used), [20])
    }

    func testSeriesWritesCompactBytesAndSkipsIdenticalSave() async throws {
        let store = QuotaSeriesStore(now: { self.now }, directory: directory)
        let value = snapshot(headline: "profile-a")
        await store.append(from: [value])
        let url = directory.appendingPathComponent("quota-series.json")
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(bytes.contains(10), "JSON should not be pretty printed")
        let marker = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: url.path)
        await store.append(from: [value])
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let date = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(date, marker)
    }

    func testUnchangedReadingRetriesAFailedWrite() async throws {
        let blocked = directory.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let store = QuotaSeriesStore(now: { self.now }, directory: blocked)
        let reading = snapshot(headline: "profile-a")
        await store.append(from: [reading])
        try FileManager.default.removeItem(at: blocked)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        await store.append(from: [reading])
        let reloaded = QuotaSeriesStore(directory: blocked)
        let rows = await reloaded.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(rows.map(\.used), [20])
    }
}
