# 🔄 Removing Sparkle for Mac App Store

This guide shows you exactly how to remove Sparkle framework from your code for App Store submission.

---

## 🎯 Why Remove Sparkle?

**Mac App Store apps CANNOT use third-party update mechanisms.**

Apple's App Store Review Guidelines require that apps distributed through the Mac App Store:
- ✅ Use Apple's built-in update system
- ❌ Cannot check for updates from external servers
- ❌ Cannot download or install updates independently

**Good News:** Apple handles updates automatically - you just submit new versions!

---

## 📝 Step-by-Step Removal Process

### Step 1: Identify Sparkle Usage

Let's find all Sparkle references in your code:

```bash
cd /Users/ahmed/Documents/NanoJet

# Find all Sparkle imports
echo "=== Sparkle Imports ==="
grep -r "import Sparkle" NanoJetApp/

# Find UpdaterManager usage
echo "=== UpdaterManager References ==="
grep -r "UpdaterManager" NanoJetApp/

# Find "Check for Updates" menu items
echo "=== Update Menu Items ==="
grep -r "Check for Updates" NanoJetApp/
grep -r "checkForUpdates" NanoJetApp/
```

### Step 2: Remove from Dependencies

**Option A: Using project.yml (if you use XcodeGen)**

Edit `project.yml`:

```yaml
packages:
  DownloadEngine:
    path: ./DownloadEngine
  # Remove this entire section:
  # Sparkle:
  #   url: https://github.com/sparkle-project/Sparkle
  #   exactVersion: 2.6.4
```

And in targets:

```yaml
dependencies:
  - package: DownloadEngine
    product: DownloadEngine
  # Remove this:
  # - package: Sparkle
  #   product: Sparkle
```

Then regenerate:
```bash
xcodegen generate
```

**Option B: Manual Xcode Project**

1. Open `NanoJet.xcodeproj` in Xcode
2. Select project → Target: NanoJetApp
3. Go to **Frameworks, Libraries, and Embedded Content**
4. Find `Sparkle.framework`
5. Click **-** to remove
6. Go to **Package Dependencies** tab
7. Select Sparkle → Click **-** to remove

### Step 3: Update Info.plist

**Automatic:** The configuration script already created `Info-AppStore.plist` without Sparkle keys.

**Manual:** Edit `NanoJetApp/Resources/Info.plist` and remove these lines:

```xml
<!-- REMOVE ALL OF THESE -->
<key>SUFeedURL</key>
<string>https://ahmedsam007.github.io/IdmMac/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>yV8yqP+FQ12R82ya1T/khpSwar0R9JadjTK9ITUbCkY=</string>

<key>SUEnableAutomaticChecks</key>
<true/>

<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<key>SUAllowsAutomaticUpdates</key>
<true/>
```

### Step 4: Handle UpdaterManager.swift

**File Location:** `NanoJetApp/Utilities/UpdaterManager.swift`

**Option A: Delete the File** (Recommended)
```bash
rm NanoJetApp/Utilities/UpdaterManager.swift
```

**Option B: Disable with Compilation Flag**

Wrap the entire file content:

```swift
#if !APP_STORE

import Sparkle

@Observable
final class UpdaterManager {
    static let shared = UpdaterManager()
    
    private let updaterController: SPUStandardUpdaterController
    
    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

#else

// App Store version - no manual updates needed
@Observable
final class UpdaterManager {
    static let shared = UpdaterManager()
    
    private init() {}
    
    func checkForUpdates() {
        // No-op: App Store handles updates
    }
}

#endif
```

Then add to your build settings: `OTHER_SWIFT_FLAGS = -DAPP_STORE` for Release builds.

### Step 5: Update UI Code

Now let's remove update-related UI elements.

#### Check Your Menu/Settings

Search for where you have "Check for Updates":

```bash
grep -rn "Check for Updates" NanoJetApp/
```

Common locations:
- App menu configuration
- Settings view
- About window

#### Example: If using SwiftUI Commands

If you have something like this in `NanoJetApp.swift`:

```swift
import SwiftUI

@main
struct NanoJetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About NanoJet") {
                    // About action
                }
            }
            
            // REMOVE THIS ENTIRE SECTION FOR APP STORE:
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdaterManager.shared.checkForUpdates()
                }
                Divider()
            }
        }
    }
}
```

**Change to:**

```swift
import SwiftUI

@main
struct NanoJetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About NanoJet") {
                    // About action
                }
            }
            
            // No "Check for Updates" in App Store version
            // Apple handles updates automatically
        }
    }
}
```

#### If using NSMenu (AppKit)

Look for menu setup code:

```swift
// REMOVE or COMMENT OUT:
let updateItem = NSMenuItem(
    title: "Check for Updates...",
    action: #selector(checkForUpdates),
    keyEquivalent: ""
)
menu.addItem(updateItem)

// And remove the method:
/*
@objc func checkForUpdates() {
    UpdaterManager.shared.checkForUpdates()
}
*/
```

