# Variable Info Popover

## Purpose
Show variable metadata and provide quick access to variable settings when clicking the (i) button.

## Design Decisions

### Always-Shown Information
- Variable name (headline)
- Data type (e.g., "Float64", "Int32")
- Dimensions (e.g., "[86400, 3]")
- Record count
- CDF attributes when present: UNITS, CATDESC, FIELDNAM

### Context-Sensitive Features

#### Color Picker
- **Shown**: Chart view, Globe view (only for selected variables)
- **Hidden**: Table view (no colors used)
- Hovering reveals X/Y/Z component colors for vectors
- Component colors animate with staggered cascade (expand in order, collapse in reverse)

#### Position Data Toggle
- **Shown**: Globe view only, and only for 3-vec variables
- **Hidden**: Table view, Chart view, non-vector variables
- Toggle: "Use as Position Data"
- Shows hint when variable wasn't auto-detected as positional

### Animation Constraints
- Fixed-layout approach to avoid popover resize crashes
- X/Y/Z colors use opacity animation only (not conditional rendering)
- `.compositingGroup()` on animated text to prevent rendering artifacts
- `.clipped()` to hide off-screen animated content

### Metadata Persistence
- Color and position overrides saved to file's extended attributes
- Uses custom xattr key for CDF Viewer metadata
- JSON-encoded for structured storage
