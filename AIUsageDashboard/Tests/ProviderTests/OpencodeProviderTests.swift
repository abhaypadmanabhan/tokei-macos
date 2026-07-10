import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let opencodeProviderSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class OpencodeProviderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testDetectAvailabilityAndAuthUseRootAndAuthMarkerOnly() async throws {
        let root = opencodeRoot()
        let provider = OpencodeProvider(opencodeDirectory: root)

        var availability = await provider.detectAvailability()
        var authStatus = try await provider.authenticate()
        XCTAssertEqual(availability, .notInstalled)
        XCTAssertEqual(authStatus, .unauthenticated)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        availability = await provider.detectAvailability()
        authStatus = try await provider.authenticate()
        XCTAssertEqual(availability, .installed)
        XCTAssertEqual(authStatus, .unauthenticated)

        try "{}".write(to: root.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        authStatus = try await provider.authenticate()
        XCTAssertEqual(authStatus, .authenticated)
    }

    func testFetchSnapshotUsesOpencodeStoreAndProviderReportedCost() async throws {
        let root = opencodeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        try createOpencodeDatabase(at: root.appendingPathComponent("opencode.db"), rows: [
            ("msg-today", "session-a", 1_769_071_614_083, OpencodeFixtures.assistantWithCost),
        ])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 1,
            day: 22,
            hour: 12
        ))!
        let parser = OpencodeStoreParser(calendar: calendar, now: { now })
        let provider = OpencodeProvider(parser: parser, opencodeDirectory: root)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .opencode)
        XCTAssertEqual(snapshot.displayName, "opencode")
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 24_463)
        XCTAssertEqual(snapshot.weekUsage.totalTokens, 24_463)
        XCTAssertEqual(snapshot.monthUsage?.totalTokens, 24_463)
        XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, 24_463)
        XCTAssertEqual(snapshot.dailyTotals?.values.reduce(0, +), 24_463)
        XCTAssertEqual(snapshot.hourlyTotals?.values.reduce(0, +), 24_463)
        XCTAssertEqual(snapshot.costUsage?.amount ?? -1, 0.07, accuracy: 0.0001)
        XCTAssertEqual(snapshot.costUsage?.currency, "USD")
        XCTAssertEqual(snapshot.costUsage?.confidence, .providerReported)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }

    func testFetchSnapshotMarksCostUnavailableWhenProviderReportedSumIsZero() async throws {
        let root = opencodeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try createOpencodeDatabase(at: root.appendingPathComponent("opencode.db"), rows: [
            ("msg-zero", "session-a", 1_769_071_614_083, OpencodeFixtures.assistant(
                id: "msg-zero",
                createdMillis: 1_769_071_614_083,
                input: 1,
                output: 2,
                cacheRead: 3,
                cacheWrite: 4,
                cost: 0
            )),
        ])
        let provider = OpencodeProvider(opencodeDirectory: root)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.costUsage?.amount)
        XCTAssertNil(snapshot.costUsage?.currency)
        XCTAssertEqual(snapshot.costUsage?.confidence, .unavailable)
    }

    func testMissingRootDoesNotCrashAndReportsNoLogs() async throws {
        let root = opencodeRoot()
        let provider = OpencodeProvider(opencodeDirectory: root)

        let snapshot = try await provider.fetchSnapshot()
        let availability = await provider.detectAvailability()

        XCTAssertEqual(availability, .notInstalled)
        XCTAssertEqual(snapshot.providerID, .opencode)
        XCTAssertEqual(snapshot.authStatus, .unauthenticated)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 0)
        XCTAssertEqual(snapshot.weekUsage.totalTokens, 0)
        XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, 0)
        XCTAssertEqual(snapshot.costUsage?.confidence, .unavailable)
        XCTAssertTrue(snapshot.warnings.contains {
            $0.level == .info && $0.message == "No opencode messages found"
        })
    }

    func testDefaultRegistryIncludesOpencodeProvider() async {
        let registry = ProviderRegistry.default()
        let ids = await registry.providers.map(\.id)
        XCTAssertTrue(ids.contains(.opencode))
    }

    private func opencodeRoot() -> URL {
        tempDirectory.appendingPathComponent("opencode", isDirectory: true)
    }

    private func createOpencodeDatabase(
        at url: URL,
        rows: [(id: String, sessionID: String, createdMillis: Int64, data: String)]
    ) throws {
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil),
            SQLITE_OK
        )
        defer { sqlite3_close(database) }

        try execute("""
            CREATE TABLE message(
              id TEXT PRIMARY KEY,
              session_id TEXT,
              time_created INT,
              time_updated INT,
              data TEXT
            )
            """, database: database)

        for row in rows {
            try insert(row: row, database: database)
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

    private func insert(
        row: (id: String, sessionID: String, createdMillis: Int64, data: String),
        database: OpaquePointer?
    ) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)"
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, row.id, -1, opencodeProviderSQLiteTransient)
        sqlite3_bind_text(statement, 2, row.sessionID, -1, opencodeProviderSQLiteTransient)
        sqlite3_bind_int64(statement, 3, row.createdMillis)
        sqlite3_bind_int64(statement, 4, row.createdMillis + 1000)
        sqlite3_bind_text(statement, 5, row.data, -1, opencodeProviderSQLiteTransient)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}
