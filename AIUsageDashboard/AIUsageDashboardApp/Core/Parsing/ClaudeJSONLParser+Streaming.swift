import Foundation

enum JSONLRecordFraming {
    static let maximumRecordBytes = 16 * 1024 * 1024
}

enum LineParseOutcome: Sendable {
    case usage(ClaudeUsageRecord)
    case skipped
    case malformed
}

extension ClaudeJSONLParser {
    /// Per-call cache accounting, printed to stderr when `TOKEI_PARSE_DEBUG=1`.
    struct ParseStats {
        var hits = 0
        var appends = 0
        var fullParses = 0
        var bytesRead: UInt64 = 0
        var duplicateKeys = 0
        var corrections = 0
        let startedAt = DispatchTime.now()

        func emit(sources: Int, cacheSize: Int, seenIDs: Int) {
            guard ProcessInfo.processInfo.environment["TOKEI_PARSE_DEBUG"] == "1" else { return }
            let elapsedMilliseconds = Double(
                DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
            ) / 1_000_000
            let line = "[parse] sources=\(sources) hits=\(hits) appends=\(appends) "
                + "full=\(fullParses) bytesRead=\(bytesRead / 1024)KiB cacheEntries=\(cacheSize) "
                + "seenIDs=\(seenIDs) dupKeys=\(duplicateKeys) corrections=\(corrections) "
                + "elapsed=\(String(format: "%.1f", elapsedMilliseconds))ms\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    struct FileCacheEntry {
        var modificationDate: Date?
        var byteOffset: UInt64
        var observedSize: UInt64
        var fileIdentifier: Data?
        var continuityTail: Data
        /// Latest/highest complete record for each message in this file. Retaining the
        /// record, rather than only its key, lets a later copy reconcile output updates.
        var recordsByID: [String: ClaudeUsageRecord]
        var unkeyedAggregate: FileAggregate
        var malformedCount: Int
        var discardingOversizedRecord: Bool
    }

    struct CalendarIdentity: Equatable {
        let identifier: Calendar.Identifier
        let timeZoneIdentifier: String
        let localeIdentifier: String?
        let firstWeekday: Int
        let minimumDaysInFirstWeek: Int

        init(_ calendar: Calendar) {
            identifier = calendar.identifier
            timeZoneIdentifier = calendar.timeZone.identifier
            localeIdentifier = calendar.locale?.identifier
            firstWeekday = calendar.firstWeekday
            minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        }
    }

    private struct FileMetadata {
        let size: UInt64
        let identifier: Data?
        let modificationDate: Date?
    }

    func cachedEntry(for source: LogSource, stats: inout ParseStats) async throws -> FileCacheEntry {
        let path = source.url.path
        if let cached = fileCache[path],
           let discoveredSize = source.fileSize,
           let discoveredIdentifier = source.fileIdentifier,
           cached.modificationDate == source.lastModified,
           cached.observedSize == discoveredSize,
           cached.fileIdentifier == discoveredIdentifier {
            stats.hits += 1
            return cached
        }

        let metadata = fileMetadata(of: source.url)
        let currentSize = metadata.size
        // Discovery and cache keys use the same timestamp representation. Falling back to
        // the raw attribute only serves callers that did not provide discovery metadata.
        let currentModificationDate = source.lastModified ?? metadata.modificationDate
        if let cached = fileCache[path],
           let cachedIdentifier = cached.fileIdentifier,
           let currentIdentifier = metadata.identifier,
           cached.modificationDate == currentModificationDate,
           cached.observedSize == currentSize,
           cachedIdentifier == currentIdentifier {
            stats.hits += 1
            return cached
        }

        let entry: FileCacheEntry
        if let cached = fileCache[path],
           let cachedModificationDate = cached.modificationDate,
           let currentModificationDate,
           let cachedIdentifier = cached.fileIdentifier,
           let currentIdentifier = metadata.identifier,
           currentModificationDate >= cachedModificationDate,
           cached.observedSize < currentSize,
           cachedIdentifier == currentIdentifier,
           try continuityTail(at: source.url, endingAt: cached.byteOffset) == cached.continuityTail {
            stats.appends += 1
            stats.bytesRead += currentSize - cached.byteOffset
            entry = try await extending(
                cached,
                at: source.url,
                modifiedAt: currentModificationDate,
                observedSize: currentSize,
                fileIdentifier: metadata.identifier
            )
        } else {
            stats.fullParses += 1
            stats.bytesRead += currentSize
            entry = try await freshEntry(
                for: source.url,
                modifiedAt: currentModificationDate,
                observedSize: currentSize,
                fileIdentifier: metadata.identifier
            )
        }
        fileCache[path] = entry
        didMutateFileCache()
        return entry
    }

