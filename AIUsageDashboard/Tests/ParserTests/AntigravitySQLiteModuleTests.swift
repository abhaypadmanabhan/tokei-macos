import os
import SQLite3
import XCTest
@testable import AIUsageDashboardCore

final class AntigravitySQLiteModuleTests: XCTestCase {
    func testHardenedConnectionDoesNotStartUnrelatedVirtualTableModules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.db")
        do {
            var database: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
            defer { sqlite3_close(database) }
            XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE steps(idx INTEGER, metadata BLOB)",
                                        nil, nil, nil), SQLITE_OK)
            let created = ["fts5", "fts4", "fts3"].contains { module in
                sqlite3_exec(database, "CREATE VIRTUAL TABLE decoy USING \(module)(content)",
                             nil, nil, nil) == SQLITE_OK
            }
            guard created else { throw XCTSkip("System SQLite has no FTS module") }
        }

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let database = try XCTUnwrap(handle)
        defer { sqlite3_close(database) }
        XCTAssertEqual(TokeiSQLiteHardenConnection(database), SQLITE_OK)
        ModuleStartupTrace.statements.withLock { $0.removeAll() }
        defer { ModuleStartupTrace.statements.withLock { $0.removeAll() } }
        XCTAssertEqual(sqlite3_trace_v2(database, UInt32(SQLITE_TRACE_STMT),
                                        ModuleStartupTrace.callback, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA main.table_list('steps')", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "SELECT idx FROM steps", nil, nil, nil), SQLITE_OK)
        let statements = ModuleStartupTrace.statements.withLock { $0 }
        XCTAssertTrue(statements.contains { $0.contains("steps") })
        XCTAssertFalse(statements.contains { $0.contains("decoy") }, statements.joined(separator: "\n"))
        XCTAssertNoThrow(try AntigravityConversationDatabase.read(url, modifiedAt: Date()))
    }
}

private enum ModuleStartupTrace {
    static let statements = OSAllocatedUnfairLock(initialState: [String]())
    static let callback: @convention(c) (
        UInt32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
    ) -> Int32 = { _, _, _, sql in
        if let sql {
            let statement = String(cString: sql.assumingMemoryBound(to: CChar.self))
            statements.withLock { $0.append(statement) }
        }
        return 0
    }
}
