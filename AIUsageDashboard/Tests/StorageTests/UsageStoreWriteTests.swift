import XCTest
@testable import AIUsageDashboardCore

final class UsageStoreWriteTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeSnapshot(todayInput: Int) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: todayInput, confidence: .localParsed), weekUsage: .unavailable
        )
    }

    func testUnchangedSaveDoesNotRewriteEvenWhenSyncTimeChanges() async throws {
        let store = UsageStore(directory: tempDirectory)
        func snapshot(at time: Date) -> ProviderSnapshot {
            ProviderSnapshot(
                providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                todayUsage: .unavailable, weekUsage: .unavailable, lastSyncedAt: time
            )
        }
        await store.save(snapshot: snapshot(at: Date(timeIntervalSince1970: 100)))
        let url = tempDirectory.appendingPathComponent("usage-store.json")
        let marker = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: url.path)
        await store.save(snapshot: snapshot(at: Date(timeIntervalSince1970: 200)))
        let reloaded = UsageStore(directory: tempDirectory)
        await reloaded.save(snapshot: snapshot(at: Date(timeIntervalSince1970: 300)))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, marker)
    }

    func testSavePrunesDailyHistoryTo400CalendarDays() async throws {
        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: makeSnapshot(todayInput: 7))
        let url = tempDirectory.appendingPathComponent("usage-store.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let original = try XCTUnwrap(object["dailyUsages"] as? [Any])
        let key = try XCTUnwrap(original[0] as? [String: Any])
        let value = try XCTUnwrap(original[1] as? [String: Any])
        let today = Calendar.current.startOfDay(for: Date())
        var entries: [Any] = []
        for age in [0, 399, 400, 401] {
            let day = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -age, to: today))
            var datedKey = key
            var datedValue = value
            datedKey["day"] = day.timeIntervalSinceReferenceDate
            datedValue["date"] = day.timeIntervalSinceReferenceDate
            entries.append(contentsOf: [datedKey, datedValue])
        }
        object["dailyUsages"] = entries
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let reloaded = UsageStore(directory: tempDirectory)
        await reloaded.save(snapshots: [])
        let saved = UsageStore(directory: tempDirectory)
        let history = await saved.dailyHistory(providerID: .claudeCode)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.last?.date, today)
    }

    func testLoadHardensExistingSupportFilesWithoutFollowingSymlinks() async throws {
        let unrelated = tempDirectory.appendingPathComponent("agent-snapshot.json")
        try Data("{}".utf8).write(to: unrelated)
        let link = tempDirectory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unrelated.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDirectory.path)
        let store = UsageStore(directory: tempDirectory)
        _ = await store.allSnapshots()
        let directoryMode = try FileManager.default.attributesOfItem(atPath: tempDirectory.path)[.posixPermissions]
        let fileMode = try FileManager.default.attributesOfItem(atPath: unrelated.path)[.posixPermissions]
        XCTAssertEqual((directoryMode as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileMode as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    func testRetentionKeepsLaterDayBucketAfterTimezoneChange() async throws {
        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: makeSnapshot(todayInput: 7))
        let url = tempDirectory.appendingPathComponent("usage-store.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var entries = try XCTUnwrap(object["dailyUsages"] as? [Any])
        var key = try XCTUnwrap(entries[0] as? [String: Any])
        var usage = try XCTUnwrap(entries[1] as? [String: Any])
        let laterBucket = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        key["day"] = laterBucket.timeIntervalSinceReferenceDate
        usage["date"] = laterBucket.timeIntervalSinceReferenceDate
        entries.append(contentsOf: [key, usage])
        object["dailyUsages"] = entries
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let reloaded = UsageStore(directory: tempDirectory)
        await reloaded.save(snapshots: [])
        let saved = UsageStore(directory: tempDirectory)
        let history = await saved.dailyHistory(providerID: .claudeCode)
        XCTAssertEqual(history.count, 2)
        XCTAssertTrue(history.contains { $0.date == laterBucket })
    }

    func testSecureWriterReplacesPrivatelyAndRejectsLinkedDirectory() throws {
        let file = tempDirectory.appendingPathComponent("private.json")
        try Data("old".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try SecureFileWriter.write(Data("new".utf8), to: file)
        XCTAssertEqual(try Data(contentsOf: file), Data("new".utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let link = tempDirectory.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tempDirectory)
        XCTAssertThrowsError(try SecureFileWriter.write(Data(), to: link.appendingPathComponent("other.json")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).sorted(),
                       ["linked", "private.json"])
    }

    func testConstructionHardensFilesBeforeAnyStoreRead() throws {
        let file = tempDirectory.appendingPathComponent("old-cache.json")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        _ = UsageStore(directory: tempDirectory)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testRepeatedObservationDoesNotRewriteButChangedQuotaKeepsFreshObservation() async throws {
        func snapshot(used: Double, observed: TimeInterval) -> ProviderSnapshot {
            ProviderSnapshot(
                providerID: .cursor, displayName: "Cursor", authStatus: .authenticated,
                quotaWindows: [QuotaWindow(providerID: .cursor, type: .monthly, used: used, limit: 100,
                                           confidence: .providerReported, source: "fixture",
                                           observedAt: Date(timeIntervalSince1970: observed))],
                todayUsage: .unavailable, weekUsage: .unavailable
            )
        }
        let store = UsageStore(directory: tempDirectory)
        await store.save(snapshot: snapshot(used: 20, observed: 100))
        let url = tempDirectory.appendingPathComponent("usage-store.json")
        let marker = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: url.path)
        await store.save(snapshot: snapshot(used: 20, observed: 200))
        let unchanged = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(unchanged, marker)
        await store.save(snapshot: snapshot(used: 21, observed: 300))
        let reloaded = UsageStore(directory: tempDirectory)
        let window = await reloaded.snapshot(providerID: .cursor)?.quotaWindows.first
        XCTAssertEqual(window?.used, 21)
        XCTAssertEqual(window?.observedAt, Date(timeIntervalSince1970: 300))
    }
}
