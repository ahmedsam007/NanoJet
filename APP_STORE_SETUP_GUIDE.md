# 🍎 Mac App Store Distribution Setup Guide

## 📋 Overview

This guide will help you prepare **NanoJet** for distribution through the Mac App Store. This requires different certificates, provisioning profiles, and code signing than direct distribution.

---

## 🎯 Key Differences: App Store vs Direct Distribution

| Aspect | Direct Distribution (Current) | Mac App Store |
|--------|------------------------------|---------------|
| **Certificates** | Developer ID Application | Mac App Distribution |
| **Provisioning** | None required | App Store provisioning profile required |
| **Updates** | Sparkle framework | Apple handles automatically |
| **Sandbox** | Optional | **Required** |
| **Code Signing** | Developer ID | Mac App Distribution |
| **Notarization** | Required | Not required (Apple reviews) |
| **Distribution** | Your website | Mac App Store only |

---

## 🚀 Step-by-Step Setup Process

### Phase 1: Apple Developer Account Setup

#### 1.1 Verify Your Account
1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Sign in with your Apple ID
3. Verify your account status is **Active**
4. Confirm you have access to **Certificates, Identifiers & Profiles**

#### 1.2 Create App Identifier
1. Go to **Certificates, Identifiers & Profiles**
2. Click **Identifiers** → **+** button
3. Select **App IDs** → **Continue**
4. Configure:
   - **Description**: `NanoJet`
   - **Bundle ID**: `com.ahmedsam.idmmac` (explicit, not wildcard)
   - **Capabilities**: Enable these:
     - ✅ **App Sandbox** (required for Mac App Store)
     - ✅ **Network: Outgoing Connections (Client)**
     - ✅ **File Access: User Selected Files (Read/Write)**
     - ✅ **File Access: Downloads Folder (Read/Write)**
5. Click **Continue** → **Register**

#### 1.3 Create Mac App Distribution Certificate

**On Your Mac:**

1. Open **Keychain Access** (Applications → Utilities)
2. From menu: **Keychain Access** → **Certificate Assistant** → **Request a Certificate from a Certificate Authority**
3. Fill in:
   - **User Email**: Your Apple ID email
   - **Common Name**: `Mac App Distribution Certificate`
   - **CA Email**: Leave blank
   - Select: **Saved to disk**
   - Select: **Let me specify key pair information**
4. Click **Continue**
5. Save as `CertificateSigningRequest.certSigningRequest`
6. Key Size: **2048 bits**, Algorithm: **RSA**

**In Apple Developer Portal:**

1. Go to **Certificates, Identifiers & Profiles** → **Certificates**
2. Click **+** button
3. Select **Mac App Distribution** → **Continue**
4. Upload your `.certSigningRequest` file
5. Click **Continue** → **Download**
6. Double-click the downloaded certificate to install in Keychain

**Verify Installation:**
```bash
# List your certificates
security find-identity -v -p codesigning

# You should see something like:
# 1) ABC123... "3rd Party Mac Developer Application: Your Name (TEAM_ID)"
```

#### 1.4 Create Mac Installer Distribution Certificate

**Same process as 1.3, but:**
- Select **Mac Installer Distribution** instead
- You'll need this to create a `.pkg` for App Store submission

#### 1.5 Create Provisioning Profile

1. Go to **Certificates, Identifiers & Profiles** → **Profiles**
2. Click **+** button
3. Select **Mac App Store** → **Continue**
4. Select your App ID: `com.ahmedsam.idmmac` → **Continue**
5. Select your **Mac App Distribution** certificate → **Continue**
6. Profile Name: `NanoJet App Store Profile`
7. Click **Generate** → **Download**
8. Double-click the `.provisionprofile` file to install

**Verify Installation:**
```bash
# List provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/
```

---

### Phase 2: Xcode Project Configuration

#### 2.1 Update Signing & Capabilities

**In Xcode:**
1. Open `NanoJet.xcodeproj`
2. Select the project in navigator
3. Select **NanoJetApp** target
4. Go to **Signing & Capabilities** tab

**Configure Signing:**
- **Automatically manage signing**: ❌ **OFF** (uncheck)
- **Team**: Select your Apple Developer team
- **Signing Certificate (Debug)**: `Mac Developer` or `Development`
- **Signing Certificate (Release)**: `3rd Party Mac Developer Application`
- **Provisioning Profile (Release)**: Select `NanoJet App Store Profile`

#### 2.2 Update Build Settings

In Xcode, select **NanoJetApp** target → **Build Settings** tab:

**Code Signing Settings:**
```
CODE_SIGN_IDENTITY[sdk=macosx*]
  - Debug: Mac Developer
  - Release: 3rd Party Mac Developer Application

CODE_SIGN_STYLE = Manual

DEVELOPMENT_TEAM = YOUR_TEAM_ID (e.g., ABC123XYZ)

PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]
  - Release: NanoJet App Store Profile
```

