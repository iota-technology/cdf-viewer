import SwiftUI
import SceneKit

struct GlobeView: View {
    @Bindable var viewModel: CDFViewModel

    @State private var selectedPositionVariable: CDFVariable?
    @State private var positions: [(x: Double, y: Double, z: Double)] = []
    @State private var timestamps: [Date] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var animationProgress: Double = 1.0
    @State private var isAnimating = false
    @State private var scene: SCNScene?
    @State private var lastTrackUpdateProgress: Double = 0.0

    // Scale factor: Earth radius ~6371 km, positions in meters
    private let earthRadiusKm: Double = 6371.0
    private let metersToSceneUnits: Double = 1.0 / 1_000_000.0  // 1 scene unit = 1000 km

    /// Current timestamp based on animation progress
    private var currentTimestamp: Date? {
        guard !timestamps.isEmpty else { return nil }
        let index = max(0, Int(Double(timestamps.count - 1) * animationProgress))
        return timestamps[index]
    }

    var body: some View {
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
                    } else if let scene = scene {
                        SceneView(
                            scene: scene,
                            options: [.allowsCameraControl, .autoenablesDefaultLighting]
                        )
                        .background(Color.black)
                        .overlay(alignment: .bottom) {
                            if let currentDate = currentTimestamp {
                                Text(currentDate, format: .dateTime.year().month().day().hour().minute())
                                    .font(.system(size: 24, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 2)
                                    .padding(.bottom, 20)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "No Track Loaded",
                            systemImage: "globe",
                            description: Text("Select a position variable and click Load Track")
                        )
                    }
                }
            }
        .onAppear {
            selectedPositionVariable = viewModel.cdfFile?.ecefPositionVariables().first
            if scene == nil {
                scene = createInitialScene()
            }
        }
        .onChange(of: animationProgress) {
            updateMarkerPosition()
            // Throttle track updates: only rebuild geometry every 2% progress change
            if abs(animationProgress - lastTrackUpdateProgress) >= 0.02 || animationProgress >= 1.0 {
                updateTrackLine()
                lastTrackUpdateProgress = animationProgress
            }
        }
        .onChange(of: positions.count) {
            lastTrackUpdateProgress = 0.0
            updateTrackLine()
            updateMarkerPosition()
        }
    }

    // MARK: - Scene Creation

    private func createInitialScene() -> SCNScene {
        let newScene = SCNScene()

        // Background
        newScene.background.contents = NSColor.black

        // Earth sphere
        let earthRadius = earthRadiusKm * metersToSceneUnits * 1000
        let earthGeometry = SCNSphere(radius: CGFloat(earthRadius))

        // Earth material with texture
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = createEarthTexture()
        earthMaterial.specular.contents = NSColor.gray
        earthMaterial.shininess = 0.1
        earthGeometry.materials = [earthMaterial]

        let earthNode = SCNNode(geometry: earthGeometry)
        earthNode.name = "earth"
        newScene.rootNode.addChildNode(earthNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 1000
        cameraNode.position = SCNVector3(x: 0, y: 0, z: earthRadius * 3)
        cameraNode.name = "camera"
        newScene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        ambientLight.name = "ambientLight"
        newScene.rootNode.addChildNode(ambientLight)

        // Directional light (sun)
        let sunLight = SCNNode()
        sunLight.light = SCNLight()
        sunLight.light?.type = .directional
        sunLight.light?.intensity = 1000
        sunLight.position = SCNVector3(x: 100, y: 100, z: 100)
        sunLight.look(at: SCNVector3(0, 0, 0))
        sunLight.name = "sunLight"
        newScene.rootNode.addChildNode(sunLight)

        return newScene
    }

    /// Updates track line geometry based on current animation progress
    private func updateTrackLine() {
        guard let scene = scene else { return }

        // Remove existing track node
        scene.rootNode.childNode(withName: "track", recursively: false)?.removeFromParentNode()

        // Calculate visible positions based on animation progress
        let visibleCount = max(1, Int(Double(positions.count) * animationProgress))
        let visiblePositions = Array(positions.prefix(visibleCount))

        // Add track if we have enough positions
        guard visiblePositions.count > 1 else { return }

        addTrackLine(to: scene, positions: visiblePositions)
    }

    /// Called during animation - only updates marker position (no geometry recreation)
    private func updateMarkerPosition() {
        guard let scene = scene, !positions.isEmpty else { return }

        // Calculate which position to show
        let index = max(0, Int(Double(positions.count - 1) * animationProgress))
        let currentPos = positions[index]
        let scenePos = ecefToSceneKit(currentPos.x, currentPos.y, currentPos.z)

        // Get or create marker node
        if let markerNode = scene.rootNode.childNode(withName: "current", recursively: false) {
            // Just update position - no node recreation
            markerNode.position = scenePos
        } else {
            // Create marker if it doesn't exist
            addCurrentPositionMarker(to: scene, position: currentPos)
        }
    }

    private func createEarthTexture() -> Any {
        // Load NASA Blue Marble texture
        if let url = Bundle.main.url(forResource: "blue_marble", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // Fallback to simple blue color if texture not found
        return NSColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
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
        timestamps = []

        Task { @MainActor in
            do {
                positions = try file.readECEFPositions(for: posVar)

                // Try to load corresponding timestamps
                if let timeVar = file.timestampVariables().first {
                    let timeValues = try file.readTimestamps(for: timeVar)
                    // Convert to Dates, matching position count
                    let count = min(timeValues.count, positions.count)
                    timestamps = timeValues.prefix(count).map { Date(timeIntervalSince1970: $0) }
                }

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
