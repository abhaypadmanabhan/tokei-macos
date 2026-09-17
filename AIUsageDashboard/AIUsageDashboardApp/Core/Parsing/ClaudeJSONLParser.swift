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
        fileCache = fileCache.filter { path, _ in
            activePaths.contains(path) || FileManager.default.fileExists(atPath: path)
        }

        let allocation = allocate(prepared, stats: &stats)

        var globalWarnings: [ProviderWarning] = []
        if allocation.ambiguousKeys > 0 {
            globalWarnings.append(ProviderWarning(
                message: "Claude history appeared in multiple accounts; "
                    + "\(allocation.ambiguousKeys) message(s) counted once with deterministic account ownership.",
                level: .warning
            ))
        }

        let byAccountID = Dictionary(uniqueKeysWithValues: prepared.map { account in
            let aggregate = allocation.byAccountID[account.id] ?? .empty
            return (account.id, makeAggregate(from: aggregate, warnings: account.warnings))
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
            claimCount: claims.count
        )
    }

    /// Explicit hook for the view-model/provider recreation path on timezone changes.
    public func updateCalendar(_ calendar: Calendar) {
        guard CalendarIdentity(calendar) != calendarIdentity else { return }
        self.calendar = calendar
        calendarIdentity = CalendarIdentity(calendar)
        fileCache.removeAll(keepingCapacity: true)
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
        let claimCount: Int
    }

    struct FileAggregate: Sendable {
        var lifetime: TokenUsage
        var dailyUsage: [Date: TokenUsage]
        var hourlyTotals: [Date: Int]

        static var empty: FileAggregate {
            FileAggregate(
                lifetime: TokenUsage(confidence: .localParsed),
                dailyUsage: [:],
                hourlyTotals: [:]
            )
        }
    }

    func accumulate(
        into aggregate: inout FileAggregate,
        record: ClaudeUsageRecord,
        multiplier: Int = 1
    ) {
        let usage = adjusted(aggregate.lifetime, by: record, multiplier: multiplier)
        aggregate.lifetime = usage

        guard let timestamp = record.timestamp else { return }
        let day = calendar.startOfDay(for: timestamp)
        let adjustedDay = adjusted(
            aggregate.dailyUsage[day] ?? UsageWindows.emptyUsage(.localParsed),
            by: record,
            multiplier: multiplier
        )
        if adjustedDay.totalTokens == 0 {
            aggregate.dailyUsage.removeValue(forKey: day)
        } else {
            aggregate.dailyUsage[day] = adjustedDay
        }

        guard let hour = UsageWindows.hourStart(for: timestamp, calendar: calendar),
              record.totalTokens > 0 else { return }
        aggregate.hourlyTotals[hour, default: 0] += record.totalTokens * multiplier
        if aggregate.hourlyTotals[hour] == 0 { aggregate.hourlyTotals.removeValue(forKey: hour) }
    }

    private func adjusted(
        _ usage: TokenUsage,
        by record: ClaudeUsageRecord,
        multiplier: Int
    ) -> TokenUsage {
        TokenUsage(
            inputTokens: (usage.inputTokens ?? 0) + record.inputTokens * multiplier,
            outputTokens: (usage.outputTokens ?? 0) + record.outputTokens * multiplier,
            cacheReadTokens: (usage.cacheReadTokens ?? 0) + record.cacheReadInputTokens * multiplier,
            cacheCreationTokens: (usage.cacheCreationTokens ?? 0)
                + record.cacheCreationInputTokens * multiplier,
            reasoningTokens: usage.reasoningTokens ?? 0,
            confidence: .localParsed
        )
    }

    private func merge(_ incremental: FileAggregate, into aggregate: inout FileAggregate) {
        aggregate.lifetime = aggregate.lifetime.merging(incremental.lifetime)
        for (day, usage) in incremental.dailyUsage {
            aggregate.dailyUsage[day] = (
                aggregate.dailyUsage[day] ?? UsageWindows.emptyUsage(.localParsed)
            ).merging(usage)
        }
        for (hour, total) in incremental.hourlyTotals {
            aggregate.hourlyTotals[hour, default: 0] += total
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
            hourlyTotals[hour, default: 0] += total
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

    private func invalidateCacheIfEffectiveCalendarChanged() {
        let effectiveIdentity = CalendarIdentity(calendar)
        guard effectiveIdentity != calendarIdentity else { return }
        calendarIdentity = effectiveIdentity
        fileCache.removeAll(keepingCapacity: true)
    }

    private func malformedWarning(count: Int, url: URL) -> ProviderWarning {
        ProviderWarning(
            message: "\(url.lastPathComponent): \(count) malformed line(s) skipped",
            level: .warning
        )
    }

}
