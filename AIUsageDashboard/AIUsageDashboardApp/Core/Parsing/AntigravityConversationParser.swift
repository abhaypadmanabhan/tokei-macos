// Adapted from T3 Code: apps/server/src/provider/Drivers/antigravityUsageReader.ts (MIT).
import Foundation

public actor AntigravityConversationParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        public let dailyTotals: [Date: Int]
        public let dailyModelUsage: [Date: [String: TokenUsage]]
        public let warnings: [ProviderWarning]
        let records: [AntigravityConversationRecord]
    }
    private struct CacheEntry {
        let fingerprint: AntigravityConversationFiles.Fingerprint
        let parsed: AntigravityConversationDatabase?
    }
    private let roots: [URL]
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let copier: @Sendable (URL, URL) throws -> Void
    private var cache: [URL: CacheEntry] = [:]

    public init(roots: [URL]? = nil, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() },
                copier: (@Sendable (URL, URL) throws -> Void)? = nil) {
        self.roots = roots ?? AntigravityConversationFiles.defaultRoots()
        self.calendar = calendar
        self.now = now
        self.copier = copier ?? { source, destination in
            try SQLiteSidecarCopy.copyDatabase(from: source, to: destination, using: .default)
        }
    }

    public func hasLocalHistory() -> Bool {
        !AntigravityConversationFiles.discover(roots).files.isEmpty
    }

    public func parse() -> AggregateUsage {
        let discovered = AntigravityConversationFiles.discover(roots)
        var partial = discovered.partial
        cache = cache.filter { discovered.files.contains($0.key) }
        var databases: [AntigravityConversationDatabase] = []
        for url in discovered.files {
            do {
                let fingerprint = try AntigravityConversationFiles.fingerprint(url)
                if cache[url]?.fingerprint != fingerprint {
                    let parsed = try? readSnapshot(url, fingerprint: fingerprint)
                    cache[url] = CacheEntry(fingerprint: fingerprint, parsed: parsed)
                }
                if let parsed = cache[url]?.parsed { databases.append(parsed) } else { partial = true }
            } catch { cache.removeValue(forKey: url); partial = true }
        }
        var models: [Int: String] = [:]
        for database in databases { models.merge(database.models) { first, _ in first } }
        let candidates = databases.flatMap(\.records).map { record in
            var record = record
            record.model = record.model ?? models[record.modelID]
                ?? AntigravityConversationRecord.knownModels[record.modelID]
            return record
        }
        return aggregate(AntigravityConversationRecord.deduplicated(candidates), partial: partial)
    }

    private func readSnapshot(_ url: URL, fingerprint: AntigravityConversationFiles.Fingerprint) throws
        -> AntigravityConversationDatabase {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TokeiAntigravity-\(UUID())")
        try SQLiteSidecarCopy.createPrivateSnapshotDirectory(at: directory, using: .default)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("history.db")
        try copier(url, snapshot)
        // A concurrent writer will change the fingerprint and force another coherent read next refresh.
        return try AntigravityConversationDatabase.read(snapshot,
            modifiedAt: Date(timeIntervalSince1970: Double(fingerprint.database.modifiedSeconds)))
    }

    private func aggregate(_ records: [AntigravityConversationRecord], partial: Bool) -> AggregateUsage {
        let reference = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: reference)
        var models: [Date: [String: TokenUsage]] = [:]
        for record in records {
            let tokens = record.tokens
            windows.accumulate(tokens, timestamp: record.timestamp, dailyTotal: tokens.totalTokens ?? 0)
            guard record.timestamp <= reference else { continue }
            let day = calendar.startOfDay(for: record.timestamp)
            let fallback = record.modelID > 0 ? "antigravity-model-\(record.modelID)" : "antigravity-unknown"
            let name = record.model ?? fallback
            let previous = models[day]?[name] ?? UsageWindows.emptyUsage(.localParsed)
            models[day, default: [:]][name] = previous.merging(tokens)
        }
        let values = windows.snapshot()
        let warnings = partial ? [ProviderWarning(message: "Some Antigravity history could not be read.",
                                                  level: .warning)] : []
        return AggregateUsage(today: records.isEmpty ? .unavailable : values.today,
                              week: records.isEmpty ? .unavailable : values.week,
                              month: records.isEmpty ? .unavailable : values.month,
                              lifetime: records.isEmpty ? .unavailable : values.lifetime,
                              dailyTotals: values.dailyTotals,
                              dailyModelUsage: UsageAggregation.recentModelUsage(
                                  models, calendar: calendar, now: reference),
                              warnings: warnings, records: records)
    }
}
