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
            } else {
                DataTableView(viewModel: viewModel)
            }
        }
        .onAppear {
            if let file = document.cdfFile {
                viewModel.cdfFile = file
                viewModel.setupDefaults()
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

        }
        .navigationTitle(document.cdfFile?.fileName ?? "CDF Viewer")
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
