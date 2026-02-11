import Foundation

// MARK: - Parser Options

/// Configuration options for CDF parsing behavior
struct CDFParserOptions {
    /// When enabled, treats INT8 variables with names starting with "timestamp"
    /// as Unix timestamps in microseconds (microseconds since 1970-01-01).
    /// Default: false (INT8 values are read as raw integers)
    var treatInt64TimestampAsUnixMicroseconds: Bool = false

    /// Default options (no special handling)
    static let `default` = CDFParserOptions()

    /// Options with Unix timestamp interpretation for INT8 "timestamp*" variables
    static let withUnixTimestamps = CDFParserOptions(treatInt64TimestampAsUnixMicroseconds: true)
}

/// CDF data type codes
enum CDFDataType: Int32 {
    case int1 = 1        // CDF_INT1 - 1-byte signed integer
    case int2 = 2        // CDF_INT2 - 2-byte signed integer
    case int4 = 4        // CDF_INT4 - 4-byte signed integer
    case int8 = 8        // CDF_INT8 - 8-byte signed integer
    case uint1 = 11      // CDF_UINT1 - 1-byte unsigned integer
    case uint2 = 12      // CDF_UINT2 - 2-byte unsigned integer
    case uint4 = 14      // CDF_UINT4 - 4-byte unsigned integer
    case real4 = 21      // CDF_REAL4 - 4-byte floating point
    case real8 = 22      // CDF_REAL8 - 8-byte floating point
    case epoch = 31      // CDF_EPOCH - 8-byte floating point (milliseconds since 0 AD)
    case epoch16 = 32    // CDF_EPOCH16 - 16-byte (two doubles)
    case timeTT2000 = 33 // CDF_TIME_TT2000 - 8-byte signed integer (nanoseconds since J2000)
    case float = 44      // CDF_FLOAT - 4-byte floating point
    case double = 45     // CDF_DOUBLE - 8-byte floating point
    case char = 51       // CDF_CHAR - 1-byte character
    case uchar = 52      // CDF_UCHAR - 1-byte unsigned character

    /// Size in bytes of this data type
    var byteSize: Int {
        switch self {
        case .int1, .uint1, .char, .uchar: return 1
        case .int2, .uint2: return 2
        case .int4, .uint4, .real4, .float: return 4
        case .int8, .real8, .double, .epoch, .timeTT2000: return 8
        case .epoch16: return 16
        }
    }

    /// Human-readable name
    var displayName: String {
        switch self {
        case .int1: return "INT1"
        case .int2: return "INT2"
        case .int4: return "INT4"
        case .int8: return "INT8"
        case .uint1: return "UINT1"
        case .uint2: return "UINT2"
        case .uint4: return "UINT4"
        case .real4: return "REAL4"
        case .real8: return "REAL8"
        case .epoch: return "EPOCH"
        case .epoch16: return "EPOCH16"
        case .timeTT2000: return "TT2000"
        case .float: return "FLOAT"
        case .double: return "DOUBLE"
        case .char: return "CHAR"
        case .uchar: return "UCHAR"
        }
    }

    /// Whether this is a numeric type
    var isNumeric: Bool {
        switch self {
        case .char, .uchar: return false
        default: return true
        }
    }

    /// Whether this is a time/epoch type
    var isTimeType: Bool {
        switch self {
        case .epoch, .epoch16, .timeTT2000: return true
        default: return false
        }
    }

    /// Whether this is an integer type (for display formatting)
    var isIntegerType: Bool {
        switch self {
        case .int1, .int2, .int4, .int8, .uint1, .uint2, .uint4:
            return true
        default:
            return false
        }
    }
}

/// Wrapper for CDF values that can hold any data type
enum CDFValue: Hashable {
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case float32(Float)
    case float64(Double)
    case string(String)
    case epoch(Double)           // Milliseconds since 0 AD
    case epoch16(Double, Double) // Two doubles for higher precision
    case timeTT2000(Int64)       // Nanoseconds since J2000
    case unixTimestamp(Int64)    // Microseconds since Unix epoch (1970)

    var doubleValue: Double? {
        switch self {
        case .int8(let v): return Double(v)
        case .int16(let v): return Double(v)
        case .int32(let v): return Double(v)
        case .int64(let v): return Double(v)
        case .uint8(let v): return Double(v)
        case .uint16(let v): return Double(v)
        case .uint32(let v): return Double(v)
        case .float32(let v): return Double(v)
        case .float64(let v): return v
        case .epoch(let v): return v
        case .epoch16(let v, _): return v
        case .timeTT2000(let v): return Double(v)
        case .unixTimestamp(let v): return Double(v)
        case .string: return nil
        }
    }

