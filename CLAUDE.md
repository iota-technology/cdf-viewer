# CDF Viewer

macOS app for viewing NASA CDF (Common Data Format) files with data tables, time series charts, and 3D globe visualization.

## Build & Run

```bash
cd CDFViewer
xcodebuild -scheme CDFViewer -configuration Debug build
pkill -x "CDFViewer"; sleep 0.5; open ~/Library/Developer/Xcode/DerivedData/CDFViewer-*/Build/Products/Debug/CDFViewer.app
```

**Important**: Always kill existing instances before opening a new build to ensure changes are visible. The `sleep 0.5` prevents race conditions with macOS app cleanup.

For release builds: `xcodebuild -scheme CDFViewer -configuration Release build`

## Release Process

1. Update `CHANGELOG.md` with new version section (follow Keep a Changelog format)
2. Commit the changelog update
3. Create an annotated tag with release notes from the changelog:

   ```bash
   git tag -a v1.0.0 -m "v1.0.0 - Brief description

   Paste relevant changelog section here"
   ```

4. Push commits and tag:

   ```bash
   git push origin main
   git push origin v1.0.0
   ```

The workflow builds an unsigned app zip and creates a GitHub release using the tag message as release notes.

## Gotchas

**#Preview macro ambiguity**: In macOS SwiftUI apps, `#Preview` blocks with `let` statements before the view cause "ambiguous use of init" errors (AppKit vs SwiftUI). Fix by inlining or using `return`.

```swift
// Bad - ambiguous
#Preview {
    let foo = Foo()
    MyView(foo: foo)
}

// Good
#Preview {
    MyView(foo: Foo())
}
```

**FileDocument temp files**: SwiftUI's `FileDocument` copies files to temp directory with UUID prefixes. To display the original filename, extract it from `configuration.file.filename` and pass it through separately.

**App icons**: macOS Big Sur+ displays all icons in a squircle mask. Design icons to work within this shape or they'll look odd.

**Unsigned app quarantine**: Downloaded unsigned apps get quarantined by macOS, showing "damaged and can't be opened". Users must run `xattr -cr /path/to/App.app` before opening.

**Swift Charts LineMark series**: When plotting multiple data series, you MUST include `series: .value("Series", seriesName)` parameter. Without it, SwiftUI Charts connects all points as one continuous line regardless of foregroundStyle color.

```swift
// Bad - all points connected as one line
LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
    .foregroundStyle(color)

// Good - separate lines per series
LineMark(x: .value("Time", point.date), y: .value("Value", point.value),
         series: .value("Series", series.name))
    .foregroundStyle(color)
```

**Swift Charts hover coordinates**: The `chartOverlay` coordinates include the y-axis label area, but `proxy.value(atX:)` expects plot-area-relative coordinates. You must offset by the plot frame origin:

```swift
.chartOverlay { proxy in
    GeometryReader { geometry in
        Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let location) = phase,
                   let plotFrame = proxy.plotFrame {
                    let plotRect = geometry[plotFrame]
                    let adjustedX = location.x - plotRect.origin.x
                    // Use adjustedX with proxy.value(atX:)
                }
            }
    }
}
```

**Swift Charts RuleMark performance**: Placing `RuleMark` (cursor line) inside `Chart` causes the entire chart to re-render on every cursor position change. With thousands of data points, this causes severe lag. Solution: draw the cursor as a `Path` in `chartOverlay` instead, which updates independently:

```swift
// Bad - RuleMark inside Chart triggers full re-render
Chart {
    ForEach(series) { ... LineMark(...) }
    if let date = cursorDate {
        RuleMark(x: .value("Cursor", date))  // Causes lag!
    }
}

// Good - Path in overlay updates independently
Chart {
    ForEach(series) { ... LineMark(...) }
}
.chartOverlay { proxy in
    GeometryReader { geometry in
        if let date = cursorDate, let plotFrame = proxy.plotFrame {
            let plotRect = geometry[plotFrame]
            if let xPos = proxy.position(forX: date) {
                Path { path in
                    path.move(to: CGPoint(x: plotRect.origin.x + xPos, y: plotRect.origin.y))
                    path.addLine(to: CGPoint(x: plotRect.origin.x + xPos, y: plotRect.maxY))
                }.stroke(Color.gray)
            }
        }
    }
}
```

**Xcode project file structure**: When adding new Swift files to an Xcode project, you need to add entries in FOUR places in `project.pbxproj`:

1. `PBXBuildFile` section - references the file for compilation
2. `PBXFileReference` section - defines the file itself
3. `PBXGroup` section - adds file to the appropriate folder/group in the navigator
4. `PBXSourcesBuildPhase` section - adds file to the Sources build phase

**FileDocument doesn't expose original file URL**: SwiftUI's `FileDocument` protocol sandboxes files and copies them to a temp directory. If you need the original file URL (e.g., for storing metadata via xattr), you must use AppKit's `NSDocument` instead. Create an `NSDocument` subclass and bridge it to SwiftUI via `NSHostingController`.

**NSDocument print() shadows Swift.print()**: Inside an `NSDocument` subclass, `print()` refers to the document's print method, not Swift's console output. Use `Swift.print()` explicitly for debug logging.

**@Observable vs ObservableObject**: When using Swift Observation's `@Observable` macro (not Combine's `ObservableObject`), don't use `@ObservedObject` - just pass the object as a regular property or use `@Bindable` for two-way binding

**macOS Tahoe Liquid Glass toolbar**: In NavigationSplitView, the toolbar glass effect stops at the sidebar edge by default, creating an ugly visual break. Fix by hiding the toolbar background on the detail view, which allows Liquid Glass to flow continuously:

