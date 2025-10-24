# NanoJet

[![Build NanoJet](https://github.com/ahmedsam007/NanoJet/actions/workflows/swift.yml/badge.svg)](https://github.com/ahmedsam007/NanoJet/actions/workflows/swift.yml)

A fast, lightweight macOS download manager with segmented downloading, pause/resume, and a simple Chrome extension handoff.

## Features
- Segmented (multi-connection) downloads
- Pause / Resume / Cancel
- Resume via HTTP Range data
- Speed, ETA, percent; Dock badge progress
- SHA-256 on completed files
- Auto-reconnect and optional shutdown-when-done
- Automatic updates via Sparkle 2 framework

## Build
- macOS 13+, Xcode 15+
- Open `NanoJet.xcodeproj` → scheme `NanoJetApp` → Run

## Distribute (direct download)
1) Create a Release build
- Xcode → Product → Archive → Distribute App → Developer ID
- Ensure Hardened Runtime is enabled and entitlements are correct

2) Notarize and staple
- You can use the helper script `Tools/release-notarize.sh` (see header in the file for usage)
- Or manually:
  - Sign the .app with your Developer ID Application certificate
  - Zip the app: `ditto -c -k --keepParent NanoJetApp.app NanoJetApp.zip`
  - Notarize: `xcrun notarytool submit NanoJetApp.zip --keychain-profile AC_PROFILE --wait`
  - Staple: `xcrun stapler staple NanoJetApp.app`

3) Publish
- Upload the stapled `NanoJetApp.zip` to your website
- Provide SHA-256 checksum alongside the download

Note: For best UX, consider shipping a `.dmg` with a drag-to-Applications window. The script can generate both `.zip` and `.dmg`.

## Automatic Updates (Sparkle 2)

NanoJet includes Sparkle 2 for secure automatic updates:
- HTTPS update feed checking
- EdDSA signature verification  
- One-click updates for users
- Checks for updates every 24 hours automatically

### Setup Updates
See [SPARKLE_SETUP.md](SPARKLE_SETUP.md) for complete instructions on:
- Generating EdDSA keys
- Creating appcast feed
- Signing releases
- Publishing updates

**Quick Start:**
1. Generate keys: `./Sparkle/bin/generate_keys`
2. Add public key to `Info.plist` (replace `YOUR_SPARKLE_PUBLIC_KEY_HERE`)
3. Update `SUFeedURL` to your appcast URL
4. Sign releases and publish appcast.xml

## Chrome Extension (optional)
- Folder: `Tools/ChromeExtension/`
- chrome://extensions → Developer Mode → Load unpacked

## Structure
- `NanoJetApp/` SwiftUI app and UI
- `DownloadEngine/` SwiftPM engine
- `Tools/ChromeExtension/` MV3 extension

## License
MIT
