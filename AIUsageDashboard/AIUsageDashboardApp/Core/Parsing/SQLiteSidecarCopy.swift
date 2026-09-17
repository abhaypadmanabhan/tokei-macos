import Darwin
import Foundation
import SQLite3

/// Creates one coherent SQLite snapshot without mutating the live database.
///
/// Shared by the DB-backed parsers (Cursor / opencode / Antigravity). SQLite's online
/// backup API reads the main image and committed WAL frames as one transactionally
/// consistent snapshot. Busy/locked sources are retried briefly; a raw main-file copy
/// is never used because rollback-journal pages may contain uncommitted writes.
enum SQLiteSidecarCopy {
    static func createPrivateSnapshotDirectory(
        at directoryURL: URL,
        using fileManager: FileManager
    ) throws {
        let privatePermissions = NSNumber(value: 0o700)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: privatePermissions]
        )
        // Enforce the final mode even if a FileManager implementation ignores the
        // creation attributes or the process umask changes them.
        try fileManager.setAttributes(
            [.posixPermissions: privatePermissions],
            ofItemAtPath: directoryURL.path
        )
    }

    static func copyDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        using fileManager: FileManager
    ) throws {
        try createPrivateDestinationFile(at: destinationURL)
        var shouldRemoveDestination = true
        defer {
            if shouldRemoveDestination {
                try? fileManager.removeItem(at: destinationURL)
            }
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
        sqlite3_busy_timeout(sourceDatabase, 50)

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
        sqlite3_busy_timeout(destinationDatabase, 50)

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
        var stepResult = SQLITE_OK
        for _ in 0..<5 {
            stepResult = sqlite3_backup_step(backup, -1)
            guard stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED else { break }
            sqlite3_sleep(50)
        }
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
            shouldRemoveDestination = false
            return
        }

        let message = (stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED)
            ? "database remained busy or locked while creating a coherent snapshot"
            : sqliteMessage(destinationDatabase)
        sqlite3_close(destinationDatabase)
        sqlite3_close(sourceDatabase)
        throw SQLiteSnapshotError(message: message)
    }

    private static func createPrivateDestinationFile(at destinationURL: URL) throws {
        let descriptor = destinationURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(
                path,
                O_CREAT | O_EXCL | O_WRONLY,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else {
            let errorNumber = errno
            throw SQLiteSnapshotError(
                message: "unable to create private SQLite snapshot: \(String(cString: strerror(errorNumber)))"
            )
        }

        let chmodResult = Darwin.fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR))
        let chmodError = errno
        let closeResult = Darwin.close(descriptor)
        let closeError = errno
        guard chmodResult == 0 else {
            removePrivateDestinationFile(at: destinationURL)
            throw SQLiteSnapshotError(
                message: "unable to secure SQLite snapshot: \(String(cString: strerror(chmodError)))"
            )
        }
        guard closeResult == 0 else {
            removePrivateDestinationFile(at: destinationURL)
            throw SQLiteSnapshotError(
                message: "unable to close SQLite snapshot: \(String(cString: strerror(closeError)))"
            )
        }
    }

    private static func removePrivateDestinationFile(at destinationURL: URL) {
        destinationURL.withUnsafeFileSystemRepresentation { path in
            if let path { _ = Darwin.unlink(path) }
        }
    }

    private static func sqliteMessage(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "unknown SQLite error"
    }
}

private struct SQLiteSnapshotError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
