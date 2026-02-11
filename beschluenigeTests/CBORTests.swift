import Foundation
import SwiftCBOR
import Testing
@testable import beschluenige

@MainActor
struct CBOREncoderTests {

    // MARK: - Unsigned integers

    @Test func encodeSmallUInt() throws {
        var enc = CBOREncoder()
        enc.encodeUInt(23)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .unsignedInt(23))
    }

    @Test func encodeUInt8() throws {
        var enc = CBOREncoder()
        enc.encodeUInt(200)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .unsignedInt(200))
    }

    @Test func encodeUInt16() throws {
        var enc = CBOREncoder()
        enc.encodeUInt(1000)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .unsignedInt(1000))
    }

    @Test func encodeUInt32() throws {
        var enc = CBOREncoder()
        enc.encodeUInt(100_000)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .unsignedInt(100_000))
    }

    @Test func encodeUInt64() throws {
        var enc = CBOREncoder()
        enc.encodeUInt(5_000_000_000)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .unsignedInt(5_000_000_000))
    }

    // MARK: - Float64

    @Test func encodeFloat64() throws {
        var enc = CBOREncoder()
        enc.encodeFloat64(3.14159)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .double(3.14159))
    }

    @Test func encodeFloat64Negative() throws {
        var enc = CBOREncoder()
        enc.encodeFloat64(-42.5)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .double(-42.5))
    }

    @Test func encodeFloat64Zero() throws {
        var enc = CBOREncoder()
        enc.encodeFloat64(0.0)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .double(0.0))
    }

    // MARK: - Strings

    @Test func encodeString() throws {
        var enc = CBOREncoder()
        enc.encodeString("hello")
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .utf8String("hello"))
    }

    @Test func encodeEmptyString() throws {
        var enc = CBOREncoder()
        enc.encodeString("")
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .utf8String(""))
    }

    // MARK: - Byte strings

    @Test func encodeBytes() throws {
        var enc = CBOREncoder()
        enc.encodeBytes(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .byteString([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    // MARK: - Arrays

    @Test func encodeDefiniteArray() throws {
        var enc = CBOREncoder()
        enc.encodeArrayHeader(count: 3)
        enc.encodeUInt(1)
        enc.encodeUInt(2)
        enc.encodeUInt(3)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)]))
    }

    @Test func encodeIndefiniteArray() throws {
        var enc = CBOREncoder()
        enc.encodeIndefiniteArrayHeader()
        enc.encodeFloat64(1.0)
        enc.encodeFloat64(2.0)
        enc.encodeBreak()
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .array([.double(1.0), .double(2.0)]))
    }

    @Test func encodeEmptyArray() throws {
        var enc = CBOREncoder()
        enc.encodeArrayHeader(count: 0)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .array([]))
    }

    // MARK: - Maps

    @Test func encodeMap() throws {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 2)
        enc.encodeUInt(0)
        enc.encodeString("hr")
        enc.encodeUInt(1)
        enc.encodeString("gps")
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .map([
            .unsignedInt(0): .utf8String("hr"),
            .unsignedInt(1): .utf8String("gps"),
        ]))
    }

    @Test func encodeEmptyMap() throws {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 0)
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .map([:]))
    }

    // MARK: - Float64 array convenience

    @Test func encodeFloat64Array() throws {
        var enc = CBOREncoder()
        enc.encodeFloat64Array([10.0, 20.0, 30.0])
        let decoded = try CBOR.decode([UInt8](enc.data))
        #expect(decoded == .array([.double(10.0), .double(20.0), .double(30.0)]))
    }

    // MARK: - Chunk-shaped data

    @Test func encodeChunkShape() throws {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)

        enc.encodeUInt(0)
        enc.encodeArrayHeader(count: 1)
        enc.encodeFloat64Array([1000.0, 120.0])

        enc.encodeUInt(1)
        enc.encodeArrayHeader(count: 0)

        enc.encodeUInt(2)
        enc.encodeArrayHeader(count: 0)

        enc.encodeUInt(3)
        enc.encodeArrayHeader(count: 0)

        let decoded = try CBOR.decode([UInt8](enc.data))
        guard case .map(let map) = decoded else {
            Issue.record("Expected map")
            return
        }
        #expect(map.count == 4)
        #expect(map[.unsignedInt(0)] == .array([
            .array([.double(1000.0), .double(120.0)]),
        ]))
    }
}

@MainActor
struct CBORDecoderTests {

    // MARK: - Unsigned integers

