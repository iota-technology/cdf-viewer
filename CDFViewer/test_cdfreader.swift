#!/usr/bin/env swift

// Test script that mimics the CDFReader parsing to find the exact failure point
import Foundation

let testFile = "/Users/jp/src/iota-technology/synthetic-data/1A/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001_MDR_GPS_1A.cdf"

print("Testing CDFReader Logic")
print("=======================\n")

let data = try! Data(contentsOf: URL(fileURLWithPath: testFile))
var position = 0

// Helper functions
func readBytes(_ count: Int) -> Data {
    let result = data[position..<position+count]
    position += count
    return result
}

func readInt64BE() -> Int64 {
    let bytes = readBytes(8)
    var value: Int64 = 0
    for i in 0..<8 {
        value |= Int64(bytes[bytes.startIndex + i]) << ((7 - i) * 8)
    }
    return value
}

func readInt32BE() -> Int32 {
    let bytes = readBytes(4)
    var value: Int32 = 0
    for i in 0..<4 {
        value |= Int32(bytes[bytes.startIndex + i]) << ((3 - i) * 8)
    }
    return value
}

func readString(_ length: Int) -> String {
    let bytes = readBytes(length)
    if let nullIdx = bytes.firstIndex(of: 0) {
        return String(data: bytes[bytes.startIndex..<nullIdx], encoding: .utf8) ?? ""
    }
    return String(data: bytes, encoding: .utf8) ?? ""
}

// Step 1: Parse Magic (8 bytes)
print("Step 1: Parsing Magic Header")
print("----------------------------")
let magicBytes = readBytes(2)
let magic = UInt16(magicBytes[magicBytes.startIndex]) << 8 | UInt16(magicBytes[magicBytes.startIndex + 1])
print("  Magic: 0x\(String(format: "%04X", magic)) \(magic == 0xCDF3 ? "✓" : "✗")")

let formatBytes = readBytes(2)
let formatVersion = UInt16(formatBytes[formatBytes.startIndex]) << 8 | UInt16(formatBytes[formatBytes.startIndex + 1])
print("  Format: 0x\(String(format: "%04X", formatVersion))")

let compBytes = readBytes(4)
let compMarker = UInt32(compBytes[compBytes.startIndex]) << 24 | UInt32(compBytes[compBytes.startIndex + 1]) << 16 |
                 UInt32(compBytes[compBytes.startIndex + 2]) << 8 | UInt32(compBytes[compBytes.startIndex + 3])
print("  Compression: 0x\(String(format: "%08X", compMarker)) \(compMarker == 0x0000FFFF ? "✓ uncompressed" : "?")")
print("  Position after magic: \(position)")

// Step 2: Parse CDR
print("\nStep 2: Parsing CDR Record")
print("--------------------------")
let cdrStart = position
let cdrSize = readInt64BE()
print("  CDR Size: \(cdrSize)")

let cdrType = readInt32BE()
print("  CDR Type: \(cdrType) \(cdrType == 1 ? "✓" : "✗ EXPECTED 1")")

