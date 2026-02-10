import SwiftUI

struct VariableListView: View {
    @Bindable var viewModel: CDFViewModel

    private var sections: [(title: String, variables: [CDFVariable])] {
        guard let file = viewModel.cdfFile else { return [] }

        var result: [(title: String, variables: [CDFVariable])] = []

        // Timestamp variables
        let timestampVars = file.timestampVariables()
        if !timestampVars.isEmpty {
            result.append(("Time", timestampVars))
        }

        // Position/Velocity variables
        let ecefVars = file.variables.filter { $0.isECEFPosition || $0.isECEFVelocity }
        if !ecefVars.isEmpty {
            result.append(("Position & Velocity", ecefVars))
        }

        // Other variables
        let otherVars = file.variables.filter {
            !$0.isTimestamp && !$0.isECEFPosition && !$0.isECEFVelocity
        }
        if !otherVars.isEmpty {
            result.append(("Other Variables", otherVars))
        }

        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.cdfFile != nil {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, 8)
                        }

                        sectionView(title: section.title, variables: section.variables, isFirst: index == 0)
                    }
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
        .navigationTitle("Variables")
    }

    @ViewBuilder
    private func sectionView(title: String, variables: [CDFVariable], isFirst: Bool) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, isFirst ? 12 : 0)
            .padding(.bottom, 4)

        ForEach(variables) { variable in
            variableRow(variable)
        }
    }

    private func variableRow(_ variable: CDFVariable) -> some View {
        let isSelected = viewModel.selectedVariable == variable

        return HStack(spacing: 8) {
            Image(systemName: variable.iconName)
                .foregroundStyle(iconColor(for: variable))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(variable.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Text("\(variable.dataType.displayName) [\(variable.recordCount)]")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedVariable = variable
        }
    }

    private func iconColor(for variable: CDFVariable) -> Color {
        if variable.isTimestamp {
            return .blue
        } else if variable.isECEFPosition {
            return .green
        } else if variable.isECEFVelocity {
            return .orange
        } else if variable.isVector {
            return .purple
        } else {
            return .secondary
        }
    }
}

#Preview {
    VariableListView(viewModel: CDFViewModel())
        .frame(width: 250)
}
