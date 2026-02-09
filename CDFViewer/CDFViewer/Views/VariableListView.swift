import SwiftUI

struct VariableListView: View {
    @Bindable var viewModel: CDFViewModel

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedVariable },
            set: { viewModel.selectedVariable = $0 }
        )) {
            if let file = viewModel.cdfFile {
                // Timestamp variables
                let timestampVars = file.timestampVariables()
                if !timestampVars.isEmpty {
                    Section("Time") {
                        ForEach(timestampVars) { variable in
                            VariableRow(variable: variable)
                                .tag(variable)
                        }
                    }
                }

                // Position/Velocity variables
                let ecefVars = file.variables.filter { $0.isECEFPosition || $0.isECEFVelocity }
                if !ecefVars.isEmpty {
                    Section("Position & Velocity") {
                        ForEach(ecefVars) { variable in
                            VariableRow(variable: variable)
                                .tag(variable)
                        }
                    }
                }

                // Other numeric variables
                let otherVars = file.variables.filter {
                    !$0.isTimestamp && !$0.isECEFPosition && !$0.isECEFVelocity
                }
                if !otherVars.isEmpty {
                    Section("Other Variables") {
                        ForEach(otherVars) { variable in
                            VariableRow(variable: variable)
                                .tag(variable)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No File Loaded",
                    systemImage: "doc.badge.plus",
                    description: Text("Open a CDF file to view its variables")
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Variables")
    }
}

// MARK: - Variable Row

struct VariableRow: View {
    let variable: CDFVariable

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: variable.iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(variable.name)
                    .lineLimit(1)

                Text(variable.typeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(variable.recordCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
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
