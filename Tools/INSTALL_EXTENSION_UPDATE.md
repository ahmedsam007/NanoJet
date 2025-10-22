# How to Install IDMMac Extension Update (v0.2.3)

## What's Fixed in v0.2.3?
- **Fixed "Extension context invalidated" error** that appeared when the extension was reloaded
- Extension now works even after being updated/reloaded without needing to refresh all tabs
- Better error handling and graceful fallbacks

## Quick Install Guide

### For Chrome/Edge/Brave/Opera

1. **Download the extension package:**
   - Location: `Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip`

2. **Extract the ZIP file** to a folder on your computer

3. **Open your browser's extensions page:**
   - Chrome: `chrome://extensions/`
   - Edge: `edge://extensions/`
   - Brave: `brave://extensions/`
   - Opera: `opera://extensions/`

4. **Enable "Developer mode"** (toggle in top-right corner)

5. **Remove the old IDMMac extension** (if you have it installed):
   - Click "Remove" on the old IDMMac Interceptor extension

6. **Click "Load unpacked"**

7. **Select the extracted folder** from step 2

8. **Done!** The extension is now installed and updated

### For Firefox

1. **Download the extension package:**
   - Location: `Tools/FirefoxExtension/artifacts-firefox/idmmac_firefox_0.2.3.xpi`

2. **Open Firefox Add-ons page:**
   - Type `about:addons` in the address bar

3. **Remove the old extension** (if you have it installed):
   - Find "IDMMac Interceptor" and click "Remove"

4. **Install the new version:**
   - Click the gear icon ⚙️ in the top-right
   - Select "Install Add-on From File..."
   - Choose `idmmac_firefox_0.2.3.xpi`
   - Click "Add" when Firefox asks for confirmation

5. **Done!** The extension is now installed and updated

## Verification

To verify the update worked:

1. Visit a video site (e.g., https://www.facebook.com/reel/...)
2. You should see a "Download" button appear on videos
3. Click it - IDMMac should open with the download

## If You Still See Errors

If you previously had the error:
1. **Reload all tabs** that had videos open before the update
2. Or just open a new tab with a video
3. The error should no longer appear

## Need Help?

If you still encounter issues:
- Check the browser console (F12) for any error messages
- Make sure the IDMMac app is running
- Verify the extension is enabled in your browser's extension page

