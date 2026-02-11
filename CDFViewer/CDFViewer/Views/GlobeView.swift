import SwiftUI
import SceneKit

/// Helper to access and configure NSWindow from SwiftUI
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

struct GlobeView: View {
    @Bindable var viewModel: CDFViewModel

    // Selection state (matching Chart view pattern)
    @State private var selectedTimeVariable: CDFVariable?
    @State private var selectedPositionVariables: Set<String> = []  // Variable names

    // Globe data - supports multiple tracks
    @State private var tracks: [String: [(x: Double, y: Double, z: Double)]] = [:]  // varName -> positions
    @State private var timestamps: [Date] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scene: SCNScene?
    @State private var trackNodes: [String: SCNNode] = [:]  // varName -> track node
    @State private var trackVerticesCache: [String: [SCNVector3]] = [:]  // varName -> vertices
    @State private var gapIndices: Set<Int> = []  // Indices where there's a gap in data
    @State private var speedMultiplier: Double = 600.0
    @State private var lastExternalProgress: Double = 1.0  // Track external changes

    // Earth material manager for seasonal textures and day/night cycle
    @State private var earthMaterial = EarthMaterial()

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

    // Sidebar visibility
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let sidebarWidth: CGFloat = 280  // Approximate sidebar width for scrubber offset

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationSidebarContainer {
                sidebarView
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 400)
        } detail: {
            // Interactive SceneView in detail area - receives mouse events
            if let scene = scene {
                SceneView(
                    scene: scene,
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .background(Color.black)
                .overlay(alignment: .bottom) {
                    scrubberControls
                }
            } else {
                Color.black
            }
        }
        .background {
            // Visual-only full-bleed background (same scene, syncs camera via shared SCNScene)
            sceneOnlyView
                .ignoresSafeArea()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sidebarToggleToolbar()
        .toolbar(removing: .sidebarToggle)
        .navigationTitle("3D Globe")
        .focusable()
        .background {
            // Force dark titlebar appearance for white title text
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                // Force titlebar to use dark appearance (white text)
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
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
            if viewModel.isAnimating && abs(newValue - lastExternalProgress) > 0.001 {
                // External change detected (from table/chart hover or slider drag)
                viewModel.isAnimating = false
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
            if isPaused && viewModel.isAnimating {
                viewModel.isAnimating = false
            }
        }
        .onChange(of: viewModel.variableOverrides) { _, _ in
            updateTrackColors()
        }
        .onChange(of: currentTimestamp) { _, newTimestamp in
            updateSunPosition(for: newTimestamp)
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
            disabledReason: { variable in
                // Time variables are never disabled, no reason needed
                if viewModel.cdfFile?.timestampVariables().contains(where: { $0.name == variable.name }) ?? false {
                    return nil
                }
                // Non-3vecs can't be positions
                if !variable.isVector {
                    return "This variable is not interpretable as a geocentric position."
                }
                // 3-vecs that aren't marked as positional
                if !viewModel.isPositional(variable) {
                    return "This variable has not been selected as a geocentric position. This can be toggled in the variable's info pane."
                }
                return nil
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
                        if viewModel.isCursorPaused && !viewModel.isAnimating {
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

    // MARK: - Scene View (Full-bleed background)

    /// Visual-only SceneView for full-bleed background effect
    /// Shares the same SCNScene as the interactive detail view, so camera changes sync
    @ViewBuilder
    private var sceneOnlyView: some View {
        if let scene = scene {
            SceneView(
                scene: scene,
                options: [.autoenablesDefaultLighting]  // No camera control - just visual
            )
            .background(Color.black)
            .allowsHitTesting(false)
        } else {
            Color.black
        }
    }

    // MARK: - Scrubber Controls

    /// QuickTime-style scrubber overlay at the bottom
    @ViewBuilder
    private var scrubberControls: some View {
        if !tracks.isEmpty {
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
                        Image(systemName: viewModel.isAnimating ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)

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

    // MARK: - Scene Creation

    private func createInitialScene() -> SCNScene {
        let newScene = SCNScene()

        // Background
        newScene.background.contents = NSColor.black

        // Star sphere - large sphere with star map texture on the inside
        let starRadius: CGFloat = 500.0  // Very large, far behind everything
        let starGeometry = SCNSphere(radius: starRadius)
        starGeometry.segmentCount = 48  // Lower detail is fine for background

        let starMaterial = SCNMaterial()
        if let starTexture = Bundle.main.url(forResource: "starmap_4k", withExtension: "jpg"),
           let starImage = NSImage(contentsOf: starTexture) {
            starMaterial.emission.contents = starImage  // Emission so it glows without lighting
            starMaterial.emission.intensity = 1.0
        }
        starMaterial.diffuse.contents = NSColor.black
        starMaterial.lightingModel = .constant  // No lighting calculations needed
        starMaterial.isDoubleSided = true  // Render on inside
        starGeometry.materials = [starMaterial]

        let starNode = SCNNode(geometry: starGeometry)
        starNode.name = "stars"
        // Flip scale to render texture on inside of sphere
        starNode.scale = SCNVector3(-1, 1, 1)
        // Set initial rotation based on sidereal time
        let starDate = currentTimestamp ?? Date()
        let starRotation = EarthMaterial.starSphereRotation(for: starDate)
        starNode.eulerAngles = SCNVector3(0, starRotation, 0)
        newScene.rootNode.addChildNode(starNode)

        // Earth sphere
        let earthRadius = earthRadiusKm * metersToSceneUnits * 1000
        let earthGeometry = SCNSphere(radius: CGFloat(earthRadius))

        // Earth material with seasonal textures
        let currentDate = currentTimestamp ?? Date()
        let material = earthMaterial.createMaterial(for: currentDate)
        earthGeometry.materials = [material]

        let earthNode = SCNNode(geometry: earthGeometry)
        earthNode.name = "earth"
        newScene.rootNode.addChildNode(earthNode)

        // Camera - standard position, globe centered at origin
        // Note: Globe centering in visible area is handled by the SceneView being in the detail area
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 600  // Must be > star sphere radius (500)
        cameraNode.position = SCNVector3(x: 0, y: 0, z: earthRadius * 3)
        cameraNode.name = "camera"
        newScene.rootNode.addChildNode(cameraNode)

        // Ambient light - low so night side is dark but city lights show
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 50
        ambientLight.name = "ambientLight"
        newScene.rootNode.addChildNode(ambientLight)

        // Directional light (sun) - very bright for vivid day side
        let sunLight = SCNNode()
        sunLight.light = SCNLight()
        sunLight.light?.type = .directional
        sunLight.light?.intensity = 5000
        let initialDate = currentTimestamp ?? Date()
        sunLight.position = EarthMaterial.sunPosition(for: initialDate)
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

        // Detect gaps in timestamp data
        gapIndices = detectGapIndices()

        // Create geometry for each track
        let sortedVars = selectedPositionVariables.sorted()
        for (index, varName) in sortedVars.enumerated() {
            guard let positions = tracks[varName], positions.count > 1 else { continue }

            // Cache vertices
            let vertices = positions.map { ecefToSceneKit($0.x, $0.y, $0.z) }
            trackVerticesCache[varName] = vertices

            // Create track node (with gaps)
            let color = nsColorForTrack(varName: varName, index: index)
            let node = createTrackNode(vertices: vertices, color: color, name: "track_\(varName)", gapIndices: gapIndices)
            scene.rootNode.addChildNode(node)
            trackNodes[varName] = node

            // Create marker
            let markerNode = createMarkerNode(color: color, name: "marker_\(varName)")
            scene.rootNode.addChildNode(markerNode)
        }

        updateTrackProgress()
    }

    /// Detects indices where there's a gap in the timestamp data
    /// A gap is defined as a time step > 3x the median time step
    private func detectGapIndices() -> Set<Int> {
        guard timestamps.count > 2 else { return [] }

        // Calculate time deltas between consecutive points
        var deltas: [TimeInterval] = []
        for i in 1..<timestamps.count {
            deltas.append(timestamps[i].timeIntervalSince(timestamps[i - 1]))
        }

        // Find median delta
        let sortedDeltas = deltas.sorted()
        let medianDelta = sortedDeltas[sortedDeltas.count / 2]

        // Gap threshold: 3x median (to account for some variation)
        let gapThreshold = medianDelta * 3

        // Find indices where a gap starts (don't draw line from i to i+1)
        var gapIndices: Set<Int> = []
        for (i, delta) in deltas.enumerated() {
            if delta > gapThreshold {
                gapIndices.insert(i)
            }
        }

        return gapIndices
    }

    private func createTrackNode(vertices: [SCNVector3], color: NSColor, name: String, gapIndices: Set<Int> = []) -> SCNNode {
        let vertexSource = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []

        // Create line segments, skipping gaps
        for i in 0..<(vertices.count - 1) {
            if !gapIndices.contains(i) {
                indices.append(Int32(i))
                indices.append(Int32(i + 1))
            }
        }

        let primitiveCount = indices.count / 2
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: primitiveCount,
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

            // Calculate how many segments to show based on progress
            let visibleSegments = max(1, Int(Double(vertices.count - 1) * viewModel.cursorProgress))

            // Recreate geometry with visible segments only, skipping gaps
            var indices: [Int32] = []
            indices.reserveCapacity(visibleSegments * 2)
            for i in 0..<visibleSegments {
                // Skip line segments that cross a gap
                if !gapIndices.contains(i) {
                    indices.append(Int32(i))
                    indices.append(Int32(i + 1))
                }
            }

            let primitiveCount = indices.count / 2
            let vertexSource = SCNGeometrySource(vertices: vertices)
            let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .line,
                primitiveCount: primitiveCount,
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
        gapIndices = []
    }

    /// Updates sun light position, star sphere rotation, and Earth material based on the current timestamp
    private func updateSunPosition(for date: Date?) {
        guard let scene = scene,
              let date = date else { return }

        // Update sun position
        if let sunLight = scene.rootNode.childNode(withName: "sunLight", recursively: false) {
            sunLight.position = EarthMaterial.sunPosition(for: date)
            sunLight.look(at: SCNVector3(0, 0, 0))
        }

        // Update star sphere rotation based on sidereal time
        if let starNode = scene.rootNode.childNode(withName: "stars", recursively: false) {
            let rotation = EarthMaterial.starSphereRotation(for: date)
            // Rotate around Y-axis (Earth's rotation axis in SceneKit coordinates)
            // Negative X scale is preserved; we rotate around Y
            starNode.eulerAngles = SCNVector3(0, rotation, 0)
        }

        // Update Earth material for seasonal blending
        if let earthNode = scene.rootNode.childNode(withName: "earth", recursively: false),
           let material = earthNode.geometry?.firstMaterial {
            earthMaterial.updateMaterial(material, for: date)
        }
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
        viewModel.isAnimating.toggle()

        if viewModel.isAnimating {
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
        guard viewModel.isAnimating else { return }

        let frameInterval: UInt64 = 16_000_000  // ~60fps in nanoseconds

        Task { @MainActor in
            while viewModel.isAnimating && viewModel.cursorProgress < 1.0 {
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
                viewModel.isAnimating = false
                viewModel.isCursorPaused = true
            }
        }
    }
}

#Preview {
    GlobeView(viewModel: CDFViewModel())
        .frame(width: 800, height: 600)
}
