# Code Signing Fix for IDMMac

## Problem

When building IDMMac without a Team ID (ad-hoc signing), the app crashes on launch with this error:

```
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Reason: code signature ... not valid for use in process: 
mapping process and mapped file (non-platform) have different Team IDs
```

## Root Cause

The Sparkle framework (added via Swift Package Manager) comes with its own code signature from the Sparkle team. When your app is built with ad-hoc signing (no Team ID), macOS refuses to load the Sparkle framework because it has a different code signature than your app.

## Solution

### Automated (Recommended)

The `release.sh` script now automatically re-signs all embedded frameworks after building. Just run:

```bash
./Tools/release.sh 0.1.0
```

### Manual Fix

If you already have a built app that won't launch, re-sign it manually:

```bash
./Tools/resign-frameworks.sh "path/to/IDMMacApp.app"
```

For example:

```bash
./Tools/resign-frameworks.sh "IDMMacApp 2025-10-21 00-56-17/IDMMacApp.app"
```

## What the Script Does

1. Removes existing signatures from Sparkle framework components
2. Re-signs all XPC services (Downloader.xpc, Installer.xpc)
3. Re-signs Updater.app
4. Re-signs the main Sparkle framework
5. Re-signs the entire app bundle with consistent signatures
6. Verifies the final signature

## For Distribution Builds

If you're building for distribution with a proper Developer ID:

1. Update `ExportOptions.plist` with your Team ID
2. Update `project.pbxproj` DEVELOPMENT_TEAM setting
3. Xcode will automatically handle framework signing

## Verification

After re-signing, verify the app signature:

```bash
codesign -vvv --deep --strict IDMMacApp.app
```

You should see "satisfies its Designated Requirement" with no errors.

## Testing

1. Double-click the app to launch it
2. It should open without crash reports
3. Check Console.app for any remaining signature warnings

