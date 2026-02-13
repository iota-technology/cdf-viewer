import Foundation

/// Represents a constant variable's value(s) for display in the constants grid.
/// Constants are CDF variables without a DEPEND_0 attribute (time-independent data).
struct ConstantValue: Identifiable {
    /// Unique identifier (uses variable name)
    let id: String

    /// The underlying CDF variable
    let variable: CDFVariable

    /// The actual data values
    let values: [CDFValue]

    /// Variable name
    var name: String { variable.name }

    /// Units from the UNITS attribute (e.g., "kg", "m/s")
    var units: String? { variable.units }

    /// Formatted units with proper symbols (m² instead of m^2, ° instead of deg, etc.)
    var formattedUnits: String? {
        guard let units = units else { return nil }
        return Self.formatUnits(units)
    }

    /// Convert unit strings to use proper symbols
    static func formatUnits(_ units: String) -> String {
        var result = units

        // Superscripts for powers
        result = result.replacingOccurrences(of: "^2", with: "²")
        result = result.replacingOccurrences(of: "^3", with: "³")
        result = result.replacingOccurrences(of: "^4", with: "⁴")
        result = result.replacingOccurrences(of: "^-1", with: "⁻¹")
        result = result.replacingOccurrences(of: "^-2", with: "⁻²")
        result = result.replacingOccurrences(of: "^-3", with: "⁻³")

        // Degree symbols - order matters (more specific first)
        result = result.replacingOccurrences(of: "degC", with: "°C")
        result = result.replacingOccurrences(of: "degF", with: "°F")
        result = result.replacingOccurrences(of: "degK", with: "K")  // Kelvin doesn't use degree symbol
        result = result.replacingOccurrences(of: "deg", with: "°")

        // Micro symbol (common patterns like us, uA, uV, um, etc.)
        result = result.replacingOccurrences(of: "micro", with: "µ")
        result = result.replacingOccurrences(of: "us", with: "µs")

        // Radians
        result = result.replacingOccurrences(of: "rad", with: "ᶜ")

        return result
    }

    /// Description from CATDESC attribute
    var description: String? {
        if let desc = variable.attributes["CATDESC"], !desc.isEmpty {
            return desc
        }
        return nil
    }

    /// Field name from FIELDNAM attribute
    var fieldName: String? {
        if let name = variable.attributes["FIELDNAM"], !name.isEmpty {
            return name
        }
        return nil
    }

    /// Whether this is a scalar (single value) or array
    var isScalar: Bool {
        values.count == 1
    }

    /// Whether this is a matrix variable
    var isMatrix: Bool {
        variable.isMatrix
    }

    /// Matrix dimensions (rows, cols), or nil if not a matrix
    var matrixDimensions: (rows: Int, cols: Int)? {
        variable.matrixDimensions
    }

    /// Row labels for matrix display (nil if no real labels from LABL_PTR_1)
    var matrixRowLabels: [String]? {
        guard matrixDimensions != nil else { return nil }
        return variable.matrixRowLabels
    }

    /// Column labels for matrix display (nil if no real labels from LABL_PTR_2)
    var matrixColumnLabels: [String]? {
        guard matrixDimensions != nil else { return nil }
        return variable.matrixColumnLabels
    }

    /// Whether this matrix has real labels (from LABL_PTR attributes)
    var hasMatrixLabels: Bool {
        return matrixRowLabels != nil || matrixColumnLabels != nil
    }

    /// Matrix values organized by row for display
    var matrixRows: [[String]]? {
        guard let dims = matrixDimensions else { return nil }
        guard values.count == dims.rows * dims.cols else { return nil }

        var rows: [[String]] = []
        for row in 0..<dims.rows {
            var rowValues: [String] = []
            for col in 0..<dims.cols {
                let index = row * dims.cols + col
                rowValues.append(values[index].stringValue)
            }
            rows.append(rowValues)
        }
        return rows
    }

    /// Formatted value string for display
    var formattedValue: String {
        if values.isEmpty {
            return "(no data)"
        }

        if values.count == 1 {
            return values[0].stringValue
        }

        // For arrays, format nicely based on size
        if values.count <= 10 {
            // Small arrays: show all values inline
            let formatted = values.map { $0.stringValue }
            return "[\(formatted.joined(separator: ", "))]"
        } else {
            // Larger arrays: show first few and count
            let first3 = values.prefix(3).map { $0.stringValue }
            return "[\(first3.joined(separator: ", ")), ... (\(values.count) total)]"
        }
    }

    /// Formatted values for multi-line display (arrays)
    /// Returns tuples of (optional label, value string)
    var formattedValuesWithLabels: [(label: String?, value: String)] {
        // Use component labels if available
        if let labels = variable.componentLabels, labels.count == values.count {
            return zip(labels, values).map { label, value in
                (label: label, value: value.stringValue)
            }
        }

        // No labels, just values
        return values.map { value in
            (label: nil, value: value.stringValue)
        }
    }
}
