#!/usr/bin/env swift

// Standalone test script for CDF parser debugging
// Run with: swift test_parser.swift

import Foundation

let testFile = "/Users/jp/src/iota-technology/synthetic-data/1A/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001_MDR_GPS_1A.cdf"

print("Testing CDF Parser")
print("==================")
print("File: \(testFile)")
print("")

// Check file exists
guard FileManager.default.fileExists(atPath: testFile) else {
    print("ERROR: Test file does not exist!")
    exit(1)
}

// Read file data
let url = URL(fileURLWithPath: testFile)
guard let data = try? Data(contentsOf: url) else {
    print("ERROR: Cannot read file data!")
    exit(1)
}

print("File size: \(data.count) bytes")
print("")

// Dump first 128 bytes as hex
print("First 128 bytes (hex dump):")
print("-----------------------------")
for row in 0..<8 {
    let start = row * 16
    let end = min(start + 16, data.count)
    let rowBytes = Array(data[start..<end])

    let hex = rowBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    let ascii = String(rowBytes.map { (0x20...0x7e).contains($0) ? Character(UnicodeScalar($0)) : "." })

    print(String(format: "%04x: %-48s  %s", start, hex, ascii))
}
print("")

// Parse magic bytes
print("Parsing Magic Header:")
print("--------------------")
let magicBytes = Array(data[0..<4])
print("Magic bytes: \(magicBytes.map { String(format: "0x%02x", $0) }.joined(separator: " "))")

// CDF3 magic is 0xCDF3 (hex bytes, not ASCII!)
let magic16 = UInt16(data[0]) << 8 | UInt16(data[1])
print("Magic (bytes 0-1) as UInt16 big-endian: 0x\(String(format: "%04x", magic16))")

if magic16 == 0xCDF3 {
    print("✓ Valid CDF3 magic number (0xCDF3)")
} else if magic16 == 0xCDF2 {
    print("✓ Valid CDF2.6 magic number (0xCDF2)")
} else {
    print("✗ INVALID magic number! Expected 0xCDF3 or 0xCDF2")
}

// Format version (bytes 2-3)
let formatVersion = UInt16(data[2]) << 8 | UInt16(data[3])
print("Format version (bytes 2-3): 0x\(String(format: "%04x", formatVersion))")
if formatVersion == 0x0001 {
    print("  = Single file with 8-byte offsets")
}

// Parse version/release (bytes 4-7)
// CDF uses big-endian for the magic header section
let versionBE = UInt16(data[4]) << 8 | UInt16(data[5])
let releaseBE = UInt16(data[6]) << 8 | UInt16(data[7])
let versionLE = UInt16(data[4]) | UInt16(data[5]) << 8
let releaseLE = UInt16(data[6]) | UInt16(data[7]) << 8

print("")
print("Version/Release bytes: \(data[4]) \(data[5]) \(data[6]) \(data[7])")
print("  As big-endian:    version=\(versionBE), release=\(releaseBE)")
print("  As little-endian: version=\(versionLE), release=\(releaseLE)")

// Compression marker (bytes 8-11)
let compMarkerBE = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
let compMarkerLE = UInt32(data[8]) | UInt32(data[9]) << 8 | UInt32(data[10]) << 16 | UInt32(data[11]) << 24

print("")
print("Compression marker bytes: \(data[8]) \(data[9]) \(data[10]) \(data[11])")
print("  As big-endian:    0x\(String(format: "%08x", compMarkerBE))")
print("  As little-endian: 0x\(String(format: "%08x", compMarkerLE))")

if compMarkerBE == 0x0000FFFF || compMarkerLE == 0x0000FFFF {
    print("✓ Uncompressed file (marker = 0x0000FFFF)")
} else if compMarkerBE == 0xCCCC0001 || compMarkerLE == 0xCCCC0001 {
    print("! Compressed file (marker = 0xCCCC0001)")
} else {
    print("? Unknown compression marker")
}

// CDR Record starts at byte 12
print("")
print("CDR Record (starting at byte 12):")
print("---------------------------------")

// CDR record size (8 bytes, big-endian in CDF format)
let cdrSizeBE = UInt64(data[12]) << 56 | UInt64(data[13]) << 48 | UInt64(data[14]) << 40 | UInt64(data[15]) << 32 |
                UInt64(data[16]) << 24 | UInt64(data[17]) << 16 | UInt64(data[18]) << 8 | UInt64(data[19])
