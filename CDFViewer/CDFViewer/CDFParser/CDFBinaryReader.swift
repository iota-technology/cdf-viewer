import Foundation

/// Low-level binary reader for CDF files
final class CDFBinaryReader {
    private let data: Data
    private(set) var position: Int = 0
    private(set) var isLittleEndian: Bool = true

    init(data: Data) {
        self.data = data
    }

    init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
    }

    var remaining: Int {
        return data.count - position
    }

    var isAtEnd: Bool {
        return position >= data.count
    }

    func setEndianness(_ littleEndian: Bool) {
        self.isLittleEndian = littleEndian
    }

    func seek(to offset: Int) {
        position = min(max(0, offset), data.count)
    }

    func seek(to offset: Int64) {
        seek(to: Int(offset))
    }

    func skip(_ count: Int) {
        position = min(position + count, data.count)
    }

    // MARK: - Read Raw Bytes

    func readBytes(_ count: Int) -> Data? {
        guard position + count <= data.count else { return nil }
        let result = data[position..<position + count]
        position += count
        return result
    }

    func peekBytes(_ count: Int) -> Data? {
        guard position + count <= data.count else { return nil }
        return data[position..<position + count]
    }

    // MARK: - Read Integers

    func readUInt8() -> UInt8? {
        guard position < data.count else { return nil }
        let value = data[position]
        position += 1
        return value
    }

    func readInt8() -> Int8? {
        guard let value = readUInt8() else { return nil }
        return Int8(bitPattern: value)
    }

    func readUInt16() -> UInt16? {
        guard let bytes = readBytes(2) else { return nil }
        var value: UInt16 = 0
        if isLittleEndian {
            value = UInt16(bytes[bytes.startIndex]) | (UInt16(bytes[bytes.startIndex + 1]) << 8)
        } else {
            value = (UInt16(bytes[bytes.startIndex]) << 8) | UInt16(bytes[bytes.startIndex + 1])
        }
        return value
    }

    func readInt16() -> Int16? {
        guard let value = readUInt16() else { return nil }
        return Int16(bitPattern: value)
    }

    func readUInt32() -> UInt32? {
        guard let bytes = readBytes(4) else { return nil }
        var value: UInt32 = 0
        if isLittleEndian {
            for i in 0..<4 {
                value |= UInt32(bytes[bytes.startIndex + i]) << (i * 8)
            }
        } else {
            for i in 0..<4 {
                value |= UInt32(bytes[bytes.startIndex + i]) << ((3 - i) * 8)
            }
        }
        return value
    }

    func readInt32() -> Int32? {
        guard let value = readUInt32() else { return nil }
        return Int32(bitPattern: value)
    }

    func readUInt64() -> UInt64? {
        guard let bytes = readBytes(8) else { return nil }
        var value: UInt64 = 0
        if isLittleEndian {
            for i in 0..<8 {
                value |= UInt64(bytes[bytes.startIndex + i]) << (i * 8)
            }
        } else {
            for i in 0..<8 {
                value |= UInt64(bytes[bytes.startIndex + i]) << ((7 - i) * 8)
            }
        }
        return value
    }

    func readInt64() -> Int64? {
        guard let value = readUInt64() else { return nil }
        return Int64(bitPattern: value)
    }

    // MARK: - Read Floating Point

    func readFloat32() -> Float? {
        guard let bits = readUInt32() else { return nil }
        return Float(bitPattern: bits)
    }

    func readFloat64() -> Double? {
        guard let bits = readUInt64() else { return nil }
        return Double(bitPattern: bits)
    }

    // MARK: - Read Strings

    func readString(length: Int) -> String? {
        guard let bytes = readBytes(length) else { return nil }
        // CDF strings are padded with nulls, trim them
        if let nullIndex = bytes.firstIndex(of: 0) {
            return String(data: bytes[bytes.startIndex..<nullIndex], encoding: .utf8)
        }
        return String(data: bytes, encoding: .utf8)
    }

    func readNullTerminatedString(maxLength: Int = 256) -> String? {
        var result = Data()
        var count = 0
        while position < data.count && count < maxLength {
            let byte = data[position]
            position += 1
            count += 1
            if byte == 0 { break }
            result.append(byte)
        }
        return String(data: result, encoding: .utf8)
    }

    // MARK: - Read CDF Value

    func readCDFValue(type: CDFDataType) -> CDFValue? {
        switch type {
        case .int1:
            guard let v = readInt8() else { return nil }
            return .int8(v)
        case .int2:
            guard let v = readInt16() else { return nil }
            return .int16(v)
        case .int4:
            guard let v = readInt32() else { return nil }
            return .int32(v)
        case .int8:
            guard let v = readInt64() else { return nil }
            return .int64(v)
        case .uint1:
            guard let v = readUInt8() else { return nil }
            return .uint8(v)
        case .uint2:
            guard let v = readUInt16() else { return nil }
            return .uint16(v)
        case .uint4:
            guard let v = readUInt32() else { return nil }
            return .uint32(v)
        case .real4, .float:
            guard let v = readFloat32() else { return nil }
            return .float32(v)
        case .real8, .double:
            guard let v = readFloat64() else { return nil }
            return .float64(v)
        case .epoch:
            guard let v = readFloat64() else { return nil }
            return .epoch(v)
        case .epoch16:
            guard let v1 = readFloat64(), let v2 = readFloat64() else { return nil }
            return .epoch16(v1, v2)
        case .timeTT2000:
            guard let v = readInt64() else { return nil }
            return .timeTT2000(v)
        case .char, .uchar:
            guard let v = readUInt8() else { return nil }
            return .string(String(Character(UnicodeScalar(v))))
        }
    }

    /// Read multiple values of the same type
    func readCDFValues(type: CDFDataType, count: Int) -> [CDFValue]? {
        var values: [CDFValue] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            guard let value = readCDFValue(type: type) else { return nil }
            values.append(value)
        }
        return values
    }

    /// Read raw doubles (common case for position/velocity data)
    func readDoubles(count: Int) -> [Double]? {
        var values: [Double] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            guard let value = readFloat64() else { return nil }
            values.append(value)
        }
        return values
    }

    /// Read raw Int64s (common case for timestamps)
    func readInt64s(count: Int) -> [Int64]? {
        var values: [Int64] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            guard let value = readInt64() else { return nil }
            values.append(value)
        }
        return values
    }

    // MARK: - Data Access

    func dataSlice(from offset: Int, length: Int) -> Data? {
        guard offset >= 0 && offset + length <= data.count else { return nil }
        return data[offset..<offset + length]
    }

    var totalSize: Int {
        return data.count
    }
}
