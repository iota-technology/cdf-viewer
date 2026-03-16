---
# io-8az7
title: Display all timestamps as UTC regardless of machine timezone
status: completed
type: bug
priority: high
created_at: 2026-03-16T18:32:31Z
updated_at: 2026-03-16T18:37:32Z
---

Timestamps shown in the app change depending on the timezone of the machine running it. All CDF timestamps should be interpreted as UTC and displayed as UTC times.

The timezone indicator "UTC" should be shown, where appropriate, but it should never show or be any other timezone.

## Summary of Changes

Fixed all 6 locations where date/time formatting used the system timezone instead of UTC:

- **DataTableNSView.swift** — Added `timeZone = UTC` to the table cell timestamp formatter
- **CanvasLineChart.swift** — Added `timeZone = UTC` to both the date and time formatters for X-axis labels
- **TimeSeriesChartView.swift** — Added `timeZone = UTC` to the static millisecond time formatter, and switched the sidebar date display from `.dateTime` to `Date.FormatStyle(timeZone: .gmt)`
- **GlobeView.swift** — Switched both sidebar and scrubber timestamp displays from `.dateTime` to `Date.FormatStyle(timeZone: .gmt)`

ISO8601DateFormatter (used in CDFDataTypes.swift) and ISO8601Format (used in CSV export) already default to UTC, so no changes were needed there.
