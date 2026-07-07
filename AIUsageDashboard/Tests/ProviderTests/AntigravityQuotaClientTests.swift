import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class AntigravityQuotaClientTests: XCTestCase {
    private var tempDirectory: URL!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        userDefaults = UserDefaults(suiteName: "com.AIUsageDashboard.AntigravityQuotaClientTests")!
        userDefaults.removeObject(forKey: "antigravityOnlineQuotaEnabled")
    }

    override func tearDown() {
        userDefaults.removeObject(forKey: "antigravityOnlineQuotaEnabled")
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testCapturedQuotaSummaryDecodesFourQuotaWindows() throws {
        let data = AntigravityFixtures.quotaSummaryJSON.data(using: .utf8)!

        let windows = try AntigravityQuotaClientImpl.decodeQuotaWindows(data, providerID: .antigravity)

        XCTAssertEqual(windows.count, 4)
        XCTAssertEqual(Set(windows.map(\.id)).count, 4)

        let byBucket = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.bucketKey.map { ($0, window) }
        })
        XCTAssertEqual(Set(byBucket.keys), Set(["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h"]))

        let geminiWeekly = try XCTUnwrap(byBucket["gemini-weekly"])
        XCTAssertEqual(geminiWeekly.id, "gemini-weekly")
        XCTAssertEqual(geminiWeekly.type, .weekly)
        XCTAssertEqual(geminiWeekly.used, 8)
        XCTAssertEqual(geminiWeekly.limit, 100)
        XCTAssertEqual(geminiWeekly.remaining, 92)
        XCTAssertEqual(geminiWeekly.label, "Gemini Models")
        XCTAssertEqual(geminiWeekly.confidence, .providerReported)
        XCTAssertEqual(geminiWeekly.source, "antigravity-local-rpc")
        XCTAssertEqual(geminiWeekly.resetAt, isoDate("2026-07-11T18:48:56Z"))

        let geminiFiveHour = try XCTUnwrap(byBucket["gemini-5h"])
        XCTAssertEqual(geminiFiveHour.id, "gemini-5h")
        XCTAssertEqual(geminiFiveHour.type, .fiveHour)
        XCTAssertEqual(geminiFiveHour.used, 12)
        XCTAssertEqual(geminiFiveHour.remaining, 88)
        XCTAssertEqual(geminiFiveHour.label, "Gemini Models")
        XCTAssertEqual(geminiFiveHour.resetAt, isoDate("2026-07-07T10:45:03Z"))

        let thirdPartyWeekly = try XCTUnwrap(byBucket["3p-weekly"])
        XCTAssertEqual(thirdPartyWeekly.type, .weekly)
        XCTAssertEqual(thirdPartyWeekly.used, 0)
        XCTAssertEqual(thirdPartyWeekly.remaining, 100)
        XCTAssertEqual(thirdPartyWeekly.label, "Claude and GPT models")

        let thirdPartyFiveHour = try XCTUnwrap(byBucket["3p-5h"])
        XCTAssertEqual(thirdPartyFiveHour.type, .fiveHour)
        XCTAssertEqual(thirdPartyFiveHour.used, 0)
        XCTAssertEqual(thirdPartyFiveHour.remaining, 100)
        XCTAssertEqual(thirdPartyFiveHour.label, "Claude and GPT models")
    }

    func testProviderFallsBackSilentlyWhenOnlineDiscoveryFails() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: fixtureRows())
        userDefaults.set(true, forKey: "antigravityOnlineQuotaEnabled")

        let provider = AntigravityProvider(
            stateDatabaseURL: stateDB,
            quotaClient: NoProcessAntigravityQuotaClient(),
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .antigravity)
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .info && $0.message == "Plan: Pro" })
        XCTAssertFalse(snapshot.warnings.contains { warning in
            warning.message.localizedCaseInsensitiveContains("online")
                || warning.message.localizedCaseInsensitiveContains("failed")
                || warning.message.localizedCaseInsensitiveContains("process")
        })
    }

    private func isoDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private func fixtureRows() -> [String: String] {
        [
            "antigravityAuthStatus": #"{"userStatusProtoBinaryBase64":"\#(AntigravityFixtures.userStatusProtoBase64)"}"#,
            "antigravityUnifiedStateSync.modelCredits": AntigravityFixtures.modelCreditsProtoBase64,
        ]
    }

    private func createStateDatabase(at url: URL, rows: [String: String]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(database) }

        try execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)", database: database)
        for (key, value) in rows {
            try insert(key: key, value: value, database: database)
        }
    }

    private func execute(_ sql: String, database: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(errorMessage)
            throw XCTSkip("SQLite setup failed: \(message)")
        }
    }

    private func insert(key: String, value: String, database: OpaquePointer?) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO ItemTable (key, value) VALUES (?, ?)"
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, value, -1, sqliteTransient)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}

private struct NoProcessAntigravityQuotaClient: AntigravityQuotaClient {
    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        throw AntigravityQuotaError.discoveryUnavailable
    }
}