    private func freshEntry(
        for url: URL,
        modifiedAt: Date?,
        observedSize: UInt64,
        fileIdentifier: Data?
    ) async throws -> FileCacheEntry {
        var recordsByID: [String: ClaudeUsageRecord] = [:]
        var unkeyedAggregate = FileAggregate.empty
        let result = try await parseFile(at: url, startingAtByte: 0) { [self] record in
            if let key = record.dedupeKey {
                self.reconcile(record, for: key, into: &recordsByID)
            } else {
                self.accumulate(into: &unkeyedAggregate, record: record)
            }
        }
        return FileCacheEntry(
            modificationDate: modifiedAt,
            byteOffset: result.finalOffset,
            observedSize: observedSize,
            fileIdentifier: fileIdentifier,
            continuityTail: try continuityTail(at: url, endingAt: result.finalOffset),
            recordsByID: recordsByID,
            unkeyedAggregate: unkeyedAggregate,
            malformedCount: result.malformedCount,
            discardingOversizedRecord: result.discardingOversizedRecord
        )
    }

    private func extending(
        _ cached: FileCacheEntry,
        at url: URL,
        modifiedAt: Date?,
        observedSize: UInt64,
        fileIdentifier: Data?
    ) async throws -> FileCacheEntry {
        var entry = cached
        let result = try await parseFile(
            at: url,
            startingAtByte: cached.byteOffset,
            startingInOversizedRecord: cached.discardingOversizedRecord
        ) { [self] record in
            if let key = record.dedupeKey {
                self.reconcile(record, for: key, into: &entry.recordsByID)
            } else {
                self.accumulate(into: &entry.unkeyedAggregate, record: record)
            }
        }
        entry.modificationDate = modifiedAt
        entry.byteOffset = result.finalOffset
        entry.observedSize = observedSize
        entry.fileIdentifier = fileIdentifier
        entry.continuityTail = try continuityTail(at: url, endingAt: result.finalOffset)
        entry.malformedCount += result.malformedCount
        entry.discardingOversizedRecord = result.discardingOversizedRecord
        return entry
    }

    private func reconcile(
        _ record: ClaudeUsageRecord,
        for key: String,
        into recordsByID: inout [String: ClaudeUsageRecord]
    ) {
        guard let existing = recordsByID[key] else {
            recordsByID[key] = record
            return
        }
        if shouldReplace(existing, with: record) { recordsByID[key] = record }
    }

    func shouldReplace(_ existing: ClaudeUsageRecord, with candidate: ClaudeUsageRecord) -> Bool {
        let existingValues = [
            existing.totalTokens,
            existing.outputTokens,
            existing.inputTokens,
            existing.cacheReadInputTokens,
            existing.cacheCreationInputTokens
        ]
        let candidateValues = [
            candidate.totalTokens,
            candidate.outputTokens,
            candidate.inputTokens,
            candidate.cacheReadInputTokens,
            candidate.cacheCreationInputTokens
        ]
        for (old, new) in zip(existingValues, candidateValues) where old != new {
            return new > old
        }
        return (candidate.timestamp ?? .distantPast) > (existing.timestamp ?? .distantPast)
    }

    private func continuityTail(at url: URL, endingAt byteOffset: UInt64) throws -> Data {
        let tailLength = min(byteOffset, 4 * 1024)
        guard tailLength > 0 else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        try handle.seek(toOffset: byteOffset - tailLength)
        return try handle.read(upToCount: Int(tailLength)) ?? Data()
    }

