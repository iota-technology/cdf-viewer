import SwiftUI
import SceneKit

struct GlobeView: View {
    @Bindable var viewModel: CDFViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPositionVariable: CDFVariable?
    @State private var positions: [(x: Double, y: Double, z: Double)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showTrack = true
    @State private var showPoints = true
    @State private var animationProgress: Double = 1.0
    @State private var isAnimating = false

    // Scale factor: Earth radius ~6371 km, positions in meters
    private let earthRadiusKm: Double = 6371.0
    private let metersToSceneUnits: Double = 1.0 / 1_000_000.0  // 1 scene unit = 1000 km

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("3D Globe View")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(.bar)

            Divider()

            HSplitView {
                // Controls sidebar
                VStack(alignment: .leading, spacing: 16) {
                    // Position variable selector
                    GroupBox("ECEF Position Variable") {
                        if let file = viewModel.cdfFile {
                            Picker("Position", selection: $selectedPositionVariable) {
                                Text("Select...").tag(nil as CDFVariable?)
                                ForEach(file.ecefPositionVariables()) { variable in
                                    Text(variable.name).tag(variable as CDFVariable?)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // Load button
                    Button(action: loadPositions) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Load Track", systemImage: "globe")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPositionVariable == nil || isLoading)

                    Divider()

                    // Display options
                    GroupBox("Display Options") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show Track Line", isOn: $showTrack)
                            Toggle("Show Points", isOn: $showPoints)
                        }
                    }

                    // Animation controls
                    if !positions.isEmpty {
                        GroupBox("Animation") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button(isAnimating ? "Stop" : "Play") {
                                        toggleAnimation()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Reset") {
                                        animationProgress = 1.0
                                        isAnimating = false
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Slider(value: $animationProgress, in: 0...1)

                                Text("\(Int(animationProgress * 100))% of track")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Stats
                    if !positions.isEmpty {
                        GroupBox("Track Info") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(positions.count) points")
                                if let first = positions.first, let last = positions.last {
                                    let startAlt = altitude(x: first.x, y: first.y, z: first.z)
                                    let endAlt = altitude(x: last.x, y: last.y, z: last.z)
                                    Text("Start altitude: \(formatKm(startAlt))")
                                    Text("End altitude: \(formatKm(endAlt))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(width: 220)

                // 3D Scene
                VStack {
                    if let error = errorMessage {
                        ContentUnavailableView(
                            "Error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else {
                        SceneView(
                            scene: createScene(),
                            options: [.allowsCameraControl, .autoenablesDefaultLighting]
                        )
                        .background(Color.black)
                    }
                }
            }
        }
        .onAppear {
            selectedPositionVariable = viewModel.cdfFile?.ecefPositionVariables().first
        }
    }

    // MARK: - Scene Creation

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        // Background
        scene.background.contents = NSColor.black

        // Earth sphere
        let earthRadius = earthRadiusKm * metersToSceneUnits * 1000  // Convert to scene units
        let earthGeometry = SCNSphere(radius: CGFloat(earthRadius))

        // Earth material with texture
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = createEarthTexture()
        earthMaterial.specular.contents = NSColor.gray
        earthMaterial.shininess = 0.1
        earthGeometry.materials = [earthMaterial]

        let earthNode = SCNNode(geometry: earthGeometry)
        earthNode.name = "earth"
        scene.rootNode.addChildNode(earthNode)

        // Add satellite track if we have positions
        if !positions.isEmpty {
            let visibleCount = Int(Double(positions.count) * animationProgress)
            let visiblePositions = Array(positions.prefix(visibleCount))

            if showTrack && visiblePositions.count > 1 {
                addTrackLine(to: scene, positions: visiblePositions)
            }

            if showPoints {
                addTrackPoints(to: scene, positions: visiblePositions)
            }

            // Current position marker
            if let current = visiblePositions.last {
                addCurrentPositionMarker(to: scene, position: current)
            }
        }

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 1000
        cameraNode.position = SCNVector3(x: 0, y: 0, z: earthRadius * 3)
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        scene.rootNode.addChildNode(ambientLight)

        // Directional light (sun)
        let sunLight = SCNNode()
        sunLight.light = SCNLight()
        sunLight.light?.type = .directional
        sunLight.light?.intensity = 1000
        sunLight.position = SCNVector3(x: 100, y: 100, z: 100)
        sunLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sunLight)

        return scene
    }

    private func createEarthTexture() -> NSImage {
        // Create a simple Earth-like texture with continents
        // In a real app, you'd load a high-res texture file
        let size = NSSize(width: 1024, height: 512)
        let image = NSImage(size: size)

        image.lockFocus()

        // Ocean blue
        NSColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()

        // Simple continent shapes (rough approximations)
        NSColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0).setFill()

        // North America
        let na = NSBezierPath()
        na.move(to: NSPoint(x: 100, y: 350))
        na.line(to: NSPoint(x: 200, y: 400))
        na.line(to: NSPoint(x: 280, y: 350))
        na.line(to: NSPoint(x: 250, y: 280))
        na.line(to: NSPoint(x: 150, y: 250))
        na.close()
        na.fill()

        // South America
        let sa = NSBezierPath()
        sa.move(to: NSPoint(x: 220, y: 200))
        sa.line(to: NSPoint(x: 280, y: 220))
        sa.line(to: NSPoint(x: 260, y: 100))
        sa.line(to: NSPoint(x: 220, y: 50))
        sa.line(to: NSPoint(x: 200, y: 120))
        sa.close()
        sa.fill()

        // Europe/Africa
        let af = NSBezierPath()
        af.move(to: NSPoint(x: 480, y: 350))
        af.line(to: NSPoint(x: 560, y: 380))
        af.line(to: NSPoint(x: 580, y: 300))
        af.line(to: NSPoint(x: 540, y: 150))
        af.line(to: NSPoint(x: 480, y: 180))
        af.line(to: NSPoint(x: 460, y: 280))
        af.close()
        af.fill()

        // Asia
        let asia = NSBezierPath()
        asia.move(to: NSPoint(x: 580, y: 380))
        asia.line(to: NSPoint(x: 800, y: 400))
        asia.line(to: NSPoint(x: 850, y: 320))
        asia.line(to: NSPoint(x: 750, y: 280))
        asia.line(to: NSPoint(x: 650, y: 300))
        asia.close()
        asia.fill()

        // Australia
        let aus = NSBezierPath()
        aus.move(to: NSPoint(x: 800, y: 150))
        aus.line(to: NSPoint(x: 880, y: 160))
        aus.line(to: NSPoint(x: 870, y: 100))
        aus.line(to: NSPoint(x: 800, y: 90))
        aus.close()
        aus.fill()

        image.unlockFocus()

        return image
    }

    private func addTrackLine(to scene: SCNScene, positions: [(x: Double, y: Double, z: Double)]) {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for (index, pos) in positions.enumerated() {
            let scenePos = ecefToSceneKit(pos.x, pos.y, pos.z)
            vertices.append(scenePos)

            if index > 0 {
                indices.append(Int32(index - 1))
                indices.append(Int32(index))
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = NSColor.yellow
        material.emission.contents = NSColor.yellow
        material.lightingModel = .constant
        geometry.materials = [material]

        let lineNode = SCNNode(geometry: geometry)
        lineNode.name = "track"
        scene.rootNode.addChildNode(lineNode)
    }

    private func addTrackPoints(to scene: SCNScene, positions: [(x: Double, y: Double, z: Double)]) {
        // Add points every N positions to avoid too many objects
        let step = max(1, positions.count / 100)

        for (index, pos) in positions.enumerated() where index % step == 0 {
            let scenePos = ecefToSceneKit(pos.x, pos.y, pos.z)

            let pointGeometry = SCNSphere(radius: 0.02)
            let material = SCNMaterial()
            material.diffuse.contents = NSColor.cyan
            material.emission.contents = NSColor.cyan.withAlphaComponent(0.5)
            pointGeometry.materials = [material]

            let pointNode = SCNNode(geometry: pointGeometry)
            pointNode.position = scenePos
            pointNode.name = "point_\(index)"
            scene.rootNode.addChildNode(pointNode)
        }
    }

    private func addCurrentPositionMarker(to scene: SCNScene, position: (x: Double, y: Double, z: Double)) {
        let scenePos = ecefToSceneKit(position.x, position.y, position.z)

        // Larger marker for current position
        let markerGeometry = SCNSphere(radius: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.red
        material.emission.contents = NSColor.red
        markerGeometry.materials = [material]

        let markerNode = SCNNode(geometry: markerGeometry)
        markerNode.position = scenePos
        markerNode.name = "current"
        scene.rootNode.addChildNode(markerNode)
    }

    // MARK: - Coordinate Conversion

    private func ecefToSceneKit(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        // ECEF coordinates are in meters
        // SceneKit Y is up, but ECEF Z is up (through north pole)
        // So we swap Y and Z
        let scale = metersToSceneUnits
        return SCNVector3(
            Float(x * scale),
            Float(z * scale),   // ECEF Z -> SceneKit Y
            Float(-y * scale)   // ECEF Y -> SceneKit -Z (right-handed)
        )
    }

    private func altitude(x: Double, y: Double, z: Double) -> Double {
        let r = sqrt(x * x + y * y + z * z)
        return (r - earthRadiusKm * 1000) / 1000  // Return in km
    }

    private func formatKm(_ km: Double) -> String {
        return String(format: "%.1f km", km)
    }

    // MARK: - Data Loading

    private func loadPositions() {
        guard let file = viewModel.cdfFile,
              let posVar = selectedPositionVariable else { return }

        isLoading = true
        errorMessage = nil
        positions = []

        Task { @MainActor in
            do {
                positions = try file.readECEFPositions(for: posVar)
                animationProgress = 1.0
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Animation

    private func toggleAnimation() {
        isAnimating.toggle()

        if isAnimating {
            animationProgress = 0
            startAnimation()
        }
    }

    private func startAnimation() {
        guard isAnimating else { return }

        Task { @MainActor in
            while isAnimating && animationProgress < 1.0 {
                try? await Task.sleep(nanoseconds: 16_000_000)  // ~60fps
                animationProgress = min(1.0, animationProgress + 0.002)
            }
            if animationProgress >= 1.0 {
                isAnimating = false
            }
        }
    }
}

#Preview {
    GlobeView(viewModel: CDFViewModel())
        .frame(width: 800, height: 600)
}
