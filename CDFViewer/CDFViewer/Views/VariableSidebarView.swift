import SwiftUI

/// Color palette for chart series indicators
let chartColorPalette: [Color] = [
    .blue, .orange, .green, .red, .purple, .brown, .pink, .gray, .cyan, .yellow
]

/// Configuration for a section of variables in the sidebar
struct VariableSectionConfig {
    let title: String
    let variables: [CDFVariable]
    let selectionMode: SelectionMode

    enum SelectionMode {
        case single  // Radio buttons - one selection
        case multi   // Checkboxes - multiple selections, with vector expansion
    }
}

/// Reusable sidebar for selecting variables across different views
struct VariableSidebarView<TrailingContent: View>: View {
    // Selection state
    @Binding var singleSelection: CDFVariable?
    @Binding var multiSelection: Set<String>  // "varName" or "varName.X"

    // Configuration
    let sections: [VariableSectionConfig]

    /// Returns true if the variable should be disabled (greyed out, not selectable)
    var isDisabled: ((CDFVariable) -> Bool)?

    /// Returns the color indicator for a component key (nil = no indicator)
    var colorForKey: ((String) -> Color?)?

    /// Returns the current hover value for a component key (nil = don't show)
    var valueForKey: ((String) -> Double?)?

    /// Set of component keys currently loading (show spinner instead of checkbox)
    var loadingKeys: Set<String> = []

    /// Callback when info button is tapped on a variable (for external handling)
    var onInfoTapped: ((CDFVariable) -> Void)?

    /// View model for info popover (if provided, popover is shown internally)
    var viewModel: CDFViewModel?

    /// Whether to show positional toggle in info popover (Globe view only)
    var showPositionalToggle: Bool = false

    /// Whether to show data type and record count under variable names
    var showDataTypeInfo: Bool = true

    /// Whether to expand vector variables into individual components (X, Y, Z)
    /// When false, vectors are shown as a single selectable item
    var expandVectors: Bool = true

    /// Optional trailing content for single selection rows (e.g., timestamp display)
    @ViewBuilder var singleSelectionTrailing: (CDFVariable) -> TrailingContent

