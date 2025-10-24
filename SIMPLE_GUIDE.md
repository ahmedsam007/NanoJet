# 🎯 SUPER SIMPLE App Store Guide (Non-Technical)

**Don't worry! I'll guide you through every single click.**

---

## ⏱️ Time Needed: About 4 hours

**What you need:**
- Your Mac
- Your Apple ID (the one with the developer account)
- 3-4 hours of your time
- Internet connection

---

# 🚀 STEP-BY-STEP PROCESS

## Part 1: Run Automation Script (5 minutes)

I'll do most of the work automatically!

**Open Terminal** (Applications → Utilities → Terminal) and copy-paste these commands:

```bash
cd /Users/ahmed/Documents/NanoJet
chmod +x automate-appstore-setup.sh
./automate-appstore-setup.sh
```

✅ The script will automatically:
- Update all your code files
- Remove Sparkle (old update system)
- Configure your project settings
- Prepare everything for App Store

**Just press Enter when it asks!**

---

## Part 2: Apple Developer Portal (30 minutes)

**⚠️ YOU MUST DO THIS - Requires your Apple ID login**

### 2.1 Open Your Web Browser

Go to: **https://developer.apple.com/account**

**Login with your Apple ID** (the one with developer account)

---

### 2.2 Create Certificates (10 minutes)

**Click:** Certificates, Identifiers & Profiles (on left side)

#### Step A: Request Certificate from Your Mac

1. **Open:** Applications → Utilities → **Keychain Access**
2. **Click:** Menu → Keychain Access → Certificate Assistant → **Request a Certificate from a Certificate Authority**
3. **Fill in:**
   - Your Email: `your-email@example.com`
   - Common Name: `Mac App Certificate`
   - CA Email: Leave blank
   - Request is: **Select "Saved to disk"**
4. **Click:** Continue
5. **Save as:** `CertificateRequest.certSigningRequest` on Desktop
6. **Click:** Done

#### Step B: Create Mac App Distribution Certificate

1. **Go back to browser** (developer.apple.com)
2. **Click:** Certificates (left sidebar)
3. **Click:** The **+** (plus) button
4. **Select:** Mac App Distribution
5. **Click:** Continue
6. **Click:** Choose File → Select `CertificateRequest.certSigningRequest` from Desktop
7. **Click:** Continue
8. **Click:** Download
9. **Double-click** the downloaded file to install it
10. **Done!** ✅

#### Step C: Create Mac Installer Distribution Certificate

**Repeat Step B, but:**
- Select "Mac Installer Distribution" instead
- Everything else is the same

**You should now have 2 certificates!** ✅

---

### 2.3 Create App ID (5 minutes)

1. **Click:** Identifiers (left sidebar)
2. **Click:** The **+** (plus) button
3. **Select:** App IDs
4. **Click:** Continue
5. **Fill in:**
   - Description: `NanoJet`
   - Bundle ID: **Select "Explicit"**
   - Bundle ID text field: `com.ahmedsam.idmmac`
6. **Scroll down** to Capabilities
7. **Check these boxes:**
   - ✅ App Sandbox
   - ✅ Network Extensions → Outgoing Connections (Client)
   - ✅ File Access
8. **Click:** Continue
9. **Click:** Register
10. **Done!** ✅

---

### 2.4 Create Provisioning Profile (5 minutes)

1. **Click:** Profiles (left sidebar)
2. **Click:** The **+** (plus) button
3. **Select:** Mac App Store (under Distribution)
4. **Click:** Continue
5. **Select:** `com.ahmedsam.idmmac` (the App ID you just created)
6. **Click:** Continue
7. **Select:** Your Mac App Distribution certificate (check the box)
8. **Click:** Continue
9. **Profile Name:** `NanoJet App Store Profile`
10. **Click:** Generate
11. **Click:** Download
12. **Double-click** the downloaded `.provisionprofile` file to install
13. **Done!** ✅

**✅ Part 2 Complete! You now have all certificates and profiles!**

---

## Part 3: Xcode Configuration (15 minutes)

### 3.1 Open Your Project

1. **Open Xcode** (if not already open)
2. **Open:** `/Users/ahmed/Documents/NanoJet/NanoJet.xcodeproj`

### 3.2 Remove Sparkle Framework

