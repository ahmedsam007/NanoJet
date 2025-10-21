# IDMMac - Installation Instructions

Welcome! Thank you for trying IDMMac.

## What is IDMMac?

IDMMac is a download manager for macOS that helps you download files faster and more efficiently.

## Installation Steps

### 1. Extract the App
- Locate the `IDMMacApp.app` file you downloaded
- Drag it to your **Applications** folder (optional but recommended)

### 2. First Launch (Important!)

⚠️ **Because this app is not notarized by Apple, you need to follow these steps:**

**Method 1: Right-Click to Open (Recommended)**
1. Right-click (or Control+Click) on `IDMMacApp.app`
2. Select **"Open"** from the menu
3. Click **"Open"** in the dialog that appears
4. The app will now launch and be trusted for future launches

**Method 2: Using System Settings**
1. Try to open the app normally (it will be blocked)
2. Go to **System Settings** → **Privacy & Security**
3. Scroll down and click **"Open Anyway"**
4. Confirm by clicking **"Open"**

### 3. Start Using IDMMac!

After the first successful launch, you can open the app normally like any other application.

## Browser Extension

IDMMac works with browser extensions for Chrome and Firefox to automatically capture downloads.

The extensions are bundled inside the app. To install them:

1. Open IDMMac
2. Go to Settings
3. Follow the instructions to install the browser extension

## System Requirements

- macOS 13.0 (Ventura) or later
- 100 MB free disk space

## Having Issues?

### "IDMMacApp.app is damaged and can't be opened"

This happens due to macOS Gatekeeper. Run this command in Terminal:

```bash
xattr -cr /Applications/IDMMacApp.app
```

Then try the right-click → Open method again.

### "Cannot verify developer"

This is normal for apps not signed with an Apple Developer certificate. Use the right-click → Open method described above.

### App crashes on launch

Make sure you're running macOS 13.0 or later. Check **About This Mac** in the Apple menu.

## Privacy & Security

- This app does not collect any personal data
- Downloads are stored locally on your Mac
- No analytics or tracking

## Support

If you need help or want to report an issue, please contact the developer.

## License

See the LICENSE file included with the app for terms of use.

---

Enjoy using IDMMacApp! 🚀

