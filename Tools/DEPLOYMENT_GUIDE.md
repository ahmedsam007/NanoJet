# 🚀 IDMMac Update Deployment Guide

This guide explains how to test updates locally and deploy them to real users.

---

## 📋 Table of Contents

1. [Testing Real Updates Locally](#testing-real-updates-locally)
2. [Deploying Updates to Users](#deploying-updates-to-users)
3. [Complete Release Workflow](#complete-release-workflow)
4. [Troubleshooting](#troubleshooting)

---

## 🧪 Testing Real Updates Locally

### Step 1: Build Archive for Distribution

```bash
# In Xcode:
# 1. Product → Archive
# 2. Wait for archive to complete
# 3. In Organizer → Select your archive
# 4. Click "Distribute App" → "Copy App"
# 5. Choose a location (e.g., ~/Desktop/IDMMacApp-Test)
```

Or use command line:

```bash
cd /Users/ahmed/Documents/IDMMac

# Build for release
xcodebuild archive \
  -scheme IDMMacApp \
  -archivePath ~/Desktop/IDMMacApp.xcarchive \
  -configuration Release

# Export the app
xcodebuild -exportArchive \
  -archivePath ~/Desktop/IDMMacApp.xcarchive \
  -exportPath ~/Desktop/IDMMacApp-Export \
  -exportOptionsPlist ExportOptions.plist
```

### Step 2: Create a Test Update Package

```bash
cd ~/Desktop

# Create a test version 0.2.0
cp -r IDMMacApp-Export/IDMMacApp.app ./IDMMacApp-0.2.0.app

# Manually change the version (or rebuild with incremented version)
# Edit Info.plist inside the app bundle:
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.2.0" \
  IDMMacApp-0.2.0.app/Contents/Info.plist

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 2" \
  IDMMacApp-0.2.0.app/Contents/Info.plist

# Zip it
cd /Users/ahmed/Documents/IDMMac
./Tools/sign_update.sh ~/Desktop/IDMMacApp-0.2.0.app 0.2.0
```

### Step 3: Set Up Local Test Server

```bash
# The test files should be in Tools/ directory
cd /Users/ahmed/Documents/IDMMac/Tools

# Move the signed update here
mv ~/Desktop/IDMMacApp-0.2.0.zip ./test-update-real.zip

# Update test-appcast-UPDATE-AVAILABLE.xml with the output from sign_update.sh

# Server should already be running on port 8000
# If not, start it:
python3 -m http.server 8000
```

### Step 4: Test the Update Flow

1. **Install the OLD version (0.1.0)**:
   - Quit any running IDMMac instances
   - Delete existing app: `rm -rf /Applications/IDMMacApp.app`
   - Copy v0.1.0 to Applications: `cp -r ~/Desktop/IDMMacApp-Export/IDMMacApp.app /Applications/`
   - Launch from Applications

2. **Check for Updates**:
   - Click gear icon ⚙️ → "Check for Updates…"
   - Should show "Version 0.2.0 available"

3. **Install the Update**:
   - Click "Install Update"
   - Sparkle will download, verify signature, and install
   - App will quit and relaunch with new version

4. **Verify New Version**:
   - App menu → About IDMMac
   - Should show version 0.2.0

---

## 🌐 Deploying Updates to Users

### Prerequisites

You need access to **https://ahmedsam.com** with the ability to upload files.

### Step 1: Prepare Your Server

Create this directory structure on your server:

```
ahmedsam.com/
└── idmmac/
    ├── appcast.xml           (update feed)
    └── downloads/
        ├── IDMMacApp-0.1.0.zip
        ├── IDMMacApp-0.2.0.zip
        └── ... (future versions)
```

### Step 2: Update Info.plist for Production

```bash
cd /Users/ahmed/Documents/IDMMac/IDMMacApp/Resources
```

Edit `Info.plist` and ensure the `SUFeedURL` points to production:

```xml
<key>SUFeedURL</key>
<string>https://ahmedsam.com/idmmac/appcast.xml</string>
```

**Important**: Remove the `localhost:8000` test URL before releasing!

### Step 3: Build Release Version

```bash
cd /Users/ahmed/Documents/IDMMac

# Increment version number first in project.yml or Xcode
# Then build for release

# Option A: Using Xcode
# 1. Product → Archive
# 2. Organizer → Distribute App → Copy App

# Option B: Command Line
xcodebuild archive \
  -scheme IDMMacApp \
  -archivePath ~/Desktop/IDMMacApp-Release.xcarchive \
  -configuration Release

xcodebuild -exportArchive \
  -archivePath ~/Desktop/IDMMacApp-Release.xcarchive \
  -exportPath ~/Desktop/IDMMacApp-Release \
  -exportOptionsPlist ExportOptions.plist
```

### Step 4: Sign the Update

```bash
# Sign your new release
cd /Users/ahmed/Documents/IDMMac
./Tools/sign_update.sh ~/Desktop/IDMMacApp-Release/IDMMacApp.app 0.2.0

# This will output:
# - IDMMacApp-0.2.0.zip (the signed package)
# - Appcast XML entry with signature
```

**Output Example**:
```xml
<item>
    <title>Version 0.2.0</title>
    <sparkle:version>2</sparkle:version>
    <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
    <enclosure 
        url="https://ahmedsam.com/idmmac/downloads/IDMMacApp-0.2.0.zip"
        length="12345678"
        type="application/octet-stream"
        sparkle:edSignature="abc123...xyz789" />
</item>
```

### Step 5: Update appcast.xml

Edit `Tools/appcast.xml`:

```bash
cd /Users/ahmed/Documents/IDMMac/Tools
nano appcast.xml
```

Add the new release **at the top** (most recent first):

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>IDMMac Updates</title>
        <link>https://ahmedsam.com/idmmac/appcast.xml</link>
        <description>Most recent updates for IDMMac</description>
        <language>en</language>
        
        <!-- NEW RELEASE - Add at the top -->
        <item>
            <title>Version 0.2.0</title>
            <description><![CDATA[
                <h3>🎉 What's New in IDMMac 0.2.0</h3>
                <ul>
                    <li>✨ Dark mode support</li>
                    <li>🔄 Automatic updates</li>
                    <li>🐛 Bug fixes</li>
                </ul>
            ]]></description>
            <pubDate>Mon, 21 Oct 2025 10:00:00 +0000</pubDate>
            <sparkle:version>2</sparkle:version>
            <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url="https://ahmedsam.com/idmmac/downloads/IDMMacApp-0.2.0.zip"
                length="PASTE_LENGTH_HERE"
                type="application/octet-stream"
                sparkle:edSignature="PASTE_SIGNATURE_HERE" />
        </item>
        
        <!-- Older releases below -->
        <item>
            <title>Version 0.1.0</title>
            ...
        </item>
        
    </channel>
</rss>
```

### Step 6: Upload to Server

```bash
# Upload the signed ZIP
scp ~/Desktop/IDMMacApp-0.2.0.zip user@ahmedsam.com:/path/to/idmmac/downloads/

# Upload the updated appcast
scp Tools/appcast.xml user@ahmedsam.com:/path/to/idmmac/appcast.xml

# Or use SFTP, FTP, cPanel File Manager, etc.
```

### Step 7: Verify Deployment

Test from a different machine or clean environment:

```bash
# Download the appcast and verify it's accessible
curl -I https://ahmedsam.com/idmmac/appcast.xml

# Should return: HTTP/1.1 200 OK

# Download the update package
curl -I https://ahmedsam.com/idmmac/downloads/IDMMacApp-0.2.0.zip

# Should return: HTTP/1.1 200 OK
```

### Step 8: Notify Users

Users will be notified automatically in two ways:

1. **Automatic Check**: Every 24 hours (set in `SUScheduledCheckInterval`)
2. **Manual Check**: When they click gear icon → "Check for Updates…"

---

## 📦 Complete Release Workflow

Here's the complete step-by-step process for releasing an update:

### 1. Prepare Release

```bash
# 1. Update version number in project.yml or Xcode
# 2. Update CHANGELOG.md with release notes
# 3. Commit changes
git add -A
git commit -m "Bump version to 0.2.0"
git tag -a v0.2.0 -m "Release version 0.2.0"
git push origin main --tags
```

### 2. Build & Sign

```bash
# Build for release (Xcode: Product → Archive)
# Then use the sign script:
cd /Users/ahmed/Documents/IDMMac
./Tools/sign_update.sh ~/Desktop/IDMMacApp-Release/IDMMacApp.app 0.2.0

# Save the output (signature and length)
```

### 3. Update Appcast

```bash
# Edit Tools/appcast.xml
# Add new <item> at the top with:
# - Version number
# - Release date
# - Release notes (HTML)
# - Download URL
# - File length (from sign_update.sh)
# - EdDSA signature (from sign_update.sh)
```

### 4. Upload Files

```bash
# Upload signed ZIP to your server
scp IDMMacApp-0.2.0.zip user@ahmedsam.com:/idmmac/downloads/

# Upload updated appcast.xml
scp Tools/appcast.xml user@ahmedsam.com:/idmmac/appcast.xml
```

### 5. Test

```bash
# On a test Mac with old version installed:
# 1. Open IDMMacApp
# 2. Gear icon → Check for Updates
# 3. Verify update is detected
# 4. Install and verify it works
```

### 6. Monitor

```bash
# Check your server logs for update requests
# Monitor for any issues reported by users
```

---

## 🔧 Troubleshooting

### Update Not Detected

**Problem**: Users don't see the update.

**Solutions**:
1. Check the `SUFeedURL` in Info.plist points to production
2. Verify appcast.xml is accessible: `curl https://ahmedsam.com/idmmac/appcast.xml`
3. Ensure version numbers are higher than current version
4. Check XML is valid: `xmllint --noout appcast.xml`

### Signature Verification Failed

**Problem**: "Update signature invalid"

**Solutions**:
1. Verify `SUPublicEDKey` in Info.plist matches your public key
2. Re-sign the update: `./Tools/sign_update.sh YourApp.app version`
3. Ensure you're using the correct private key from Keychain

### Download Fails

**Problem**: Update downloads but fails to install.

**Solutions**:
1. Check file permissions on server (should be readable)
2. Verify ZIP file is not corrupted: `unzip -t IDMMacApp-0.2.0.zip`
3. Ensure `length` attribute in appcast matches actual file size

### App Won't Launch After Update

**Problem**: App crashes or won't start after updating.

**Solutions**:
1. Check app is properly code-signed
2. Verify all frameworks/dependencies are included
3. Test the update ZIP on a clean Mac before deploying

---

## 📝 Quick Reference Commands

```bash
# Sign an update
./Tools/sign_update.sh ~/path/to/YourApp.app 1.0.0

# Start local test server
cd Tools && python3 -m http.server 8000

# Verify XML is valid
xmllint --noout appcast.xml

# Check version in built app
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  /Applications/IDMMacApp.app/Contents/Info.plist

# Upload to server
scp file.zip user@server.com:/path/
```

---

## 🎯 Best Practices

1. **Always test updates locally first** before deploying to production
2. **Keep backups** of all released versions
3. **Use semantic versioning**: `MAJOR.MINOR.PATCH` (e.g., 0.2.0)
4. **Write clear release notes** - users appreciate knowing what changed
5. **Don't skip versions** in appcast.xml - keep history
6. **Monitor your update server** - ensure it's always accessible
7. **Sign everything** - never skip signature verification
8. **Test on multiple macOS versions** if you support them

---

## 🔐 Security Notes

- **NEVER commit your private key** to git
- Keep private key in macOS Keychain only
- Use HTTPS for appcast.xml (not HTTP)
- Always verify signatures locally before deploying
- Consider notarizing your app with Apple (required for macOS 10.15+)

---

## 📞 Support

If you encounter issues:
1. Check Sparkle documentation: https://sparkle-project.org/documentation/
2. Check macOS Console.app for Sparkle logs (filter by "Sparkle")
3. Test with verbose logging enabled

---

**Last Updated**: October 20, 2025
**Sparkle Version**: 2.6.4

