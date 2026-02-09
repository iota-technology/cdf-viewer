import Foundation

// MARK: - CDF Record Types

enum CDFRecordType: Int32 {
    case cdr = 1   // CDF Descriptor Record
    case gdr = 2   // Global Descriptor Record
    case rVDR = 3  // rVariable Descriptor Record
    case aDR = 4   // Attribute Descriptor Record
    case agrEDR = 5 // Attribute gEntry Descriptor Record
    case vxr = 6   // Variable Index Record
    case vvr = 7   // Variable Values Record
    case zVDR = 8  // zVariable Descriptor Record
    case adrEDR = 9 // Attribute rEntry Descriptor Record
    case ccr = 10  // Compressed CDF Record
    case cpr = 11  // Compression Parameters Record
    case spr = 12  // Sparseness Parameters Record
    case cvvr = 13 // Compressed Variable Values Record
    case uir = -1  // Unused Internal Record
}

// MARK: - Magic Number
//
// CDF file format magic:
// Bytes 0-1: 0xCDF3 (hex, big-endian) - identifies CDF version 3
// Bytes 2-3: 0x0001 = single file with 8-byte offsets, 0x0002 = multi-file
// Bytes 4-7: Compression marker (0x0000FFFF = uncompressed, 0xCCCC0001 = compressed)
//
// Note: The magic is NOT ASCII "cdf3" - it's the hex bytes 0xCD, 0xF3

struct CDFMagic {
    static let cdf3Magic: UInt16 = 0xCDF3      // CDF version 3 magic (big-endian)
    static let cdf26Magic: UInt16 = 0xCDF2     // CDF version 2.6 magic
    static let singleFile: UInt16 = 0x0001     // Single file, 8-byte offsets
    static let uncompressed: UInt32 = 0x0000FFFF
    static let compressed: UInt32 = 0xCCCC0001

    let majorVersion: Int    // 3 for CDF3, 2 for CDF2.6
    let formatVersion: UInt16 // 0x0001 = single file 8-byte offsets
    let isCompressed: Bool

    init?(reader: CDFBinaryReader) {
        // Read first 2 bytes for magic identifier (always big-endian)
        // Note: Data slices maintain original indices, so we must use startIndex
        guard let magicBytes = reader.readBytes(2) else { return nil }
        let magic = UInt16(magicBytes[magicBytes.startIndex]) << 8 | UInt16(magicBytes[magicBytes.startIndex + 1])

        // Check for CDF3 or CDF2.6 magic
        if magic == CDFMagic.cdf3Magic {
            self.majorVersion = 3
        } else if magic == CDFMagic.cdf26Magic {
            self.majorVersion = 2
        } else {
            // Not a valid CDF file
            return nil
        }

        // Read format version (bytes 2-3, big-endian)
        guard let formatBytes = reader.readBytes(2) else { return nil }
        self.formatVersion = UInt16(formatBytes[formatBytes.startIndex]) << 8 | UInt16(formatBytes[formatBytes.startIndex + 1])

        // Read compression marker (bytes 4-7, big-endian)
        guard let compBytes = reader.readBytes(4) else { return nil }
        let s = compBytes.startIndex
        let compressionMarker = UInt32(compBytes[s]) << 24 | UInt32(compBytes[s + 1]) << 16 |
                                UInt32(compBytes[s + 2]) << 8 | UInt32(compBytes[s + 3])

        self.isCompressed = compressionMarker != CDFMagic.uncompressed
    }
}

// MARK: - CDF Descriptor Record (CDR)

