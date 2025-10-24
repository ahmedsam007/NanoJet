# 🍎 NanoJet - Mac App Store Distribution

**Everything you need to publish NanoJet on the Mac App Store!**

---

## 📚 Documentation Overview

I've prepared complete guides to help you through every step:

### 🚀 Start Here

**1. [APP_STORE_QUICKSTART.md](APP_STORE_QUICKSTART.md)** ⚡  
Quick 3-4 hour guide to get your app submitted. Perfect if you're familiar with the process.

**2. [APP_STORE_SETUP_GUIDE.md](APP_STORE_SETUP_GUIDE.md)** 📖  
Complete detailed guide covering every step from certificates to submission. Read this if it's your first time.

**3. [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md)** ✅  
Track your progress with checkboxes. Never miss a step!

### 🔧 Technical Guides

**4. [CODE_CHANGES_FOR_APPSTORE.md](CODE_CHANGES_FOR_APPSTORE.md)** 💻  
Exact code changes needed to remove Sparkle and prepare for App Store.

**5. [REMOVE_SPARKLE_GUIDE.md](REMOVE_SPARKLE_GUIDE.md)** 🔄  
Detailed guide for removing Sparkle framework (required for App Store).

### 📄 Configuration Files

**6. [configure-appstore.sh](configure-appstore.sh)** 🛠️  
Automated script to configure your project. Run this first!

**7. [project-appstore.yml](project-appstore.yml)** ⚙️  
App Store-ready project configuration (removes Sparkle, sets up signing).

**8. [Tools/ExportOptionsAppStore.plist](Tools/ExportOptionsAppStore.plist)** 📦  
Export configuration for App Store archives.

### 🔐 App Store Ready Files

**9. [NanoJetApp/App/NanoJetApp-AppStore.swift](NanoJetApp/App/NanoJetApp-AppStore.swift)**  
Main app file with Sparkle removed.

**10. [NanoJetApp/App/NanoJetApp-AppStore.entitlements](NanoJetApp/App/NanoJetApp-AppStore.entitlements)**  
App Store compliant entitlements with sandbox enabled.

**11. [NanoJetApp/Resources/Info-AppStore.plist](NanoJetApp/Resources/Info-AppStore.plist)**  
Info.plist without Sparkle keys.

**12. [PRIVACY_POLICY_WEB.html](PRIVACY_POLICY_WEB.html)**  
Ready-to-upload privacy policy (required for App Store).

---

## 🎯 Quick Start (TL;DR)

```bash
cd /Users/ahmed/Documents/NanoJet

# 1. Run configuration script
./configure-appstore.sh
# (Enter your Apple Developer Team ID when prompted)

# 2. Apply code changes
cp NanoJetApp/App/NanoJetApp-AppStore.swift NanoJetApp/App/NanoJetApp.swift
mv NanoJetApp/Utilities/UpdaterManager.swift backups/

# 3. Manually edit these 2 files:
# - NanoJetApp/UI/ContentView.swift (remove lines 630-634)
# - NanoJetApp/UI/AboutView.swift (remove lines 89-92)

# 4. Remove Sparkle from Xcode project
# Open Xcode → Target → Remove Sparkle framework

# 5. Build archive
# Xcode → Product → Archive

# 6. Submit
# Organizer → Validate → Upload to App Store
```

