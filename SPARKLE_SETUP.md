# Sparkle 2 Update Setup Guide

This guide explains how to set up automatic updates for NanoJet using Sparkle 2 framework.

## Overview

NanoJet now includes Sparkle 2 for secure automatic updates:
- ✅ HTTPS update feed checking
- ✅ EdDSA signature verification
- ✅ One-click updates for users
- ✅ Delta updates support (smaller downloads)

## Prerequisites

1. A web server to host your appcast feed and releases
2. Command-line tools for signing updates
3. macOS Developer ID certificate for code signing

## Step 1: Install Sparkle Tools

Download Sparkle 2 tools from: https://github.com/sparkle-project/Sparkle/releases

```bash
# Extract Sparkle tools
unzip Sparkle-2.x.x.tar.xz
cd Sparkle-2.x.x/bin
```

## Step 2: Generate EdDSA Keys

Generate a public/private key pair for signing your updates:

```bash
./generate_keys
```

This creates:
- **Private key**: Keep this SECRET and secure (used for signing)
- **Public key**: Add to your Info.plist (for verification)

### Update Info.plist

Replace `YOUR_SPARKLE_PUBLIC_KEY_HERE` in `NanoJetApp/Resources/Info.plist` with your public key:

```xml
<key>SUPublicEDKey</key>
<string>YOUR_ACTUAL_PUBLIC_KEY</string>
```

### Store Private Key Securely

Save your private key in a secure location (NOT in your repository):

```bash
# Example: Save to 1Password, Keychain, or secure file
echo "YOUR_PRIVATE_KEY" > ~/.sparkle_private_key
chmod 600 ~/.sparkle_private_key
```

## Step 3: Configure Update Feed URL

Update the `SUFeedURL` in `Info.plist` to point to your appcast feed:

```xml
<key>SUFeedURL</key>
<string>https://ahmedsam.com/idmmac/appcast.xml</string>
```

## Step 4: Build and Archive Your Release

1. **Build Release version** in Xcode:
   - Product → Archive
   - Distribute App → Developer ID
   - Export notarized .app

2. **Create ZIP of your app**:
   ```bash
   ditto -c -k --keepParent NanoJetApp.app NanoJetApp-0.1.0.zip
   ```

## Step 5: Sign Your Update

Sign the release ZIP with your private key:

```bash
./sign_update NanoJetApp-0.1.0.zip -f ~/.sparkle_private_key
```

This outputs an **EdDSA signature** - save this for the appcast.

## Step 6: Create Appcast Feed

Create an `appcast.xml` file on your server:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>NanoJet Updates</title>
        <link>https://ahmedsam.com/idmmac/appcast.xml</link>
        <description>Most recent updates for NanoJet</description>
        <language>en</language>
        
        <item>
            <title>Version 0.1.0</title>
            <description><![CDATA[
                <h3>What's New in NanoJet 0.1.0</h3>
                <ul>
                    <li>Initial release</li>
                    <li>Segmented multi-connection downloads</li>
                    <li>Pause/resume support</li>
                    <li>SHA-256 file verification</li>
                    <li>Browser extension integration</li>
                </ul>
            ]]></description>
            <pubDate>Mon, 20 Oct 2025 10:00:00 +0000</pubDate>
            <sparkle:version>1</sparkle:version>
            <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url="https://ahmedsam.com/idmmac/downloads/NanoJetApp-0.1.0.zip"
                length="12345678"
                type="application/octet-stream"
                sparkle:edSignature="YOUR_SIGNATURE_FROM_SIGN_UPDATE" />
        </item>
        
    </channel>
</rss>
```

### Important Fields:

- **sparkle:version**: Build number (CFBundleVersion)
- **sparkle:shortVersionString**: Marketing version (0.1.0)
- **enclosure url**: Direct download URL for the ZIP
- **length**: File size in bytes (`ls -l NanoJetApp-0.1.0.zip`)
- **sparkle:edSignature**: Signature from `sign_update` command

## Step 7: Upload to Your Server

Upload to your web server:

```bash
# Upload files
scp NanoJetApp-0.1.0.zip user@ahmedsam.com:/var/www/idmmac/downloads/
scp appcast.xml user@ahmedsam.com:/var/www/idmmac/
```

Ensure HTTPS is enabled on your server for security.

## Step 8: Test Updates

1. Build and install your app with Sparkle integrated
2. Set a lower version number temporarily to test updates
3. Go to **gear menu (⚙️) → Check for Updates…**
4. Sparkle should detect the update and offer to install it

## Automated Build Script

Create a script to automate the release process:

```bash
#!/bin/bash
# release-update.sh

VERSION="0.1.0"
BUILD="1"
PRIVATE_KEY="~/.sparkle_private_key"

# 1. Build app (assumes already archived)
echo "Creating ZIP..."
ditto -c -k --keepParent NanoJetApp.app "NanoJetApp-${VERSION}.zip"

# 2. Sign update
echo "Signing update..."
SIGNATURE=$(./Sparkle/bin/sign_update "NanoJetApp-${VERSION}.zip" -f "$PRIVATE_KEY")
echo "Signature: $SIGNATURE"

# 3. Get file size
SIZE=$(stat -f%z "NanoJetApp-${VERSION}.zip")
echo "Size: $SIZE bytes"

# 4. Generate appcast entry
cat << EOF

Add this to your appcast.xml:

<item>
    <title>Version ${VERSION}</title>
    <pubDate>$(date -R)</pubDate>
    <sparkle:version>${BUILD}</sparkle:version>
    <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    <enclosure 
        url="https://ahmedsam.com/idmmac/downloads/NanoJetApp-${VERSION}.zip"
        length="${SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}" />
</item>

EOF

echo "Done! Upload NanoJetApp-${VERSION}.zip and update appcast.xml"
```

## Update Frequency

The app checks for updates every 24 hours by default. You can change this in Info.plist:

```xml
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>  <!-- seconds (86400 = 24 hours) -->
```

## Delta Updates (Optional)

For smaller downloads, generate delta patches between versions:

```bash
./BinaryDelta create old.zip new.zip delta.patch
```

Add delta information to your appcast for users with the old version.

## Security Best Practices

1. ✅ **Always use HTTPS** for your appcast feed
2. ✅ **Keep private key secure** - never commit to git
3. ✅ **Sign all releases** with EdDSA signature
4. ✅ **Notarize your app** with Apple before distributing
5. ✅ **Use release notes** to inform users of changes

## User Experience

Users can check for updates in three ways:

1. **Automatic**: App checks every 24 hours in background
2. **Manual**: Gear menu (⚙️) → "Check for Updates…"
3. **About window**: "Check for Updates" button

When an update is available:
- Sparkle shows a dialog with release notes
- User can install immediately or skip
- App downloads, verifies signature, and updates
- Restart required for installation

## Troubleshooting

### Update Check Fails

- Verify `SUFeedURL` is accessible via HTTPS
- Check server logs for 404 errors
- Validate appcast.xml syntax

### Signature Verification Fails

- Ensure public key in Info.plist matches private key used for signing
- Re-generate signature if keys were regenerated
- Check that signature is correctly copied to appcast.xml

### App Won't Update

- Check that `sparkle:version` (build number) is higher than current
- Verify app is properly code-signed with Developer ID
- Ensure app is notarized and stapled

## Resources

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
- [Appcast Feed Specification](https://sparkle-project.org/documentation/publishing/)

## Support

For issues with Sparkle integration, contact ahmed@ahmedsam.com or check the project README.