struct CDFDescriptorRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let gdrOffset: Int64
    let version: Int32
    let release: Int32
    let encoding: CDFEncoding
    let flags: Int32
    let rfuA: Int32
    let rfuB: Int32
    let increment: Int32
    let rfuD: Int32
    let rfuE: Int32
    let copyright: String

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let gdr = reader.readInt64() else { return nil }
        self.gdrOffset = gdr

        guard let ver = reader.readInt32() else { return nil }
        self.version = ver

        guard let rel = reader.readInt32() else { return nil }
        self.release = rel

        guard let enc = reader.readInt32(),
              let encoding = CDFEncoding(rawValue: enc) else {
            // Default to IBMPC if unknown
            self.encoding = .ibmpc
            reader.skip(4) // Skip the encoding we couldn't parse
            guard let flags = reader.readInt32() else { return nil }
            self.flags = flags
            guard let rfuA = reader.readInt32() else { return nil }
            self.rfuA = rfuA
            guard let rfuB = reader.readInt32() else { return nil }
            self.rfuB = rfuB
            guard let inc = reader.readInt32() else { return nil }
            self.increment = inc
            guard let rfuD = reader.readInt32() else { return nil }
            self.rfuD = rfuD
            guard let rfuE = reader.readInt32() else { return nil }
            self.rfuE = rfuE
            // Copyright is rest of record
            let copyrightLength = Int(recordSize) - 56
            self.copyright = reader.readString(length: copyrightLength) ?? ""
            return
        }
        self.encoding = encoding

        // NOTE: Do NOT change endianness here - record structures are always big-endian
        // The encoding is only used for reading actual data values in VVR/CVVR records

        guard let flags = reader.readInt32() else { return nil }
        self.flags = flags

        guard let rfuA = reader.readInt32() else { return nil }
        self.rfuA = rfuA

        guard let rfuB = reader.readInt32() else { return nil }
        self.rfuB = rfuB

        guard let inc = reader.readInt32() else { return nil }
        self.increment = inc

        guard let rfuD = reader.readInt32() else { return nil }
        self.rfuD = rfuD

        guard let rfuE = reader.readInt32() else { return nil }
        self.rfuE = rfuE

        // Copyright is rest of record
        let copyrightLength = Int(recordSize) - 56
        self.copyright = reader.readString(length: copyrightLength) ?? ""
    }
}

// MARK: - Global Descriptor Record (GDR)

struct GlobalDescriptorRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let rVDRhead: Int64      // Offset to first rVariable VDR
    let zVDRhead: Int64      // Offset to first zVariable VDR
    let aDRhead: Int64       // Offset to first Attribute DR
    let eof: Int64           // End of file offset
    let nrVars: Int32        // Number of rVariables
    let numAttr: Int32       // Number of attributes
    let rMaxRec: Int32       // Maximum record number for rVariables
    let rNumDims: Int32      // Number of dimensions for rVariables
    let nzVars: Int32        // Number of zVariables
    let uirHead: Int64       // Offset to first unused internal record
    let rfuC: Int32
    let leapSecondLastUpdated: Int32
    let rfuE: Int32
    let rDimSizes: [Int32]   // Dimension sizes for rVariables

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let rVDR = reader.readInt64() else { return nil }
        self.rVDRhead = rVDR

        guard let zVDR = reader.readInt64() else { return nil }
        self.zVDRhead = zVDR

        guard let aDR = reader.readInt64() else { return nil }
        self.aDRhead = aDR

        guard let eofOffset = reader.readInt64() else { return nil }
        self.eof = eofOffset

        guard let nrV = reader.readInt32() else { return nil }
        self.nrVars = nrV

        guard let nAttr = reader.readInt32() else { return nil }
        self.numAttr = nAttr

        guard let maxRec = reader.readInt32() else { return nil }
        self.rMaxRec = maxRec

        guard let numDims = reader.readInt32() else { return nil }
        self.rNumDims = numDims

        guard let nzV = reader.readInt32() else { return nil }
        self.nzVars = nzV

        guard let uir = reader.readInt64() else { return nil }
        self.uirHead = uir

        guard let rfuC = reader.readInt32() else { return nil }
        self.rfuC = rfuC

        guard let leap = reader.readInt32() else { return nil }
        self.leapSecondLastUpdated = leap

        guard let rfuE = reader.readInt32() else { return nil }
        self.rfuE = rfuE

        // Read dimension sizes
        var dims: [Int32] = []
        for _ in 0..<numDims {
            guard let dim = reader.readInt32() else { return nil }
            dims.append(dim)
        }
        self.rDimSizes = dims
    }
}

// MARK: - Variable Descriptor Record (VDR)