    private func fileMetadata(of url: URL) -> FileMetadata {
        // A URL instance can cache resource values across an append or atomic replacement.
        // Recreate it from the path so this fallback observes current filesystem metadata.
        let currentURL = URL(fileURLWithPath: url.path)
        guard let values = try? currentURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .fileSizeKey
        ]), let size = values.fileSize else {
            return FileMetadata(size: 0, identifier: nil, modificationDate: nil)
        }
        return FileMetadata(
            size: UInt64(size),
            identifier: values.fileResourceIdentifier as? Data,
            modificationDate: values.contentModificationDate
        )
    }

    /// Streams a JSONL file starting at `byteOffset` (useful for append-only logs that have
    /// already been partially parsed). Returns the number of malformed lines and the final
    /// file offset reached, so callers can resume from the end on the next sync.
    func parseFile(
        at url: URL,
        startingAtByte byteOffset: UInt64,
        startingInOversizedRecord: Bool = false,
        onRecord: (ClaudeUsageRecord) -> Void
    ) async throws -> (
        malformedCount: Int,
        finalOffset: UInt64,
        discardingOversizedRecord: Bool
    ) {
        var malformedCount = 0
        var finalOffset = byteOffset
        var buffer = Data()
        var alreadyScanned = 0
        var discardingOversizedRecord = startingInOversizedRecord
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }

        if byteOffset > 0 {
            try fileHandle.seek(toOffset: byteOffset)
        }

        while try autoreleasepool(invoking: {
            guard let chunk = try fileHandle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
            }

            if discardingOversizedRecord {
                guard let newlineIndex = chunk.firstIndex(of: 0x0A) else {
                    finalOffset += UInt64(chunk.count)
                    return true
                }
                let nextRecordStart = chunk.index(after: newlineIndex)
                finalOffset += UInt64(chunk.distance(from: chunk.startIndex, to: nextRecordStart))
                discardingOversizedRecord = false
                buffer.append(contentsOf: chunk[nextRecordStart...])
            } else {
                buffer.append(chunk)
            }

            var lineStart = buffer.startIndex
            var searchStart = buffer.index(buffer.startIndex, offsetBy: alreadyScanned)

            while let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A) {
                let recordByteCount = buffer.distance(from: lineStart, to: newlineIndex)
                if recordByteCount > JSONLRecordFraming.maximumRecordBytes {
                    malformedCount += 1
                } else {
                    var line = Data(buffer[lineStart..<newlineIndex])
                    if line.last == 0x0D { line.removeLast() }
                    if !line.isEmpty {
                        process(line, malformedCount: &malformedCount, onRecord: onRecord)
                    }
                }
                lineStart = buffer.index(after: newlineIndex)
                searchStart = lineStart
            }

            if lineStart > buffer.startIndex {
                finalOffset += UInt64(buffer.distance(from: buffer.startIndex, to: lineStart))
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
            alreadyScanned = buffer.count
            if buffer.count > JSONLRecordFraming.maximumRecordBytes {
                malformedCount += 1
                finalOffset += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: false)
                alreadyScanned = 0
                discardingOversizedRecord = true
            }
            return true
        }) {}

        if !discardingOversizedRecord {
            processTrailingBuffer(
                buffer,
                malformedCount: &malformedCount,
                finalOffset: &finalOffset,
                onRecord: onRecord
            )
        }
        return (malformedCount, finalOffset, discardingOversizedRecord)
    }

    private func processTrailingBuffer(
        _ buffer: Data,
        malformedCount: inout Int,
        finalOffset: inout UInt64,
        onRecord: (ClaudeUsageRecord) -> Void
    ) {
        guard !buffer.isEmpty else { return }
        switch parseLine(buffer) {
        case .usage(let record):
            onRecord(record)
            finalOffset += UInt64(buffer.count)
        case .skipped:
            finalOffset += UInt64(buffer.count)
        case .malformed where isIncompleteJSON(buffer):
            break
        case .malformed:
            malformedCount += 1
            finalOffset += UInt64(buffer.count)
        }
    }

    private func process(
        _ data: Data,
        malformedCount: inout Int,
        onRecord: (ClaudeUsageRecord) -> Void
    ) {
        switch parseLine(data) {
        case .usage(let record):
            onRecord(record)
        case .skipped:
            break
        case .malformed:
            malformedCount += 1
        }
    }

    private func isIncompleteJSON(_ data: Data) -> Bool {
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return false
        } catch {
            let description = (error as NSError).userInfo["NSDebugDescription"] as? String ?? ""
            return description.localizedCaseInsensitiveContains("unexpected end of file")
                || description.localizedCaseInsensitiveContains("unterminated")
        }
    }

    func parseLine(_ data: Data) -> LineParseOutcome {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }

        guard let usage = extractUsage(from: json) else {
            return .skipped
        }

        let message = json["message"] as? [String: Any]
        let messageID = message?["id"] as? String ?? json["message_id"] as? String
        let requestID = json["requestId"] as? String ?? json["request_id"] as? String
        let sessionID = json["sessionId"] as? String ?? json["session_id"] as? String
        let uuid = json["uuid"] as? String

        let record = ClaudeUsageRecord(
            messageID: messageID,
            requestID: requestID,
            sessionID: sessionID,
            uuid: uuid,
            timestamp: JSONLDateParsing.parseTimestamp(from: json),
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
        )
        return .usage(record)
    }

    private func extractUsage(from json: [String: Any]) -> [String: Any]? {
        if let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            return usage
        }
        if let usage = json["usage"] as? [String: Any],
           usage.keys.contains(where: { $0.hasSuffix("_tokens") }) {
            return usage
        }
        return nil
    }
}
