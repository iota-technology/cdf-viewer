import Foundation
import UniformTypeIdentifiers

/// Represents an open CDF file
@Observable
final class CDFFile: Identifiable {
    let id = UUID()
    let url: URL
    private let reader: CDFReader

    // Parsed data
    private(set) var fileInfo: CDFFileInfo
    private(set) var variables: [CDFVariable] = []
    private(set) var attributes: [CDFAttribute] = []
    private(set) var warnings: [CDFWarning] = []
    private(set) var parseError: CDFError?

    // Selection state
    var selectedVariable: CDFVariable?

    // Cached data for selected variable
    private var cachedVariableData: [String: [CDFValue]] = [:]

    init(url: URL) throws {
        self.url = url
        self.reader = try CDFReader(url: url)

        // Parse immediately
        do {
            try reader.parse()
            self.fileInfo = reader.fileInfo
            self.variables = reader.variables
            self.attributes = reader.attributes
            self.warnings = reader.warnings
        } catch let error as CDFError {
            self.parseError = error
            self.fileInfo = CDFFileInfo(
                url: url,
                version: "Error",
                encoding: "Unknown",
                majority: "Unknown",
                numVariables: 0,
                numAttributes: 0,
                copyright: ""
            )
            throw error
        }
    }

    var fileName: String {
        url.lastPathComponent
    }

    // MARK: - Data Access

    /// Read all data for a variable
    func readData(for variable: CDFVariable) throws -> [CDFValue] {
        if let cached = cachedVariableData[variable.name] {
            return cached
        }

        let data = try reader.readVariableData(variable)
        cachedVariableData[variable.name] = data
        return data
    }

    /// Read data as rows for table display
    func readDataRows(for variable: CDFVariable, range: Range<Int>? = nil) throws -> [CDFDataRow] {
        let allData = try readData(for: variable)

        guard !allData.isEmpty else { return [] }

        // Single record with 1D array: treat dimension elements as rows
        if variable.isSingleRecordArray {
            let effectiveRange = range ?? (0..<variable.displayRowCount)
            var rows: [CDFDataRow] = []

            for elementIndex in effectiveRange {
                guard elementIndex < allData.count else { break }
                rows.append(CDFDataRow(id: elementIndex, values: [allData[elementIndex]]))
            }

            return rows
        }

        // 2D array with [rows, cols] shape: first dimension is rows, second is columns
        if variable.dimensions.count == 2 {
            let colsPerRow = variable.dimensions[1]
            let effectiveRange = range ?? (0..<variable.displayRowCount)
            var rows: [CDFDataRow] = []

            for rowIndex in effectiveRange {
                let startIndex = rowIndex * colsPerRow
                let endIndex = min(startIndex + colsPerRow, allData.count)
                guard startIndex < allData.count else { break }
                let rowValues = Array(allData[startIndex..<endIndex])
                rows.append(CDFDataRow(id: rowIndex, values: rowValues))
            }

            return rows
        }

        // Standard case: records as rows
        let elementsPerRecord = variable.totalElements
        guard elementsPerRecord > 0 else { return [] }

        let effectiveRange = range ?? (0..<variable.recordCount)
        var rows: [CDFDataRow] = []

        for recordIndex in effectiveRange {
            let startIndex = recordIndex * elementsPerRecord
            let endIndex = min(startIndex + elementsPerRecord, allData.count)

            guard startIndex < allData.count else { break }

            let rowValues = Array(allData[startIndex..<endIndex])
            rows.append(CDFDataRow(id: recordIndex, values: rowValues))
        }

        return rows
    }

    /// Read doubles for a variable (for charting)
    func readDoubles(for variable: CDFVariable) throws -> [Double] {
        return try reader.readVariableDoubles(variable)
    }

    /// Read timestamps as Unix seconds
    func readTimestamps(for variable: CDFVariable) throws -> [Double] {
        let values = try readData(for: variable)
        return values.compactMap { value -> Double? in
            switch value {
            case .int64(let v):
                // Assume milliseconds since Unix epoch
                return Double(v) / 1000.0
            case .timeTT2000(let v):
                // Nanoseconds since J2000
                let j2000Unix = 946728000.0
                return j2000Unix + Double(v) / 1e9
            case .epoch(let v):
                // Milliseconds since 0 AD
                let epochToUnix = 62167219200000.0
                return (v - epochToUnix) / 1000.0
            case .float64(let v):
                return v
            default:
                return nil
            }
        }
    }

    /// Read ECEF positions as (x, y, z) tuples in meters
    func readECEFPositions(for variable: CDFVariable) throws -> [(x: Double, y: Double, z: Double)] {
        let data = try readData(for: variable)
        var positions: [(Double, Double, Double)] = []

        // Check if this is a 2D array [n, 3] or separate x, y, z
        if variable.dimensions.count == 2 && variable.dimensions[1] == 3 {
            // Single variable with [n, 3] shape
            for i in stride(from: 0, to: data.count, by: 3) {
                guard i + 2 < data.count,
                      let x = data[i].doubleValue,
                      let y = data[i + 1].doubleValue,
                      let z = data[i + 2].doubleValue else { continue }
                positions.append((x, y, z))
            }
        } else {
            // Scalar array - need to combine with other variables
            // This would be handled at a higher level
            for value in data {
                if let d = value.doubleValue {
                    positions.append((d, 0, 0))
                }
            }
        }

        return positions
    }

    // MARK: - Variable Lookup

    func timestampVariables() -> [CDFVariable] {
        return variables.filter { $0.isTimestamp }
    }

    func ecefPositionVariables() -> [CDFVariable] {
        return variables.filter { $0.isECEFPosition }
    }

    func ecefVelocityVariables() -> [CDFVariable] {
        return variables.filter { $0.isECEFVelocity }
    }

    func numericVariables() -> [CDFVariable] {
        return variables.filter { $0.dataType.isNumeric && !$0.isTimestamp }
    }

    // MARK: - Memory Management

    func clearCache() {
        cachedVariableData.removeAll()
        reader.clearCache()
    }
}

// MARK: - UTType Extension

extension UTType {
    static var cdf: UTType {
        UTType(importedAs: "gov.nasa.gsfc.cdf")
    }
}
