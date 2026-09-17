import Foundation
import SQLite3

/// Creates one coherent SQLite snapshot without mutating the live database.
///
/// Shared by the DB-backed parsers (Cursor / opencode / Antigravity), which each
/// duplicated this loop verbatim. SQLite's online backup API reads the main image
/// and committed WAL frames as one transactionally consistent snapshot. A sequential
/// filesystem copy cannot provide that guarantee and can pair sidecars with the wrong
/// main-file generation.
enum SQLiteSidecarCopy {
    static func copyDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        using fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        var sourceDatabase: OpaquePointer?
        let sourceResult = sqlite3_open_v2(
            sourceURL.path,
            &sourceDatabase,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard sourceResult == SQLITE_OK, let sourceDatabase else {
            let message = sourceDatabase.map(sqliteMessage) ?? "unable to open source database"
            if let sourceDatabase { sqlite3_close(sourceDatabase) }
            throw SQLiteSnapshotError(message: message)
        }
        sqlite3_busy_timeout(sourceDatabase, 1_000)

        var destinationDatabase: OpaquePointer?
        let destinationResult = sqlite3_open_v2(
            destinationURL.path,
            &destinationDatabase,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard destinationResult == SQLITE_OK, let destinationDatabase else {
            let message = destinationDatabase.map(sqliteMessage) ?? "unable to create snapshot database"
            if let destinationDatabase { sqlite3_close(destinationDatabase) }
            sqlite3_close(sourceDatabase)
            throw SQLiteSnapshotError(message: message)
        }
        sqlite3_busy_timeout(destinationDatabase, 1_000)

        guard let backup = sqlite3_backup_init(
            destinationDatabase,
            "main",
            sourceDatabase,
            "main"
        ) else {
            let message = sqliteMessage(destinationDatabase)
            sqlite3_close(destinationDatabase)
            sqlite3_close(sourceDatabase)
            throw SQLiteSnapshotError(message: message)
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        if stepResult == SQLITE_DONE, finishResult == SQLITE_OK {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let journalResult = sqlite3_exec(
                destinationDatabase,
                "PRAGMA journal_mode=DELETE",
                nil,
                nil,
                &errorMessage
            )
            let message = errorMessage.map { String(cString: $0) }
            sqlite3_free(errorMessage)
            sqlite3_close(destinationDatabase)
            sqlite3_close(sourceDatabase)
            guard journalResult == SQLITE_OK else {
                throw SQLiteSnapshotError(message: message ?? "could not finalize SQLite snapshot")
            }
            return
        }

        let message = sqliteMessage(destinationDatabase)
        sqlite3_close(destinationDatabase)
        sqlite3_close(sourceDatabase)

        let walURL = URL(fileURLWithPath: sourceURL.path + "-wal")
        if (stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED),
           !fileManager.fileExists(atPath: walURL.path) {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }
        throw SQLiteSnapshotError(message: message)
    }

    private static func sqliteMessage(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "unknown SQLite error"
    }
}

private struct SQLiteSnapshotError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
