import Foundation

public actor ClineMessagesParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        public let dailyTotals: [Date: Int]
        public let hourlyTotals: [Date: Int]?
        public let totalCost: Double
        public let warnings: [ProviderWarning]
    }

    private let calendar: Calendar
    private let now: () -> Date
    private let maxFileSizeBytes: UInt64
    private let readFile: @Sendable (URL, Int) throws -> Data
    private struct CachedFile {
        let fingerprint: LocalUsageFileFingerprint
        let decoded: Result<ClineSessionFile?, Error>
    }
    private var fileCache: [String: CachedFile] = [:]

    public init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        maxFileSizeBytes: UInt64 = 16 * 1024 * 1024,
        readFile: @escaping @Sendable (URL, Int) throws -> Data = { url, limit in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: limit) ?? Data()
        }
    ) {
        self.calendar = calendar
        self.now = now
        self.maxFileSizeBytes = maxFileSizeBytes
        self.readFile = readFile
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var warnings: [ProviderWarning] = []
        let referenceDate = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: referenceDate)
        var seenMessageIDs = Set<String>()
        var totalCost = 0.0
        let currentPaths = Set(logSources.map { $0.url.path })
        fileCache = fileCache.filter { currentPaths.contains($0.key) }

        for source in logSources {
            do {
                guard let sessionFile = try sessionFile(at: source.url) else {
                    let name = source.url.lastPathComponent
                    warnings.append(ProviderWarning(
                        message: "\(name): file exceeds maximum \(maxFileSizeBytes) bytes; skipped",
                        level: .warning
                    ))
                    continue
                }

                let sessionMillis = sessionMillisHint(from: source.sessionID ?? source.url.deletingLastPathComponent().lastPathComponent)

                for message in sessionFile.messages ?? [] {
                    guard let metrics = message.metrics else { continue }
                    guard let messageID = message.id else { continue }
                    guard seenMessageIDs.insert(messageID).inserted else { continue }

                    let usage = metrics.tokenUsage
                    let timestamp = ClineTimestampParsing.parse(
                        ts: message.ts,
                        sessionMillisHint: sessionMillis
                    )
                    windows.accumulate(usage, timestamp: timestamp, dailyTotal: usage.totalTokens ?? 0)
                    totalCost += metrics.cost ?? 0
                }
            } catch {
                warnings.append(ProviderWarning(
                    message: "Failed to parse \(source.url.lastPathComponent)",
                    level: .warning
                ))
            }
        }

        let snapshot = windows.snapshot()
        return AggregateUsage(
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            lifetime: snapshot.lifetime,
            dailyTotals: snapshot.dailyTotals,
            hourlyTotals: snapshot.hourlyTotals,
            totalCost: totalCost,
            warnings: warnings
        )
    }

    private func sessionFile(at url: URL) throws -> ClineSessionFile? {
        // Cline has always followed log-file aliases. Stamp the resolved file,
        // keeping that behaviour while noticing retargeted links and replacements.
        let fingerprint = try LocalUsageFileFingerprint.read(url.resolvingSymlinksInPath())
        if let cached = fileCache[url.path], cached.fingerprint == fingerprint {
            return try cached.decoded.get()
        }
        fileCache.removeValue(forKey: url.path)
        // The read stays bounded even if the file grows after stat. Malformed/oversized
        // content is cached too; I/O failures retry, and a write during the read is never cached.
        let data = try readFile(url, Int(maxFileSizeBytes) + 1)
        let decoded: Result<ClineSessionFile?, Error> = Result {
            guard data.count <= maxFileSizeBytes else { return nil }
            return try JSONDecoder().decode(ClineSessionFile.self, from: data)
        }
        if try LocalUsageFileFingerprint.read(url.resolvingSymlinksInPath()) == fingerprint {
            fileCache[url.path] = CachedFile(fingerprint: fingerprint, decoded: decoded)
        }
        return try decoded.get()
    }

    private func sessionMillisHint(from sessionID: String) -> Int64? {
        guard let prefix = sessionID.split(separator: "_").first,
              let millis = Int64(prefix) else {
            return nil
        }
        return millis
    }
}

enum ClineTimestampParsing {
    static func parse(ts: ClineFlexibleNumber?, sessionMillisHint: Int64?) -> Date? {
        guard let raw = ts?.doubleValue else {
            if let sessionMillisHint {
                return Date(timeIntervalSince1970: TimeInterval(sessionMillisHint) / 1000)
            }
            return nil
        }

        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000)
        }
        return Date(timeIntervalSince1970: raw)
    }
}

struct ClineSessionFile: Decodable, Sendable {
    let messages: [ClineMessage]?
}

struct ClineMessage: Decodable, Sendable {
    let id: String?
    let ts: ClineFlexibleNumber?
    let metrics: ClineMetrics?
}

struct ClineMetrics: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let cost: Double?

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            cacheReadTokens: cacheReadTokens ?? 0,
            cacheCreationTokens: cacheWriteTokens ?? 0,
            reasoningTokens: 0,
            confidence: .localParsed
        )
    }
}

struct ClineFlexibleNumber: Decodable, Sendable {
    let doubleValue: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int64.self) {
            doubleValue = Double(intValue)
        } else if let double = try? container.decode(Double.self) {
            doubleValue = double
        } else {
            doubleValue = nil
        }
    }
}
