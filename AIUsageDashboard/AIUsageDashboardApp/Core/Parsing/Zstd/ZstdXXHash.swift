// Zstandard content checksum (XXH64, seed 0); Copyright Yann Collet - Meta Platforms, Inc.
// BSD-3-Clause; see THIRD_PARTY_NOTICES.md.
import Foundation

/// Streaming XXH64. Wrapping operations here are required by the hash, never used for bounds.
struct ZstdXXHash {
    private static let prime1: UInt64 = 11_400_714_785_074_694_791
    private static let prime2: UInt64 = 14_029_467_366_897_019_727
    private static let prime3: UInt64 = 1_609_587_929_392_839_161
    private static let prime4: UInt64 = 9_650_029_242_287_828_579
    private static let prime5: UInt64 = 2_870_177_450_012_600_261
    private var lanes = [prime1 &+ prime2, prime2, 0, 0 &- prime1]
    private var tail: [UInt8] = []
    private var count = 0

    mutating func update(_ bytes: [UInt8]) {
        count += bytes.count // Decoder bounds the total to 256 MiB before this call.
        var cursor = 0
        if !tail.isEmpty {
            let take = min(32 - tail.count, bytes.count)
            tail.append(contentsOf: bytes.prefix(take))
            cursor = take
            if tail.count == 32 { stripe(tail, at: 0); tail.removeAll(keepingCapacity: true) }
        }
        while bytes.count - cursor >= 32 { stripe(bytes, at: cursor); cursor += 32 }
        tail.append(contentsOf: bytes[cursor...])
    }

    var digest: UInt64 {
        var hash: UInt64
        if count >= 32 {
            hash = Self.rotate(lanes[0], 1) &+ Self.rotate(lanes[1], 7)
                &+ Self.rotate(lanes[2], 12) &+ Self.rotate(lanes[3], 18)
            for lane in lanes { hash = (hash ^ Self.round(0, lane)) &* Self.prime1 &+ Self.prime4 }
        } else { hash = Self.prime5 }
        hash &+= UInt64(count)
        var cursor = 0
        while tail.count - cursor >= 8 {
            hash ^= Self.round(0, Self.word(tail, at: cursor, count: 8))
            hash = Self.rotate(hash, 27) &* Self.prime1 &+ Self.prime4
            cursor += 8
        }
        if tail.count - cursor >= 4 {
            hash ^= Self.word(tail, at: cursor, count: 4) &* Self.prime1
            hash = Self.rotate(hash, 23) &* Self.prime2 &+ Self.prime3
            cursor += 4
        }
        while cursor < tail.count {
            hash ^= UInt64(tail[cursor]) &* Self.prime5
            hash = Self.rotate(hash, 11) &* Self.prime1
            cursor += 1
        }
        hash ^= hash >> 33
        hash &*= Self.prime2
        hash ^= hash >> 29
        hash &*= Self.prime3
        return hash ^ (hash >> 32)
    }

    private mutating func stripe(_ bytes: [UInt8], at cursor: Int) {
        for lane in 0..<4 { lanes[lane] = Self.round(lanes[lane], Self.word(bytes, at: cursor + lane * 8, count: 8)) }
    }

    private static func round(_ accumulator: UInt64, _ word: UInt64) -> UInt64 {
        rotate(accumulator &+ word &* prime2, 31) &* prime1
    }

    private static func rotate(_ value: UInt64, _ bits: Int) -> UInt64 {
        (value << bits) | (value >> (64 - bits))
    }

    /// Every call is within a full stripe or a checked tail range.
    private static func word(_ bytes: [UInt8], at cursor: Int, count: Int) -> UInt64 {
        var word: UInt64 = 0
        for index in 0..<count { word |= UInt64(bytes[cursor + index]) << (8 * index) }
        return word
    }
}
