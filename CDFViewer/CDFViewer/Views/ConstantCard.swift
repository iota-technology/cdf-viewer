import SwiftUI

/// Card displaying a single constant variable's value and metadata
struct ConstantCard: View {
    let constant: ConstantValue
    @Bindable var viewModel: CDFViewModel
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Name and info button
            HStack {
                Text(constant.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    showingInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingInfo) {
                    VariableInfoPopover(
                        variable: constant.variable,
                        viewModel: viewModel,
                        showPositionalToggle: false
                    )
                }
            }

            // Value display with inline units
            if constant.isScalar {
                // Single value - larger display with units
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(constant.formattedValue)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)

                    if let units = constant.formattedUnits {
                        Text(units)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if constant.isMatrix,
                      let matrixRows = constant.matrixRows {
                // Matrix - display as grid with optional row/column headers
                MatrixGridView(
                    matrixRows: matrixRows,
                    rowLabels: constant.matrixRowLabels,
                    colLabels: constant.matrixColumnLabels,
                    units: constant.formattedUnits
                )
            } else if constant.values.count <= 10 {
                // Small array - show values in bracketed column with units to the right
                // Uses same styling as matrix row labels for consistency
                let fontSize: CGFloat = constant.values.count <= 3 ? 18 : (constant.values.count <= 6 ? 15 : 13)
                let valuesWithLabels = constant.formattedValuesWithLabels
                let hasLabels = valuesWithLabels.contains { $0.label != nil }

                HStack(alignment: .center, spacing: 6) {
                    // Bracketed values column
                    BracketedColumn(fontSize: fontSize) {
                        ForEach(Array(valuesWithLabels.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 0) {
                                // Row label (same style as matrix)
                                if hasLabels {
                                    Text(item.label ?? "")
                                        .font(.system(size: fontSize - 4))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 20, alignment: .trailing)
                                }
                                Text(item.value)
                                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(width: 60)
                            }
                        }
                    }

                    // Units to the right of bracket
                    if let units = constant.formattedUnits {
                        Text(units)
                            .font(.system(size: fontSize - 2))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Larger array - show summary with units
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(constant.formattedValue)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)

                    if let units = constant.formattedUnits {
                        Text(units)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Metadata footer
            VStack(alignment: .leading, spacing: 2) {
                if let desc = constant.description ?? constant.fieldName {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Data type info
                Text("\(constant.variable.dataType.displayName) \(constant.variable.dimensionString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

/// A view that wraps content in subtle square brackets
struct BracketedColumn<Content: View>: View {
    let fontSize: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // Left bracket
            BracketShape(isLeft: true)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: 6)

            // Content column (centered)
            VStack(alignment: .center, spacing: 2) {
                content
            }

            // Right bracket
            BracketShape(isLeft: false)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: 6)
        }
    }
}

/// Shape for drawing a square bracket (left or right)
struct BracketShape: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 2  // How far the horizontal parts extend

        if isLeft {
            // Left bracket: ⎡ shape
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            // Right bracket: ⎤ shape
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        return path
    }
}

/// Display a matrix as a grid with optional row and column headers
struct MatrixGridView: View {
    let matrixRows: [[String]]
    let rowLabels: [String]?
    let colLabels: [String]?
    let units: String?

    private var fontSize: CGFloat {
        // Adjust font size based on matrix dimensions
        let totalCells = matrixRows.count * (matrixRows.first?.count ?? 0)
        if totalCells <= 4 { return 16 }
        if totalCells <= 9 { return 14 }
        return 12
    }

    private var hasLabels: Bool {
        rowLabels != nil || colLabels != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                // Matrix with brackets
                HStack(spacing: 2) {
                    // Left bracket
                    BracketShape(isLeft: true)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        .frame(width: 6)

                    // Grid content
                    VStack(alignment: .leading, spacing: 2) {
                        // Column headers (only if we have labels)
                        if let colLabels = colLabels {
                            HStack(spacing: 0) {
                                // Empty corner cell (only if we also have row labels)
                                if rowLabels != nil {
                                    Text("")
                                        .frame(width: 20)
                                }

                                ForEach(Array(colLabels.enumerated()), id: \.offset) { _, label in
                                    Text(label)
                                        .font(.system(size: fontSize - 4))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 60)
                                }
                            }
                        }

                        // Matrix rows with optional row headers
                        ForEach(Array(matrixRows.enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: 0) {
                                // Row header (only if we have labels)
                                if let rowLabels = rowLabels {
                                    Text(rowLabels[rowIndex])
                                        .font(.system(size: fontSize - 4))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 20, alignment: .trailing)
                                }

                                // Row values
                                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                    Text(value)
                                        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(width: 60)
                                }
                            }
                        }
                    }

                    // Right bracket
                    BracketShape(isLeft: false)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        .frame(width: 6)
                }

                // Units to the right
                if let units = units {
                    Text(units)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