    @Test func decodeSmallUInt() throws {
        let bytes = SwiftCBOR.CBOR.encode(UInt64(23))
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeUInt()
        #expect(value == 23)
        #expect(dec.isAtEnd)
    }

    @Test func decodeUInt64() throws {
        let bytes = SwiftCBOR.CBOR.encode(UInt64(5_000_000_000))
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeUInt()
        #expect(value == 5_000_000_000)
    }

    @Test func decodeUInt8Width() throws {
        let bytes = SwiftCBOR.CBOR.encode(UInt64(200))
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeUInt()
        #expect(value == 200)
    }

    @Test func decodeUInt16Width() throws {
        let bytes = SwiftCBOR.CBOR.encode(UInt64(1000))
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeUInt()
        #expect(value == 1000)
    }

    @Test func decodeUInt32Width() throws {
        let bytes = SwiftCBOR.CBOR.encode(UInt64(100_000))
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeUInt()
        #expect(value == 100_000)
    }

    // MARK: - Float64

    @Test func decodeFloat64() throws {
        let bytes = SwiftCBOR.CBOR.encodeDouble(3.14159)
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeFloat64()
        #expect(value == 3.14159)
    }

    // MARK: - Strings

    @Test func decodeString() throws {
        let bytes = SwiftCBOR.CBOR.encodeString("hello")
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeString()
        #expect(value == "hello")
    }

    @Test func decodeStringUInt16Length() throws {
        let longString = String(repeating: "x", count: 300)
        let bytes = SwiftCBOR.CBOR.encodeString(longString)
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeString()
        #expect(value == longString)
    }

    @Test func decodeStringUInt32Length() throws {
        let longString = String(repeating: "a", count: 70_000)
        let bytes = SwiftCBOR.CBOR.encodeString(longString)
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeString()
        #expect(value.count == 70_000)
    }

    // MARK: - Byte strings

    @Test func decodeBytes() throws {
        let bytes = SwiftCBOR.CBOR.encodeByteString([0xDE, 0xAD])
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeBytes()
        #expect(value == Data([0xDE, 0xAD]))
    }

    @Test func decodeByteStringUInt8Width() throws {
        let payload = [UInt8](repeating: 0xAB, count: 30)
        let bytes = SwiftCBOR.CBOR.encodeByteString(payload)
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeBytes()
        #expect(value.count == 30)
    }

    @Test func decodeByteStringUInt16Length() throws {
        let payload = [UInt8](repeating: 0xAB, count: 300)
        let bytes = SwiftCBOR.CBOR.encodeByteString(payload)
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeBytes()
        #expect(value.count == 300)
    }

    @Test func decodeByteStringUInt32Length() throws {
        let payload = [UInt8](repeating: 0xCD, count: 70_000)
        let bytes = SwiftCBOR.CBOR.encodeByteString(payload)
        var dec = CBORDecoder(data: Data(bytes))
        let value = try dec.decodeBytes()
        #expect(value.count == 70_000)
    }

    // MARK: - Arrays

    @Test func decodeDefiniteArray() throws {
        let bytes = SwiftCBOR.CBOR.encodeArray([UInt64(1), UInt64(2)])
        var dec = CBORDecoder(data: Data(bytes))
        let count = try dec.decodeArrayHeader()
        #expect(count == 2)
        #expect(try dec.decodeUInt() == 1)
        #expect(try dec.decodeUInt() == 2)
    }

    @Test func decodeIndefiniteArray() throws {
        var bytes: [UInt8] = [0x9F]
        bytes.append(contentsOf: SwiftCBOR.CBOR.encodeDouble(1.5))
        bytes.append(contentsOf: SwiftCBOR.CBOR.encodeDouble(2.5))
        bytes.append(0xFF)

        var dec = CBORDecoder(data: Data(bytes))
        let count = try dec.decodeArrayHeader()
        #expect(count == nil)
        var values: [Double] = []
        while try !dec.isBreak() {
            values.append(try dec.decodeFloat64())
        }
        try dec.decodeBreak()
        #expect(values == [1.5, 2.5])
    }

    // MARK: - Maps

    @Test func decodeMap() throws {
        let bytes = SwiftCBOR.CBOR.encode([UInt64(0): UInt64(42)])
        var dec = CBORDecoder(data: Data(bytes))
        let count = try dec.decodeMapHeader()
        #expect(count == 1)
        #expect(try dec.decodeUInt() == 0)
        #expect(try dec.decodeUInt() == 42)
    }

