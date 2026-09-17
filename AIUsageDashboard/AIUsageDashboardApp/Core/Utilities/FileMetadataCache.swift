import Foundation

/// Caches an optional value until the source file's identity or metadata changes.
final class FileMetadataCache<Value>: @unchecked Sendable {
    private struct Stamp: Equatable {
        let size: UInt64
        let modifiedAt: Date?
        let fileNumber: UInt64?
    }

    private struct Entry {
        let stamp: Stamp
        let value: Value?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(
        at url: URL,
        fileManager: FileManager,
        load: () -> Value?
    ) -> Value? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            lock.withLock { entries.removeValue(forKey: url.path) }
            return nil
        }
        let stamp = Stamp(
            size: size,
            modifiedAt: attributes[.modificationDate] as? Date,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
        if let cached = lock.withLock({ entries[url.path] }), cached.stamp == stamp {
            return cached.value
        }

        let value = load()
        lock.withLock { entries[url.path] = Entry(stamp: stamp, value: value) }
        return value
    }
}
