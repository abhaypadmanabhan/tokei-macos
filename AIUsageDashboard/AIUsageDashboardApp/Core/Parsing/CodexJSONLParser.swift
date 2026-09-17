import Foundation

public actor CodexJSONLParser {
    struct FileUsage: Sendable {
        let path: String
        let firstEventAt: Date?
        let lastEventAt: Date?
        let lifetime: TokenUsage
        let dailyUsage: [Date: TokenUsage]
        let dailyTotals: [Date: Int]
        let hourlyTotals: [Date: Int]
    }

    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        /// Raw token components keyed by the parser calendar's start of day.
        /// Codex identity attribution consumes these dated totals instead of a
        /// date-relative `today` snapshot so midnight cannot move old usage.
        public let dailyUsage: [Date: TokenUsage]
        public let dailyTotals: [Date: Int]
        public let todayStart: Date
        public let hourlyTotals: [Date: Int]?
        public let quotaWindows: [QuotaWindow]
        public let deltaReportedTotalTokens: Int
        public let finalReportedTotalTokens: Int
        public let warnings: [ProviderWarning]
        let files: [FileUsage]
    }

    private var calendar: Calendar
    private let now: () -> Date

    /// Caches per-file aggregates so unchanged logs are not re-parsed on every sync.
    /// Each entry retains additive usage plus the per-file latest-wins values needed
    /// to reconstruct the global result.
    private var fileCache: [String: FileCacheEntry] = [:]
    private var modelDetectionCache: [String: ModelDetectionCacheEntry] = [:]
    private var modelDetectionFileReadCount = 0
    private var fileReadCount = 0

    public init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var warnings: [ProviderWarning] = []
        let referenceDate = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: referenceDate)
        var dailyUsage: [Date: TokenUsage] = [:]
        var hourlyTotals: [Date: Int] = [:]
        var latestRateLimits: CodexRateLimitSnapshot?
        var deltaReportedTotalTokens = 0
        var finalTotalsBySession: [String: CodexSessionFinalTotal] = [:]
        var arithmeticOverflowed = false
        var files: [FileUsage] = []

        for source in logSources {
            let path = source.url.path
            let currentMetadata = fileMetadata(of: source.url)
            let currentModificationDate = source.lastModified ?? currentMetadata.modificationDate
            let currentSize = currentMetadata.size

            if let cached = fileCache[path],
               cached.modificationDate == currentModificationDate,
               cached.byteOffset == currentSize,
               cached.fileIdentifier == currentMetadata.identifier {
                apply(
                    cached.aggregate,
                    to: &windows,
                    dailyUsage: &dailyUsage,
                    hourlyTotals: &hourlyTotals,
                    latestRateLimits: &latestRateLimits,
                    deltaReportedTotalTokens: &deltaReportedTotalTokens,
                    finalTotalsBySession: &finalTotalsBySession,
                    arithmeticOverflowed: &arithmeticOverflowed
                )
                files.append(fileUsage(path: path, aggregate: cached.aggregate))
                if cached.malformedCount > 0 {
                    warnings.append(malformedWarning(count: cached.malformedCount, url: source.url))
                }
                continue
            }

            do {
                var incrementalAggregate = FileAggregate.empty
                let sessionKey = source.sessionID ?? path
                let parseResult: JSONLParseResult

                if let cached = fileCache[path],
                   let cachedModificationDate = cached.modificationDate,
                   let currentModificationDate,
                   currentModificationDate >= cachedModificationDate,
                   cached.byteOffset < currentSize,
                   cached.byteOffset > 0,
                    cached.fileIdentifier == currentMetadata.identifier,
                    try continuityTail(at: source.url, endingAt: cached.byteOffset)
                    == cached.continuityTail {
                    incrementalAggregate.lastCumulativeUsageBySession =
                        cached.aggregate.lastCumulativeUsageBySession
                    fileReadCount += 1
                    parseResult = try await parseFile(
                        at: source.url,
                        startingAtByte: cached.byteOffset,
                        startingInOversizedRecord: cached.discardingOversizedRecord
                    ) { [self] record in
                        self.accumulate(
                            into: &incrementalAggregate,
                            record: record,
                            sessionKey: sessionKey
                        )
                    }

                    var updatedAggregate = cached.aggregate
                    merge(incrementalAggregate, into: &updatedAggregate)
                    let updatedEntry = FileCacheEntry(
                        modificationDate: currentModificationDate,
                        byteOffset: parseResult.finalOffset,
                        fileIdentifier: currentMetadata.identifier,
                        continuityTail: try continuityTail(
                            at: source.url,
                            endingAt: parseResult.finalOffset
                        ),
                        aggregate: updatedAggregate,
                        malformedCount: cached.malformedCount + parseResult.malformedCount,
                        discardingOversizedRecord: parseResult.discardingOversizedRecord
                    )
                    fileCache[path] = updatedEntry
                    apply(
                        updatedEntry.aggregate,
                        to: &windows,
                        dailyUsage: &dailyUsage,
                        hourlyTotals: &hourlyTotals,
                        latestRateLimits: &latestRateLimits,
                        deltaReportedTotalTokens: &deltaReportedTotalTokens,
                        finalTotalsBySession: &finalTotalsBySession,
                        arithmeticOverflowed: &arithmeticOverflowed
                    )
                    files.append(fileUsage(path: path, aggregate: updatedEntry.aggregate))
                    if updatedEntry.malformedCount > 0 {
                        warnings.append(malformedWarning(
                            count: updatedEntry.malformedCount,
                            url: source.url
                        ))
                    }
                } else {
                    fileReadCount += 1
                    parseResult = try await parseFile(
                        at: source.url,
                        startingAtByte: 0
                    ) { [self] record in
                        self.accumulate(
                            into: &incrementalAggregate,
                            record: record,
                            sessionKey: sessionKey
                        )
                    }

                    let entry = FileCacheEntry(
                        modificationDate: currentModificationDate,
                        byteOffset: parseResult.finalOffset,
                        fileIdentifier: currentMetadata.identifier,
                        continuityTail: try continuityTail(
                            at: source.url,
                            endingAt: parseResult.finalOffset
                        ),
                        aggregate: incrementalAggregate,
                        malformedCount: parseResult.malformedCount,
                        discardingOversizedRecord: parseResult.discardingOversizedRecord
                    )
                    fileCache[path] = entry
                    apply(
                        entry.aggregate,
                        to: &windows,
                        dailyUsage: &dailyUsage,
                        hourlyTotals: &hourlyTotals,
                        latestRateLimits: &latestRateLimits,
                        deltaReportedTotalTokens: &deltaReportedTotalTokens,
                        finalTotalsBySession: &finalTotalsBySession,
                        arithmeticOverflowed: &arithmeticOverflowed
                    )
                    files.append(fileUsage(path: path, aggregate: entry.aggregate))
                    if entry.malformedCount > 0 {
                        warnings.append(malformedWarning(count: entry.malformedCount, url: source.url))
                    }
                }
            } catch {
                warnings.append(ProviderWarning(
                    message: "Failed to parse \(source.url.lastPathComponent): \(error.localizedDescription)",
                    level: .warning
                ))
            }
        }

        // Evict cache entries for files no longer present so the cache can't grow
        // unbounded — Codex creates a new per-session log file continually, and a
        // long-running menu-bar app would otherwise retain every one ever seen.
        //
        // CodexProvider parses one account slice at a time. Retain entries outside this
        // slice while their files still exist, or alternating accounts evict and re-read
        // each other's cache on every refresh. This mirrors Claude's multi-root fix.
        // The cross-file dedup ordering bug the Claude fix then exposed does not apply:
        // Codex aggregates per session file with no shared dedupe-key set.
        let activePaths = Set(logSources.map(\.url.path))
        fileCache = fileCache.filter { path, _ in
            activePaths.contains(path) || FileManager.default.fileExists(atPath: path)
        }

        let finalReportedTotalTokens = TokenArithmetic.sum(
            finalTotalsBySession.values.map(\.totalTokens),
            overflowed: &arithmeticOverflowed
        )
        if arithmeticOverflowed || windows.arithmeticOverflowed {
            warnings.append(arithmeticOverflowWarning())
        }
        let snapshot = windows.snapshot()
        return AggregateUsage(
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            lifetime: snapshot.lifetime,
            dailyUsage: dailyUsage,
            dailyTotals: snapshot.dailyTotals,
            todayStart: calendar.startOfDay(for: referenceDate),
            hourlyTotals: hourlyTotals.isEmpty ? nil : hourlyTotals,
            quotaWindows: quotaWindows(from: latestRateLimits, referenceDate: referenceDate),
            deltaReportedTotalTokens: deltaReportedTotalTokens,
            finalReportedTotalTokens: finalReportedTotalTokens,
            warnings: warnings,
            files: files
        )
    }

    // MARK: - Caching

    private struct FileCacheEntry {
        var modificationDate: Date?
        var byteOffset: UInt64
        var fileIdentifier: UInt64?
        var continuityTail: Data
        var aggregate: FileAggregate
        var malformedCount: Int
        var discardingOversizedRecord: Bool
    }

    private func continuityTail(at url: URL, endingAt byteOffset: UInt64) throws -> Data {
        let tailLength = min(byteOffset, 4 * 1024)
        guard tailLength > 0 else { return Data() }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }
        try fileHandle.seek(toOffset: byteOffset - tailLength)
        return try fileHandle.read(upToCount: Int(tailLength)) ?? Data()
    }

    private struct FileAggregate: Sendable {
        var lifetime: TokenUsage
        var dailyUsage: [Date: TokenUsage]
        var dailyReportedTotals: [Date: Int]
        var hourlyTotals: [Date: Int]
        var deltaReportedTotalTokens: Int
        var finalTotalsBySession: [String: CodexSessionFinalTotal]
        var latestRateLimits: CodexRateLimitSnapshot?
        var lastCumulativeUsageBySession: [String: CodexCumulativeUsageSignature]
        var firstEventAt: Date?
        var lastEventAt: Date?
        var arithmeticOverflowed: Bool

        static var empty: FileAggregate {
            FileAggregate(
                lifetime: TokenUsage(confidence: .localParsed),
                dailyUsage: [:],
                dailyReportedTotals: [:],
                hourlyTotals: [:],
                deltaReportedTotalTokens: 0,
                finalTotalsBySession: [:],
                latestRateLimits: nil,
                lastCumulativeUsageBySession: [:],
                firstEventAt: nil,
                lastEventAt: nil,
                arithmeticOverflowed: false
            )
        }
    }

    private func accumulate(
        into aggregate: inout FileAggregate,
        record: CodexUsageRecord,
        sessionKey: String
    ) {
        if let timestamp = record.timestamp {
            aggregate.firstEventAt = min(aggregate.firstEventAt ?? timestamp, timestamp)
            aggregate.lastEventAt = max(aggregate.lastEventAt ?? timestamp, timestamp)
        }
        guard record.contributesUsage else { return }

        let repeatsCumulativeUsage: Bool
        if let signature = record.cumulativeUsageSignature {
            repeatsCumulativeUsage = aggregate.lastCumulativeUsageBySession[sessionKey] == signature
            aggregate.lastCumulativeUsageBySession[sessionKey] = signature
        } else {
            repeatsCumulativeUsage = false
        }
        let deltaUsage = repeatsCumulativeUsage
            ? UsageWindows.emptyUsage(.localParsed)
            : record.deltaUsage
        let deltaReportedTotalTokens = repeatsCumulativeUsage ? 0 : record.deltaReportedTotalTokens

        aggregate.lifetime = aggregate.lifetime.merging(
            deltaUsage,
            overflowed: &aggregate.arithmeticOverflowed
        )
        aggregate.deltaReportedTotalTokens = TokenArithmetic.adding(
            aggregate.deltaReportedTotalTokens,
            deltaReportedTotalTokens,
            overflowed: &aggregate.arithmeticOverflowed
        )

        recordLatestSnapshots(into: &aggregate, from: record, sessionKey: sessionKey)

        guard let timestamp = record.timestamp else { return }
        let day = calendar.startOfDay(for: timestamp)
        aggregate.dailyUsage[day] = (
            aggregate.dailyUsage[day] ?? UsageWindows.emptyUsage(.localParsed)
        ).merging(deltaUsage, overflowed: &aggregate.arithmeticOverflowed)
        aggregate.dailyReportedTotals[day] = TokenArithmetic.adding(
            aggregate.dailyReportedTotals[day, default: 0],
            deltaReportedTotalTokens,
            overflowed: &aggregate.arithmeticOverflowed
        )

        guard deltaReportedTotalTokens > 0,
              let hour = UsageWindows.hourStart(for: timestamp, calendar: calendar) else { return }
        aggregate.hourlyTotals[hour] = TokenArithmetic.adding(
            aggregate.hourlyTotals[hour, default: 0],
            deltaReportedTotalTokens,
            overflowed: &aggregate.arithmeticOverflowed
        )
    }

    private func recordLatestSnapshots(
        into aggregate: inout FileAggregate,
        from record: CodexUsageRecord,
        sessionKey: String
    ) {
        if let cumulativeTotal = record.cumulativeReportedTotalTokens {
            let current = aggregate.finalTotalsBySession[sessionKey]
            if current == nil || record.isNewerThan(current!) {
                aggregate.finalTotalsBySession[sessionKey] = CodexSessionFinalTotal(
                    timestamp: record.timestamp,
                    totalTokens: cumulativeTotal
                )
            }
        }
        if let rateLimits = record.rateLimits,
           aggregate.latestRateLimits == nil
            || rateLimits.timestamp > aggregate.latestRateLimits!.timestamp {
            aggregate.latestRateLimits = rateLimits
        }
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
        for (day, total) in incremental.dailyReportedTotals {
            aggregate.dailyReportedTotals[day] = TokenArithmetic.adding(
                aggregate.dailyReportedTotals[day, default: 0],
                total,
                overflowed: &aggregate.arithmeticOverflowed
            )
        }
        for (hour, total) in incremental.hourlyTotals {
            aggregate.hourlyTotals[hour] = TokenArithmetic.adding(
                aggregate.hourlyTotals[hour, default: 0],
                total,
                overflowed: &aggregate.arithmeticOverflowed
            )
        }
        aggregate.deltaReportedTotalTokens = TokenArithmetic.adding(
            aggregate.deltaReportedTotalTokens,
            incremental.deltaReportedTotalTokens,
            overflowed: &aggregate.arithmeticOverflowed
        )

        for (sessionKey, candidate) in incremental.finalTotalsBySession {
            let current = aggregate.finalTotalsBySession[sessionKey]
            if current == nil || candidate.isNewerThan(current!) {
                aggregate.finalTotalsBySession[sessionKey] = candidate
            }
        }
        if let candidate = incremental.latestRateLimits,
           aggregate.latestRateLimits == nil
            || candidate.timestamp > aggregate.latestRateLimits!.timestamp {
            aggregate.latestRateLimits = candidate
        }
        for (sessionKey, signature) in incremental.lastCumulativeUsageBySession {
            aggregate.lastCumulativeUsageBySession[sessionKey] = signature
        }
        if let firstEventAt = incremental.firstEventAt {
            aggregate.firstEventAt = min(aggregate.firstEventAt ?? firstEventAt, firstEventAt)
        }
        if let lastEventAt = incremental.lastEventAt {
            aggregate.lastEventAt = max(aggregate.lastEventAt ?? lastEventAt, lastEventAt)
        }
    }

    private func fileUsage(path: String, aggregate: FileAggregate) -> FileUsage {
        FileUsage(
            path: path,
            firstEventAt: aggregate.firstEventAt,
            lastEventAt: aggregate.lastEventAt,
            lifetime: aggregate.lifetime,
            dailyUsage: aggregate.dailyUsage,
            dailyTotals: aggregate.dailyReportedTotals,
            hourlyTotals: aggregate.hourlyTotals
        )
    }

    private func apply(
        _ aggregate: FileAggregate,
        to windows: inout UsageWindows,
        dailyUsage: inout [Date: TokenUsage],
        hourlyTotals: inout [Date: Int],
        latestRateLimits: inout CodexRateLimitSnapshot?,
        deltaReportedTotalTokens: inout Int,
        finalTotalsBySession: inout [String: CodexSessionFinalTotal],
        arithmeticOverflowed: inout Bool
    ) {
        arithmeticOverflowed = arithmeticOverflowed || aggregate.arithmeticOverflowed
        windows.accumulate(aggregate.lifetime, timestamp: nil, dailyTotal: 0)
        for (day, usage) in aggregate.dailyUsage {
            dailyUsage[day] = (
                dailyUsage[day] ?? UsageWindows.emptyUsage(usage.confidence)
            ).merging(usage, overflowed: &arithmeticOverflowed)
            windows.accumulate(
                usage,
                timestamp: day,
                dailyTotal: aggregate.dailyReportedTotals[day] ?? 0,
                includeInLifetime: false
            )
        }
        for (hour, total) in aggregate.hourlyTotals {
            guard hour >= windows.hourlyStartDate else { continue }
            hourlyTotals[hour] = TokenArithmetic.adding(
                hourlyTotals[hour, default: 0],
                total,
                overflowed: &arithmeticOverflowed
            )
        }
        deltaReportedTotalTokens = TokenArithmetic.adding(
            deltaReportedTotalTokens,
            aggregate.deltaReportedTotalTokens,
            overflowed: &arithmeticOverflowed
        )

        for (sessionKey, candidate) in aggregate.finalTotalsBySession {
            let current = finalTotalsBySession[sessionKey]
            if current == nil || candidate.isNewerThan(current!) {
                finalTotalsBySession[sessionKey] = candidate
            }
        }
        if let candidate = aggregate.latestRateLimits,
           latestRateLimits == nil || candidate.timestamp > latestRateLimits!.timestamp {
            latestRateLimits = candidate
        }
    }

    private struct FileMetadata {
        let size: UInt64
        let identifier: UInt64?
        let modificationDate: Date?
    }

    private func fileMetadata(of url: URL) -> FileMetadata {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return FileMetadata(size: 0, identifier: nil, modificationDate: nil)
        }
        let identifier = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        return FileMetadata(
            size: size.uint64Value,
            identifier: identifier,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }

    private func malformedWarning(count: Int, url: URL) -> ProviderWarning {
        ProviderWarning(
            message: "\(url.lastPathComponent): \(count) malformed line(s) skipped",
            level: .warning
        )
    }

    private func arithmeticOverflowWarning() -> ProviderWarning {
        ProviderWarning(
            message: "Codex token totals exceeded the supported integer range and were clamped.",
            level: .warning
        )
    }

    /// Rebuild cached day/hour buckets after a timezone or calendar-rule change.
    public func updateCalendar(_ calendar: Calendar) {
        guard self.calendar.identifier != calendar.identifier
            || self.calendar.timeZone.identifier != calendar.timeZone.identifier
            || self.calendar.firstWeekday != calendar.firstWeekday
            || self.calendar.minimumDaysInFirstWeek != calendar.minimumDaysInFirstWeek
            || self.calendar.locale?.identifier != calendar.locale?.identifier else { return }
        self.calendar = calendar
        fileCache.removeAll(keepingCapacity: true)
    }

    func fileReadCountForTesting() -> Int {
        fileReadCount
    }

}