1. **Click:** Project name "NanoJet" in left sidebar (blue icon)
2. **Click:** Target "NanoJetApp" (under TARGETS)
3. **Click:** Tab "Frameworks, Libraries, and Embedded Content"
4. **Find:** Sparkle.framework in the list
5. **Click:** The **-** (minus) button to remove it
6. **Confirm** if asked

### 3.3 Configure Signing

1. Still in NanoJetApp target
2. **Click:** Tab "Signing & Capabilities"
3. **Uncheck:** ❌ "Automatically manage signing"
4. **Team:** Select your team (should show your name and `4H548RMBS5`)
5. **Debug section:**
   - Signing Certificate: Select "Mac Developer"
   - Provisioning Profile: Automatic (or select any Development profile)
6. **Release section:**
   - Signing Certificate: Select "3rd Party Mac Developer Application"
   - Provisioning Profile: Select "NanoJet App Store Profile"

If you see any errors, that's OK! We'll fix them when building.

**Done!** ✅

---

## Part 4: Clean and Build (10 minutes)

### 4.1 Clean Everything

**In Xcode:**
1. **Menu:** Product → Clean Build Folder
2. **Or press:** Option + Shift + Command + K
3. **Wait** for it to finish (5 seconds)

### 4.2 Build the App

1. **Top of Xcode:** Select "Any Mac" as the destination (next to NanoJetApp)
2. **Menu:** Product → Build
3. **Or press:** Command + B
4. **Wait** for build to complete (2-5 minutes)

