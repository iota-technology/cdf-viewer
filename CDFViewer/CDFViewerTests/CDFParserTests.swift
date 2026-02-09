import XCTest
@testable import CDFViewer

final class CDFParserTests: XCTestCase {

    // Test file paths
    let testFile1A = "/Users/jp/src/iota-technology/synthetic-data/1A/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001/IO_TEST_001_GPS_1A_20250101T000000_20250101T235959_0001_MDR_GPS_1A.cdf"
    let testFile1B = "/Users/jp/src/iota-technology/synthetic-data/1B/IO_TEST_001_GPS_1B_20250101T000000_20250101T235959_0001/IO_TEST_001_GPS_1B_20250101T000000_20250101T235959_0001_MDR_GPS_1B.cdf"

    // MARK: - Binary Reader Tests

    func testBinaryReaderCanOpenFile() throws {
        let url = URL(fileURLWithPath: testFile1A)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile1A), "Test file should exist")

        let reader = try CDFBinaryReader(url: url)
        XCTAssertNotNil(reader, "Should be able to create binary reader")
    }

    func testBinaryReaderReadsMagicBytes() throws {
        let url = URL(fileURLWithPath: testFile1A)
        let reader = try CDFBinaryReader(url: url)

        // Read first 4 bytes
        guard let magicBytes = reader.readBytes(4) else {
            XCTFail("Should be able to read 4 bytes")
            return
        }

        let magicStr = String(data: magicBytes, encoding: .ascii)
        print("Magic bytes: \(magicBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
        print("Magic string: \(magicStr ?? "nil")")

        XCTAssertTrue(magicStr == "cdf3" || magicStr == "CDF3", "Magic should be cdf3 or CDF3, got: \(magicStr ?? "nil")")
    }

    func testBinaryReaderReadsHeader() throws {
        let url = URL(fileURLWithPath: testFile1A)
        let reader = try CDFBinaryReader(url: url)

        // Read first 16 bytes to understand header structure
        guard let headerBytes = reader.readBytes(16) else {
            XCTFail("Should be able to read 16 bytes")
            return
        }

        print("Header bytes (hex): \(headerBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")

        // Parse manually
        let magic = String(data: headerBytes[0..<4], encoding: .ascii)
        print("Magic: \(magic ?? "nil")")

        // Bytes 4-5: version (little-endian for IBMPC)
        let version = UInt16(headerBytes[4]) | (UInt16(headerBytes[5]) << 8)
        print("Version bytes: \(headerBytes[4]), \(headerBytes[5]) -> \(version)")

        // Bytes 6-7: release
        let release = UInt16(headerBytes[6]) | (UInt16(headerBytes[7]) << 8)
        print("Release bytes: \(headerBytes[6]), \(headerBytes[7]) -> \(release)")

        // Bytes 8-11: compression marker
        let compressionMarker = UInt32(headerBytes[8]) | (UInt32(headerBytes[9]) << 8) | (UInt32(headerBytes[10]) << 16) | (UInt32(headerBytes[11]) << 24)
        print("Compression marker: 0x\(String(format: "%08x", compressionMarker))")
    }

    // MARK: - Magic Number Tests

    func testCDFMagicParsing() throws {
        let url = URL(fileURLWithPath: testFile1A)
        let reader = try CDFBinaryReader(url: url)

        let magic = CDFMagic(reader: reader)

        XCTAssertNotNil(magic, "Should be able to parse magic number")

        if let magic = magic {
            print("Parsed magic:")
            print("  Major version: \(magic.majorVersion)")
            print("  Version: \(magic.version)")
            print("  Release: \(magic.release)")
            print("  Is compressed: \(magic.isCompressed)")

            XCTAssertEqual(magic.majorVersion, 3, "Major version should be 3")
        }
    }

    // MARK: - CDR Tests

    func testCDRParsing() throws {
        let url = URL(fileURLWithPath: testFile1A)
        let reader = try CDFBinaryReader(url: url)

        // First read magic
        guard let magic = CDFMagic(reader: reader) else {
            XCTFail("Should be able to parse magic")
            return
        }

        print("After magic, reader position should be at byte 12")

        // Now try to read CDR
        let cdr = CDFDescriptorRecord(reader: reader)

        XCTAssertNotNil(cdr, "Should be able to parse CDR")

        if let cdr = cdr {
            print("Parsed CDR:")
            print("  Record size: \(cdr.recordSize)")
            print("  Record type: \(cdr.recordType)")
            print("  GDR offset: \(cdr.gdrOffset)")
            print("  Version: \(cdr.version)")
            print("  Release: \(cdr.release)")
            print("  Encoding: \(cdr.encoding)")
            print("  Flags: \(cdr.flags)")
            print("  Copyright: \(cdr.copyright.prefix(50))...")

            XCTAssertEqual(cdr.recordType, .cdr, "Record type should be CDR")
            XCTAssertGreaterThan(cdr.gdrOffset, 0, "GDR offset should be positive")
        }
    }

    // MARK: - Full Parser Tests

    func testFullParserOnTestFile() throws {
        let url = URL(fileURLWithPath: testFile1A)

        do {
            let cdfReader = try CDFReader(url: url)
            try cdfReader.parse()

            print("Successfully parsed CDF file!")
            print("File info: \(cdfReader.fileInfo)")
            print("Variables: \(cdfReader.variables.count)")
            for variable in cdfReader.variables {
                print("  - \(variable.name): \(variable.dataType) \(variable.dimensions)")
            }
            print("Attributes: \(cdfReader.attributes.count)")
            print("Warnings: \(cdfReader.warnings.count)")
            for warning in cdfReader.warnings {
                print("  - \(warning.message)")
            }

            XCTAssertEqual(cdfReader.variables.count, 16, "Should have 16 variables")
        } catch {
            print("Parse failed with error: \(error)")
            XCTFail("Parsing should succeed: \(error)")
        }
    }

    // MARK: - Debug: Raw Header Dump

    func testRawHeaderDump() throws {
        let url = URL(fileURLWithPath: testFile1A)
        let data = try Data(contentsOf: url)

        print("File size: \(data.count) bytes")
        print("\nFirst 128 bytes (hex dump):")

        for row in 0..<8 {
            let start = row * 16
            let end = min(start + 16, data.count)
            let rowBytes = data[start..<end]

            let hex = rowBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = String(rowBytes.map { (0x20...0x7e).contains($0) ? Character(UnicodeScalar($0)) : "." })

            print(String(format: "%04x: %-48s  %s", start, hex, ascii))
        }
    }

    // MARK: - Endianness Test

    func testEndiannessHandling() throws {
        let url = URL(fileURLWithPath: testFile1A)
        let reader = try CDFBinaryReader(url: url)

        // Skip magic (4 bytes)
        _ = reader.readBytes(4)

        // Read version as big-endian first
        reader.setEndianness(false) // big-endian
        let versionBE = reader.readUInt16()

        // Reset and read as little-endian
        reader.seek(to: 4)
        reader.setEndianness(true) // little-endian
        let versionLE = reader.readUInt16()

        print("Version as big-endian: \(versionBE ?? 0)")
        print("Version as little-endian: \(versionLE ?? 0)")

        // The file is IBMPC encoded (little-endian), so LE should give sensible values
    }
}
