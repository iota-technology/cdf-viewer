import SwiftUI

struct ContentView: View {
    @Binding var document: CDFDocument
    @State private var viewModel = CDFViewModel()
    @State private var showFileInfo = false
    @State private var showChart = false
    @State private var showGlobe = false

    var body: some View {
        NavigationSplitView {
            // Sidebar with variable list
            VariableListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            // Main content area
            if let error = document.loadError {
                ErrorView(error: error)
            } else if let selectedVar = viewModel.selectedVariable {
                DataTableView(viewModel: viewModel, variable: selectedVar)
            } else {
                ContentUnavailableView(
                    "Select a Variable",
                    systemImage: "sidebar.left",
                    description: Text("Choose a variable from the sidebar to view its data")
                )
            }
        }
        .onAppear {
            if let file = document.cdfFile {
                viewModel.cdfFile = file
                // Auto-select first variable
                if let first = file.variables.first {
                    viewModel.selectedVariable = first
                }
                // Auto-detect time variable
                viewModel.chartTimeVariable = file.timestampVariables().first
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // File info button
                Button {
                    showFileInfo.toggle()
                } label: {
                    Label("File Info", systemImage: "info.circle")
                }
                .popover(isPresented: $showFileInfo) {
                    if let file = document.cdfFile {
                        FileInfoView(fileInfo: file.fileInfo, attributes: file.attributes)
                            .frame(width: 400, height: 500)
                    }
                }

                Divider()

                // Chart button
                Button {
                    showChart.toggle()
                } label: {
                    Label("Chart", systemImage: "chart.xyaxis.line")
                }
                .disabled(viewModel.chartTimeVariable == nil)
                .sheet(isPresented: $showChart) {
                    TimeSeriesChartView(viewModel: viewModel)
                        .frame(minWidth: 800, minHeight: 600)
                }

                // Globe button
                Button {
                    showGlobe.toggle()
                } label: {
                    Label("Globe", systemImage: "globe")
                }
                .disabled(document.cdfFile?.ecefPositionVariables().isEmpty ?? true)
                .sheet(isPresented: $showGlobe) {
                    GlobeView(viewModel: viewModel)
                        .frame(minWidth: 800, minHeight: 600)
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                // Export button
                if let variable = viewModel.selectedVariable {
                    Button {
                        exportVariable(variable)
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(document.cdfFile?.fileName ?? "CDF Viewer")
    }

    private func exportVariable(_ variable: CDFVariable) {
        do {
            let csv = try viewModel.exportDataAsCSV(variable: variable)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "\(variable.name).csv"

            if panel.runModal() == .OK, let url = panel.url {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Error Loading CDF File")
                .font(.title2)
                .fontWeight(.semibold)

            if let cdfError = error as? CDFError {
                Text(cdfError.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let recovery = cdfError.recoverySuggestion {
                    Text(recovery)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            } else {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(document: .constant(CDFDocument()))
}