#### If you have a Settings gear icon

In your `SettingsView.swift` or similar, remove update-related buttons:

```swift
// REMOVE:
Button("Check for Updates...") {
    UpdaterManager.shared.checkForUpdates()
}

// REMOVE:
Text("Automatic updates enabled")
```

### Step 6: Update About Window (Optional)

If your About window mentions updates, consider updating the text:

**Before:**
```swift
Text("NanoJet automatically checks for updates every 24 hours")
```

**After:**
```swift
Text("Updates are delivered automatically through the Mac App Store")
```

### Step 7: Clean Imports

Search for any remaining Sparkle imports:

```bash
# Find all files with Sparkle import
grep -l "import Sparkle" NanoJetApp/**/*.swift
```

For each file found, remove:
```swift
import Sparkle  // DELETE THIS LINE
```

### Step 8: Verify Build

Now test that everything compiles:

```bash
cd /Users/ahmed/Documents/NanoJet

# Clean build
xcodebuild clean -project NanoJet.xcodeproj -scheme NanoJetApp

# Build
xcodebuild build -project NanoJet.xcodeproj -scheme NanoJetApp -configuration Release
```

Or in Xcode:
1. **Product** → **Clean Build Folder** (⌥⇧⌘K)
2. **Product** → **Build** (⌘B)
3. Fix any compilation errors

---

## 🧪 Testing

After removing Sparkle, test your app:

1. **Launch the app**
2. **Verify no crashes** on startup
3. **Check menus** - no "Check for Updates" item
4. **Test all features** - ensure nothing else broke

---

## 🎯 Verification Checklist

Before proceeding to App Store submission:

- [ ] No compilation errors
- [ ] App launches successfully
- [ ] No "Check for Updates" in menus
- [ ] No Sparkle imports in code
- [ ] Info.plist has no `SU*` keys
- [ ] UpdaterManager not referenced anywhere
- [ ] Build succeeds in Release configuration

**Verify with these commands:**

```bash
# Should return nothing:
grep -r "import Sparkle" NanoJetApp/
grep -r "UpdaterManager" NanoJetApp/ --include="*.swift"
grep "SUFeedURL" NanoJetApp/Resources/Info.plist

# All of above should have no output (empty results)
```

---

## 🔄 Alternative: Dual Configuration

If you want to maintain BOTH App Store and direct distribution versions:

### Use Compilation Flags

**In project.yml:**
```yaml
settings:
  configs:
    Release-AppStore:
      OTHER_SWIFT_FLAGS: -DAPP_STORE
      ENABLE_APP_SANDBOX: YES
    Release-Direct:
      OTHER_SWIFT_FLAGS: -DDIRECT_DISTRIBUTION
      ENABLE_APP_SANDBOX: NO
```

**In code:**
```swift
#if APP_STORE
    // App Store version - no Sparkle
#else
    // Direct distribution - with Sparkle
    import Sparkle
#endif
```

This allows you to:
- Build **Release-AppStore** configuration → for Mac App Store
- Build **Release-Direct** configuration → for website download

---

## 📱 What About Users on Direct Distribution?

If you already have users who downloaded directly from your website:

**Option 1: Migrate to App Store (Recommended)**
1. Submit to App Store
2. Update your website to redirect to Mac App Store
3. Add migration notice in your app (if you release one more direct update)

**Option 2: Maintain Both**
- Keep direct distribution with Sparkle
- Also distribute through App Store
- Use different bundle IDs: `com.ahmedsam.idmmac.direct` vs `com.ahmedsam.idmmac`

---

## 🎉 You're Done!

Once you've completed all steps:

1. ✅ Sparkle removed from code
2. ✅ UI updated (no update menu items)
3. ✅ App builds successfully
4. ✅ App runs without errors

**Next step:** Continue with [APP_STORE_CHECKLIST.md](./APP_STORE_CHECKLIST.md) to submit!

---

## 💡 Pro Tips

**For future updates:**
- Just increment version number
- Archive and upload to App Store Connect
- Apple distributes automatically to all users

**Users get updates:**
- Automatically (if they have auto-updates enabled)
- Or manually through Mac App Store app

**You control:**
- When to submit new versions
- Release notes for each version
- Phased rollout (optional, for gradual deployment)

---

## 📞 Need Help?

**Common Issues:**

**Q: Build fails with "No such module 'Sparkle'"**
A: You missed removing a Sparkle import. Search: `grep -r "import Sparkle" NanoJetApp/`

**Q: App crashes on launch after removing Sparkle**
A: Check if you're still calling `UpdaterManager.shared` somewhere. Search: `grep -r "UpdaterManager" NanoJetApp/`

**Q: Can I keep Sparkle for testing?**
A: Not in the App Store build. Use compilation flags to maintain separate builds.

---

**Last Updated:** October 23, 2025

