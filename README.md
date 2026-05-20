# WindowLayout

A native macOS SwiftUI app that saves and restores window positions and sizes per display configuration — automatically.

## Features

- **Live tracking** — records window positions as you move/resize them (800ms debounce)
- **Screen fingerprinting** — uniquely identifies every display by its hardware ID, so layouts are tied to the exact physical monitors
- **Auto-restore** — when a display configuration reconnects, the saved layout is applied automatically
- **CGWindowList capture** — snapshots all visible windows across all apps, not just the manager itself
- **AppleScript restore** — moves windows in other apps via `set bounds of front window`
- **Named layouts** — rename, manage, and delete layouts per screen config
- **Live activity log** — see every tracking event in real time

## Requirements

- macOS 15.0 (Sonoma) or later
- Xcode 15+

## Setup

1. Open `WindowLayout.xcodeproj` in Xcode
2. Select your Development Team in Signing & Capabilities
3. Build & Run (⌘R)

### Permissions needed

| Permission | Why |
|---|---|
| **Accessibility** | To move windows in other apps (System Settings → Privacy → Accessibility) |
| **Automation / Apple Events** | Granted automatically on first use (moving another app's window) |

## How it works

### Screen fingerprinting
Each physical display reports a unique `NSScreenNumber` via `NSDeviceDescriptionKey`. This app combines all connected screen numbers + resolutions into a sorted key like:

```
12345678@2560x1600+87654321@2560x1440
```

When displays change, a new key is computed and matched against saved layouts.

### Window capture
Uses `CGWindowListCopyWindowInfo` to snapshot all on-screen windows (layer 0) including their global frame in screen coordinates. Tiny utility windows (<50px) are ignored.

### Coordinate system
- **CGWindowList** uses top-left origin (screen coordinates)
- **AppKit / NSWindow** uses bottom-left origin
- The manager converts between them using the primary screen height

### Auto-save debounce
Window move/resize notifications are debounced for 800ms — the layout is only written after the window has been still for that duration, avoiding excessive disk writes while dragging.

### Restore for other apps
The restore path uses AppleScript:
```applescript
tell application "AppName"
    set bounds of front window to {x, y, x2, y2}
end tell
```
This requires Accessibility permission and works with most standard macOS apps.

## File structure

```
WindowLayout/
├── WindowLayoutApp.swift       # App entry point + AppDelegate
├── WindowLayoutManager.swift   # Core tracking, save, and restore engine
├── ScreenFingerprint.swift     # Unique display config identification
├── WindowRecord.swift          # Data models (WindowRecord, LayoutSnapshot, LayoutStore)
├── ContentView.swift           # Main navigation shell
├── LayoutsView.swift           # Saved layouts browser + detail
├── ActivityView.swift          # Live event log
├── SettingsView.swift          # Preferences
└── WindowLayout.entitlements   # App entitlements
```

## Data storage

Layouts are saved to:
```
~/Library/Application Support/WindowLayout/layouts.json
```

The JSON structure:
```json
{
  "autoSaveEnabled": true,
  "autoRestoreEnabled": true,
  "restoreAnimated": true,
  "snapshots": {
    "12345678@2560x1600": {
      "name": "MacBook Built-in",
      "screenKey": "12345678@2560x1600",
      "records": [
        {
          "windowID": { "appBundleID": "Xcode", "windowTitle": "MyProject" },
          "globalFrame": { "x": 100, "y": 200, "width": 1400, "height": 900 },
          "screenKey": "12345678@2560x1600",
          "savedAt": "2025-01-01T10:00:00Z"
        }
      ]
    }
  }
}
```

## Limitations

- **Own-process windows**: NSWindow restoration is instant and precise
- **Other apps**: AppleScript only moves the frontmost window of each app; background windows require the app to be focused first
- **Full Accessibility**: For complete multi-window restore across all apps, the Accessibility API (`AXUIElement`) can be used as an enhancement — see comments in `WindowManager.swift`
- **Sandboxed apps**: Some Mac App Store apps may not accept Apple Events

## Enhancement ideas

- Menu bar icon for quick save/restore without opening the main window
- AXUIElement-based restore for precise multi-window control
- Per-app layout overrides
- Hotkey support (via `NSEvent.addGlobalMonitorForEvents`)
- iCloud sync of layouts across Macs
