import Foundation

extension CodexJSONLParser {
    func parseFile(
        at url: URL,
        startingAtByte byteOffset: UInt64,
        startingInOversizedRecord: Bool = false,
        onRecord: (CodexUsageRecord) -> Void
    ) async throws -> (
        malformedCount: Int,
        finalOffset: UInt64,
        discardingOversizedRecord: Bool
    ) {
        var malformedCount = 0
        var finalOffset = byteOffset
        var buffer = Data()
        var discardingOversizedRecord = startingInOversizedRecord
        // Large enough to amortize FileHandle/autorelease overhead, while the
        // frozen long-line benchmark remains below the 64 MiB RSS budget.
        let readChunkSize = 4 * 1024 * 1024
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }

        if byteOffset > 0 {
            try fileHandle.seek(toOffset: byteOffset)
        }

        var alreadyScanned = 0
        while true {
            let didRead = try autoreleasepool { () throws -> Bool in
                guard let chunk = try fileHandle.read(upToCount: readChunkSize), !chunk.isEmpty else {
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
                        if line.last == 0x0D {
                            line.removeLast()
                        }
                        if !line.isEmpty {
                            process(
                                line,
                                malformedCount: &malformedCount,
                                onRecord: onRecord
                            )
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
            }
            if !didRead { break }
        }

        guard !buffer.isEmpty, !discardingOversizedRecord else {
            return (malformedCount, finalOffset, discardingOversizedRecord)
        }

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
        return (malformedCount, finalOffset, discardingOversizedRecord)
    }

    private func process(
        _ data: Data,
        malformedCount: inout Int,
        onRecord: (CodexUsageRecord) -> Void
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
}