    var stringValue: String {
        switch self {
        case .int8(let v): return String(v)
        case .int16(let v): return String(v)
        case .int32(let v): return String(v)
        case .int64(let v): return String(v)
        case .uint8(let v): return String(v)
        case .uint16(let v): return String(v)
        case .uint32(let v): return String(v)
        case .float32(let v): return formatNumber(Double(v))
        case .float64(let v): return formatNumber(v)
        case .string(let v): return v
        case .epoch(let v): return formatEpoch(v)
        case .epoch16(let v1, let v2): return formatEpoch16(v1, v2)
        case .timeTT2000(let v): return formatTT2000(v)
        case .unixTimestamp(let v): return formatUnixTimestamp(v)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.6e", value)
        } else {
            return String(format: "%.6g", value)
        }
    }

    private func formatEpoch(_ milliseconds: Double) -> String {
        // CDF EPOCH: milliseconds since 0 AD
        // Convert to Unix timestamp (seconds since 1970)
        let epochToUnix = 62167219200000.0 // milliseconds from 0 AD to 1970
        let unixMs = milliseconds - epochToUnix
        let date = Date(timeIntervalSince1970: unixMs / 1000.0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func formatEpoch16(_ d1: Double, _ d2: Double) -> String {
        // First double is milliseconds, second is picoseconds remainder
        return formatEpoch(d1) + " (ps: \(d2))"
    }

    private func formatTT2000(_ nanoseconds: Int64) -> String {
        // CDF TT2000: nanoseconds since J2000 (2000-01-01 12:00:00 TT)
        // J2000 in Unix time: 946728000 seconds (approximately)
        let j2000Unix = 946728000.0
        let seconds = Double(nanoseconds) / 1e9
        let date = Date(timeIntervalSince1970: j2000Unix + seconds)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func formatUnixTimestamp(_ microseconds: Int64) -> String {
        // Unix timestamp: microseconds since 1970-01-01 00:00:00 UTC
        let seconds = Double(microseconds) / 1_000_000.0
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// CDF encoding types
enum CDFEncoding: Int32 {
    case network = 1     // Network (XDR)
    case sun = 2         // Sun
    case vax = 3         // VAX
    case decstation = 4  // DECstation
    case sgi = 5         // SGI
    case ibmpc = 6       // IBMPC (little-endian)
    case ibmrs = 7       // IBM RS
    case host = 8        // Host
    case ppc = 9         // PPC
    case hp = 11         // HP
    case neXT = 12       // NeXT
    case alphaosf1 = 13  // Alpha OSF/1
    case alphavmsd = 14  // Alpha VMS D
    case alphavmsg = 15  // Alpha VMS G
    case alphavmsi = 16  // Alpha VMS I
    case arm_little = 17 // ARM little-endian
    case arm_big = 18    // ARM big-endian
    case ia64vms_i = 19  // IA64 VMS I
    case ia64vms_d = 20  // IA64 VMS D
    case ia64vms_g = 21  // IA64 VMS G

    /// Whether this encoding is little-endian
    var isLittleEndian: Bool {
        switch self {
        case .vax, .decstation, .ibmpc, .alphavmsd, .alphavmsg, .alphavmsi, .alphaosf1, .arm_little, .ia64vms_i, .ia64vms_d, .ia64vms_g:
            return true
        default:
            return false
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .network: return "Network (XDR)"
        case .sun: return "Sun"
        case .vax: return "VAX"
        case .decstation: return "DECstation"
        case .sgi: return "SGI"
        case .ibmpc: return "IBM PC"
        case .ibmrs: return "IBM RS"
        case .host: return "Host"
        case .ppc: return "PowerPC"
        case .hp: return "HP"
        case .neXT: return "NeXT"
        case .alphaosf1: return "Alpha OSF/1"
        case .alphavmsd: return "Alpha VMS D"
        case .alphavmsg: return "Alpha VMS G"
        case .alphavmsi: return "Alpha VMS I"
        case .arm_little: return "ARM (little-endian)"
        case .arm_big: return "ARM (big-endian)"
        case .ia64vms_i: return "IA64 VMS I"
        case .ia64vms_d: return "IA64 VMS D"
        case .ia64vms_g: return "IA64 VMS G"
        }
    }
}

/// CDF majority (row vs column major)
enum CDFMajority: Int32 {
    case row = 1
    case column = 2
}
