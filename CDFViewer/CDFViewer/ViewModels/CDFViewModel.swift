import Foundation
import SwiftUI

/// Main view model for a CDF document
@Observable
final class CDFViewModel {
    // The loaded CDF file
    var cdfFile: CDFFile?

    /// Original file URL for xattr persistence (set from NSDocument)
    var originalFileURL: URL?

    /// User overrides for variable metadata (colors, positional flag)
    var variableOverrides: [String: VariableMetadata] = [:]

    // Table selection state (new multi-column approach)
    var tableTimeVariable: CDFVariable? {
        didSet { loadTableData() }
    }
    var tableSelectedComponents: Set<String> = [] {  // "varName" or "varName.X"
        didSet {
            // Track newly added components as "loading"
            let added = tableSelectedComponents.subtracting(oldValue)
            if !added.isEmpty {
                loadingComponents.formUnion(added)
            }
            loadTableData()
        }
    }

    // Table data - array-based for fast index access (no per-row object allocation)
    private(set) var tableColumns: [DataColumn] = []
    private(set) var isLoadingData = false
    private(set) var dataError: CDFError?

    /// Components currently being loaded (for showing spinners in sidebar)
    private(set) var loadingComponents: Set<String> = []

    // Full dataset stored as contiguous arrays for O(1) access
    private(set) var allTimestamps: [Date] = []
    private var columnData: [String: [Double]] = [:]

    /// Number of rows available in the table
    var tableRowCount: Int { allTimestamps.count }

    /// Get timestamp for a row index - O(1)
    func timestamp(at index: Int) -> Date? {
        guard index >= 0 && index < allTimestamps.count else { return nil }
        return allTimestamps[index]
    }

    /// Get value for a column at row index - O(1)
    func value(column: String, at index: Int) -> Double? {
        guard let data = columnData[column], index >= 0 && index < data.count else { return nil }
        return data[index]
    }

    // Chart selection
    var chartTimeVariable: CDFVariable?
    var chartYVariables: Set<CDFVariable> = []
    var showChart = false

    // Globe selection
    var globePositionVariable: CDFVariable?
    var showGlobe = false

    // MARK: - Shared Cursor State (synchronized across table, chart, globe)

    /// Current cursor position as row index (nil = not hovering)
    var cursorIndex: Int?

    /// Whether the cursor is paused (locked to current position)
    var isCursorPaused: Bool = false

    /// Whether globe animation is currently playing (set by GlobeView)
    /// When true, chart hover is disabled to prevent accidental animation stops
    var isAnimating: Bool = false

    /// Current cursor as progress (0-1), for globe animation
    var cursorProgress: Double {
        get {
            guard let index = cursorIndex, totalRecords > 0 else { return 1.0 }
            return Double(index) / Double(max(1, totalRecords - 1))
        }
        set {
            guard totalRecords > 0 else { return }
            cursorIndex = Int(newValue * Double(totalRecords - 1))
        }
    }

    /// Current cursor as Date, for chart - uses full timestamp array
    var cursorDate: Date? {
        get {
            guard let index = cursorIndex, index < allTimestamps.count else { return nil }
            return allTimestamps[index]
        }
        set {
            guard let date = newValue, !allTimestamps.isEmpty else {
                cursorIndex = nil
                return
            }
            // Binary search for closest timestamp (array is sorted)
            let target = date.timeIntervalSince1970
            var low = 0
            var high = allTimestamps.count - 1

            while low < high {
                let mid = (low + high) / 2
                if allTimestamps[mid].timeIntervalSince1970 < target {
                    low = mid + 1
                } else {
                    high = mid
                }
            }

            // Check if low-1 is closer
            if low > 0 {
                let distLow = abs(allTimestamps[low].timeIntervalSince(date))
                let distPrev = abs(allTimestamps[low - 1].timeIntervalSince(date))
                if distPrev < distLow {
                    low -= 1
                }
            }
            cursorIndex = low
        }
    }

    /// Toggle pause state; if not paused, pause at current position
    func toggleCursorPause() {
        if isCursorPaused {
            isCursorPaused = false
        } else if cursorIndex != nil {
            isCursorPaused = true
        }
    }

    /// Clear cursor when mouse leaves
    func clearCursor() {
        if !isCursorPaused {
            cursorIndex = nil
        }
    }

    // Total rows for table - uses actual loaded data count
    var totalRecords: Int {
        allTimestamps.count
    }

    // MARK: - File Loading

    func loadFile(from url: URL) {
        do {
            cdfFile = try CDFFile(url: url, options: .withUnixTimestamps)
            setupDefaults()
        } catch let error as CDFError {
            dataError = error
        } catch {
            dataError = .corruptedData(error.localizedDescription)
        }
    }

