import Foundation
import UniformTypeIdentifiers

/// Represents an open CDF file
@Observable
final class CDFFile: Identifiable {
    let id = UUID()
    let url: URL
    private let reader: CDFReader

    /// Parser options for configuring how data is interpreted
    let parserOptions: CDFParserOptions

    // Parsed data
    private(set) var fileInfo: CDFFileInfo
    private(set) var variables: [CDFVariable] = []
    private(set) var attributes: [CDFAttribute] = []
    private(set) var warnings: [CDFWarning] = []
    private(set) var parseError: CDFError?

    // Cached data
    private var cachedVariableData: [String: [CDFValue]] = [:]

    init(url: URL, displayName: String? = nil, options: CDFParserOptions = .default) throws {
        self.url = url
        self.reader = try CDFReader(url: url)
        self.parserOptions = options

        // Parse immediately
        do {
            try reader.parse()
            self.fileInfo = reader.fileInfo(displayName: displayName)
            self.variables = reader.variables
            self.attributes = reader.attributes
            self.warnings = reader.warnings

            // Resolve LABL_PTR_* attributes to get component labels for vector variables
            resolveComponentLabels()
        } catch let error as CDFError {
            self.parseError = error
            self.fileInfo = CDFFileInfo(
                url: url,
                version: "Error",
                encoding: "Unknown",
                majority: "Unknown",
                numVariables: 0,
                numAttributes: 0,
                copyright: "",
                displayName: displayName
            )
            throw error
        }
    }

    var fileName: String {
        fileInfo.fileName
    }

    // MARK: - Component Label Resolution

    /// Resolve LABL_PTR_* attributes to populate componentLabels for vector variables.
    /// CDF ISTP convention uses LABL_PTR_1, LABL_PTR_2, etc. to point to label variables.
    /// Handles three formats:
    /// 1. Single variable name pointing to a label array (standard ISTP)
    /// 2. Multiple variable names (one per component), each containing a label string
    /// 3. Direct labels in the attribute value itself (separated by newlines)
    private func resolveComponentLabels() {
        var updatedVariables: [CDFVariable] = []

        for var variable in variables {
            guard variable.isVector else {
                updatedVariables.append(variable)
                continue
            }

            // Find the appropriate LABL_PTR_* attribute for the component dimension
            guard let labelPointerKey = findLabelPointerKey(for: variable),
                  let labelPointerValue = variable.attributes[labelPointerKey] else {
                updatedVariables.append(variable)
                continue
            }

            // Case 1: Single variable name pointing to label array
            if let labelVariable = variables.first(where: { $0.name == labelPointerValue }) {
                if let labels = readLabels(from: labelVariable) {
                    variable.componentLabels = labels
                }
            }
            // Case 2 & 3: Multiple values (newline-separated variable names or direct labels)
            else if labelPointerValue.contains("\n") || labelPointerValue.contains(",") {
                let separator = labelPointerValue.contains("\n") ? "\n" : ","
                let parts = labelPointerValue.components(separatedBy: separator)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Try to look up each part as a variable name
                var labels: [String] = []
                for part in parts {
                    if let labelVar = variables.first(where: { $0.name == part }),
                       let label = readSingleLabel(from: labelVar) {
                        labels.append(label)
                    } else {
                        // Use the part itself as the label (clean it up)
                        labels.append(cleanupLabel(part))
                    }
                }

                if labels.count == variable.vectorSize {
                    variable.componentLabels = labels
                }
            }

            updatedVariables.append(variable)
        }

        self.variables = updatedVariables
    }

    /// Find the appropriate LABL_PTR_* attribute key for a variable's component dimension.
    /// Returns the first LABL_PTR_N that exists in the variable's attributes.
    private func findLabelPointerKey(for variable: CDFVariable) -> String? {
        // Try LABL_PTR_1 through LABL_PTR_3 (covers most use cases)
        for n in 1...3 {
            let key = "LABL_PTR_\(n)"
            if variable.attributes[key] != nil {
                return key
            }
        }
        return nil
    }

    /// Read string labels from a label variable (array of strings).
    private func readLabels(from labelVariable: CDFVariable) -> [String]? {
        guard labelVariable.dataType == .char || labelVariable.dataType == .uchar else {
            return nil
        }

        do {
            let data = try reader.readVariableData(labelVariable)
            let labels = data.compactMap { value -> String? in
                if case .string(let s) = value {
                    return s.trimmingCharacters(in: .whitespaces)
                }
                return nil
            }
            return labels.isEmpty ? nil : labels
        } catch {
            return nil
        }
    }

    /// Read a single label string from a scalar string variable.
    private func readSingleLabel(from labelVariable: CDFVariable) -> String? {
        guard labelVariable.dataType == .char || labelVariable.dataType == .uchar else {
            return nil
        }

        do {
            let data = try reader.readVariableData(labelVariable)
            // Get the first string value
            for value in data {
                if case .string(let s) = value {
                    return s.trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Clean up a label value that might be a variable name or raw label.
    /// Examples: "x_ecef_label" → "X", "r_ecef_label" → "r_ecef"
    private func cleanupLabel(_ rawLabel: String) -> String {
        var label = rawLabel

        // Remove common suffixes like "_label", "_lbl"
        for suffix in ["_label", "_lbl", "_LABEL", "_LBL"] {
            if label.hasSuffix(suffix) {
                label = String(label.dropLast(suffix.count))
                break
            }
        }

        // If it's a simple coordinate indicator (x, y, z, w, etc.), uppercase it
        if label.count == 1 || (label.count <= 2 && label.allSatisfy { $0.isLetter }) {
            return label.uppercased()
        }

        return label
    }

    // MARK: - Data Access

    /// Read all data for a variable
    func readData(for variable: CDFVariable) throws -> [CDFValue] {
        if let cached = cachedVariableData[variable.name] {
            return cached
        }

        var data = try reader.readVariableData(variable)

        // Convert INT8 "timestamp*" variables to Unix timestamps if option is enabled
        if parserOptions.treatInt64TimestampAsUnixMicroseconds &&
           variable.dataType == .int8 &&
           variable.name.lowercased().hasPrefix("timestamp") {
            data = data.map { value in
                if case .int64(let v) = value {
                    return .unixTimestamp(v)
                }
                return value
            }
        }

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

        // CDF EPOCH offset: milliseconds from year 0 AD to Unix epoch (1970)
        let epochToUnixMs = 62167219200000.0
        // J2000 in Unix time (2000-01-01 12:00:00 TT)
        let j2000Unix = 946728000.0

        return values.compactMap { value -> Double? in
            switch value {
            case .epoch(let v):
                // CDF_EPOCH: milliseconds since 0 AD
                return (v - epochToUnixMs) / 1000.0

            case .epoch16(let v, _):
                // CDF_EPOCH16: first double is milliseconds since 0 AD
                return (v - epochToUnixMs) / 1000.0

            case .timeTT2000(let v):
                // CDF_TIME_TT2000: nanoseconds since J2000
                return j2000Unix + Double(v) / 1e9

            case .float64(let v):
                // Regular double - assume Unix seconds
                return v

            case .float32(let v):
                return Double(v)

            case .int64(let v):
                // Regular int64 - assume milliseconds since Unix epoch
                return Double(v) / 1000.0

            case .unixTimestamp(let v):
                // Unix timestamp in microseconds -> convert to seconds
                return Double(v) / 1_000_000.0

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