let cdrSizeLE = UInt64(data[12]) | UInt64(data[13]) << 8 | UInt64(data[14]) << 16 | UInt64(data[15]) << 24 |
                UInt64(data[16]) << 32 | UInt64(data[17]) << 40 | UInt64(data[18]) << 48 | UInt64(data[19]) << 56

print("CDR size bytes (12-19): \(Array(data[12..<20]).map { String(format: "%02x", $0) }.joined(separator: " "))")
print("  As big-endian:    \(cdrSizeBE)")
print("  As little-endian: \(cdrSizeLE)")

// CDR record type (4 bytes at offset 20)
let cdrTypeBE = UInt32(data[20]) << 24 | UInt32(data[21]) << 16 | UInt32(data[22]) << 8 | UInt32(data[23])
let cdrTypeLE = UInt32(data[20]) | UInt32(data[21]) << 8 | UInt32(data[22]) << 16 | UInt32(data[23]) << 24

print("CDR type bytes (20-23): \(Array(data[20..<24]).map { String(format: "%02x", $0) }.joined(separator: " "))")
print("  As big-endian:    \(cdrTypeBE) (should be 1 for CDR)")
print("  As little-endian: \(cdrTypeLE) (should be 1 for CDR)")

// GDR offset (8 bytes at offset 24)
let gdrOffsetBE = UInt64(data[24]) << 56 | UInt64(data[25]) << 48 | UInt64(data[26]) << 40 | UInt64(data[27]) << 32 |
                  UInt64(data[28]) << 24 | UInt64(data[29]) << 16 | UInt64(data[30]) << 8 | UInt64(data[31])
let gdrOffsetLE = UInt64(data[24]) | UInt64(data[25]) << 8 | UInt64(data[26]) << 16 | UInt64(data[27]) << 24 |
                  UInt64(data[28]) << 32 | UInt64(data[29]) << 40 | UInt64(data[30]) << 48 | UInt64(data[31]) << 56

print("GDR offset bytes (24-31): \(Array(data[24..<32]).map { String(format: "%02x", $0) }.joined(separator: " "))")
print("  As big-endian:    \(gdrOffsetBE)")
print("  As little-endian: \(gdrOffsetLE)")

// Encoding (4 bytes at offset 44 in CDR)
// CDR: size(8) + type(4) + gdrOffset(8) + version(4) + release(4) + encoding(4)
// So encoding is at: 12 + 8 + 4 + 8 + 4 + 4 = 40
let encOffset = 12 + 20 // 12 (start of CDR) + 20 (offset to encoding within CDR)
let encodingBE = UInt32(data[encOffset]) << 24 | UInt32(data[encOffset+1]) << 16 | UInt32(data[encOffset+2]) << 8 | UInt32(data[encOffset+3])
let encodingLE = UInt32(data[encOffset]) | UInt32(data[encOffset+1]) << 8 | UInt32(data[encOffset+2]) << 16 | UInt32(data[encOffset+3]) << 24

print("")
print("Encoding bytes (at offset \(encOffset)): \(Array(data[encOffset..<encOffset+4]).map { String(format: "%02x", $0) }.joined(separator: " "))")
print("  As big-endian:    \(encodingBE)")
print("  As little-endian: \(encodingLE)")
print("  (9 = IBMPC/little-endian, 8 = NETWORK/big-endian)")

print("")
print("Analysis Complete")
print("=================")

// Determine likely endianness
if cdrTypeLE == 1 {
    print("→ File appears to use LITTLE-ENDIAN byte order")
    print("  CDR record type = \(cdrTypeLE) (correct)")
    print("  CDR size = \(cdrSizeLE)")
    print("  GDR offset = \(gdrOffsetLE)")
} else if cdrTypeBE == 1 {
    print("→ File appears to use BIG-ENDIAN byte order")
    print("  CDR record type = \(cdrTypeBE) (correct)")
    print("  CDR size = \(cdrSizeBE)")
    print("  GDR offset = \(gdrOffsetBE)")
} else {
    print("→ ERROR: Neither endianness gives CDR type = 1")
    print("  This may indicate the file structure is different than expected")
}
