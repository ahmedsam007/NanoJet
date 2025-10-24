# ⚡ Mac App Store Quick Start Guide

**Get your app in the App Store in 3-4 hours!**

This is the TL;DR version. For complete details, see [APP_STORE_SETUP_GUIDE.md](APP_STORE_SETUP_GUIDE.md)

---

## 🎯 Prerequisites

- ✅ Apple Developer account approved ($99/year)
- ✅ macOS with Xcode installed
- ✅ Your Apple ID and Team ID ready

---

## 🚀 Phase 1: Apple Developer Portal (30 min)

### 1. Create Certificates

Go to [developer.apple.com](https://developer.apple.com/account) → Certificates, Identifiers & Profiles

**A. Request Certificate:**
1. Open Keychain Access → Certificate Assistant → Request Certificate from CA
2. Save `.certSigningRequest` file

**B. Create Mac App Distribution Certificate:**
1. Certificates → **+** → Mac App Distribution
2. Upload `.certSigningRequest` → Download
3. Double-click to install

**C. Create Mac Installer Distribution Certificate:**
1. Same process, but choose "Mac Installer Distribution"

### 2. Create App ID

1. Identifiers → **+** → App IDs
2. Bundle ID: `com.ahmedsam.idmmac` (explicit)
3. Enable: App Sandbox, Network Client, File Access
4. Register

### 3. Create Provisioning Profile

1. Profiles → **+** → Mac App Store
2. Select: `com.ahmedsam.idmmac`
3. Select: Your Mac App Distribution certificate
4. Name: `NanoJet App Store Profile`
5. Download and double-click to install

---

## 🔧 Phase 2: Configure Your Project (30 min)

### Quick Configuration:

```bash
cd /Users/ahmed/Documents/NanoJet

# Run the setup script
./configure-appstore.sh

# Follow the prompts and enter your Team ID
```

### What it does:
- ✅ Backs up current configuration
- ✅ Switches to App Store settings
- ✅ Removes Sparkle configuration
- ✅ Updates entitlements and Info.plist

### Manual Steps After Script:

1. **Remove Sparkle from Code:**
   ```bash
   # Apply prepared App Store versions
   cp NanoJetApp/App/NanoJetApp-AppStore.swift NanoJetApp/App/NanoJetApp.swift
   
   # Backup and remove UpdaterManager
   mv NanoJetApp/Utilities/UpdaterManager.swift backups/
   ```

2. **Edit ContentView.swift:**
   - Remove lines 630-634 (Check for Updates button)

3. **Edit AboutView.swift:**
   - Remove lines 89-92 (Check for Updates button)

4. **Remove Sparkle from Project:**
   - Open Xcode → Target → Remove Sparkle framework
   - Or edit `project.yml` and run `xcodegen generate`

---

## 🌐 Phase 3: App Store Connect (45 min)

Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)

### 1. Create App Record

1. My Apps → **+** → New App
2. Platform: macOS
3. Name: `NanoJet` (or your preferred name)
4. Bundle ID: `com.ahmedsam.idmmac`
5. SKU: `IDMMAC001`

### 2. Fill Information

**App Information:**
- **Category:** Utilities
- **Privacy Policy:** `https://ahmedsam.com/idmmac/privacy.html`
  - Upload `PRIVACY_POLICY_WEB.html` to your website
- **Description:**
  ```
  Fast, reliable download manager with multi-connection downloads, 
  pause/resume, and Chrome extension integration.
  ```

**Pricing:**
- Free (or set price)

### 3. Prepare Screenshots

Take 3-5 screenshots (1280x800 minimum):
1. Main window with active download
2. Multiple downloads in queue
3. Settings or features view

---

## 📦 Phase 4: Build & Submit (1-2 hours)

### 1. Configure Xcode Signing

1. Open `NanoJet.xcodeproj`
2. Target → Signing & Capabilities
3. **Uncheck** "Automatically manage signing"
4. Team: Select your team (YOUR_TEAM_ID)
5. **Debug:** Mac Developer
6. **Release:** 3rd Party Mac Developer Application
7. **Provisioning Profile:** NanoJet App Store Profile

