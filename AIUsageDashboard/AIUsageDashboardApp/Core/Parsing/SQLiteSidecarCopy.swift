import Foundation

/// Copies a SQLite database file together with its `-wal`/`-shm` sidecars so the
/// copy can be opened read-only without touching (or being disturbed by) the live
/// database another process still holds open.
///
/// Shared by the DB-backed parsers (Cursor / opencode / Antigravity), which each
/// duplicated this loop verbatim. Copying the sidecars next to the destination
/// before opening is what lets SQLite replay any un-checkpointed WAL frames into
/// the copy; without them the copy would read as an older snapshot. Sidecar copies
/// are best-effort — a missing or unreadable sidecar is skipped, matching WAL
/// semantics where the main file alone is still a valid (if slightly stale)
/// database.
enum SQLiteSidecarCopy {
    static func copyDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        using fileManager: FileManager
    ) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        for suffix in ["-wal", "-shm"] {
            let sourceSidecar = URL(fileURLWithPath: sourceURL.path + suffix)
            guard fileManager.fileExists(atPath: sourceSidecar.path) else { continue }
            let destinationSidecar = URL(fileURLWithPath: destinationURL.path + suffix)
            try? fileManager.copyItem(at: sourceSidecar, to: destinationSidecar)
        }
    }
}