enum CodexLineParseOutcome: Sendable {
    case usage(CodexUsageRecord)
    case skipped
    case malformed
}

struct CodexUsageRecord: Sendable {
    let timestamp: Date?
    let contributesUsage: Bool
    let deltaUsage: TokenUsage
    let deltaReportedTotalTokens: Int
    let cumulativeReportedTotalTokens: Int?
    let cumulativeUsageSignature: CodexCumulativeUsageSignature?
    let rateLimits: CodexRateLimitSnapshot?

    func isNewerThan(_ finalTotal: CodexSessionFinalTotal) -> Bool {
        switch (timestamp, finalTotal.timestamp) {
        case let (lhs?, rhs?):
            return lhs >= rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return true
        }
    }
}

struct CodexCumulativeUsageSignature: Sendable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedInputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?
}

struct CodexSessionFinalTotal: Sendable {
    let timestamp: Date?
    let totalTokens: Int

    func isNewerThan(_ other: CodexSessionFinalTotal) -> Bool {
        switch (timestamp, other.timestamp) {
        case let (lhs?, rhs?):
            return lhs >= rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return true
        }
    }
}

struct CodexRateLimitSnapshot: Sendable {
    let timestamp: Date
    let planType: String?
    let primary: CodexRateLimit?
    let secondary: CodexRateLimit?
    let spendControlIndividualLimit: CodexSpendControlLimit?
    let credits: CodexCreditsSnapshot?
    let rateLimitResetCredits: CodexResetBankSnapshot?
}

