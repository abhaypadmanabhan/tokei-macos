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

    // Regression: `ps -axo command=` on a busy machine emits well over the ~64KB pipe
    // buffer. If run() calls waitUntilExit() before draining stdout, the child blocks
    // writing to the full pipe while the app blocks waiting — a permanent deadlock that
    // stalls the whole sync (snapshotAll awaits every provider). Drive run() with a
    // large-output command and require the FULL output back promptly. The pre-fix code
    // hangs here → the timeout makes this fail cleanly instead of hanging the suite.
    func testRunDrainsLargeSubprocessOutputWithoutDeadlock() throws {
        let discoverer = DefaultAntigravityQuotaEndpointDiscoverer()
        let box = OutputBox()
        let done = expectation(description: "run() returns without deadlocking on large output")

        DispatchQueue.global().async {
            box.value = discoverer.run(URL(fileURLWithPath: "/usr/bin/seq"), arguments: ["1", "200000"])
            done.fulfill()
        }
        wait(for: [done], timeout: 20)

        let output = try XCTUnwrap(box.value, "run() hung or returned nil on >64KB output")
        XCTAssertGreaterThan(output.utf8.count, 65_536, "test must exceed the pipe buffer to exercise the deadlock path")
        XCTAssertTrue(output.hasPrefix("1\n"), "output should start at the first line")
        XCTAssertTrue(output.contains("\n200000"), "output should include the final line — proof it was fully drained, not truncated")
    }

    func testRunTerminatesRunawaySubprocessWithinTimeout() throws {
        // Defense-in-depth: an unexpectedly long-running probe must not block the sync.
        let discoverer = DefaultAntigravityQuotaEndpointDiscoverer()
        let box = OutputBox()
        let done = expectation(description: "run() returns after the watchdog terminates a hung child")

        DispatchQueue.global().async {
            // `sleep 30` would block far past the timeout; the watchdog must kill it.
            box.value = discoverer.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 1)
            box.returned = true
            done.fulfill()
        }
        wait(for: [done], timeout: 10)

        XCTAssertTrue(box.returned, "run() should return promptly after the watchdog fires, not block for 30s")
        XCTAssertNil(box.value, "a terminated (non-zero exit) subprocess yields no output")
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

/// Reference holder so a background `run()` result can be read after the expectation
/// resolves (the `wait` establishes the happens-before ordering).
private final class OutputBox: @unchecked Sendable {
    var value: String?
    var returned = false
}
