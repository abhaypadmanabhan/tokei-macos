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

    private func snapshot(headline: String) -> ProviderSnapshot {
        let accounts = [
            ProviderAccountUsage(id: "profile-a", accountID: "account-a", label: "A",
                                 quotaWindows: [window(used: 20, reset: 20_000)], todayUsage: .unavailable),
            ProviderAccountUsage(id: "profile-b", accountID: "account-b", label: "B",
                                 quotaWindows: [window(used: 30, reset: 10_000)], todayUsage: .unavailable)
        ]
        return ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                quotaWindows: accounts.first { $0.id == headline }!.quotaWindows,
                                todayUsage: .unavailable, weekUsage: .unavailable,
                                accounts: accounts, headlineAccountID: headline)
    }

    func testAccountSwitchReadsOnlyHeadlineHistoryAndPersistsBothAccounts() async throws {
        let store = QuotaSeriesStore(now: { self.now }, directory: directory)
        await store.append(from: [snapshot(headline: "profile-a")])
        await store.append(from: [snapshot(headline: "profile-b")])
        let samples = await store.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(samples.map(\.used), [30])
        let reloaded = QuotaSeriesStore(directory: directory)
        let saved = await reloaded.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(saved.map(\.used), [30])
        await store.append(from: [snapshot(headline: "profile-a")])
        let firstAccount = await store.samples(for: .claudeCode, windowType: .weekly)
        XCTAssertEqual(firstAccount.map(\.used), [20])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("quota-series.json"))
        ) as? [String: Any])
        let rows = try XCTUnwrap(object["samples"] as? [[String: Any]])
        XCTAssertEqual(Set(rows.compactMap { $0["accountID"] as? String }), ["account-a", "account-b"])
        XCTAssertEqual(rows.count, 2)
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
}
