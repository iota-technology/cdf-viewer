# Cursor Synchronization

## Purpose
Keep Table, Chart, and Globe views aligned to the same point in time, enabling cross-view analysis.

## Design Decisions

### Shared State
- Single `cursorIndex` in ViewModel (row index into timestamp array)
- Converted to `cursorDate` for Chart view
- Converted to `cursorProgress` (0-1) for Globe animation
- Shared `isCursorPaused` state controls pause across all views
- Shared `isAnimating` state for Globe animation playback

### Interaction Modes

#### Hover Mode (default)
- Moving mouse updates cursor position
- Leaving a view clears the cursor
- All views follow the cursor in real-time

#### Paused Mode
- Clicking in any view pauses at that position
- Cursor stays fixed even when mouse moves away
- Visual indicators: orange slider tint (Globe), highlighted row (Table), orange pause icon in sidebar
- Click anywhere in the same view to unpause (returns to hover mode)
- Pause can also be unset from other views

### Pause Toggle Behavior

The pause state acts as a simple toggle:

1. **Click while NOT paused** → Pause at clicked position
2. **Click while paused** → Unpause (return to hover mode)

This applies consistently across all views:

- **Table**: Click any row to toggle pause
- **Chart**: Click anywhere in plot area to toggle pause
- **Globe**: Click scrubber or use play/pause button

### View-Specific Behavior

#### Table View
- Hovering a row sets cursor to that row index (when not paused)
- Clicking toggles pause state
- Row highlight follows cursor position
- Paused row shows stronger highlight color

#### Chart View
- Hovering sets cursor via timestamp lookup (when not paused)
- Uses binary search to find closest timestamp
- Vertical cursor line tracks position
- Clicking toggles pause and jumps to clicked timestamp
- When Globe animation is playing, hover is ignored (must click to stop)

#### Globe View
- Cursor controls orbit track progress (how much of path is visible)
- Animation scrubber slider bound to cursor progress
- Play button animates cursor through time
- Pausing animation pauses the shared cursor
- Scrubber turns orange when paused
- External pause (from Table/Chart click) stops animation

### Cross-View Interactions

- Pausing in one view pauses all views
- Unpausing in one view unpauses all views
- Globe animation respects external pause state
- Chart ignores hover during Globe animation (prevents accidental interruption)
- Clicking Chart during animation stops animation and jumps to clicked time

### Timestamp Alignment

- All views use same timestamp array from selected time variable
- Binary search ensures efficient timestamp-to-index conversion
- Handles varying timestamp granularity gracefully