struct CodexRateLimit: Sendable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let limitWindowSeconds: Int?
    let windowDurationMins: Int?
    let resetsAt: Date?
    let resetsInSeconds: Int?
}

struct CodexSpendControlLimit: Sendable {
    let limit: String?
    let used: String?
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetsAt: Date?
}

struct CodexCreditsSnapshot: Sendable {
    let usedPercent: Double?
    let balance: Double?
    let limit: Double?
}

struct CodexResetBankSnapshot: Sendable {
    let available: Int?
    let count: Int?
}

private enum CodexWindowDuration {
    static let sessionSeconds = 18_000
    static let weeklySeconds = 604_800
    static let toleranceSeconds = 3_600
}

extension CodexJSONLParser {
    /// Best-effort scan for the most recently configured model, read from `turn_context`
    /// events' `payload.model`. Read-only: does not affect `parse(logSources:)` or the
    /// shape of `AggregateUsage`. This is a separate pass over the log files from
    /// `parse(logSources:)`'s token-count scan, so sources are walked newest-first
    /// (they're expected pre-sorted chronologically, as `CodexProvider.discoverLogSources()`
    /// returns them) and stop at the first file with a `turn_context` event — avoiding a
    /// second full read of every session file just to find the most recent model.
    public func detectLatestModel(logSources: [LogSource]) async -> String? {
        let activePaths = Set(logSources.map(\.url.path))
        defer {
            modelDetectionCache = modelDetectionCache.filter { activePaths.contains($0.key) }
        }
        for source in logSources.reversed() {
            let metadata = fileMetadata(of: source.url)
            let stamp = ModelSourceStamp(
                fileIdentifier: metadata.identifier,
                modificationDate: metadata.modificationDate ?? source.lastModified,
                size: metadata.size
            )
            let cached = modelDetectionCache[source.url.path]
            let model: String?
            if cached?.stamp == stamp {
                model = cached?.model
            } else {
                model = await latestModel(inFileAt: source.url)
                modelDetectionCache[source.url.path] = ModelDetectionCacheEntry(
                    stamp: stamp,
                    model: model
                )
            }
            if let model {
                return model
            }
        }
        return nil
    }

