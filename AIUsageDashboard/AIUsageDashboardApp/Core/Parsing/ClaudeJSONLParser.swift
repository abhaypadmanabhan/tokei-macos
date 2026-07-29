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

            do {
                // Step 1: bring this file's own aggregate up to date. Nothing here depends
                // on the other files in this call.
                var entry: FileCacheEntry
                if let cached = fileCache[path],
                   cached.modificationDate == currentMod,
                   cached.byteOffset == currentSize {
                    stats.hits += 1
                    entry = cached
                } else if let cached = fileCache[path],
                          let cachedMod = cached.modificationDate,
                          let currentMod,
                          currentMod >= cachedMod,
                          cached.byteOffset <= currentSize,
                          cached.byteOffset > 0 {
                    // The file grew since the last parse (or was appended while we were
                    // not watching). Resume from the previous offset instead of re-reading
                    // the entire file.
                    stats.appends += 1
                    stats.bytesRead += currentSize - cached.byteOffset
                    entry = try await extending(cached, at: source.url, modifiedAt: currentMod)
                } else {
                    // First sync, rotated, truncated, or touched without growing: parse the
                    // whole file and replace any stale cache entry.
                    stats.fullParses += 1
                    stats.bytesRead += currentSize
                    entry = try await freshEntry(for: source.url, modifiedAt: currentMod)
                }

                // Step 2: add it to the call total, minus anything an earlier file in this
                // call already accounted for.
                let contribution = try await contribution(
                    of: &entry,
                    at: source.url,
                    dedupingAgainst: &seenIDs,
                    stats: &stats
                )
                fileCache[path] = entry
                apply(contribution, to: &windows, hourlyTotals: &hourlyTotals)
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
        /// Keys a file shares with one applied earlier in the same call, and the re-reads
        /// spent resolving them. `dupKeys > 0` with `corrections == 0` is the healthy
        /// steady state: overlap detected, memo still valid.
        var duplicateKeys = 0
        var corrections = 0
        let startedAt = DispatchTime.now()

        func emit(sources: Int, cacheSize: Int, seenIDs: Int) {
            guard ProcessInfo.processInfo.environment["TOKEI_PARSE_DEBUG"] == "1" else { return }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
            let line = "[parse] sources=\(sources) hits=\(hits) appends=\(appends) "
                + "full=\(fullParses) bytesRead=\(bytesRead / 1024)KiB cacheEntries=\(cacheSize) "
                + "seenIDs=\(seenIDs) dupKeys=\(duplicateKeys) corrections=\(corrections) "
                + "elapsed=\(String(format: "%.1f", ms))ms\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    // MARK: - Caching

    private struct FileCacheEntry {
        var modificationDate: Date?
        var byteOffset: UInt64
        /// The file's **own** aggregate: every record it contains, deduped only against
        /// other records in the same file. Deliberately independent of what else this
        /// parser has parsed, so the entry means the same thing whichever call, in
        /// whichever order, is served from it.
        var aggregate: FileAggregate
        /// Every dedupe key in the file — again the file's own, not the ones it happened
        /// to claim first.
        var ids: Set<String>
        var malformedCount: Int
        /// Memoized aggregate for the case where this file's keys overlap a file applied
        /// earlier in the call. Recomputing it costs a re-read, so it is kept until the
        /// excluded set actually changes; in a steady state it never does.
        var correction: Correction?

        struct Correction {
            var excluded: Set<String>
            var aggregate: FileAggregate
        }
    }

    /// Parses a file in full and describes it on its own terms.
    private func freshEntry(for url: URL, modifiedAt: Date?) async throws -> FileCacheEntry {
        var aggregate = FileAggregate.empty
        var ids: Set<String> = []
        let result = try await parseFile(at: url, startingAtByte: 0) { [self] record in
            if let key = record.dedupeKey {
                guard ids.insert(key).inserted else { return }
            }
            self.accumulate(into: &aggregate, record: record)
        }
        return FileCacheEntry(
            modificationDate: modifiedAt,
            byteOffset: result.finalOffset,
            aggregate: aggregate,
            ids: ids,
            malformedCount: result.malformedCount,
            correction: nil
        )
    }

    /// Folds the bytes appended since `cached.byteOffset` into the entry.
    private func extending(
        _ cached: FileCacheEntry,
        at url: URL,
        modifiedAt: Date?
    ) async throws -> FileCacheEntry {
        var entry = cached
        var appended = FileAggregate.empty
        // Appended records also extend any memoized correction, so a file that both grows
        // and overlaps another does not pay for a full re-read on every refresh.
        let excluded = cached.correction?.excluded
        var appendedNotExcluded = FileAggregate.empty

        let result = try await parseFile(at: url, startingAtByte: cached.byteOffset) { [self] record in
            let key = record.dedupeKey
            if let key {
                guard entry.ids.insert(key).inserted else { return }
            }
            self.accumulate(into: &appended, record: record)
            if let excluded, key.map({ !excluded.contains($0) }) ?? true {
                self.accumulate(into: &appendedNotExcluded, record: record)
            }
        }

        merge(appended, into: &entry.aggregate)
        if var correction = entry.correction {
            merge(appendedNotExcluded, into: &correction.aggregate)
            entry.correction = correction
        }
        entry.modificationDate = modifiedAt
        entry.byteOffset = result.finalOffset
        entry.malformedCount += result.malformedCount
        return entry
    }

    /// Folds `entry`'s keys into `seen` and returns what this file should add to the call.
    ///
    /// A per-file aggregate is only safely additive across files when the files' key sets
    /// are disjoint, and Claude's logs do not guarantee that: a resumed session copies the
    /// earlier session's records into a new file. So check the property rather than assume
    /// it, and when it does not hold, recompute this file's aggregate without the keys an
    /// earlier file already claimed.
    ///
    /// The check is the same single pass over the file's keys that folding them into
    /// `seen` already required, so the disjoint case — every file, on this machine's
    /// corpus, in the order the provider lists them — costs nothing extra.
    private func contribution(
        of entry: inout FileCacheEntry,
        at url: URL,
        dedupingAgainst seen: inout Set<String>,
        stats: inout ParseStats
    ) async throws -> FileAggregate {
        var duplicated: Set<String> = []
        for id in entry.ids where !seen.insert(id).inserted {
            duplicated.insert(id)
        }

        guard !duplicated.isEmpty else {
            entry.correction = nil
            return entry.aggregate
        }

        stats.duplicateKeys += duplicated.count
        if let correction = entry.correction, correction.excluded == duplicated {
            return correction.aggregate
        }

        stats.corrections += 1
        stats.bytesRead += fileSize(of: url)
        let corrected = try await aggregate(at: url, excluding: duplicated)
        entry.correction = FileCacheEntry.Correction(excluded: duplicated, aggregate: corrected)
        return corrected
    }

    private func aggregate(at url: URL, excluding excluded: Set<String>) async throws -> FileAggregate {
        var aggregate = FileAggregate.empty
        var ids: Set<String> = []
        _ = try await parseFile(at: url, startingAtByte: 0) { [self] record in
            if let key = record.dedupeKey {
                guard !excluded.contains(key), ids.insert(key).inserted else { return }
            }
            self.accumulate(into: &aggregate, record: record)
        }
        return aggregate
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
