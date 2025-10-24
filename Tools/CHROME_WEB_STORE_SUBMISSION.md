# Chrome Web Store Submission Guide

## Privacy Policy URL

**Use this URL when submitting to Chrome Web Store:**

```
https://github.com/ahmedsam007/IdmMac/blob/main/PRIVACY_POLICY.md
```

This URL points to your comprehensive privacy policy that clearly states:
- ✅ No user data is collected
- ✅ No external servers are contacted
- ✅ All operations are local
- ✅ Detailed permission explanations

---

## Extension Information for Submission

### Basic Information

**Extension Name:**
```
NanoJet Interceptor
```

**Short Description (132 characters max):**
```
Download videos and files using the NanoJet desktop app. Seamlessly intercepts downloads and sends them to your local app.
```

**Detailed Description:**

```
NanoJet Interceptor is a companion browser extension for the NanoJet desktop download manager application.

Features:
• Automatically detect downloadable videos and media on web pages
• One-click download button overlay on video elements
• Right-click context menu for links and media files
• Automatic download interception - send downloads to NanoJet app instead of browser
• Support for authenticated downloads with cookie forwarding
• Works with YouTube, Facebook, Instagram, Twitter, and many other sites

Privacy & Security:
• NO data collection - we don't collect any personal information
• NO analytics or tracking
• All operations are local to your device
• Open source - view our code on GitHub

How it works:
1. Install the extension and the NanoJet desktop app
2. Visit any website with downloadable media
3. Click the "Download" button that appears on videos
4. Or right-click any link and select "Download with NanoJet"
5. Downloads are automatically sent to your NanoJet app for fast, reliable downloading

Requirements:
• NanoJet desktop application must be installed on macOS
• Download the app from: https://github.com/ahmedsam007/IdmMac

This extension is completely free and open source. No subscriptions, no ads, no data collection.

Source code: https://github.com/ahmedsam007/IdmMac
```

### Category
```
Productivity
```

### Language
```
English
```

---

## Privacy Information

### Privacy Policy URL
```
https://github.com/ahmedsam007/IdmMac/blob/main/PRIVACY_POLICY.md
```

### Single Purpose Description
```
This extension detects downloadable media on web pages and sends download requests to the user's local NanoJet desktop application for enhanced download management.
```

### Permission Justifications

When Chrome Web Store asks why you need each permission, use these explanations:

**`downloads` permission:**
```
Required to intercept browser downloads and redirect them to the NanoJet desktop application for better download management.
```

**`tabs` permission:**
```
Needed to open the idmmac:// custom URL scheme in a new tab to communicate with the local NanoJet desktop application.
```

**`cookies` permission:**
```
Required to read website cookies and pass them to the local NanoJet app to enable authenticated downloads from sites where the user is logged in (e.g., private videos, member-only content).
```

**`storage` permission:**
```
Used to store extension settings and user preferences locally in the browser.
```

**`contextMenus` permission:**
```
Allows adding a "Download with NanoJet" option to the browser's right-click context menu for convenient access.
```

**`notifications` permission:**
```
Used to show notifications about download status and extension updates.
```

**`<all_urls>` / Host permissions:**
```
Required to detect downloadable media (videos, audio files) on any website the user visits. This permission allows the extension to scan page content for video elements and download URLs. All processing is done locally - no data is sent to external servers.
```

---

## Store Listing Assets

### Icons Required

You already have these in your extension:
- ✅ 16x16: `icons/icon16.png`
- ✅ 32x32: `icons/icon32.png`
- ✅ 48x48: `icons/icon48.png`
- ✅ 128x128: `icons/icon128.png`

### Additional Store Images Needed

Chrome Web Store requires promotional images:

**Small Promotional Tile (440x280 pixels)** - Required
- Create a banner with your app icon and text: "NanoJet - Enhanced Download Manager"

**Large Promotional Tile (920x680 pixels)** - Optional but recommended
- Create a larger banner showcasing features

**Marquee Promotional Tile (1400x560 pixels)** - Optional
- Wide banner for featured listings

