import Darwin
import Foundation

/// Private, same-directory atomic writes shared by Core caches and external snapshots.
public enum SecureFileWriter {
    public static func write(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
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
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    /// Upgrade existing support files without opening their contents or following links.
    /// Missing directories stay missing, preserving first-launch detection.
    public static func hardenExistingDirectory(at directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try secureDirectory(at: directory)
        for child in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        ) {
            let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                try hardenExistingDirectory(at: child)
            } else if values.isRegularFile == true {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: child.path)
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
