# CDF Viewer

macOS app for viewing NASA CDF (Common Data Format) files with data tables, time series charts, and 3D globe visualization.

## Build & Run

```bash
cd CDFViewer
xcodebuild -scheme CDFViewer -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/CDFViewer-*/Build/Products/Debug/CDFViewer.app
```

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

**Xcode project file structure**: When adding new Swift files to an Xcode project, you need to add entries in THREE places in `project.pbxproj`:
1. `PBXBuildFile` section - references the file for compilation
2. `PBXFileReference` section - defines the file itself
3. `PBXGroup` section - adds file to the appropriate folder/group in the navigator

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
