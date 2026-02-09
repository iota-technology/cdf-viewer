#!/usr/bin/env swift

// Deep dive into CDF header structure
import Foundation

let testFile = "/Users/jp/src/iota-technology/synthetic-data/1A/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001_MDR_GPS_1A.cdf"

let data = try! Data(contentsOf: URL(fileURLWithPath: testFile))

print("CDF Header Analysis")
print("===================\n")

// Helper to read big-endian values
func readUInt16BE(_ d: Data, at offset: Int) -> UInt16 {
    UInt16(d[offset]) << 8 | UInt16(d[offset+1])
}

func readUInt32BE(_ d: Data, at offset: Int) -> UInt32 {
    UInt32(d[offset]) << 24 | UInt32(d[offset+1]) << 16 | UInt32(d[offset+2]) << 8 | UInt32(d[offset+3])
}

func readInt64BE(_ d: Data, at offset: Int) -> Int64 {
    Int64(d[offset]) << 56 | Int64(d[offset+1]) << 48 | Int64(d[offset+2]) << 40 | Int64(d[offset+3]) << 32 |
    Int64(d[offset+4]) << 24 | Int64(d[offset+5]) << 16 | Int64(d[offset+6]) << 8 | Int64(d[offset+7])
}

func readInt32BE(_ d: Data, at offset: Int) -> Int32 {
    Int32(d[offset]) << 24 | Int32(d[offset+1]) << 16 | Int32(d[offset+2]) << 8 | Int32(d[offset+3])
}

// Magic (bytes 0-3)
let magic = readUInt16BE(data, at: 0)
let formatVersion = readUInt16BE(data, at: 2)
print("Bytes 0-3 (Magic Header):")
print("  Magic: 0x\(String(format: "%04X", magic)) \(magic == 0xCDF3 ? "✓ CDF3" : "?")")
print("  Format: 0x\(String(format: "%04X", formatVersion)) \(formatVersion == 0x0001 ? "✓ Single file 8-byte" : "?")")

// Compression marker (bytes 4-7)
let compMarker = readUInt32BE(data, at: 4)
print("\nBytes 4-7 (Compression Marker):")
print("  Value: 0x\(String(format: "%08X", compMarker)) \(compMarker == 0x0000FFFF ? "✓ Uncompressed" : "?")")

// CDR starts at byte 8
print("\n--- CDR Record (starting at byte 8) ---")

// CDR Record Size (8 bytes, big-endian)
let cdrSize = readInt64BE(data, at: 8)
print("CDR Size (bytes 8-15): \(cdrSize) bytes")

// CDR Record Type (4 bytes, big-endian)
let cdrType = readInt32BE(data, at: 16)
print("CDR Type (bytes 16-19): \(cdrType) \(cdrType == 1 ? "✓ CDR" : "?")")

// GDR Offset (8 bytes, big-endian)
let gdrOffset = readInt64BE(data, at: 20)
print("GDR Offset (bytes 20-27): \(gdrOffset)")

// CDR Version (4 bytes at offset 28)
let cdrVersion = readInt32BE(data, at: 28)
print("CDF Version (bytes 28-31): \(cdrVersion)")

// CDR Release (4 bytes at offset 32)
let cdrRelease = readInt32BE(data, at: 32)
print("CDF Release (bytes 32-35): \(cdrRelease)")

// CDR Encoding (4 bytes at offset 36)
let encoding = readInt32BE(data, at: 36)
print("Encoding (bytes 36-39): \(encoding) \(encoding == 9 ? "✓ IBMPC" : encoding == 8 ? "NETWORK" : "?")")

// CDR Flags (4 bytes at offset 40)
let flags = readInt32BE(data, at: 40)
print("Flags (bytes 40-43): \(flags)")

// Now let's look at GDR
print("\n--- GDR Record (at offset \(gdrOffset)) ---")

let gdrSize = readInt64BE(data, at: Int(gdrOffset))
print("GDR Size: \(gdrSize) bytes")

let gdrType = readInt32BE(data, at: Int(gdrOffset) + 8)
print("GDR Type: \(gdrType) \(gdrType == 2 ? "✓ GDR" : "?")")

let rVDRhead = readInt64BE(data, at: Int(gdrOffset) + 12)
print("rVDR head: \(rVDRhead)")

let zVDRhead = readInt64BE(data, at: Int(gdrOffset) + 20)
print("zVDR head: \(zVDRhead)")

let aDRhead = readInt64BE(data, at: Int(gdrOffset) + 28)
print("aDR head: \(aDRhead)")

let eof = readInt64BE(data, at: Int(gdrOffset) + 36)
print("EOF: \(eof)")

let nrVars = readInt32BE(data, at: Int(gdrOffset) + 44)
print("nrVars: \(nrVars)")

let numAttr = readInt32BE(data, at: Int(gdrOffset) + 48)
print("numAttr: \(numAttr)")

let rMaxRec = readInt32BE(data, at: Int(gdrOffset) + 52)
print("rMaxRec: \(rMaxRec)")

let rNumDims = readInt32BE(data, at: Int(gdrOffset) + 56)
print("rNumDims: \(rNumDims)")

let nzVars = readInt32BE(data, at: Int(gdrOffset) + 60)
print("nzVars: \(nzVars)")

print("\n=== Summary ===")
print("This CDF file has \(nzVars) zVariables and \(nrVars) rVariables")
print("First zVDR at offset: \(zVDRhead)")

// Look at first zVDR
if zVDRhead > 0 {
    print("\n--- First zVDR (at offset \(zVDRhead)) ---")
    let vdrSize = readInt64BE(data, at: Int(zVDRhead))
    let vdrType = readInt32BE(data, at: Int(zVDRhead) + 8)
    print("VDR Size: \(vdrSize)")
    print("VDR Type: \(vdrType) \(vdrType == 8 ? "✓ zVDR" : "?")")

    let vdrNext = readInt64BE(data, at: Int(zVDRhead) + 12)
    print("Next VDR: \(vdrNext)")

    let dataType = readInt32BE(data, at: Int(zVDRhead) + 20)
    print("Data type: \(dataType)")

    // Variable name at offset 64 from VDR start (after other fields)
    let nameOffset = Int(zVDRhead) + 84
    if let nameData = data[nameOffset..<min(nameOffset+64, data.count)].first(where: { _ in true }) {
        let nameBytes = Array(data[nameOffset..<min(nameOffset+256, data.count)])
        if let nullIdx = nameBytes.firstIndex(of: 0) {
            let name = String(bytes: nameBytes[0..<nullIdx], encoding: .utf8)
            print("Variable name: \(name ?? "?")")
        }
    }
}
