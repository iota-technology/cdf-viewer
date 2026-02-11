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
