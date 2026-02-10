import SwiftUI

struct VariableListView: View {
    @Bindable var viewModel: CDFViewModel

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
