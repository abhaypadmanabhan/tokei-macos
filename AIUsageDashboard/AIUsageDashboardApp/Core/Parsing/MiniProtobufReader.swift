import Foundation

public struct MiniProtobufReader: Sendable {
    public enum WireType: Int, Sendable {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    public enum Value: Sendable, Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case lengthDelimited(Data, nestedFields: [Field])
        case fixed32(UInt32)
    }

    public struct Field: Sendable, Equatable {
        public let number: Int
        public let wireType: WireType
        public let value: Value

        public init(number: Int, wireType: WireType, value: Value) {
            self.number = number
            self.wireType = wireType
            self.value = value
        }
    }

    private let maximumNestedDepth = 16

    public init() {}

    public func parse(_ data: Data) -> [Field] {
        parseFields(Array(data), depth: 0, strict: false) ?? []
    }

    private func parseFields(_ bytes: [UInt8], depth: Int, strict: Bool) -> [Field]? {
        var offset = 0
        var fields: [Field] = []

        while offset < bytes.count {
            guard let key = readVarint(bytes, offset: &offset) else {
                return strict ? nil : fields
            }

            let fieldNumber = Int(key >> 3)
            let rawWireType = Int(key & 0x7)
            guard fieldNumber > 0, let wireType = WireType(rawValue: rawWireType) else {
                return strict ? nil : fields
            }

            switch wireType {
            case .varint:
                guard let value = readVarint(bytes, offset: &offset) else {
                    return strict ? nil : fields
                }
                fields.append(Field(number: fieldNumber, wireType: wireType, value: .varint(value)))

            case .fixed64:
                guard let value = readFixed64(bytes, offset: &offset) else {
                    return strict ? nil : fields
                }
                fields.append(Field(number: fieldNumber, wireType: wireType, value: .fixed64(value)))

            case .lengthDelimited:
                guard let length = readVarint(bytes, offset: &offset),
                      length <= UInt64(bytes.count - offset) else {
                    return strict ? nil : fields
                }

                let end = offset + Int(length)
                let payload = Array(bytes[offset..<end])
                offset = end

                let nestedFields: [Field]
                if depth < maximumNestedDepth,
                   let parsedNestedFields = parseFields(payload, depth: depth + 1, strict: true),
                   !parsedNestedFields.isEmpty {
                    nestedFields = parsedNestedFields
                } else {
                    nestedFields = []
                }

                fields.append(Field(
                    number: fieldNumber,
                    wireType: wireType,
                    value: .lengthDelimited(Data(payload), nestedFields: nestedFields)
                ))

            case .fixed32:
                guard let value = readFixed32(bytes, offset: &offset) else {
                    return strict ? nil : fields
                }
                fields.append(Field(number: fieldNumber, wireType: wireType, value: .fixed32(value)))
            }
        }

        return fields
    }

    private func readVarint(_ bytes: [UInt8], offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        for _ in 0..<10 {
            guard offset < bytes.count else { return nil }
            let byte = bytes[offset]
            offset += 1

            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        return nil
    }

    private func readFixed32(_ bytes: [UInt8], offset: inout Int) -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        var result: UInt32 = 0
        for index in 0..<4 {
            result |= UInt32(bytes[offset + index]) << UInt32(index * 8)
        }
        offset += 4
        return result
    }

    private func readFixed64(_ bytes: [UInt8], offset: inout Int) -> UInt64? {
        guard offset + 8 <= bytes.count else { return nil }
        var result: UInt64 = 0
        for index in 0..<8 {
            result |= UInt64(bytes[offset + index]) << UInt64(index * 8)
        }
        offset += 8
        return result
    }
}
