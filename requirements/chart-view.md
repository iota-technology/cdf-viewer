# Chart View

## Purpose
Time series visualization for selected variables. Opens as an auxiliary window from the main document.

## Design Decisions

### Auxiliary Window
- Opens from toolbar button in main document window
- Shares ViewModel with Table view (synchronized selection and cursor)
- Independent window lifecycle (can close without closing document)

### Variable Selection
- Sidebar mirrors Table view structure
- Time variable for X-axis (single-select)
- Data variables for Y-axis (multi-select)
- Each selected variable gets its own colored line

### Chart Rendering
- Uses Swift Charts for visualization
- Each data series requires explicit `series:` parameter for proper separation
- Cursor drawn as overlay Path (not RuleMark) to avoid performance issues

### Hover Interaction
- Hovering shows cursor line and value readouts
- Values displayed in sidebar next to variable names
- Only shows values for selected variables

### Color System
- Each variable gets deterministic color based on name hash
- Vector components get hue-shifted variants (X, Y: +30°, Z: +60°)
- Colors persist across sessions via file xattr

### Cursor Synchronization
- Cursor position shared with Table and Globe views
- Clicking chart pauses cursor at that timestamp
- Pause indicated by orange slider tint

<!-- TODO: Understand primary workflows - anomaly detection? Comparing variables? Event correlation? -->
