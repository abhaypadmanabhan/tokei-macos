import SQLite3
import XCTest
@testable import AIUsageDashboardCore

final class CursorCSVCacheTests: XCTestCase {
    func testEveryCSVRefreshParsesWithoutRetainingTheExportAndDayRollsOver() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = directory.appendingPathComponent("preferences").path
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "cursorNetworkUsageEnabled")
        defer {
            defaults.removePersistentDomain(forName: suite)
            defaults.synchronize()
            try? FileManager.default.removeItem(at: directory)
        }
        let databaseURL = directory.appendingPathComponent("state.vscdb")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let sql = "CREATE TABLE ItemTable(key TEXT PRIMARY KEY,value TEXT); " +
            "INSERT INTO ItemTable VALUES('cursorAuth/accessToken','\(CursorFixtures.jwtPlaceholder)');"
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let csv = "Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Cost\n" +
            "2026-07-08T09:00:00Z,test-model,10,10,20,5,0.01\n"
        let client = CSVCacheClient(csv)
        let clock = CSVCacheClock()
        let counter = CSVParseCounter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let provider = CursorProvider(
            stateDatabaseURL: databaseURL, usageClient: client, calendar: calendar, now: clock.read,
            userDefaults: defaults, parseUsageEvents: { counter.increment(); return CursorUsageCSV.parseEvents($0) }
        )
        for _ in 0..<3 {
            let snapshot = try await provider.fetchSnapshot()
            XCTAssertEqual(snapshot.todayUsage.totalTokens, 35)
        }
        XCTAssertEqual(counter.count, 3)
        await client.set(csv.replacingOccurrences(of: ",10,10,20,5,", with: ",11,11,20,5,"))
        let changed = try await provider.fetchSnapshot()
        XCTAssertEqual(changed.todayUsage.totalTokens, 36)
        XCTAssertEqual(counter.count, 4)
        clock.nextDay()
        let tomorrow = try await provider.fetchSnapshot()
        XCTAssertEqual(tomorrow.todayUsage.totalTokens, 0)
        XCTAssertEqual(counter.count, 5, "parse the current export and rebuild date windows each refresh")
    }
}

private actor CSVCacheClient: CursorUsageClient {
    private var csv: String
    init(_ csv: String) { self.csv = csv }
    func set(_ csv: String) { self.csv = csv }
    func fetchUsageEventsCSV(cookie: String) async throws -> String { csv }
    func fetchUsageSummary(cookie: String) async throws -> Data { Data("{}".utf8) }
}

private final class CSVParseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private final class CSVCacheClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
    func read() -> Date { lock.withLock { value } }
    func nextDay() { lock.withLock { value = value.addingTimeInterval(86_400) } }
}
