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

    // Hover state
    @State private var hoverIndex: Int?
    @State private var isPaused = false
    @State private var pausedIndex: Int?

    // Computed active index (paused or hovered)
    private var activeIndex: Int? {
        isPaused ? pausedIndex : hoverIndex
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
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
        VStack(alignment: .leading, spacing: 0) {
            // Time Variables section
            Text("Time Variable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            if let file = viewModel.cdfFile {
                let timeVars = file.timestampVariables()
                ForEach(timeVars) { variable in
                    timeVariableRow(variable)
                }

                if timeVars.isEmpty {
                    Text("No time variables found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }

            // Divider
            Divider()
                .padding(.vertical, 8)

            // Data Variables section
            Text("Data Variables")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let file = viewModel.cdfFile {
                        let numericVars = file.numericVariables()
                        ForEach(numericVars) { variable in
                            dataVariableRow(variable)
                        }

                        if numericVars.isEmpty {
                            Text("No numeric variables found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func timeVariableRow(_ variable: CDFVariable) -> some View {
        HStack {
            Image(systemName: selectedTimeVariable == variable ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selectedTimeVariable == variable ? .blue : .secondary)
                .font(.system(size: 12))

            Text(variable.name)
                .font(.system(size: 13))

            Spacer()

            // Show current timestamp on hover (only for selected time variable)
            if selectedTimeVariable == variable,
               let index = activeIndex,
               let firstSeries = chartSeries.first,
               index < firstSeries.points.count {
                HStack(spacing: 4) {
                    Text(firstSeries.points[index].date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTimeVariable = variable
        }
    }

    private func dataVariableRow(_ variable: CDFVariable) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main variable row
            HStack {
                // Checkbox for parent variable
                let isAnySelected = isVariableOrComponentSelected(variable)
                Image(systemName: isAnySelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isAnySelected ? .blue : .secondary)
                    .font(.system(size: 12))

                Text(variable.name)
                    .font(.system(size: 13))

                Spacer()

                // Show value on hover
                if let value = getCurrentValue(for: variable.name) {
                    Text(formatValue(value))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleVariable(variable)
            }

            // Component sub-items for vectors
            if variable.isVector {
                let components = componentNames(for: variable)
                ForEach(components, id: \.self) { component in
                    componentRow(variable: variable, component: component)
                }
            }
        }
    }

    private func componentRow(variable: CDFVariable, component: String) -> some View {
        let key = "\(variable.name).\(component)"
        let isSelected = selectedComponents.contains(key)

        return HStack {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.system(size: 11))

            Text(component)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            // Show value on hover
            if let value = getCurrentValue(for: key) {
                Text(formatValue(value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 32)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleComponent(key)
        }
    }

    private func componentNames(for variable: CDFVariable) -> [String] {
        let count = variable.totalElements
        if count == 3 {
            return ["X", "Y", "Z"]
        } else if count == 2 {
            return ["X", "Y"]
        } else {
            return (0..<min(count, 10)).map { "[\($0)]" }
        }
    }

    // MARK: - Selection Logic

    private func isVariableOrComponentSelected(_ variable: CDFVariable) -> Bool {
        if variable.isVector {
            let components = componentNames(for: variable)
            return components.contains { selectedComponents.contains("\(variable.name).\($0)") }
        } else {
            return selectedComponents.contains(variable.name)
        }
    }

    private func toggleVariable(_ variable: CDFVariable) {
        if variable.isVector {
            let components = componentNames(for: variable)
            let keys = components.map { "\(variable.name).\($0)" }
            let allSelected = keys.allSatisfy { selectedComponents.contains($0) }

            if allSelected {
                // Deselect all
                for key in keys {
                    selectedComponents.remove(key)
                }
            } else {
                // Select all
                for key in keys {
                    selectedComponents.insert(key)
                }
            }
        } else {
            if selectedComponents.contains(variable.name) {
                selectedComponents.remove(variable.name)
            } else {
                selectedComponents.insert(variable.name)
            }
        }
    }

    private func toggleComponent(_ key: String) {
        if selectedComponents.contains(key) {
            selectedComponents.remove(key)
        } else {
            selectedComponents.insert(key)
        }
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
            ForEach(chartSeries) { series in
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(series.name, point.value)
                    )
                    .foregroundStyle(by: .value("Variable", series.name))
                }
            }

            // Vertical cursor line
            if let index = activeIndex, let firstSeries = chartSeries.first, index < firstSeries.points.count {
                RuleMark(x: .value("Cursor", firstSeries.points[index].date))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
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
                        guard !isPaused else { return }
                        switch phase {
                        case .active(let location):
                            updateHoverIndex(at: location, proxy: proxy)
                        case .ended:
                            hoverIndex = nil
                        }
                    }
                    .onTapGesture {
                        if isPaused {
                            isPaused = false
                            pausedIndex = nil
                        } else if hoverIndex != nil {
                            isPaused = true
                            pausedIndex = hoverIndex
                        }
                    }
            }
        }
    }

    private func updateHoverIndex(at location: CGPoint, proxy: ChartProxy) {
        guard let firstSeries = chartSeries.first, !firstSeries.points.isEmpty else { return }

        if let date: Date = proxy.value(atX: location.x) {
            // Find closest point index
            var closestIndex = 0
            var closestDistance = Double.infinity

            for (index, point) in firstSeries.points.enumerated() {
                let distance = abs(point.date.timeIntervalSince(date))
                if distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }

            hoverIndex = closestIndex
        }
    }

    // MARK: - Value Display

    private func getCurrentValue(for key: String) -> Double? {
        guard let index = activeIndex else { return nil }

        for series in chartSeries {
            if series.name == key && index < series.points.count {
                return series.points[index].value
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
        hoverIndex = nil
        isPaused = false
        pausedIndex = nil

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
                    let elementsPerRecord = variable.totalElements
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

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.2e", value)
        } else {
            return String(format: "%.2f", value)
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
