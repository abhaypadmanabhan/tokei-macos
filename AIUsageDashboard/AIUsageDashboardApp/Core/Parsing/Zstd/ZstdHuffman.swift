// Port of facebook/zstd educational_decoder; Copyright Meta Platforms, Inc. and affiliates.
// BSD-3-Clause; see THIRD_PARTY_NOTICES.md.
import Foundation

struct ZstdHuffman {
    private let symbols: [UInt8]
    private let widths: [Int]
    private let depth: Int

    static func read(from input: inout ZstdBits) throws -> ZstdHuffman {
        let header = try input.read(8)
        var weights: [Int] = []
        if header >= 128 {
            let count = header - 127
            let bytes = try input.take((count + 1) / 2)
            weights = (0..<count).map { index in
                index % 2 == 0 ? Int(bytes[index / 2] >> 4) : Int(bytes[index / 2] & 15)
            }
        } else {
            var encoded = try ZstdBits(input.take(header))
            let table = try ZstdFSE.read(from: &encoded, maxAccuracy: 7, maxSymbol: 255)
            weights = try table.decodeWeights(from: encoded.take(encoded.remainingBytes))
        }
        return try ZstdHuffman(weights: weights)
    }

    private init(weights: [Int]) throws {
        guard !weights.isEmpty, weights.count < 256 else { throw ZstdDecoder.DecodeError.malformed }
        let (bitCounts, depth) = try Self.bitCounts(weights: weights)
        let (symbols, widths) = try Self.canonicalTable(bitCounts: bitCounts, depth: depth)
        self.depth = depth
        self.symbols = symbols
        self.widths = widths
    }

    private static func bitCounts(weights: [Int]) throws -> ([Int], Int) {
        var sum = 0
        for weight in weights {
            guard (0...11).contains(weight) else { throw ZstdDecoder.DecodeError.malformed }
            if weight > 0 { sum += 1 << (weight - 1) }
        }
        guard sum > 0 else { throw ZstdDecoder.DecodeError.malformed }
        let depth = Int.bitWidth - sum.leadingZeroBitCount
        guard depth <= 11 else { throw ZstdDecoder.DecodeError.malformed }
        let remainder = (1 << depth) - sum
        guard remainder > 0, remainder & (remainder - 1) == 0 else { throw ZstdDecoder.DecodeError.malformed }
        let lastWeight = Int.bitWidth - remainder.leadingZeroBitCount
        let bitCounts = (weights + [lastWeight]).map { $0 == 0 ? 0 : depth + 1 - $0 }
        return (bitCounts, depth)
    }

    private static func canonicalTable(bitCounts: [Int], depth: Int) throws -> ([UInt8], [Int]) {
        var ranks = [Int](repeating: 0, count: depth + 1)
        for width in bitCounts {
            guard (0...depth).contains(width) else { throw ZstdDecoder.DecodeError.malformed }
            ranks[width] += 1
        }
        var starts = [Int](repeating: 0, count: depth + 1)
        let size = 1 << depth
        for width in stride(from: depth, through: 1, by: -1) {
            starts[width - 1] = starts[width] + ranks[width] * (1 << (depth - width))
        }
        guard starts[0] == size else { throw ZstdDecoder.DecodeError.malformed }
        var symbols = [UInt8](repeating: 0, count: size)
        var widths = [Int](repeating: 0, count: size)
        for (symbol, width) in bitCounts.enumerated() where width > 0 {
            let start = starts[width]
            let count = 1 << (depth - width)
            guard start >= 0, count <= size - start else { throw ZstdDecoder.DecodeError.malformed }
            for index in start..<start + count {
                symbols[index] = UInt8(symbol) // At most 256 validated symbols.
                widths[index] = width
            }
            starts[width] += count
        }
        return (symbols, widths)
    }

    func decode(_ input: inout ZstdBits, count: Int, fourStreams: Bool) throws -> [UInt8] {
        if !fourStreams { return try stream(input.take(input.remainingBytes), count: count) }
        let lengths = try [input.read(16), input.read(16), input.read(16)]
        let segment = (count + 3) / 4
        guard count >= 3 * segment else { throw ZstdDecoder.DecodeError.malformed }
        var output: [UInt8] = []
        output.reserveCapacity(count)
        for length in lengths { output += try stream(input.take(length), count: segment) }
        output += try stream(input.take(input.remainingBytes), count: count - 3 * segment)
        return output
    }

    private func stream(_ bytes: [UInt8], count: Int) throws -> [UInt8] {
        guard count > 0, count <= ZstdDecoder.maximumBlockSize else { throw ZstdDecoder.DecodeError.malformed }
        var bits = try ZstdReverseBits(bytes)
        var state = try bits.read(depth, padded: true)
        var output: [UInt8] = []
        output.reserveCapacity(count)
        for _ in 0..<count {
            guard bits.position > -depth, symbols.indices.contains(state), widths[state] > 0 else {
                throw ZstdDecoder.DecodeError.malformed
            }
            output.append(symbols[state])
            let width = widths[state]
            state = try ((state << width) + bits.read(width, padded: true)) & ((1 << depth) - 1)
        }
        guard bits.position == -depth else { throw ZstdDecoder.DecodeError.malformed }
        return output
    }
}