    // Internal state for info popover
    @State private var infoPopoverVariable: CDFVariable?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 8)
                }

                sectionView(section)
            }
        }
    }

    // MARK: - Section View

    @ViewBuilder
    private func sectionView(_ section: VariableSectionConfig) -> some View {
        Text(section.title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, index(of: section) == 0 ? 12 : 0)
            .padding(.bottom, 4)

        if section.variables.isEmpty {
            Text("No variables found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            switch section.selectionMode {
            case .single:
                ForEach(section.variables) { variable in
                    singleSelectionRow(variable)
                }
            case .multi:
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(section.variables) { variable in
                            multiSelectionRow(variable)
                        }
                    }
                }
            }
        }
    }

    private func index(of section: VariableSectionConfig) -> Int {
        sections.firstIndex(where: { $0.title == section.title }) ?? 0
    }

    // MARK: - Single Selection Row (Radio)

    private func singleSelectionRow(_ variable: CDFVariable) -> some View {
        let isSelected = singleSelection == variable
        let disabled = isDisabled?(variable) ?? false

        return HStack {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(disabled ? Color.gray.opacity(0.3) : (isSelected ? Color.blue : Color.secondary))
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text(variable.name)
                        .font(.system(size: 13))
                        .foregroundStyle(disabled ? .secondary : .primary)

                    if showDataTypeInfo {
                        Text("\(variable.dataType.displayName) [\(variable.recordCount)]")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .opacity(disabled ? 0.5 : 1.0)

            // Info button - always fully visible, popover attached here for correct arrow
            if viewModel != nil || onInfoTapped != nil {
                Button {
                    if viewModel != nil {
                        infoPopoverVariable = variable
                    } else {
                        onInfoTapped?(variable)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { infoPopoverVariable == variable },
                    set: { if !$0 { infoPopoverVariable = nil } }
                )) {
                    if let vm = viewModel {
                        VariableInfoPopover(
                            variable: variable,
                            viewModel: vm,
                            showPositionalToggle: showPositionalToggle,
                            defaultColor: colorForKey?(variable.name) ?? .blue
                        )
                    }
                }
            }

            Spacer()

            // Custom trailing content (e.g., timestamp display)
            singleSelectionTrailing(variable)

            // Show value if provided
            if let value = valueForKey?(variable.name) {
                Text(formatValue(value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Show color if provided
            if let color = colorForKey?(variable.name) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !disabled else { return }
            singleSelection = variable
        }
    }

    // MARK: - Multi Selection Row (Checkbox with Vector Expansion)

    private func multiSelectionRow(_ variable: CDFVariable) -> some View {
        let disabled = isDisabled?(variable) ?? false
        let shouldExpand = expandVectors && variable.isVector
        // Check if any component of this variable is loading
        let isLoading = isVariableLoading(variable, expanded: shouldExpand)

        return VStack(alignment: .leading, spacing: 0) {
            // Main variable row
            HStack {
                HStack {
                    let isAnySelected = isVariableOrComponentSelected(variable)
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: isAnySelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(disabled ? Color.gray.opacity(0.3) : (isAnySelected ? Color.blue : Color.secondary))
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(variable.name)
                            .font(.system(size: 13))
                            .foregroundStyle(disabled ? .secondary : .primary)

                        if showDataTypeInfo {
                            // Show vector size when not expanding (e.g., "DOUBLE[3]")
                            if variable.isVector && !expandVectors {
                                Text("\(variable.dataType.displayName)[\(variable.displayColumnsPerRow)]")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("\(variable.dataType.displayName) [\(variable.recordCount)]")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .opacity(disabled ? 0.5 : 1.0)

                // Info button - always fully visible, popover attached here for correct arrow
                if viewModel != nil || onInfoTapped != nil {
                    Button {
                        if viewModel != nil {
                            infoPopoverVariable = variable
                        } else {
                            onInfoTapped?(variable)
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(
                        get: { infoPopoverVariable == variable },
                        set: { if !$0 { infoPopoverVariable = nil } }
                    )) {
                        if let vm = viewModel {
                            VariableInfoPopover(
                                variable: variable,
                                viewModel: vm,
                                showPositionalToggle: showPositionalToggle,
                                defaultColor: colorForKey?(variable.name) ?? .blue
                            )
                        }
                    }
                }

                Spacer()

                // Show value on hover (for scalar variables, or vectors when not expanded)
                if !shouldExpand, let value = valueForKey?(variable.name) {
                    Text(formatValue(value))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Color indicator (for scalar variables, or vectors when not expanded)
                if !shouldExpand, let color = colorForKey?(variable.name) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !disabled else { return }
                toggleVariable(variable, expanded: shouldExpand)
            }

            // Component sub-items for vectors (only when expanding)
            if shouldExpand {
                let components = componentNames(for: variable)
                ForEach(components, id: \.self) { component in
                    componentRow(variable: variable, component: component, disabled: disabled)
                }
            }
        }
    }

    private func componentRow(variable: CDFVariable, component: String, disabled: Bool) -> some View {
        let key = "\(variable.name).\(component)"
        let isSelected = multiSelection.contains(key)
        let isLoading = loadingKeys.contains(key)

        return HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(disabled ? Color.gray.opacity(0.3) : (isSelected ? Color.blue : Color.secondary))
                    .font(.system(size: 11))
            }

            Text(component)
                .font(.system(size: 12))
                .foregroundStyle(disabled ? .tertiary : .secondary)

            Spacer()

            // Show value on hover
            if let value = valueForKey?(key) {
                Text(formatValue(value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Color indicator
            if let color = colorForKey?(key) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.leading, 32)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(disabled ? 0.5 : 1.0)
        .onTapGesture {
            guard !disabled else { return }
            toggleComponent(key)
        }
    }

    // MARK: - Component Names

    private func componentNames(for variable: CDFVariable) -> [String] {
        // Use displayColumnsPerRow which correctly handles 2D arrays like [86400, 3]
        let count = variable.displayColumnsPerRow
        if count == 3 {
            return ["X", "Y", "Z"]
        } else if count == 2 {
            return ["X", "Y"]
        } else {
            return (0..<min(count, 10)).map { "[\($0)]" }
        }
    }

    // MARK: - Selection Logic

    private func isVariableOrComponentSelected(_ variable: CDFVariable) -> Bool {
        if variable.isVector && expandVectors {
            // Expanded mode: check if any component is selected
            let components = componentNames(for: variable)
            return components.contains { multiSelection.contains("\(variable.name).\($0)") }
        } else {
            // Scalar or non-expanded vector: check by variable name
            return multiSelection.contains(variable.name)
        }
    }

    private func isVariableLoading(_ variable: CDFVariable, expanded: Bool) -> Bool {
        if variable.isVector && expanded {
            // Check if any component is loading
            let components = componentNames(for: variable)
            return components.contains { loadingKeys.contains("\(variable.name).\($0)") }
        } else {
            return loadingKeys.contains(variable.name)
        }
    }

    private func toggleVariable(_ variable: CDFVariable, expanded: Bool = true) {
        if variable.isVector && expanded {
            // Expanded mode: toggle all component keys
            let components = componentNames(for: variable)
            let keys = components.map { "\(variable.name).\($0)" }
            let allSelected = keys.allSatisfy { multiSelection.contains($0) }

            if allSelected {
                for key in keys {
                    multiSelection.remove(key)
                }
            } else {
                for key in keys {
                    multiSelection.insert(key)
                }
            }
        } else {
            // Scalar or non-expanded vector: toggle by variable name
            if multiSelection.contains(variable.name) {
                multiSelection.remove(variable.name)
            } else {
                multiSelection.insert(variable.name)
            }
        }
    }

    private func toggleComponent(_ key: String) {
        if multiSelection.contains(key) {
            multiSelection.remove(key)
        } else {
            multiSelection.insert(key)
        }
    }

    // MARK: - Formatting

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.2e", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Convenience Initializers

extension VariableSidebarView where TrailingContent == EmptyView {
    /// Create a sidebar with a single-selection section (for table view)
    init(
        title: String,
        variables: [CDFVariable],
        selection: Binding<CDFVariable?>,
        showDataTypeInfo: Bool = true,
        isDisabled: ((CDFVariable) -> Bool)? = nil,
        loadingKeys: Set<String> = [],
        viewModel: CDFViewModel? = nil,
        showPositionalToggle: Bool = false,
        onInfoTapped: ((CDFVariable) -> Void)? = nil
    ) {
        self._singleSelection = selection
        self._multiSelection = .constant([])
        self.sections = [
            VariableSectionConfig(title: title, variables: variables, selectionMode: .single)
        ]
        self.showDataTypeInfo = showDataTypeInfo
        self.expandVectors = true
        self.isDisabled = isDisabled
        self.loadingKeys = loadingKeys
        self.viewModel = viewModel
        self.showPositionalToggle = showPositionalToggle
        self.onInfoTapped = onInfoTapped
        self.singleSelectionTrailing = { _ in EmptyView() }
    }

    /// Create a sidebar with multiple sections (for chart view)
    init(
        singleSelection: Binding<CDFVariable?>,
        multiSelection: Binding<Set<String>>,
        sections: [VariableSectionConfig],
        showDataTypeInfo: Bool = true,
        expandVectors: Bool = true,
        isDisabled: ((CDFVariable) -> Bool)? = nil,
        colorForKey: ((String) -> Color?)? = nil,
        valueForKey: ((String) -> Double?)? = nil,
        loadingKeys: Set<String> = [],
        viewModel: CDFViewModel? = nil,
        showPositionalToggle: Bool = false,
        onInfoTapped: ((CDFVariable) -> Void)? = nil
    ) {
        self._singleSelection = singleSelection
        self._multiSelection = multiSelection
        self.sections = sections
        self.showDataTypeInfo = showDataTypeInfo
        self.expandVectors = expandVectors
        self.isDisabled = isDisabled
        self.colorForKey = colorForKey
        self.valueForKey = valueForKey
        self.loadingKeys = loadingKeys
        self.viewModel = viewModel
        self.showPositionalToggle = showPositionalToggle
        self.onInfoTapped = onInfoTapped
        self.singleSelectionTrailing = { _ in EmptyView() }
    }
}

extension VariableSidebarView {
    /// Create a sidebar with custom trailing content for single selection rows
    init(
        singleSelection: Binding<CDFVariable?>,
        multiSelection: Binding<Set<String>>,
        sections: [VariableSectionConfig],
        showDataTypeInfo: Bool = true,
        expandVectors: Bool = true,
        isDisabled: ((CDFVariable) -> Bool)? = nil,
        colorForKey: ((String) -> Color?)? = nil,
        valueForKey: ((String) -> Double?)? = nil,
        loadingKeys: Set<String> = [],
        viewModel: CDFViewModel? = nil,
        showPositionalToggle: Bool = false,
        onInfoTapped: ((CDFVariable) -> Void)? = nil,
        @ViewBuilder singleSelectionTrailing: @escaping (CDFVariable) -> TrailingContent
    ) {
        self._singleSelection = singleSelection
        self._multiSelection = multiSelection
        self.sections = sections
        self.showDataTypeInfo = showDataTypeInfo
        self.expandVectors = expandVectors
        self.isDisabled = isDisabled
        self.colorForKey = colorForKey
        self.valueForKey = valueForKey
        self.loadingKeys = loadingKeys
        self.viewModel = viewModel
        self.showPositionalToggle = showPositionalToggle
        self.onInfoTapped = onInfoTapped
        self.singleSelectionTrailing = singleSelectionTrailing
    }
}
