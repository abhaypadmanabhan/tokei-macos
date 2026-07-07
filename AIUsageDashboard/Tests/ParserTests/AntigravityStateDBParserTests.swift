import SQLite3
import XCTest
@testable import AIUsageDashboardCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class AntigravityStateDBParserTests: XCTestCase {
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

    func testParserDecodesPlanQuotaIntsAndDoubleEncodedCreditsFromFixtureDatabase() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: fixtureRows())

        let parsed = await AntigravityStateDBParser().parse(stateDatabaseURL: stateDB)

        XCTAssertEqual(parsed.planName, "Pro")
        XCTAssertEqual(parsed.availableCredits, 1000)
        XCTAssertEqual(parsed.minimumCreditAmountForUsage, 50)
        XCTAssertEqual(parsed.rawQuotaValues[7], 16_384)
        XCTAssertEqual(parsed.rawQuotaValues[8], 600)
        XCTAssertEqual(parsed.rawQuotaValues[12], 50_000)
        XCTAssertEqual(parsed.rawQuotaValues[13], 150_000)
        XCTAssertEqual(parsed.rawQuotaValues[14], 25_000)
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    func testParserReadsFromTempCopyWithoutMutatingOriginalDatabase() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: fixtureRows())
        let originalModifiedAt = try stateDB.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        var lockedDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(stateDB.path, &lockedDatabase, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer {
            sqlite3_exec(lockedDatabase, "ROLLBACK", nil, nil, nil)
            sqlite3_close(lockedDatabase)
        }
        XCTAssertEqual(sqlite3_exec(lockedDatabase, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, nil), SQLITE_OK)

        let parsed = await AntigravityStateDBParser().parse(stateDatabaseURL: stateDB)

        XCTAssertEqual(parsed.planName, "Pro")
        XCTAssertEqual(parsed.availableCredits, 1000)
        let modifiedAtAfterRead = try stateDB.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        XCTAssertEqual(modifiedAtAfterRead, originalModifiedAt)
    }

    func testProviderAvailabilityUsesStateDatabasePresenceOnly() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        let provider = AntigravityProvider(stateDatabaseURL: stateDB)

        var availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .notInstalled)

        try createStateDatabase(at: stateDB, rows: fixtureRows())
        availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
    }

    func testProviderReturnsAuthenticatedCreditsQuotaAndPlanWarning() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: fixtureRows())
        let provider = AntigravityProvider(stateDatabaseURL: stateDB)

        let snapshot = try await provider.fetchSnapshot()
        let capabilities = await provider.capabilities

        XCTAssertEqual(capabilities.rawValue, ProviderCapabilities([.localLog, .quota]).rawValue)
        XCTAssertEqual(snapshot.providerID, .antigravity)
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.todayUsage.confidence, .unavailable)
        XCTAssertEqual(snapshot.weekUsage.confidence, .unavailable)
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.type, .credits)
        XCTAssertEqual(snapshot.quotaWindows.first?.remaining, 1000)
        XCTAssertEqual(snapshot.quotaWindows.first?.limit, 1050)
        XCTAssertEqual(snapshot.quotaWindows.first?.used, 50)
        XCTAssertEqual(snapshot.quotaWindows.first?.confidence, .localParsed)
        XCTAssertEqual(snapshot.quotaWindows.first?.source, "antigravity local protobuf")
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .info && $0.message == "Plan: Pro" })
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .info && $0.message == "Antigravity raw quota field 7: 16384" })
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
