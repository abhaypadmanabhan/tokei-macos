// Port of facebook/zstd educational_decoder; Copyright Meta Platforms, Inc. and affiliates.
// BSD-3-Clause; see THIRD_PARTY_NOTICES.md.
import Foundation

final class ZstdFrame {
    let header: ZstdFrameHeader
    let blockLimit: Int
    private(set) var produced = 0
    private var history: [UInt8] = []
    private var historyNext = 0
    private var huffman: ZstdHuffman?
    private var literalTable: ZstdFSE?
    private var offsetTable: ZstdFSE?
    private var matchTable: ZstdFSE?
    private var offsets = [1, 4, 8]

    init(header: ZstdFrameHeader) {
        self.header = header
        blockLimit = min(header.window, ZstdDecoder.maximumBlockSize)
    }

    func block(type: Int, size: Int, input: ZstdInput, remaining: Int) throws -> [UInt8] {
        switch type {
        case 0:
            guard size <= remaining else { throw ZstdDecoder.DecodeError.outputTooLarge }
            return try input.read(size)
        case 1:
            guard size <= remaining else { throw ZstdDecoder.DecodeError.outputTooLarge }
            return try Array(repeating: UInt8(input.integer(1)), count: size)
        case 2:
            var bits = try ZstdBits(input.read(size))
            let literals = try literals(from: &bits)
            return try sequences(from: &bits, literals: literals, limit: min(blockLimit, remaining))
        default: throw ZstdDecoder.DecodeError.malformed
        }
    }

    func remember(_ bytes: [UInt8]) throws {
        guard bytes.count <= ZstdDecoder.maximumOutputSize - produced else {
            throw ZstdDecoder.DecodeError.outputTooLarge
        }
        if let size = header.contentSize, bytes.count > size - produced {
            throw ZstdDecoder.DecodeError.malformed
        }
        produced += bytes.count
        guard !bytes.isEmpty else { return }
        // Grow only as bytes arrive, then retain a circular window. No advertised-size allocation.
        let growth = min(header.window - history.count, bytes.count)
        if growth > 0 {
            history.append(contentsOf: bytes.prefix(growth))
            historyNext = history.count == header.window ? 0 : history.count
        }
        var cursor = growth
        while cursor < bytes.count {
            // Each contiguous copy is bounded by the end of the ring and the source block.
            let length = min(history.count - historyNext, bytes.count - cursor)
            history.replaceSubrange(historyNext..<historyNext + length, with: bytes[cursor..<cursor + length])
            cursor += length
            historyNext += length
            if historyNext == history.count { historyNext = 0 }
        }
    }

    private func literals(from input: inout ZstdBits) throws -> [UInt8] {
        let type = try input.read(2)
        let format = try input.read(2)
        if type <= 1 {
            let size: Int
            if format & 1 == 0 {
                try input.rewindOneBit()
                size = try input.read(5)
            } else { size = try input.read(format == 1 ? 12 : 20) }
            guard size <= blockLimit else { throw ZstdDecoder.DecodeError.malformed }
            return type == 0 ? try input.take(size) : try Array(repeating: UInt8(input.read(8)), count: size)
        }
        let width = format <= 1 ? 10 : (format == 2 ? 14 : 18)
        let size = try input.read(width)
        let compressedSize = try input.read(width)
        guard size <= blockLimit else { throw ZstdDecoder.DecodeError.malformed }
        var encoded = try ZstdBits(input.take(compressedSize))
        if type == 2 { huffman = try ZstdHuffman.read(from: &encoded) }
        guard let huffman else { throw ZstdDecoder.DecodeError.malformed }
        return try huffman.decode(&encoded, count: size, fourStreams: format != 0)
    }

