# Globe View

## Purpose
Visualize satellite orbital position data on a 3D Earth globe with time-synchronized playback.

## Design Decisions

### Position Variable Detection
- Auto-detects ECEF (Earth-Centered Earth-Fixed) position variables
- Heuristic: 3-vec double variables with names containing "ecef" or "position"
- Users can manually toggle any 3-vec as position data via info popover

### Orbit Track Rendering
- Uses SceneKit for 3D rendering
- Track drawn as line segments from start to current cursor position
- Track grows/shrinks as user scrubs through time
- Each selected variable gets its own colored track

### Playback Controls
- Play/pause button with configurable speed multiplier (1x to 1000x)
- Scrubber slider for manual time navigation
- Slider turns orange when paused to indicate frozen state
- No separate pause indicator icon needed (slider color is sufficient)

### Cursor Synchronization
- Globe cursor syncs with Table and Chart views
- Clicking in Chart/Table pauses and sets position
- Globe animation respects external pause state

### Position Toggle
- Only shown for 3-vec variables (scalars and other shapes can't be positions)
- Toggle in info popover: "Use as Position Data"
- Shows "(Not automatically detected)" hint when manual override
- State persisted in file xattr metadata

### Live Color Updates
- Changing color in info popover immediately updates track color
- SceneKit materials updated via onChange observer
- Both track line and marker sphere update together

### Full-Bleed Visual Design
- Scene extends under sidebar for immersive space visualization
- Dark background with Earth requires white navigation title
- Window titlebar transparent to blend with scene
- Sidebar follows system light/dark mode appearance
- Implementation uses dual SceneView (interactive in detail, visual-only as background)
- Camera controls (rotate, zoom, pan) work only in detail area (not under sidebar)

### Seasonal Earth Textures

- Uses NASA Blue Marble monthly composites (12 textures, one per month)
- Textures represent Earth's appearance on approximately the 1st of each month
- Smooth blending between consecutive months based on day of month
- Blend formula: `blendFactor = (dayOfMonth - 1) / daysInMonth`
- Example: February 15th blends ~50% February texture with ~50% March texture

### Day/Night Cycle

- Sun position calculated from timestamp using astronomical formulas
- Solar declination varies seasonally: +23.45° (summer solstice) to -23.45° (winter solstice)
- Hour angle based on UTC time: sun at longitude 0° at 12:00 UTC, moving 15°/hour westward
- Coordinate conversion from ECEF to SceneKit (X stays, ECEF Z→SceneKit Y, ECEF Y→SceneKit -Z)

### City Lights (Black Marble)

- Night side shows city lights from NASA Black Marble texture
- Applied as emission map, visible only on dark side of Earth
- Warm yellow-orange tint (RGB: 1.0, 0.85, 0.5) for realistic city light appearance
- Terminator transition: ~15° (0.26 radians) smooth fade using smoothstep
- Day side dims to 2% ambient to prevent complete blackout while maintaining contrast

### Star Background

- Large sphere (radius 500) surrounding the scene with NASA star map texture
- Texture from NASA SVS (svs.gsfc.nasa.gov/4851), converted from 8K EXR to 4K JPEG
- Rendered on inside of sphere using negative X scale and emission-only material
- Rotates based on Greenwich Mean Sidereal Time (GMST) for accurate star positions
- Uses IAU 1982 formula: GMST = 280.46° + 360.985647° × days since J2000.0
- Stars rotate ~1° more per day than the sun (sidereal day ≈ 23h 56m vs solar day 24h)

### Orbit Track Gap Detection

- Detects gaps in timestamp data (time delta > 3× median time step)
- Gaps rendered as actual breaks in the track line, not straight lines
- Prevents misleading visualization of data discontinuities
