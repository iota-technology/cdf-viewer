# Constants View

## Purpose
Display time-independent CDF variables (constants) that don't have a DEPEND_* attribute referencing a time variable. These are typically metadata like spacecraft mass, calibration values, or fixed parameters.

## Design Decisions

### Independent Variable Section
- Renamed from "Time Variable" to "Independent Variable" to accommodate both modes
- Time variables shown as radio buttons with data type and record count
- "Constants" pseudo-option appears only if the file has constant variables
- Shows count of available constants (e.g., "55 variables")

### Constant Detection
- A variable is a constant if it has no `DEPEND_0`, `DEPEND_1`, or `DEPEND_2` attribute referencing a timestamp variable
- Must be numeric type
- Must not itself be a timestamp variable

### Card-Based Display
- Constants displayed as cards in a responsive grid (280-400px per card)
- Cards sized to fit their content (not stretched to match row neighbors)
- Top-aligned within grid rows

### Card Content
- **Header**: Variable name with info button (opens VariableInfoPopover)
- **Value Display**:
  - Scalars: Large monospaced font (24pt)
  - Small vectors (≤10 elements): Bracketed column with component labels if available
  - Large arrays: Summary showing first 3 values and total count
- **Units**: Inline with values, formatted with proper symbols
- **Footer**: Description (CATDESC or FIELDNAM) and data type info

### Unit Formatting
Convert common unit patterns to proper symbols:
- `^2` → `²`, `^3` → `³`, `^-1` → `⁻¹`
- `degC` → `°C`, `degF` → `°F`, `deg` → `°`
- `degK` → `K` (Kelvin uses no degree symbol)
- `micro` → `µ`, `us` → `µs`
- `rad` → `ᶜ` (superscript c for radians)

### Vector Display
- Center-justified column with subtle square brackets
- Component labels shown if LABL_PTR_* attribute provides them
- Font size scales based on element count (18pt for ≤3, 15pt for ≤6, 13pt for ≤10)

### Matrix Display

- 2D arrays where both dimensions are ≤10 are displayed as visual matrices
- Row and column headers from LABL_PTR_1 and LABL_PTR_2 attributes
- Square brackets frame the entire matrix grid
- Combined labels used for flat representation (e.g., "xx", "xy", "xz" for 3x3)
- Font size scales based on total cell count

### Disabled Features
When viewing constants:
- Chart button disabled (no time axis)
- Globe button disabled (no position data)
- CSV export disabled

## User-Facing Behavior
1. Open a CDF file
2. In the sidebar's Independent Variable section, click "Constants"
3. The Data Variables section updates to show only constant variables
4. Select constants to view them as cards in the main area
5. Click the info button on any card for full variable details