    /// Set up default selections for a loaded file
    func setupDefaults() {
        guard let file = cdfFile else { return }

        // Auto-detect time variable for table and chart
        if let timeVar = file.timestampVariables().first {
            tableTimeVariable = timeVar
            chartTimeVariable = timeVar
        }
        // Auto-select first ECEF position variable's components
        if let ecefVar = file.ecefPositionVariables().first {
            let components = componentNames(for: ecefVar)
            for comp in components {
                tableSelectedComponents.insert("\(ecefVar.name).\(comp)")
            }
        }
    }

    // MARK: - Table Data Loading

    private func loadTableData() {
        guard let file = cdfFile,
              let timeVar = tableTimeVariable else {
            tableColumns = []
            allTimestamps = []
            columnData = [:]
            return
        }

        isLoadingData = true
        dataError = nil

        Task { @MainActor in
            do {
                // Read all timestamps (full dataset for cursor sync)
                let rawTimestamps = try file.readTimestamps(for: timeVar)
                let timestamps = rawTimestamps.map { Date(timeIntervalSince1970: $0) }

                // Build columns list
                var columns: [DataColumn] = [
                    DataColumn(id: "time", name: "Time", key: "time")
                ]

                // Group selected components by variable
                var variableComponents: [String: [String]] = [:]  // varName -> [X, Y, Z]
                var scalarVariables: [String] = []

                for key in tableSelectedComponents {
                    if key.contains(".") {
                        let parts = key.split(separator: ".")
                        let varName = String(parts[0])
                        let component = String(parts[1])
                        variableComponents[varName, default: []].append(component)
                    } else {
                        scalarVariables.append(key)
                    }
                }

                // Add columns for vector components
                for (varName, components) in variableComponents.sorted(by: { $0.key < $1.key }) {
                    let variable = file.variables.first(where: { $0.name == varName })
                    let isInteger = variable?.dataType.isIntegerType ?? false
                    let unitsSuffix = variable?.units.map { " (\($0))" } ?? ""
                    for component in components.sorted() {
                        let key = "\(varName).\(component)"
                        columns.append(DataColumn(id: key, name: "\(varName).\(component)\(unitsSuffix)", key: key, isIntegerType: isInteger))
                    }
                }

                // Add columns for scalar variables
                for varName in scalarVariables.sorted() {
                    let variable = file.variables.first(where: { $0.name == varName })
                    let isInteger = variable?.dataType.isIntegerType ?? false
                    let unitsSuffix = variable?.units.map { " (\($0))" } ?? ""
                    columns.append(DataColumn(id: varName, name: "\(varName)\(unitsSuffix)", key: varName, isIntegerType: isInteger))
                }

                // Read data for each variable/component into contiguous arrays
                var newColumnData: [String: [Double]] = [:]

                // Load vector component data
                for (varName, components) in variableComponents {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)
                    // Use displayColumnsPerRow for 2D arrays like [86400, 3] - this gives 3, not 259200
                    let elementsPerRecord = variable.displayColumnsPerRow
                    let componentNames = self.componentNames(for: variable)

                    for component in components {
                        guard let compIndex = componentNames.firstIndex(of: component) else { continue }
                        let key = "\(varName).\(component)"

                        // Pre-allocate array for performance
                        var componentValues = [Double]()
                        componentValues.reserveCapacity(timestamps.count)

                        for i in 0..<timestamps.count {
                            let valueIndex = i * elementsPerRecord + compIndex
                            if valueIndex < values.count {
                                componentValues.append(values[valueIndex])
                            }
                        }
                        newColumnData[key] = componentValues
                    }
                }

                // Load scalar data
                for varName in scalarVariables {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)
                    newColumnData[varName] = values
                }

                // Store all data - no row object creation needed
                self.tableColumns = columns
                self.allTimestamps = timestamps
                self.columnData = newColumnData

                self.loadingComponents = []
                isLoadingData = false
            } catch let error as CDFError {
                dataError = error
                tableColumns = []
                allTimestamps = []
                columnData = [:]
                loadingComponents = []
                isLoadingData = false
            } catch {
                dataError = .corruptedData(error.localizedDescription)
                tableColumns = []
                allTimestamps = []
                columnData = [:]
                loadingComponents = []
                isLoadingData = false
            }
        }
    }

    /// Get component names for a vector variable
    private func componentNames(for variable: CDFVariable) -> [String] {
        return CDFColumn.componentNames(for: variable)
    }

    // MARK: - Chart Data

    func chartData() throws -> [(time: Date, values: [String: Double])] {
        guard let file = cdfFile,
              let timeVar = chartTimeVariable,
              !chartYVariables.isEmpty else {
            return []
        }

        let timestamps = try file.readTimestamps(for: timeVar)
        var result: [(Date, [String: Double])] = []

        // Read Y variable data
        var yData: [String: [Double]] = [:]
        for yVar in chartYVariables {
            yData[yVar.name] = try file.readDoubles(for: yVar)
        }

        // Combine into time series
        for (index, timestamp) in timestamps.enumerated() {
            let date = Date(timeIntervalSince1970: timestamp)
            var values: [String: Double] = [:]
            for (name, data) in yData {
                if index < data.count {
                    values[name] = data[index]
                }
            }
            result.append((date, values))
        }

        return result
    }

    // MARK: - Globe Data

    func globePositions() throws -> [(x: Double, y: Double, z: Double)] {
        guard let file = cdfFile,
              let posVar = globePositionVariable else {
            return []
        }

        return try file.readECEFPositions(for: posVar)
    }

    // MARK: - Export

    func exportTableAsCSV() throws -> String {
        guard !tableColumns.isEmpty, !allTimestamps.isEmpty else {
            throw CDFError.dataReadFailed(variable: "table", reason: "No data to export")
        }

        var csv = tableColumns.map { $0.name }.joined(separator: ",") + "\n"

        for i in 0..<allTimestamps.count {
            var values: [String] = []
            for column in tableColumns {
                if column.key == "time" {
                    values.append(allTimestamps[i].ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                } else if let val = value(column: column.key, at: i) {
                    values.append(formatValue(val))
                } else {
                    values.append("")
                }
            }
            csv += values.joined(separator: ",") + "\n"
        }

        return csv
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.6e", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    // MARK: - Variable Metadata

    /// Check if a variable should be treated as positional (for Globe)
    /// Returns the override if set, otherwise falls back to heuristic
    func isPositional(_ variable: CDFVariable) -> Bool {
        if let override = variableOverrides[variable.name]?.isPositional {
            return override
        }
        return variable.isECEFPosition
    }

    /// Get color for a variable, respecting user override
    /// Default colors use deterministic random hues at fixed L=65, C=60 for visual consistency
    func colorFor(_ variableName: String, index: Int, palette: [Color]) -> Color {
        if let hex = variableOverrides[variableName]?.customColor,
           let color = Color(hex: hex) {
            return color
        }
        return defaultColor(for: variableName)
    }

    /// Generate a deterministic "random" color for a variable based on its name
    /// Uses fixed L=65 and C=60 with a hue derived from hashing the variable name
    private func defaultColor(for variableName: String) -> Color {
        // Use a simple hash of the variable name to get a deterministic hue
        var hash: UInt64 = 5381
        for char in variableName.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        // Map hash to hue (0-360)
        let hue = Double(hash % 360)
        // Fixed lightness and chroma for good visibility
        return Color.lch(lightness: 65, chroma: 60, hue: hue)
    }

    /// Get metadata for a variable (creates default if not exists)
    func metadata(for variableName: String) -> VariableMetadata {
        variableOverrides[variableName] ?? VariableMetadata()
    }

    /// Update metadata for a variable and save to xattr
    func setMetadata(_ metadata: VariableMetadata, for variableName: String) {
        if metadata.hasOverrides {
            variableOverrides[variableName] = metadata
        } else {
            variableOverrides.removeValue(forKey: variableName)
        }
        saveMetadata()
    }

    /// Load metadata from extended attributes on the original file
    func loadMetadata() {
        guard let url = originalFileURL else { return }

        guard let data = url.extendedAttribute(forName: URL.cdfViewerMetadataAttributeName) else {
            return
        }

        do {
            let fileMetadata = try JSONDecoder().decode(FileMetadata.self, from: data)
            variableOverrides = fileMetadata.variableOverrides
        } catch {
            print("Failed to load metadata: \(error)")
        }
    }

    /// Save metadata to extended attributes on the original file
    func saveMetadata() {
        guard let url = originalFileURL else { return }

        let fileMetadata = FileMetadata(variableOverrides: variableOverrides)

        // If no overrides, remove the attribute
        if fileMetadata.isEmpty {
            try? url.removeExtendedAttribute(forName: URL.cdfViewerMetadataAttributeName)
            return
        }

        do {
            let data = try JSONEncoder().encode(fileMetadata)
            try url.setExtendedAttribute(data, forName: URL.cdfViewerMetadataAttributeName)
        } catch {
            print("Failed to save metadata: \(error)")
        }
    }
}

// MARK: - Table Data Structures

struct DataColumn: Identifiable {
    let id: String
    let name: String
    let key: String
    let isIntegerType: Bool

    init(id: String, name: String, key: String, isIntegerType: Bool = false) {
        self.id = id
        self.name = name
        self.key = key
        self.isIntegerType = isIntegerType
    }
}
