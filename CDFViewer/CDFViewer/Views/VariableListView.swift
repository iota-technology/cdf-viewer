import SwiftUI

struct VariableListView: View {
    @Bindable var viewModel: CDFViewModel

    /// Data variables to show based on current selection
    private var dataVariables: [CDFVariable] {
        guard let file = viewModel.cdfFile else { return [] }

        if viewModel.isShowingConstants {
            // Show constants (variables without DEPEND_0)
            return file.constantVariables()
        } else if let timeVar = viewModel.tableTimeVariable {
            // Show variables that depend on the selected time variable
            return file.variablesDependingOn(timeVariable: timeVar)
        } else {
            // No selection - show all numeric variables
            return file.numericVariables()
        }
    }

    /// Whether to expand vectors (not needed for constants which are typically scalar/small arrays)
    private var expandVectors: Bool {
        !viewModel.isShowingConstants
    }

    var body: some View {
        if let file = viewModel.cdfFile {
            VStack(alignment: .leading, spacing: 0) {
                // Independent Variable section
                independentVariableSection(file: file)

                Divider()
                    .padding(.vertical, 8)

                // Data Variables section
                dataVariablesSection(file: file)

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                "No File Loaded",
                systemImage: "doc.badge.plus",
                description: Text("Open a CDF file to view its variables")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Independent Variable Section

    @ViewBuilder
    private func independentVariableSection(file: CDFFile) -> some View {
        Text("Independent Variable")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

        let timeVariables = file.timestampVariables()

        if timeVariables.isEmpty && !file.hasConstants {
            Text("No variables found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            // Time variables as radio options
            ForEach(timeVariables) { variable in
                timeVariableRow(variable)
            }

            // Constants pseudo-option (only if file has constants)
            if file.hasConstants {
                constantsRow(count: file.constantVariables().count)
            }
        }
    }

    private func timeVariableRow(_ variable: CDFVariable) -> some View {
        let isSelected = viewModel.tableIndependentSelection?.timeVariable == variable

        return HStack {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text(variable.name)
                    .font(.system(size: 13))

                Text("\(variable.dataType.displayName) [\(variable.recordCount)]")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.tableIndependentSelection = .timeVariable(variable)
        }
    }

    private func constantsRow(count: Int) -> some View {
        let isSelected = viewModel.isShowingConstants

        return HStack {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text("Constants")
                    .font(.system(size: 13))

                Text("\(count) variables")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.tableIndependentSelection = .constants
        }
    }

    // MARK: - Data Variables Section

    @ViewBuilder
    private func dataVariablesSection(file: CDFFile) -> some View {
        let sectionConfig = VariableSectionConfig(
            title: "Data Variables",
            variables: dataVariables,
            selectionMode: .multi
        )

        VariableSidebarView(
            singleSelection: .constant(nil),
            multiSelection: $viewModel.tableSelectedComponents,
            sections: [sectionConfig],
            showDataTypeInfo: true,
            expandVectors: expandVectors,
            loadingKeys: viewModel.loadingComponents,
            viewModel: viewModel,
            showPositionalToggle: false
        )
    }
}

#Preview {
    VariableListView(viewModel: CDFViewModel())
        .frame(width: 280)
}
