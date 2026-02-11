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

### Variable Association Constraints

Variables are disabled based on two checks (in priority order):

1. **Time association (DEPEND_0)**
   - Data variables must be associated with the selected time variable via `DEPEND_0` attribute
   - Time variables must be associated with at least one selected data variable
   - Variables without `DEPEND_0` are treated as compatible with any time variable
   - Disabled tooltip explains which time variable to select

2. **Unit compatibility**
   - All selected data variables must share the same unit (for meaningful Y-axis)
   - Variables with different units are disabled after the first selection
   - Deselecting all variables unlocks unit selection again

### Chart Rendering

- Uses Canvas for high-performance rendering with large datasets
- Min-max downsampling preserves visual peaks/valleys at any zoom level
- Cursor drawn as overlay Path (not RuleMark) to avoid performance issues

### Adaptive Time Axis

- Two-line layout: time (top), date (bottom)
- Date only shown at leftmost tick where that date starts
- Subsequent ticks on the same date show only time
- Three precision levels adapting to zoom:
  - `HH:mm` - default when ticks differ by minutes
  - `HH:mm:ss` - when consecutive ticks share same hour:minute
  - `HH:mm:ss.SSS` - when consecutive ticks share same second
- Tick count reduced for millisecond labels to prevent overlap

### Hover Interaction

- Hovering shows cursor line and value readouts
- Values displayed in sidebar next to variable names
- Only shows values for selected variables

### Color System

- Each variable gets deterministic color based on name hash
- Vector components use adaptive LCH algorithm (see [variable-colors.md](variable-colors.md))
- Colors persist across sessions via file xattr

### Timestamp Display

- Sidebar shows timestamp when hovering with time variable selected
- Two-line format: date (YYYY-MM-DD) and time with milliseconds (HH:mm:ss.SSS)
- Pause indicator (orange pause icon) shown when cursor is paused

### Cursor Synchronization

- Cursor position shared with Table and Globe views
- Clicking chart pauses cursor at that timestamp
- Pause indicated by orange slider tint
