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

    public init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        maxFileSizeBytes: UInt64 = 16 * 1024 * 1024
    ) {
        self.calendar = calendar
        self.now = now
        self.maxFileSizeBytes = maxFileSizeBytes
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var warnings: [ProviderWarning] = []
        let referenceDate = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: referenceDate)
        var seenMessageIDs = Set<String>()
        var totalCost = 0.0

        for source in logSources {
            do {
                // Bound the read itself rather than stat-then-read: a separate
                // attributesOfItem() check races a file that grows between the check
                // and Data(contentsOf:). Reading at most maxFileSizeBytes+1 bytes means
                // the cap is enforced on the actual bytes we consume, and — since a
                // within-cap file returns fewer bytes than requested — this read also
                // *is* the full file content, no second pass needed.
                let handle = try FileHandle(forReadingFrom: source.url)
                let data = try handle.read(upToCount: Int(maxFileSizeBytes) + 1) ?? Data()
                try handle.close()
                guard data.count <= maxFileSizeBytes else {
                    let name = source.url.lastPathComponent
                    warnings.append(ProviderWarning(
                        message: "\(name): file exceeds maximum \(maxFileSizeBytes) bytes; skipped",
                        level: .warning
                    ))
                    continue
                }

                let sessionFile = try JSONDecoder().decode(ClineSessionFile.self, from: data)
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
                    message: "Failed to parse \(source.url.lastPathComponent): \(error.localizedDescription)",
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