if cdrType != 1 {
    print("\n  ⚠️  CDR Type mismatch! Let's check what's at this position...")
    position = cdrStart
    let rawBytes = Array(readBytes(20))
    print("  Raw bytes at CDR start: \(rawBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
    exit(1)
}

let gdrOffset = readInt64BE()
print("  GDR Offset: \(gdrOffset)")

let cdrVersion = readInt32BE()
print("  CDF Version: \(cdrVersion)")

let cdrRelease = readInt32BE()
print("  CDF Release: \(cdrRelease)")

let encoding = readInt32BE()
print("  Encoding: \(encoding) \(encoding == 6 ? "✓ IBMPC" : "?")")

let flags = readInt32BE()
print("  Flags: \(flags)")

// Skip rfuA, rfuB, increment, rfuD, rfuE (5 x 4 bytes = 20 bytes)
_ = readBytes(20)

// Copyright string (rest of CDR)
let copyrightLength = Int(cdrSize) - (position - cdrStart)
let copyright = readString(copyrightLength)
print("  Copyright: \(copyright.prefix(50))...")

print("  Position after CDR: \(position)")

// Step 3: Parse GDR
print("\nStep 3: Parsing GDR Record")
print("--------------------------")
position = Int(gdrOffset)
print("  Seeking to GDR at offset \(gdrOffset)")

let gdrSize = readInt64BE()
print("  GDR Size: \(gdrSize)")

let gdrType = readInt32BE()
print("  GDR Type: \(gdrType) \(gdrType == 2 ? "✓" : "✗ EXPECTED 2")")

if gdrType != 2 {
    print("\n  ⚠️  GDR Type mismatch!")
    exit(1)
}

let rVDRhead = readInt64BE()
print("  rVDR head: \(rVDRhead)")

let zVDRhead = readInt64BE()
print("  zVDR head: \(zVDRhead)")

let aDRhead = readInt64BE()
print("  aDR head: \(aDRhead)")

let eof = readInt64BE()
print("  EOF: \(eof)")

let nrVars = readInt32BE()
print("  nrVars: \(nrVars)")

let numAttr = readInt32BE()
print("  numAttr: \(numAttr)")

let rMaxRec = readInt32BE()
print("  rMaxRec: \(rMaxRec)")

let rNumDims = readInt32BE()
print("  rNumDims: \(rNumDims)")

let nzVars = readInt32BE()
print("  nzVars: \(nzVars)")

// Step 4: Parse first zVDR
if zVDRhead > 0 {
    print("\nStep 4: Parsing First zVDR")
    print("--------------------------")
    position = Int(zVDRhead)
    print("  Seeking to zVDR at offset \(zVDRhead)")

    let vdrSize = readInt64BE()
    print("  VDR Size: \(vdrSize)")

    let vdrType = readInt32BE()
    print("  VDR Type: \(vdrType) \(vdrType == 8 ? "✓ zVDR" : "✗ EXPECTED 8")")

    if vdrType != 8 {
        print("\n  ⚠️  VDR Type mismatch!")
        exit(1)
    }

    let vdrNext = readInt64BE()
    print("  Next VDR: \(vdrNext)")

    let dataType = readInt32BE()
    print("  Data Type: \(dataType)")

    let maxRec = readInt32BE()
    print("  Max Record: \(maxRec)")

    let vxrHead = readInt64BE()
    print("  VXR Head: \(vxrHead)")

    let vxrTail = readInt64BE()
    print("  VXR Tail: \(vxrTail)")

    let vdrFlags = readInt32BE()
    print("  Flags: \(vdrFlags)")

    let sRecords = readInt32BE()
    print("  sRecords: \(sRecords)")

    // Skip rfuB, rfuC, rfuF (3 x 4 bytes)
    _ = readBytes(12)

    let numElems = readInt32BE()
    print("  Num Elements: \(numElems)")

    let varNum = readInt32BE()
    print("  Variable Number: \(varNum)")

    let cprOffset = readInt64BE()
    print("  CPR/SPR Offset: \(cprOffset)")

    let blockingFactor = readInt32BE()
    print("  Blocking Factor: \(blockingFactor)")

    let varName = readString(256)
    print("  Variable Name: '\(varName)'")

    // For zVDR, read dimensions
    let zNumDims = readInt32BE()
    print("  zNumDims: \(zNumDims)")

    if zNumDims > 0 {
        print("  Dimension sizes: ", terminator: "")
        for i in 0..<zNumDims {
            let dimSize = readInt32BE()
            print("\(dimSize) ", terminator: "")
        }
        print("")

        print("  Dimension varys: ", terminator: "")
        for i in 0..<zNumDims {
            let dimVary = readInt32BE()
            print("\(dimVary == -1 ? "T" : "F") ", terminator: "")
        }
        print("")
    }
}

print("\n=== All parsing steps completed successfully! ===")
print("\nSummary:")
print("  CDF Version: \(cdrVersion).\(cdrRelease)")
print("  zVariables: \(nzVars)")
print("  rVariables: \(nrVars)")
print("  Attributes: \(numAttr)")