Then go to [App Store Connect](https://appstoreconnect.apple.com) and complete the submission.

---

## 📋 Prerequisites

Before you start, make sure you have:

- ✅ **Apple Developer Account** - Active and paid ($99/year)
- ✅ **Developer Agreement** - Accepted in Apple Developer portal
- ✅ **Xcode** - Latest version installed
- ✅ **macOS** - Running Ventura 13.0 or later
- ✅ **Team ID** - From [developer.apple.com/account](https://developer.apple.com/account)

---

## 🛠️ What's Different for App Store?

| Aspect | Direct Distribution (Current) | Mac App Store |
|--------|------------------------------|---------------|
| **Updates** | Sparkle framework | Apple automatic |
| **Certificates** | Developer ID | Mac App Distribution |
| **Sandbox** | Optional | **Required** |
| **Code Signing** | Automatic | Manual |
| **Distribution** | Your website | Mac App Store only |
| **Notarization** | Required | Not needed |

---

## 📦 Files You'll Modify

### Config Files (Already Prepared)
- ✅ `project.yml` → Use `project-appstore.yml`
- ✅ `Info.plist` → Use `Info-AppStore.plist`
- ✅ `Entitlements` → Use `NanoJetApp-AppStore.entitlements`

### Code Files (Need Manual Edits)
- 🔧 `NanoJetApp/App/NanoJetApp.swift` - Remove Sparkle import & menu
- 🔧 `NanoJetApp/UI/ContentView.swift` - Remove "Check for Updates" button
- 🔧 `NanoJetApp/UI/AboutView.swift` - Remove "Check for Updates" button
- 🗑️ `NanoJetApp/Utilities/UpdaterManager.swift` - Delete or stub

---

## ⏱️ Time Estimates

| Phase | Task | Time |
|-------|------|------|
| **1** | Apple Developer Setup (certificates, profiles) | 30-60 min |
| **2** | Project Configuration (run scripts, code changes) | 30-45 min |
| **3** | App Store Connect (create app, metadata) | 45-60 min |
| **4** | Build & Submit (archive, validate, upload) | 1-2 hours |
| **Total** | **Your Time** | **3-4 hours** |
| | Apple Processing | 30-60 min |
| | Apple Review | 1-3 days |
| **Total** | **To Live** | **1-4 days** |

---

## 🎓 Recommended Path

### For First-Time Publishers:

1. Read [APP_STORE_SETUP_GUIDE.md](APP_STORE_SETUP_GUIDE.md) completely
2. Follow [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md) step by step
3. Use [CODE_CHANGES_FOR_APPSTORE.md](CODE_CHANGES_FOR_APPSTORE.md) for code modifications

### For Experienced Developers:

1. Skim [APP_STORE_QUICKSTART.md](APP_STORE_QUICKSTART.md)
2. Run `./configure-appstore.sh`
3. Make code changes from [CODE_CHANGES_FOR_APPSTORE.md](CODE_CHANGES_FOR_APPSTORE.md)
4. Build and submit

---

## 🔍 Verification Steps

Before submitting, verify:

```bash
# 1. No Sparkle references
grep -r "import Sparkle" NanoJetApp/
# Should return: nothing

# 2. No UpdaterManager calls
grep -r "UpdaterManager.shared" NanoJetApp/
# Should return: nothing

# 3. Certificates installed
security find-identity -v -p codesigning
# Should show: "3rd Party Mac Developer Application"

# 4. App builds
xcodebuild build -project NanoJet.xcodeproj -scheme NanoJetApp -configuration Release
# Should succeed

# 5. Archive validates
# Xcode → Organizer → Validate
# Should pass all checks
```

---

## 📱 Post-Submission

### While in Review:
- Check App Store Connect daily for status updates
- Respond promptly to any questions from Apple
- Have your demo credentials ready (if needed)

### After Approval:
1. **App goes live** (automatic or manual release)
2. **Get your App Store link:**
   ```
   https://apps.apple.com/app/idmmac/YOURAPPID
   ```
3. **Update your website** to link to Mac App Store
4. **Announce on social media** 📢
5. **Monitor reviews** and respond to feedback

### For Updates:
1. Increment version number
2. Update "What's New" text
3. Archive and submit new build
4. Apple reviews update (usually faster, 1-2 days)

---

## 🚨 Important Notes

### ⚠️ Must Do:
- **Remove ALL Sparkle code** - App Store will reject if present
- **Enable App Sandbox** - Required for Mac App Store
- **Manual code signing** - Automatic won't work for App Store
- **Host Privacy Policy** - Must be accessible before submission

### ❌ Don't Do:
- **Don't skip validation** - Always validate before uploading
- **Don't rush** - Take time to test thoroughly
- **Don't forget screenshots** - Minimum 3 required
- **Don't use wildcard bundle ID** - Must be explicit

---

## 🐛 Troubleshooting

### Common Issues:

**"No provisioning profile found"**
```bash
# Solution: Download and install profile
# Go to developer.apple.com → Profiles → Download
# Double-click the .provisionprofile file
```

**"Code signing failed"**
```bash
# Solution: Set manual signing in Xcode
# Target → Signing & Capabilities
# Uncheck "Automatically manage signing"
# Select your team and profile
```

**"Entitlements not compatible"**
```bash
# Solution: Use the App Store entitlements
cp NanoJetApp/App/NanoJetApp-AppStore.entitlements NanoJetApp/App/NanoJetApp.entitlements
```

**Build errors mentioning Sparkle**
```bash
# Solution: Remove all Sparkle imports
grep -r "import Sparkle" NanoJetApp/
# Remove each occurrence
```

---

## 📞 Getting Help

### Documentation:
- All guides are in this directory
- Start with [APP_STORE_QUICKSTART.md](APP_STORE_QUICKSTART.md)

### Apple Resources:
- [Developer Portal](https://developer.apple.com/account)
- [App Store Connect](https://appstoreconnect.apple.com)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple Developer Support](https://developer.apple.com/contact/)

### Community:
- [Apple Developer Forums](https://developer.apple.com/forums/)
- Stack Overflow: `[macos] [app-store]` tags

---

## ✅ Success Criteria

Your app is ready to submit when:

- ✅ Archive validates without errors in Xcode
- ✅ No Sparkle references in code
- ✅ App sandbox enabled
- ✅ Manual signing configured correctly
- ✅ Privacy policy hosted and accessible
- ✅ Screenshots prepared (minimum 3)
- ✅ App Store Connect metadata complete
- ✅ App runs correctly with sandbox enabled

---

## 🎯 What's Next?

After your app is approved and live:

### Week 1:
- Monitor for crash reports in App Store Connect
- Respond to user reviews
- Fix any critical bugs quickly

### Month 1:
- Gather user feedback
- Plan next version features
- Consider adding localizations

### Ongoing:
- Regular updates (every 2-3 months)
- Respond to reviews within 1-2 days
- Monitor Mac App Store placement
- Consider paid upgrade or in-app purchases

---

## 📊 App Store Optimization (ASO)

To maximize downloads:

**Good App Name:**
- "NanoJet - Download Manager"
- "NanoJet: Fast Downloads"

**Keywords:** (100 chars max)
```
download,manager,downloader,fast,speed,resume,pause,youtube,video,file,transfer
```

**Screenshots:** Show:
1. Active download with speed/progress
2. Multiple simultaneous downloads
3. Unique features (YouTube, scheduler, etc.)

**Description:** Highlight:
- Main benefit first (faster downloads)
- Key features (bullets)
- Use case (who needs it)
- Chrome extension mention

---

## 🎉 Congratulations!

You now have everything needed to:
- ✅ Configure your project for App Store
- ✅ Remove Sparkle and prepare code
- ✅ Create certificates and profiles
- ✅ Build and submit your app
- ✅ Handle the review process

**Time to get started! Good luck with your submission! 🚀**

---

## 📝 Changelog

**October 23, 2025:**
- Created complete App Store documentation
- Prepared configuration scripts and files
- Ready for submission

---

**Questions?** Read the guides above, they cover everything! 📚

**Ready?** Start with [APP_STORE_QUICKSTART.md](APP_STORE_QUICKSTART.md) ⚡

---

*Made with ❤️ for macOS developers*

