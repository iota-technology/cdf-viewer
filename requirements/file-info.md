# File Info

## Purpose
Display CDF file metadata and global attributes in an accessible popover.

## Design Decisions

### Access
- Toolbar button (info.circle icon) in main document window
- Opens as popover attached to button
- Scrollable for files with many attributes

### Displayed Information

#### File Details
- File name and size
- CDF version (e.g., "3.9.0")
- Encoding (e.g., "IBMPC", "Network")
- Variable count
- Attribute count

#### Global Attributes
- Mission/instrument metadata
- Data provenance information
- Generation timestamps
- Contact information

#### Variable Attributes
- Collapsible disclosure groups per attribute
- Shows values for each variable that has that attribute
- Common attributes: UNITS, CATDESC, FIELDNAM, VALIDMIN, VALIDMAX

#### Copyright
- Displayed if present in file
- Typically NASA/institution data usage terms

### Text Selection
- All values are selectable for copy/paste
- Useful for citing data sources or debugging issues
