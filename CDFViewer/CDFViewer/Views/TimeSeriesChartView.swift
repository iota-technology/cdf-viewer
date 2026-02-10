import SwiftUI
import Charts

struct TimeSeriesChartView: View {
    @Bindable var viewModel: CDFViewModel

    // Selection state
    @State private var selectedTimeVariable: CDFVariable?
    @State private var selectedComponents: Set<String> = [] // "varName" or "varName.X"

    // Chart data
    @State private var chartSeries: [ChartSeries] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Use shared cursor from viewModel
    private var activeDate: Date? {
        viewModel.cursorDate
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar using reusable component
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 400)
        } detail: {
            // Chart area
            chartAreaView
        }
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
            colorForKey: seriesColor,
            valueForKey: getCurrentValue,
            singleSelectionTrailing: { variable in
                // Show timestamp for selected time variable when hovering
                if selectedTimeVariable == variable, let date = activeDate {
                    HStack(spacing: 4) {
                        Text(date, format: .dateTime.month().day().hour().minute().second())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var chartView: some View {
        Chart {
            ForEach(Array(chartSeries.enumerated()), id: \.element.id) { index, series in
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(series.name, point.value),
                        series: .value("Series", series.name)
                    )
                    .foregroundStyle(chartColorPalette[index % chartColorPalette.count])
                }
            }

            // Vertical cursor line
            if let date = activeDate {
                RuleMark(x: .value("Cursor", date))
                    .foregroundStyle(viewModel.isCursorPaused ? .orange.opacity(0.7) : .gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: viewModel.isCursorPaused ? 2 : 1, dash: viewModel.isCursorPaused ? [] : [5, 5]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day().hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard !viewModel.isCursorPaused else { return }
                        switch phase {
                        case .active(let location):
                            // Adjust for plot area offset (accounts for y-axis labels)
                            if let plotFrame = proxy.plotFrame {
                                let plotRect = geometry[plotFrame]
                                let adjustedX = location.x - plotRect.origin.x
                                // Only update if within plot area bounds
                                if adjustedX >= 0 && adjustedX <= plotRect.width {
                                    if let date: Date = proxy.value(atX: adjustedX) {
                                        viewModel.cursorDate = date
                                    }
                                }
                            }
                        case .ended:
                            viewModel.clearCursor()
                        }
                    }
                    .onTapGesture {
                        viewModel.toggleCursorPause()
                    }
            }
        }
    }

    // MARK: - Value Display

    private func getCurrentValue(for key: String) -> Double? {
        guard let date = activeDate else { return nil }

        for series in chartSeries {
            if series.name == key, !series.points.isEmpty {
                // Find closest point to the active date
                var closestPoint: ChartPoint?
                var closestDistance = Double.infinity

                for point in series.points {
                    let distance = abs(point.date.timeIntervalSince(date))
                    if distance < closestDistance {
                        closestDistance = distance
                        closestPoint = point
                    }
                }

                return closestPoint?.value
            }
        }
        return nil
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
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                // Read timestamps
                let timestamps = try file.readTimestamps(for: timeVar)

                // Subsample if too many points
                let maxPoints = 5000
                let step = max(1, timestamps.count / maxPoints)

                var series: [ChartSeries] = []

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

                // Load vector component data
                for (varName, components) in variableComponents {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)
                    // Use displayColumnsPerRow for 2D arrays like [86400, 3] - this gives 3, not 259200
                    let elementsPerRecord = variable.displayColumnsPerRow
                    let componentNames = self.componentNames(for: variable)

                    for component in components {
                        guard let compIndex = componentNames.firstIndex(of: component) else { continue }

                        var points: [ChartPoint] = []
                        for i in stride(from: 0, to: timestamps.count, by: step) {
                            let valueIndex = i * elementsPerRecord + compIndex
                            if valueIndex < values.count {
                                let date = Date(timeIntervalSince1970: timestamps[i])
                                points.append(ChartPoint(date: date, value: values[valueIndex]))
                            }
                        }

                        let seriesName = "\(varName).\(component)"
                        series.append(ChartSeries(name: seriesName, points: points))
                    }
                }

                // Load scalar data
                for varName in scalarVariables {
                    guard let variable = file.variables.first(where: { $0.name == varName }) else { continue }
                    let values = try file.readDoubles(for: variable)

                    var points: [ChartPoint] = []
                    for i in stride(from: 0, to: min(timestamps.count, values.count), by: step) {
                        let date = Date(timeIntervalSince1970: timestamps[i])
                        points.append(ChartPoint(date: date, value: values[i]))
                    }

                    series.append(ChartSeries(name: varName, points: points))
                }

                chartSeries = series
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                chartSeries = []
                isLoading = false
            }
        }
    }

    /// Get the color for a series by name (based on its index in chartSeries)
    private func seriesColor(for name: String) -> Color? {
        guard let index = chartSeries.firstIndex(where: { $0.name == name }) else {
            return nil
        }
        return chartColorPalette[index % chartColorPalette.count]
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

// MARK: - Data Models

struct ChartSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [ChartPoint]
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

#Preview {
    TimeSeriesChartView(viewModel: CDFViewModel())
        .frame(width: 900, height: 600)
}
