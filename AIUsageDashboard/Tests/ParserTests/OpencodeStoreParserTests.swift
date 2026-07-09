import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let opencodeSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class OpencodeStoreParserTests: XCTestCase {
    private var tempDirectory: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testParsesSQLiteFixtureIntoTokenWindowsDailyTotalsAndCost() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        try createOpencodeDatabase(at: databaseURL, rows: [
            ("msg-today", "session-a", 1_769_071_614_083, OpencodeFixtures.assistantWithCost),
            ("msg-week", "session-a", 1_768_812_414_083, OpencodeFixtures.assistantWithoutCost),
            ("msg-user", "session-a", 1_769_071_600_000, OpencodeFixtures.userWithoutTokens),
        ])

        let parser = makeParser()
        let usage = await parser.parse(rootDirectory: root)

        XCTAssertEqual(usage.sourceKind, .sqliteDatabase)
        XCTAssertTrue(usage.warnings.isEmpty)
        XCTAssertEqual(usage.lifetime.inputTokens, 312)
        XCTAssertEqual(usage.lifetime.outputTokens, 63)
        XCTAssertEqual(usage.lifetime.cacheReadTokens, 24_492)
        XCTAssertEqual(usage.lifetime.cacheCreationTokens, 18)
        XCTAssertEqual(usage.lifetime.reasoningTokens, 5)
        XCTAssertEqual(usage.lifetime.totalTokens, 24_890)
        XCTAssertEqual(usage.today.totalTokens, 24_463)
        XCTAssertEqual(usage.week.totalTokens, 24_890)
        XCTAssertEqual(usage.month.totalTokens, 24_890)
        XCTAssertEqual(usage.dailyTotals[date("2026-01-22")], 24_463)
        XCTAssertEqual(usage.dailyTotals[date("2026-01-19")], 427)
        XCTAssertEqual(usage.totalCost, 0.07, accuracy: 0.0001)
    }

    func testParsesJSONFallbackWhenDatabaseHasNoRows() async throws {
        let root = try makeRoot()
        try createOpencodeDatabase(at: root.appendingPathComponent("opencode.db"), rows: [])
        let messageDir = root
            .appendingPathComponent("storage/message/session-json", isDirectory: true)
        try FileManager.default.createDirectory(at: messageDir, withIntermediateDirectories: true)
        try OpencodeFixtures.assistant(
            id: "json-msg",
            createdMillis: 1_769_071_614_083,
            input: 12,
            output: 8,
            cacheRead: 30,
            cacheWrite: 4,
            cost: 0.02
        ).write(to: messageDir.appendingPathComponent("json-msg.json"), atomically: true, encoding: .utf8)

        let usage = await makeParser().parse(rootDirectory: root)

        XCTAssertEqual(usage.sourceKind, .jsonFiles)
        XCTAssertTrue(usage.warnings.isEmpty)
        XCTAssertEqual(usage.lifetime.inputTokens, 12)
        XCTAssertEqual(usage.lifetime.outputTokens, 8)
        XCTAssertEqual(usage.lifetime.cacheReadTokens, 30)
        XCTAssertEqual(usage.lifetime.cacheCreationTokens, 4)
        XCTAssertEqual(usage.lifetime.totalTokens, 54)
        XCTAssertEqual(usage.dailyTotals[date("2026-01-22")], 54)
        XCTAssertEqual(usage.totalCost, 0.02, accuracy: 0.0001)
    }

    func testBothSourcesPreferDatabaseRowsWithoutDoubleCounting() async throws {
        let root = try makeRoot()
        try createOpencodeDatabase(at: root.appendingPathComponent("opencode.db"), rows: [
            ("db-msg", "session-db", 1_769_071_614_083, OpencodeFixtures.assistant(
                id: "db-msg",
                createdMillis: 1_769_071_614_083,
                input: 10,
                output: 5,
                cacheRead: 0,
                cacheWrite: 0
            )),
        ])
        let messageDir = root
            .appendingPathComponent("storage/message/session-json", isDirectory: true)
        try FileManager.default.createDirectory(at: messageDir, withIntermediateDirectories: true)
        try OpencodeFixtures.assistant(
            id: "json-msg",
            createdMillis: 1_769_071_614_083,
            input: 999,
            output: 999,
            cacheRead: 999,
            cacheWrite: 999
        ).write(to: messageDir.appendingPathComponent("json-msg.json"), atomically: true, encoding: .utf8)

        let usage = await makeParser().parse(rootDirectory: root)

        XCTAssertEqual(usage.sourceKind, .sqliteDatabase)
        XCTAssertEqual(usage.lifetime.totalTokens, 15)
        XCTAssertEqual(usage.dailyTotals[date("2026-01-22")], 15)
    }

    func testMissingTokensBlocksAreSkippedWithoutWarnings() async throws {
        let root = try makeRoot()
        try createOpencodeDatabase(at: root.appendingPathComponent("opencode.db"), rows: [
            ("user-msg", "session-a", 1_769_071_600_000, OpencodeFixtures.user(createdMillis: 1_769_071_600_000)),
        ])

        let usage = await makeParser().parse(rootDirectory: root)

        XCTAssertEqual(usage.sourceKind, .sqliteDatabase)
        XCTAssertEqual(usage.lifetime.totalTokens, 0)
        XCTAssertTrue(usage.dailyTotals.isEmpty)
        XCTAssertTrue(usage.warnings.isEmpty)
    }

    // MARK: - Helpers

    private func makeParser() -> OpencodeStoreParser {
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 1,
            day: 22,
            hour: 12
        ))!
        return OpencodeStoreParser(calendar: calendar, now: { now })
    }

    private func makeRoot() throws -> URL {
        let root = tempDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func date(_ dayString: String) -> Date {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
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

        sqlite3_bind_text(statement, 1, row.id, -1, opencodeSQLiteTransient)
        sqlite3_bind_text(statement, 2, row.sessionID, -1, opencodeSQLiteTransient)
        sqlite3_bind_int64(statement, 3, row.createdMillis)
        sqlite3_bind_int64(statement, 4, row.createdMillis + 1000)
        sqlite3_bind_text(statement, 5, row.data, -1, opencodeSQLiteTransient)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}
