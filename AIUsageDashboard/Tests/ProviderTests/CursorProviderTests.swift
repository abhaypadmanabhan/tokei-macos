import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class CursorProviderTests: XCTestCase {
    private var tempDirectory: URL!
    private var calendar: Calendar!
    private var userDefaults: UserDefaults!

    /// Fixed "now" so the CSV fixture's dates fall into deterministic windows:
    /// today = 2026-07-08, weekStart = 2026-07-02, monthStart = 2026-06-08.
    private var referenceNow: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

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
        let provider = makeProvider(stateDB: stateDB)

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
        let status = try await makeProvider(stateDB: dbWithToken).authenticate()
        XCTAssertEqual(status, .authenticated)

        let dbWithoutToken = tempDirectory.appendingPathComponent("without-token.vscdb")
        try createStateDatabase(at: dbWithoutToken, rows: [:])
        let noTokenStatus = try await makeProvider(stateDB: dbWithoutToken).authenticate()
        XCTAssertEqual(noTokenStatus, .unauthenticated)
    }

    func testD11FlagOffKeepsAcceptedLinesOutOfTokenHistory() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 3, composerAccepted: 18))

        let provider = makeProvider(stateDB: stateDB)
        XCTAssertEqual(provider.capabilities, [.localLog])

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        assertUnavailable(snapshot.todayUsage)
        assertUnavailable(snapshot.weekUsage)
        XCTAssertNil(snapshot.monthUsage)
        XCTAssertNil(snapshot.costUsage)
        XCTAssertEqual(snapshot.warnings.map(\.message), ["Plan: Pro (active)"])
        // D11: accepted code lines are not tokens and must never enter token history.
        XCTAssertNil(snapshot.dailyTotals)
        XCTAssertNil(snapshot.hourlyTotals)
    }

    func testA3FlagOnFetchesTokensQuotaAndCostAtSuccessfulResponseTime() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 3, composerAccepted: 18))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let client = MockCursorUsageClient(
            csv: .success(CursorFixtures.usageEventsCSV),
            summary: .success(Data(CursorFixtures.usageSummary.utf8))
        )
        let provider = makeProvider(stateDB: stateDB, client: client)
        XCTAssertEqual(provider.capabilities, [.localLog, .quota, .tokenUsage, .providerEndpoint])

        let snapshot = try await provider.fetchSnapshot()

        // Today = the single 2026-07-08 event (the all-zero errored row is dropped).
        XCTAssertEqual(snapshot.todayUsage.confidence, .providerReported)
        XCTAssertEqual(snapshot.todayUsage.inputTokens, 1000)
        XCTAssertEqual(snapshot.todayUsage.cacheCreationTokens, 200)
        XCTAssertEqual(snapshot.todayUsage.cacheReadTokens, 500)
        XCTAssertEqual(snapshot.todayUsage.outputTokens, 300)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 2000)

        XCTAssertEqual(snapshot.weekUsage.totalTokens, 2900)  // 07-08 + 07-04
        XCTAssertEqual(snapshot.monthUsage?.totalTokens, 3400) // + 06-20
        XCTAssertNil(snapshot.lifetimeUsage)

        // Real token daily totals supersede the offline code-line stats.
        XCTAssertEqual(snapshot.dailyTotals?[day("2026-07-08")], 2000)
        XCTAssertNil(snapshot.dailyTotals?[day("2026-07-06")])
        XCTAssertEqual(snapshot.hourlyTotals?[date("2026-07-08", hour: 9)], 2000)
        XCTAssertEqual(snapshot.hourlyTotals?[date("2026-07-04", hour: 10)], 900)
        XCTAssertNil(snapshot.hourlyTotals?[date("2026-06-20", hour: 12)])

        XCTAssertEqual(snapshot.costUsage?.amount ?? 0, 1234.62, accuracy: 0.01)
        XCTAssertEqual(snapshot.costUsage?.currency, "USD")

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let quota = snapshot.quotaWindows[0]
        XCTAssertEqual(quota.type, .monthly)
        XCTAssertEqual(quota.used, 42.5)
        XCTAssertEqual(quota.limit, 100)
        XCTAssertEqual(quota.confidence, .providerReported)
        XCTAssertEqual(quota.label, "Pro (active)")
        XCTAssertNotNil(quota.resetAt)
        // A3: provider quota freshness is the successful response time.
        XCTAssertEqual(quota.observedAt, referenceNow)
    }

    func testFlagOnKeepsTokensWhenSummaryFails() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 3, composerAccepted: 18))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        // CSV succeeds, summary fails → tokens still land, just no quota gauge.
        let client = MockCursorUsageClient(
            csv: .success(CursorFixtures.usageEventsCSV),
            summary: .failure(CursorUsageError.httpStatus(500))
        )
        let snapshot = try await makeProvider(stateDB: stateDB, client: client).fetchSnapshot()

        XCTAssertEqual(snapshot.todayUsage.totalTokens, 2000)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testD11FlagOnFailureDoesNotRelabelAcceptedLinesAsTokens() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 1, composerAccepted: 2))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let client = MockCursorUsageClient(csv: .failure(CursorUsageError.httpStatus(500)))
        let snapshot = try await makeProvider(stateDB: stateDB, client: client).fetchSnapshot()

        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        assertUnavailable(snapshot.todayUsage)
        // D11: an online failure leaves token history unavailable, not code-line totals.
        XCTAssertNil(snapshot.dailyTotals)
        XCTAssertEqual(snapshot.warnings.last?.level, .warning)
        XCTAssertTrue(snapshot.warnings.last?.message.contains("Falling back") == true)
    }

    func testD11EmptyOnlineCSVProducesEmptyTokenHistory() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 100, composerAccepted: 23))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")
        let client = MockCursorUsageClient(
            csv: .success("Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output,Total Tokens,Cost\n"),
            summary: .success(Data(CursorFixtures.usageSummary.utf8))
        )

        let snapshot = try await makeProvider(stateDB: stateDB, client: client).fetchSnapshot()

        XCTAssertNil(snapshot.dailyTotals)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 0)
    }

    func testF5CursorFetchUsesOneTemporaryDatabaseSnapshotAndCleansItUp() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 1, composerAccepted: 2))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")
        let fileManager = CountingFileManager()
        let client = MockCursorUsageClient(
            csv: .success(CursorFixtures.usageEventsCSV),
            summary: .success(Data(CursorFixtures.usageSummary.utf8))
        )

        _ = try await makeProvider(
            stateDB: stateDB,
            client: client,
            fileManager: fileManager
        ).fetchSnapshot()

        XCTAssertEqual(fileManager.cursorSnapshotDirectories.count, 1)
        XCTAssertTrue(fileManager.cursorSnapshotDirectories.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testFlagOnWithUnresolvableSessionAddsWarning() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership,
            "cursorAuth/accessToken": CursorFixtures.jwt(sub: "1234567890") // no normalizable id
        ])
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let snapshot = try await makeProvider(stateDB: stateDB).fetchSnapshot()

        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertEqual(snapshot.warnings.last?.level, .warning)
        XCTAssertTrue(snapshot.warnings.last?.message.contains("no Cursor session") == true)
    }

    // MARK: - Helpers

    private func makeProvider(
        stateDB: URL,
        client: CursorUsageClient? = nil,
        fileManager: FileManager = .default
    ) -> CursorProvider {
        let fixedNow = referenceNow
        return CursorProvider(
            fileManager: fileManager,
            stateDatabaseURL: stateDB,
            parser: CursorStateDBParser(fileManager: fileManager, calendar: calendar),
            usageClient: client,
            calendar: calendar,
            now: { fixedNow },
            userDefaults: userDefaults
        )
    }

    private func offlineRows(tabAccepted: Int, composerAccepted: Int) -> [String: String] {
        [
            "cursorAuth/stripeMembershipType": CursorFixtures.proMembership,
            "cursorAuth/stripeSubscriptionStatus": CursorFixtures.activeStatus,
            "cursorAuth/accessToken": CursorFixtures.jwtPlaceholder,
            CursorFixtures.aiCodeTrackingKey(date: "2026-07-06"): CursorFixtures.acceptedLines(
                date: "2026-07-06", tabAccepted: tabAccepted, composerAccepted: composerAccepted
            )
        ]
    }

    private func day(_ dayString: String) -> Date {
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

    private func assertUnavailable(_ usage: TokenUsage, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(usage.inputTokens, file: file, line: line)
        XCTAssertNil(usage.outputTokens, file: file, line: line)
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

extension CursorProviderTests {
    func testR0603CursorObservedAtUsesQuotaResponseTimeWhenCSVCompletesLater() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 0, composerAccepted: 0))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")
        let clock = AdvancingCursorClock(referenceNow)
        let client = DelayedCursorCSVClient(clock: clock)
        let provider = CursorProvider(
            stateDatabaseURL: stateDB,
            usageClient: client,
            calendar: calendar,
            now: { clock.value },
            userDefaults: userDefaults
        )

        let snapshot = try await provider.fetchSnapshot()
        let quota = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(quota.observedAt, referenceNow)
        let utilization = Utilization(
            providerID: .cursor,
            window: quota.type,
            usedPercent: quota.used ?? 0,
            confidence: quota.confidence,
            observedAt: quota.observedAt
        )
        XCTAssertFalse(RouteTargetPolicy.agent.isRoutable(utilization, now: clock.value))
    }
}

