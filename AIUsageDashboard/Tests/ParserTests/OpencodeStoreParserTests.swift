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

    func testBucketsHourlyTotalsWithinFourteenDayWindow() async throws {
        let root = try makeRoot()
        let hour = date("2026-01-22", hour: 5)
        let sameHour = hour.addingTimeInterval(30 * 60)
        let oldHour = date("2026-01-05", hour: 5)
        try createOpencodeDatabase(at: root.appendingPathComponent("opencode.db"), rows: [
            ("recent-a", "session-a", millis(hour), OpencodeFixtures.assistant(
                id: "recent-a", createdMillis: millis(hour), input: 10, output: 0, cacheRead: 0, cacheWrite: 0
            )),
            ("recent-b", "session-a", millis(sameHour), OpencodeFixtures.assistant(
                id: "recent-b", createdMillis: millis(sameHour), input: 20, output: 0, cacheRead: 0, cacheWrite: 0
            )),
            ("old", "session-a", millis(oldHour), OpencodeFixtures.assistant(
                id: "old", createdMillis: millis(oldHour), input: 40, output: 0, cacheRead: 0, cacheWrite: 0
            )),
        ])

        let usage = await makeParser().parse(rootDirectory: root)

        XCTAssertEqual(usage.hourlyTotals?[hour], 30)
        XCTAssertNil(usage.hourlyTotals?[oldHour])
        XCTAssertEqual(usage.hourlyTotals?.values.reduce(0, +), 30)
    }

    func testF2ThirtyUnchangedRefreshesUseOneDatabaseSnapshot() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        try createOpencodeDatabase(at: databaseURL, rows: [
            ("cached", "session-a", 1_769_071_614_083, OpencodeFixtures.assistantWithCost),
        ])
        let fileManager = OpencodeCountingFileManager()
        let parser = makeParser(fileManager: fileManager)

        var last: OpencodeStoreParser.AggregateUsage?
        for _ in 0..<30 {
            last = await parser.parse(rootDirectory: root)
        }

        XCTAssertEqual(last?.lifetime.totalTokens, 24_463)
        XCTAssertEqual(fileManager.opencodeSnapshotCount, 1)
    }

    func testF2WALOnlyCommitInvalidatesCacheAndAppearsInNextAggregate() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        let database = try openWALDatabase(at: databaseURL)
        defer { sqlite3_close(database) }
        try execute("PRAGMA wal_autocheckpoint=0", database: database)
        try execute("""
            CREATE TABLE message(
              id TEXT PRIMARY KEY,
              session_id TEXT,
              time_created INT,
              time_updated INT,
              data TEXT
            )
            """, database: database)
        try insert(
            row: ("base", "session-a", 1_769_071_614_083, OpencodeFixtures.assistant(
                id: "base", createdMillis: 1_769_071_614_083,
                input: 10, output: 5, cacheRead: 0, cacheWrite: 0
            )),
            database: database
        )
        try execute("PRAGMA wal_checkpoint(TRUNCATE)", database: database)

        let parser = makeParser()
        let before = await parser.parse(rootDirectory: root)
        XCTAssertEqual(before.lifetime.totalTokens, 15)

        try insert(
            row: ("wal", "session-a", 1_769_071_615_083, OpencodeFixtures.assistant(
                id: "wal", createdMillis: 1_769_071_615_083,
                input: 20, output: 0, cacheRead: 0, cacheWrite: 0
            )),
            database: database
        )
        let after = await parser.parse(rootDirectory: root)

        XCTAssertEqual(after.lifetime.totalTokens, 35)
    }

    func testF2UnchangedDatabaseRewindowsAtLocalMidnight() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        try createOpencodeDatabase(at: databaseURL, rows: [
            ("today", "session-a", 1_769_071_614_083, OpencodeFixtures.assistant(
                id: "today", createdMillis: 1_769_071_614_083,
                input: 10, output: 5, cacheRead: 0, cacheWrite: 0
            )),
        ])
        let clock = MutableTestDate(date("2026-01-22", hour: 12))
        let fileManager = OpencodeCountingFileManager()
        let parser = makeParser(fileManager: fileManager, now: { clock.value })

        let beforeMidnight = await parser.parse(rootDirectory: root)
        XCTAssertEqual(beforeMidnight.today.totalTokens, 15)

        clock.value = date("2026-01-23", hour: 12)
        let afterMidnight = await parser.parse(rootDirectory: root)

        XCTAssertEqual(afterMidnight.today.totalTokens, 0)
        XCTAssertEqual(afterMidnight.lifetime.totalTokens, 15)
        XCTAssertEqual(fileManager.opencodeSnapshotCount, 2)
    }

    func testR06B01LockedDatabaseAfterMidnightDoesNotServeCachedAggregate() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        let beforeMidnight = date("2026-01-22", hour: 23).addingTimeInterval(59 * 60)
        let committed = OpencodeFixtures.assistant(
            id: "msg", createdMillis: millis(beforeMidnight),
            input: 10, output: 0, cacheRead: 0, cacheWrite: 0
        )
        try createOpencodeDatabase(at: databaseURL, rows: [
            ("msg", "session", millis(beforeMidnight), committed),
        ])

        let clock = MutableTestDate(beforeMidnight)
        let parser = makeParser(now: { clock.value })
        let cached = await parser.parse(rootDirectory: root)
        XCTAssertEqual(cached.today.totalTokens, 10)

        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path, &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
            ),
            SQLITE_OK
        )
        guard let database else { throw XCTSkip("SQLite rollback-journal setup failed") }
        defer {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            sqlite3_close(database)
        }
        try execute("PRAGMA journal_mode=DELETE; PRAGMA cache_size=1", database: database)
        let uncommitted = OpencodeFixtures.assistant(
            id: "msg", createdMillis: millis(beforeMidnight),
            input: 900, output: 0, cacheRead: 0, cacheWrite: 0
        )
        try execute("BEGIN EXCLUSIVE; UPDATE message SET data = '\(uncommitted)' WHERE id = 'msg'", database: database)
        XCTAssertEqual(sqlite3_db_cacheflush(database), SQLITE_OK)

        clock.value = beforeMidnight.addingTimeInterval(2 * 60)
        let afterMidnight = await parser.parse(rootDirectory: root)

        XCTAssertEqual(afterMidnight.sourceKind, .none)
        XCTAssertEqual(afterMidnight.today.totalTokens, 0)
        XCTAssertEqual(afterMidnight.dailyTotals[calendar.startOfDay(for: clock.value)] ?? 0, 0)
        XCTAssertEqual(afterMidnight.lifetime.totalTokens, 0)
        XCTAssertNotEqual(afterMidnight.lifetime.totalTokens, 900)
        XCTAssertEqual(afterMidnight.warnings.count, 1)
    }

    func testR06B01DatabaseSchemaFailureFallsBackToJSONWarmAndCold() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        let created = date("2026-01-22", hour: 11)
        try createOpencodeDatabase(at: databaseURL, rows: [
            ("db-msg", "session", millis(created), OpencodeFixtures.assistant(
                id: "db-msg", createdMillis: millis(created),
                input: 10, output: 0, cacheRead: 0, cacheWrite: 0
            )),
        ])
        let parser = makeParser()
        let cached = await parser.parse(rootDirectory: root)
        XCTAssertEqual(cached.lifetime.totalTokens, 10)

        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path, &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
            ),
            SQLITE_OK
        )
        guard let database else { throw XCTSkip("SQLite schema-failure setup failed") }
        defer { sqlite3_close(database) }
        try execute("DROP TABLE message", database: database)

        let messageDirectory = root.appendingPathComponent("storage/message/session-json", isDirectory: true)
        try FileManager.default.createDirectory(at: messageDirectory, withIntermediateDirectories: true)
        try OpencodeFixtures.assistant(
            id: "json-msg", createdMillis: millis(created),
            input: 77, output: 0, cacheRead: 0, cacheWrite: 0
        ).write(
            to: messageDirectory.appendingPathComponent("json-msg.json"),
            atomically: true,
            encoding: .utf8
        )

        let warm = await parser.parse(rootDirectory: root)
        let cold = await makeParser().parse(rootDirectory: root)

        XCTAssertEqual(warm.sourceKind, .jsonFiles)
        XCTAssertEqual(warm.lifetime.totalTokens, 77)
        XCTAssertEqual(warm.warnings.count, 1)
        XCTAssertEqual(cold.sourceKind, .jsonFiles)
        XCTAssertEqual(cold.lifetime.totalTokens, 77)
        XCTAssertEqual(cold.warnings.count, 1)
    }

    func testR0602RollbackJournalSpillNeverSurfacesUncommittedPages() async throws {
        let root = try makeRoot()
        let databaseURL = root.appendingPathComponent("opencode.db")
        let committed = OpencodeFixtures.assistant(
            id: "msg", createdMillis: 1_789_611_000_000,
            input: 10, output: 0, cacheRead: 0, cacheWrite: 0
        )
        try createOpencodeDatabase(at: databaseURL, rows: [
            ("msg", "session", 1_789_611_000_000, committed)
        ])

        let cachedParser = makeParser()
        let committedUsage = await cachedParser.parse(rootDirectory: root)
        XCTAssertEqual(committedUsage.lifetime.totalTokens, 10)

        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path, &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
            ),
            SQLITE_OK
        )
        guard let database else { throw XCTSkip("SQLite rollback-journal setup failed") }
        defer {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            sqlite3_close(database)
        }
        try execute("PRAGMA journal_mode=DELETE; PRAGMA cache_size=1", database: database)
        let uncommitted = OpencodeFixtures.assistant(
            id: "msg", createdMillis: 1_789_611_000_000,
            input: 900, output: 0, cacheRead: 0, cacheWrite: 0
        )
        try execute("BEGIN EXCLUSIVE; UPDATE message SET data = '\(uncommitted)' WHERE id = 'msg'", database: database)
        XCTAssertEqual(sqlite3_db_cacheflush(database), SQLITE_OK)

        let uncached = await makeParser().parse(rootDirectory: root)
        XCTAssertEqual(uncached.sourceKind, .none)
        XCTAssertEqual(uncached.lifetime.totalTokens, 0)
        XCTAssertEqual(uncached.warnings.count, 1)

        let cached = await cachedParser.parse(rootDirectory: root)
        // R06B-01/F2: failed reads invalidate cache so the warm path matches a cold parser.
        XCTAssertEqual(cached.sourceKind, .none)
        XCTAssertEqual(cached.lifetime.totalTokens, 0)
        XCTAssertNotEqual(cached.lifetime.totalTokens, 900)
        XCTAssertEqual(cached.warnings.count, 1)
    }

    // MARK: - Helpers

    private func makeParser(
        fileManager: FileManager = .default,
        now: (@Sendable () -> Date)? = nil
    ) -> OpencodeStoreParser {
        let fixedNow = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 1,
            day: 22,
            hour: 12
        ))!
        return OpencodeStoreParser(
            fileManager: fileManager,
            calendar: calendar,
            now: now ?? { fixedNow }
        )
    }

    private func openWALDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        XCTAssertEqual(result, SQLITE_OK)
        guard let database else { throw XCTSkip("SQLite WAL setup failed") }
        try execute("PRAGMA journal_mode=WAL", database: database)
        return database
    }

    private func makeRoot() throws -> URL {
        let root = tempDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func date(_ dayString: String) -> Date {
        date(dayString, hour: 0)
    }

    private func date(_ dayString: String, hour: Int) -> Date {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: hour
        ))!
    }

    private func millis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
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

private final class OpencodeCountingFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshotCount = 0

    var opencodeSnapshotCount: Int {
        lock.withLock { snapshotCount }
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if url.lastPathComponent.hasPrefix("TokeiOpencodeStore-") {
            lock.withLock { snapshotCount += 1 }
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}

private final class MutableTestDate: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
