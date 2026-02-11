import SwiftUI

struct VariableListView: View {
    @Bindable var viewModel: CDFViewModel

    /// Get color for a variable (only show for selected variables)
    private func colorForVariable(_ name: String) -> Color? {
        // Only show color if this variable/component is selected
        guard viewModel.tableSelectedComponents.contains(name) ||
              viewModel.tableSelectedComponents.contains(where: { $0.hasPrefix(name + ".") }) else {
            return nil
        }
        // Use ViewModel's color which is deterministic based on variable name
        return viewModel.colorFor(name, index: 0, palette: chartColorPalette)
    }

    private var sidebarSections: [VariableSectionConfig] {
        guard let file = viewModel.cdfFile else { return [] }
        return [
            VariableSectionConfig(
                title: "Time Variable",
                variables: file.timestampVariables(),
                selectionMode: .single
            ),
            VariableSectionConfig(
                title: "Data Variables",
                variables: file.numericVariables(),
                selectionMode: .multi
            )
        ]
    }

    var body: some View {
        if viewModel.cdfFile != nil {
            VariableSidebarView(
                singleSelection: $viewModel.tableTimeVariable,
                multiSelection: $viewModel.tableSelectedComponents,
                sections: sidebarSections,
                showDataTypeInfo: true,
                colorForKey: colorForVariable,
                loadingKeys: viewModel.loadingComponents,
                viewModel: viewModel,
                showPositionalToggle: false
            )
        } else {
            ContentUnavailableView(
                "No File Loaded",
                systemImage: "doc.badge.plus",
                description: Text("Open a CDF file to view its variables")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    VariableListView(viewModel: CDFViewModel())
        .frame(width: 280)
}
