# CDF File Format Support

## Purpose
Native parsing of NASA CDF (Common Data Format) files without external dependencies.

## Design Decisions

### Pure Swift Parser
- No dependency on NASA's C library
- Binary parsing using Swift's Data and memory mapping
- Supports CDF versions 2.6+ through 3.9+

### Supported Data Types
- Integers: INT1, INT2, INT4, INT8, UINT1, UINT2, UINT4
- Floats: FLOAT, DOUBLE
- Time: CDF_EPOCH, CDF_EPOCH16, CDF_TIME_TT2000
- Strings: CDF_CHAR

### Timestamp Handling
- Auto-detects timestamp variables by name/type heuristics
- Converts CDF epochs to Swift Date objects
- Special handling for Unix timestamps in microseconds (configurable)
- TT2000 (nanoseconds since J2000) fully supported

### Compression Support
- Handles GZIP-compressed variable data
- Transparent decompression during read

### Variable Classification
- **Timestamp variables**: Detected by type (EPOCH, TT2000) or name pattern
- **Position variables**: 3-vec doubles with "ecef" or "position" in name
- **Numeric variables**: All other numeric types for plotting

### File Metadata
- Global attributes (mission info, data provenance)
- Variable attributes (UNITS, CATDESC, FIELDNAM)
- Copyright and licensing information

### Error Handling
- Graceful handling of malformed/truncated files
- Warning collection for non-fatal issues
- Descriptive error messages with recovery suggestions