    private func sequences(from input: inout ZstdBits, literals: [UInt8], limit: Int) throws -> [UInt8] {
        let count = try sequenceCount(from: &input)
        if count == 0 {
            guard input.remainingBytes == 0, literals.count <= limit else { throw ZstdDecoder.DecodeError.malformed }
            return literals
        }
        // Every sequence emits at least three match bytes, even if it consumes no bits.
        guard count <= limit / 3 else { throw ZstdDecoder.DecodeError.malformed }
        let modes = try input.read(8)
        guard modes & 3 == 0 else { throw ZstdDecoder.DecodeError.malformed }
        literalTable = try table(mode: modes >> 6, part: 0, previous: literalTable, input: &input)
        offsetTable = try table(mode: (modes >> 4) & 3, part: 1, previous: offsetTable, input: &input)
        matchTable = try table(mode: (modes >> 2) & 3, part: 2, previous: matchTable, input: &input)
        guard let literalTable, let offsetTable, let matchTable else { throw ZstdDecoder.DecodeError.malformed }
        var bits = try ZstdReverseBits(input.take(input.remainingBytes))
        var literalState = try bits.read(literalTable.accuracy)
        var offsetState = try bits.read(offsetTable.accuracy)
        var matchState = try bits.read(matchTable.accuracy)
        var output = ZstdBlockBuffer(limit: limit)
        var literalCursor = 0
        for index in 0..<count {
            let literalCode = try literalTable.entry(literalState).symbol
            let offsetCode = try offsetTable.entry(offsetState).symbol
            let matchCode = try matchTable.entry(matchState).symbol
            guard literalCode <= 35, matchCode <= 52, offsetCode <= 31 else {
                throw ZstdDecoder.DecodeError.malformed
            }
            let offsetValue = try (1 << offsetCode) + bits.read(offsetCode)
            let matchLength = try ZstdSequenceTables.matchBases[matchCode]
                + bits.read(ZstdSequenceTables.matchBits[matchCode])
            let literalLength = try ZstdSequenceTables.literalBases[literalCode]
                + bits.read(ZstdSequenceTables.literalBits[literalCode])
            try output.copy(literals, cursor: &literalCursor, count: literalLength)
            let offset = try repeatOffset(offsetValue, noLiterals: literalLength == 0)
            try output.match(
                offset: offset, count: matchLength, history: history, next: historyNext, window: header.window
            )
            if index + 1 < count {
                try literalTable.update(&literalState, bits: &bits)
                try matchTable.update(&matchState, bits: &bits)
                try offsetTable.update(&offsetState, bits: &bits)
            }
        }
        guard bits.position == 0 else { throw ZstdDecoder.DecodeError.malformed }
        try output.copy(literals, cursor: &literalCursor, count: literals.count - literalCursor)
        return output.bytes
    }

    private func sequenceCount(from input: inout ZstdBits) throws -> Int {
        let byte = try input.read(8)
        if byte < 128 { return byte }
        if byte < 255 { return try ((byte - 128) << 8) + input.read(8) }
        return try input.read(16) + 0x7f00
    }

    private func table(mode: Int, part: Int, previous: ZstdFSE?, input: inout ZstdBits) throws -> ZstdFSE {
        let maximum = [35, 31, 52][part]
        switch mode {
        case 0:
            return try ZstdFSE(frequencies: ZstdSequenceTables.distributions[part], accuracy: [6, 5, 6][part])
        case 1:
            let symbol = try input.read(8)
            guard symbol <= maximum else { throw ZstdDecoder.DecodeError.malformed }
            return ZstdFSE(symbol: symbol)
        case 2:
            return try ZstdFSE.read(from: &input, maxAccuracy: [9, 8, 9][part], maxSymbol: maximum)
        case 3:
            guard let previous else { throw ZstdDecoder.DecodeError.malformed }
            return previous
        default: throw ZstdDecoder.DecodeError.malformed
        }
    }

    private func repeatOffset(_ value: Int, noLiterals: Bool) throws -> Int {
        let offset: Int
        if value <= 3 {
            let index = value - 1 + (noLiterals ? 1 : 0)
            offset = index == 3 ? offsets[0] - 1 : offsets[index]
            guard offset > 0 else { throw ZstdDecoder.DecodeError.malformed }
            if index == 0 { return offset }
            if index > 1 { offsets[2] = offsets[1] }
        } else {
            offset = value - 3
            offsets[2] = offsets[1]
        }
        offsets[1] = offsets[0]
        offsets[0] = offset
        return offset
    }
}

/// Writes are bounded before any copy, including overlapping matches and circular history.
private struct ZstdBlockBuffer {
    private var storage: [UInt8]
    private var count = 0
    var bytes: [UInt8] { Array(storage.prefix(count)) }

    init(limit: Int) { storage = [UInt8](repeating: 0, count: limit) }

    mutating func copy(_ literals: [UInt8], cursor: inout Int, count length: Int) throws {
        guard length >= 0, cursor <= literals.count, length <= literals.count - cursor,
              length <= storage.count - count else { throw ZstdDecoder.DecodeError.malformed }
        for index in 0..<length { storage[count + index] = literals[cursor + index] }
        count += length
        cursor += length
    }

    mutating func match(offset: Int, count length: Int, history: [UInt8], next: Int, window: Int) throws {
        guard offset > 0, offset <= window, offset <= history.count + count,
              length >= 0, length <= storage.count - count else { throw ZstdDecoder.DecodeError.malformed }
        // The offset guard ensures every source is in history or in bytes already emitted.
        storage.withUnsafeMutableBufferPointer { buffer in
            for index in count..<count + length {
                if offset <= index { buffer[index] = buffer[index - offset] } else {
                    let historyIndex = (next + history.count - (offset - index)) % history.count
                    buffer[index] = history[historyIndex]
                }
            }
        }
        count += length
    }
}
