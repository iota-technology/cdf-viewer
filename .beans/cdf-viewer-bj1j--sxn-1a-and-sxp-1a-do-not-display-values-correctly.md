---
# cdf-viewer-bj1j
title: SXN_1A and SXP_1A do not display values correctly, something is going wrong with displaying quaternions and the timestamps
status: completed
type: bug
priority: normal
created_at: 2026-03-24T02:57:32Z
updated_at: 2026-04-04T14:34:20Z
---

## Summary of Changes

### Root cause: VXR tree traversal
The CDF parser only followed linear VXR chains (via `vxrNext` pointers), but ISTP-compliant CDF files with many records use a **tree of VXR index nodes**. Each VXR entry can point to either a data record (VVR/CVVR) or another sub-VXR node. The parser encountered VXR records (type 6) where it expected data and silently skipped them, resulting in zero data.

**Fix (CDFReader.swift):** Extracted VXR traversal into a recursive `readVXRTree` method that follows sub-VXR nodes before reading data blocks.

### Performance: Direct double decoding
The hot path (readDoubles/readTimestamps) created millions of CDFValue enum boxes just to immediately extract the Double. Added a `decodeDoublesDirectly` method that bulk-converts raw bytes to [Double] without intermediary allocations — using `withUnsafeBytes` for zero-copy reinterpretation when endianness matches.

**Result:** 850K timestamp file loads **2.6x faster** (0.59s → 0.23s). readTimestamps is 5.8x faster, readDoubles is 3x faster.
