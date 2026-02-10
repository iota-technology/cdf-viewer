import SwiftUI

struct DataTableView: View {
    @Bindable var viewModel: CDFViewModel

    @State private var selectedRows: Set<Int> = []

    // Column widths
    private let timeColumnWidth: CGFloat = 180
    private let dataColumnWidth: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingData {
                ProgressView("Loading data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.dataError {
                ErrorBanner(error: error)
            } else if viewModel.tableColumns.isEmpty {
                ContentUnavailableView(
                    "No Data Selected",
                    systemImage: "tablecells",
                    description: Text("Select a time variable and data variables from the sidebar")
                )
            } else {
                // Column headers
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Time column header
                        Text("Time")
                            .font(.caption.weight(.semibold))
                            .frame(width: timeColumnWidth, alignment: .leading)
                            .padding(.horizontal, 8)

                        // Data column headers
                        ForEach(viewModel.tableColumns.filter { $0.key != "time" }) { column in
                            Text(column.name)
                                .font(.caption.weight(.semibold))
                                .frame(width: dataColumnWidth, alignment: .trailing)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(.bar)
                }

                Divider()

                // Data rows
                ScrollView(.horizontal, showsIndicators: true) {
                    List(viewModel.tableRows, selection: $selectedRows) { row in
                        HStack(spacing: 0) {
                            // Time value
                            Text(row.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                .font(.system(.body, design: .monospaced))
                                .frame(width: timeColumnWidth, alignment: .leading)
                                .padding(.horizontal, 8)

                            // Data values
                            ForEach(viewModel.tableColumns.filter { $0.key != "time" }) { column in
                                if let value = row.values[column.key] {
                                    Text(formatValue(value))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: dataColumnWidth, alignment: .trailing)
                                        .padding(.horizontal, 4)
                                } else {
                                    Text("-")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: dataColumnWidth, alignment: .trailing)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                }
                            }
                        }
                        .tag(row.id)
                        .contextMenu {
                            Button("Copy Row") {
                                copyRows([row.id])
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                // Footer with stats
                TableFooterView(
                    totalRecords: viewModel.totalRecords,
                    displayedRecords: viewModel.tableRows.count,
                    selectedCount: selectedRows.count
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
                .disabled(viewModel.tableRows.isEmpty)
            }
        }
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.6e", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    private func copyRows(_ selection: Set<Int>) {
        let selectedRowData = viewModel.tableRows.filter { selection.contains($0.id) }
        var text = viewModel.tableColumns.map { $0.name }.joined(separator: "\t") + "\n"

        for row in selectedRowData {
            var values: [String] = []
            for column in viewModel.tableColumns {
                if column.key == "time" {
                    values.append(row.timestamp.ISO8601Format())
                } else if let value = row.values[column.key] {
                    values.append(formatValue(value))
                } else {
                    values.append("")
                }
            }
            text += values.joined(separator: "\t") + "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
    let displayedRecords: Int
    let selectedCount: Int

    var body: some View {
        HStack {
            Text("\(displayedRecords) of \(totalRecords) rows")
                .font(.caption)
                .foregroundStyle(.secondary)

            if displayedRecords < totalRecords {
                Text("(showing first \(displayedRecords))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if selectedCount > 0 {
                Text("\(selectedCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
