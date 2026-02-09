#!/usr/bin/env swift

// Test the actual CDFFile and CDFReader classes
// This compiles standalone and tests the same code the app uses

import Foundation
import Compression

// ============================================================================
// Copy of CDFDataTypes.swift
// ============================================================================

enum CDFDataType: Int32 {
    case int1 = 1, int2 = 2, int4 = 4, int8 = 8
    case uint1 = 11, uint2 = 12, uint4 = 14
    case real4 = 21, real8 = 22
    case epoch = 31, epoch16 = 32, timeTT2000 = 33
    case float = 44, double = 45
    case char = 51, uchar = 52

    var byteSize: Int {
        switch self {
        case .int1, .uint1, .char, .uchar: return 1
        case .int2, .uint2: return 2
        case .int4, .uint4, .real4, .float: return 4
        case .int8, .real8, .double, .epoch, .timeTT2000: return 8
        case .epoch16: return 16
        }
    }

    var displayName: String { String(describing: self) }
}

enum CDFEncoding: Int32 {
    case network = 1, sun = 2, vax = 3, decstation = 4, sgi = 5
    case ibmpc = 6, ibmrs = 7, host = 8, ppc = 9
    case hp = 11, neXT = 12, alphaosf1 = 13
    case alphavmsd = 14, alphavmsg = 15, alphavmsi = 16
    case arm_little = 17, arm_big = 18
    case ia64vms_i = 19, ia64vms_d = 20, ia64vms_g = 21

    var isLittleEndian: Bool {
        switch self {
        case .vax, .decstation, .ibmpc, .alphavmsd, .alphavmsg, .alphavmsi, .alphaosf1, .arm_little, .ia64vms_i, .ia64vms_d, .ia64vms_g:
            return true
        default:
            return false
        }
    }
}

// ============================================================================
// Copy of CDFBinaryReader.swift
// ============================================================================

final class CDFBinaryReader {
    private let data: Data
    private(set) var position: Int = 0
    private(set) var isLittleEndian: Bool = true

    init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
    }

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { position >= data.count }

    func setEndianness(_ littleEndian: Bool) {
        self.isLittleEndian = littleEndian
    }

    func seek(to offset: Int64) {
        position = Int(offset)
    }

    func readBytes(_ count: Int) -> Data? {
        guard position + count <= data.count else { return nil }
        let result = data[position..<position + count]
        position += count
        return result
    }

    func readInt32() -> Int32? {
        guard let bytes = readBytes(4) else { return nil }
        var value: Int32 = 0
        if isLittleEndian {
            for i in 0..<4 { value |= Int32(bytes[bytes.startIndex + i]) << (i * 8) }
        } else {
            for i in 0..<4 { value |= Int32(bytes[bytes.startIndex + i]) << ((3 - i) * 8) }
        }
        return value
    }

    func readInt64() -> Int64? {
        guard let bytes = readBytes(8) else { return nil }
        var value: Int64 = 0
        if isLittleEndian {
            for i in 0..<8 { value |= Int64(bytes[bytes.startIndex + i]) << (i * 8) }
        } else {
            for i in 0..<8 { value |= Int64(bytes[bytes.startIndex + i]) << ((7 - i) * 8) }
        }
        return value
    }

    func readString(length: Int) -> String? {
        guard let bytes = readBytes(length) else { return nil }
        if let nullIndex = bytes.firstIndex(of: 0) {
            return String(data: bytes[bytes.startIndex..<nullIndex], encoding: .utf8)
        }
        return String(data: bytes, encoding: .utf8)
    }
}

// ============================================================================
// Copy of CDFRecords.swift (simplified)
// ============================================================================

enum CDFRecordType: Int32 {
    case cdr = 1, gdr = 2, rVDR = 3, aDR = 4, agrEDR = 5
    case vxr = 6, vvr = 7, zVDR = 8, adrEDR = 9
    case ccr = 10, cpr = 11, spr = 12, cvvr = 13
    case uir = -1
}

struct CDFMagic {
    let majorVersion: Int
    let formatVersion: UInt16
    let isCompressed: Bool

    init?(reader: CDFBinaryReader) {
        guard let magicBytes = reader.readBytes(2) else { return nil }
        let magic = UInt16(magicBytes[0]) << 8 | UInt16(magicBytes[1])

        if magic == 0xCDF3 {
            self.majorVersion = 3
        } else if magic == 0xCDF2 {
            self.majorVersion = 2
        } else {
            print("Invalid magic: 0x\(String(format: "%04X", magic))")
            return nil
        }

        guard let formatBytes = reader.readBytes(2) else { return nil }
        self.formatVersion = UInt16(formatBytes[0]) << 8 | UInt16(formatBytes[1])

        guard let compBytes = reader.readBytes(4) else { return nil }
        let compMarker = UInt32(compBytes[0]) << 24 | UInt32(compBytes[1]) << 16 |
                        UInt32(compBytes[2]) << 8 | UInt32(compBytes[3])
        self.isCompressed = compMarker != 0x0000FFFF
    }
}

