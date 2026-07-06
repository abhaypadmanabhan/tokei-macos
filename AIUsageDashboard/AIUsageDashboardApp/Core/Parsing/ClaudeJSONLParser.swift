import Foundation

public actor ClaudeJSONLParser {
    public enum ParserError: Error, Equatable {
        case malformedLine(Int)
        case missingUsageBlock(Int)
    }

    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        public let warnings: [ProviderWarning]
    }

    let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var seenIDs: Set<String> = []
        var records: [ClaudeUsageRecord] = []
        var warnings: [ProviderWarning] = []

        for source in logSources {
            do {
                let sourceRecords = try await parseFile(at: source.url)
                for record in sourceRecords {
                    let dedupeKey = record.messageID ?? record.requestID ?? "\(source.url.path):\(records.count)"
                    if seenIDs.insert(dedupeKey).inserted {
                        records.append(record)
                    }
                }
            } catch {
                warnings.append(ProviderWarning(
                    message: "Failed to parse \(source.url.lastPathComponent): \(error.localizedDescription)",
                    level: .warning
                ))
            }
        }

        let (today, week, month, lifetime) = aggregate(records: records)
        return AggregateUsage(today: today, week: week, month: month, lifetime: lifetime, warnings: warnings)
    }

    private func aggregate(records: [ClaudeUsageRecord]) -> (TokenUsage, TokenUsage, TokenUsage, TokenUsage) {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let monthStart = calendar.date(byAdding: .month, value: -1, to: todayStart) ?? todayStart

        var today = TokenUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, reasoningTokens: 0, confidence: .localParsed)
        var week = TokenUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, reasoningTokens: 0, confidence: .localParsed)
        var month = TokenUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, reasoningTokens: 0, confidence: .localParsed)
        var lifetime = TokenUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, reasoningTokens: 0, confidence: .localParsed)

        for record in records {
            let usage = TokenUsage(
                inputTokens: record.inputTokens,
                outputTokens: record.outputTokens,
                cacheReadTokens: record.cacheReadInputTokens,
                cacheCreationTokens: record.cacheCreationInputTokens,
                confidence: .localParsed
            )
            lifetime = lifetime.merging(usage)
            if let ts = record.timestamp {
                if ts >= todayStart { today = today.merging(usage) }
                if ts >= weekStart { week = week.merging(usage) }
                if ts >= monthStart { month = month.merging(usage) }
            }
        }
        return (today, week, month, lifetime)
    }
}
