import Foundation

extension CodexJSONLParser {
    func parseFile(
        at url: URL,
        startingAtByte byteOffset: UInt64,
        onRecord: (CodexUsageRecord) -> Void
    ) async throws -> (malformedCount: Int, finalOffset: UInt64) {
        var malformedCount = 0
        var finalOffset = byteOffset
        var buffer = Data()
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }

        if byteOffset > 0 {
            try fileHandle.seek(toOffset: byteOffset)
        }

        var alreadyScanned = 0
        while true {
            let didRead = try autoreleasepool { () throws -> Bool in
                guard let chunk = try fileHandle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                    return false
                }
                buffer.append(chunk)
                var lineStart = buffer.startIndex
                var searchStart = buffer.index(buffer.startIndex, offsetBy: alreadyScanned)

                while let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A) {
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
                    lineStart = buffer.index(after: newlineIndex)
                    searchStart = lineStart
                }

                if lineStart > buffer.startIndex {
                    finalOffset += UInt64(buffer.distance(from: buffer.startIndex, to: lineStart))
                    buffer.removeSubrange(buffer.startIndex..<lineStart)
                }
                alreadyScanned = buffer.count
                return true
            }
            if !didRead { break }
        }

        guard !buffer.isEmpty else {
            return (malformedCount, finalOffset)
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
        return (malformedCount, finalOffset)
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
