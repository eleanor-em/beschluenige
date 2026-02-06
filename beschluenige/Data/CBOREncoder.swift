import Foundation

// Minimal CBOR encoder covering only the types needed for workout data export.
// Supports: unsigned int, Float64, Data, String, definite/indefinite Array, definite Map, Break.
// See RFC 8949 for the CBOR specification.

struct CBOREncoder {
    private(set) var data = Data()

    // MARK: - Major type 0: Unsigned integer

    mutating func encodeUInt(_ value: UInt64) {
        writeHead(majorType: 0, value: value)
    }

    // MARK: - Major type 2: Byte string

    mutating func encodeBytes(_ bytes: Data) {
        writeHead(majorType: 2, value: UInt64(bytes.count))
        data.append(bytes)
    }

    // MARK: - Major type 3: Text string

    mutating func encodeString(_ string: String) {
        let utf8 = Data(string.utf8)
        writeHead(majorType: 3, value: UInt64(utf8.count))
        data.append(utf8)
    }

    // MARK: - Major type 4: Array (definite length)

    mutating func encodeArrayHeader(count: Int) {
        writeHead(majorType: 4, value: UInt64(count))
    }

    // MARK: - Major type 4: Array (indefinite length)

    mutating func encodeIndefiniteArrayHeader() {
        data.append(0x9F)  // major 4 + additional 31
    }

    // MARK: - Major type 5: Map (definite length)

    mutating func encodeMapHeader(count: Int) {
        writeHead(majorType: 5, value: UInt64(count))
    }

    // MARK: - Major type 7: Float64

    mutating func encodeFloat64(_ value: Double) {
        data.append(0xFB)  // major 7, additional 27
        var big = value.bitPattern.bigEndian
        data.append(Data(bytes: &big, count: 8))
    }

    // MARK: - Major type 7: Break (stops indefinite container)

    mutating func encodeBreak() {
        data.append(0xFF)
    }

    // MARK: - Convenience: encode an array of Float64 values as a definite CBOR array

    mutating func encodeFloat64Array(_ values: [Double]) {
        encodeArrayHeader(count: values.count)
        for v in values {
            encodeFloat64(v)
        }
    }

    // MARK: - Internal

    private mutating func writeHead(majorType: UInt8, value: UInt64) {
        let major = majorType << 5
        if value < 24 {
            data.append(major | UInt8(value))
        } else if value <= UInt8.max {
            data.append(major | 24)
            data.append(UInt8(value))
        } else if value <= UInt16.max {
            data.append(major | 25)
            var big = UInt16(value).bigEndian
            data.append(Data(bytes: &big, count: 2))
        } else if value <= UInt32.max {
            data.append(major | 26)
            var big = UInt32(value).bigEndian
            data.append(Data(bytes: &big, count: 4))
        } else {
            data.append(major | 27)
            var big = value.bigEndian
            data.append(Data(bytes: &big, count: 8))
        }
    }
}
