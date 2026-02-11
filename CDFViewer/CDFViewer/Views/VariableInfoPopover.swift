import SwiftUI

/// Popover showing variable details with color picker and positional toggle
struct VariableInfoPopover: View {
    let variable: CDFVariable
    var viewModel: CDFViewModel
    let showPositionalToggle: Bool
    /// The default color to show (nil = don't show color picker at all)
    let defaultColor: Color?

    @State private var selectedColor: Color = .blue
    @State private var isPositional: Bool = false
    @State private var isHoveringColor: Bool = false
    @State private var hoverDismissTask: DispatchWorkItem?

    init(variable: CDFVariable, viewModel: CDFViewModel, showPositionalToggle: Bool = false, defaultColor: Color? = nil) {
        self.variable = variable
        self.viewModel = viewModel
        self.showPositionalToggle = showPositionalToggle
        self.defaultColor = defaultColor

        // Initialize state from view model
        let metadata = viewModel.metadata(for: variable.name)
        _isPositional = State(initialValue: metadata.isPositional ?? variable.isECEFPosition)

        // Use custom color if set, otherwise use the default color passed in
        if let hexColor = metadata.customColor, let color = Color(hex: hexColor) {
            _selectedColor = State(initialValue: color)
        } else if let color = defaultColor {
            _selectedColor = State(initialValue: color)
        } else {
            _selectedColor = State(initialValue: .blue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with optional color picker
            HStack {
                Text(variable.name)
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                // Color picker with sub-colors overlay for vectors (only when color is used)
                if defaultColor != nil {
                    colorPickerWithSubColors
                }
            }

            Divider()

            // Variable details
            VStack(alignment: .leading, spacing: 6) {
                DetailRow(label: "Type", value: variable.dataType.displayName)
                DetailRow(label: "Dimensions", value: variable.dimensionString)
                DetailRow(label: "Records", value: "\(variable.recordCount)")

                // Show relevant CDF attributes
                if let units = variable.attributes["UNITS"], !units.isEmpty {
                    DetailRow(label: "Units", value: units)
                }
                if let desc = variable.attributes["CATDESC"], !desc.isEmpty {
                    DetailRow(label: "Description", value: desc)
                }
                if let fieldName = variable.attributes["FIELDNAM"], !fieldName.isEmpty, fieldName != variable.name {
                    DetailRow(label: "Field Name", value: fieldName)
                }
            }

            // Positional toggle (Globe view only)
            if showPositionalToggle {
                Divider()

                Toggle("Use as Position Data", isOn: $isPositional)
                    .toggleStyle(.switch)
                    .onChange(of: isPositional) { _, newValue in
                        updatePositionalMetadata(newValue)
                    }
                    .help("When enabled, this variable will be displayed as positions on the 3D globe")

                if variable.isVector && !variable.isECEFPosition {
                    Text("Not automatically detected as position data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Color Picker with Sub-Colors

    private let componentRowHeight: CGFloat = 18
    private let subColorsHeight: CGFloat = 62  // 3 rows + spacing

    @ViewBuilder
    private var colorPickerWithSubColors: some View {
        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
            .labelsHidden()
            .onChange(of: selectedColor) { _, newColor in
                updateColorMetadata(newColor)
            }
            .overlay(alignment: .topLeading) {
                // Sub-colors cascade below the color picker (vectors only)
                if variable.isVector {
                    VStack(alignment: .leading, spacing: 2) {
                        animatedColorRow("X", color: selectedColor, index: 0)
                        animatedColorRow("Y", color: selectedColor.lchHueShifted(by: 30), index: 1)
                        animatedColorRow("Z", color: selectedColor.lchHueShifted(by: 60), index: 2)
                    }
                    .clipped()
                    .padding(.top, 28)  // Position below the color picker
                }
            }
            // Extend hit testing area to cover both picker and where sub-colors appear
            .contentShape(
                Rectangle()
                    .size(width: 60, height: variable.isVector ? 28 + subColorsHeight : 28)
            )
            .onHover { hovering in
                if variable.isVector {
                    handleColorHover(hovering)
                }
            }
    }

    private func handleColorHover(_ hovering: Bool) {
        // Cancel any pending dismiss
        hoverDismissTask?.cancel()
        hoverDismissTask = nil

        if hovering {
            // Immediately show on hover
            isHoveringColor = true
        } else {
            // Delay hiding so animation can continue if user hovers back quickly
            let task = DispatchWorkItem { [self] in
                isHoveringColor = false
            }
            hoverDismissTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
        }
    }

    @ViewBuilder
    private func animatedColorRow(_ label: String, color: Color, index: Int) -> some View {
        // Staggered cascade: expand in order (X→Y→Z), collapse in reverse (Z→Y→X) at 2x speed
        let expandDelay = Double(index) * 0.12
        let collapseDelay = Double(2 - index) * 0.06

        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .foregroundColor(Color(nsColor: .labelColor))
                .font(.caption)
        }
        .frame(height: componentRowHeight)
        .compositingGroup()  // Rasterize before applying opacity to fix text rendering
        // Each row slides out from directly under the one above (just one row height)
        .offset(y: isHoveringColor ? 0 : -componentRowHeight)
        .opacity(isHoveringColor ? 1 : 0)
        .animation(
            .spring(response: 0.35, dampingFraction: 0.7)
                .delay(isHoveringColor ? expandDelay : collapseDelay),
            value: isHoveringColor
        )
    }

    private func updateColorMetadata(_ color: Color) {
        var metadata = viewModel.metadata(for: variable.name)
        metadata.customColor = color.hexString
        viewModel.setMetadata(metadata, for: variable.name)
    }

    private func updatePositionalMetadata(_ isPositional: Bool) {
        var metadata = viewModel.metadata(for: variable.name)
        // Only store override if different from heuristic
        if isPositional == variable.isECEFPosition {
            metadata.isPositional = nil  // Use heuristic
        } else {
            metadata.isPositional = isPositional
        }
        viewModel.setMetadata(metadata, for: variable.name)
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