    // MARK: - Float64 array convenience

    @Test func decodeFloat64Array() throws {
        var enc = CBOREncoder()
        enc.encodeFloat64Array([10.0, 20.0, 30.0])
        var dec = CBORDecoder(data: enc.data)
        let values = try dec.decodeFloat64Array()
        #expect(values == [10.0, 20.0, 30.0])
    }

    @Test func decodeFloat64ArrayIndefinite() throws {
        var enc = CBOREncoder()
        enc.encodeIndefiniteArrayHeader()
        enc.encodeFloat64(1.0)
        enc.encodeFloat64(2.0)
        enc.encodeBreak()
        var dec = CBORDecoder(data: enc.data)
        let values = try dec.decodeFloat64Array()
        #expect(values == [1.0, 2.0])
    }

    // MARK: - Peek

    @Test func peekMajorType() throws {
        var enc = CBOREncoder()
        enc.encodeUInt(42)
        let dec = CBORDecoder(data: enc.data)
        #expect(try dec.peekMajorType() == 0)
    }

    @Test func peekByte() throws {
        var enc = CBOREncoder()
        enc.encodeFloat64(1.0)
        let dec = CBORDecoder(data: enc.data)
        #expect(try dec.peekByte() == 0xFB)
    }

    // MARK: - Round-trip

    @Test func roundTripChunkData() throws {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        for key: UInt64 in 0..<4 {
            enc.encodeUInt(key)
            enc.encodeArrayHeader(count: 2)
            enc.encodeFloat64Array([1000.0, 120.0])
            enc.encodeFloat64Array([1001.0, 130.0])
        }

        let swiftCBOR = try CBOR.decode([UInt8](enc.data))
        guard case .map(let map) = swiftCBOR else {
            Issue.record("Expected map from SwiftCBOR decode")
            return
        }
        #expect(map.count == 4)

        var dec = CBORDecoder(data: enc.data)
        let mapCount = try dec.decodeMapHeader()
        #expect(mapCount == 4)
        for expectedKey: UInt64 in 0..<4 {
            #expect(try dec.decodeUInt() == expectedKey)
            #expect(try dec.decodeArrayHeader() == 2)
            #expect(try dec.decodeFloat64Array() == [1000.0, 120.0])
            #expect(try dec.decodeFloat64Array() == [1001.0, 130.0])
        }
        #expect(dec.isAtEnd)
    }

    // MARK: - Error cases

    @Test func decodeEmptyDataThrows() {
        var dec = CBORDecoder(data: Data())
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }

    @Test func decodeTypeMismatchThrows() {
        var enc = CBOREncoder()
        enc.encodeString("hello")
        var dec = CBORDecoder(data: enc.data)
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }

    @Test func decodeFloat64TruncatedThrows() {
        let bytes: [UInt8] = [0xFB, 0x40, 0x09]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeFloat64() }
    }

    @Test func decodeFloat64WrongMarkerThrows() {
        let bytes: [UInt8] = [0x01]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeFloat64() }
    }

    @Test func decodeBreakWrongByteThrows() {
        let bytes: [UInt8] = [0x01]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeBreak() }
    }

    @Test func decodeBytesTooShortThrows() {
        let bytes: [UInt8] = [0x4A, 0x01, 0x02]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeBytes() }
    }

    @Test func decodeStringTooShortThrows() {
        let bytes: [UInt8] = [0x6A, 0x41, 0x42]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeString() }
    }

    @Test func decodeInvalidUTF8Throws() {
        let bytes: [UInt8] = [0x63, 0xFF, 0xFE, 0xFD]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeString() }
    }

    @Test func decodeUInt16HeaderTruncatedThrows() {
        let bytes: [UInt8] = [0x19, 0x01]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }

    @Test func decodeUInt32HeaderTruncatedThrows() {
        let bytes: [UInt8] = [0x1A, 0x00, 0x01]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }

    @Test func decodeUInt64HeaderTruncatedThrows() {
        let bytes: [UInt8] = [0x1B, 0x00, 0x00, 0x00, 0x01]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }

    @Test func decodeUInt8HeaderTruncatedThrows() {
        let bytes: [UInt8] = [0x18]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }

    @Test func decodeUnsupportedAdditionalThrows() {
        let bytes: [UInt8] = [0x1C]
        var dec = CBORDecoder(data: Data(bytes))
        #expect(throws: (any Error).self) { try dec.decodeUInt() }
    }
}