**Important Build Settings:**
```
ENABLE_HARDENED_RUNTIME = YES
ENABLE_APP_SANDBOX = YES (for Release)
```

#### 2.3 Update Entitlements for App Store

Your current entitlements are good, but verify they're App Store compliant:

**NanoJetApp/App/NanoJetApp.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Store Required -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- Your App Needs -->
    <key>com.apple.security.network.client</key>
    <true/>
    
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    
    <!-- Remove this for App Store: -->
    <!-- <key>com.apple.application-identifier</key> -->
    <!-- <string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string> -->
</dict>
</plist>
```

**Note:** The `com.apple.application-identifier` is automatically added by Xcode/provisioning profile.

#### 2.4 Remove Sparkle Framework

**⚠️ CRITICAL:** Mac App Store apps **CANNOT** use third-party update mechanisms.

1. **Remove Sparkle dependency:**
   - Edit `project.yml` (remove Sparkle package)
   - Or in Xcode: Target → Frameworks → Remove Sparkle

2. **Remove Sparkle from Info.plist:**
   - Remove `SUFeedURL`
   - Remove `SUPublicEDKey`
   - Remove `SUEnableAutomaticChecks`
   - Remove `SUScheduledCheckInterval`
   - Remove `SUAllowsAutomaticUpdates`

3. **Remove Sparkle code:**
   - Remove `UpdaterManager.swift` or disable Sparkle checks
   - Remove menu items related to "Check for Updates"

4. **Update UI:**
   - Remove gear icon → "Check for Updates" menu item
   - Apple will handle updates automatically

---

### Phase 3: App Store Connect Setup

#### 3.1 Create App Record

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** button → **New App**
3. Fill in:
   - **Platforms**: macOS
   - **Name**: `NanoJet` (or your preferred name)
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: Select `com.ahmedsam.idmmac`
   - **SKU**: `IDMMAC001` (unique identifier for your records)
   - **User Access**: Full Access

#### 3.2 App Information

**Category:**
- Primary: Utilities or Productivity
- Secondary: (optional)

**Privacy Policy URL:**
- You have `PRIVACY_POLICY.md` - convert to web page and host it
- Example: `https://ahmedsam.com/idmmac/privacy`

**App Description:**
```
NanoJet is a fast, lightweight download manager for macOS with segmented downloading and intelligent resume capabilities.

Features:
• Multi-connection downloads for maximum speed
• Pause and resume at any time
• Automatic reconnection on network interruption  
• Real-time speed monitoring and ETA
• SHA-256 verification for completed files
• Beautiful, native macOS interface
• Chrome extension for seamless download handoff

Perfect for downloading large files quickly and reliably.
```

**Keywords:**
```
download manager, downloader, download, fast download, resume download, multi-connection
```

#### 3.3 Pricing and Availability

- **Price**: Free (or set a price)
- **Availability**: All territories (or select specific countries)

#### 3.4 Prepare Screenshots

**Required Sizes:**
- 1280 x 800 pixels (or higher resolution at 16:10 aspect ratio)
- At least **3 screenshots** required

**Recommended Content:**
1. Main window with active download
2. Download list with multiple items
3. Settings/preferences window
4. YouTube setup or Chrome extension (if applicable)

**Create Screenshots:**
```bash
# Launch your app
# Use macOS Screenshot tool (Cmd+Shift+4)
# Capture at least 3 different views
```

#### 3.5 App Review Information

**Contact Information:**
- First Name, Last Name
- Phone Number
- Email Address

**Demo Account** (if needed):
- For features requiring login/account
- Your app likely doesn't need this

**Notes for Reviewer:**
```
NanoJet is a download manager that helps users download files faster using multi-connection downloading.

To test:
1. Launch the app
2. Copy a download URL (e.g., https://example.com/largefile.zip)
3. The app will detect the copied URL and offer to download it
4. OR use the Chrome extension in Tools/ChromeExtension folder to send downloads to the app

The app requests network access to download files and file access permissions for the Downloads folder.

Thank you for reviewing!
```

---

### Phase 4: Build and Submit

#### 4.1 Prepare for Archive

**Update Version:**
```yaml
# project.yml
MARKETING_VERSION: 1.0.0  # First App Store release
CURRENT_PROJECT_VERSION: 1
```

**Clean Build:**
```bash
cd /Users/ahmed/Documents/NanoJet

# Clean
rm -rf build/
rm -rf ~/Library/Developer/Xcode/DerivedData/NanoJet-*

# Regenerate project if using XcodeGen
xcodegen generate
```

#### 4.2 Create Archive

**In Xcode:**
1. Select **Any Mac** (or **My Mac**) as destination
2. **Product** → **Clean Build Folder** (Option+Shift+Cmd+K)
3. **Product** → **Archive**
4. Wait for archive to complete

