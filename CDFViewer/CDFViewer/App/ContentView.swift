import SwiftUI

struct ContentView: View {
    @Binding var document: CDFDocument
    @State private var viewModel = CDFViewModel()
    @State private var documentID = UUID()
    @State private var showFileInfo = false
    @Environment(ViewModelRegistry.self) private var registry
    @Environment(\.openWindow) private var openWindow

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
                // Register viewModel for auxiliary windows
                registry.register(viewModel, for: documentID)
            }
        }
        .onDisappear {
            registry.unregister(documentID)
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

                // Chart button - opens separate window
                Button {
                    openWindow(id: "Time Series Chart", value: documentID)
                } label: {
                    Label("Chart", systemImage: "chart.xyaxis.line")
                }
                .disabled(viewModel.chartTimeVariable == nil)

                // Globe button - opens separate window
                Button {
                    openWindow(id: "3D Globe", value: documentID)
                } label: {
                    Label("Globe", systemImage: "globe")
                }
                .disabled(document.cdfFile?.ecefPositionVariables().isEmpty ?? true)
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
