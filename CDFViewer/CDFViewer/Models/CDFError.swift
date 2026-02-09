import Foundation

/// Errors that can occur when reading CDF files
enum CDFError: LocalizedError {
    case fileNotFound(String)
    case invalidMagicNumber
    case unsupportedVersion(Int, Int)
    case invalidRecordType(Int32, at: Int)
    case unexpectedEndOfFile(at: Int, expected: Int)
    case invalidVariableDescriptor(String)
    case decompressionFailed(String)
    case dataReadFailed(variable: String, reason: String)
    case invalidDataType(Int32)
    case corruptedData(String)
    case unsupportedFeature(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "CDF file not found: \(path)"
        case .invalidMagicNumber:
            return "Not a valid CDF file. Expected 'CDF3' magic number at file start."
        case .unsupportedVersion(let version, let release):
            return "Unsupported CDF version \(version).\(release). This viewer supports CDF 3.x."
        case .invalidRecordType(let type, let offset):
            return "Invalid record type \(type) at byte offset \(offset)."
        case .unexpectedEndOfFile(let at, let expected):
            return "Unexpected end of file at byte \(at). Expected at least \(expected) more bytes."
        case .invalidVariableDescriptor(let name):
            return "Invalid variable descriptor for '\(name)'."
        case .decompressionFailed(let reason):
            return "Failed to decompress data: \(reason)"
        case .dataReadFailed(let variable, let reason):
            return "Failed to read data for variable '\(variable)': \(reason)"
        case .invalidDataType(let type):
            return "Invalid or unsupported data type code: \(type)"
        case .corruptedData(let details):
            return "Corrupted CDF data: \(details)"
        case .unsupportedFeature(let feature):
            return "Unsupported CDF feature: \(feature)"
        }
    }

    var failureReason: String? {
        switch self {
        case .invalidMagicNumber:
            return "The file does not begin with the expected CDF signature bytes."
        case .decompressionFailed:
            return "The compressed data block could not be decompressed. The file may be corrupted."
        case .corruptedData:
            return "The file structure does not match the expected CDF format."
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidMagicNumber:
            return "Verify this is a NASA CDF file and not a different format (e.g., netCDF, HDF5)."
        case .unsupportedVersion:
            return "Try using NASA's CDF tools to convert the file to CDF 3.x format."
        case .decompressionFailed:
            return "Try re-downloading the file or use NASA's cdfdump tool to verify file integrity."
        case .unsupportedFeature:
            return "Some advanced CDF features may not be supported. Try using NASA's official CDF tools."
        default:
            return nil
        }
    }
}

/// Warnings during CDF parsing (non-fatal issues)
struct CDFWarning: Identifiable {
    let id = UUID()
    let message: String
    let location: String?
    let severity: Severity

    enum Severity {
        case info
        case warning
        case error
    }
}
