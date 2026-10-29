import Foundation

/// The same bounded record framing for plain file reads and decoded zstd blocks.
struct CodexJSONLFramer {
    private var buffer = Data()
    private var alreadyScanned = 0
    private var malformedCount = 0
    private var finalOffset: UInt64
    private var discardingOversizedRecord: Bool

    init(startingAtByte: UInt64 = 0, startingInOversizedRecord: Bool = false) {
        finalOffset = startingAtByte
        discardingOversizedRecord = startingInOversizedRecord
    }

    mutating func consume(_ chunk: Data, parseLine: (Data) -> CodexLineParseOutcome,
                          onRecord: (CodexUsageRecord) -> Void) {
        if discardingOversizedRecord {
            guard let newline = chunk.firstIndex(of: 0x0A) else {
                finalOffset += UInt64(chunk.count)
                return
            }
            let start = chunk.index(after: newline)
            finalOffset += UInt64(chunk.distance(from: chunk.startIndex, to: start))
            discardingOversizedRecord = false
            buffer.append(contentsOf: chunk[start...])
        } else { buffer.append(chunk) }
        var lineStart = buffer.startIndex
        var searchStart = buffer.index(buffer.startIndex, offsetBy: alreadyScanned)
        while let newline = buffer[searchStart...].firstIndex(of: 0x0A) {
            if buffer.distance(from: lineStart, to: newline) > JSONLRecordFraming.maximumRecordBytes {
                malformedCount += 1
            } else {
                var line = Data(buffer[lineStart..<newline])
                if line.last == 0x0D { line.removeLast() }
                if !line.isEmpty { process(parseLine(line), onRecord: onRecord) }
            }
            lineStart = buffer.index(after: newline)
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
    }

    mutating func finish(parseLine: (Data) -> CodexLineParseOutcome,
                         onRecord: (CodexUsageRecord) -> Void) -> JSONLParseResult {
        if !buffer.isEmpty, !discardingOversizedRecord {
            let outcome = parseLine(buffer)
            if case .malformed = outcome, Self.isIncompleteJSON(buffer) {
                return result
            }
            process(outcome, onRecord: onRecord)
            finalOffset += UInt64(buffer.count)
        }
        return result
    }

    private var result: JSONLParseResult {
        JSONLParseResult(malformedCount: malformedCount, finalOffset: finalOffset,
                         discardingOversizedRecord: discardingOversizedRecord)
    }

    private mutating func process(_ outcome: CodexLineParseOutcome, onRecord: (CodexUsageRecord) -> Void) {
        switch outcome {
        case .usage(let record): onRecord(record)
        case .skipped: break
        case .malformed: malformedCount += 1
        }
    }

    private static func isIncompleteJSON(_ data: Data) -> Bool {
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return false
        } catch {
            let description = (error as NSError).userInfo["NSDebugDescription"] as? String ?? ""
            return description.localizedCaseInsensitiveContains("unexpected end of file")
                || description.localizedCaseInsensitiveContains("unterminated")
        }
    }
}
