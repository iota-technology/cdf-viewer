import SwiftUI

struct DataTableView: View {
    @Bindable var viewModel: CDFViewModel

    // Column widths - stored as state for resizing
    @State private var timeColumnWidth: CGFloat = 250  // Fits "31 Dec 2024 at 23:53:43"
    @State private var columnWidths: [String: CGFloat] = [:]  // key -> width
    private let defaultDataColumnWidth: CGFloat = 140
    private let minColumnWidth: CGFloat = 60

    private func widthForColumn(_ key: String) -> CGFloat {
        columnWidths[key] ?? defaultDataColumnWidth
    }

    private func columnWidthBinding(for key: String) -> Binding<CGFloat> {
        Binding(
            get: { columnWidths[key] ?? defaultDataColumnWidth },
            set: { columnWidths[key] = $0 }
        )
    }

    private var totalWidth: CGFloat {
        let dataColumnsWidth = viewModel.tableColumns
            .filter { $0.key != "time" }
            .reduce(0) { $0 + widthForColumn($1.key) }
        return timeColumnWidth + dataColumnsWidth + 20
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Note: We don't show a loading indicator to avoid flash on quick updates
                if let error = viewModel.dataError {
                    ErrorBanner(error: error)
                } else if viewModel.tableColumns.isEmpty {
                    ContentUnavailableView(
                        "No Data Selected",
                        systemImage: "tablecells",
                        description: Text("Select a time variable and data variables from the sidebar")
                    )
                } else {
                    let effectiveWidth = max(totalWidth, geometry.size.width)

                    // Single horizontal ScrollView containing both header and data
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            // Column headers with resize handles
                            HStack(spacing: 0) {
                                Text("Time")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: timeColumnWidth, alignment: .leading)
                                    .padding(.horizontal, 8)

                                // Time column resize handle
                                ColumnResizeHandle(
                                    width: $timeColumnWidth,
                                    minWidth: minColumnWidth
                                )

                                ForEach(viewModel.tableColumns.filter { $0.key != "time" }) { column in
                                    Text(column.name)
                                        .font(.caption.weight(.semibold))
                                        .frame(width: widthForColumn(column.key), alignment: .trailing)
                                        .padding(.horizontal, 4)

                                    // Data column resize handle
                                    ColumnResizeHandle(
                                        width: columnWidthBinding(for: column.key),
                                        minWidth: minColumnWidth
                                    )
                                }

                                Spacer(minLength: 0)
                            }
                            .frame(width: effectiveWidth, alignment: .leading)
                            .padding(.vertical, 6)
                            .background(.bar)

                            Divider()

                            // Data rows with vertical scrolling
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 0) {
                                    ForEach(viewModel.tableRows) { row in
                                        TableRowView(
                                            row: row,
                                            columns: viewModel.tableColumns,
                                            timeColumnWidth: timeColumnWidth,
                                            columnWidths: columnWidths,
                                            defaultDataColumnWidth: defaultDataColumnWidth,
                                            effectiveWidth: effectiveWidth,
                                            isHighlighted: viewModel.cursorIndex == row.id,
                                            isPaused: viewModel.isCursorPaused && viewModel.cursorIndex == row.id,
                                            onHover: { isHovering in
                                                if !viewModel.isCursorPaused {
                                                    viewModel.cursorIndex = isHovering ? row.id : nil
                                                }
                                            },
                                            onTap: {
                                                if viewModel.isCursorPaused && viewModel.cursorIndex == row.id {
                                                    // Clicking paused row unpauses
                                                    viewModel.isCursorPaused = false
                                                } else {
                                                    // Clicking any row pauses on it
                                                    viewModel.cursorIndex = row.id
                                                    viewModel.isCursorPaused = true
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .onHover { isHovering in
                        if !isHovering {
                            viewModel.clearCursor()
                        }
                    }

                    // Footer with stats
                    TableFooterView(
                        totalRecords: viewModel.totalRecords,
                        displayedRecords: viewModel.tableRows.count,
                        cursorIndex: viewModel.cursorIndex,
                        isPaused: viewModel.isCursorPaused
                    )
                }
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

// MARK: - Table Row View

struct TableRowView: View {
    let row: DataRow
    let columns: [DataColumn]
    let timeColumnWidth: CGFloat
    let columnWidths: [String: CGFloat]
    let defaultDataColumnWidth: CGFloat
    let effectiveWidth: CGFloat
    let isHighlighted: Bool
    let isPaused: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    private func widthForColumn(_ key: String) -> CGFloat {
        columnWidths[key] ?? defaultDataColumnWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(row.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(width: timeColumnWidth, alignment: .leading)
                .padding(.horizontal, 8)

            // Spacer for time column resize handle
            Spacer().frame(width: 8)

            ForEach(columns.filter { $0.key != "time" }) { column in
                if let value = row.values[column.key] {
                    Text(formatValue(value))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: widthForColumn(column.key), alignment: .trailing)
                        .padding(.horizontal, 4)
                } else {
                    Text("-")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: widthForColumn(column.key), alignment: .trailing)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }

                // Spacer for column resize handle
                Spacer().frame(width: 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: effectiveWidth, alignment: .leading)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
    }

    private var backgroundColor: Color {
        if isPaused {
            return Color.accentColor.opacity(0.3)
        } else if isHighlighted {
            return Color.accentColor.opacity(0.15)
        } else if row.id % 2 == 1 {
            return Color.gray.opacity(0.1)
        }
        return Color.clear
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.6e", value)
        } else {
            return String(format: "%.6f", value)
        }
    }
}

// MARK: - Table Footer

struct TableFooterView: View {
    let totalRecords: Int
    let displayedRecords: Int
    let cursorIndex: Int?
    let isPaused: Bool

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

// MARK: - Column Resize Handle

struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color.clear)
            .frame(width: 8, height: 20)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            startWidth = width
                            isDragging = true
                        }
                        width = max(minWidth, startWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
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
