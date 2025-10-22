# Privacy Policy for IDMMac Browser Extension

**Last Updated:** October 22, 2025

## Introduction

IDMMac ("we", "our", or "the extension") is a browser extension that helps users download media files using the IDMMac desktop application. This privacy policy explains how the extension handles data.

## Our Commitment to Your Privacy

**We do NOT collect, store, transmit, or share any personal information or user data.**

The IDMMac extension operates entirely locally on your device and does not communicate with any external servers, analytics services, or third-party services.

## What the Extension Does

The IDMMac extension:

1. **Detects downloadable media** on web pages you visit
2. **Extracts download URLs** from video and audio elements
3. **Sends download information to your local IDMMac app** using the `idmmac://` custom URL scheme
4. **Reads cookies** from websites (only to pass them to your local app for authenticated downloads)
5. **Adds a download button overlay** on video elements for your convenience

All of these operations happen **locally on your device**. No data leaves your computer except to communicate with your own IDMMac desktop application running on the same machine.

## Data Collection and Usage

### We Do NOT Collect:

- ❌ Personal information (name, email, address, etc.)
- ❌ Browsing history
- ❌ Search queries
- ❌ IP addresses
- ❌ Device information
- ❌ Location data
- ❌ Analytics or usage statistics
- ❌ Cookies or website data for our own purposes
- ❌ Any data that is sent to remote servers

### What Data the Extension Accesses Locally:

The extension accesses the following data **only locally** to perform its function:

1. **Cookies**: Read from websites to enable authenticated downloads (e.g., downloading private videos). These cookies are passed directly to your local IDMMac app and are never sent anywhere else.

2. **Page Content**: Scans web pages for `<video>`, `<audio>`, and media URLs to detect downloadable content. This information stays in your browser and is only used to show you download options.

3. **Network Requests**: Monitors network requests on pages to detect media URLs (e.g., .mp4, .webm files). This data is processed locally and never transmitted externally.

4. **User-Agent and Referrer Headers**: These are read from your browser and passed to your local IDMMac app to ensure successful downloads. No external servers receive this information.

## Permissions Explained

The extension requires certain browser permissions to function. Here's what each permission is used for:

### Required Permissions:

- **`downloads`**: To intercept browser downloads and redirect them to IDMMac app
- **`tabs`**: To open the `idmmac://` custom URL scheme in a new tab to communicate with your local app
- **`cookies`**: To read cookies from websites and pass them to your local app for authenticated downloads
- **`storage`**: To save your extension settings (e.g., enabled/disabled state) locally in your browser
- **`contextMenus`**: To add "Download with IDMMac" option to right-click menus
- **`<all_urls>` / Host Permissions**: To detect downloadable media on any website you visit

**All permissions are used exclusively for local operations. No data is sent to external servers.**

## Data Storage

The extension stores minimal data locally in your browser using the `chrome.storage` API:

- Extension settings and preferences
- User configuration (if any)

This data:
- ✅ Stays on your device
- ✅ Is not synchronized across devices
- ✅ Is not accessible to us or any third party
- ✅ Is deleted when you uninstall the extension

## Third-Party Services

**We do not use any third-party services**, including:

- No analytics services (e.g., Google Analytics)
- No error tracking services
- No advertising networks
- No data collection platforms
- No cloud storage services

## Communication

The extension communicates **only** with:

1. **Your local IDMMac desktop application** running on your computer via the `idmmac://` custom URL scheme
2. **Websites you visit** to detect downloadable media (standard browser behavior)

The extension does **NOT** communicate with:
- Our servers (we don't have any)
- Third-party servers
- Analytics services
- Any external services

## Children's Privacy

The extension does not knowingly collect any information from anyone, including children under the age of 13. Since we don't collect any data at all, the extension is safe for users of all ages.

## Changes to This Privacy Policy

We may update this privacy policy from time to time. Any changes will be posted on this page with an updated "Last Updated" date. We encourage you to review this policy periodically.

## Data Security

Since we don't collect or transmit any user data, there is no risk of data breaches or unauthorized access to your information through our extension. All data processing happens locally on your device.

## Your Rights

Since we don't collect any personal data:

- There is no data to request access to
- There is no data to delete
- There is no data to export
- There is no data to correct

Your privacy is inherently protected because we simply don't collect any data.

## Open Source

The IDMMac extension is open source. You can review the source code at:

**GitHub Repository:** https://github.com/ahmedsam007/IdmMac

The source code clearly shows that no data collection or external communication occurs.

## Contact Information

If you have any questions or concerns about this privacy policy, please contact us:

- **GitHub Issues:** https://github.com/ahmedsam007/IdmMac/issues
- **GitHub Repository:** https://github.com/ahmedsam007/IdmMac

## Summary

**In short:**
- ✅ We do NOT collect any personal information
- ✅ We do NOT track your browsing activity
- ✅ We do NOT send data to any servers
- ✅ We do NOT use analytics or tracking services
- ✅ All operations are local to your device
- ✅ Your privacy is fully protected

The IDMMac extension is designed with privacy as a top priority. It performs its function entirely on your device without collecting or transmitting any user data.

---

**By using the IDMMac extension, you agree to this privacy policy.**

For the full terms of use, please visit: https://github.com/ahmedsam007/IdmMac

---

*This privacy policy is effective as of October 22, 2025.*

