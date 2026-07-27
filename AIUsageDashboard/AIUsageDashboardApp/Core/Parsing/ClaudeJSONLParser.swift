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
        var stats = ParseStats()

        for source in logSources {
            let path = source.url.path
            let currentMod = source.lastModified
            let currentSize = fileSize(of: source.url)

            if let cached = fileCache[path],
               cached.modificationDate == currentMod,
               cached.byteOffset == currentSize {
                stats.hits += 1
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
                    stats.appends += 1
                    stats.bytesRead += currentSize - cached.byteOffset
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
                    stats.fullParses += 1
                    stats.bytesRead += currentSize
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
                    message: "Failed to parse \(source.url.lastPathComponent)",
                    level: .warning
                ))
            }
        }

        // Evict cache entries for files no longer present so the cache can't grow
        // unbounded across a long-running session as Claude rotates project logs.
        //
        // Eviction is by **existence on disk**, not by membership in this call's source
        // list. One parser instance is shared across every Claude account and
        // `ClaudeCodeProvider.fetchSnapshot()` calls this once per account, so a source
        // list is one account's slice of the corpus — never the whole of it. Filtering on
        // that slice made each account's parse evict the other accounts' entries, so every
        // account missed the cache on every refresh and re-read the entire ~800 MB corpus
        // every two seconds. Existence is the property the eviction actually cares about
        // and it does not depend on who is calling.
        let activePaths = Set(logSources.map(\.url.path))
        fileCache = fileCache.filter { path, _ in
            // Anything in this call's list was just stat'd; only the rest needs checking.
            activePaths.contains(path) || FileManager.default.fileExists(atPath: path)
        }

        stats.emit(sources: logSources.count, cacheSize: fileCache.count, seenIDs: seenIDs.count)

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

    // MARK: - Diagnostics

    /// Per-call cache accounting, printed to stderr when `TOKEI_PARSE_DEBUG=1`. The parse
    /// cache is the difference between an idle menu-bar app and a pegged core, so its hit
    /// rate needs to be observable on a real corpus rather than inferred from the code.
    private struct ParseStats {
        var hits = 0
        var appends = 0
        var fullParses = 0
        var bytesRead: UInt64 = 0
        let startedAt = DispatchTime.now()

        func emit(sources: Int, cacheSize: Int, seenIDs: Int) {
            guard ProcessInfo.processInfo.environment["TOKEI_PARSE_DEBUG"] == "1" else { return }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
            let line = "[parse] sources=\(sources) hits=\(hits) appends=\(appends) "
                + "full=\(fullParses) bytesRead=\(bytesRead / 1024)KiB cacheEntries=\(cacheSize) "
                + "seenIDs=\(seenIDs) elapsed=\(String(format: "%.1f", ms))ms\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
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
