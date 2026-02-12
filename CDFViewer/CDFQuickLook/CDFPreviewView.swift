import SwiftUI

/// QuickLook preview view for CDF files
struct CDFPreviewView: View {
    let fileInfo: CDFFileInfo
    let variables: [CDFVariable]
    let attributes: [CDFAttribute]

    /// Key global attributes to display (in priority order)
    private let keyAttributeNames = [
        "Project", "Source_name", "Mission_group", "Discipline",
        "Data_type", "Descriptor", "Data_version",
        "TEXT", "TITLE", "Acknowledgement"
    ]

    private var keyAttributes: [(name: String, value: String)] {
        let globalAttrs = attributes.filter { $0.isGlobal }
        var result: [(String, String)] = []

        for name in keyAttributeNames {
            if let attr = globalAttrs.first(where: { $0.name.lowercased() == name.lowercased() }),
               let entry = attr.entries.first {
                let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    result.append((attr.name, value))
                }
            }
            // Limit to 4 key attributes to save space
            if result.count >= 4 { break }
        }
        return result
    }

    private var timeVariables: [CDFVariable] {
        variables.filter { $0.isTimestamp }
    }

    private var dataVariables: [CDFVariable] {
        variables.filter { !$0.isTimestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with file info
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Main content in two columns
            HStack(alignment: .top, spacing: 16) {
                // Left column: Variables
                variablesSection
                    .frame(maxWidth: .infinity)

                Divider()

                // Right column: Key attributes + metadata
                VStack(alignment: .leading, spacing: 12) {
                    metadataSection
                    if !keyAttributes.isEmpty {
                        Divider()
                        attributesSection
                    }
                }
                .frame(width: 220)
            }
            .padding(16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileInfo.fileName)
                    .font(.headline)
                    .lineLimit(1)

                Text("NASA Common Data Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fileInfo.fileSizeFormatted)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("\(variables.count) variables")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Variables Section

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Time variables
            if !timeVariables.isEmpty {
                sectionHeader("Time Variables", icon: "clock", count: timeVariables.count)
                variableGrid(timeVariables)
            }

            // Data variables
            if !dataVariables.isEmpty {
                if !timeVariables.isEmpty {
                    Spacer().frame(height: 4)
                }
                sectionHeader("Data Variables", icon: "number", count: dataVariables.count)
                variableGrid(dataVariables)
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func variableGrid(_ vars: [CDFVariable]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], alignment: .leading, spacing: 4) {
            ForEach(vars, id: \.name) { variable in
                variableRow(variable)
            }
        }
    }

    private func variableRow(_ variable: CDFVariable) -> some View {
        HStack(spacing: 6) {
            Image(systemName: variable.iconName)
                .font(.caption2)
                .foregroundStyle(iconColor(for: variable))
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 0) {
                Text(variable.name)
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(variable.dataType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if variable.dimensionString != "scalar" {
                        Text(variable.dimensionString)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let units = variable.units {
                        Text("(\(units))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func iconColor(for variable: CDFVariable) -> Color {
        if variable.isTimestamp {
            return .blue
        } else if variable.isECEFPosition || variable.isECEFVelocity {
            return .green
        } else if variable.isVector {
            return .orange
        } else {
            return .secondary
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("File Details")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                metadataRow("Version", fileInfo.version)
                metadataRow("Encoding", fileInfo.encoding)
                if !fileInfo.copyright.isEmpty {
                    metadataRow("Copyright", fileInfo.copyright)
                }
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
    }

    // MARK: - Attributes Section

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attributes")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(keyAttributes, id: \.name) { attr in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attr.name.replacingOccurrences(of: "_", with: " "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(attr.value)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

#Preview {
    CDFPreviewView(
        fileInfo: CDFFileInfo(
            url: URL(fileURLWithPath: "/test/example_data.cdf"),
            version: "3.9",
            encoding: "IBM PC",
            majority: "Row",
            numVariables: 8,
            numAttributes: 12,
            copyright: "NASA GSFC"
        ),
        variables: [
            CDFVariable(
                name: "Timestamp",
                dataType: .timeTT2000,
                numElements: 1,
                dimensions: [],
                dimVarys: [],
                maxRecord: 86399,
                isZVariable: true,
                vxrOffset: 0,
                cprOffset: 0,
                attributes: [:]
            ),
            CDFVariable(
                name: "ECEF_R",
                dataType: .double,
                numElements: 1,
                dimensions: [3],
                dimVarys: [true],
                maxRecord: 86399,
                isZVariable: true,
                vxrOffset: 0,
                cprOffset: 0,
                attributes: ["UNITS": "m"]
            ),
            CDFVariable(
                name: "ECEF_V",
                dataType: .double,
                numElements: 1,
                dimensions: [3],
                dimVarys: [true],
                maxRecord: 86399,
                isZVariable: true,
                vxrOffset: 0,
                cprOffset: 0,
                attributes: ["UNITS": "m/s"]
            ),
            CDFVariable(
                name: "Temperature",
                dataType: .float,
                numElements: 1,
                dimensions: [],
                dimVarys: [],
                maxRecord: 86399,
                isZVariable: true,
                vxrOffset: 0,
                cprOffset: 0,
                attributes: ["UNITS": "K"]
            )
        ],
        attributes: [
            CDFAttribute(
                name: "Project",
                isGlobal: true,
                entries: [CDFAttributeEntry(entryNum: 0, dataType: .char, value: "NASA Heliophysics")]
            ),
            CDFAttribute(
                name: "Source_name",
                isGlobal: true,
                entries: [CDFAttributeEntry(entryNum: 0, dataType: .char, value: "GOES-16")]
            )
        ]
    )
    .frame(width: 600, height: 400)
}
