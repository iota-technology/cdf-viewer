import SwiftUI
import SceneKit

struct GlobeView: View {
    @Bindable var viewModel: CDFViewModel

    // Selection state (matching Chart view pattern)
    @State private var selectedTimeVariable: CDFVariable?
    @State private var selectedPositionVariables: Set<String> = []  // Variable names

    // Sidebar visibility (Photos-style toggle)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Globe data - supports multiple tracks
    @State private var tracks: [String: [(x: Double, y: Double, z: Double)]] = [:]  // varName -> positions
    @State private var timestamps: [Date] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isAnimating = false
    @State private var scene: SCNScene?
    @State private var trackNodes: [String: SCNNode] = [:]  // varName -> track node
    @State private var trackVerticesCache: [String: [SCNVector3]] = [:]  // varName -> vertices
    @State private var speedMultiplier: Double = 600.0
    @State private var lastExternalProgress: Double = 1.0  // Track external changes

    private let speedOptions: [(label: String, value: Double)] = [
        ("60×", 60),
        ("300×", 300),
        ("600×", 600),
        ("1200×", 1200),
        ("3600×", 3600)
    ]

    // Scale factor: Earth radius ~6371 km, positions in meters
    private let earthRadiusKm: Double = 6371.0
    private let metersToSceneUnits: Double = 1.0 / 1_000_000.0  // 1 scene unit = 1000 km

    /// Set of positional variable names for fast lookup (respects user overrides)
    private var positionalVariableNames: Set<String> {
        guard let file = viewModel.cdfFile else { return [] }
        return Set(file.numericVariables().filter { viewModel.isPositional($0) }.map { $0.name })
    }

    /// Current timestamp based on cursor progress
    private var currentTimestamp: Date? {
        guard !timestamps.isEmpty else { return nil }
        let index = max(0, Int(Double(timestamps.count - 1) * viewModel.cursorProgress))
        return timestamps[index]
    }

