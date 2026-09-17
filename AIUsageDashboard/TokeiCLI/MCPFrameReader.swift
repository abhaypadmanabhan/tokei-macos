import Darwin
import Foundation

/// Bounded newline framing for the stdio transport. Once a frame exceeds the cap,
/// bytes are discarded directly from the input until the next delimiter instead of
/// being accumulated in memory.
struct MCPFrameReader {
    static let maximumFrameBytes = 1024 * 1024
    private static let readChunkBytes = 64 * 1024

    enum Frame: Equatable {
        case data(Data)
        case oversized
    }

    private let readChunk: (Int) -> Data?
    private var buffer = Data()
    private var discardingOversizedFrame = false
    private(set) var peakBufferedByteCount = 0

    init(readChunk: @escaping (Int) -> Data?) {
        self.readChunk = readChunk
    }

    init(fileHandle: FileHandle) {
        self.init(fileDescriptor: fileHandle.fileDescriptor)
    }

    init(fileDescriptor: Int32) {
        self.init { requestedBytes in
            autoreleasepool {
                var bytes = [UInt8](repeating: 0, count: requestedBytes)
                while true {
                    let byteCount = bytes.withUnsafeMutableBytes {
                        Darwin.read(fileDescriptor, $0.baseAddress, $0.count)
                    }
                    if byteCount > 0 { return Data(bytes.prefix(byteCount)) }
                    if byteCount == 0 || errno != EINTR { return nil }
                }
            }
        }
    }

    mutating func nextFrame() -> Frame? {
        while true {
            if discardingOversizedFrame {
                guard let chunk = readChunk(Self.readChunkBytes), !chunk.isEmpty else {
                    discardingOversizedFrame = false
                    return nil
                }
                guard let delimiter = chunk.firstIndex(of: 0x0A) else { continue }

                discardingOversizedFrame = false
                let suffixStart = chunk.index(after: delimiter)
                if suffixStart < chunk.endIndex {
                    buffer.append(contentsOf: chunk[suffixStart...])
                    recordPeak()
                }
                continue
            }

            if let delimiter = buffer.firstIndex(of: 0x0A) {
                let frameByteCount = buffer.distance(from: buffer.startIndex, to: delimiter)
                let frame = Data(buffer[..<delimiter])
                buffer.removeSubrange(buffer.startIndex...delimiter)
                return frameByteCount <= Self.maximumFrameBytes ? .data(frame) : .oversized
            }

            if buffer.count > Self.maximumFrameBytes {
                buffer.removeAll(keepingCapacity: false)
                discardingOversizedFrame = true
                return .oversized
            }

            let remainingCapacity = Self.maximumFrameBytes + 1 - buffer.count
            let requestedBytes = min(Self.readChunkBytes, remainingCapacity)
            guard let chunk = readChunk(requestedBytes), !chunk.isEmpty else {
                guard !buffer.isEmpty else { return nil }
                let frame = buffer
                buffer.removeAll(keepingCapacity: false)
                return .data(frame)
            }
            buffer.append(chunk)
            recordPeak()
        }
    }

    private mutating func recordPeak() {
        peakBufferedByteCount = max(peakBufferedByteCount, buffer.count)
    }
}
