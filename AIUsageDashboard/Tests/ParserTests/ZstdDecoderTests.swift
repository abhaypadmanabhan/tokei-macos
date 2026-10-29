import Foundation
import XCTest
@testable import AIUsageDashboardCore

final class ZstdDecoderTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "zst"))
        return try Data(contentsOf: url)
    }

    private var text: Data {
        Data((0..<5000).map {
            "{\"index\":\($0 % 97),\"message\":\"the quick brown fox visits a quiet room\",\"tokens\":\($0 % 37)}\n"
        }.joined().utf8)
    }

    func testRawRLEAndCompressedBlocks() throws {
        let rawURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "raw", withExtension: "bin"))
        XCTAssertEqual(try ZstdDecoder.decode(fixture("raw")), try Data(contentsOf: rawURL))
        XCTAssertEqual(try ZstdDecoder.decode(fixture("rle")), Data(repeating: 82, count: 300_000))
        for name in ["compressed", "checksum", "high"] {
            XCTAssertEqual(try ZstdDecoder.decode(fixture(name)), text, name)
        }
    }

    func testMultipleFramesAndStreamingBlocks() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "multi", withExtension: "zst"))
        var decoded = Data()
        var chunks = 0
        try ZstdDecoder.decode(fileAt: url) { chunk in
            XCTAssertLessThanOrEqual(chunk.count, 128 * 1024)
            decoded.append(chunk)
            chunks += 1
        }
        XCTAssertGreaterThan(chunks, 2)
        XCTAssertEqual(decoded, text + Data("tail\n".utf8))
    }

    func testMalformedFixturesThrow() throws {
        let names = [
            "truncated", "oversized-window", "corrupt-0", "corrupt-4", "corrupt-9", "corrupt-5518", "corrupt-11035"
        ]
        for name in names {
            XCTAssertThrowsError(try ZstdDecoder.decode(fixture(name)), name)
        }
        var checksum = try fixture("checksum")
        checksum[checksum.count - 1] ^= 1
        XCTAssertThrowsError(try ZstdDecoder.decode(checksum))
        XCTAssertThrowsError(try ZstdDecoder.decode(Data()))
    }

    func testEveryTruncatedPrefixThrows() throws {
        let frame = try fixture("stress")
        for length in 0..<frame.count {
            XCTAssertThrowsError(try ZstdDecoder.decode(Data(frame.prefix(length))), "prefix \(length)")
        }
    }

    func testEveryByteBitFlipCannotCrash() throws {
        let frame = try fixture("stress")
        for offset in frame.indices {
            var damaged = frame
            damaged[offset] ^= 0x80
            do {
                let decoded = try ZstdDecoder.decode(damaged)
                // Unused header bits may change; accepted mutations must retain the content.
                XCTAssertEqual(decoded, Data(text.prefix(2048)), "offset \(offset)")
            } catch {
                XCTAssertTrue(error is ZstdDecoder.DecodeError, "offset \(offset): \(error)")
            }
        }
    }

    func testUnknownContentSizeAndCircularWindow() throws {
        XCTAssertEqual(try ZstdDecoder.decode(fixture("window")), Data(text.prefix(50_000)))
    }

    func testStreamingOutputLimitAndMultipleFrameLimit() throws {
        for name in ["output-limit", "multi-output-limit"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "zst"))
            var bytes = 0
            XCTAssertThrowsError(try ZstdDecoder.decode(fileAt: url) { bytes += $0.count }) { error in
                guard case ZstdDecoder.DecodeError.outputTooLarge = error else {
                    return XCTFail("Wrong error: \(error)")
                }
            }
            XCTAssertEqual(bytes, 256 * 1024 * 1024)
        }
    }

    func testContentSizeTrailingGarbageAndSkippableFrames() throws {
        let tail = try fixture("tail")
        // CLI stdin compression omits content size; byte 5 of tail is a window descriptor.
        // Supply a single-segment header explicitly, and prove it valid before mutation.
        let knownSize = Data([0x28, 0xb5, 0x2f, 0xfd, 0x24, 5]) + tail.dropFirst(6)
        XCTAssertEqual(try ZstdDecoder.decode(knownSize), Data("tail\n".utf8))
        var wrongSize = knownSize
        wrongSize[5] = 6
        XCTAssertThrowsError(try ZstdDecoder.decode(wrongSize))
        XCTAssertThrowsError(try ZstdDecoder.decode(tail + Data([0])))
        let skippable = Data([0x50, 0x2a, 0x4d, 0x18, 3, 0, 0, 0, 1, 2, 3])
        XCTAssertEqual(try ZstdDecoder.decode(skippable + tail + skippable), Data("tail\n".utf8))
        let empty = Data([0x28, 0xb5, 0x2f, 0xfd, 0x20, 0, 1, 0, 0])
        XCTAssertEqual(try ZstdDecoder.decode(empty), Data())
    }

    func testAllContentSizeFieldWidths() throws {
        let raw = try fixture("raw")
        let rawURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "raw", withExtension: "bin"))
        let expected = try Data(contentsOf: rawURL)
        let fields: [(UInt8, [UInt8])] = [
            (0x60, [0, 3]), // 768 + 256 = 1024.
            (0xa0, [0, 4, 0, 0]),
            (0xe0, [0, 4, 0, 0, 0, 0, 0, 0])
        ]
        for (descriptor, size) in fields {
            let frame = Data([0x28, 0xb5, 0x2f, 0xfd, descriptor] + size) + raw.dropFirst(6)
            XCTAssertEqual(try ZstdDecoder.decode(frame), expected)
        }
    }

    func testSlicedInputAndConsumerError() throws {
        let padded = Data([0, 1]) + (try fixture("stress"))
        XCTAssertEqual(try ZstdDecoder.decode(padded.dropFirst(2)), Data(text.prefix(2048)))
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "compressed", withExtension: "zst"))
        enum ConsumerError: Error { case stopped }
        var chunks = 0
        XCTAssertThrowsError(try ZstdDecoder.decode(fileAt: url) { _ in
            chunks += 1
            throw ConsumerError.stopped
        }) { error in
            XCTAssertTrue(error is ConsumerError)
        }
        XCTAssertEqual(chunks, 1)
    }

    func testChecksumVectorsAndIncrementalUpdates() {
        XCTAssertEqual(ZstdXXHash().digest, 0xef46db3751d8e999)
        var hash = ZstdXXHash()
        hash.update(Array("a".utf8))
        hash.update(Array("bc".utf8))
        XCTAssertEqual(hash.digest, 0x44bc2cf5ad770999)
        let bytes = Array(text)
        var whole = ZstdXXHash()
        whole.update(bytes)
        var split = ZstdXXHash()
        for offset in stride(from: 0, to: bytes.count, by: 13) {
            split.update(Array(bytes[offset..<min(offset + 13, bytes.count)]))
        }
        XCTAssertEqual(split.digest, whole.digest)
    }

    func testDictionaryReservedBlockAndOversizedContentThrow() throws {
        let dictionary = Data([0x28, 0xb5, 0x2f, 0xfd, 0x21, 1, 0, 1, 0, 0])
        XCTAssertThrowsError(try ZstdDecoder.decode(dictionary))
        let reservedBlock = Data([0x28, 0xb5, 0x2f, 0xfd, 0x20, 0, 7, 0, 0])
        XCTAssertThrowsError(try ZstdDecoder.decode(reservedBlock))
        let hugeContent = Data([0x28, 0xb5, 0x2f, 0xfd, 0xe0] + Array(repeating: 255, count: 8))
        XCTAssertThrowsError(try ZstdDecoder.decode(hugeContent))
    }
}
