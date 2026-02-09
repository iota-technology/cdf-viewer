import SwiftUI

struct FileInfoView: View {
    let fileInfo: CDFFileInfo
    let attributes: [CDFAttribute]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // File details
                GroupBox("File Details") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("File Name:")
                                .foregroundStyle(.secondary)
                            Text(fileInfo.fileName)
                                .textSelection(.enabled)
                        }

                        GridRow {
                            Text("File Size:")
                                .foregroundStyle(.secondary)
                            Text(fileInfo.fileSizeFormatted)
                        }

                        GridRow {
                            Text("CDF Version:")
                                .foregroundStyle(.secondary)
                            Text(fileInfo.version)
                        }

                        GridRow {
                            Text("Encoding:")
                                .foregroundStyle(.secondary)
                            Text(fileInfo.encoding)
                        }

                        GridRow {
                            Text("Variables:")
                                .foregroundStyle(.secondary)
                            Text("\(fileInfo.numVariables)")
                        }

                        GridRow {
                            Text("Attributes:")
                                .foregroundStyle(.secondary)
                            Text("\(fileInfo.numAttributes)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                // Global attributes
                let globalAttrs = attributes.filter { $0.isGlobal }
                if !globalAttrs.isEmpty {
                    GroupBox("Global Attributes") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(globalAttrs, id: \.name) { attr in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attr.name)
                                        .font(.headline)

                                    ForEach(attr.entries, id: \.entryNum) { entry in
                                        Text(entry.value)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.vertical, 4)

                                if attr.name != globalAttrs.last?.name {
                                    Divider()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }

                // Variable attributes
                let varAttrs = attributes.filter { !$0.isGlobal }
                if !varAttrs.isEmpty {
                    GroupBox("Variable Attributes") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(varAttrs, id: \.name) { attr in
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(attr.entries, id: \.entryNum) { entry in
                                            HStack {
                                                Text("Var \(entry.entryNum):")
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 60, alignment: .leading)
                                                Text(entry.value)
                                                    .textSelection(.enabled)
                                            }
                                            .font(.caption)
                                        }
                                    }
                                    .padding(.leading, 16)
                                } label: {
                                    Text(attr.name)
                                        .font(.headline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }

                // Copyright
                if !fileInfo.copyright.isEmpty {
                    GroupBox("Copyright") {
                        Text(fileInfo.copyright)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FileInfoView(
        fileInfo: CDFFileInfo(
            url: URL(fileURLWithPath: "/test.cdf"),
            version: "3.9.0",
            encoding: "IBMPC",
            majority: "Row",
            numVariables: 4,
            numAttributes: 2,
            copyright: "NASA GSFC"
        ),
        attributes: []
    )
    .frame(width: 400, height: 500)
}
