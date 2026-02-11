# Metadata Persistence

## Purpose
Remember user customizations (colors, position toggles) per CDF file across sessions.

## Design Decisions

### Storage Mechanism
- Uses macOS extended attributes (xattr) on the CDF file itself
- Custom attribute key: `com.iota-technology.cdfviewer.metadata`
- JSON-encoded for structured storage

### Stored Data
- `variableOverrides`: Dictionary keyed by variable name
  - `customColor`: Hex color string (e.g., "#FF6B6B")
  - `isPositional`: Boolean override for position detection

### Persistence Triggers
- Saved immediately when user changes a setting
- Loaded when document opens
- Removed if all overrides cleared (clean xattr)

### Why Extended Attributes?
- Travels with the file (copy, move, sync)
- No separate database or config files to manage
- Works with any filesystem that supports xattr
- Invisible to users who don't care about it

### Limitations
- Lost if file copied to filesystem without xattr support
- Not visible in Finder (by design)
- Size limited by filesystem xattr limits

### NSDocument Requirement
- SwiftUI's FileDocument copies files to temp directory (loses xattr)
- Using NSDocument to maintain original file URL for xattr access
- Bridge to SwiftUI via NSHostingController
