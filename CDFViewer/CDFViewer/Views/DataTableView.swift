import SwiftUI

struct DataTableView: View {
    @Bindable var viewModel: CDFViewModel
    let variable: CDFVariable

    @State private var selectedRows: Set<Int> = []
    @State private var showVectorInspector = false
    @State private var inspectedRow: CDFDataRow?

    private var columns: [CDFColumn] {
        CDFColumn.columnsForVariable(variable)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with variable info
            VariableHeaderView(variable: variable)

            Divider()

            // Data table
            if viewModel.isLoadingData {
                ProgressView("Loading data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.dataError {
                ErrorBanner(error: error)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text(variable.isSingleRecordArray ? "Index" : "Record")
                        .font(.caption.weight(.semibold))
                        .frame(width: 70, alignment: .leading)
                        .padding(.horizontal, 8)

                    ForEach(columns) { column in
                        Text(column.name)
                            .font(.caption.weight(.semibold))
                            .frame(width: column.width, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                // Data rows
                List(viewModel.currentData, selection: $selectedRows) { row in
                    HStack(spacing: 0) {
                        Text("\(row.id)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)

                        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                            if index < row.values.count {
                                Text(row.values[index].stringValue)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: column.width, alignment: .leading)
                                    .lineLimit(1)
                            } else {
                                Text("-")
                                    .frame(width: column.width, alignment: .leading)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()
                    }
                    .tag(row.id)
                    .contextMenu {
                        Button("Inspect Row") {
                            inspectedRow = row
                            showVectorInspector = true
                        }
                        Button("Copy Row") {
                            copyRow(row)
                        }
                    }
                }
                .listStyle(.plain)
            }

            // Footer with stats
            TableFooterView(
                totalRecords: variable.displayRowCount,
                displayedRecords: viewModel.currentData.count,
                selectedCount: selectedRows.count
            )
        }
        .sheet(isPresented: $showVectorInspector) {
            if let row = inspectedRow {
                VectorInspectorView(
                    row: row,
                    variable: variable,
                    columns: columns
                )
            }
        }
    }

    private func copyRow(_ row: CDFDataRow) {
        let values = (["\(row.id)"] + row.values.map { $0.stringValue }).joined(separator: "\t")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values, forType: .string)
    }
}

// MARK: - Variable Header

struct VariableHeaderView: View {
    let variable: CDFVariable

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(variable.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label(variable.dataType.displayName, systemImage: "number")
                    Label(variable.dimensionString, systemImage: "square.grid.2x2")
                    Label("\(variable.displayRowCount) rows", systemImage: "list.bullet")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Show DEPEND attribute if present
            if let depend = variable.dependsOn {
                Text("Depends on: \(depend)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background)
    }
}

// MARK: - Data Cell

struct DataCellView: View {
    let value: CDFValue
    let dataType: CDFDataType

    var body: some View {
        Text(value.stringValue)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .foregroundStyle(textColor)
    }

    private var textColor: Color {
        if dataType.isTimeType {
            return .blue
        }
        return .primary
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
    let variable = CDFVariable(
        name: "r_ecef",
        dataType: .double,
        numElements: 1,
        dimensions: [86400, 3],
        dimVarys: [true, true],
        maxRecord: 0,
        isZVariable: true,
        vxrOffset: 0,
        cprOffset: 0,
        attributes: [:]
    )

    DataTableView(viewModel: CDFViewModel(), variable: variable)
}