struct VariableDescriptorRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let vdrNext: Int64       // Offset to next VDR
    let dataType: CDFDataType
    let maxRec: Int32        // Maximum record number written
    let vxrHead: Int64       // Offset to first VXR
    let vxrTail: Int64       // Offset to last VXR
    let flags: Int32
    let sRecords: Int32      // Type of sparse records
    let rfuB: Int32
    let rfuC: Int32
    let rfuF: Int32
    let numElems: Int32      // Number of elements (for strings)
    let num: Int32           // Variable number
    let cprOrSprOffset: Int64
    let blockingFactor: Int32
    let name: String
    let zNumDims: Int32      // Number of dimensions (zVariables only)
    let zDimSizes: [Int32]   // Dimension sizes (zVariables only)
    let dimVarys: [Bool]     // Dimension variance flags

    var isZVariable: Bool {
        return recordType == .zVDR
    }

    var totalElements: Int {
        if zDimSizes.isEmpty {
            return Int(numElems)
        }
        return zDimSizes.reduce(1) { $0 * Int($1) }
    }

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let next = reader.readInt64() else { return nil }
        self.vdrNext = next

        guard let dtRaw = reader.readInt32(),
              let dt = CDFDataType(rawValue: dtRaw) else { return nil }
        self.dataType = dt

        guard let maxR = reader.readInt32() else { return nil }
        self.maxRec = maxR

        guard let vxrH = reader.readInt64() else { return nil }
        self.vxrHead = vxrH

        guard let vxrT = reader.readInt64() else { return nil }
        self.vxrTail = vxrT

        guard let fl = reader.readInt32() else { return nil }
        self.flags = fl

        guard let sRec = reader.readInt32() else { return nil }
        self.sRecords = sRec

        guard let rfuB = reader.readInt32() else { return nil }
        self.rfuB = rfuB

        guard let rfuC = reader.readInt32() else { return nil }
        self.rfuC = rfuC

        guard let rfuF = reader.readInt32() else { return nil }
        self.rfuF = rfuF

        guard let nElems = reader.readInt32() else { return nil }
        self.numElems = nElems

        guard let varNum = reader.readInt32() else { return nil }
        self.num = varNum

        guard let cprSpr = reader.readInt64() else { return nil }
        self.cprOrSprOffset = cprSpr

        guard let blocking = reader.readInt32() else { return nil }
        self.blockingFactor = blocking

        // Name is 256 bytes, null-padded
        guard let varName = reader.readString(length: 256) else { return nil }
        self.name = varName

        // For zVariables, read dimensions
        if type == .zVDR {
            guard let numDims = reader.readInt32() else { return nil }
            self.zNumDims = numDims

            var sizes: [Int32] = []
            for _ in 0..<numDims {
                guard let s = reader.readInt32() else { return nil }
                sizes.append(s)
            }
            self.zDimSizes = sizes

            // Read dimension variances (-1 = VARY, 0 = NOVARY)
            var varys: [Bool] = []
            for _ in 0..<numDims {
                guard let v = reader.readInt32() else { return nil }
                varys.append(v != 0)
            }
            self.dimVarys = varys
        } else {
            self.zNumDims = 0
            self.zDimSizes = []
            self.dimVarys = []
        }
    }
}

// MARK: - Variable Index Record (VXR)

struct VariableIndexRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let vxrNext: Int64       // Offset to next VXR
    let nEntries: Int32      // Number of entries allocated
    let nUsedEntries: Int32  // Number of used entries
    let entries: [(first: Int32, last: Int32, offset: Int64)]  // Record ranges and offsets

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let next = reader.readInt64() else { return nil }
        self.vxrNext = next

        guard let nEnt = reader.readInt32() else { return nil }
        self.nEntries = nEnt

        guard let nUsed = reader.readInt32() else { return nil }
        self.nUsedEntries = nUsed

        // VXR stores arrays separately: First[nEntries], Last[nEntries], Offset[nEntries]
        // Read all First values
        var firsts: [Int32] = []
        for _ in 0..<nEnt {
            guard let first = reader.readInt32() else { return nil }
            firsts.append(first)
        }

        // Read all Last values
        var lasts: [Int32] = []
        for _ in 0..<nEnt {
            guard let last = reader.readInt32() else { return nil }
            lasts.append(last)
        }

        // Read all Offset values
        var offsets: [Int64] = []
        for _ in 0..<nEnt {
            guard let offset = reader.readInt64() else { return nil }
            offsets.append(offset)
        }

        // Combine into entries (only used entries)
        var entries: [(Int32, Int32, Int64)] = []
        for i in 0..<Int(nUsed) {
            entries.append((firsts[i], lasts[i], offsets[i]))
        }
        self.entries = entries
    }
}

// MARK: - Variable Values Record (VVR)

struct VariableValuesRecord {
    let recordSize: Int64
    let recordType: CDFRecordType

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type
    }

    var dataOffset: Int {
        return 12 // Size (8) + Type (4)
    }

    var dataSize: Int {
        return Int(recordSize) - dataOffset
    }
}

