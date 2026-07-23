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

    /// Caches per-file aggregates so unchanged logs are not re-parsed on every sync.
    /// The key is the file path; entries are invalidated when the modification date
    /// or file size changes.
    private var fileCache: [String: FileCacheEntry] = [:]

    public init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var seenIDs: Set<String> = []
        var warnings: [ProviderWarning] = []
        var windows = UsageWindows(calendar: calendar, referenceDate: now())
        var hourlyTotals: [Date: Int] = [:]

        for source in logSources {
            let path = source.url.path
            let currentMod = source.lastModified
            let currentSize = fileSize(of: source.url)

            if let cached = fileCache[path],
               cached.modificationDate == currentMod,
               cached.byteOffset == currentSize {
                seenIDs.formUnion(cached.seenIDs)
                apply(cached.aggregate, to: &windows, hourlyTotals: &hourlyTotals)
                if cached.malformedCount > 0 {
                    warnings.append(malformedWarning(count: cached.malformedCount, url: source.url))
                }
                continue
            }

            do {
                var incrementalAggregate = FileAggregate.empty
                var incrementalIDs: Set<String> = []
                var malformedCount = 0
                let parseResult: (malformedCount: Int, finalOffset: UInt64)

                if let cached = fileCache[path],
                   let cachedMod = cached.modificationDate,
                   let currentMod = currentMod,
                   currentMod >= cachedMod,
                   cached.byteOffset <= currentSize,
                   cached.byteOffset > 0 {
                    // The file grew since the last parse (or was appended while we were
                    // not watching). Resume from the previous offset instead of re-reading
                    // the entire file.
                    seenIDs.formUnion(cached.seenIDs)
                    parseResult = try await parseFile(
                        at: source.url,
                        startingAtByte: cached.byteOffset
                    ) { [self] record in
                        if let key = record.dedupeKey {
                            guard seenIDs.insert(key).inserted else { return }
                        }
                        self.accumulate(into: &incrementalAggregate, record: record)
                        if let key = record.dedupeKey {
                            incrementalIDs.insert(key)
                        }
                    }
                    malformedCount = parseResult.malformedCount

                    var updatedAggregate = cached.aggregate
                    merge(incrementalAggregate, into: &updatedAggregate)
                    let updatedEntry = FileCacheEntry(
                        path: path,
                        modificationDate: currentMod,
                        byteOffset: parseResult.finalOffset,
                        aggregate: updatedAggregate,
                        seenIDs: cached.seenIDs.union(incrementalIDs),
                        malformedCount: cached.malformedCount + malformedCount
                    )
                    fileCache[path] = updatedEntry
                    seenIDs.formUnion(updatedEntry.seenIDs)
                    apply(updatedEntry.aggregate, to: &windows, hourlyTotals: &hourlyTotals)
                    if updatedEntry.malformedCount > 0 {
                        warnings.append(malformedWarning(count: updatedEntry.malformedCount, url: source.url))
                    }
                } else {
                    // First sync, rotated, truncated, or touched without growing: parse the
                    // whole file and replace any stale cache entry.
                    parseResult = try await parseFile(at: source.url, startingAtByte: 0) { [self] record in
                        if let key = record.dedupeKey {
                            guard seenIDs.insert(key).inserted else { return }
                        }
                        self.accumulate(into: &incrementalAggregate, record: record)
                        if let key = record.dedupeKey {
                            incrementalIDs.insert(key)
                        }
                    }
                    malformedCount = parseResult.malformedCount

                    let entry = FileCacheEntry(
                        path: path,
                        modificationDate: currentMod,
                        byteOffset: parseResult.finalOffset,
                        aggregate: incrementalAggregate,
                        seenIDs: incrementalIDs,
                        malformedCount: malformedCount
                    )
                    fileCache[path] = entry
                    seenIDs.formUnion(incrementalIDs)
                    apply(incrementalAggregate, to: &windows, hourlyTotals: &hourlyTotals)
                    if malformedCount > 0 {
                        warnings.append(malformedWarning(count: malformedCount, url: source.url))
                    }
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
            hourlyTotals: hourlyTotals.isEmpty ? nil : hourlyTotals,
            warnings: warnings
        )
    }

    // MARK: - Caching

    private struct FileCacheEntry {
        let path: String
        var modificationDate: Date?
        var byteOffset: UInt64
        var aggregate: FileAggregate
        var seenIDs: Set<String>
        var malformedCount: Int
    }

    private struct FileAggregate: Sendable {
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

    private func accumulate(into aggregate: inout FileAggregate, record: ClaudeUsageRecord) {
        let usage = record.toTokenUsage()
        aggregate.lifetime = aggregate.lifetime.merging(usage)

        guard let timestamp = record.timestamp else { return }
        let day = calendar.startOfDay(for: timestamp)
        aggregate.dailyUsage[day] = (aggregate.dailyUsage[day] ?? emptyUsage()).merging(usage)

        guard let hour = hourStart(for: timestamp),
              let total = usage.totalTokens,
              total > 0 else { return }
        aggregate.hourlyTotals[hour, default: 0] += total
    }

    private func merge(_ incremental: FileAggregate, into aggregate: inout FileAggregate) {
        aggregate.lifetime = aggregate.lifetime.merging(incremental.lifetime)
        for (day, usage) in incremental.dailyUsage {
            aggregate.dailyUsage[day] = (aggregate.dailyUsage[day] ?? emptyUsage()).merging(usage)
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
            guard hour >= windows.hourlyStartDate else { continue }
            hourlyTotals[hour, default: 0] += total
        }
    }

    private func fileSize(of url: URL) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    private func malformedWarning(count: Int, url: URL) -> ProviderWarning {
        ProviderWarning(
            message: "\(url.lastPathComponent): \(count) malformed line(s) skipped",
            level: .warning
        )
    }

    private func emptyUsage() -> TokenUsage {
        TokenUsage(
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            confidence: .localParsed
        )
    }

    private func hourStart(for timestamp: Date) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
        return calendar.date(from: components)
    }
}
