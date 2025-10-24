# 🔄 Code Changes Required for App Store

This document shows **exactly** what code changes you need to make to remove Sparkle for App Store submission.

---

## 📋 Summary of Changes

**Files to Modify:**
1. ✅ `NanoJetApp/App/NanoJetApp.swift` - Remove Sparkle import and "Check for Updates" menu
2. ✅ `NanoJetApp/UI/ContentView.swift` - Remove "Check for Updates" from gear menu
3. ✅ `NanoJetApp/UI/AboutView.swift` - Remove "Check for Updates" button
4. ✅ `NanoJetApp/Utilities/UpdaterManager.swift` - Delete file (or create stub)

**Files NOT to Change:**
- ❌ `YouTubeSetupView.swift` - This "Check for Updates" is for yt-dlp tool, not the app!

---

## 🛠️ Method 1: Use Pre-Made App Store Files (EASIEST)

I've created App Store-ready versions of your files:

```bash
cd /Users/ahmed/Documents/NanoJet

# Backup originals
mkdir -p backups
cp NanoJetApp/App/NanoJetApp.swift backups/
cp NanoJetApp/Resources/Info.plist backups/
cp NanoJetApp/App/NanoJetApp.entitlements backups/

# Use App Store versions
cp NanoJetApp/App/NanoJetApp-AppStore.swift NanoJetApp/App/NanoJetApp.swift
cp NanoJetApp/Resources/Info-AppStore.plist NanoJetApp/Resources/Info.plist
cp NanoJetApp/App/NanoJetApp-AppStore.entitlements NanoJetApp/App/NanoJetApp.entitlements

# Delete UpdaterManager (or rename it)
mv NanoJetApp/Utilities/UpdaterManager.swift backups/
```

**Then manually edit these 2 files:**
- `NanoJetApp/UI/ContentView.swift` (see below)
- `NanoJetApp/UI/AboutView.swift` (see below)

---

## 🛠️ Method 2: Manual Changes (DETAILED)

### Change 1: NanoJetApp/App/NanoJetApp.swift

**Line 5 - Remove Sparkle import:**

```swift
// BEFORE:
import Sparkle

// AFTER:
// Sparkle removed for App Store - Apple handles updates
```

**Lines 90-94 - Remove "Check for Updates" menu:**

```swift
// BEFORE:
CommandGroup(after: .appInfo) {
    Button("Check for Updates…") {
        UpdaterManager.shared.checkForUpdates()
    }
}

// AFTER:
// "Check for Updates" removed - App Store handles updates automatically
```

### Change 2: NanoJetApp/UI/ContentView.swift

**Find this section around line 630:**

```swift
// BEFORE:
Divider()
Button {
    UpdaterManager.shared.checkForUpdates()
} label: {
    Label("Check for Updates…", systemImage: "arrow.down.circle")
}
Button {
    showFeedbackSheet = true
} label: {
    Label("Send Feedback", systemImage: "envelope")
}

// AFTER:
Divider()
// "Check for Updates" removed for App Store
Button {
    showFeedbackSheet = true
} label: {
    Label("Send Feedback", systemImage: "envelope")
}
```

**The exact change:**
Delete lines 630-634 (the UpdaterManager button)

### Change 3: NanoJetApp/UI/AboutView.swift

**Find this section around line 88:**

```swift
// BEFORE:
// Update & Close Buttons
HStack(spacing: 12) {
    Button("Check for Updates") {
        UpdaterManager.shared.checkForUpdates()
    }
    .buttonStyle(.bordered)
    
    Button("Close") {
        dismiss()
    }
    .buttonStyle(.borderedProminent)
    .keyboardShortcut(.defaultAction)
}

// AFTER:
// Close Button
HStack(spacing: 12) {
    // "Check for Updates" removed for App Store
    
    Button("Close") {
        dismiss()
    }
    .buttonStyle(.borderedProminent)
    .keyboardShortcut(.defaultAction)
}
```

**The exact change:**
Delete lines 89-92 (the "Check for Updates" button)

### Change 4: NanoJetApp/Utilities/UpdaterManager.swift

**Option A: Delete the file** (recommended)

```bash
rm NanoJetApp/Utilities/UpdaterManager.swift
```

**Option B: Create a stub** (if you want to keep file structure)

Replace entire file contents with:

```swift
// UpdaterManager.swift - App Store Version
// Sparkle removed - Mac App Store handles updates automatically

import Foundation

/// Stub for UpdaterManager - no-op in App Store version
/// Apple provides automatic updates through the App Store
final class UpdaterManager {
    static let shared = UpdaterManager()
    
    private init() {
        // No initialization needed
    }
    
    func checkForUpdates() {
        // No-op: App Store handles updates
        print("App Store version - updates handled by Apple")
    }
}
```

---

## ✅ Quick Apply Script

Save this as `apply-appstore-changes.sh`:

