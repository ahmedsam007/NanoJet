# Extension Context Invalidation Fix - v0.2.3

## Problem
Users encountered the error "Extension context invalidated" when using the NanoJet Chrome/Firefox extension. This error occurred when:
- The extension was reloaded or updated
- The extension was disabled and re-enabled
- Content scripts were still running on web pages after the extension was reloaded

The error appeared in the console as:
```
NanoJet build/open error Error: Extension context invalidated.
```

## Root Cause
When a Chrome extension is reloaded, the background service worker (worker.js) is restarted, but content scripts (content.js) continue running on already-open web pages. Any attempt by the content script to communicate with the background script using `chrome.runtime.sendMessage()` would fail with "Extension context invalidated" because the connection was lost.

## Solution
Implemented a robust fallback mechanism in both Chrome and Firefox extensions that:

1. **Detects Invalid Context**: Added `isExtensionContextValid()` function that checks if the extension context is still valid by verifying `chrome.runtime.id` exists.

2. **Graceful Fallback**: When the context is invalid, the extension now:
   - Uses a direct `window.open()` fallback with the `idmmac://` custom URL scheme
   - Still passes headers (Referer, Origin, User-Agent) and same-origin cookies
   - Logs a clear warning message to the console instead of throwing an error
   - Continues to function even without HttpOnly cookies (which require the background script)

3. **Error Handling**: Added `chrome.runtime.lastError` checks in all message callbacks to detect when messages fail mid-flight.

4. **Optional Features**: Made optional features (like file size enrichment via HEAD requests) silently fail instead of crashing when the context is invalid.

## Changes Made

### Chrome Extension (Tools/ChromeExtension/)
- **content.js**: 
  - Added `isExtensionContextValid()` function
  - Added `buildAndOpenDirect()` fallback function
  - Updated `sendToApp()` with context validation and error handling
  - Updated `showMenu()` to check context before HEAD requests
  - Updated `ensureGlobalButton()` to check context before getting icon URL

### Firefox Extension (Tools/FirefoxExtension/)
- **content.js**: 
  - Applied same fixes as Chrome extension
  - Added `collectGlobalSources()` function (was missing)
  - Added Firefox-specific lastError handling

### Version Updates
- Chrome extension: v0.2.2 → v0.2.3
- Firefox extension: v0.2.0 → v0.2.3

## Installation

### Chrome/Edge/Brave
1. Remove the old extension (optional but recommended)
2. Install the new version from:
   - `Tools/ChromeExtension/artifacts/idmmac_chrome_0.2.3.zip`
3. Extract the zip and load it as an unpacked extension in chrome://extensions/

### Firefox
1. Remove the old extension (optional but recommended)
2. Install the new version from:
   - `Tools/FirefoxExtension/artifacts-firefox/idmmac_firefox_0.2.3.xpi`
3. Open about:addons and drag the .xpi file to install (or use "Install Add-on From File...")

## Testing
1. Install the new extension
2. Navigate to a video site (e.g., Facebook, YouTube, Vimeo)
3. Click the "Download" button on a video
4. The download should open in NanoJet
5. **To test the fix specifically:**
   - With a video page open, go to chrome://extensions/
   - Click the reload button on the NanoJet extension
   - Go back to the video page (DO NOT reload the page)
   - Click the "Download" button again
   - Previously: Would show "Extension context invalidated" error
   - Now: Should work correctly with a console warning but still trigger the download

## User Impact
- **Before**: Extension would completely fail after being reloaded, requiring users to reload all open web pages
- **After**: Extension continues to work with graceful degradation (missing HttpOnly cookies only)
- Users will see a helpful console message: "NanoJet: Extension context invalidated. Using fallback method. Please reload the page for full functionality."

## Technical Notes
- The fallback method cannot access HttpOnly cookies (requires background script)
- Same-origin cookies accessible via `document.cookie` are still included
- Most video downloads work fine without HttpOnly cookies
- Users can reload the page for full functionality including HttpOnly cookies

