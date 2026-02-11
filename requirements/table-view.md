# Table View

## Purpose
The primary view for exploring raw CDF data. Shows timestamps and selected variable values in a scrollable table.

## Design Decisions

### Main Document Window
- Table view is the default view when opening a CDF file
- Sidebar shows variable list for selection
- Chart and Globe views open as auxiliary windows

### Variable Selection

- Single-select for time variable (used as row index)
- Multi-select for data variables (each becomes a column)
- Vector variables expand to X, Y, Z component columns

### Timestamp Format

- Full precision: `yyyy-MM-dd HH:mm:ss.SSS` (milliseconds included)
- Consistent with chart view's maximum precision level

### Performance
- Uses NSTableView (AppKit) for efficient handling of large datasets
- Array-based data storage for O(1) row access
- No per-row object allocation (uses index-based lookup)

### Cursor Synchronization
- Hovering a row sets the shared cursor position
- Clicking pauses the cursor at that position
- Cursor position syncs with Chart and Globe views

### Vector Inspector
- Clicking a vector cell opens detailed inspector
- Shows 3D visualization of vector components
- Displays X, Y, Z values with unit hints

<!-- TODO: Clarify primary use case - is this for exploration, verification, or finding specific events? -->
