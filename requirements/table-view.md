# Table View

## Purpose
The primary view for exploring raw CDF data. Shows timestamps and selected variable values in a scrollable table.

## Design Decisions

### Main Document Window
- Table view is the default view when opening a CDF file
- Sidebar shows variable list for selection
- Chart and Globe views open as auxiliary windows

### Independent Variable Section

- Renamed from "Time Variable" to accommodate time-based and constant modes
- Time variables shown as radio buttons with data type and record count
- "Constants" pseudo-option available if file has time-independent variables
- See `constants-view.md` for constants mode details

### Variable Selection

- Single-select for independent variable (time variable or constants mode)
- Multi-select for data variables (each becomes a column)
- Vector variables expand to component columns (e.g., x, y, z)
- Matrix variables expand to combined columns (e.g., xx, xy, xz, yx, yy, yz, zx, zy, zz)
- Data variables filtered based on DEPEND_* attributes matching selected time variable

### Matrix Support

- 2D arrays where both dimensions are ≤10 are treated as matrices
- Each matrix element becomes a separate column
- Column labels combine row and column dimension labels (from LABL_PTR_1 and LABL_PTR_2)
- Example: A 3x3 matrix with labels ["x","y","z"] produces columns: xx, xy, xz, yx, yy, yz, zx, zy, zz

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