    func modelDetectionFileReadCountForTesting() -> Int {
        modelDetectionFileReadCount
    }

    private func latestModel(inFileAt url: URL) async -> String? {
        modelDetectionFileReadCount += 1
        var model: String?
        do {
            for try await line in url.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "turn_context",
                      let payload = json["payload"] as? [String: Any],
                      let payloadModel = payload["model"] as? String else { continue }
                model = payloadModel
            }
        } catch {
            return nil
        }
        return model
    }

    private struct ModelSourceStamp: Equatable {
        let fileIdentifier: UInt64?
        let modificationDate: Date?
        let size: UInt64
    }

    private struct ModelDetectionCacheEntry {
        let stamp: ModelSourceStamp
        let model: String?
    }

    func parseLine(_ data: Data) -> CodexLineParseOutcome {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }

        let timestamp = JSONLDateParsing.parseTimestamp(from: json)

        guard json["type"] as? String == "event_msg",
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "token_count" else {
            guard let timestamp else { return .skipped }
            return .usage(CodexUsageRecord(
                timestamp: timestamp,
                contributesUsage: false,
                deltaUsage: UsageWindows.emptyUsage(.localParsed),
                deltaReportedTotalTokens: 0,
                cumulativeReportedTotalTokens: nil,
                cumulativeUsageSignature: nil,
                rateLimits: nil
            ))
        }

        guard let info = payload["info"] as? [String: Any],
              let lastUsage = info["last_token_usage"] as? [String: Any] else {
            return .malformed
        }

        guard let deltaUsage = tokenUsage(from: lastUsage) else { return .malformed }
        let deltaReportedValue = CheckedNumericConversion.optionalTokenCount(lastUsage["total_tokens"])
        guard deltaReportedValue.isValid else { return .malformed }
        let deltaReportedTotal = deltaReportedValue.value ?? deltaUsage.totalTokens ?? 0
        let cumulative = cumulativeUsageSignature(from: info)
        guard cumulative.isValid else { return .malformed }
        let cumulativeSignature = cumulative.value
        let cumulativeReportedTotal = cumulativeSignature?.totalTokens

        return .usage(CodexUsageRecord(
            timestamp: timestamp,
            contributesUsage: true,
            deltaUsage: deltaUsage,
            deltaReportedTotalTokens: deltaReportedTotal,
            cumulativeReportedTotalTokens: cumulativeReportedTotal,
            cumulativeUsageSignature: cumulativeSignature,
            rateLimits: rateLimits(from: payload["rate_limits"], timestamp: timestamp)
        ))
    }

    private func cumulativeUsageSignature(
        from info: [String: Any]
    ) -> (isValid: Bool, value: CodexCumulativeUsageSignature?) {
        guard let usage = info["total_token_usage"] as? [String: Any] else {
            return (true, nil)
        }
        let input = CheckedNumericConversion.optionalTokenCount(usage["input_tokens"])
        let output = CheckedNumericConversion.optionalTokenCount(usage["output_tokens"])
        let cached = CheckedNumericConversion.optionalTokenCount(usage["cached_input_tokens"])
        let reasoning = CheckedNumericConversion.optionalTokenCount(usage["reasoning_output_tokens"])
        let total = CheckedNumericConversion.optionalTokenCount(usage["total_tokens"])
        guard input.isValid, output.isValid, cached.isValid, reasoning.isValid, total.isValid else {
            return (false, nil)
        }
        let signature = CodexCumulativeUsageSignature(
            inputTokens: input.value,
            outputTokens: output.value,
            cachedInputTokens: cached.value,
            reasoningOutputTokens: reasoning.value,
            totalTokens: total.value
        )
        let hasValue = signature.inputTokens != nil || signature.outputTokens != nil
            || signature.cachedInputTokens != nil || signature.reasoningOutputTokens != nil
            || signature.totalTokens != nil
        return (true, hasValue ? signature : nil)
    }

    private func tokenUsage(from json: [String: Any]) -> TokenUsage? {
        guard let rawInput = CheckedNumericConversion.tokenCount(json["input_tokens"]),
              let rawOutput = CheckedNumericConversion.tokenCount(json["output_tokens"]),
              let cacheRead = CheckedNumericConversion.tokenCount(json["cached_input_tokens"]),
              let reasoning = CheckedNumericConversion.tokenCount(json["reasoning_output_tokens"]) else {
            return nil
        }

        var overflowed = false
        let input = max(0, TokenArithmetic.subtracting(rawInput, cacheRead, overflowed: &overflowed))
        let output = max(0, TokenArithmetic.subtracting(rawOutput, reasoning, overflowed: &overflowed))
        _ = TokenArithmetic.sum([input, output, cacheRead, reasoning], overflowed: &overflowed)
        guard !overflowed else { return nil }

        return TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: 0,
            reasoningTokens: reasoning,
            confidence: .localParsed
        )
    }

    private func rateLimits(from value: Any?, timestamp: Date?) -> CodexRateLimitSnapshot? {
        guard let timestamp,
              let json = value as? [String: Any] else {
            return nil
        }

        let spendControl = json["spend_control"] as? [String: Any]
        return CodexRateLimitSnapshot(
            timestamp: timestamp,
            planType: json["plan_type"] as? String,
            primary: rateLimit(from: json["primary"], eventTimestamp: timestamp),
            secondary: rateLimit(from: json["secondary"], eventTimestamp: timestamp),
            spendControlIndividualLimit: spendControlLimit(from: spendControl?["individual_limit"]),
            credits: creditsSnapshot(from: json["credits"]),
            rateLimitResetCredits: resetBankSnapshot(from: json["rate_limit_reset_credits"])
        )
    }

    private func rateLimit(from value: Any?, eventTimestamp: Date) -> CodexRateLimit? {
        guard let json = value as? [String: Any] else {
            return nil
        }
        let resetsInSeconds = intValue(json["resets_in_seconds"])
        let resetsAt = intValue(json["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? resetsInSeconds.map { eventTimestamp.addingTimeInterval(TimeInterval($0)) }
        return CodexRateLimit(
            usedPercent: doubleValue(json["used_percent"]),
            windowMinutes: intValue(json["window_minutes"]),
            limitWindowSeconds: intValue(json["limit_window_seconds"]),
            windowDurationMins: intValue(json["window_duration_mins"]),
            resetsAt: resetsAt,
            resetsInSeconds: resetsInSeconds
        )
    }

    private func spendControlLimit(from value: Any?) -> CodexSpendControlLimit? {
        guard let json = value as? [String: Any] else { return nil }
        return CodexSpendControlLimit(
            limit: json["limit"] as? String,
            used: json["used"] as? String,
            usedPercent: doubleValue(json["used_percent"]),
            remainingPercent: doubleValue(json["remaining_percent"]),
            resetsAt: intValue(json["reset_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func creditsSnapshot(from value: Any?) -> CodexCreditsSnapshot? {
        guard let json = value as? [String: Any] else { return nil }
        return CodexCreditsSnapshot(
            usedPercent: doubleValue(json["used_percent"]),
            balance: doubleValue(json["balance"]),
            limit: doubleValue(json["limit"])
        )
    }

    private func resetBankSnapshot(from value: Any?) -> CodexResetBankSnapshot? {
        guard let json = value as? [String: Any] else { return nil }
        return CodexResetBankSnapshot(
            available: intValue(json["available"]),
            count: intValue(json["count"])
        )
    }

    private func windowDurationSeconds(for rateLimit: CodexRateLimit) -> Int? {
        if let seconds = rateLimit.limitWindowSeconds { return seconds }
        if let minutes = rateLimit.windowMinutes { return minutes * 60 }
        if let minutes = rateLimit.windowDurationMins { return minutes * 60 }
        return nil
    }

    private func quotaWindowType(
        for rateLimit: CodexRateLimit,
        positionalFallback: QuotaWindowType
    ) -> QuotaWindowType {
        guard let seconds = windowDurationSeconds(for: rateLimit) else {
            return positionalFallback
        }
        let sessionDistance = abs(seconds - CodexWindowDuration.sessionSeconds)
        let weeklyDistance = abs(seconds - CodexWindowDuration.weeklySeconds)
        if sessionDistance <= CodexWindowDuration.toleranceSeconds,
           sessionDistance <= weeklyDistance {
            return .session
        }
        if weeklyDistance <= CodexWindowDuration.toleranceSeconds {
            return .weekly
        }
        return positionalFallback
    }

    private func quotaWindows(
        from snapshot: CodexRateLimitSnapshot?,
        referenceDate: Date
    ) -> [QuotaWindow] {
        guard let snapshot else { return [] }
        let confidence: MetricConfidence = referenceDate.timeIntervalSince(snapshot.timestamp) > 86_400
            ? .estimated
            : .providerReported

        var windows: [QuotaWindow] = []
        var sessionWindow: QuotaWindow?
        var weeklyWindow: QuotaWindow?

        if let primary = snapshot.primary {
            let type = quotaWindowType(for: primary, positionalFallback: .session)
            let window = quotaWindow(
                type: type,
                rateLimit: primary,
                planType: snapshot.planType,
                confidence: confidence,
                observedAt: snapshot.timestamp
            )
            switch type {
            case .session: sessionWindow = window
            case .weekly: weeklyWindow = window
            default: windows.append(window)
            }
        }
        if let secondary = snapshot.secondary {
            let type = quotaWindowType(for: secondary, positionalFallback: .weekly)
            let window = quotaWindow(
                type: type,
                rateLimit: secondary,
                planType: snapshot.planType,
                confidence: confidence,
                observedAt: snapshot.timestamp
            )
            switch type {
            case .session where sessionWindow == nil: sessionWindow = window
            case .weekly where weeklyWindow == nil: weeklyWindow = window
            case .session: sessionWindow = window
            case .weekly: weeklyWindow = window
            default: windows.append(window)
            }
        }
        if let sessionWindow { windows.append(sessionWindow) }
        if let weeklyWindow { windows.append(weeklyWindow) }

        if let individualLimit = snapshot.spendControlIndividualLimit {
            windows.append(individualLimitWindow(
                from: individualLimit,
                planType: snapshot.planType,
                confidence: confidence,
                observedAt: snapshot.timestamp
            ))
        }
        if let credits = snapshot.credits {
            if let window = purchasableCreditsWindow(
                from: credits,
                planType: snapshot.planType,
                confidence: confidence,
                observedAt: snapshot.timestamp
            ) {
                windows.append(window)
            }
        }
        if let resetBank = snapshot.rateLimitResetCredits {
            if let window = resetBankWindow(
                from: resetBank,
                planType: snapshot.planType,
                confidence: confidence,
                observedAt: snapshot.timestamp
            ) {
                windows.append(window)
            }
        }
        return windows
    }

    private func quotaWindow(
        type: QuotaWindowType,
        rateLimit: CodexRateLimit,
        planType: String?,
        confidence: MetricConfidence,
        observedAt: Date
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .codex,
            type: type,
            used: rateLimit.usedPercent,
            limit: 100,
            remaining: rateLimit.usedPercent.map { 100 - $0 },
            resetAt: rateLimit.resetsAt,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), \(sourceWindowLabel(for: rateLimit, type: type)))",
            observedAt: observedAt
        )
    }

    private func individualLimitWindow(
        from limit: CodexSpendControlLimit,
        planType: String?,
        confidence: MetricConfidence,
        observedAt: Date
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .codex,
            type: .credits,
            used: limit.usedPercent,
            limit: 100,
            remaining: limit.remainingPercent,
            resetAt: limit.resetsAt,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), monthly credit limit)",
            label: "Monthly credit limit",
            bucketKey: "spend_control_individual_limit",
            observedAt: observedAt
        )
    }

    private func purchasableCreditsWindow(
        from credits: CodexCreditsSnapshot,
        planType: String?,
        confidence: MetricConfidence,
        observedAt: Date
    ) -> QuotaWindow? {
        guard credits.usedPercent != nil || credits.balance != nil || credits.limit != nil else {
            return nil
        }
        let used = credits.usedPercent
        let limit = credits.limit ?? (used != nil ? 100 : nil)
        let remaining: Double?
        if let used, let limit {
            remaining = limit - used
        } else {
            remaining = credits.balance
        }
        return QuotaWindow(
            providerID: .codex,
            type: .credits,
            // `balance` is credits REMAINING, not used — never place it in `used`
            // (that would render an 80-of-100-remaining balance as "80% used").
            // Leave `used` nil when only a balance is known; `remaining` carries it.
            used: used,
            limit: limit,
            remaining: remaining,
            resetAt: nil,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), purchasable credits)",
            label: "Purchasable credits",
            bucketKey: "credits",
            observedAt: observedAt
        )
    }

    private func resetBankWindow(
        from resetBank: CodexResetBankSnapshot,
        planType: String?,
        confidence: MetricConfidence,
        observedAt: Date
    ) -> QuotaWindow? {
        guard let count = resetBank.available ?? resetBank.count else { return nil }
        let available = Double(count)
        return QuotaWindow(
            providerID: .codex,
            type: .credits,
            used: nil,
            limit: available,
            remaining: available,
            resetAt: nil,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), reset bank)",
            label: "Reset bank",
            bucketKey: "reset_bank",
            observedAt: observedAt
        )
    }

    private func sourceWindowLabel(for rateLimit: CodexRateLimit, type: QuotaWindowType) -> String {
        if let seconds = windowDurationSeconds(for: rateLimit) {
            if abs(seconds - CodexWindowDuration.sessionSeconds) <= CodexWindowDuration.toleranceSeconds {
                return "5h window"
            }
            if abs(seconds - CodexWindowDuration.weeklySeconds) <= CodexWindowDuration.toleranceSeconds {
                return "weekly window"
            }
            if seconds.isMultiple(of: 3600) {
                return "\(seconds / 3600)h window"
            }
            return "\(seconds)s window"
        }
        if let minutes = rateLimit.windowMinutes {
            return sourceWindow(type: type, minutes: minutes)
        }
        return type == .weekly ? "weekly window" : "session window"
    }

    private func sourcePlan(_ planType: String?) -> String {
        guard let planType, !planType.isEmpty else { return "unknown plan" }
        return "\(planType) plan"
    }

    private func sourceWindow(type: QuotaWindowType, minutes: Int?) -> String {
        if minutes == 300 {
            return "5h window"
        }
        if minutes == 10_080 {
            return "weekly window"
        }
        if let minutes, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h window"
        }
        if let minutes {
            return "\(minutes)m window"
        }
        return type == .weekly ? "weekly window" : "session window"
    }

    private func intValue(_ value: Any?) -> Int? {
        CheckedNumericConversion.integer(value)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }
}
