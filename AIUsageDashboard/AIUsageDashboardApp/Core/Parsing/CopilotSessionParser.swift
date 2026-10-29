import Darwin
import Foundation

/// Reads only CLI session.shutdown counters. No authentication files or session-store databases.
public actor CopilotSessionParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        public let dailyTotals: [Date: Int]
        public let dailyModelUsage: [Date: [String: TokenUsage]]
        public let warnings: [ProviderWarning]
        public let shutdownCount: Int
    }
    struct Shutdown: Sendable {
        let timestamp: Date
        let models: [String: TokenUsage]
    }
    private struct CachedFile {
        let fingerprint: LocalUsageFileFingerprint
        let shutdowns: [Shutdown]
        let malformed: Int
    }
    private let root: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let chunkReader: @Sendable (FileHandle) throws -> Data?
    private var cache: [URL: CachedFile] = [:]

    public init(sessionStateDirectory: URL? = nil, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() },
                chunkReader: (@Sendable (FileHandle) throws -> Data?)? = nil) {
        root = sessionStateDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/session-state")
        self.calendar = calendar
        self.now = now
        self.chunkReader = chunkReader ?? { try $0.read(upToCount: 64 * 1024) }
    }

    public func parse() -> AggregateUsage {
        var partial = false
        let files = discover(partial: &partial)
        let active = Set(files)
        cache = cache.filter { active.contains($0.key) }
        for url in files {
            do {
                let fingerprint = try LocalUsageFileFingerprint.read(url)
                if cache[url]?.fingerprint != fingerprint {
                    do {
                        let result = try readFile(url)
                        cache[url] = CachedFile(fingerprint: fingerprint, shutdowns: result.records,
                                                malformed: result.malformed)
                    } catch {
                        cache[url] = CachedFile(fingerprint: fingerprint, shutdowns: [], malformed: 1)
                    }
                }
                partial = partial || (cache[url]?.malformed ?? 0) > 0
            } catch { cache.removeValue(forKey: url); partial = true }
        }
        return aggregate(files: files, partial: partial)
    }

    private func discover(partial: inout Bool) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        do {
            let sessions = try FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return try sessions.sorted { $0.path < $1.path }.compactMap { session in
                let values = try session.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
                let url = session.appendingPathComponent("events.jsonl")
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let file = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return file.isRegularFile == true && file.isSymbolicLink != true ? url : nil
            }
        } catch { partial = true; return [] }
    }

    private func aggregate(files: [URL], partial: Bool) -> AggregateUsage {
        let reference = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: reference)
        var dailyModels: [Date: [String: TokenUsage]] = [:]
        var count = 0
        for url in files {
            var previous: [String: TokenUsage] = [:]
            let shutdowns = (cache[url]?.shutdowns ?? []).sorted { $0.timestamp < $1.timestamp }
            count += shutdowns.count
            for shutdown in shutdowns where shutdown.timestamp <= reference {
                let day = calendar.startOfDay(for: shutdown.timestamp)
                for (model, cumulative) in shutdown.models {
                    let old = previous[model] ?? UsageWindows.emptyUsage(.localParsed)
                    let updated = Self.highWater(cumulative, old)
                    let delta = Self.delta(updated, after: old)
                    previous[model] = updated
                    windows.accumulate(delta, timestamp: shutdown.timestamp, dailyTotal: delta.totalTokens ?? 0)
                    dailyModels[day, default: [:]][model] = (dailyModels[day]?[model]
                        ?? UsageWindows.emptyUsage(.localParsed)).merging(delta)
                }
            }
        }
        let result = windows.snapshot()
        let warnings = partial ? [ProviderWarning(message: "Some Copilot CLI history could not be read.",
                                                  level: .warning)] : []
        return AggregateUsage(today: count == 0 ? .unavailable : result.today,
                              week: count == 0 ? .unavailable : result.week,
                              month: count == 0 ? .unavailable : result.month,
                              lifetime: count == 0 ? .unavailable : result.lifetime,
                              dailyTotals: result.dailyTotals,
                              dailyModelUsage: UsageAggregation.recentModelUsage(
                                  dailyModels, calendar: calendar, now: reference),
                              warnings: warnings, shutdownCount: count)
    }

    /// Reclassification can subtract from uncached/visible buckets while adding to their subsets.
    /// Those signed corrections have zero total and preserve the shutdown day's accounting.
    private static func delta(_ current: TokenUsage, after previous: TokenUsage) -> TokenUsage {
        func difference(_ key: KeyPath<TokenUsage, Int?>) -> Int {
            (current[keyPath: key] ?? 0) - (previous[keyPath: key] ?? 0)
        }
        return TokenUsage(inputTokens: difference(\.inputTokens), outputTokens: difference(\.outputTokens),
                          cacheReadTokens: difference(\.cacheReadTokens),
                          cacheCreationTokens: difference(\.cacheCreationTokens),
                          reasoningTokens: difference(\.reasoningTokens), confidence: .localParsed)
    }

    private static func highWater(_ current: TokenUsage, _ previous: TokenUsage) -> TokenUsage {
        let output = max(outputTotal(current), outputTotal(previous))
        let reasoning = max(current.reasoningTokens ?? 0, previous.reasoningTokens ?? 0)
        let cached = max(current.cacheReadTokens ?? 0, previous.cacheReadTokens ?? 0)
        let creation = max(current.cacheCreationTokens ?? 0, previous.cacheCreationTokens ?? 0)
        let cacheTotal = TokenArithmetic.sum([cached, creation])
        let input = max(inputTotal(current), inputTotal(previous), cacheTotal)
        return TokenUsage(inputTokens: input - cacheTotal, outputTokens: output - reasoning,
                          cacheReadTokens: cached, cacheCreationTokens: creation,
                          reasoningTokens: reasoning, confidence: .localParsed)
    }

    private static func inputTotal(_ usage: TokenUsage) -> Int {
        TokenArithmetic.sum([usage.inputTokens ?? 0, usage.cacheReadTokens ?? 0, usage.cacheCreationTokens ?? 0])
    }

    private static func outputTotal(_ usage: TokenUsage) -> Int {
        TokenArithmetic.sum([usage.outputTokens ?? 0, usage.reasoningTokens ?? 0])
    }

}

