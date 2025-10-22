# 🚨 Important Update: IDMMac Extension v0.2.3 Available

## Critical Bug Fix - Please Update!

We've fixed a critical bug that was causing the **"Extension context invalidated"** error. If you've experienced this error, please update to version 0.2.3.

---

## 🐛 What Was Fixed

**Problem:** The extension would stop working and show errors after being updated or reloaded, requiring you to refresh all browser tabs.

**Solution:** The extension now handles updates gracefully and continues working without needing to refresh your pages!

---

## ✅ How to Check Your Current Version

### Chrome/Edge/Brave
1. Go to `chrome://extensions/` (or `edge://extensions/`)
2. Find "IDMMac Interceptor"
3. Look at the version number under the extension name
4. If it's **older than 0.2.3**, please update!

### Firefox
1. Go to `about:addons`
2. Find "IDMMac Interceptor"
3. Click on it to see the version
4. If it's **older than 0.2.3**, please update!

---

## 📥 How to Update

### Option 1: Download from GitHub (Recommended)

**For Chrome/Edge/Brave:**
1. Download: [idmmac_chrome_0.2.3.zip](https://github.com/ahmedsam007/IdmMac/raw/main/Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip)
2. Extract the ZIP file
3. Go to `chrome://extensions/`
4. Remove the old "IDMMac Interceptor" extension
5. Enable "Developer mode" (top-right toggle)
6. Click "Load unpacked"
7. Select the extracted folder
8. Done! ✅

**For Firefox:**
1. Download: [idmmac_firefox_0.2.3.xpi](https://github.com/ahmedsam007/IdmMac/raw/main/Tools/FirefoxExtension/artifacts-firefox/idmmac_firefox_0.2.3.xpi)
2. Go to `about:addons`
3. Remove the old "IDMMac Interceptor" extension
4. Click the gear icon ⚙️ → "Install Add-on From File..."
5. Select the downloaded .xpi file
6. Click "Add" to confirm
7. Done! ✅

### Option 2: Clone/Pull from GitHub

If you have the repository:
```bash
cd /path/to/IdmMac
git pull origin main
```

Then follow the installation steps above using the files from:
- Chrome: `Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip`
- Firefox: `Tools/FirefoxExtension/artifacts-firefox/idmmac_firefox_0.2.3.xpi`

---

## 🎉 What's New in v0.2.3

✅ **Fixed "Extension context invalidated" error**
- Extension continues working after updates
- No need to reload browser tabs
- Graceful fallback when background script is unavailable

✅ **Better error handling**
- Clear, helpful console messages
- No more cryptic errors
- Downloads continue to work even during edge cases

✅ **Improved stability**
- Robust error recovery
- Better handling of edge cases
- More reliable video detection

---

## 🆘 Need Help?

If you encounter any issues:

1. **Check the browser console** (F12 → Console tab) for error messages
2. **Make sure IDMMac app is running**
3. **Try reloading the page** after installing the update
4. **Report issues** on GitHub: [github.com/ahmedsam007/IdmMac/issues](https://github.com/ahmedsam007/IdmMac/issues)

---

## 📋 Full Changelog

See [CHANGELOG.md](https://github.com/ahmedsam007/IdmMac/blob/main/Tools/ChromeExtension/CHANGELOG.md) for detailed version history.

---

**Thank you for using IDMMac!** 🙏

