# ✅ Mac App Store Submission Checklist

Use this checklist to track your progress preparing NanoJet for the Mac App Store.

---

## 📱 Phase 1: Apple Developer Account (30-60 minutes)

- [ ] **Apple Developer account is active** ($99/year paid)
- [ ] **Logged into** [developer.apple.com](https://developer.apple.com/account)
- [ ] **Created App ID**
  - Bundle ID: `com.ahmedsam.idmmac`
  - Capabilities: App Sandbox, Network, File Access enabled
- [ ] **Created Mac App Distribution Certificate**
  - Certificate installed in Keychain Access
  - Verified with: `security find-identity -v -p codesigning`
- [ ] **Created Mac Installer Distribution Certificate** (for pkg)
- [ ] **Created Provisioning Profile**
  - Name: "NanoJet App Store Profile"
  - Downloaded and installed
  - Verified in: `~/Library/MobileDevice/Provisioning Profiles/`

**How to verify:**
```bash
# Check certificates
security find-identity -v -p codesigning | grep "3rd Party Mac Developer"

# Check provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/
```

---

## 🔧 Phase 2: Xcode Configuration (30 minutes)

- [ ] **Ran configuration script**
  ```bash
  cd /Users/ahmed/Documents/NanoJet
  ./configure-appstore.sh
  ```
- [ ] **Updated Xcode project settings**
  - Opened `NanoJet.xcodeproj` in Xcode
  - Target → Signing & Capabilities
  - Unchecked "Automatically manage signing"
  - Set Team ID
  - Debug: Mac Developer certificate
  - Release: 3rd Party Mac Developer Application
  - Provisioning Profile: NanoJet App Store Profile

- [ ] **Verified Build Settings**
  - `CODE_SIGN_STYLE = Manual`
  - `ENABLE_APP_SANDBOX = YES`
  - `ENABLE_HARDENED_RUNTIME = YES` (Release)
  - `DEVELOPMENT_TEAM = YOUR_TEAM_ID`

- [ ] **Removed Sparkle Framework**
  - Removed from project dependencies
  - Removed from Link Binary with Libraries

- [ ] **Updated Info.plist**
  - Removed `SUFeedURL`
  - Removed `SUPublicEDKey`
  - Removed all `SU*` keys
  - Added `LSApplicationCategoryType`

- [ ] **Updated Entitlements**
  - Using `NanoJetApp-AppStore.entitlements`
  - Sandbox enabled
  - Only App Store-approved entitlements

---

## 💻 Phase 3: Code Changes (1-2 hours)

- [ ] **Removed Sparkle imports**
  - Search project for `import Sparkle`
  - Comment out or remove all imports

- [ ] **Removed UpdaterManager usage**
  - File: `NanoJetApp/Utilities/UpdaterManager.swift`
  - Either delete file or disable functionality
  - Remove any calls to `UpdaterManager`

- [ ] **Updated UI - Remove Update Menu Items**
  - Removed "Check for Updates..." menu item
  - Removed update-related buttons/UI
  - Search for: "Check for Updates", "update", "Sparkle"

- [ ] **Tested Build**
  - Build succeeded without errors
  - Run in Debug mode - no Sparkle warnings

**Files to check:**
```bash
# Find Sparkle references
grep -r "import Sparkle" NanoJetApp/
grep -r "UpdaterManager" NanoJetApp/
grep -r "Check for Updates" NanoJetApp/
```

---

## 🌐 Phase 4: App Store Connect (1 hour)

- [ ] **Logged into** [App Store Connect](https://appstoreconnect.apple.com)
- [ ] **Created App Record**
  - Platform: macOS
  - Name: NanoJet (or your chosen name)
  - Bundle ID: com.ahmedsam.idmmac
  - SKU: IDMMAC001

- [ ] **Filled App Information**
  - Primary category: Utilities
  - Subtitle (optional)
  - Privacy Policy URL: `https://ahmedsam.com/idmmac/privacy`

- [ ] **Set Pricing**
  - Free or Paid price selected
  - Territories selected

- [ ] **Prepared Screenshots** (minimum 3 required)
  - Screenshot 1: Main window with download
  - Screenshot 2: Multiple downloads
  - Screenshot 3: Settings/Features
  - Resolution: 1280x800 or higher (16:10 aspect ratio)

- [ ] **App Description Written**
  - Short description (170 characters)
  - Full description
  - Keywords (100 characters max)
  - What's New (for version 1.0.0)

- [ ] **App Review Information**
  - Contact information filled
  - Notes for reviewer written
  - Demo account (if needed)

---

## 🚀 Phase 5: Build & Submit (1-2 hours)

- [ ] **Version Numbers Updated**
  - Marketing Version: 1.0.0
  - Current Project Version: 1
  - Updated in `project.yml` or Xcode

- [ ] **Clean Build**
  ```bash
  # Clean all caches
  rm -rf build/
  rm -rf ~/Library/Developer/Xcode/DerivedData/NanoJet-*
  ```

- [ ] **Created Archive**
  - Product → Clean Build Folder (⌥⇧⌘K)
  - Product → Archive (⌘B won't work, must Archive)
  - Archive completed without errors

- [ ] **Validated Archive**
  - Xcode → Organizer → Archives
  - Selected archive → Validate App
  - Choose App Store Connect distribution
  - Validation passed ✅

- [ ] **Uploaded to App Store Connect**
  - Organizer → Distribute App
  - Choose App Store Connect
  - Upload completed successfully
  - Processing started (wait 30min-2hrs)

- [ ] **Completed App Store Connect Setup**
  - Build processing complete
  - Build selected for version 1.0.0
  - All screenshots uploaded
  - All metadata complete
  - Export compliance answered

- [ ] **Submitted for Review**
  - Clicked "Add for Review"
  - Status changed to "Waiting for Review"

---

## 📊 Post-Submission Tracking

**Submission Date:** `_______________`

**Timeline:**
- [ ] Build uploaded: `_______________`
- [ ] Processing complete: `_______________`
- [ ] Submitted for review: `_______________`
- [ ] In review: `_______________`
- [ ] Approved/Rejected: `_______________`
- [ ] Released: `_______________`

**Expected Timeline:**
- Processing: 30 minutes - 2 hours
- Review: 1-3 days (sometimes up to 7 days)

---

## 🐛 Troubleshooting

### If validation fails:

**Common Issue: "No valid signing identity"**
- Solution: Re-download certificates and profiles from developer portal
- Restart Xcode after installing

**Common Issue: "Provisioning profile doesn't match"**
- Solution: Ensure bundle ID in Xcode matches exactly: `com.ahmedsam.idmmac`
- Recreate provisioning profile if needed

**Common Issue: "Invalid entitlements"**
- Solution: Use `NanoJetApp-AppStore.entitlements` 
- Remove any non-approved entitlements

**Common Issue: "Upload failed"**
- Solution: Check internet connection
- Try uploading with Application Loader or Transporter app
- Verify archive is under 4GB

### If rejected by App Store Review:

1. **Read rejection reason carefully**
2. **Fix issues** mentioned in Resolution Center
3. **Reply with explanation** if you think it's a misunderstanding
4. **Submit new build** with fixes
5. **Response time:** Reviews usually respond within 24-48 hours

---

## 📚 Quick Commands Reference

```bash
# Check certificates
security find-identity -v -p codesigning

# Check provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/

# Find Sparkle references
grep -r "Sparkle" NanoJetApp/

# Check app version
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  NanoJetApp/Resources/Info.plist

# Clean build
rm -rf build/ ~/Library/Developer/Xcode/DerivedData/NanoJet-*

# Archive from command line
xcodebuild archive \
  -project NanoJet.xcodeproj \
  -scheme NanoJetApp \
  -configuration Release \
  -archivePath ~/Desktop/NanoJetApp.xcarchive

# Export for App Store
xcodebuild -exportArchive \
  -archivePath ~/Desktop/NanoJetApp.xcarchive \
  -exportPath ~/Desktop/NanoJetApp-AppStore \
  -exportOptionsPlist Tools/ExportOptionsAppStore.plist
```

---

## 🎯 Success Criteria

You're ready to submit when ALL of these are true:

- ✅ Archive validates without errors
- ✅ No Sparkle references in code
- ✅ App runs properly with App Sandbox enabled
- ✅ All screenshots and metadata complete
- ✅ Privacy policy hosted and accessible
- ✅ Team ID and certificates configured correctly

---

## 📞 Need Help?

**Resources:**
- [Full Guide](./APP_STORE_SETUP_GUIDE.md) - Detailed step-by-step instructions
- [Apple Developer Forums](https://developer.apple.com/forums/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)

**Contact:**
- Apple Developer Support: https://developer.apple.com/contact/
- Available with paid developer account

---

**Created:** October 23, 2025  
**Last Updated:** October 23, 2025

