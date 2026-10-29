import Foundation

extension CodexJSONLParser {
    func parseFile(
        at url: URL,
        startingAtByte byteOffset: UInt64,
        startingInOversizedRecord: Bool = false,
        onRecord: (CodexUsageRecord) -> Void
    ) async throws -> JSONLParseResult {
        var framer = CodexJSONLFramer(startingAtByte: byteOffset,
                                     startingInOversizedRecord: startingInOversizedRecord)
        let file = try FileHandle(forReadingFrom: url)
        defer { file.closeFile() }
        if byteOffset > 0 { try file.seek(toOffset: byteOffset) }
        // Preserve the existing plain-log read size and append/incomplete-tail behavior.
        while true {
            let didRead = try autoreleasepool { () throws -> Bool in
                guard let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty else { return false }
                framer.consume(chunk, parseLine: parseLine, onRecord: onRecord)
                return true
            }
            if !didRead { break }
        }
        return framer.finish(parseLine: parseLine, onRecord: onRecord)
    }
}
