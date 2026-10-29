import Foundation

enum JSONLRecordFraming {
    static let maximumRecordBytes = 16 * 1024 * 1024
}

struct JSONLParseResult: Sendable {
    let malformedCount: Int
    let finalOffset: UInt64
    let discardingOversizedRecord: Bool
}