### 2. Update Version

```bash
# Edit project.yml or in Xcode:
# MARKETING_VERSION: 1.0.0
# CURRENT_PROJECT_VERSION: 1
```

### 3. Build Archive

In Xcode:
1. Select **Any Mac** as destination
2. **Product** → **Clean Build Folder** (⌥⇧⌘K)
3. **Product** → **Archive**
4. Wait for completion (5-10 minutes)

### 4. Validate

1. **Window** → **Organizer** → **Archives**
2. Select your archive
3. Click **Validate App**
4. Choose: App Store Connect
5. Wait for validation ✅

### 5. Upload

1. Click **Distribute App**
2. Choose: **App Store Connect** → **Upload**
3. Include symbols: Yes
4. Click **Upload**
5. Wait for upload (10-30 minutes)

### 6. Submit for Review

1. Go back to App Store Connect
2. Wait for build processing (30-60 minutes)
3. Version 1.0.0 → Select your build
4. Upload screenshots
5. Fill "What's New"
6. Click **Add for Review**
7. **Submit for Review** ✅

---

## ⏱️ Timeline

| Step | Time |
|------|------|
| Developer Portal Setup | 30 min |
| Project Configuration | 30 min |
| App Store Connect Setup | 45 min |
| Build & Upload | 1-2 hours |
| **Total** | **3-4 hours** |
| Processing | 30-60 min |
| Review | 1-3 days |
| **Ready to Release** | **1-4 days** |

---

## ✅ Quick Checklist

Before submitting:

- [ ] Apple Developer account active
- [ ] Certificates installed (check Keychain)
- [ ] Provisioning profile installed
- [ ] Sparkle removed from code
- [ ] Project uses manual signing
- [ ] Version set to 1.0.0
- [ ] Archive validates without errors
- [ ] Privacy policy hosted online
- [ ] Screenshots prepared (3 minimum)
- [ ] App Store Connect metadata complete

---

## 🎯 Quick Commands

```bash
# Check certificates
security find-identity -v -p codesigning

# Check for Sparkle references
grep -r "import Sparkle" NanoJetApp/
grep -r "UpdaterManager" NanoJetApp/

# Clean build
rm -rf build/ ~/Library/Developer/Xcode/DerivedData/NanoJet-*

# Archive from terminal
xcodebuild archive \
  -project NanoJet.xcodeproj \
  -scheme NanoJetApp \
  -configuration Release \
  -archivePath ~/Desktop/NanoJetApp.xcarchive
```

---

## 🐛 Common Issues

**"No provisioning profiles found"**
→ Download from developer portal and double-click to install

**"Code signing failed"**
→ Set CODE_SIGN_STYLE to Manual in Build Settings

**"Sparkle not found" error**
→ Remove all `import Sparkle` lines and UpdaterManager references

**Validation fails**
→ Check entitlements are App Store compliant
→ Ensure ENABLE_APP_SANDBOX = YES

---

## 📞 Need Help?

**Detailed Guides:**
- [APP_STORE_SETUP_GUIDE.md](APP_STORE_SETUP_GUIDE.md) - Complete step-by-step
- [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md) - Track your progress
- [CODE_CHANGES_FOR_APPSTORE.md](CODE_CHANGES_FOR_APPSTORE.md) - Code modifications
- [REMOVE_SPARKLE_GUIDE.md](REMOVE_SPARKLE_GUIDE.md) - Remove update framework

**Apple Resources:**
- [Developer Portal](https://developer.apple.com/account)
- [App Store Connect](https://appstoreconnect.apple.com)
- [Support](https://developer.apple.com/contact/)

---

## 🎉 After Approval

1. **App goes live** automatically (or when you release it)
2. **Share the link:** `https://apps.apple.com/app/idmmac/YOURAPPID`
3. **Monitor reviews** and respond to users
4. **Plan updates** - just increment version and re-submit

**Congrats on your App Store launch! 🚀**

---

**Created:** October 23, 2025  
**Estimated Time:** 3-4 hours setup + 1-3 days review