**Screenshots (1280x800 or 640x400)** - At least 1 required, up to 5 recommended
- Screenshot 1: Extension overlay on a video showing the download button
- Screenshot 2: Context menu with "Download with NanoJet" option
- Screenshot 3: Extension popup or settings (if you have one)
- Screenshot 4: Download in progress in NanoJet app
- Screenshot 5: Successful download completed

---

## Upload Package

### What to Upload
```
Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip
```

**Important:** Extract this ZIP file and re-zip only the contents (not the folder itself) for Chrome Web Store submission.

```bash
# Prepare the package for Chrome Web Store
cd /Users/ahmed/Documents/NanoJet/Tools/ChromeExtension
unzip -q artifacts/idmmac_chrome_0.2.3.zip -d temp_extract
cd temp_extract
zip -r ../chrome_web_store_package.zip *
cd ..
rm -rf temp_extract
```

Then upload: `chrome_web_store_package.zip`

---

## Distribution Settings

### Visibility
Choose one:
- **Public** - Anyone can find and install
- **Unlisted** - Only people with the direct link can install
- **Private** - Only specific users/domains can install

Recommended: **Public** (unless you want to limit distribution)

### Regions
```
All regions (default)
```

---

## Developer Information

### Official URL (Optional)
```
https://github.com/ahmedsam007/IdmMac
```

### Homepage URL (Optional)
```
https://github.com/ahmedsam007/IdmMac
```

### Support URL (Optional)
```
https://github.com/ahmedsam007/IdmMac/issues
```

---

## Pricing

```
Free
```

---

## Review Tips

### Common Rejection Reasons & How We Address Them:

1. **Privacy Policy Missing** ✅ SOLVED
   - We have a comprehensive privacy policy at the required URL

2. **Unclear Permission Usage** ✅ SOLVED
   - We provide detailed justifications for each permission

3. **Data Collection Not Disclosed** ✅ SOLVED
   - Our privacy policy clearly states we collect NO data

4. **Single Purpose Violation** ✅ SOLVED
   - Our extension has a single, clear purpose: send downloads to NanoJet app

5. **Insufficient Description** ✅ SOLVED
   - We have a detailed description explaining all features

### Before Submitting:

- ✅ Test the extension thoroughly on a fresh Chrome install
- ✅ Ensure all permissions are necessary and justified
- ✅ Verify the privacy policy URL is accessible
- ✅ Check that all images/icons are correct size and format
- ✅ Review the extension name and description for clarity
- ✅ Make sure the manifest.json is valid

---

## Submission Checklist

- [ ] Extension package prepared (chrome_web_store_package.zip)
- [ ] Privacy policy URL ready: https://github.com/ahmedsam007/IdmMac/blob/main/PRIVACY_POLICY.md
- [ ] Store listing description written
- [ ] Permission justifications prepared
- [ ] Icons ready (16, 32, 48, 128)
- [ ] Promotional images created (at least 440x280)
- [ ] Screenshots taken (at least 1, preferably 5)
- [ ] Category selected: Productivity
- [ ] Support URL set: https://github.com/ahmedsam007/IdmMac/issues
- [ ] Developer account fee paid ($5 one-time)
- [ ] Extension tested on fresh Chrome install

---

## Submission URL

**Chrome Web Store Developer Dashboard:**
```
https://chrome.google.com/webstore/devconsole
```

**First time?** You'll need to:
1. Pay one-time $5 developer registration fee
2. Verify your email
3. Complete your developer profile

---

## After Submission

- Review typically takes **1-3 business days**
- You'll receive an email when the review is complete
- If rejected, address the feedback and resubmit
- Once approved, your extension will be live on the Chrome Web Store!

---

## Post-Publication

### Update the Extension

When you release v0.2.4 or later:
1. Update the version in manifest.json
2. Create the new package
3. Upload to Chrome Web Store Developer Dashboard
4. The update will be automatically distributed to all users

### Monitor Reviews

- Check Chrome Web Store reviews regularly
- Respond to user feedback
- Use feedback to improve the extension

---

**Good luck with your submission!** 🚀

If you have any questions during the submission process, refer to the official Chrome Web Store documentation:
https://developer.chrome.com/docs/webstore/

