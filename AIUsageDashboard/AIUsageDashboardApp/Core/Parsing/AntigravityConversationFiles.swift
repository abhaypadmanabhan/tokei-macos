// Adapted from T3 Code: apps/server/src/provider/Drivers/antigravityUsageReader.ts (MIT).
import Darwin
import Foundation

/// Fresh lstat values include ctime and inode, so restoring size/mtime cannot hide a replacement.
struct LocalUsageFileFingerprint: Equatable, Sendable {
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    let inode: UInt64

    static func read(_ url: URL) throws -> Self {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileReadUnknown) }
        return Self(size: info.st_size, modifiedSeconds: info.st_mtimespec.tv_sec,
                    modifiedNanos: info.st_mtimespec.tv_nsec, changedSeconds: info.st_ctimespec.tv_sec,
                    changedNanos: info.st_ctimespec.tv_nsec, inode: info.st_ino)
    }
}

enum AntigravityConversationFiles {
    struct Fingerprint: Equatable, Sendable {
        let database: LocalUsageFileFingerprint
        let wal: LocalUsageFileFingerprint?
    }

    static func fingerprint(_ url: URL) throws -> Fingerprint {
        let wal = URL(fileURLWithPath: url.path + "-wal")
        return Fingerprint(database: try .read(url), wal: FileManager.default.fileExists(atPath: wal.path)
                           ? try .read(wal) : nil)
    }

    static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        if let override = environment["ANTIGRAVITY_DATA_DIR"], !override.isEmpty {
            return override.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
        }
        let gemini = home.appendingPathComponent(".gemini")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: gemini.path)) ?? []
        let canonical = ["antigravity", "antigravity-cli", "antigravity-ide", "antigravity-backup"]
        // Extra roots are conversation stores, not similarly named browser/cache profiles.
        let additional = names.filter { name in
            guard name.hasPrefix("antigravity") else { return false }
            let conversations = gemini.appendingPathComponent(name).appendingPathComponent("conversations")
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: conversations.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        return Set(canonical + additional).sorted().map { gemini.appendingPathComponent($0) }
            + [home.appendingPathComponent(".config/antigravity")]
    }

    static func discover(_ roots: [URL]) -> (files: [URL], partial: Bool) {
        var files: Set<URL> = []
        var directories: Set<URL> = []
        var partial = false
        let manager = FileManager.default
        for root in roots {
            let conversations = root.appendingPathComponent("conversations")
            let directory = (manager.fileExists(atPath: conversations.path) ? conversations : root)
                .resolvingSymlinksInPath()
            guard directories.insert(directory).inserted, manager.fileExists(atPath: directory.path) else { continue }
            guard let enumerator = manager.enumerator(at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in partial = true; return true }) else {
                partial = true
                continue
            }
            for case let url as URL in enumerator {
                do {
                    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if url.pathExtension == "db", values.isRegularFile == true { files.insert(url) }
                } catch { partial = true }
            }
        }
        return (files.sorted { $0.path < $1.path }, partial)
    }
}