**Or Command Line:**
```bash
xcodebuild archive \
  -project NanoJet.xcodeproj \
  -scheme NanoJetApp \
  -configuration Release \
  -archivePath ~/Desktop/NanoJetApp.xcarchive
```

#### 4.3 Validate Archive

**In Xcode Organizer:**
1. Select your archive
2. Click **Validate App**
3. Choose:
   - **App Store Connect** distribution
   - Your team
   - Your signing certificate
4. Click **Validate**

**Fix any issues before proceeding.**

#### 4.4 Upload to App Store Connect

**In Xcode Organizer:**
1. Select your archive
2. Click **Distribute App**
3. Choose **App Store Connect**
4. Select:
   - **Upload**
   - Your team  
   - Include symbols (recommended)
5. Review and click **Upload**

**Or use command line:**
```bash
# Export for App Store
xcodebuild -exportArchive \
  -archivePath ~/Desktop/NanoJetApp.xcarchive \
  -exportPath ~/Desktop/NanoJetApp-AppStore \
  -exportOptionsPlist Tools/ExportOptionsAppStore.plist

# Upload using Transporter app or:
xcrun altool --upload-app \
  --type macos \
  --file ~/Desktop/NanoJetApp-AppStore/NanoJetApp.pkg \
  --username YOUR_APPLE_ID \
  --password @keychain:AC_PASSWORD
```

#### 4.5 Submit for Review

1. Go to **App Store Connect** → **My Apps** → **NanoJet**
2. Create a new version: **1.0.0**
3. Upload screenshots
4. Fill in "What's New in This Version"
5. Choose **Manual Release** or **Automatic** release after approval
6. Click **Add for Review**
7. Submit for review

**Processing Time:**
- Processing: 30 minutes - 2 hours
- Review: 1-3 days typically

---

## 📝 ExportOptions.plist for App Store

Create this file: `/Users/ahmed/Documents/NanoJet/Tools/ExportOptionsAppStore.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>manual</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.ahmedsam.idmmac</key>
        <string>NanoJet App Store Profile</string>
    </dict>
</dict>
</plist>
```

---

## ✅ Pre-Submission Checklist

Before submitting to App Store, verify:

- [ ] Developer account is active and paid
- [ ] App ID registered with correct bundle identifier
- [ ] Mac App Distribution certificate installed
- [ ] Mac Installer Distribution certificate installed  
- [ ] Provisioning profile downloaded and installed
- [ ] Xcode project uses App Store signing
- [ ] Sparkle framework removed
- [ ] Update-related UI removed
- [ ] Entitlements are App Store compliant
- [ ] App sandbox is enabled
- [ ] Version number updated (1.0.0)
- [ ] Privacy policy hosted on web
- [ ] App Store Connect record created
- [ ] Screenshots prepared (at least 3)
- [ ] App description written
- [ ] Archive validates without errors
- [ ] Archive uploaded to App Store Connect
- [ ] All metadata filled in App Store Connect

---

## 🎯 Common Issues and Solutions

### Issue: "No Provisioning Profiles Found"
**Solution:** 
- Download profile from developer portal
- Double-click to install
- Restart Xcode

### Issue: "Code signing failed"
**Solution:**
- Verify certificate is installed in Keychain
- Check `DEVELOPMENT_TEAM` matches your team ID
- Ensure profile matches bundle ID exactly

### Issue: "Entitlements not compatible with App Store"
**Solution:**
- Remove any entitlements not approved for App Store
- Remove `com.apple.security.get-task-allow`
- Ensure sandbox is enabled

### Issue: "Binary was uploaded with incorrect metadata"
**Solution:**
- Re-create archive with correct settings
- Validate before uploading
- Check Info.plist has all required keys

---

## 📱 Post-Approval

### After Approval:

1. **Celebrate!** 🎉
2. **Monitor Reviews** - Respond to user feedback
3. **Plan Updates** - Create roadmap for future releases
4. **Remove Direct Distribution**:
   - Update website to point to Mac App Store
   - Keep GitHub for open source/collaboration

### Future Updates:

When releasing updates:
1. Increment version number
2. Update "What's New"  
3. Archive → Validate → Upload
4. Submit new version for review

---

## 🔗 Helpful Resources

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#mac)
- [Mac App Store Submission Guide](https://developer.apple.com/macos/submit/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Code Signing Guide](https://developer.apple.com/support/code-signing/)
- [App Sandbox Guide](https://developer.apple.com/documentation/security/app_sandbox)

---

## 📞 Support

If you encounter issues:
1. Check Apple Developer Forums
2. Review App Store Connect logs
3. Contact Apple Developer Support (available with paid account)

---

**Created**: October 23, 2025  
**For**: NanoJet v1.0.0 Mac App Store Release

