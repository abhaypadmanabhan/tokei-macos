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

    var calendar: Calendar
    var calendarIdentity: CalendarIdentity
    private let now: () -> Date

    /// Caches per-file aggregates so unchanged logs are not re-parsed on every sync.
    /// The key is the file path; entries are invalidated when the modification date
    /// or file size changes.
    var fileCache: [String: FileCacheEntry] = [:]
    private var fileCacheGeneration: UInt64 = 0
    private var allocationCache: AllocationCache?

    public init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.calendarIdentity = CalendarIdentity(calendar)
        self.now = now
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        let accountID = "__single_account__"
        let result = await parse(accountLogSources: [
            AccountLogSources(accountID: accountID, logSources: logSources)
        ])
        return result.byAccountID[accountID] ?? emptyAggregate(warnings: result.warnings)
    }

    struct AccountLogSources: Sendable {
        let accountID: String
        let logSources: [LogSource]
    }

    struct AccountParseResult: Sendable {
        let byAccountID: [String: AggregateUsage]
        let warnings: [ProviderWarning]
    }

    /// Parses all Claude identities as one provider-wide dedupe domain while retaining a
    /// disjoint aggregate for each account. Copied history cannot establish which identity
    /// was billed, so ownership is deterministic: the lexicographically first account id.
    func parse(accountLogSources: [AccountLogSources]) async -> AccountParseResult {
        invalidateCacheIfEffectiveCalendarChanged()
        var stats = ParseStats()
        let prepared = await prepare(accountLogSources, stats: &stats)

        let activePaths = Set(accountLogSources.flatMap(\.logSources).map(\.url.path))
        let retainedFileCache = fileCache.filter { path, _ in
            activePaths.contains(path) || FileManager.default.fileExists(atPath: path)
        }
        if retainedFileCache.count != fileCache.count {
            fileCache = retainedFileCache
            didMutateFileCache()
        }

        let allocationKey = makeAllocationCacheKey(for: accountLogSources)
        let allocation: AllocationResult
        if let cached = allocationCache, cached.key == allocationKey {
            allocation = cached.result
        } else {
            allocation = allocate(prepared, stats: &stats)
            allocationCache = AllocationCache(key: allocationKey, result: allocation)
        }

        var globalWarnings: [ProviderWarning] = []
        if allocation.ambiguousKeys > 0 {
            globalWarnings.append(ambiguityWarning(for: allocation))
        }

        let byAccountID = Dictionary(uniqueKeysWithValues: prepared.map { account in
            let aggregate = allocation.byAccountID[account.id] ?? .empty
            var warnings = account.warnings
            if aggregate.arithmeticOverflowed {
                warnings.append(arithmeticOverflowWarning())
            }
            return (account.id, makeAggregate(from: aggregate, warnings: warnings))
        })

        stats.emit(
            sources: accountLogSources.flatMap(\.logSources).count,
            cacheSize: fileCache.count,
            seenIDs: allocation.claimCount
        )
        return AccountParseResult(byAccountID: byAccountID, warnings: globalWarnings)
    }

    private func prepare(
        _ accounts: [AccountLogSources],
        stats: inout ParseStats
    ) async -> [PreparedAccount] {
        var prepared: [PreparedAccount] = []
        for account in accounts.sorted(by: { $0.accountID < $1.accountID }) {
            var entries: [FileCacheEntry] = []
            var warnings: [ProviderWarning] = []
            for source in account.logSources.sorted(by: { $0.url.path < $1.url.path }) {
                do {
                    let entry = try await cachedEntry(for: source, stats: &stats)
                    entries.append(entry)
                    if entry.malformedCount > 0 {
                        warnings.append(malformedWarning(count: entry.malformedCount, url: source.url))
                    }
                } catch {
                    fileCache.removeValue(forKey: source.url.path)
                    didMutateFileCache()
                    warnings.append(ProviderWarning(
                        message: "Failed to parse \(source.url.lastPathComponent)",
                        level: .warning
                    ))
                }
            }
            prepared.append(PreparedAccount(id: account.accountID, entries: entries, warnings: warnings))
        }
        return prepared
    }

    private func allocate(
        _ accounts: [PreparedAccount],
        stats: inout ParseStats
    ) -> AllocationResult {
        var allocations = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, FileAggregate.empty) }
        )
        var claims: [String: ClaimedRecord] = [:]
        var ambiguousKeys = 0
        var ambiguousOwnerIDs: Set<String> = []

        for account in accounts {
            for entry in account.entries {
                merge(entry.unkeyedAggregate, into: &allocations[account.id, default: .empty])
                for (key, record) in entry.recordsByID {
                    guard var claimed = claims[key] else {
                        claims[key] = ClaimedRecord(record: record, ownerID: account.id, ambiguous: false)
                        accumulate(into: &allocations[account.id, default: .empty], record: record)
                        continue
                    }

                    stats.duplicateKeys += 1
                    if claimed.ownerID != account.id, !claimed.ambiguous {
                        claimed.ambiguous = true
                        ambiguousKeys += 1
                        ambiguousOwnerIDs.insert(claimed.ownerID)
                    }
                    if shouldReplace(claimed.record, with: record) {
                        stats.corrections += 1
                        accumulate(
                            into: &allocations[claimed.ownerID, default: .empty],
                            record: claimed.record,
                            multiplier: -1
                        )
                        accumulate(
                            into: &allocations[claimed.ownerID, default: .empty],
                            record: record
                        )
                        claimed.record = record
                    }
                    claims[key] = claimed
                }
            }
        }
        return AllocationResult(
            byAccountID: allocations,
            ambiguousKeys: ambiguousKeys,
            ambiguousOwnerIDs: ambiguousOwnerIDs,
            claimCount: claims.count
        )
    }

    /// Explicit hook for the view-model/provider recreation path on timezone changes.
    public func updateCalendar(_ calendar: Calendar) {
        guard CalendarIdentity(calendar) != calendarIdentity else { return }
        self.calendar = calendar
        calendarIdentity = CalendarIdentity(calendar)
        fileCache.removeAll(keepingCapacity: true)
        didMutateFileCache()
    }

    private struct PreparedAccount {
        let id: String
        let entries: [FileCacheEntry]
        let warnings: [ProviderWarning]
    }

    private struct ClaimedRecord {
        var record: ClaudeUsageRecord
        let ownerID: String
        var ambiguous: Bool
    }

    private struct AllocationResult {
        let byAccountID: [String: FileAggregate]
        let ambiguousKeys: Int
        let ambiguousOwnerIDs: Set<String>
        let claimCount: Int
    }

    private struct AllocationAccountMembership: Equatable {
        let id: String
        let paths: [String]
    }

    private struct AllocationCacheKey: Equatable {
        let generation: UInt64
        let accounts: [AllocationAccountMembership]
    }

    private struct AllocationCache {
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

    func accumulate(
        into aggregate: inout FileAggregate,
        record: ClaudeUsageRecord,
        multiplier: Int = 1
    ) {
        let usage = adjusted(
            aggregate.lifetime,
            by: record,
            multiplier: multiplier,
            overflowed: &aggregate.arithmeticOverflowed
        )
        aggregate.lifetime = usage

        guard let timestamp = record.timestamp else { return }
        let day = calendar.startOfDay(for: timestamp)
        let adjustedDay = adjusted(
            aggregate.dailyUsage[day] ?? UsageWindows.emptyUsage(.localParsed),
            by: record,
            multiplier: multiplier,
            overflowed: &aggregate.arithmeticOverflowed
        )
        if adjustedDay.totalTokens == 0 {
            aggregate.dailyUsage.removeValue(forKey: day)
        } else {
            aggregate.dailyUsage[day] = adjustedDay
        }

        guard let hour = UsageWindows.hourStart(for: timestamp, calendar: calendar),
              record.totalTokens > 0 else { return }
        let contribution = TokenArithmetic.multiplied(
            record.totalTokens,
            by: multiplier,
            overflowed: &aggregate.arithmeticOverflowed
        )
        aggregate.hourlyTotals[hour] = TokenArithmetic.adding(
            aggregate.hourlyTotals[hour, default: 0],
            contribution,
            overflowed: &aggregate.arithmeticOverflowed
        )
        if aggregate.hourlyTotals[hour] == 0 { aggregate.hourlyTotals.removeValue(forKey: hour) }
    }

    private func adjusted(
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
            reasoningTokens: usage.reasoningTokens ?? 0,
            confidence: .localParsed
        )
        _ = adjusted.totalTokens(overflowed: &overflowed)
        return adjusted
    }

    private func merge(_ incremental: FileAggregate, into aggregate: inout FileAggregate) {
        aggregate.arithmeticOverflowed = aggregate.arithmeticOverflowed
            || incremental.arithmeticOverflowed
        aggregate.lifetime = aggregate.lifetime.merging(
            incremental.lifetime,
            overflowed: &aggregate.arithmeticOverflowed
        )
        for (day, usage) in incremental.dailyUsage {
            aggregate.dailyUsage[day] = (
                aggregate.dailyUsage[day] ?? UsageWindows.emptyUsage(.localParsed)
            ).merging(usage, overflowed: &aggregate.arithmeticOverflowed)
        }
        for (hour, total) in incremental.hourlyTotals {
            aggregate.hourlyTotals[hour] = TokenArithmetic.adding(
                aggregate.hourlyTotals[hour, default: 0],
                total,
                overflowed: &aggregate.arithmeticOverflowed
            )
        }
    }

    private func apply(
        _ aggregate: FileAggregate,
        to windows: inout UsageWindows,
        hourlyTotals: inout [Date: Int]
    ) {
        windows.accumulate(aggregate.lifetime, timestamp: nil, dailyTotal: 0)
        for (day, usage) in aggregate.dailyUsage {
            windows.accumulate(
                usage,
                timestamp: day,
                dailyTotal: usage.totalTokens ?? 0,
                includeInLifetime: false
            )
        }
        for (hour, total) in aggregate.hourlyTotals {
            guard hour >= windows.hourlyStartDate, hour < windows.nextDayStartDate else { continue }
            hourlyTotals[hour] = TokenArithmetic.adding(hourlyTotals[hour, default: 0], total)
        }
    }

    private func makeAggregate(
        from aggregate: FileAggregate,
        warnings: [ProviderWarning]
    ) -> AggregateUsage {
        var windows = UsageWindows(calendar: calendar, referenceDate: now())
        var hourlyTotals: [Date: Int] = [:]
        apply(aggregate, to: &windows, hourlyTotals: &hourlyTotals)
        let snapshot = windows.snapshot()
        return AggregateUsage(
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            lifetime: snapshot.lifetime,
            dailyTotals: snapshot.dailyTotals,
            hourlyTotals: hourlyTotals.isEmpty ? nil : hourlyTotals,
            warnings: warnings
        )
    }

    private func emptyAggregate(warnings: [ProviderWarning]) -> AggregateUsage {
        makeAggregate(from: .empty, warnings: warnings)
    }

    private func makeAllocationCacheKey(
        for accounts: [AccountLogSources]
    ) -> AllocationCacheKey {
        AllocationCacheKey(
            generation: fileCacheGeneration,
            accounts: accounts.sorted(by: { $0.accountID < $1.accountID }).map { account in
                AllocationAccountMembership(
                    id: account.accountID,
                    paths: account.logSources.map(\.url.path).sorted()
                )
            }
        )
    }

    func didMutateFileCache() {
        fileCacheGeneration &+= 1
        allocationCache = nil
    }

    private func ambiguityWarning(for allocation: AllocationResult) -> ProviderWarning {
        let owners = allocation.ambiguousOwnerIDs.sorted().map(Self.boundedAccountName)
        let ownerDescription: String
        if owners.count <= 2 {
            ownerDescription = owners.joined(separator: " and ")
        } else {
            ownerDescription = owners.prefix(2).joined(separator: ", ")
                + ", and \(owners.count - 2) other accounts"
        }
        let messageNoun = allocation.ambiguousKeys == 1 ? "message was" : "messages were"
        let pathNoun = owners.count == 1 ? "its account path sorts" : "their account paths sort"
        return ProviderWarning(
            message: "Claude history appeared in multiple accounts; \(allocation.ambiguousKeys) shared "
                + "\(messageNoun) counted once under \(ownerDescription) because \(pathNoun) first.",
            level: .warning
        )
    }

    private static func boundedAccountName(_ accountID: String) -> String {
        let name = URL(fileURLWithPath: accountID).lastPathComponent
        guard name.count > 32 else { return name }
        return String(name.prefix(31)) + "…"
    }

    private func invalidateCacheIfEffectiveCalendarChanged() {
        let effectiveIdentity = CalendarIdentity(calendar)
        guard effectiveIdentity != calendarIdentity else { return }
        calendarIdentity = effectiveIdentity
        fileCache.removeAll(keepingCapacity: true)
        didMutateFileCache()
    }

    private func malformedWarning(count: Int, url: URL) -> ProviderWarning {
        ProviderWarning(
            message: "\(url.lastPathComponent): \(count) malformed line(s) skipped",
            level: .warning
        )
    }

    private func arithmeticOverflowWarning() -> ProviderWarning {
        ProviderWarning(
            message: "Claude token totals exceeded the supported integer range and were clamped.",
            level: .warning
        )
    }

}
