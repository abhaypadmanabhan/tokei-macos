// Port of facebook/zstd educational_decoder; Copyright Meta Platforms, Inc. and affiliates.
// BSD-3-Clause; see THIRD_PARTY_NOTICES.md.
import Foundation

/// Pure Swift Zstandard frames, no dictionaries. Tables and history never cross frame boundaries.
enum ZstdDecoder {
    static let maximumWindowSize = 128 * 1024 * 1024
    static let maximumOutputSize = 256 * 1024 * 1024
    static let maximumBlockSize = 128 * 1024

    enum DecodeError: Error {
        case malformed
        case truncated
        case dictionaryUnsupported
        case windowTooLarge
        case outputTooLarge
        case checksumMismatch
    }

    static func decode(_ data: Data) throws -> Data {
        var output = Data()
        try decode(input: ZstdInput(data: data)) { output.append($0) }
        return output
    }

    /// Chunks are provisional until this returns successfully: a later checksum or frame may fail.
    static func decode(fileAt url: URL, onChunk: (Data) throws -> Void) throws {
        try decode(input: ZstdInput(fileAt: url), onChunk: onChunk)
    }

    private static func decode(input: ZstdInput, onChunk: (Data) throws -> Void) throws {
        var total = 0
        var sawFrame = false
        while true {
            let bytes = try input.read(4, allowEOF: true)
            if bytes.isEmpty { break }
            let magic = bytes.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
            if magic & 0xfffffff0 == 0x184d2a50 {
                var left = try input.integer(4)
                while left > 0 {
                    let count = Int(min(left, UInt64(maximumBlockSize)))
                    _ = try input.read(count)
                    left -= UInt64(count)
                }
                sawFrame = true
                continue
            }
            guard magic == 0xfd2fb528 else { throw DecodeError.malformed }
            sawFrame = true
            try decodeFrame(input: input, total: &total, onChunk: onChunk)
        }
        guard sawFrame else { throw DecodeError.truncated }
    }

    private static func decodeFrame(input: ZstdInput, total: inout Int, onChunk: (Data) throws -> Void) throws {
        let header = try ZstdFrameHeader(input)
        if let size = header.contentSize, size > maximumOutputSize - total { throw DecodeError.outputTooLarge }
        let frame = ZstdFrame(header: header)
        var checksum = ZstdXXHash()
        var last = false
        while !last {
            let blockHeader = try input.integer(3)
            last = blockHeader & 1 != 0
            let type = Int((blockHeader >> 1) & 3)
            let size = Int(blockHeader >> 3)
            guard size <= frame.blockLimit else { throw DecodeError.malformed }
            let block = try frame.block(type: type, size: size, input: input, remaining: maximumOutputSize - total)
            guard block.count <= maximumOutputSize - total else { throw DecodeError.outputTooLarge }
            total += block.count
            try frame.remember(block)
            if header.hasChecksum { checksum.update(block) }
            if !block.isEmpty { try onChunk(Data(block)) }
        }
        if let size = header.contentSize, frame.produced != size { throw DecodeError.malformed }
        if header.hasChecksum {
            let expected = try input.integer(4)
            guard expected == checksum.digest & 0xffffffff else { throw DecodeError.checksumMismatch }
        }
    }
}

struct ZstdFrameHeader {
    let window: Int
    let contentSize: Int?
    let hasChecksum: Bool

    init(_ input: ZstdInput) throws {
        let descriptor = try input.integer(1)
        guard descriptor & 8 == 0 else { throw ZstdDecoder.DecodeError.malformed }
        let single = descriptor & 32 != 0
        let sizeFlag = Int(descriptor >> 6)
        var window: UInt64 = 0
        if !single {
            let byte = try input.integer(1)
            // The descriptor exponent is at most 31, so this shift is <=41.
            let base = UInt64(1) << (10 + (byte >> 3))
            window = base + (base / 8) * (byte & 7)
            guard window <= ZstdDecoder.maximumWindowSize else { throw ZstdDecoder.DecodeError.windowTooLarge }
        }
        let dictionaryBytes = [0, 1, 2, 4][Int(descriptor & 3)]
        guard try input.integer(dictionaryBytes) == 0 else { throw ZstdDecoder.DecodeError.dictionaryUnsupported }
        var content: UInt64?
        if single || sizeFlag != 0 {
            let size = try input.integer([1, 2, 4, 8][sizeFlag])
            // The +256 adjustment applies only to a 16-bit field, never UInt64.max.
            content = sizeFlag == 1 ? size + 256 : size
        }
        if let content, content > ZstdDecoder.maximumOutputSize { throw ZstdDecoder.DecodeError.outputTooLarge }
        if single { window = content ?? 0 }
        guard window <= ZstdDecoder.maximumWindowSize else { throw ZstdDecoder.DecodeError.windowTooLarge }
        self.window = Int(window)
        contentSize = content.map(Int.init)
        hasChecksum = descriptor & 4 != 0
    }
}
