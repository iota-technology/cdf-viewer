import Foundation
import SwiftUI

/// Main view model for a CDF document
@Observable
final class CDFViewModel {
    // The loaded CDF file
    var cdfFile: CDFFile?

    // Table selection state (new multi-column approach)
    var tableTimeVariable: CDFVariable? {
        didSet { loadTableData() }
    }
    var tableSelectedComponents: Set<String> = [] {  // "varName" or "varName.X"
        didSet { loadTableData() }
    }

    // Table data
    private(set) var tableColumns: [DataColumn] = []
    private(set) var tableRows: [DataRow] = []
    private(set) var isLoadingData = false
    private(set) var dataError: CDFError?

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

    /// Current cursor as Date, for chart
    var cursorDate: Date? {
        get {
            guard let index = cursorIndex, index < tableRows.count else { return nil }
            return tableRows[index].timestamp
        }
        set {
            guard let date = newValue, !tableRows.isEmpty else {
                cursorIndex = nil
                return
            }
            // Find closest row to the date
            var closestIndex = 0
            var closestDistance = Double.infinity
            for (i, row) in tableRows.enumerated() {
                let distance = abs(row.timestamp.timeIntervalSince(date))
                if distance < closestDistance {
                    closestDistance = distance
                    closestIndex = i
                }
            }
            cursorIndex = closestIndex
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

    // Total rows for table
    var totalRecords: Int {
        tableTimeVariable?.displayRowCount ?? 0
    }

    // MARK: - File Loading

    func loadFile(from url: URL) {
        do {
            cdfFile = try CDFFile(url: url)
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
            tableRows = []
            return
        }

        isLoadingData = true
        dataError = nil

        Task { @MainActor in
            do {
                // Read timestamps
                let timestamps = try file.readTimestamps(for: timeVar)

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
                    for component in components.sorted() {
                        let key = "\(varName).\(component)"
                        columns.append(DataColumn(id: key, name: "\(varName).\(component)", key: key))
                    }
                }

                // Add columns for scalar variables
                for varName in scalarVariables.sorted() {
                    columns.append(DataColumn(id: varName, name: varName, key: varName))
                }

                // Read data for each variable/component
                var columnData: [String: [Double]] = [:]

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

                        var componentValues: [Double] = []
                        for i in 0..<timestamps.count {
                            let valueIndex = i * elementsPerRecord + compIndex
                            if valueIndex < values.count {
                                componentValues.append(values[valueIndex])
                            }
                        }
                        columnData[key] = componentValues
                    }
                }

                // Load scalar data
                for varName in scalarVariables {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)
                    columnData[varName] = values
                }

                // Build rows (limit to first 10000 for performance)
                let maxRows = min(timestamps.count, 10000)
                var rows: [DataRow] = []

                for i in 0..<maxRows {
                    let date = Date(timeIntervalSince1970: timestamps[i])
                    var values: [String: Double] = [:]

                    for (key, data) in columnData {
                        if i < data.count {
                            values[key] = data[i]
                        }
                    }

                    rows.append(DataRow(id: i, timestamp: date, values: values))
                }

                self.tableColumns = columns
                self.tableRows = rows
                isLoadingData = false
            } catch let error as CDFError {
                dataError = error
                tableColumns = []
                tableRows = []
                isLoadingData = false
            } catch {
                dataError = .corruptedData(error.localizedDescription)
                tableColumns = []
                tableRows = []
                isLoadingData = false
            }
        }
    }

    /// Get component names for a vector variable
    private func componentNames(for variable: CDFVariable) -> [String] {
        // Use displayColumnsPerRow which correctly handles 2D arrays like [86400, 3]
        let count = variable.displayColumnsPerRow
        if count == 3 {
            return ["X", "Y", "Z"]
        } else if count == 2 {
            return ["X", "Y"]
        } else {
            return (0..<min(count, 10)).map { "[\($0)]" }
        }
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
        guard !tableColumns.isEmpty, !tableRows.isEmpty else {
            throw CDFError.dataReadFailed(variable: "table", reason: "No data to export")
        }

        var csv = tableColumns.map { $0.name }.joined(separator: ",") + "\n"

        for row in tableRows {
            var values: [String] = []
            for column in tableColumns {
                if column.key == "time" {
                    values.append(row.timestamp.ISO8601Format())
                } else if let value = row.values[column.key] {
                    values.append(formatValue(value))
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
}

// MARK: - Table Data Structures

struct DataColumn: Identifiable {
    let id: String
    let name: String
    let key: String
}

struct DataRow: Identifiable {
    let id: Int
    let timestamp: Date
    let values: [String: Double]
}