struct CDFDescriptorRecord {
    let recordSize: Int64
    let gdrOffset: Int64
    let version: Int32
    let release: Int32
    let encoding: CDFEncoding

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { print("Failed to read CDR size"); return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32() else { print("Failed to read CDR type"); return nil }
        guard typeRaw == 1 else { print("CDR type is \(typeRaw), expected 1"); return nil }

        guard let gdr = reader.readInt64() else { print("Failed to read GDR offset"); return nil }
        self.gdrOffset = gdr

        guard let ver = reader.readInt32() else { return nil }
        self.version = ver

        guard let rel = reader.readInt32() else { return nil }
        self.release = rel

        guard let enc = reader.readInt32() else { return nil }
        if let encoding = CDFEncoding(rawValue: enc) {
            self.encoding = encoding
        } else {
            print("Unknown encoding: \(enc)")
            return nil
        }
    }
}

struct GlobalDescriptorRecord {
    let nzVars: Int32
    let zVDRhead: Int64

    init?(reader: CDFBinaryReader) {
        guard let _ = reader.readInt64() else { return nil } // size
        guard let typeRaw = reader.readInt32() else { return nil }
        guard typeRaw == 2 else { print("GDR type is \(typeRaw), expected 2"); return nil }

        guard let _ = reader.readInt64() else { return nil } // rVDRhead
        guard let zVDR = reader.readInt64() else { return nil }
        self.zVDRhead = zVDR

        // Skip to nzVars (at offset 60 from start of GDR content)
        _ = reader.readBytes(36) // aDRhead(8) + eof(8) + nrVars(4) + numAttr(4) + rMaxRec(4) + rNumDims(4) = 32 bytes after zVDRhead
                                  // Wait, we already read 8+4+8+8 = 28 bytes, need 60-28 = 32 more
        guard let nzV = reader.readInt32() else { return nil }
        self.nzVars = nzV
    }
}

struct VariableDescriptorRecord {
    let name: String
    let dataType: CDFDataType
    let vdrNext: Int64
    let dimensions: [Int]

    init?(reader: CDFBinaryReader) {
        guard let _ = reader.readInt64() else { return nil } // size
        guard let typeRaw = reader.readInt32() else { return nil }
        guard typeRaw == 8 else { print("VDR type is \(typeRaw), expected 8"); return nil }

        guard let next = reader.readInt64() else { return nil }
        self.vdrNext = next

        guard let dtRaw = reader.readInt32() else { return nil }
        guard let dt = CDFDataType(rawValue: dtRaw) else {
            print("Unknown data type: \(dtRaw)")
            return nil
        }
        self.dataType = dt

        // Skip to name (we need to skip several fields)
        _ = reader.readBytes(52) // maxRec(4) + vxrHead(8) + vxrTail(8) + flags(4) + sRecords(4) + rfuB(4) + rfuC(4) + rfuF(4) + numElems(4) + num(4) + cpr(8) + blocking(4) = 60 bytes
        // Wait, we already read 8+4+8+4 = 24, need to read 60 more to get to name at offset 84 from VDR start
        // 84 - 24 = 60

        guard let varName = reader.readString(length: 256) else { return nil }
        self.name = varName

        guard let numDims = reader.readInt32() else { return nil }
        var dims: [Int] = []
        for _ in 0..<numDims {
            guard let d = reader.readInt32() else { return nil }
            dims.append(Int(d))
        }
        self.dimensions = dims
    }
}

// ============================================================================
// Test Code
// ============================================================================

let testFile = "/Users/jp/src/iota-technology/synthetic-data/1A/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001_MDR_GPS_1A.cdf"

print("Testing CDF Parsing with Real Classes")
print("=====================================\n")

do {
    let reader = try CDFBinaryReader(url: URL(fileURLWithPath: testFile))
    reader.setEndianness(false) // Big-endian for records

    print("Step 1: Parse Magic")
    guard let magic = CDFMagic(reader: reader) else {
        print("  ✗ Failed to parse magic")
        exit(1)
    }
    print("  ✓ Magic OK - CDF version \(magic.majorVersion)")

    print("\nStep 2: Parse CDR")
    guard let cdr = CDFDescriptorRecord(reader: reader) else {
        print("  ✗ Failed to parse CDR")
        exit(1)
    }
    print("  ✓ CDR OK - version \(cdr.version).\(cdr.release), encoding: \(cdr.encoding)")

    print("\nStep 3: Parse GDR")
    reader.seek(to: cdr.gdrOffset)
    guard let gdr = GlobalDescriptorRecord(reader: reader) else {
        print("  ✗ Failed to parse GDR")
        exit(1)
    }
    print("  ✓ GDR OK - \(gdr.nzVars) zVariables")

    print("\nStep 4: Parse Variables")
    var offset = gdr.zVDRhead
    var count = 0
    while offset > 0 && count < 20 {
        reader.seek(to: offset)
        guard let vdr = VariableDescriptorRecord(reader: reader) else {
            print("  ✗ Failed to parse VDR at offset \(offset)")
            break
        }
        print("  ✓ Variable \(count): '\(vdr.name)' - \(vdr.dataType.displayName) \(vdr.dimensions)")
        offset = vdr.vdrNext
        count += 1
    }

    print("\n=== SUCCESS! Parsed \(count) variables ===")

} catch {
    print("Error: \(error)")
}
