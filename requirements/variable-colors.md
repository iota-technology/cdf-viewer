# Variable Colors

## Purpose
Each data variable gets a unique, visually consistent color for display in Chart and Globe views.

## Design Decisions

### Deterministic Random Colors
- Colors are generated from a hash of the variable name
- Same variable always gets the same color across sessions
- Uses LCH color space with fixed L=65 (lightness) and C=60 (chroma)
- Only the hue varies, ensuring all colors have similar visual weight

### User-Customizable
- Users can override colors via the info popover color picker
- Custom colors are persisted in file extended attributes (xattr)
- Overrides survive app restarts and file moves

### Vector Component Colors
- 3-vec variables (X, Y, Z) get hue-shifted variants of the base color
- X: base color, Y: +30° hue shift, Z: +60° hue shift
- Shown on hover in the info popover with animated cascade reveal

### View-Specific Behavior
- **Chart view**: Shows colors for selected variables in sidebar and on chart lines
- **Globe view**: Shows colors for selected position variables on orbit tracks
- **Table view**: No colors (data is text-only, no visual encoding needed)

### Color Indicator in Sidebar
- Small colored circle appears next to selected variables
- Only shown when variable is actively selected
- Matches the color used in the visualization