extension CopilotSessionParser {
    /// Buffer is capped before append; discarded records resume at their next newline.
    private func readFile(_ url: URL) throws -> (records: [Shutdown], malformed: Int) {
        let handle = try Self.openRegularFile(url)
        defer { try? handle.close() }
        var buffer = Data()
        var discarding = false
        var records: [Shutdown] = []
        var malformed = 0
        func process() {
            guard !buffer.isEmpty else { return }
            do {
                if let record = try Self.shutdown(buffer) { records.append(record) }
            } catch { malformed += 1 }
            buffer.removeAll(keepingCapacity: false)
        }
        while let chunk = try chunkReader(handle), !chunk.isEmpty {
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 10)
                let end = newline ?? chunk.endIndex
                if !discarding {
                    if buffer.count + chunk.distance(from: start, to: end) <= JSONLRecordFraming.maximumRecordBytes {
                        buffer.append(contentsOf: chunk[start..<end])
                    } else {
                        buffer.removeAll(keepingCapacity: false)
                        discarding = true
                    }
                }
                if let newline {
                    if discarding { malformed += 1 } else { process() }
                    discarding = false
                    start = chunk.index(after: newline)
                } else { break }
            }
        }
        return (records, malformed)
    }

    private static func openRegularFile(_ url: URL) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func shutdown(_ data: Data) throws -> Shutdown? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard json["type"] as? String == "session.shutdown" else { return nil }
        guard let timestamp = JSONLDateParsing.parseTimestamp(from: json),
              let data = json["data"] as? [String: Any],
              let metrics = data["modelMetrics"] as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var models: [String: TokenUsage] = [:]
        for (model, metric) in metrics {
            guard let usage = metric["usage"] as? [String: Any] else { continue }
            guard let input = CheckedNumericConversion.tokenCount(usage["inputTokens"]),
                  let output = CheckedNumericConversion.tokenCount(usage["outputTokens"]),
                  let cached = CheckedNumericConversion.tokenCount(usage["cacheReadTokens"]),
                  let creation = CheckedNumericConversion.tokenCount(usage["cacheWriteTokens"]),
                  let reasoning = CheckedNumericConversion.tokenCount(usage["reasoningTokens"]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var overflowed = false
            let cacheTotal = TokenArithmetic.sum([cached, creation], overflowed: &overflowed)
            let thinking = min(output, reasoning)
            // Copilot reports total prompt/output counters; Tokei's priced buckets are disjoint.
            // Schema: github/copilot-sdk docs/features/streaming-events.md (assistant.usage).
            let tokens = TokenUsage(inputTokens: max(0, input - cacheTotal), outputTokens: output - thinking,
                                    cacheReadTokens: cached, cacheCreationTokens: creation,
                                    reasoningTokens: thinking, confidence: .localParsed)
            _ = tokens.totalTokens(overflowed: &overflowed)
            guard !overflowed else { throw CocoaError(.fileReadCorruptFile) }
            models[model] = tokens
        }
        return Shutdown(timestamp: timestamp, models: models)
    }
}
