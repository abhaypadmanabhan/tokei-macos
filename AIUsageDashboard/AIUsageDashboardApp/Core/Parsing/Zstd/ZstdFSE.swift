// Port of facebook/zstd educational_decoder; Copyright Meta Platforms, Inc. and affiliates.
// BSD-3-Clause; see THIRD_PARTY_NOTICES.md.
import Foundation

/// Finite State Entropy decoding table. Entries encode a symbol and its next-state interval.
struct ZstdFSE {
    struct Entry {
        let symbol: Int
        let bits: Int
        let base: Int
    }
    let accuracy: Int
    let entries: [Entry]

    init(symbol: Int) {
        accuracy = 0
        entries = [Entry(symbol: symbol, bits: 0, base: 0)]
    }

    init(frequencies: [Int], accuracy: Int) throws {
        guard (5...9).contains(accuracy), !frequencies.isEmpty, frequencies.count <= 256 else {
            throw ZstdDecoder.DecodeError.malformed
        }
        let size = 1 << accuracy
        var total = 0
        for frequency in frequencies {
            guard frequency >= -1, frequency <= size else { throw ZstdDecoder.DecodeError.malformed }
            total += abs(frequency) // <=256 * 512, no untrusted-width arithmetic.
        }
        guard total == size else { throw ZstdDecoder.DecodeError.malformed }
        let (symbols, initialStates) = try Self.spread(frequencies, size: size)
        self.accuracy = accuracy
        entries = try Self.makeEntries(symbols: symbols, states: initialStates, accuracy: accuracy)
    }

    private static func spread(_ frequencies: [Int], size: Int) throws -> ([Int], [Int]) {
        var symbols = [Int](repeating: 0, count: size)
        var next = [Int](repeating: 0, count: frequencies.count)
        var high = size
        for (symbol, frequency) in frequencies.enumerated() where frequency == -1 {
            high -= 1
            symbols[high] = symbol
            next[symbol] = 1
        }
        // All -1 probabilities occupy the whole table; there is then no spreading loop.
        let step = (size >> 1) + (size >> 3) + 3
        var position = 0
        for (symbol, frequency) in frequencies.enumerated() where frequency > 0 {
            next[symbol] = frequency
            for _ in 0..<frequency {
                guard position < high else { throw ZstdDecoder.DecodeError.malformed }
                symbols[position] = symbol
                repeat { position = (position + step) & (size - 1) } while position >= high
            }
        }
        guard position == 0 else { throw ZstdDecoder.DecodeError.malformed }
        return (symbols, next)
    }

    private static func makeEntries(symbols: [Int], states: [Int], accuracy: Int) throws -> [Entry] {
        var next = states
        let size = 1 << accuracy
        var table: [Entry] = []
        table.reserveCapacity(size)
        for symbol in symbols {
            let state = next[symbol]
            guard state > 0 else { throw ZstdDecoder.DecodeError.malformed }
            next[symbol] += 1
            let bits = accuracy - (Int.bitWidth - 1 - state.leadingZeroBitCount)
            guard bits >= 0, bits <= accuracy else { throw ZstdDecoder.DecodeError.malformed }
            let base = (state << bits) - size
            guard base >= 0, base + (1 << bits) <= size else { throw ZstdDecoder.DecodeError.malformed }
            table.append(Entry(symbol: symbol, bits: bits, base: base))
        }
        return table
    }

    static func read(from input: inout ZstdBits, maxAccuracy: Int, maxSymbol: Int) throws -> ZstdFSE {
        let accuracy = try input.read(4) + 5
        guard accuracy <= maxAccuracy else { throw ZstdDecoder.DecodeError.malformed }
        var remaining = 1 << accuracy
        var frequencies: [Int] = []
        while remaining > 0 {
            guard frequencies.count <= maxSymbol else { throw ZstdDecoder.DecodeError.malformed }
            let bits = Int.bitWidth - (remaining + 1).leadingZeroBitCount
            var value = try input.read(bits)
            let lowerMask = (1 << (bits - 1)) - 1
            let threshold = (1 << bits) - 1 - (remaining + 1)
            if value & lowerMask < threshold {
                try input.rewindOneBit()
                value &= lowerMask
            } else if value > lowerMask {
                value -= threshold
            }
            let probability = value - 1
            remaining -= abs(probability)
            guard remaining >= 0 else { throw ZstdDecoder.DecodeError.malformed }
            frequencies.append(probability)
            if probability == 0 {
                var repeats: Int
                repeat {
                    repeats = try input.read(2)
                    guard repeats <= maxSymbol + 1 - frequencies.count else { throw ZstdDecoder.DecodeError.malformed }
                    frequencies.append(contentsOf: repeatElement(0, count: repeats))
                } while repeats == 3
            }
        }
        input.align()
        return try ZstdFSE(frequencies: frequencies, accuracy: accuracy)
    }

    func entry(_ state: Int) throws -> Entry {
        guard entries.indices.contains(state) else { throw ZstdDecoder.DecodeError.malformed }
        return entries[state]
    }

    func update(_ state: inout Int, bits: inout ZstdReverseBits, padded: Bool = false) throws {
        let entry = try entry(state)
        state = try entry.base + bits.read(entry.bits, padded: padded)
    }

    func decodeWeights(from bytes: [UInt8]) throws -> [Int] {
        var bits = try ZstdReverseBits(bytes)
        var first = try bits.read(accuracy)
        var second = try bits.read(accuracy)
        var weights: [Int] = []
        while weights.count < 255 {
            weights.append(try entry(first).symbol)
            try update(&first, bits: &bits, padded: true)
            if bits.position < 0 {
                weights.append(try entry(second).symbol)
                break
            }
            guard weights.count < 255 else { throw ZstdDecoder.DecodeError.malformed }
            weights.append(try entry(second).symbol)
            try update(&second, bits: &bits, padded: true)
            if bits.position < 0 {
                weights.append(try entry(first).symbol)
                break
            }
        }
        guard bits.position < 0, weights.count <= 255 else { throw ZstdDecoder.DecodeError.malformed }
        return weights
    }
}