    /// Total positions across all tracks (for track info display)
    private var totalPositions: Int {
        tracks.values.first?.count ?? 0
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationSidebarContainer(sidebarBackground: .black) {
                sidebarView
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 400)
        } detail: {
            globeAreaView
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sidebarToggleToolbar()
        .toolbar(removing: .sidebarToggle)
        .onAppear {
            setupInitialSelection()
        }
        .onChange(of: selectedPositionVariables) { _, _ in
            loadPositions()
        }
        .onChange(of: viewModel.cursorProgress) { oldValue, newValue in
            updateMarkerPositions()
            updateTrackProgress()

            // If progress changed externally (not from our animation), stop animating
            if isAnimating && abs(newValue - lastExternalProgress) > 0.001 {
                // External change detected (from table/chart hover or slider drag)
                isAnimating = false
            }
            lastExternalProgress = newValue
        }
        .onChange(of: tracks.count) {
            createTrackGeometries()
            updateMarkerPositions()
            updateTrackProgress()
        }
        .onChange(of: viewModel.isCursorPaused) { _, isPaused in
            // If cursor was paused externally (from table/chart click), stop our animation
            if isPaused && isAnimating {
                isAnimating = false
            }
        }
        .onChange(of: viewModel.variableOverrides) { _, _ in
            updateTrackColors()
        }
        .onKeyPress(.space) {
            if !tracks.isEmpty {
                toggleAnimation()
                return .handled
            }
            return .ignored
        }
        .focusable()
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VariableSidebarView(
            singleSelection: $selectedTimeVariable,
            multiSelection: $selectedPositionVariables,
            sections: sidebarSections,
            showDataTypeInfo: true,
            expandVectors: false,  // Globe shows whole vectors, not X/Y/Z components
            isDisabled: { variable in
                // Disable non-ECEF variables in the Position section
                // (Time variables are never disabled)
                !viewModel.isPositional(variable) &&
                !(viewModel.cdfFile?.timestampVariables().contains(where: { $0.name == variable.name }) ?? false)
            },
            colorForKey: trackColor,
            viewModel: viewModel,
            showPositionalToggle: true,
            singleSelectionTrailing: { variable in
                // Show timestamp for selected time variable
                if selectedTimeVariable == variable, let date = currentTimestamp {
                    HStack(spacing: 4) {
                        Text(date, format: .dateTime.month().day().hour().minute().second())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if viewModel.isCursorPaused && !isAnimating {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        )
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
                title: "Position Variables",
                variables: file.numericVariables(),
                selectionMode: .multi
            )
        ]
    }

    /// Get track color by variable name (for sidebar indicator)
    /// Only returns a color if the variable is selected
    private func trackColor(for name: String) -> Color? {
        // Only show color indicator if this variable is selected
        guard selectedPositionVariables.contains(name) else { return nil }
        let sortedVars = Array(selectedPositionVariables.sorted())
        let index = sortedVars.firstIndex(of: name) ?? 0
        // Use custom color from metadata if set, otherwise use default color for variable
        return viewModel.colorFor(name, index: index, palette: trackColorPalette)
    }

    /// Colors for multiple tracks
    private var trackColorPalette: [Color] {
        [.yellow, .cyan, .green, .orange, .pink, .purple]
    }

    private func setupInitialSelection() {
        guard let file = viewModel.cdfFile else { return }

        // Select first time variable
        selectedTimeVariable = file.timestampVariables().first

        // Only pre-select ECEF variable if there's exactly one
        let posVars = file.ecefPositionVariables()
        if posVars.count == 1, let onlyPos = posVars.first {
            selectedPositionVariables.insert(onlyPos.name)
        }

        // Create initial scene
        if scene == nil {
            scene = createInitialScene()
        }

        // If nothing selected, ensure no tracks are shown
        if selectedPositionVariables.isEmpty {
            clearAllTracks()
        }
    }

    // MARK: - Globe Area

    private var globeAreaView: some View {
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
                    if !tracks.isEmpty {
                        // QuickTime-style scrubber overlay
                        VStack(spacing: 8) {
                            // Timestamp display
                            if let currentDate = currentTimestamp {
                                Text(currentDate, format: .dateTime.year().month().day().hour().minute())
                                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 2)
                            }

                            // Scrubber controls
                            HStack(spacing: 12) {
                                // Play/Pause button
                                Button {
                                    toggleAnimation()
                                } label: {
                                    Image(systemName: isAnimating ? "pause.fill" : "play.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)

                                // Pause indicator (synced with table/chart)
                                if viewModel.isCursorPaused && !isAnimating {
                                    Image(systemName: "pause.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                // Scrubber slider - bound to shared cursor progress
                                Slider(value: $viewModel.cursorProgress, in: 0...1)
                                    .tint(viewModel.isCursorPaused ? .orange : .white)
                                    .frame(minWidth: 200)

                                // Speed picker
                                Menu {
                                    ForEach(speedOptions, id: \.value) { option in
                                        Button {
                                            speedMultiplier = option.value
                                        } label: {
                                            HStack {
                                                Text(option.label)
                                                if speedMultiplier == option.value {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text(speedOptions.first { $0.value == speedMultiplier }?.label ?? "\(Int(speedMultiplier))×")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .frame(width: 60)
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.bottom, 20)
                        .padding(.horizontal, 20)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Track Loaded",
                    systemImage: "globe",
                    description: Text("Select a position variable to load the track")
                )
            }
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

    /// Creates track geometries for all selected position variables
    private func createTrackGeometries() {
        guard let scene = scene else { return }

        // Remove existing tracks and markers
        for (varName, _) in trackNodes {
            scene.rootNode.childNode(withName: "track_\(varName)", recursively: false)?.removeFromParentNode()
            scene.rootNode.childNode(withName: "marker_\(varName)", recursively: false)?.removeFromParentNode()
        }
        trackNodes = [:]
        trackVerticesCache = [:]

        // Create geometry for each track
        let sortedVars = selectedPositionVariables.sorted()
        for (index, varName) in sortedVars.enumerated() {
            guard let positions = tracks[varName], positions.count > 1 else { continue }

            // Cache vertices
            let vertices = positions.map { ecefToSceneKit($0.x, $0.y, $0.z) }
            trackVerticesCache[varName] = vertices

            // Create track node
            let color = nsColorForTrack(varName: varName, index: index)
            let node = createTrackNode(vertices: vertices, color: color, name: "track_\(varName)")
            scene.rootNode.addChildNode(node)
            trackNodes[varName] = node

            // Create marker
            let markerNode = createMarkerNode(color: color, name: "marker_\(varName)")
            scene.rootNode.addChildNode(markerNode)
        }

        updateTrackProgress()
    }

    private func createTrackNode(vertices: [SCNVector3], color: NSColor, name: String) -> SCNNode {
        let vertexSource = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in 0..<(vertices.count - 1) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: vertices.count - 1,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = name
        return node
    }

    private func createMarkerNode(color: NSColor, name: String) -> SCNNode {
        let markerGeometry = SCNSphere(radius: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        markerGeometry.materials = [material]

        let node = SCNNode(geometry: markerGeometry)
        node.name = name
        return node
    }

    private func nsColorForTrack(varName: String, index: Int) -> NSColor {
        // Use custom color from metadata if set
        let swiftColor = viewModel.colorFor(varName, index: index, palette: trackColorPalette)
        return NSColor(swiftColor)
    }

    /// Updates track and marker colors when metadata changes
    private func updateTrackColors() {
        guard let scene = scene else { return }

        let sortedVars = selectedPositionVariables.sorted()
        for (index, varName) in sortedVars.enumerated() {
            let color = nsColorForTrack(varName: varName, index: index)

            // Update track color
            if let trackNode = scene.rootNode.childNode(withName: "track_\(varName)", recursively: false),
               let material = trackNode.geometry?.firstMaterial {
                material.diffuse.contents = color
                material.emission.contents = color
            }

            // Update marker color
            if let markerNode = scene.rootNode.childNode(withName: "marker_\(varName)", recursively: false),
               let material = markerNode.geometry?.firstMaterial {
                material.diffuse.contents = color
                material.emission.contents = color
            }
        }
    }

    /// Updates track visibility based on current progress
    private func updateTrackProgress() {
        guard let scene = scene else { return }

        for (varName, vertices) in trackVerticesCache {
            guard vertices.count > 1,
                  let trackNode = trackNodes[varName] else { continue }

            // Calculate how many segments to show
            let visibleSegments = max(1, Int(Double(vertices.count - 1) * viewModel.cursorProgress))

            // Recreate geometry with visible segments only
            var indices: [Int32] = []
            indices.reserveCapacity(visibleSegments * 2)
            for i in 0..<visibleSegments {
                indices.append(Int32(i))
                indices.append(Int32(i + 1))
            }

            let vertexSource = SCNGeometrySource(vertices: vertices)
            let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .line,
                primitiveCount: visibleSegments,
                bytesPerIndex: MemoryLayout<Int32>.size
            )

            let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
            geometry.materials = trackNode.geometry?.materials ?? []
            trackNode.geometry = geometry
        }
    }

    /// Updates marker positions for all tracks
    private func updateMarkerPositions() {
        guard let scene = scene else { return }

        for (varName, positions) in tracks {
            guard !positions.isEmpty else { continue }

            let index = max(0, Int(Double(positions.count - 1) * viewModel.cursorProgress))
            let currentPos = positions[index]
            let scenePos = ecefToSceneKit(currentPos.x, currentPos.y, currentPos.z)

            if let markerNode = scene.rootNode.childNode(withName: "marker_\(varName)", recursively: false) {
                markerNode.position = scenePos
            }
        }
    }

    /// Removes all track and marker nodes from the scene
    private func clearAllTracks() {
        guard let scene = scene else { return }

        // Remove ALL track and marker nodes by name pattern
        // This is more robust than relying on trackNodes dictionary
        scene.rootNode.childNodes.filter {
            $0.name?.hasPrefix("track_") == true || $0.name?.hasPrefix("marker_") == true
        }.forEach { $0.removeFromParentNode() }

        // Clear caches
        trackNodes = [:]
        trackVerticesCache = [:]
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
        guard let file = viewModel.cdfFile else { return }

        // Filter to only positional variables that are selected
        let selectedPosVars = selectedPositionVariables.filter { positionalVariableNames.contains($0) }
        guard !selectedPosVars.isEmpty else {
            // Clear all tracks and remove from scene
            tracks = [:]
            timestamps = []
            clearAllTracks()
            return
        }

        isLoading = true
        errorMessage = nil
        tracks = [:]
        timestamps = []

        Task { @MainActor in
            do {
                // Load positions for each selected variable
                var newTracks: [String: [(x: Double, y: Double, z: Double)]] = [:]

                for varName in selectedPosVars {
                    guard let posVar = file.variables.first(where: { $0.name == varName }) else { continue }
                    let positions = try file.readECEFPositions(for: posVar)
                    newTracks[varName] = positions
                }

                tracks = newTracks

                // Load timestamps from selected time variable (or first available)
                let timeVar = selectedTimeVariable ?? file.timestampVariables().first
                if let timeVar = timeVar {
                    let timeValues = try file.readTimestamps(for: timeVar)
                    // Use the length of the first track for matching
                    let posCount = tracks.values.first?.count ?? timeValues.count
                    let count = min(timeValues.count, posCount)
                    timestamps = timeValues.prefix(count).map { Date(timeIntervalSince1970: $0) }
                }

                viewModel.cursorProgress = 1.0
                lastExternalProgress = 1.0
                isLoading = false

                // Trigger geometry creation
                createTrackGeometries()
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
            // If at the end, restart from beginning
            if viewModel.cursorProgress >= 1.0 {
                viewModel.cursorProgress = 0
            }
            // Unfreeze the cursor when animation starts
            viewModel.isCursorPaused = false
            startAnimation()
        } else {
            // Pause the cursor when animation stops
            viewModel.isCursorPaused = true
        }
    }

    /// Total duration of the track in seconds (from timestamps)
    private var trackDuration: TimeInterval {
        if timestamps.count >= 2,
           let first = timestamps.first,
           let last = timestamps.last {
            return last.timeIntervalSince(first)
        }
        // Fallback: assume 90 minutes if no timestamps
        return 90 * 60
    }

    private func startAnimation() {
        guard isAnimating else { return }

        let frameInterval: UInt64 = 16_000_000  // ~60fps in nanoseconds

        Task { @MainActor in
            while isAnimating && viewModel.cursorProgress < 1.0 {
                try? await Task.sleep(nanoseconds: frameInterval)
                // Recalculate each frame in case speed changed during animation
                // At speedMultiplier×, animation completes in (trackDuration / speedMultiplier) seconds
                let animationDuration = trackDuration / speedMultiplier
                let progressPerFrame = 1.0 / (animationDuration * 60.0)  // 60 fps
                let newProgress = min(1.0, viewModel.cursorProgress + progressPerFrame)
                viewModel.cursorProgress = newProgress
                lastExternalProgress = newProgress  // Track our own updates
            }
            if viewModel.cursorProgress >= 1.0 {
                isAnimating = false
                viewModel.isCursorPaused = true
            }
        }
    }
}

#Preview {
    GlobeView(viewModel: CDFViewModel())
        .frame(width: 800, height: 600)
}
