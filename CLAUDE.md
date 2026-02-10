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

Push a semantic version tag to trigger GitHub Actions release:
```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow builds an unsigned app zip and creates a GitHub release.

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
