import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class CursorProviderTests: XCTestCase {
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

    func testDetectAvailabilityUsesStateDatabasePresenceOnly() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        let provider = CursorProvider(stateDatabaseURL: stateDB)

        var availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .notInstalled)

        try createStateDatabase(at: stateDB, rows: [:])
        availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
    }

    func testFetchSnapshotParsesDatedTokenUsageRows() async throws {
        let clock = fixtureClock()
        let dates = fixtureDates(calendar: clock.calendar, referenceNow: clock.now)
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorUsage.dailyStats.v1.\(dates.today)": CursorFixtures.dailyTokenStats(
                date: dates.today,
                inputTokens: 100,
                outputTokens: 40,
                cacheReadTokens: 10,
                cacheCreationTokens: 5,
                reasoningTokens: 2
            ),
            "cursorUsage.dailyStats.v1.\(dates.week)": CursorFixtures.dailyTokenStats(
                date: dates.week,
                inputTokens: 200,
                outputTokens: 80,
                cacheReadTokens: 20,
                cacheCreationTokens: 10,
                reasoningTokens: 4
            ),
            "cursorUsage.dailyStats.v1.\(dates.outsideWeek)": CursorFixtures.dailyTokenStats(
                date: dates.outsideWeek,
                inputTokens: 300,
                outputTokens: 120,
                cacheReadTokens: 30,
                cacheCreationTokens: 15,
                reasoningTokens: 6
            ),
            "aiCodeTracking.dailyStats.v1.5.\(dates.today)": CursorFixtures.codeLineDailyStats(date: dates.today)
        ])

        let provider = provider(stateDatabaseURL: stateDB, calendar: clock.calendar, now: clock.now)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertEqual(snapshot.authStatus, .unknown)
        XCTAssertEqual(snapshot.todayUsage.inputTokens, 100)
        XCTAssertEqual(snapshot.todayUsage.outputTokens, 40)
        XCTAssertEqual(snapshot.todayUsage.cacheReadTokens, 10)
        XCTAssertEqual(snapshot.todayUsage.cacheCreationTokens, 5)
        XCTAssertEqual(snapshot.todayUsage.reasoningTokens, 2)
        XCTAssertEqual(snapshot.todayUsage.confidence, .localParsed)
        XCTAssertEqual(snapshot.weekUsage.inputTokens, 300)
        XCTAssertEqual(snapshot.weekUsage.outputTokens, 120)
        XCTAssertEqual(snapshot.weekUsage.cacheReadTokens, 30)
        XCTAssertEqual(snapshot.weekUsage.cacheCreationTokens, 15)
        XCTAssertEqual(snapshot.weekUsage.reasoningTokens, 6)
        XCTAssertEqual(snapshot.weekUsage.confidence, .localParsed)
        XCTAssertEqual(snapshot.monthUsage?.totalTokens, 942)
        XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, 942)
        XCTAssertEqual(snapshot.dailyTotals?.values.reduce(0, +), 942)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }

    func testFetchSnapshotReadsFromTempCopyWhenOriginalIsLocked() async throws {
        let clock = fixtureClock()
        let dates = fixtureDates(calendar: clock.calendar, referenceNow: clock.now)
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorUsage.dailyStats.v1.\(dates.today)": CursorFixtures.dailyTokenStats(
                date: dates.today,
                inputTokens: 11,
                outputTokens: 7,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0
            )
        ])
        let originalModifiedAt = try stateDB.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        var lockedDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(stateDB.path, &lockedDatabase, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer {
            sqlite3_exec(lockedDatabase, "ROLLBACK", nil, nil, nil)
            sqlite3_close(lockedDatabase)
        }
        XCTAssertEqual(sqlite3_exec(lockedDatabase, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, nil), SQLITE_OK)

        let provider = provider(stateDatabaseURL: stateDB, calendar: clock.calendar, now: clock.now)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.todayUsage.totalTokens, 18)
        let modifiedAtAfterRead = try stateDB.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        XCTAssertEqual(modifiedAtAfterRead, originalModifiedAt)
    }

    func testFetchSnapshotFallsBackWhenNoTokenMetricsExistLocally() async throws {
        let clock = fixtureClock()
        let dates = fixtureDates(calendar: clock.calendar, referenceNow: clock.now)
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "aiCodeTracking.dailyStats.v1.5.\(dates.today)": CursorFixtures.codeLineDailyStats(date: dates.today)
        ])

        let provider = provider(stateDatabaseURL: stateDB, calendar: clock.calendar, now: clock.now)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertEqual(snapshot.authStatus, .unknown)
        XCTAssertEqual(snapshot.todayUsage.confidence, .unavailable)
        XCTAssertNil(snapshot.todayUsage.totalTokens)
        XCTAssertEqual(snapshot.weekUsage.confidence, .unavailable)
        XCTAssertNil(snapshot.weekUsage.totalTokens)
        XCTAssertNil(snapshot.monthUsage)
        XCTAssertNil(snapshot.lifetimeUsage)
        XCTAssertNil(snapshot.costUsage)
        XCTAssertEqual(snapshot.warnings.count, 1)
        XCTAssertEqual(snapshot.warnings.first?.message, "Cursor token metrics were not found in the local state database")
        XCTAssertEqual(snapshot.warnings.first?.level, .info)
    }

    private func provider(stateDatabaseURL: URL, calendar: Calendar, now: Date) -> CursorProvider {
        CursorProvider(
            stateDatabaseURL: stateDatabaseURL,
            parser: CursorStateDBParser(calendar: calendar, now: { now })
        )
    }

    private func fixtureClock() -> (calendar: Calendar, now: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 12))!
        return (calendar, now)
    }

    private func fixtureDates(
        calendar: Calendar,
        referenceNow: Date
    ) -> (today: String, week: String, outsideWeek: String) {
        let today = calendar.startOfDay(for: referenceNow)
        let week = calendar.date(byAdding: .day, value: -3, to: today)!
        let outsideWeek = calendar.date(byAdding: .day, value: -10, to: today)!
        return (
            today: Self.dayString(today, calendar: calendar),
            week: Self.dayString(week, calendar: calendar),
            outsideWeek: Self.dayString(outsideWeek, calendar: calendar)
        )
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
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
