import SwiftUI

struct DataTableView: View {
    @Bindable var viewModel: CDFViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.dataError {
                ErrorBanner(error: error)
            } else if viewModel.tableColumns.isEmpty {
                ContentUnavailableView(
                    "No Data Selected",
                    systemImage: "tablecells",
                    description: Text("Select a time variable and data variables from the sidebar")
                )
            } else {
                // High-performance NSTableView for smooth scrolling
                DataTableNSView(viewModel: viewModel)

                // Footer with stats
                TableFooterView(
                    totalRecords: viewModel.totalRecords,
                    cursorIndex: viewModel.cursorIndex,
                    isPaused: viewModel.isCursorPaused
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.tableRowCount == 0)
            }
        }
    }

    private func exportCSV() {
        do {
            let csv = try viewModel.exportTableAsCSV()

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.commaSeparatedText]
            savePanel.nameFieldStringValue = "export.csv"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Export failed: \(error)")
        }
    }
}

// MARK: - Table Footer

struct TableFooterView: View {
    let totalRecords: Int
    let cursorIndex: Int?
    let isPaused: Bool

    var body: some View {
        HStack {
            Text("\(totalRecords) rows")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Show current row info when paused
            if isPaused, let index = cursorIndex {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                    Text("Row \(index + 1)")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let error: CDFError

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error.localizedDescription)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.1))

            Spacer()
        }
    }
}

#Preview {
    DataTableView(viewModel: CDFViewModel())
}
