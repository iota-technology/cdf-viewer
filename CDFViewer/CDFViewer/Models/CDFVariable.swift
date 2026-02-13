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

    /// Component labels from LABL_PTR_* attribute (e.g., ["x", "y", "z", "w"] for quaternions)
    /// This is resolved after parsing by looking up the referenced label variable.
    var componentLabels: [String]?

    /// Row labels for matrix variables (from LABL_PTR_1)
    var matrixRowLabels: [String]?

    /// Column labels for matrix variables (from LABL_PTR_2)
    var matrixColumnLabels: [String]?

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
    /// The threshold of > 10 distinguishes actual arrays from vectors (2-10 elements)
    /// which should be displayed as columns rather than separate rows.
    var isSingleRecordArray: Bool {
        return maxRecord == 0 && dimensions.count == 1 && dimensions[0] > 10
    }

    /// Whether each CDF record contains multiple displayable rows.
    /// This is true for 2D arrays like [N, 3] where N elements per record
    /// should each become a separate display row with 3 columns.
    /// Note: Small matrices (≤10x10) are displayed as single rows with many columns.
    var hasMultipleRowsPerRecord: Bool {
        guard dimensions.count == 2 && dimensions[0] > 1 else { return false }
        // Matrices are displayed as a single row with combined columns
        return !isMatrix
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
        if let size = vectorSize {
            return size
        }
        if let dims = matrixDimensions {
            // Matrices display all elements as columns (rows * cols)
            return dims.rows * dims.cols
        }
        if dimensions.isEmpty || dimensions == [1] {
            return 1
        }
        return dimensions.last ?? 1
    }

    /// Whether this variable contains vector data (2D, 3D, 4D quaternion, etc.)
    /// Vectors are defined as 1D arrays with size between 2 and 10.
    /// Note: 2D arrays are matrices, not vectors.
    var isVector: Bool {
        guard dimensions.count == 1, let lastDim = dimensions.last else { return false }
        return lastDim >= 2 && lastDim <= 10
    }

    /// Whether this variable contains matrix data (2D array with small dimensions).
    /// Matrices are defined as 2D arrays where both dimensions are between 2 and 10.
    var isMatrix: Bool {
        guard dimensions.count == 2 else { return false }
        return dimensions[0] >= 2 && dimensions[0] <= 10 &&
               dimensions[1] >= 2 && dimensions[1] <= 10
    }

    /// Matrix dimensions (rows, cols), or nil if not a matrix
    var matrixDimensions: (rows: Int, cols: Int)? {
        guard isMatrix else { return nil }
        return (rows: dimensions[0], cols: dimensions[1])
    }

    /// Generate combined matrix labels (e.g., ["xx", "xy", "xz", "yx", ...])
    /// Returns nil if not a matrix or if no real labels are available from LABL_PTR attributes
    var combinedMatrixLabels: [String]? {
        guard let dims = matrixDimensions else { return nil }

        // Only generate combined labels if we have real labels from LABL_PTR
        guard let rowLabels = matrixRowLabels, let colLabels = matrixColumnLabels,
              rowLabels.count == dims.rows, colLabels.count == dims.cols else {
            return nil
        }

        // Generate combined labels in row-major order
        var labels: [String] = []
        for row in 0..<dims.rows {
            for col in 0..<dims.cols {
                labels.append("\(rowLabels[row])\(colLabels[col])")
            }
        }
        return labels
    }

    /// Size of the vector (number of components), or nil if not a vector
    var vectorSize: Int? {
        guard isVector else { return nil }
        return dimensions.last
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

    /// Whether this appears to be a timestamp variable.
    /// Uses specific patterns to avoid false positives on variables like "ontime", "runtime", etc.
    var isTimestamp: Bool {
        // Always true for time data types (EPOCH, EPOCH16, TT2000)
        if dataType.isTimeType {
            return true
        }

        let lowerName = name.lowercased()
        // Check for "timestamp" anywhere
        if lowerName.contains("timestamp") {
            return true
        }
        // Check for names starting with "time" (e.g., "time", "time_utc", "time_gps")
        if lowerName.hasPrefix("time") {
            return true
        }
        // Check for "_time" suffix (e.g., "utc_time", "gps_time")
        if lowerName.hasSuffix("_time") {
            return true
        }
        return false
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

    /// Get the UNITS attribute value (e.g., "meters", "m/s")
    var units: String? {
        if let units = attributes["UNITS"], !units.isEmpty {
            return units
        }
        return nil
    }

    /// SF icon name for this variable type
    var iconName: String {
        if isTimestamp {
            return "clock"
        } else if isECEFPosition || isECEFVelocity {
            return "globe"
        } else if isMatrix {
            return "square.grid.3x3"
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

    /// Appropriate column width based on data type
    static func widthForDataType(_ dataType: CDFDataType) -> CGFloat {
        if dataType.isTimeType {
            // ISO8601 timestamps with fractional seconds need more space
            return 220
        }
        return 150
    }

    /// Get component names for a variable.
    /// Uses componentLabels from LABL_PTR_* if available, otherwise uses indices.
    static func componentNames(for variable: CDFVariable) -> [String] {
        guard let size = variable.vectorSize else { return [] }

        // Use labels from CDF file if available
        if let labels = variable.componentLabels, labels.count == size {
            return labels
        }

        // Fall back to indices - no assumptions about meaning
        return (0..<size).map { "[\($0)]" }
    }

    static func columnsForVariable(_ variable: CDFVariable) -> [CDFColumn] {
        let width = widthForDataType(variable.dataType)

        // Single record with 1D array: dimension elements become rows, single value column
        if variable.isSingleRecordArray {
            return [
                CDFColumn(id: 0, name: variable.name, dataType: variable.dataType, width: width)
            ]
        }

        // Vector variable (2-10 components): show with appropriate column names
        if variable.vectorSize != nil {
            let names = componentNames(for: variable)
            return names.enumerated().map { i, name in
                CDFColumn(id: i, name: name, dataType: variable.dataType, width: 120)
            }
        }

        // Matrix variable: show with combined row/column labels
        if let dims = variable.matrixDimensions {
            let labels = variable.combinedMatrixLabels ?? (0..<(dims.rows * dims.cols)).map { "[\($0)]" }
            return labels.enumerated().map { i, name in
                CDFColumn(id: i, name: name, dataType: variable.dataType, width: 100)
            }
        }

        // Scalar or single-element dimension
        if variable.dimensions.isEmpty || variable.dimensions == [1] {
            return [
                CDFColumn(id: 0, name: variable.name, dataType: variable.dataType, width: width)
            ]
        }

        // Multi-dimensional - last dimension becomes columns
        let count = variable.dimensions.last ?? 1
        return (0..<count).map { i in
            CDFColumn(id: i, name: "[\(i)]", dataType: variable.dataType, width: width)
        }
    }
}
