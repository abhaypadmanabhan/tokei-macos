import Foundation

/// One decode attempt per fingerprint across parser instances and calendar invalidations.
/// Only compact usage/model/tier records survive; conversation text and decoded bytes do not.
actor CodexCompressedLogCache {
    static let shared = CodexCompressedLogCache()

    struct Fingerprint: Equatable, Sendable {
        let size: UInt64
        let modified: Date
        let inode: UInt64

        init?(size: UInt64, modified: Date?, inode: UInt64?) {
            guard let modified, let inode else { return nil }
            self.size = size
            self.modified = modified
            self.inode = inode
        }

        static func read(_ url: URL) -> Fingerprint? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            return Fingerprint(size: size.uint64Value, modified: attributes[.modificationDate] as? Date,
                               inode: inode.uint64Value)
        }
    }

    struct Decoded: Sendable {
        let records: [CodexUsageRecord]
        let firstEventAt: Date?
        let lastEventAt: Date?
        let malformedCount: Int
        let decoderSeconds: TimeInterval
    }

    enum Outcome: Sendable {
        case decoded(Decoded)
        case failed(String)
    }

    struct Lookup: Sendable {
        let outcome: Outcome
        let readFromDisk: Bool
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let outcome: Outcome
    }
    private var entries: [String: Entry] = [:]

    func read(_ url: URL, fingerprint: Fingerprint,
              parseLine: @Sendable (Data) -> CodexLineParseOutcome) -> Lookup {
        if let entry = entries[url.path], entry.fingerprint == fingerprint {
            return Lookup(outcome: entry.outcome, readFromDisk: false)
        }
        let outcome: Outcome
        do {
            let decoded = try decode(url, parseLine: parseLine)
            guard Fingerprint.read(url) == fingerprint else { throw CacheError.changedDuringRead }
            outcome = .decoded(decoded)
        } catch { outcome = .failed(error.localizedDescription) }
        entries[url.path] = Entry(fingerprint: fingerprint, outcome: outcome)
        return Lookup(outcome: outcome, readFromDisk: true)
    }

    private func decode(_ url: URL, parseLine: (Data) -> CodexLineParseOutcome) throws -> Decoded {
        var records: [CodexUsageRecord] = []
        var first: Date?
        var last: Date?
        var framer = CodexJSONLFramer()
        var framingSeconds = 0.0
        let keep: (CodexUsageRecord) -> Void = { record in
            if let timestamp = record.timestamp {
                first = min(first ?? timestamp, timestamp)
                last = max(last ?? timestamp, timestamp)
            }
            if record.contributesUsage || record.model != nil || record.tier != nil { records.append(record) }
        }
        let start = ProcessInfo.processInfo.systemUptime
        try ZstdDecoder.decode(fileAt: url) { chunk in
            let frameStart = ProcessInfo.processInfo.systemUptime
            autoreleasepool { framer.consume(chunk, parseLine: parseLine, onRecord: keep) }
            framingSeconds += ProcessInfo.processInfo.systemUptime - frameStart
        }
        let decoderSeconds = max(0, ProcessInfo.processInfo.systemUptime - start - framingSeconds)
        let result = autoreleasepool { framer.finish(parseLine: parseLine, onRecord: keep) }
        return Decoded(records: records, firstEventAt: first, lastEventAt: last,
                       malformedCount: result.malformedCount, decoderSeconds: decoderSeconds)
    }

    private enum CacheError: Error { case changedDuringRead }
}