**If you see errors:**
- Don't panic!
- **Copy the error message**
- **Run:** `./fix-build-errors.sh` (I'll create this script)

**If build succeeds:** ✅ Great! Continue!

---

## Part 5: Create Archive (15 minutes)

### 5.1 Archive Your App

**In Xcode:**
1. **Make sure:** "Any Mac" is selected at the top
2. **Menu:** Product → Archive
3. **Wait** (this takes 5-10 minutes, be patient!)
4. When done, the **Organizer** window will open automatically

### 5.2 Validate the Archive

**In Organizer window:**
1. **Select** your archive (should be at the top)
2. **Click:** "Validate App" button (blue button on right)
3. **Select:** App Store Connect
4. **Click:** Next
5. **Automatically manage signing:** Leave checked
6. **Click:** Next
7. **Wait** for validation (2-5 minutes)

**If validation succeeds:** ✅ Perfect!

**If validation fails:**
- Read the error message
- Common fixes in the guides
- Or contact me with the error

---

## Part 6: App Store Connect (30 minutes)

**⚠️ YOU MUST DO THIS - Requires your Apple ID**

### 6.1 Open App Store Connect

Go to: **https://appstoreconnect.apple.com**

**Login** with your Apple ID

### 6.2 Create Your App

1. **Click:** "My Apps"
2. **Click:** The **+** button (top left)
3. **Click:** "New App"
4. **Fill in:**
   - Platform: Check ✅ **macOS**
   - Name: `NanoJet` (or whatever you want to call it)
   - Primary Language: English (U.S.)
   - Bundle ID: Select `com.ahmedsam.idmmac`
   - SKU: `IDMMAC001` (just a unique code for your records)
   - User Access: Full Access
5. **Click:** Create

### 6.3 Upload Privacy Policy

**First, upload the privacy policy to your website:**

I created `PRIVACY_POLICY_WEB.html` for you.

1. Upload it to your website at: `https://ahmedsam.com/idmmac/privacy.html`
2. Or use GitHub Pages, or any web hosting

**Then in App Store Connect:**

1. **Click:** App Information (left sidebar)
2. **Find:** Privacy Policy URL
3. **Enter:** `https://ahmedsam.com/idmmac/privacy.html` (or wherever you uploaded it)
4. **Click:** Save

### 6.4 Fill App Information

**In App Store Connect:**

1. **Category:** Primary: Utilities
2. **Subcategory:** (optional)

### 6.5 Pricing and Availability

1. **Click:** Pricing and Availability (left sidebar)
2. **Price:** Select "Free" (or set a price if you want)
3. **Availability:** All countries (or select specific ones)
4. **Click:** Save

### 6.6 Prepare for Submission

1. **Click:** Version 1.0.0 (or "Prepare for Submission")
2. **Fill in:**

**Screenshots (Required - minimum 3):**

You need to take screenshots of your app!

1. **Open your app** (build and run it)
2. **Press:** Command + Shift + 4 (screenshot tool)
3. **Drag** to capture these views:
   - Main window with a download in progress
   - Download list with multiple items
   - Settings or another feature

Upload at least 3 screenshots.

**App Description:**
```
NanoJet is a powerful download manager for macOS that accelerates your downloads with multi-connection technology.

Features:
• Faster downloads with segmented downloading
• Pause and resume anytime
• Automatic reconnection on network interruption
• Real-time speed monitoring and progress tracking
• SHA-256 file verification for security
• Beautiful, native macOS interface
• Chrome extension for seamless integration

Perfect for downloading large files quickly and reliably!
```

**Keywords:** (max 100 characters)
```
download,manager,fast,speed,downloader,youtube,video,file,resume,pause
```

**Support URL:** `https://ahmedsam.com`

**What's New in This Version:**
```
First release of NanoJet for Mac App Store!

Enjoy fast, reliable downloads with multi-connection technology, pause/resume support, and automatic file verification.
```

### 6.7 App Review Information

**Contact Information:**
- First Name: Ahmed
- Last Name: Amouna
- Phone: Your phone number
- Email: Your email

**Notes for Reviewer:**
```
NanoJet is a download manager that helps users download files faster.

To test:
1. Launch the app
2. Copy any download URL (e.g., https://speed.hetzner.de/100MB.bin)
3. The app will detect it and ask to download
4. Click Start to begin download

The app requests network access for downloads and file access for saving files.

Thank you for reviewing!
```

**Click:** Save

---

## Part 7: Upload Build (10 minutes)

**Back in Xcode Organizer:**

1. **Select** your archive
2. **Click:** "Distribute App" button
3. **Select:** App Store Connect
4. **Click:** Next
5. **Select:** Upload
6. **Click:** Next
7. **Automatically manage signing:** Leave checked
8. **Click:** Next
9. **Review** the summary
10. **Click:** Upload
11. **Wait** (5-10 minutes)

**When upload completes:** ✅ Success!

---

## Part 8: Submit for Review (5 minutes)

**Go back to App Store Connect:**

1. **Refresh** the page
2. **Wait** for build to finish processing (30-60 minutes)
   - You'll get an email when it's ready
   - Or keep refreshing the page
3. **When build appears:**
   - **Click:** The **+** next to "Build"
   - **Select** your uploaded build
   - **Click:** Done
4. **Check everything is filled:**
   - ✅ Screenshots uploaded
   - ✅ Description filled
   - ✅ Privacy policy URL entered
   - ✅ Build selected
5. **Click:** "Add for Review" button (top right)
6. **Click:** "Submit for Review"

**🎉 DONE! Your app is submitted!**

---

## 📧 What Happens Next?

### Timeline:
- **Processing:** 30-60 minutes (automated by Apple)
- **Waiting for Review:** 1-24 hours
- **In Review:** 1-3 days
- **Total:** Usually 2-4 days

### You'll Get Emails:
1. "Your app is processing" ✉️
2. "Your app is ready for review" ✉️
3. "Your app is in review" ✉️
4. "Your app has been approved" ✉️ 🎉 (or needs changes)

### After Approval:
- Your app goes live on Mac App Store!
- You'll get the App Store link
- Users can find and download it

---

## 🆘 If Something Goes Wrong

### Build Errors?
Run: `./fix-build-errors.sh`

### Validation Fails?
- Check error message
- Common issue: Signing - make sure certificates are installed
- Run: `security find-identity -v -p codesigning`

### Need Help?
- Check `APP_STORE_SETUP_GUIDE.md` for detailed troubleshooting
- Apple Developer Support: https://developer.apple.com/contact/

---

## ✅ Quick Checklist

Before submitting, make sure:

- [ ] Ran `automate-appstore-setup.sh`
- [ ] Created certificates in developer portal
- [ ] Created App ID
- [ ] Created provisioning profile
- [ ] Configured Xcode signing
- [ ] App builds without errors
- [ ] Archive validates successfully
- [ ] Privacy policy uploaded to website
- [ ] Took 3+ screenshots
- [ ] Filled all App Store Connect fields
- [ ] Build uploaded and selected
- [ ] Submitted for review

---

**You can do this! Just follow each step carefully. Good luck! 🍀**