```bash
#!/bin/bash

cd /Users/ahmed/Documents/NanoJet

echo "📦 Applying App Store code changes..."

# Backup
mkdir -p backups/$(date +%Y%m%d-%H%M%S)
cp NanoJetApp/App/NanoJetApp.swift backups/$(date +%Y%m%d-%H%M%S)/
echo "✅ Backups created"

# Apply prepared files
if [ -f "NanoJetApp/App/NanoJetApp-AppStore.swift" ]; then
    cp NanoJetApp/App/NanoJetApp-AppStore.swift NanoJetApp/App/NanoJetApp.swift
    echo "✅ Updated NanoJetApp.swift"
fi

# Remove UpdaterManager
if [ -f "NanoJetApp/Utilities/UpdaterManager.swift" ]; then
    mv NanoJetApp/Utilities/UpdaterManager.swift backups/$(date +%Y%m%d-%H%M%S)/
    echo "✅ Removed UpdaterManager.swift"
fi

echo ""
echo "⚠️  MANUAL STEPS REQUIRED:"
echo "1. Edit NanoJetApp/UI/ContentView.swift - remove lines 630-634"
echo "2. Edit NanoJetApp/UI/AboutView.swift - remove lines 89-92"
echo ""
echo "See CODE_CHANGES_FOR_APPSTORE.md for details"
```

Run it:
```bash
chmod +x apply-appstore-changes.sh
./apply-appstore-changes.sh
```

---

## 🧪 Testing After Changes

```bash
# Clean build
rm -rf build/
xcodebuild clean -project NanoJet.xcodeproj -scheme NanoJetApp

# Build
xcodebuild build -project NanoJet.xcodeproj -scheme NanoJetApp -configuration Release

# If successful, run the app and verify:
# 1. App launches without errors
# 2. No "Check for Updates" in menus
# 3. All other features work normally
```

---

## ✅ Verification Checklist

After making changes:

- [ ] No compilation errors
- [ ] App launches successfully
- [ ] No Sparkle imports: `grep -r "import Sparkle" NanoJetApp/`
- [ ] No UpdaterManager calls: `grep -r "UpdaterManager" NanoJetApp/`
- [ ] No "Check for Updates" in App menu
- [ ] No "Check for Updates" in gear menu
- [ ] No "Check for Updates" button in About window
- [ ] All download features still work

---

## 📝 Detailed File Diffs

### NanoJetApp.swift diff:

```diff
- import Sparkle
+ // Sparkle removed for App Store

  CommandGroup(replacing: .appInfo) {
      // About NanoJet is now available in the gear menu
  }
- CommandGroup(after: .appInfo) {
-     Button("Check for Updates…") {
-         UpdaterManager.shared.checkForUpdates()
-     }
- }
+ // "Check for Updates" removed - App Store handles updates
```

### ContentView.swift diff:

```diff
  } label: {
      Label("Open Automation Privacy…", systemImage: "lock")
  }
  Divider()
- Button {
-     UpdaterManager.shared.checkForUpdates()
- } label: {
-     Label("Check for Updates…", systemImage: "arrow.down.circle")
- }
  Button {
      showFeedbackSheet = true
  } label: {
```

### AboutView.swift diff:

```diff
  Spacer()
  
- // Update & Close Buttons
+ // Close Button
  HStack(spacing: 12) {
-     Button("Check for Updates") {
-         UpdaterManager.shared.checkForUpdates()
-     }
-     .buttonStyle(.bordered)
-     
      Button("Close") {
          dismiss()
      }
```

---

## 🎯 What NOT to Change

**YouTubeSetupView.swift:**

This file has a "Check for Updates" button, but it's for updating **yt-dlp** (the YouTube downloader tool), NOT the app itself. **Leave it as-is!**

```swift
// This is OK to keep - it updates yt-dlp, not the app
Button("Check for Updates") {
    Task {
        await ytdlpManager.updateYTDLP()  // ← Updates yt-dlp tool
    }
}
```

---

## 💡 Pro Tips

1. **Test in Debug first** before building Release
2. **Use version control** - commit your changes
3. **Keep backups** of working direct distribution version
4. **Document your changes** in git commit message

---

## 🔄 Reverting Changes

If you need to go back to direct distribution:

```bash
cd /Users/ahmed/Documents/NanoJet

# Restore from backups
cp backups/YYYYMMDD-HHMMSS/NanoJetApp.swift NanoJetApp/App/
cp backups/YYYYMMDD-HHMMSS/UpdaterManager.swift NanoJetApp/Utilities/

# Re-add Sparkle to project
# Edit project.yml to add Sparkle back
xcodegen generate
```

---

## 📞 Need Help?

If you get stuck:

1. Check compilation errors carefully
2. Make sure you removed ALL Sparkle references
3. Verify UpdaterManager isn't called anywhere
4. Try clean build: `rm -rf build/`

---

**Created:** October 23, 2025  
**Last Updated:** October 23, 2025

