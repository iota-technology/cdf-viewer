import SwiftUI

/// Displays constant variables as a vertically scrollable grid of cards
struct ConstantsGridView: View {
    @Bindable var viewModel: CDFViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16, alignment: .top)
    ]

    var body: some View {
        if viewModel.constantValues.isEmpty {
            if viewModel.isLoadingData {
                ProgressView("Loading constants...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Constants Selected",
                    systemImage: "equal.circle",
                    description: Text("Select constants from the sidebar to view their values")
                )
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(viewModel.constantValues) { constant in
                        ConstantCard(constant: constant, viewModel: viewModel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
        }
    }
}
