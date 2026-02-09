import Foundation

/// Represents a variable in a CDF file
struct CDFVariable: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dataType: CDFDataType
    let numElements: Int
    let dimensions: [Int]
    let dimVarys: [Bool]
    let maxRecord: Int
    let isZVariable: Bool
    let vxrOffset: Int64
    let cprOffset: Int64
    let attributes: [String: String]

    /// Total number of elements per record
    var totalElements: Int {
        if dimensions.isEmpty {
            return numElements
        }
        return dimensions.reduce(1, *)
    }

    /// Total number of records
    var recordCount: Int {
        return maxRecord + 1
    }

    /// Whether this is a single-record variable with a 1D array dimension.
    /// In this case, we display dimension elements as rows rather than records.
    /// The threshold of > 3 distinguishes actual arrays from 3-vectors which
    /// should be displayed as X/Y/Z columns rather than separate rows.
    var isSingleRecordArray: Bool {
        return maxRecord == 0 && dimensions.count == 1 && dimensions[0] > 3
    }

    /// Whether each CDF record contains multiple displayable rows.
    /// This is true for 2D arrays like [N, 3] where N elements per record
    /// should each become a separate display row with 3 columns.
    var hasMultipleRowsPerRecord: Bool {
        return dimensions.count == 2 && dimensions[0] > 1
    }

    /// Effective row count for display (accounts for arrays stored as single records)
    var displayRowCount: Int {
        if isSingleRecordArray {
            return dimensions[0]
        }
        if hasMultipleRowsPerRecord {
            return dimensions[0] * recordCount
        }
        return recordCount
    }

    /// Number of columns per display row
    var displayColumnsPerRow: Int {
        if isSingleRecordArray {
            return 1
        }
        if dimensions.count >= 2 && dimensions.last == 3 {
            return 3  // 3-vector
        }
        if dimensions.isEmpty || dimensions == [1] {
            return 1
        }
        return dimensions.last ?? 1
    }

    /// Whether this variable contains vector data (e.g., 3-vec)
    var isVector: Bool {
        return dimensions.count >= 1 && dimensions.last == 3
    }

    /// Whether this appears to be ECEF position data
    var isECEFPosition: Bool {
        let lowerName = name.lowercased()
        return lowerName.contains("ecef") && (lowerName.contains("r_") || lowerName.contains("pos") || lowerName.hasPrefix("r"))
    }

    /// Whether this appears to be ECEF velocity data
    var isECEFVelocity: Bool {
        let lowerName = name.lowercased()
        return lowerName.contains("ecef") && (lowerName.contains("v_") || lowerName.contains("vel") || lowerName.hasPrefix("v"))
    }

    /// Whether this appears to be a timestamp
    var isTimestamp: Bool {
        let lowerName = name.lowercased()
        return lowerName.contains("timestamp") || lowerName.contains("time") || dataType.isTimeType
    }

    /// Dimension string for display (e.g., "[86400, 3]")
    var dimensionString: String {
        if dimensions.isEmpty {
            if numElements > 1 {
                return "[\(numElements)]"
            }
            return "scalar"
        }
        return "[\(dimensions.map { String($0) }.joined(separator: ", "))]"
    }

    /// Full type string for display (e.g., "CDF_DOUBLE [86400, 3]")
    var typeString: String {
        return "\(dataType.displayName) \(dimensionString)"
    }

    /// Get the DEPEND attribute value (dependency on another variable)
    var dependsOn: String? {
        return attributes["DEPEND_1"] ?? attributes["DEPEND_0"]
    }

    /// SF icon name for this variable type
    var iconName: String {
        if isTimestamp {
            return "clock"
        } else if isECEFPosition || isECEFVelocity {
            return "globe"
        } else if isVector {
            return "arrow.up.right.and.arrow.down.left"
        } else if dataType == .char || dataType == .uchar {
            return "textformat"
        } else {
            return "number"
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CDFVariable, rhs: CDFVariable) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a row of data from a CDF variable
struct CDFDataRow: Identifiable {
    let id: Int  // Record number
    let values: [CDFValue]

    /// Get value at column index
    subscript(column: Int) -> CDFValue? {
        guard column >= 0 && column < values.count else { return nil }
        return values[column]
    }

    /// Get values as a vector (for 3-vec data)
    var asVector: (x: Double, y: Double, z: Double)? {
        guard values.count >= 3,
              let x = values[0].doubleValue,
              let y = values[1].doubleValue,
              let z = values[2].doubleValue else {
            return nil
        }
        return (x, y, z)
    }
}

/// Column definition for data table
struct CDFColumn: Identifiable {
    let id: Int
    let name: String
    let dataType: CDFDataType
    let width: CGFloat

    static func columnsForVariable(_ variable: CDFVariable) -> [CDFColumn] {
        // Single record with 1D array: dimension elements become rows, single value column
        if variable.isSingleRecordArray {
            return [
                CDFColumn(id: 0, name: variable.name, dataType: variable.dataType, width: 150)
            ]
        }

        // 2D array with last dim = 3 (e.g., [N, 3] for positions): show as X, Y, Z
        if variable.dimensions.count == 2 && variable.dimensions[1] == 3 {
            return [
                CDFColumn(id: 0, name: "X", dataType: variable.dataType, width: 120),
                CDFColumn(id: 1, name: "Y", dataType: variable.dataType, width: 120),
                CDFColumn(id: 2, name: "Z", dataType: variable.dataType, width: 120)
            ]
        }

        // 1D array with exactly 3 elements: show as X, Y, Z
        if variable.dimensions.count == 1 && variable.dimensions[0] == 3 {
            return [
                CDFColumn(id: 0, name: "X", dataType: variable.dataType, width: 120),
                CDFColumn(id: 1, name: "Y", dataType: variable.dataType, width: 120),
                CDFColumn(id: 2, name: "Z", dataType: variable.dataType, width: 120)
            ]
        }

        // Scalar or single-element dimension
        if variable.dimensions.isEmpty || variable.dimensions == [1] {
            return [
                CDFColumn(id: 0, name: variable.name, dataType: variable.dataType, width: 150)
            ]
        }

        // Multi-dimensional - last dimension becomes columns
        let count = variable.dimensions.last ?? 1
        return (0..<count).map { i in
            CDFColumn(id: i, name: "[\(i)]", dataType: variable.dataType, width: 100)
        }
    }
}
