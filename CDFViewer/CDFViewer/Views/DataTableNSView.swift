import SwiftUI
import AppKit

/// NSTableView wrapper for high-performance table display with 100k+ rows
/// Uses native AppKit virtualization and cell reuse for smooth scrolling
struct DataTableNSView: NSViewRepresentable {
    @Bindable var viewModel: CDFViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 8, height: 4)
        tableView.rowHeight = 22
        tableView.headerView = NSTableHeaderView()
        tableView.gridStyleMask = [.solidVerticalGridLineMask]

        // Set fixed row height for maximum performance
        tableView.usesAutomaticRowHeights = false

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView

        // Store reference for updates
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        // Update columns if changed
        let currentColumnIds = Set(tableView.tableColumns.map { $0.identifier.rawValue })
        let newColumnIds = Set(viewModel.tableColumns.map { $0.key })

        if currentColumnIds != newColumnIds {
            // Remove old columns
            for column in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(column)
            }

            // Add new columns
            for column in viewModel.tableColumns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key))
                tableColumn.title = column.name
                tableColumn.width = column.key == "time" ? 220 : 140
                tableColumn.minWidth = 60
                tableColumn.maxWidth = 400
                tableColumn.headerCell.alignment = column.key == "time" ? .left : .right
                tableView.addTableColumn(tableColumn)
            }
        }

        // Reload data
        tableView.reloadData()

        // Update cursor highlight
        context.coordinator.updateHighlight()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var viewModel: CDFViewModel
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        private var isUpdatingSelection = false

        init(viewModel: CDFViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            viewModel.tableRowCount
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let columnId = tableColumn?.identifier.rawValue else { return nil }

            let cellId = NSUserInterfaceItemIdentifier("DataCell")
            var cellView = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTextField

            if cellView == nil {
                cellView = NSTextField(labelWithString: "")
                cellView?.identifier = cellId
                cellView?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                cellView?.lineBreakMode = .byTruncatingTail
                cellView?.cell?.truncatesLastVisibleLine = true
            }

            // Get value based on column
            // Note: Must set ALL cell properties in every branch due to cell reuse
            if columnId == "time" {
                cellView?.alignment = .left
                if let timestamp = viewModel.timestamp(at: row) {
                    cellView?.stringValue = formatTimestamp(timestamp)
                    cellView?.textColor = .labelColor
                } else {
                    cellView?.stringValue = "-"
                    cellView?.textColor = .tertiaryLabelColor
                }
            } else {
                cellView?.alignment = .right
                if let value = viewModel.value(column: columnId, at: row) {
                    // Check if this column is an integer type
                    let column = viewModel.tableColumns.first { $0.key == columnId }
                    let isInteger = column?.isIntegerType ?? false
                    cellView?.stringValue = formatValue(value, isInteger: isInteger)
                    cellView?.textColor = .labelColor
                } else {
                    cellView?.stringValue = "-"
                    cellView?.textColor = .tertiaryLabelColor
                }
            }

            return cellView
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = HighlightableRowView()
            rowView.row = row
            rowView.coordinator = self
            return rowView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView = tableView else { return }
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 {
                viewModel.cursorIndex = selectedRow
                viewModel.isCursorPaused = true
            }
        }

        // MARK: - Cursor Handling

        func handleRowHover(row: Int, entered: Bool) {
            guard !viewModel.isCursorPaused else { return }
            if entered {
                viewModel.cursorIndex = row
            } else {
                viewModel.clearCursor()
            }
        }

        func handleRowClick(row: Int) {
            if viewModel.isCursorPaused && viewModel.cursorIndex == row {
                viewModel.isCursorPaused = false
            } else {
                viewModel.cursorIndex = row
                viewModel.isCursorPaused = true
            }
        }

        func updateHighlight() {
            tableView?.enumerateAvailableRowViews { rowView, row in
                if let highlightable = rowView as? HighlightableRowView {
                    highlightable.updateHighlight()
                }
            }
        }

        // MARK: - Formatting

        private func formatTimestamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }

        private func formatValue(_ value: Double, isInteger: Bool = false) -> String {
            if isInteger {
                // Format as integer (no decimal point)
                return String(format: "%.0f", value)
            } else if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
                return String(format: "%.6e", value)
            } else {
                return String(format: "%.6f", value)
            }
        }
    }
}

// MARK: - Custom Row View with Hover Support

class HighlightableRowView: NSTableRowView {
    var row: Int = 0
    weak var coordinator: DataTableNSView.Coordinator?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator?.handleRowHover(row: row, entered: true)
        updateHighlight()
    }

    override func mouseExited(with event: NSEvent) {
        coordinator?.handleRowHover(row: row, entered: false)
        updateHighlight()
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.handleRowClick(row: row)
        updateHighlight()
    }

    func updateHighlight() {
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let coordinator = coordinator else {
            super.drawBackground(in: dirtyRect)
            return
        }

        let isPaused = coordinator.viewModel.isCursorPaused && coordinator.viewModel.cursorIndex == row
        let isHighlighted = coordinator.viewModel.cursorIndex == row

        if isPaused {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            dirtyRect.fill()
        } else if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            dirtyRect.fill()
        } else if row % 2 == 1 {
            NSColor.alternatingContentBackgroundColors[1].setFill()
            dirtyRect.fill()
        } else {
            NSColor.alternatingContentBackgroundColors[0].setFill()
            dirtyRect.fill()
        }
    }
}
