import SwiftUI

struct VectorInspectorView: View {
    let row: CDFDataRow
    let variable: CDFVariable
    let columns: [CDFColumn]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Record #\(row.id)")
                        .font(.headline)
                    Text(variable.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 3-Vector visualization
                    if let vector = row.asVector {
                        VectorVisualization(x: vector.x, y: vector.y, z: vector.z)
                            .frame(height: 200)
                            .padding()
                            .background(.fill.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Component values
                    GroupBox("Components") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                                if index < row.values.count {
                                    GridRow {
                                        Text(column.name)
                                            .font(.headline)
                                            .frame(width: 40, alignment: .leading)

                                        Text(row.values[index].stringValue)
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)

                                        // Unit hint based on variable name
                                        Text(unitHint(for: variable, component: column.name))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Magnitude for vectors
                    if let vector = row.asVector {
                        GroupBox("Computed Values") {
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                                GridRow {
                                    Text("Magnitude")
                                        .font(.headline)
                                        .frame(width: 100, alignment: .leading)

                                    let magnitude = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
                                    Text(formatValue(magnitude))
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)

                                    Text(magnitudeUnit(for: variable))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                // For ECEF positions, show lat/lon/alt
                                if variable.isECEFPosition {
                                    let (lat, lon, alt) = ecefToGeodetic(x: vector.x, y: vector.y, z: vector.z)

                                    GridRow {
                                        Text("Latitude")
                                            .font(.headline)
                                            .frame(width: 100, alignment: .leading)
                                        Text(formatDegrees(lat))
                                            .font(.system(.body, design: .monospaced))
                                        Text("")
                                    }

                                    GridRow {
                                        Text("Longitude")
                                            .font(.headline)
                                            .frame(width: 100, alignment: .leading)
                                        Text(formatDegrees(lon))
                                            .font(.system(.body, design: .monospaced))
                                        Text("")
                                    }

                                    GridRow {
                                        Text("Altitude")
                                            .font(.headline)
                                            .frame(width: 100, alignment: .leading)
                                        Text(formatValue(alt / 1000))
                                            .font(.system(.body, design: .monospaced))
                                        Text("km")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }

                    // Raw values for inspection
                    GroupBox("Raw Values") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                                HStack {
                                    Text("[\(index)]")
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 40, alignment: .leading)
                                    Text(value.stringValue)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 600)
    }

    // MARK: - Helpers

    private func unitHint(for variable: CDFVariable, component: String) -> String {
        if variable.isECEFPosition {
            return "m"
        } else if variable.isECEFVelocity {
            return "m/s"
        }
        return ""
    }

    private func magnitudeUnit(for variable: CDFVariable) -> String {
        if variable.isECEFPosition {
            return "m"
        } else if variable.isECEFVelocity {
            return "m/s"
        }
        return ""
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1e6 || (abs(value) < 1e-3 && value != 0) {
            return String(format: "%.6e", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    private func formatDegrees(_ value: Double) -> String {
        let degrees = value * 180.0 / .pi
        return String(format: "%.6f\u{00B0}", degrees)
    }

    // ECEF to Geodetic conversion (WGS84)
    private func ecefToGeodetic(x: Double, y: Double, z: Double) -> (lat: Double, lon: Double, alt: Double) {
        let a = 6378137.0  // WGS84 semi-major axis
        let f = 1.0 / 298.257223563  // WGS84 flattening
        let b = a * (1 - f)
        let e2 = (a * a - b * b) / (a * a)
        let ep2 = (a * a - b * b) / (b * b)

        let p = sqrt(x * x + y * y)
        let lon = atan2(y, x)

        // Iterative calculation for latitude
        var lat = atan2(z, p * (1 - e2))
        for _ in 0..<10 {
            let N = a / sqrt(1 - e2 * sin(lat) * sin(lat))
            lat = atan2(z + e2 * N * sin(lat), p)
        }

        let N = a / sqrt(1 - e2 * sin(lat) * sin(lat))
        let alt = p / cos(lat) - N

        return (lat, lon, alt)
    }
}

// MARK: - Vector Visualization

struct VectorVisualization: View {
    let x: Double
    let y: Double
    let z: Double

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let scale = size * 0.35

            ZStack {
                // Background grid
                Path { path in
                    // Horizontal line
                    path.move(to: CGPoint(x: center.x - scale, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + scale, y: center.y))
                    // Vertical line
                    path.move(to: CGPoint(x: center.x, y: center.y - scale))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + scale))
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                // Axis labels
                Text("X")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .position(x: center.x + scale + 15, y: center.y)

                Text("Y")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .position(x: center.x, y: center.y - scale - 15)

                // Vector arrow (X-Y projection)
                let magnitude = sqrt(x * x + y * y + z * z)
                if magnitude > 0 {
                    let normalizedX = x / magnitude
                    let normalizedY = y / magnitude

                    let endPoint = CGPoint(
                        x: center.x + normalizedX * scale * 0.8,
                        y: center.y - normalizedY * scale * 0.8  // Flip Y for screen coords
                    )

                    // Arrow body
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: endPoint)
                    }
                    .stroke(Color.accentColor, lineWidth: 2)

                    // Arrow head
                    let angle = atan2(center.y - endPoint.y, endPoint.x - center.x)
                    let arrowSize: CGFloat = 10

                    Path { path in
                        path.move(to: endPoint)
                        path.addLine(to: CGPoint(
                            x: endPoint.x - arrowSize * cos(angle - .pi / 6),
                            y: endPoint.y + arrowSize * sin(angle - .pi / 6)
                        ))
                        path.move(to: endPoint)
                        path.addLine(to: CGPoint(
                            x: endPoint.x - arrowSize * cos(angle + .pi / 6),
                            y: endPoint.y + arrowSize * sin(angle + .pi / 6)
                        ))
                    }
                    .stroke(Color.accentColor, lineWidth: 2)
                }

                // Z indicator
                let zNormalized = z / sqrt(x * x + y * y + z * z)
                VStack {
                    Text("Z: \(zNormalized > 0 ? "+" : "")\(String(format: "%.2f", zNormalized))")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .position(x: center.x + scale - 30, y: center.y - scale + 20)
            }
        }
    }
}

#Preview {
    VectorInspectorView(
        row: CDFDataRow(id: 0, values: [.float64(-5436430.0), .float64(-4363540.0), .float64(-14696.4)]),
        variable: CDFVariable(
            name: "r_ecef",
            dataType: .double,
            numElements: 1,
            dimensions: [3],
            dimVarys: [true],
            maxRecord: 86399,
            isZVariable: true,
            vxrOffset: 0,
            cprOffset: 0,
            attributes: [:]
        ),
        columns: [
            CDFColumn(id: 0, name: "X", dataType: .double, width: 120),
            CDFColumn(id: 1, name: "Y", dataType: .double, width: 120),
            CDFColumn(id: 2, name: "Z", dataType: .double, width: 120)
        ]
    )
}
