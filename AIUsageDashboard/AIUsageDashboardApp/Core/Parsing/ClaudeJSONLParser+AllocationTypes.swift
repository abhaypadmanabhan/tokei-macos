import Foundation

extension ClaudeJSONLParser {
    struct PreparedAccount {
        let id: String
        let entries: [FileCacheEntry]
        let warnings: [ProviderWarning]
    }

    struct ClaimedRecord {
        var record: ClaudeUsageRecord
        let ownerID: String
        var ambiguous: Bool
    }

    struct AllocationResult {
        let byAccountID: [String: FileAggregate]
        let ambiguousKeys: Int
        let ambiguousOwnerIDs: Set<String>
        let claimCount: Int
    }

    struct AllocationAccountMembership: Equatable {
        let id: String
        let paths: [String]
    }

    struct AllocationCacheKey: Equatable {
        let generation: UInt64
        let accounts: [AllocationAccountMembership]
    }

    struct AllocationCache {
        let key: AllocationCacheKey
        let result: AllocationResult
    }

    struct FileAggregate: Sendable {
        var lifetime: TokenUsage
        var dailyUsage: [Date: TokenUsage]
        var dailyModelUsage: [Date: [String: TokenUsage]]
        var hourlyTotals: [Date: Int]
        var arithmeticOverflowed: Bool

        static var empty: FileAggregate {
            FileAggregate(
                lifetime: TokenUsage(confidence: .localParsed),
                dailyUsage: [:],
                dailyModelUsage: [:],
                hourlyTotals: [:],
                arithmeticOverflowed: false
            )
        }
    }

    func accumulateModelUsage(
        _ record: ClaudeUsageRecord,
        day: Date,
        multiplier: Int,
        into aggregate: inout FileAggregate
    ) {
        if let month = modelUsageMonth, day >= month.start, day < month.end {
            let modelUsage = adjusted(
                aggregate.dailyModelUsage[day]?[record.model] ?? UsageWindows.emptyUsage(.localParsed),
                by: record,
                multiplier: multiplier,
                overflowed: &aggregate.arithmeticOverflowed
            )
            if modelUsage.totalTokens == 0 {
                aggregate.dailyModelUsage[day]?.removeValue(forKey: record.model)
                if aggregate.dailyModelUsage[day]?.isEmpty == true {
                    aggregate.dailyModelUsage.removeValue(forKey: day)
                }
            } else {
                aggregate.dailyModelUsage[day, default: [:]][record.model] = modelUsage
            }
        }
    }

    func mergeModelUsage(_ incremental: FileAggregate, into aggregate: inout FileAggregate) {
        for (day, models) in incremental.dailyModelUsage {
            for (model, usage) in models {
                let previous = aggregate.dailyModelUsage[day]?[model] ?? UsageWindows.emptyUsage(.localParsed)
                aggregate.dailyModelUsage[day, default: [:]][model] = previous.merging(
                    usage, overflowed: &aggregate.arithmeticOverflowed
                )
            }
        }
    }

    func adjusted(
        _ usage: TokenUsage,
        by record: ClaudeUsageRecord,
        multiplier: Int,
        overflowed: inout Bool
    ) -> TokenUsage {
        func adjustedComponent(_ current: Int, _ value: Int) -> Int {
            let contribution = TokenArithmetic.multiplied(value, by: multiplier, overflowed: &overflowed)
            return TokenArithmetic.adding(current, contribution, overflowed: &overflowed)
        }

        let adjusted = TokenUsage(
            inputTokens: adjustedComponent(usage.inputTokens ?? 0, record.inputTokens),
            outputTokens: adjustedComponent(usage.outputTokens ?? 0, record.outputTokens),
            cacheReadTokens: adjustedComponent(usage.cacheReadTokens ?? 0, record.cacheReadInputTokens),
            cacheCreationTokens: adjustedComponent(
                usage.cacheCreationTokens ?? 0,
                record.cacheCreationInputTokens
            ),
            cacheCreation1hTokens: usage.cacheCreation1hTokens == nil && record.cacheCreation1hTokens == nil
                ? nil : adjustedComponent(usage.cacheCreation1hTokens ?? 0, record.cacheCreation1hTokens ?? 0),
            reasoningTokens: usage.reasoningTokens ?? 0,
            confidence: .localParsed
        )
        _ = adjusted.totalTokens(overflowed: &overflowed)
        return adjusted
    }

}