```swift
NavigationSplitView {
    sidebar
} detail: {
    detailView
        .navigationTitle("Title")
        .toolbarBackground(.hidden, for: .windowToolbar)
}
```

Also add `.windowToolbarStyle(.unified)` to the WindowGroup for best results.

**Popover content resize crash**: Any animated content change inside a `.popover()` that causes the popover to resize triggers a crash in `PopoverHostingView.updateAnimatedWindowSize`. This includes conditionally showing/hiding views with animation, VStacks that grow, etc. Fix by using fixed-layout approaches with opacity-only animations:

```swift
// Bad - VStack height changes cause crash
VStack {
    MainContent()
    if isExpanded {
        ExpandedContent()  // Crash when animated!
    }
}

// Good - fixed layout, opacity-only animation
VStack {
    MainContent()
    ExpandedContent()
        .opacity(isExpanded ? 1 : 0)
        .animation(.spring(), value: isExpanded)
}
.clipped()
```

**Text opacity in animated views**: When animating opacity on views containing text, the text can render semi-transparent even at full opacity due to how SwiftUI composites the animation. Fix with `.compositingGroup()` to rasterize the view before applying opacity:

```swift
HStack {
    Circle().fill(color)
    Text("Label")
        .foregroundColor(Color(nsColor: .labelColor))  // Use explicit color
}
.compositingGroup()  // Rasterize before opacity animation
.opacity(isVisible ? 1 : 0)
.animation(.spring(), value: isVisible)
```

**SceneKit materials don't auto-update from SwiftUI**: When using SceneKit views inside SwiftUI with an `@Observable` view model, changes to view model properties don't automatically update SceneKit node materials. You must add `.onChange` observers and manually update materials:

```swift
.onChange(of: viewModel.variableOverrides) { _, _ in
    updateNodeColors()  // Manually update SCNMaterial.diffuse.contents
}
```

**Full-bleed SceneView with NavigationSplitView**: To have a SceneView extend behind the sidebar (full-bleed effect) while still receiving mouse events for camera control, use a dual SceneView approach. Both share the same `SCNScene` object so camera changes sync:

```swift
NavigationSplitView(...) {
    sidebar
} detail: {
    // Interactive SceneView - receives mouse events
    SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
}
.background {
    // Visual-only SceneView for full-bleed effect
    SceneView(scene: scene, options: [.autoenablesDefaultLighting])  // No camera control
        .ignoresSafeArea()
        .allowsHitTesting(false)
}
```

**Color utilities not called from UI code**: When implementing color transformation functions (like `componentColors(for:)`), it's easy to write the utility but forget to call it from the actual UI code. Always verify new color utilities are wired up in `colorForSeries` or equivalent functions, not just written.

**White navigation title on dark background (macOS)**: SwiftUI's `.toolbarColorScheme(.dark)` doesn't reliably make navigation titles white on macOS. Use a WindowAccessor to set the window's appearance directly:

```swift
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { configure(window) }
        }
    }
}

// Usage:
.background {
    WindowAccessor { window in
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
    }
}
```

## Unified Sidebar (NavigationSidebarContainer)

**All three views use NavigationSidebarContainer for consistent sidebar styling.** The sidebar toggle uses a pure SwiftUI approach that's iPad-compatible.

### Required Pattern

```swift
var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
        NavigationSidebarContainer(sidebarBackground: .black /* optional */) {
            sidebarView
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 400)
    } detail: {
        detailView
    }
    .sidebarToggleToolbar()  // Adds left-aligned toggle button
    .toolbar(removing: .sidebarToggle)  // Removes SwiftUI's default right-aligned toggle
    .toolbarBackground(.hidden, for: .windowToolbar)  // Enables Liquid Glass flow
}
```

### How It Works

1. **NavigationSidebarContainer** wraps sidebar content for consistent styling (e.g., background color for Globe)
2. **sidebarToggleToolbar()** adds a left-aligned toggle button using `NSSplitViewController.toggleSidebar(_:)` action
3. **toolbar(removing: .sidebarToggle)** removes SwiftUI's default right-aligned toggle to avoid duplicates
4. **toolbarBackground(.hidden)** allows Liquid Glass to flow across the entire title bar

### DO NOT

- Use NSToolbar's `.toggleSidebar` item (conflicts with SwiftUI toolbar)
- Forget `.toolbar(removing: .sidebarToggle)` (causes duplicate buttons)
- Forget `.toolbarBackground(.hidden, for: .windowToolbar)` (breaks Liquid Glass)

## Product Requirements

**Keep `/requirements/` updated.** This directory contains markdown files documenting what we're building and why.

- One file per feature (e.g., `variable-colors.md`, `globe-view.md`)
- Include: purpose, design decisions, user-facing behavior
- Update when adding features or changing behavior
- Ask questions to understand user motivations when unclear

**Always ask** when you need context on the "why" behind a feature. Understanding motivations leads to better design decisions and more useful requirements docs.

## CLAUDE.md Maintenance

**Keep this file lean.** Only include:
- Project-specific setup that isn't obvious from package.json/config files
- Hard-won lessons from debugging (gotchas that caused real bugs)
- User preferences for how Claude should work

**Don't include:** General language/framework knowledge, standard patterns, things discoverable from file structure.

**Update this file** when you discover:
- A non-obvious bug or gotcha that took debugging to figure out
- A project-specific pattern that would save research time
- New user preferences expressed during the conversation
