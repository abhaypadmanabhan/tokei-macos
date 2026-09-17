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
        var hourlyTotals: [Date: Int]
        var arithmeticOverflowed: Bool

        static var empty: FileAggregate {
            FileAggregate(
                lifetime: TokenUsage(confidence: .localParsed),
                dailyUsage: [:],
                hourlyTotals: [:],
                arithmeticOverflowed: false
            )
        }
    }
}
