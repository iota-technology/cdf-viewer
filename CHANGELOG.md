# Changelog

All notable changes to CDF Viewer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] - 2026-02-12

### Added

- QuickLook Preview extension for CDF files
  - Shows file metadata (name, size, version, encoding)
  - Displays full variable list with types, dimensions, and units
  - Shows key global attributes (Project, Source, Mission, etc.)
  - Two-column layout optimized for Finder preview
- Support for N-dimensional vectors (2D, 3D, 4D quaternions, up to 10 components)
- LABL_PTR_* attribute support for reading component labels from CDF files

### Changed

- Vector component names use CDF file labels when available, fall back to indices ([0], [1], etc.)
- Release builds are now code-signed and notarized by Apple

## [0.10.3] - 2026-02-12

### Added

- Custom About window with company attribution and clickable links
- Company attribution on Welcome window (byJP Limited for Iota Technology)

### Changed

- Bundle identifier updated to com.iotatechnology.CDFViewer

## [0.10.2] - 2026-02-12

### Changed

- CSV export now includes milliseconds in timestamps (ISO8601 with fractional seconds)

## [0.10.1] - 2026-02-12

### Added

- Sparkle auto-update framework for automatic updates
- "Check for Updates..." menu item in app menu

## [0.10.0] - 2026-02-11

### Added

- Welcome window shown when app launches with no documents open
- File menu with Open action (Cmd+O)
- Association-based variable filtering in chart view (using DEPEND_0 attribute)
- Adaptive LCH color algorithm for vector components (handles white, black, gray base colors)
- Two-line timestamp format in chart sidebar (date + time with milliseconds)

### Changed

- Vector component colors (X, Y, Z) now use adaptive algorithm that adjusts lightness and chroma based on base color characteristics
- Variables without DEPEND_0 are treated as compatible with any time variable

### Fixed

- Chart grid lines now align exactly with tick marks when panning
- Vector component colors now visually distinguishable for all base colors (including near-white, near-black, and gray)

## [0.8.0] - 2025-02-11

### Added

- Human-readable unit names on chart Y-axis (e.g., "Meters (m)" instead of just "m")
- UnitNames mapping for common scientific units (m, km, m/s, rad/s, A, V, etc.)
- Units displayed in parentheses in table column headers and sidebar

## [0.7.1] - 2025-02-11

### Performance

- Binary search for visible point range in charts (O(log n) vs O(n))
- Min-max downsampling preserves peaks/valleys while reducing rendered points
- Y-range calculation only iterates visible points
- Cache column type lookups in table for O(1) access
- Reuse DateFormatter instead of creating per-row

### Added

- Units display in sidebar next to data type (when UNITS attribute exists)
- Y-axis label on charts showing units (when all selected variables share same units)
- Integer types display without decimal points in table

## [0.7.0] - 2025-02-11

### Changed

- Replace Swift Charts with Canvas-based rendering for 60fps chart performance
- Chart now renders full-resolution data (no decimation artifacts)

### Fixed

- Chart correctly handles NaN/infinite values and data gaps
- Decompression buffer too small for highly compressible CDF data
- Table cell reuse bugs causing wrong colors and alignment

## [0.4.4] - 2025-02-10

### Added

- Variable info popover with color picker (click ℹ️ button next to any variable)
- Custom color persistence via macOS extended attributes (colors saved on CDF file)
- LCH color space for vector component colors (X/Y/Z shift hue by 30°/60° while preserving lightness and chroma)
- Positional toggle in globe view info popover to override ECEF detection heuristic

## [0.4.3] - 2025-02-10

### Fixed

- Liquid Glass toolbar now flows continuously across NavigationSplitView (hidden toolbar background)

## [0.4.2] - 2025-02-10

### Added

- Multi-track support in globe view (select multiple ECEF position variables)
- Track color indicators in globe sidebar
- `expandVectors` option in VariableSidebarView (show vectors as single items)

### Changed

- Globe view now uses NavigationSplitView for better sidebar behavior

## [0.4.1] - 2025-02-10

### Performance

- Chart cursor line now renders as lightweight overlay (no longer triggers full chart re-render on hover)

## [0.4.0] - 2025-02-10

### Added

- NSTableView-based table for smooth scrolling with 86,400+ rows
- Min-max decimation for charts (preserves peaks and valleys)
- README with app icon and screenshot
- Array-based data storage for O(1) access

### Changed

- Cursor now works across full dataset range (not limited to 10,000 rows)
- Chart hover values now show accurate data (not decimated)

### Performance

- Table scrolling is now smooth with 100k+ rows (native AppKit virtualization)
- Chart rendering reduced from 86,400 to ~5,000 points while preserving visual accuracy
- Binary search for cursor date lookup

## [0.3.0] - 2025-02-10

### Added
- Resizable table columns with drag handles
- Synchronized cursor across table, chart, and globe views
- Reusable VariableSidebarView component for consistent UI
- Multi-column table approach with variable selection sidebar

### Fixed
- 2D array handling for ECEF vector data (now correctly shows X/Y/Z components)
- Stride calculation to display all records, not just first row
- Timestamp column width to prevent text wrapping
- Removed loading flash on quick data updates

## [0.2.0] - 2025-02-09

### Added
- Color indicators in chart sidebar matching line colors
- Redesigned time series chart with improved sidebar

### Fixed
- Chart hover tracking and cursor alignment
- Viewer-only app with CDF file filtering
- Documentation for unsigned app quarantine workaround

## [0.1.0] - 2025-02-08

### Added
- Initial release of CDF Viewer macOS app
- Native Swift CDF parser (no external dependencies)
- Data table view with lazy loading
- Time series chart using Swift Charts
- 3D globe visualization with Blue Marble Earth texture
- ECEF position track display on globe
- Timestamp scrubbing on globe view
- Space bar play/pause for globe animation
- App icon
- GitHub Actions release workflow

### Fixed
- VXR and CVVR record parsing for compressed CDF files
- Original filename display instead of UUID-prefixed temp path
- Chart data variables appearing in selection list
