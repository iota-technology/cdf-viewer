# Welcome Window

## Purpose

Provide a landing screen when no CDF files are open, with a button to open a file.

## Behavior

- **Shown** when the app launches with no documents open
- **Shown** when the last document window is closed
- **Shown** when clicking the dock icon with no visible windows
- **Hidden** when a document window opens
- **Never shown** when the app is launched by double-clicking a CDF file in Finder

The welcome window must not flash or appear briefly when opening a file from Finder. It is managed programmatically by AppDelegate (not as a SwiftUI Scene) to ensure it only appears after confirming no documents are being opened.

## Content

- App icon (128x128)
- "CDF Viewer" title
- Subtitle: "View NASA Common Data Format files"
- Attribution links (byJP, Iota Technology)
- "Open a CDF File" button that presents the system file picker

## Window Style

- Hidden title bar (transparent, content extends behind it)
- Fixed size (400x340)
- Centered on screen
- Closable, movable by background
- Excluded from Window menu
