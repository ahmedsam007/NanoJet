# IDMMac

A fast, lightweight macOS download manager with segmented downloading, pause/resume, and a simple Chrome extension handoff.

## Features
- Segmented (multi-connection) downloads
- Pause / Resume / Cancel
- Resume via HTTP Range data
- Speed, ETA, percent; Dock badge progress
- SHA-256 on completed files
- Auto-reconnect and optional shutdown-when-done

## Build
- macOS 13+, Xcode 15+
- Open `IDMMac.xcodeproj` → scheme `IDMMacApp` → Run

## Chrome Extension (optional)
- Folder: `Tools/ChromeExtension/`
- chrome://extensions → Developer Mode → Load unpacked

## Structure
- `IDMMacApp/` SwiftUI app and UI
- `DownloadEngine/` SwiftPM engine
- `Tools/ChromeExtension/` MV3 extension

## License
MIT
