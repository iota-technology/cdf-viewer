# Cursor Synchronization

## Purpose
Keep Table, Chart, and Globe views aligned to the same point in time, enabling cross-view analysis.

## Design Decisions

### Shared State
- Single `cursorIndex` in ViewModel (row index into timestamp array)
- Converted to `cursorDate` for Chart view
- Converted to `cursorProgress` (0-1) for Globe animation

### Interaction Modes

#### Hover Mode (default)
- Moving mouse updates cursor position
- Leaving a view clears the cursor
- All views follow the cursor in real-time

#### Paused Mode
- Clicking in any view pauses at that position
- Cursor stays fixed even when mouse moves away
- Visual indicator: orange slider tint (Globe), highlighted row (Table)
- Click again or press space to unpause

### View-Specific Behavior

#### Table View
- Hovering a row sets cursor to that row index
- Clicking pauses cursor at that row
- Row highlight follows cursor position

#### Chart View
- Hovering sets cursor via timestamp lookup
- Uses binary search to find closest timestamp
- Vertical cursor line tracks mouse position

#### Globe View
- Cursor controls orbit track progress (how much of path is visible)
- Animation scrubber slider bound to cursor progress
- Play button animates cursor through time
- Pausing animation pauses the shared cursor

### Timestamp Alignment
- All views use same timestamp array from selected time variable
- Binary search ensures efficient timestamp-to-index conversion
- Handles varying timestamp granularity gracefully

<!-- TODO: Confirm use case - is this for "spot something in chart, see where on globe"? -->
