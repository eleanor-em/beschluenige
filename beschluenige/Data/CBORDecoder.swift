import Foundation

// Minimal CBOR decoder covering the types used in workout data chunks.
// Supports: unsigned int, Float64, Data, String, definite/indefinite Array, definite Map, Break.
// See RFC 8949 for the CBOR specification.

struct CBORDecoder {
    private let data: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { offset >= data.count }

    // MARK: - Peek at next major type without consuming

    func peekMajorType() throws -> UInt8 {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        return data[offset] >> 5
    }

    func peekByte() throws -> UInt8 {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        return data[offset]
    }

    // MARK: - Unsigned integer (major type 0)

    mutating func decodeUInt() throws -> UInt64 {
        let (major, value) = try readHead()
        guard major == 0 else { throw CBORError.typeMismatch(expected: 0, got: major) }
        return value
    }

    // MARK: - Byte string (major type 2)

    mutating func decodeBytes() throws -> Data {
        let (major, length) = try readHead()
        guard major == 2 else { throw CBORError.typeMismatch(expected: 2, got: major) }
        let count = Int(length)
        guard offset + count <= data.count else { throw CBORError.unexpectedEnd }
        let result = data[offset..<(offset + count)]
        offset += count
        return Data(result)
    }

    // MARK: - Text string (major type 3)

    mutating func decodeString() throws -> String {
        let (major, length) = try readHead()
        guard major == 3 else { throw CBORError.typeMismatch(expected: 3, got: major) }
        let count = Int(length)
        guard offset + count <= data.count else { throw CBORError.unexpectedEnd }
        let bytes = data[offset..<(offset + count)]
        offset += count
        guard let str = String(data: Data(bytes), encoding: .utf8) else {
            throw CBORError.invalidUTF8
        }
        return str
    }

    // MARK: - Array header (major type 4)

    // Returns nil for indefinite-length arrays (caller should read until break).
    mutating func decodeArrayHeader() throws -> Int? {
        let byte = try peekByte()
        if byte == 0x9F {
            offset += 1
            return nil  // indefinite length
        }
        let (major, value) = try readHead()
        guard major == 4 else { throw CBORError.typeMismatch(expected: 4, got: major) }
        return Int(value)
    }

    // MARK: - Map header (major type 5)

    mutating func decodeMapHeader() throws -> Int {
        let (major, value) = try readHead()
        guard major == 5 else { throw CBORError.typeMismatch(expected: 5, got: major) }
        return Int(value)
    }

    // MARK: - Float64 (major type 7, additional 27)

    mutating func decodeFloat64() throws -> Double {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        let byte = data[offset]
        guard byte == 0xFB else { throw CBORError.typeMismatch(expected: 7, got: byte >> 5) }
        offset += 1
        guard offset + 8 <= data.count else { throw CBORError.unexpectedEnd }
        var big: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &big) { buf in
            data.copyBytes(to: buf, from: offset..<(offset + 8))
        }
        offset += 8
        return Double(bitPattern: UInt64(bigEndian: big))
    }

    // MARK: - Break (0xFF)

    mutating func decodeBreak() throws {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        guard data[offset] == 0xFF else { throw CBORError.expectedBreak }
        offset += 1
    }

    func isBreak() throws -> Bool {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        return data[offset] == 0xFF
    }

    // MARK: - Convenience: decode a definite array of Float64

    mutating func decodeFloat64Array() throws -> [Double] {
        guard let count = try decodeArrayHeader() else {
            // Indefinite-length array
            var result: [Double] = []
            while try !isBreak() {
                result.append(try decodeFloat64())
            }
            try decodeBreak()
            return result
        }
        var result: [Double] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try decodeFloat64())
        }
        return result
    }

    // MARK: - Internal

    private mutating func readHead() throws -> (majorType: UInt8, value: UInt64) {
        guard offset < data.count else { throw CBORError.unexpectedEnd }
        let initial = data[offset]
        offset += 1
        let major = initial >> 5
        let additional = initial & 0x1F

        if additional < 24 {
            return (major, UInt64(additional))
        } else if additional == 24 {
            guard offset < data.count else { throw CBORError.unexpectedEnd }
            let val = data[offset]
            offset += 1
            return (major, UInt64(val))
        } else if additional == 25 {
            guard offset + 2 <= data.count else { throw CBORError.unexpectedEnd }
            var big: UInt16 = 0
            _ = withUnsafeMutableBytes(of: &big) { buf in
                data.copyBytes(to: buf, from: offset..<(offset + 2))
            }
            offset += 2
            return (major, UInt64(UInt16(bigEndian: big)))
        } else if additional == 26 {
            guard offset + 4 <= data.count else { throw CBORError.unexpectedEnd }
            var big: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &big) { buf in
                data.copyBytes(to: buf, from: offset..<(offset + 4))
            }
            offset += 4
            return (major, UInt64(UInt32(bigEndian: big)))
        } else if additional == 27 {
            guard offset + 8 <= data.count else { throw CBORError.unexpectedEnd }
            var big: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &big) { buf in
                data.copyBytes(to: buf, from: offset..<(offset + 8))
            }
            offset += 8
            return (major, UInt64(bigEndian: big))
        } else {
            throw CBORError.unsupportedAdditional(additional)
        }
    }
}

enum CBORError: Error {
    case unexpectedEnd
    case typeMismatch(expected: UInt8, got: UInt8)
    case expectedBreak
    case invalidUTF8
    case unsupportedAdditional(UInt8)
}
