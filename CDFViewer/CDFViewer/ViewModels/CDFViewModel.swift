import Foundation
import SwiftUI

/// Main view model for a CDF document
@Observable
final class CDFViewModel {
    // The loaded CDF file
    var cdfFile: CDFFile?

    // Selection state
    var selectedVariable: CDFVariable? {
        didSet {
            if let variable = selectedVariable {
                loadVariableData(variable)
            } else {
                currentData = []
            }
        }
    }

    // Data for current selection
    private(set) var currentData: [CDFDataRow] = []
    private(set) var isLoadingData = false
    private(set) var dataError: CDFError?

    // Chart selection
    var chartTimeVariable: CDFVariable?
    var chartYVariables: Set<CDFVariable> = []
    var showChart = false

    // Globe selection
    var globePositionVariable: CDFVariable?
    var showGlobe = false

    // Visible row range for lazy loading
    var visibleRange: Range<Int> = 0..<100 {
        didSet {
            if let variable = selectedVariable {
                loadVisibleData(variable)
            }
        }
    }

    // Total rows for current variable (uses displayRowCount for proper row handling)
    var totalRecords: Int {
        selectedVariable?.displayRowCount ?? 0
    }

    // MARK: - File Loading

    func loadFile(from url: URL) {
        do {
            cdfFile = try CDFFile(url: url)
            // Auto-select first variable
            if let first = cdfFile?.variables.first {
                selectedVariable = first
            }
            // Auto-detect chart time variable
            chartTimeVariable = cdfFile?.timestampVariables().first
        } catch let error as CDFError {
            dataError = error
        } catch {
            dataError = .corruptedData(error.localizedDescription)
        }
    }

    // MARK: - Data Loading

    private func loadVariableData(_ variable: CDFVariable) {
        guard let file = cdfFile else { return }

        isLoadingData = true
        dataError = nil

        Task { @MainActor in
            do {
                // Load initial visible range (use displayRowCount for proper row counting)
                let range = 0..<min(1000, variable.displayRowCount)
                currentData = try file.readDataRows(for: variable, range: range)
                isLoadingData = false
            } catch let error as CDFError {
                dataError = error
                isLoadingData = false
            } catch {
                dataError = .dataReadFailed(variable: variable.name, reason: error.localizedDescription)
                isLoadingData = false
            }
        }
    }

    private func loadVisibleData(_ variable: CDFVariable) {
        guard let file = cdfFile else { return }

        // Extend range slightly for smooth scrolling
        let bufferSize = 50
        let extendedStart = max(0, visibleRange.lowerBound - bufferSize)
        let extendedEnd = min(variable.displayRowCount, visibleRange.upperBound + bufferSize)

        Task { @MainActor in
            do {
                let rows = try file.readDataRows(for: variable, range: extendedStart..<extendedEnd)
                // Merge with existing data if needed
                currentData = rows
            } catch {
                // Ignore errors for lazy loading - keep existing data
            }
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

    func exportDataAsCSV(variable: CDFVariable) throws -> String {
        guard let file = cdfFile else {
            throw CDFError.dataReadFailed(variable: variable.name, reason: "No file loaded")
        }

        let rows = try file.readDataRows(for: variable)
        let columns = CDFColumn.columnsForVariable(variable)

        var csv = "Record," + columns.map { $0.name }.joined(separator: ",") + "\n"

        for row in rows {
            let values = row.values.map { $0.stringValue }
            csv += "\(row.id)," + values.joined(separator: ",") + "\n"
        }

        return csv
    }
}
