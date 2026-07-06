import Foundation

public actor ClaudeJSONLParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
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

        let referenceDate = now()
        let todayStart = calendar.startOfDay(for: referenceDate)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let monthStart = calendar.date(byAdding: .month, value: -1, to: todayStart) ?? todayStart

        var today = emptyUsage
        var week = emptyUsage
        var month = emptyUsage
        var lifetime = emptyUsage

        for source in logSources {
            do {
                let malformedCount = try await parseFile(at: source.url) { record in
                    if let key = record.dedupeKey {
                        guard seenIDs.insert(key).inserted else { return }
                    }
                    let usage = record.toTokenUsage()
                    lifetime = lifetime.merging(usage)
                    if let ts = record.timestamp {
                        if ts >= todayStart { today = today.merging(usage) }
                        if ts >= weekStart { week = week.merging(usage) }
                        if ts >= monthStart { month = month.merging(usage) }
                    }
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

        return AggregateUsage(today: today, week: week, month: month, lifetime: lifetime, warnings: warnings)
    }

    private var emptyUsage: TokenUsage {
        TokenUsage(
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            confidence: .localParsed
        )
    }
}
