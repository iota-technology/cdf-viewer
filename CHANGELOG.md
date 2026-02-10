# Changelog

All notable changes to CDF Viewer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
