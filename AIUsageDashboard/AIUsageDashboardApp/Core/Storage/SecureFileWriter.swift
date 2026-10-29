import Darwin
import Foundation
import os

/// Private, same-directory atomic writes shared by Core caches and external snapshots.
public enum SecureFileWriter {
    private static let logger = Logger(subsystem: "ai.padzy.tokei", category: "SecureFileWriter")

    public static func write(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = directory.appendingPathComponent(destination.lastPathComponent)
        try secureDirectory(at: directory)
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = temporary.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600) } ?? -1
        }
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
        }
        guard fchmod(descriptor, 0o600) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        // rename replaces the directory entry, never follows an existing destination symlink,
        // and retains the private temporary file's mode rather than the old file's mode.
        guard Darwin.rename(temporary.path, target.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    /// Resolve the support root once, then upgrade files without opening contents or following child links.
    /// Missing directories stay missing, preserving first-launch detection.
    public static func hardenExistingDirectory(at directory: URL, using fileManager: FileManager = .default) throws {
        let root = directory.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: root.path) else { return }
        try hardenDirectory(at: root, using: fileManager)
    }

    private static func hardenDirectory(at directory: URL, using fileManager: FileManager) throws {
        try secureDirectory(at: directory)
        for child in try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        ) {
            do {
                let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
                guard values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    try hardenDirectory(at: child, using: fileManager)
                } else if values.isRegularFile == true {
                    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: child.path)
                }
            } catch {
                logger.error("Could not harden support child \(child.path, privacy: .private): \(error)")
            }
        }
    }

    private static func secureDirectory(at directory: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else { throw POSIXError(.ENOTDIR) }
        } else {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