private final class CountingFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshotDirectories: [URL] = []

    var cursorSnapshotDirectories: [URL] {
        lock.withLock { snapshotDirectories }
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if url.lastPathComponent.hasPrefix("TokeiCursorStateDB-") {
            lock.withLock { snapshotDirectories.append(url) }
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}

private struct MockCursorUsageClient: CursorUsageClient {
    let csv: Result<String, Error>
    var summary: Result<Data, Error>?

    func fetchUsageEventsCSV(cookie: String) async throws -> String {
        try csv.get()
    }

    func fetchUsageSummary(cookie: String) async throws -> Data {
        switch summary {
        case .success(let data): return data
        case .failure(let error): throw error
        case nil: throw CursorUsageError.unexpectedResponse
        }
    }
}

private final class AdvancingCursorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date { lock.withLock { storedValue } }

    func advance(by interval: TimeInterval) { lock.withLock { storedValue += interval } }
}

private actor DelayedCursorCSVClient: CursorUsageClient {
    private let clock: AdvancingCursorClock
    private var summaryCompleted = false

    init(clock: AdvancingCursorClock) {
        self.clock = clock
    }

    func fetchUsageSummary(cookie: String) async throws -> Data {
        summaryCompleted = true
        return Data(CursorFixtures.usageSummary.utf8)
    }
    func fetchUsageEventsCSV(cookie: String) async throws -> String {
        while !summaryCompleted { await Task.yield() }
        try await Task.sleep(for: .milliseconds(20))
        clock.advance(by: 3_600)
        return "Date,Total Tokens\n"
    }
}
