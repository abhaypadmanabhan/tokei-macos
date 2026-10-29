// Adapted from T3 Code: apps/server/src/provider/Drivers/antigravityUsageReader.ts (MIT).
import Foundation

/// Schema-directed protobuf. Length-delimited values are decoded only at known message paths.
struct AntigravityProtobuf {
    enum Value {
        case integer(UInt64)
        case bytes(Data)
    }
    enum DecodeError: Error { case malformed }
    private var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let tag = try Self.varint(bytes, offset: &offset)
            guard tag >> 3 > 0, tag >> 3 <= UInt64(Int.max) else { throw DecodeError.malformed }
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                fields[field, default: []].append(.integer(try Self.varint(bytes, offset: &offset)))
            case 2:
                let length = try Self.varint(bytes, offset: &offset)
                guard length <= UInt64(bytes.count - offset) else { throw DecodeError.malformed }
                let end = offset + Int(length)
                fields[field, default: []].append(.bytes(Data(bytes[offset..<end])))
                offset = end
            case 1, 5:
                let length = tag & 7 == 1 ? 8 : 4
                guard length <= bytes.count - offset else { throw DecodeError.malformed }
                offset += length
            default:
                throw DecodeError.malformed
            }
        }
    }

    func number(_ field: Int) -> Int {
        guard case .integer(let value) = fields[field]?.first, value <= 9_007_199_254_740_992 else { return 0 }
        return Int(value)
    }

    func message(_ field: Int) throws -> AntigravityProtobuf? {
        guard case .bytes(let data) = fields[field]?.first else { return nil }
        return try AntigravityProtobuf(data)
    }

    func messages(_ field: Int) throws -> [AntigravityProtobuf] {
        try (fields[field] ?? []).compactMap { value in
            guard case .bytes(let data) = value else { return nil }
            return try AntigravityProtobuf(data)
        }
    }

    func text(_ field: Int) throws -> String? {
        guard case .bytes(let data) = fields[field]?.first else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw DecodeError.malformed }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var timestamp: Date? {
        let seconds = number(1)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(seconds) + Double(number(2)) / 1_000_000_000)
    }

    private static func varint(_ bytes: [UInt8], offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            guard offset < bytes.count else { throw DecodeError.malformed }
            let byte = bytes[offset]
            offset += 1
            guard index < 9 || byte <= 1 else { throw DecodeError.malformed }
            value |= UInt64(byte & 127) << (index * 7)
            if byte < 128 { return value }
        }
        throw DecodeError.malformed
    }
}
