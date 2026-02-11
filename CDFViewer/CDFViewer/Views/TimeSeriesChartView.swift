import SwiftUI

struct TimeSeriesChartView: View {
    @Bindable var viewModel: CDFViewModel

    // Selection state
    @State private var selectedTimeVariable: CDFVariable?
    @State private var selectedComponents: Set<String> = [] // "varName" or "varName.X"

    // Static formatter for time with milliseconds (expensive to create, reuse)
    private static let timeWithMillisFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // Sidebar visibility (Photos-style toggle)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Chart data - full resolution for Canvas rendering
    @State private var chartSeries: [CanvasChartSeries] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Zoom/pan state
    @State private var visibleDateRange: ClosedRange<Date>?  // nil = show all data
    @State private var fullDateRange: ClosedRange<Date>?     // Full extent of data

    // Use shared cursor from viewModel
    private var activeDate: Date? {
        viewModel.cursorDate
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationSidebarContainer {
                sidebarView
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 400)
        } detail: {
            // Chart area
            chartAreaView
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sidebarToggleToolbar()
        .toolbar(removing: .sidebarToggle)
        .onAppear {
            setupInitialSelection()
        }
        .onChange(of: selectedTimeVariable) { _, _ in
            loadChartData()
        }
        .onChange(of: selectedComponents) { _, _ in
            loadChartData()
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VariableSidebarView(
            singleSelection: $selectedTimeVariable,
            multiSelection: $selectedComponents,
            sections: sidebarSections,
            showDataTypeInfo: true,
            isDisabled: isVariableDisabled,
            disabledReason: disabledReason,
            colorForKey: seriesColor,
            valueForKey: getCurrentValue,
            viewModel: viewModel,
            showPositionalToggle: false,
            singleSelectionTrailing: { variable in
                // Show timestamp for selected time variable when hovering
                if selectedTimeVariable == variable, let date = activeDate {
                    HStack(alignment: .top, spacing: 4) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(date, format: .dateTime.year().month().day())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(Self.timeWithMillisFormatter.string(from: date))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if viewModel.isCursorPaused {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        )
    }

    private var sidebarSections: [VariableSectionConfig] {
        guard let file = viewModel.cdfFile else { return [] }
        return [
            VariableSectionConfig(
                title: "Time Variable",
                variables: file.timestampVariables(),
                selectionMode: .single
            ),
            VariableSectionConfig(
                title: "Data Variables",
                variables: file.numericVariables(),
                selectionMode: .multi
            )
        ]
    }

    // MARK: - Chart Area

    private var chartAreaView: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if isLoading {
                ProgressView("Loading chart data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chartSeries.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Select a time variable and data variables to display")
                )
            } else {
                chartView
                    .padding()
            }
        }
    }

    /// Whether the chart is currently zoomed (not showing full range)
    private var isZoomed: Bool {
        visibleDateRange != nil
    }

    /// The unit of currently selected variables (nil if none selected or mixed units)
    private var selectedUnit: String? {
        guard let file = viewModel.cdfFile else { return nil }

        var units: Set<String> = []
        for key in selectedComponents {
            // Extract variable name (strip component suffix if present)
            let varName = key.contains(".") ? String(key.split(separator: ".")[0]) : key
            if let variable = file.variables.first(where: { $0.name == varName }),
               let unit = variable.units {
                units.insert(unit)
            }
        }

        // Return the unit if all selected variables have the same unit
        guard units.count == 1, let unit = units.first else { return nil }
        return unit
    }

    /// Common units for the Y-axis label (if all selected variables have the same units)
    private var yAxisUnits: String? {
        guard let unit = selectedUnit else { return nil }
        return UnitNames.displayName(for: unit)
    }

    // MARK: - Variable Association Helpers

    /// Get the DEPEND_0 attribute (primary time dependency) for a variable
    private func timeVariableName(for variable: CDFVariable) -> String? {
        variable.attributes["DEPEND_0"]
    }

    /// Check if a time variable is associated with any of the selected data variables
    private func isTimeVariableAssociatedWithSelection(_ timeVar: CDFVariable) -> Bool {
        guard let file = viewModel.cdfFile else { return false }

        // Check if any selected data variable depends on this time variable
        for key in selectedComponents {
            let varName = key.contains(".") ? String(key.split(separator: ".")[0]) : key
            if let dataVar = file.variables.first(where: { $0.name == varName }) {
                // If DEPEND_0 is not set, treat as compatible with any time variable
                guard let dependsOn = timeVariableName(for: dataVar) else { return true }
                if dependsOn == timeVar.name {
                    return true
                }
            }
        }
        return false
    }

    /// Check if a data variable is associated with the selected time variable
    private func isDataVariableAssociatedWithSelectedTime(_ dataVar: CDFVariable) -> Bool {
        guard let selectedTime = selectedTimeVariable else { return true }  // No time selected = all enabled
        // If DEPEND_0 is not set, treat as compatible with any time variable
        guard let dependsOn = timeVariableName(for: dataVar) else { return true }
        return dependsOn == selectedTime.name
    }

    /// Check if a variable is disabled (association check takes priority over unit check)
    private func isVariableDisabled(_ variable: CDFVariable) -> Bool {
        // Time variable section
        if variable.isTimestamp {
            // If no data variables selected, all time variables are enabled
            guard !selectedComponents.isEmpty else { return false }
            // Only enable time variables associated with selected data variables
            return !isTimeVariableAssociatedWithSelection(variable)
        }

        // Data variable section
        // First check: association with selected time variable (takes priority)
        if !isDataVariableAssociatedWithSelectedTime(variable) {
            return true
        }

        // Second check: unit constraints (only if association check passes)
        guard !selectedComponents.isEmpty else { return false }

        // If we have a selected unit, disable variables with different units
        if let requiredUnit = selectedUnit {
            let varUnit = variable.units ?? ""
            return varUnit != requiredUnit
        }

        // If selected variables have no units, disable variables that DO have units
        if let file = viewModel.cdfFile {
            let selectedHaveNoUnits = selectedComponents.allSatisfy { key in
                let varName = key.contains(".") ? String(key.split(separator: ".")[0]) : key
                if let v = file.variables.first(where: { $0.name == varName }) {
                    return v.units == nil || v.units?.isEmpty == true
                }
                return true
            }
            if selectedHaveNoUnits {
                return variable.units != nil && !variable.units!.isEmpty
            }
        }

        return false
    }

    /// Get the reason why a variable is disabled
    private func disabledReason(for variable: CDFVariable) -> String? {
        guard isVariableDisabled(variable) else { return nil }

        // Time variable disabled reasons
        if variable.isTimestamp {
            return "This time variable is not associated with the selected data variables."
        }

        // Data variable disabled reasons - check association first (takes priority)
        if !isDataVariableAssociatedWithSelectedTime(variable) {
            if let selectedTime = selectedTimeVariable {
                return "This variable is not associated with \(selectedTime.name). Select a different time variable to chart this."
            }
        }

        // Unit mismatch reasons
        if let requiredUnit = selectedUnit {
            let displayUnit = UnitNames.displayName(for: requiredUnit)
            return "This variable is not in \(displayUnit). Deselect other variables first to chart this one."
        }

        return "This variable has different units than selected variables. Deselect other variables first to chart this one."
    }

    @ViewBuilder
    private var chartView: some View {
        ZStack(alignment: .topTrailing) {
            CanvasLineChart(
                series: chartSeries,
                visibleXRange: visibleDateRange,
                fullXRange: fullDateRange,
                cursorDate: activeDate,
                isCursorPaused: viewModel.isCursorPaused,
                isAnimating: viewModel.isAnimating,
                colorForSeries: colorForSeries,
                yAxisLabel: yAxisUnits,
                onZoom: { scale in applyZoom(scale: scale) },
                onPan: { delta in applyPan(pixelDelta: delta) },
                onHover: { date in
                    guard !viewModel.isCursorPaused else { return }
                    if let date = date {
                        viewModel.cursorDate = date
                    } else {
                        viewModel.clearCursor()
                    }
                },
                onTap: { clickedDate in
                    // If animation is playing, stop it and jump to clicked position
                    if viewModel.isAnimating {
                        viewModel.isAnimating = false
                        if let date = clickedDate {
                            viewModel.cursorDate = date
                        }
                        viewModel.isCursorPaused = true
                    } else {
                        viewModel.toggleCursorPause()
                    }
                }
            )

            // Reset button (shown when zoomed)
            if isZoomed {
                Button(action: resetZoom) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .padding(8)
            }
        }
    }

    // MARK: - Zoom/Pan

    /// Apply zoom centered on chart midpoint
    private func applyZoom(scale: CGFloat) {
        guard let fullRange = fullDateRange else { return }

        let currentRange = visibleDateRange ?? fullRange
        let currentDuration = currentRange.upperBound.timeIntervalSince(currentRange.lowerBound)
        let midpoint = currentRange.lowerBound.addingTimeInterval(currentDuration / 2)

        // Calculate new duration (zoom in = scale > 1 = shorter duration)
        let newDuration = currentDuration / Double(scale)

        // Clamp to reasonable bounds (min 0.5 seconds for ~1cm/point at max zoom, max full range)
        let fullDuration = fullRange.upperBound.timeIntervalSince(fullRange.lowerBound)
        let clampedDuration = min(max(newDuration, 0.5), fullDuration)

        // If zoomed out to full range or beyond, reset
        if clampedDuration >= fullDuration * 0.99 {
            visibleDateRange = nil
            return
        }

        // Calculate new range centered on midpoint
        let halfDuration = clampedDuration / 2
        var newStart = midpoint.addingTimeInterval(-halfDuration)
        var newEnd = midpoint.addingTimeInterval(halfDuration)

        // Clamp to full range bounds
        if newStart < fullRange.lowerBound {
            newStart = fullRange.lowerBound
            newEnd = newStart.addingTimeInterval(clampedDuration)
        }
        if newEnd > fullRange.upperBound {
            newEnd = fullRange.upperBound
            newStart = newEnd.addingTimeInterval(-clampedDuration)
        }

        visibleDateRange = newStart...newEnd
    }

    /// Apply pan (horizontal scroll) - delta is in pixels
    private func applyPan(pixelDelta: CGFloat) {
        guard let fullRange = fullDateRange else { return }

        let currentRange = visibleDateRange ?? fullRange
        let currentDuration = currentRange.upperBound.timeIntervalSince(currentRange.lowerBound)
        let fullDuration = fullRange.upperBound.timeIntervalSince(fullRange.lowerBound)

        // Don't pan if at full view
        guard currentDuration < fullDuration * 0.99 else { return }

        // Convert pixel delta to time offset (assume ~800px chart width as baseline)
        // Natural scrolling: swipe right (positive delta) = reveal earlier content = negative time offset
        let timePerPixel = currentDuration / 800.0  // Approximate chart width
        let timeOffset = -Double(pixelDelta) * timePerPixel

        var newStart = currentRange.lowerBound.addingTimeInterval(timeOffset)
        var newEnd = currentRange.upperBound.addingTimeInterval(timeOffset)

        // Clamp to full range bounds
        if newStart < fullRange.lowerBound {
            newStart = fullRange.lowerBound
            newEnd = newStart.addingTimeInterval(currentDuration)
        }
        if newEnd > fullRange.upperBound {
            newEnd = fullRange.upperBound
            newStart = newEnd.addingTimeInterval(-currentDuration)
        }

        visibleDateRange = newStart...newEnd
    }

    /// Reset zoom to show full data range
    private func resetZoom() {
        visibleDateRange = nil
    }

    // MARK: - Value Display

    private func getCurrentValue(for key: String) -> Double? {
        // Only show values for selected components
        guard selectedComponents.contains(key) else { return nil }
        // Find the series with this name
        guard let series = chartSeries.first(where: { $0.name == key }),
              let cursorDate = viewModel.cursorDate else { return nil }
        let cursorTimestamp = cursorDate.timeIntervalSince1970
        // Find the closest point to the cursor date using binary search for efficiency
        guard let closest = series.points.min(by: {
            abs($0.timestamp - cursorTimestamp) < abs($1.timestamp - cursorTimestamp)
        }) else { return nil }
        return closest.value
    }

    // MARK: - Data Loading

    private func setupInitialSelection() {
        selectedTimeVariable = viewModel.chartTimeVariable

        // Auto-select first ECEF position variable's components
        if let file = viewModel.cdfFile {
            if let ecefVar = file.ecefPositionVariables().first {
                let components = componentNames(for: ecefVar)
                for comp in components {
                    selectedComponents.insert("\(ecefVar.name).\(comp)")
                }
            }
        }
    }

    private func loadChartData() {
        guard let file = viewModel.cdfFile,
              let timeVar = selectedTimeVariable,
              !selectedComponents.isEmpty else {
            chartSeries = []
            fullDateRange = nil
            visibleDateRange = nil
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                // Read timestamps
                let timestamps = try file.readTimestamps(for: timeVar)

                var series: [CanvasChartSeries] = []

                // Group selected components by variable
                var variableComponents: [String: [String]] = [:] // varName -> [X, Y, Z]
                var scalarVariables: [String] = []

                for key in selectedComponents {
                    if key.contains(".") {
                        let parts = key.split(separator: ".")
                        let varName = String(parts[0])
                        let component = String(parts[1])
                        variableComponents[varName, default: []].append(component)
                    } else {
                        scalarVariables.append(key)
                    }
                }

                // Load vector component data - full resolution
                for (varName, components) in variableComponents {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)
                    let elementsPerRecord = variable.displayColumnsPerRow
                    let componentNames = self.componentNames(for: variable)

                    for component in components {
                        guard let compIndex = componentNames.firstIndex(of: component) else { continue }

                        // Extract component values at full resolution
                        var points: [CanvasChartPoint] = []
                        points.reserveCapacity(timestamps.count)
                        for i in 0..<timestamps.count {
                            let valueIndex = i * elementsPerRecord + compIndex
                            if valueIndex < values.count {
                                points.append(CanvasChartPoint(timestamp: timestamps[i], value: values[valueIndex]))
                            }
                        }

                        let seriesName = "\(varName).\(component)"
                        series.append(CanvasChartSeries(name: seriesName, points: points))
                    }
                }

                // Load scalar data - full resolution
                for varName in scalarVariables {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)

                    var points: [CanvasChartPoint] = []
                    let count = min(timestamps.count, values.count)
                    points.reserveCapacity(count)
                    for i in 0..<count {
                        points.append(CanvasChartPoint(timestamp: timestamps[i], value: values[i]))
                    }

                    series.append(CanvasChartSeries(name: varName, points: points))
                }

                chartSeries = series
                isLoading = false

                // Calculate full date range from timestamps
                if let minTime = timestamps.min(), let maxTime = timestamps.max() {
                    fullDateRange = Date(timeIntervalSince1970: minTime)...Date(timeIntervalSince1970: maxTime)
                }
                // Reset zoom when data changes
                visibleDateRange = nil
            } catch {
                errorMessage = error.localizedDescription
                chartSeries = []
                fullDateRange = nil
                visibleDateRange = nil
                isLoading = false
            }
        }
    }

    /// Get the color for a series by name, respecting custom colors and vector component hue shifts
    /// Only returns a color if the variable/component is selected
    private func seriesColor(for name: String) -> Color? {
        // Only show color indicator if this item is selected
        let isSelected = selectedComponents.contains(name) ||
                         selectedComponents.contains(where: { $0.hasPrefix(name + ".") })
        guard isSelected else { return nil }

        // Try exact match first (for scalar variables or component keys)
        if let index = chartSeries.firstIndex(where: { $0.name == name }) {
            return colorForSeries(name: name, index: index)
        }
        // For base variable names (e.g., "VarName" when chartSeries has "VarName.X"),
        // return the base color from the ViewModel
        return viewModel.colorFor(name, index: 0, palette: chartColorPalette)
    }

    /// Get color for a series, handling both scalar variables and vector components
    private func colorForSeries(name: String, index: Int) -> Color {
        // Check if this is a vector component (e.g., "VarName.X", "VarName.Y", "VarName.Z")
        if name.contains(".") {
            let parts = name.split(separator: ".")
            let varName = String(parts[0])
            let component = String(parts[1])

            // Find the index of the FIRST component of this variable for consistent base color
            // All components (X, Y, Z) should share the same base color
            let firstComponentIndex = chartSeries.firstIndex(where: { $0.name.hasPrefix(varName + ".") }) ?? index
            let baseColor = viewModel.colorFor(varName, index: firstComponentIndex, palette: chartColorPalette)

            // Use adaptive LCH algorithm for component colors
            let componentColors = VariableMetadata.componentColors(for: baseColor)
            switch component {
            case "X": return componentColors.x
            case "Y": return componentColors.y
            case "Z": return componentColors.z
            default: return baseColor
            }
        } else {
            // Scalar variable - use custom color or palette
            return viewModel.colorFor(name, index: index, palette: chartColorPalette)
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
}

#Preview {
    TimeSeriesChartView(viewModel: CDFViewModel())
        .frame(width: 900, height: 600)
}
