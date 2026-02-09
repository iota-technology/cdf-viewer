import SwiftUI
import Charts

struct TimeSeriesChartView: View {
    @Bindable var viewModel: CDFViewModel

    @State private var selectedTimeVariable: CDFVariable?
    @State private var selectedYVariables: Set<CDFVariable> = []
    @State private var chartData: [ChartDataPoint] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDate: Date?
    @State private var hoveredPoint: ChartDataPoint?

    var body: some View {
        HSplitView {
                // Variable selection sidebar
                VStack(alignment: .leading, spacing: 16) {
                    // Time variable selector
                    GroupBox("Time Variable (X-Axis)") {
                        if let file = viewModel.cdfFile {
                            Picker("Time", selection: $selectedTimeVariable) {
                                Text("Select...").tag(nil as CDFVariable?)
                                ForEach(file.timestampVariables()) { variable in
                                    Text(variable.name).tag(variable as CDFVariable?)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // Y variable selector
                    GroupBox("Data Variables (Y-Axis)") {
                        if let file = viewModel.cdfFile {
                            let numericVars = file.numericVariables()
                            if numericVars.isEmpty {
                                Text("No numeric variables")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(numericVars) { variable in
                                            Toggle(isOn: Binding(
                                                get: { selectedYVariables.contains(variable) },
                                                set: { isSelected in
                                                    if isSelected {
                                                        selectedYVariables.insert(variable)
                                                    } else {
                                                        selectedYVariables.remove(variable)
                                                    }
                                                }
                                            )) {
                                                VStack(alignment: .leading) {
                                                    Text(variable.name)
                                                    Text(variable.typeString)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .toggleStyle(.checkbox)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .frame(minHeight: 150, maxHeight: 300)
                            }
                        }
                    }

                    // Load button
                    Button(action: loadChartData) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Load Chart", systemImage: "chart.xyaxis.line")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTimeVariable == nil || selectedYVariables.isEmpty || isLoading)

                    Spacer()
                }
                .padding()
                .frame(width: 250)

                // Chart area
                VStack {
                    if let error = errorMessage {
                        ContentUnavailableView(
                            "Error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else if chartData.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Select variables and click Load Chart")
                        )
                    } else {
                        // The chart
                        chartView
                            .padding()

                        // Legend
                        legendView
                            .padding(.horizontal)
                            .padding(.bottom)
                    }
                }
            }
        .onAppear {
            selectedTimeVariable = viewModel.chartTimeVariable
        }
    }

    // MARK: - Chart View

    @ViewBuilder
    private var chartView: some View {
        Chart(chartData) { point in
            ForEach(point.values.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(name, value)
                )
                .foregroundStyle(by: .value("Variable", name))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
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
        .chartLegend(.hidden) // We show custom legend
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let date: Date = proxy.value(atX: location.x) {
                                hoveredPoint = chartData.min(by: {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                })
                            }
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
            }
        }

        // Hover tooltip
        if let point = hoveredPoint {
            HStack(spacing: 16) {
                Text(point.date, style: .time)
                    .foregroundStyle(.secondary)

                ForEach(point.values.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                    Text("\(name): \(formatValue(value))")
                        .font(.caption)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Legend

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(selectedYVariables), id: \.id) { variable in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForVariable(variable))
                            .frame(width: 8, height: 8)
                        Text(variable.name)
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadChartData() {
        guard let file = viewModel.cdfFile,
              let timeVar = selectedTimeVariable,
              !selectedYVariables.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        chartData = []

        Task { @MainActor in
            do {
                // Read timestamps
                let timestamps = try file.readTimestamps(for: timeVar)

                // Read Y data
                var yData: [String: [Double]] = [:]
                for yVar in selectedYVariables {
                    // For multi-dimensional variables, flatten or take first component
                    let values = try file.readDoubles(for: yVar)

                    if yVar.isVector {
                        // For vectors, plot magnitude or individual components
                        let elementsPerRecord = yVar.totalElements
                        var magnitudes: [Double] = []
                        for i in stride(from: 0, to: values.count, by: elementsPerRecord) {
                            let end = min(i + elementsPerRecord, values.count)
                            let components = Array(values[i..<end])
                            let magnitude = sqrt(components.reduce(0) { $0 + $1 * $1 })
                            magnitudes.append(magnitude)
                        }
                        yData["\(yVar.name) (mag)"] = magnitudes
                    } else {
                        yData[yVar.name] = values
                    }
                }

                // Combine into chart data points
                // Subsample if too many points
                let maxPoints = 5000
                let step = max(1, timestamps.count / maxPoints)

                var points: [ChartDataPoint] = []
                for i in stride(from: 0, to: timestamps.count, by: step) {
                    let date = Date(timeIntervalSince1970: timestamps[i])
                    var values: [String: Double] = [:]
                    for (name, data) in yData {
                        if i < data.count {
                            values[name] = data[i]
                        }
                    }
                    if !values.isEmpty {
                        points.append(ChartDataPoint(date: date, values: values))
                    }
                }

                chartData = points
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func colorForVariable(_ variable: CDFVariable) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .cyan, .pink, .yellow]
        let index = Array(selectedYVariables).firstIndex(of: variable) ?? 0
        return colors[index % colors.count]
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.3e", value)
        } else {
            return String(format: "%.3f", value)
        }
    }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let values: [String: Double]
}

// MARK: - ViewModel Extension

extension CDFViewModel {
    @Observable
    final class ChartViewModel {
        var timeVariable: CDFVariable?
        var yVariables: Set<CDFVariable> = []
    }
}

#Preview {
    TimeSeriesChartView(viewModel: CDFViewModel())
        .frame(width: 800, height: 600)
}
