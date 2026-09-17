import Foundation

extension ClaudeJSONLParser {
    /// Streams a JSONL file starting at `byteOffset` and returns resumable framing state.
    func parseFile(
        at url: URL,
        startingAtByte byteOffset: UInt64,
        startingInOversizedRecord: Bool = false,
        onRecord: (ClaudeUsageRecord) -> Void
    ) async throws -> JSONLParseResult {
        var malformedCount = 0
        var finalOffset = byteOffset
        var buffer = Data()
        var alreadyScanned = 0
        var discardingOversizedRecord = startingInOversizedRecord
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }

        if byteOffset > 0 { try fileHandle.seek(toOffset: byteOffset) }
        while try autoreleasepool(invoking: {
            guard let chunk = try fileHandle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
            }
            guard append(
                chunk,
                to: &buffer,
                discardingOversizedRecord: &discardingOversizedRecord,
                finalOffset: &finalOffset
            ) else { return true }
            discardingOversizedRecord = drainCompleteRecords(
                from: &buffer,
                alreadyScanned: &alreadyScanned,
                malformedCount: &malformedCount,
                finalOffset: &finalOffset,
                onRecord: onRecord
            )
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
        return JSONLParseResult(
            malformedCount: malformedCount,
            finalOffset: finalOffset,
            discardingOversizedRecord: discardingOversizedRecord
        )
    }

    private func append(
        _ chunk: Data,
        to buffer: inout Data,
        discardingOversizedRecord: inout Bool,
        finalOffset: inout UInt64
    ) -> Bool {
        guard discardingOversizedRecord else {
            buffer.append(chunk)
            return true
        }
        guard let newlineIndex = chunk.firstIndex(of: 0x0A) else {
            finalOffset += UInt64(chunk.count)
            return false
        }
        let nextRecordStart = chunk.index(after: newlineIndex)
        finalOffset += UInt64(chunk.distance(from: chunk.startIndex, to: nextRecordStart))
        discardingOversizedRecord = false
        buffer.append(contentsOf: chunk[nextRecordStart...])
        return true
    }

    private func drainCompleteRecords(
        from buffer: inout Data,
        alreadyScanned: inout Int,
        malformedCount: inout Int,
        finalOffset: inout UInt64,
        onRecord: (ClaudeUsageRecord) -> Void
    ) -> Bool {
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
        guard buffer.count > JSONLRecordFraming.maximumRecordBytes else { return false }
        malformedCount += 1
        finalOffset += UInt64(buffer.count)
        buffer.removeAll(keepingCapacity: false)
        alreadyScanned = 0
        return true
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
        guard let usage = extractUsage(from: json) else { return .skipped }

        let message = json["message"] as? [String: Any]
        let messageID = message?["id"] as? String ?? json["message_id"] as? String
        let requestID = json["requestId"] as? String ?? json["request_id"] as? String
        let sessionID = json["sessionId"] as? String ?? json["session_id"] as? String
        let uuid = json["uuid"] as? String
        guard let inputTokens = CheckedNumericConversion.tokenCount(usage["input_tokens"]),
              let outputTokens = CheckedNumericConversion.tokenCount(usage["output_tokens"]),
              let cacheReadInputTokens = CheckedNumericConversion.tokenCount(
                  usage["cache_read_input_tokens"]
              ),
              let cacheCreationInputTokens = CheckedNumericConversion.tokenCount(
                  usage["cache_creation_input_tokens"]
              ) else {
            return .malformed
        }
        var totalOverflowed = false
        _ = TokenArithmetic.sum(
            [inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens],
            overflowed: &totalOverflowed
        )
        guard !totalOverflowed else { return .malformed }

        return .usage(ClaudeUsageRecord(
            messageID: messageID,
            requestID: requestID,
            sessionID: sessionID,
            uuid: uuid,
            timestamp: JSONLDateParsing.parseTimestamp(from: json),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens
        ))
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
