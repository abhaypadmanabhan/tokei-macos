import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class CursorStateDBParserTests: XCTestCase {
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

    func testParsesMembershipPlanAndAcceptedLines() async throws {
        let db = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: db, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership,
            "cursorAuth/stripeSubscriptionStatus": CursorFixtures.activeStatus,
            "cursorAuth/cachedEmail": CursorFixtures.cachedEmail,
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder,
            CursorFixtures.aiCodeTrackingKey(date: "2026-07-06"): CursorFixtures.acceptedLines(
                date: "2026-07-06", tabAccepted: 3, composerAccepted: 18
            ),
            CursorFixtures.aiCodeTrackingKey(date: "2026-07-05"): CursorFixtures.acceptedLines(
                date: "2026-07-05", tabAccepted: 5, composerAccepted: 10
            )
        ])

        let parser = CursorStateDBParser(calendar: calendar)
        let state = await parser.parse(stateDatabaseURL: db)

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertEqual(state.membershipType, "pro")
        XCTAssertEqual(state.subscriptionStatus, "active")
        XCTAssertEqual(state.email, "user@example.com")
        XCTAssertEqual(state.warnings.count, 1)
        XCTAssertEqual(state.warnings.first?.level, .info)
        XCTAssertEqual(state.warnings.first?.message, "Plan: Pro (active)")

        XCTAssertEqual(state.acceptedLinesByDate.count, 2)
        XCTAssertEqual(state.acceptedLinesByDate[date("2026-07-06")], 21)
        XCTAssertEqual(state.acceptedLinesByDate[date("2026-07-05")], 15)
    }

    func testNoAccessTokenMeansUnauthenticated() async throws {
        let db = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: db, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership
        ])

        let parser = CursorStateDBParser(calendar: calendar)
        let state = await parser.parse(stateDatabaseURL: db)

        XCTAssertFalse(state.isAuthenticated)
        XCTAssertEqual(state.membershipType, "pro")
    }

    func testMissingPlanFieldsProduceNoPlanWarning() async throws {
        let db = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: db, rows: [
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder
        ])

        let parser = CursorStateDBParser(calendar: calendar)
        let state = await parser.parse(stateDatabaseURL: db)

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.warnings.isEmpty)
    }

    func testReadAccessTokenReturnsValueWhenPresent() async throws {
        let db = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: db, rows: [
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder
        ])

        let parser = CursorStateDBParser(calendar: calendar)
        let token = await parser.readAccessToken(stateDatabaseURL: db)
        XCTAssertEqual(token, CursorFixtures.jwtPlaceholder)
    }

    func testReadAccessTokenReturnsNilWhenMissing() async throws {
        let db = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: db, rows: [:])

        let parser = CursorStateDBParser(calendar: calendar)
        let token = await parser.readAccessToken(stateDatabaseURL: db)
        XCTAssertNil(token)
    }

    // MARK: - Helpers

    private func date(_ dayString: String) -> Date {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private func createStateDatabase(at url: URL, rows: [String: String]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil),
            SQLITE_OK
        )
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
