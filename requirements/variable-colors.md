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

Uses adaptive LCH algorithm to ensure X, Y, Z are always visually distinguishable:

- **Normal colors (mid-lightness, saturated)**: Shifts hue ±30° per step with ±10% chroma variation
- **Low chroma (C<15, near gray)**: Adds +25 chroma per step to create actual color differences
- **Dark colors (L<30)**: Lightens +28 and adds +15 chroma per step
- **Light colors (L>70)**: Darkens -28 and adds +15 chroma per step

This handles edge cases like white, black, or gray base colors where pure hue shifts would be invisible. Test coverage in `test_color_variants.swift` ensures minimum LCH distance between variants.

Shown on hover in the info popover with animated cascade reveal.

### View-Specific Behavior
- **Chart view**: Shows colors for selected variables in sidebar and on chart lines
- **Globe view**: Shows colors for selected position variables on orbit tracks
- **Table view**: No colors (data is text-only, no visual encoding needed)

### Color Indicator in Sidebar
- Small colored circle appears next to selected variables
- Only shown when variable is actively selected
- Matches the color used in the visualization
