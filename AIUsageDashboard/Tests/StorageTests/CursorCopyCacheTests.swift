import SQLite3
import XCTest
@testable import AIUsageDashboardCore

final class CursorCopyCacheTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("state.vscdb")
        try execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }

    func testThreeUnchangedRefreshesOnlyCopyOnce() async {
        let manager = CountingSnapshotManager()
        let parser = CursorStateDBParser(copyDatabase: { source, destination in
            manager.recordCopy()
            try SQLiteSidecarCopy.copyDatabase(from: source, to: destination, using: .default)
        })
        for _ in 0..<3 {
            _ = await parser.parse(stateDatabaseURL: databaseURL)
        }
        XCTAssertEqual(manager.copies, 1)
    }

    func testWALOnlyChangeInvalidatesAndMissingDatabaseDropsCachedState() async throws {
        let manager = CountingSnapshotManager()
        let parser = CursorStateDBParser(copyDatabase: { source, destination in
            manager.recordCopy()
            try SQLiteSidecarCopy.copyDatabase(from: source, to: destination, using: .default)
        })
        _ = await parser.parse(stateDatabaseURL: databaseURL)
        let wal = URL(fileURLWithPath: databaseURL.path + "-wal")
        try Data().write(to: wal)
        _ = await parser.parse(stateDatabaseURL: databaseURL)
        XCTAssertEqual(manager.copies, 2)
        try FileManager.default.removeItem(at: wal)
        try FileManager.default.removeItem(at: databaseURL)
        let missing = await parser.parse(stateDatabaseURL: databaseURL)
        XCTAssertFalse(missing.warnings.isEmpty)
        try execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
        let recovered = await parser.parse(stateDatabaseURL: databaseURL)
        XCTAssertTrue(recovered.warnings.isEmpty)
    }
}

private final class CountingSnapshotManager: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var copies: Int { lock.withLock { value } }

    func recordCopy() { lock.withLock { value += 1 } }
}
