# NanoJet Browser Extension Changelog

## Version 0.2.3 (2025-10-22)

### Bug Fixes
- **Fixed "Extension context invalidated" error** - The extension now handles being reloaded gracefully without breaking on already-open pages
- Added robust fallback mechanism when background script connection is lost
- Added proper error handling for all `chrome.runtime.sendMessage()` calls
- Extension continues to work (with graceful degradation) even when context is invalid

### Technical Improvements
- Added `isExtensionContextValid()` function to detect when extension context is lost
- Added `buildAndOpenDirect()` fallback function for direct downloads
- Added `chrome.runtime.lastError` checks in all message callbacks
- Made optional features (like file size HEAD requests) fail silently when context is invalid
- Added better console logging to help users understand what's happening

### User Experience
- No need to reload all browser tabs after extension update/reload
- Clear console warnings instead of cryptic errors
- Downloads continue to work even after extension is reloaded (with minor degradation: no HttpOnly cookies)

---

## Version 0.2.2

### Features
- Improved YouTube video detection and format selection
- Better metadata display (resolution, codec, audio/video indicators)
- Enhanced video detection on Facebook and other social media sites

### Bug Fixes
- Fixed video detection on sites with shadow DOM
- Improved cookie handling for authenticated downloads

---

## Version 0.2.1

### Features
- Added global floating download button for sites without `<video>` elements
- Better network interception for Telegram and similar sites
- Enhanced metadata extraction from URLs

### Bug Fixes
- Fixed positioning of download overlay buttons
- Improved video source detection

---

## Version 0.2.0

### Initial Release
- Download button overlay on video elements
- Context menu integration
- Automatic download interception
- Cookie and header forwarding
- YouTube format selection support

