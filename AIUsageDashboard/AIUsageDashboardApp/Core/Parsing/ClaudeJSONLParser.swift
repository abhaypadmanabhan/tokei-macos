import Foundation

public actor ClaudeJSONLParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        /// Total tokens per calendar day (start-of-day key) for records with timestamps.
        public let dailyTotals: [Date: Int]
        public let hourlyTotals: [Date: Int]?
        public let warnings: [ProviderWarning]
    }

    let calendar: Calendar
    private let now: () -> Date

    public init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var seenIDs: Set<String> = []
        var warnings: [ProviderWarning] = []
        var windows = UsageWindows(calendar: calendar, referenceDate: now())

        for source in logSources {
            do {
                let malformedCount = try await parseFile(at: source.url) { record in
                    if let key = record.dedupeKey {
                        guard seenIDs.insert(key).inserted else { return }
                    }
                    let usage = record.toTokenUsage()
                    windows.accumulate(usage, timestamp: record.timestamp, dailyTotal: record.totalTokens)
                }
                if malformedCount > 0 {
                    warnings.append(ProviderWarning(
                        message: "\(source.url.lastPathComponent): \(malformedCount) malformed line(s) skipped",
                        level: .warning
                    ))
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
            warnings: warnings
        )
    }
}
