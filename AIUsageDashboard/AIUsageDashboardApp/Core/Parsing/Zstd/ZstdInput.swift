// Port of facebook/zstd educational_decoder; Copyright Meta Platforms, Inc. and affiliates.
// BSD-3-Clause; see THIRD_PARTY_NOTICES.md.
import Foundation

/// File reads are exact and bounded to a block; compressed files need not fit in memory.
final class ZstdInput {
    private let data: Data?
    private let handle: FileHandle?
    private var offset = 0

    init(data: Data) { self.data = data; handle = nil }
    init(fileAt url: URL) throws { data = nil; handle = try FileHandle(forReadingFrom: url) }
    deinit { try? handle?.close() }

    func read(_ count: Int, allowEOF: Bool = false) throws -> [UInt8] {
        guard count >= 0, count <= ZstdDecoder.maximumBlockSize else { throw ZstdDecoder.DecodeError.malformed }
        if let data {
            guard offset <= data.count, count <= data.count - offset else {
                if allowEOF && offset == data.count { return [] }
                throw ZstdDecoder.DecodeError.truncated
            }
            let start = data.index(data.startIndex, offsetBy: offset)
            offset += count // Bounded by data.count above.
            return Array(data[start..<data.index(start, offsetBy: count)])
        }
        guard let handle else { throw ZstdDecoder.DecodeError.malformed }
        var result = Data()
        while result.count < count {
            let chunk = try handle.read(upToCount: count - result.count) ?? Data()
            if chunk.isEmpty {
                if allowEOF && result.isEmpty { return [] }
                throw ZstdDecoder.DecodeError.truncated
            }
            result.append(chunk)
        }
        return Array(result)
    }

    func integer(_ count: Int) throws -> UInt64 {
        guard (0...8).contains(count) else { throw ZstdDecoder.DecodeError.malformed }
        return try read(count).enumerated().reduce(0) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
    }
}

/// Forward, little-endian bits for literals and normalized frequency headers.
struct ZstdBits {
    let bytes: [UInt8]
    var position = 0
    var remainingBytes: Int { (bytes.count * 8 - position) / 8 }

    init(_ bytes: [UInt8]) throws {
        guard bytes.count <= ZstdDecoder.maximumBlockSize else { throw ZstdDecoder.DecodeError.malformed }
        self.bytes = bytes
    }

    mutating func read(_ count: Int) throws -> Int {
        guard (0...32).contains(count), position >= 0,
              position <= bytes.count * 8, count <= bytes.count * 8 - position else {
            throw ZstdDecoder.DecodeError.truncated
        }
        let result = Self.value(bytes, at: position, count: count)
        position += count
        return result
    }

    mutating func rewindOneBit() throws {
        guard position > 0 else { throw ZstdDecoder.DecodeError.malformed }
        position -= 1
    }

    mutating func align() { position = ((position + 7) / 8) * 8 }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard position % 8 == 0, count >= 0, count <= remainingBytes else {
            throw ZstdDecoder.DecodeError.truncated
        }
        let start = position / 8
        position += count * 8 // All bitstreams are <=128 KiB.
        return Array(bytes[start..<start + count])
    }

    /// Caller first checks the complete bit range. Each byte is then in that range.
    static func value(_ bytes: [UInt8], at start: Int, count: Int) -> Int {
        var result = 0
        var shift = 0
        var cursor = start
        var left = count
        while left > 0 {
            let bit = cursor % 8
            let width = min(left, 8 - bit)
            result |= ((Int(bytes[cursor / 8]) >> bit) & ((1 << width) - 1)) << shift
            left -= width
            shift += width
            cursor += width
        }
        return result
    }
}

/// Entropy streams are read backwards; padding is allowed only where the format specifies it.
struct ZstdReverseBits {
    let bytes: [UInt8]
    var position: Int

    init(_ bytes: [UInt8]) throws {
        guard bytes.count <= ZstdDecoder.maximumBlockSize, let last = bytes.last, last != 0 else {
            throw ZstdDecoder.DecodeError.malformed
        }
        self.bytes = bytes
        position = (bytes.count - 1) * 8 + (7 - last.leadingZeroBitCount)
    }

    mutating func read(_ count: Int, padded: Bool = false) throws -> Int {
        guard (0...32).contains(count), position <= bytes.count * 8,
              position >= -32, padded || count <= position else { throw ZstdDecoder.DecodeError.malformed }
        let next = position - count
        guard next >= -32 else { throw ZstdDecoder.DecodeError.malformed }
        let actualStart = max(0, next)
        let actualCount = max(0, position - actualStart)
        let value = ZstdBits.value(bytes, at: actualStart, count: actualCount)
        position = next
        return value << min(count, max(0, -next))
    }
}