// MARK: - Compressed Variable Values Record (CVVR)

struct CompressedVariableValuesRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let rfuA: Int32          // Reserved (4 bytes, not 8!)
    let compressedSize: Int64

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let rfu = reader.readInt32() else { return nil }  // 4 bytes, not 8!
        self.rfuA = rfu

        guard let cSize = reader.readInt64() else { return nil }
        self.compressedSize = cSize
    }

    var dataOffset: Int {
        return 24 // Size (8) + Type (4) + RFU (4) + CompressedSize (8) = 24
    }
}

// MARK: - Attribute Descriptor Record (ADR)

struct AttributeDescriptorRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let adrNext: Int64
    let agrEDRhead: Int64
    let scope: Int32         // 1 = global, 2 = variable
    let num: Int32
    let ngrEntries: Int32
    let maxgrEntry: Int32
    let rfuA: Int32
    let azEDRhead: Int64
    let nzEntries: Int32
    let maxzEntry: Int32
    let rfuE: Int32
    let name: String

    var isGlobal: Bool {
        return scope == 1
    }

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let next = reader.readInt64() else { return nil }
        self.adrNext = next

        guard let agrHead = reader.readInt64() else { return nil }
        self.agrEDRhead = agrHead

        guard let sc = reader.readInt32() else { return nil }
        self.scope = sc

        guard let n = reader.readInt32() else { return nil }
        self.num = n

        guard let ngrE = reader.readInt32() else { return nil }
        self.ngrEntries = ngrE

        guard let maxgr = reader.readInt32() else { return nil }
        self.maxgrEntry = maxgr

        guard let rfuA = reader.readInt32() else { return nil }
        self.rfuA = rfuA

        guard let azHead = reader.readInt64() else { return nil }
        self.azEDRhead = azHead

        guard let nzE = reader.readInt32() else { return nil }
        self.nzEntries = nzE

        guard let maxz = reader.readInt32() else { return nil }
        self.maxzEntry = maxz

        guard let rfuE = reader.readInt32() else { return nil }
        self.rfuE = rfuE

        guard let attrName = reader.readString(length: 256) else { return nil }
        self.name = attrName
    }
}

// MARK: - Attribute Entry Descriptor Record

struct AttributeEntryRecord {
    let recordSize: Int64
    let recordType: CDFRecordType
    let aedrNext: Int64
    let attrNum: Int32
    let dataType: CDFDataType
    let num: Int32
    let numElems: Int32
    let rfuA: Int32
    let rfuB: Int32
    let rfuC: Int32
    let rfuD: Int32
    let rfuE: Int32
    let value: Data

    init?(reader: CDFBinaryReader) {
        guard let size = reader.readInt64() else { return nil }
        self.recordSize = size

        guard let typeRaw = reader.readInt32(),
              let type = CDFRecordType(rawValue: typeRaw) else { return nil }
        self.recordType = type

        guard let next = reader.readInt64() else { return nil }
        self.aedrNext = next

        guard let attrN = reader.readInt32() else { return nil }
        self.attrNum = attrN

        guard let dtRaw = reader.readInt32(),
              let dt = CDFDataType(rawValue: dtRaw) else { return nil }
        self.dataType = dt

        guard let n = reader.readInt32() else { return nil }
        self.num = n

        guard let nElems = reader.readInt32() else { return nil }
        self.numElems = nElems

        guard let rfuA = reader.readInt32() else { return nil }
        self.rfuA = rfuA

        guard let rfuB = reader.readInt32() else { return nil }
        self.rfuB = rfuB

        guard let rfuC = reader.readInt32() else { return nil }
        self.rfuC = rfuC

        guard let rfuD = reader.readInt32() else { return nil }
        self.rfuD = rfuD

        guard let rfuE = reader.readInt32() else { return nil }
        self.rfuE = rfuE

        // Value data
        let valueSize = Int(numElems) * dataType.byteSize
        guard let valueData = reader.readBytes(valueSize) else { return nil }
        self.value = valueData
    }

    func stringValue() -> String? {
        if dataType == .char || dataType == .uchar {
            var str = String(data: value, encoding: .utf8)
            // Trim null padding
            if let nullIndex = str?.firstIndex(of: "\0") {
                str = String(str![..<nullIndex])
            }
            return str
        }
        return nil
    }
}
