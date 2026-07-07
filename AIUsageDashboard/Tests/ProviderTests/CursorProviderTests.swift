import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class CursorProviderTests: XCTestCase {
    private var tempDirectory: URL!
    private var calendar: Calendar!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        userDefaults = UserDefaults(suiteName: "com.AIUsageDashboard.CursorProviderTests")!
        userDefaults.removeObject(forKey: "cursorNetworkUsageEnabled")
    }

    override func tearDown() {
        userDefaults.removeObject(forKey: "cursorNetworkUsageEnabled")
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testDetectAvailabilityUsesStateDatabasePresenceOnly() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        let provider = CursorProvider(
            stateDatabaseURL: stateDB,
            parser: CursorStateDBParser(calendar: calendar),
            userDefaults: userDefaults
        )

        var availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .notInstalled)

        try createStateDatabase(at: stateDB, rows: [:])
        availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
    }

    func testAuthenticateReflectsAccessTokenPresence() async throws {
        let dbWithToken = tempDirectory.appendingPathComponent("with-token.vscdb")
        try createStateDatabase(at: dbWithToken, rows: [
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder
        ])
        let providerWithToken = CursorProvider(
            stateDatabaseURL: dbWithToken,
            parser: CursorStateDBParser(calendar: calendar),
            userDefaults: userDefaults
        )
        let status = try await providerWithToken.authenticate()
        XCTAssertEqual(status, .authenticated)

        let dbWithoutToken = tempDirectory.appendingPathComponent("without-token.vscdb")
        try createStateDatabase(at: dbWithoutToken, rows: [:])
        let providerWithoutToken = CursorProvider(
            stateDatabaseURL: dbWithoutToken,
            parser: CursorStateDBParser(calendar: calendar),
            userDefaults: userDefaults
        )
        let noTokenStatus = try await providerWithoutToken.authenticate()
        XCTAssertEqual(noTokenStatus, .unauthenticated)
    }

    func testFlagOffUsesOfflineOnly() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership,
            "cursorAuth/stripeSubscriptionStatus": CursorFixtures.activeStatus,
            CursorFixtures.aiCodeTrackingKey(date: "2026-07-06"): CursorFixtures.acceptedLines(
                date: "2026-07-06", tabAccepted: 3, composerAccepted: 18
            )
        ])

        let provider = CursorProvider(
            stateDatabaseURL: stateDB,
            parser: CursorStateDBParser(calendar: calendar),
            userDefaults: userDefaults
        )

        XCTAssertEqual(provider.capabilities, [.localLog])

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertEqual(snapshot.authStatus, .unauthenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        assertUnavailable(snapshot.todayUsage)
        assertUnavailable(snapshot.weekUsage)
        XCTAssertNil(snapshot.monthUsage)
        XCTAssertNil(snapshot.lifetimeUsage)
        XCTAssertNil(snapshot.costUsage)
        XCTAssertEqual(snapshot.warnings.count, 1)
        XCTAssertEqual(snapshot.warnings.first?.level, .info)
        XCTAssertEqual(snapshot.warnings.first?.message, "Plan: Pro (active)")
        XCTAssertEqual(snapshot.dailyTotals?[date("2026-07-06")], 21)
    }

    func testFlagOnWithMockClientFetchesQuota() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership,
            "cursorAuth/stripeSubscriptionStatus": CursorFixtures.activeStatus,
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder,
            CursorFixtures.aiCodeTrackingKey(date: "2026-07-06"): CursorFixtures.acceptedLines(
                date: "2026-07-06", tabAccepted: 3, composerAccepted: 18
            )
        ])
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let response = CursorUsageResponse(
            quotaWindows: [
                QuotaWindow(
                    providerID: .cursor,
                    type: .monthly,
                    used: 1500,
                    limit: 5000,
                    remaining: 3500,
                    confidence: .providerReported,
                    source: "test"
                )
            ],
            warnings: []
        )
        let mockClient = MockCursorUsageClient(result: .success(response))
        let provider = CursorProvider(
            stateDatabaseURL: stateDB,
            parser: CursorStateDBParser(calendar: calendar),
            usageClient: mockClient,
            userDefaults: userDefaults
        )

        XCTAssertEqual(provider.capabilities, [.localLog, .quota, .tokenUsage, .providerEndpoint])

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.used, 1500)
        XCTAssertEqual(snapshot.quotaWindows.first?.confidence, .providerReported)
        assertUnavailable(snapshot.todayUsage)
        assertUnavailable(snapshot.weekUsage)
        XCTAssertEqual(snapshot.dailyTotals?[date("2026-07-06")], 21)
        XCTAssertEqual(snapshot.warnings.count, 1)
    }

    func testFlagOnWithClientFailureFallsBackToOffline() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership,
            "cursorAuth/stripeSubscriptionStatus": CursorFixtures.activeStatus,
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder,
            CursorFixtures.aiCodeTrackingKey(date: "2026-07-06"): CursorFixtures.acceptedLines(
                date: "2026-07-06", tabAccepted: 1, composerAccepted: 2
            )
        ])
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let mockClient = MockCursorUsageClient(result: .failure(CursorUsageError.httpStatus(500)))
        let provider = CursorProvider(
            stateDatabaseURL: stateDB,
            parser: CursorStateDBParser(calendar: calendar),
            usageClient: mockClient,
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertEqual(snapshot.dailyTotals?[date("2026-07-06")], 3)
        XCTAssertEqual(snapshot.warnings.count, 2)
        XCTAssertEqual(snapshot.warnings.first?.level, .info)
        XCTAssertEqual(snapshot.warnings.last?.level, .warning)
        XCTAssertTrue(snapshot.warnings.last?.message.contains("Falling back") == true)
    }

    func testFlagOnWithoutAccessTokenAddsWarning() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership
        ])
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let provider = CursorProvider(
            stateDatabaseURL: stateDB,
            parser: CursorStateDBParser(calendar: calendar),
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertEqual(snapshot.warnings.count, 2)
        XCTAssertEqual(snapshot.warnings.last?.level, .warning)
        XCTAssertTrue(snapshot.warnings.last?.message.contains("no access token") == true)
    }

    // MARK: - Helpers

    private func date(_ dayString: String) -> Date {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private func assertUnavailable(_ usage: TokenUsage, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(usage.inputTokens, file: file, line: line)
        XCTAssertNil(usage.outputTokens, file: file, line: line)
        XCTAssertNil(usage.cacheReadTokens, file: file, line: line)
        XCTAssertNil(usage.cacheCreationTokens, file: file, line: line)
        XCTAssertNil(usage.reasoningTokens, file: file, line: line)
        XCTAssertEqual(usage.confidence, .unavailable, file: file, line: line)
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

private struct MockCursorUsageClient: CursorUsageClient {
    let result: Result<CursorUsageResponse, Error>

    func fetchUsage(bearerToken: String) async throws -> CursorUsageResponse {
        switch result {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}
