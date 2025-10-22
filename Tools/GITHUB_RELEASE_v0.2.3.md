# GitHub Release Notes for v0.2.3

## Release Title
```
IDMMac Browser Extension v0.2.3 - Critical Bug Fix
```

## Release Tag
```
extension-v0.2.3
```

## Release Description

```markdown
## 🐛 Critical Bug Fix - Extension Context Invalidation

This release fixes the **"Extension context invalidated"** error that occurred when the extension was reloaded or updated while browser tabs were still open.

### What's Fixed

✅ **Extension Context Invalidation Error**
- Extension now gracefully handles being reloaded/updated
- No need to refresh browser tabs after extension updates
- Graceful fallback when background script connection is lost
- Clear, helpful error messages instead of cryptic failures

### Technical Improvements

- Added `isExtensionContextValid()` function to detect invalid extension context
- Added `buildAndOpenDirect()` fallback function for graceful degradation
- Added `chrome.runtime.lastError` checks in all message callbacks
- Made optional features (file size enrichment) fail silently when context is invalid
- Enhanced error handling throughout the extension

### Impact

**Before:** Extension would completely fail after being reloaded, requiring users to reload all open web pages.

**After:** Extension continues to work with graceful degradation (HttpOnly cookies unavailable only), providing a seamless user experience.

---

## 📥 Installation

### Chrome / Edge / Brave / Opera

1. Download `idmmac_chrome_0.2.3.zip` below
2. Extract the ZIP file to a folder
3. Open `chrome://extensions/` (or equivalent for your browser)
4. Enable "Developer mode" (toggle in top-right)
5. Remove old IDMMac extension if installed
6. Click "Load unpacked" and select the extracted folder

### Firefox

1. Download `idmmac_firefox_0.2.3.xpi` below
2. Open `about:addons`
3. Remove old IDMMac extension if installed
4. Click gear icon ⚙️ → "Install Add-on From File..."
5. Select the downloaded .xpi file

---

## 📋 Files

- **idmmac_chrome_0.2.3.zip** - Chrome/Edge/Brave extension
- **idmmac_firefox_0.2.3.xpi** - Firefox extension

---

## 📚 Documentation

- [Installation Guide](Tools/INSTALL_EXTENSION_UPDATE.md)
- [Technical Fix Details](Tools/EXTENSION_CONTEXT_FIX.md)
- [Changelog](Tools/ChromeExtension/CHANGELOG.md)

---

## 🔗 Links

- **Full Commit:** https://github.com/ahmedsam007/IdmMac/commit/b9810e6
- **Report Issues:** https://github.com/ahmedsam007/IdmMac/issues

---

**Upgrade is highly recommended for all users!**
```

## Files to Attach to Release

Upload these files as release assets:
1. `Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip`
2. `Tools/FirefoxExtension/artifacts-firefox/idmmac_firefox_0.2.3.xpi`

## How to Create the Release on GitHub

### Using GitHub Web Interface:

1. Go to: https://github.com/ahmedsam007/IdmMac/releases/new

2. Fill in the form:
   - **Tag:** `extension-v0.2.3`
   - **Target:** `main`
   - **Title:** `IDMMac Browser Extension v0.2.3 - Critical Bug Fix`
   - **Description:** Copy the release description above
   - **Attach files:** Upload the 2 files listed above

3. Check "Set as the latest release"

4. Click "Publish release"

### Using GitHub CLI (gh):

```bash
# Make sure you're in the project directory
cd /Users/ahmed/Documents/IDMMac

# Create the release
gh release create extension-v0.2.3 \
  --title "IDMMac Browser Extension v0.2.3 - Critical Bug Fix" \
  --notes-file Tools/GITHUB_RELEASE_v0.2.3.md \
  Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip \
  Tools/FirefoxExtension/artifacts-firefox/idmmac_firefox_0.2.3.xpi

# The release will be automatically published and set as latest
```

---

## After Publishing

1. **Share the release URL** with your users
2. **Post an announcement** on your social media / user groups
3. **Send notification** using the UPDATE_NOTIFICATION_v0.2.3.md content
4. **Monitor for issues** in the GitHub issues section

