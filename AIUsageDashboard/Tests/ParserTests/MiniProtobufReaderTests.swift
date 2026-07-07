import XCTest
@testable import AIUsageDashboardCore

final class MiniProtobufReaderTests: XCTestCase {
    func testParsesNestedFixedAndUnknownFieldsWithoutThrowing() {
        let fields = MiniProtobufReader().parse(Data(hexString: AntigravityFixtures.miniReaderMixedWireHex))

        XCTAssertEqual(fields.map(\.number), [1, 99, 3, 4, 2])

        guard case .lengthDelimited(let nestedData, let nestedFields) = fields[0].value else {
            return XCTFail("field 1 should be length-delimited")
        }
        XCTAssertEqual(nestedData, Data(hexString: AntigravityFixtures.miniReaderNestedPayloadHex))
        XCTAssertEqual(nestedFields.count, 1)
        XCTAssertEqual(nestedFields[0].number, 1)
        XCTAssertEqual(nestedFields[0].wireType, .varint)
        XCTAssertEqual(nestedFields[0].varintValue, 150)

        XCTAssertEqual(fields[1].number, 99)
        XCTAssertEqual(fields[1].varintValue, 7)
        XCTAssertEqual(fields[2].fixed32Value, 0x11223344)
        XCTAssertEqual(fields[3].fixed64Value, 0x0102030405060708)

        guard case .lengthDelimited(let stringData, let stringNestedFields) = fields[4].value else {
            return XCTFail("field 2 should be length-delimited")
        }
        XCTAssertEqual(String(data: stringData, encoding: .utf8), "ok")
        XCTAssertTrue(stringNestedFields.isEmpty)
    }

    func testMalformedUnknownWireTypeDoesNotThrowAndKeepsEarlierFields() {
        let fields = MiniProtobufReader().parse(Data(hexString: AntigravityFixtures.malformedUnknownWireHex))

        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].number, 1)
        XCTAssertEqual(fields[0].varintValue, 1)
    }
}

private extension MiniProtobufReader.Field {
    var varintValue: UInt64? {
        guard case .varint(let value) = value else { return nil }
        return value
    }

    var fixed32Value: UInt32? {
        guard case .fixed32(let value) = value else { return nil }
        return value
    }

    var fixed64Value: UInt64? {
        guard case .fixed64(let value) = value else { return nil }
        return value
    }
}

private extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
