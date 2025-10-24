# How to Send Updates to Existing Users

This guide explains how to send automatic updates to users who already have NanoJet installed.

## Overview

NanoJet uses **Sparkle 2** for automatic updates. When you release a new version:
1. Users with the old version will be automatically notified
2. They can download and install the update with one click
3. The app updates itself without needing to re-download manually

## Prerequisites

✅ You already have:
- Sparkle framework integrated in your app
- Public/private key pair for signing updates (in `bin/`)
- Appcast XML feed setup (`Tools/appcast.xml`)

## Update Workflow

### Step 1: Update Version Number in Xcode

1. Open `NanoJet.xcodeproj` in Xcode
2. Select the **project** (not target) in the navigator
3. Go to the **Build Settings** tab
4. Search for `MARKETING_VERSION`
5. Change it from `0.1.0` to your new version (e.g., `0.2.0`)
6. Save the project (Cmd+S)

### Step 2: Create Update Package

Run the automated script:

```bash
cd /Users/ahmed/Documents/NanoJet
./Tools/create-update.sh 0.2.0
```

This will:
- ✅ Build the new version
- ✅ Re-sign all frameworks
- ✅ Create a signed update zip
- ✅ Generate the Sparkle signature
- ✅ Create an appcast entry for you
- ✅ Open the output folder

### Step 3: Upload Files to Your Server

You need to upload two files:

**A. Upload the app zip:**
```bash
scp ~/Desktop/NanoJet-Update-v0.2.0/NanoJetApp-0.2.0.zip user@ahmedsam.com:/var/www/idmmac/downloads/
```

**B. Upload the appcast.xml** (after editing it in step 4):
```bash
scp Tools/appcast.xml user@ahmedsam.com:/var/www/idmmac/
```

### Step 4: Update appcast.xml

1. Open `Tools/appcast.xml`
2. Open the generated `appcast-entry.xml` from the output folder
3. Copy the `<item>` block from `appcast-entry.xml`
4. **Paste it at the TOP** of the items list in `appcast.xml` (after line 13)
5. The most recent version should always be first
6. Save the file

**Example appcast.xml structure:**
```xml
<channel>
    <title>NanoJet Updates</title>
    ...
    
    <!-- NEWEST VERSION FIRST -->
    <item>
        <title>Version 0.2.0</title>
        ...
    </item>
    
    <item>
        <title>Version 0.1.0</title>
        ...
    </item>
</channel>
```

### Step 5: Test Before Deploying

**IMPORTANT:** Test on a machine with the old version first!

1. Install the old version (0.1.0) on a test Mac
2. Upload your new appcast.xml to the server
3. Open the old version - it should show an update notification
4. Click "Install Update" and verify it works
5. If successful, you're ready to go live!

## 🚀 That's It!

Once you upload the files:
- ✅ Users will be notified about the update next time they open the app
- ✅ They can install it with one click
- ✅ The update is cryptographically signed and verified

## Alternative: Manual Process

If you prefer to do it manually without the script:

```bash
# 1. Build
xcodebuild -scheme NanoJetApp -configuration Release build

# 2. Find the built app
cd ~/Library/Developer/Xcode/DerivedData/NanoJet-*/Build/Products/Release/

# 3. Re-sign frameworks
/path/to/resign-frameworks.sh NanoJetApp.app

# 4. Create zip
ditto -c -k --keepParent NanoJetApp.app NanoJetApp-0.2.0.zip

# 5. Sign with Sparkle
/path/to/bin/sign_update NanoJetApp-0.2.0.zip

# 6. Copy signature and add to appcast.xml
```

## Release Notes (Optional)

You can create HTML release notes for users:

1. Create a file: `releases/0.2.0.html` on your server
2. Add what's new in this version
3. Make sure the URL in appcast.xml points to it:
   ```xml
   <sparkle:releaseNotesLink>https://ahmedsam.com/idmmac/releases/0.2.0.html</sparkle:releaseNotesLink>
   ```

Or remove the `releaseNotesLink` and use inline `<description>` instead.

## Troubleshooting

### "The update is improperly signed"
- Make sure you're using the same private key that matches the public key in Info.plist
- Re-run `sign_update` to get the correct signature

### Users don't see the update
- Check that `appcast.xml` is accessible at the URL in Info.plist
- Verify the version numbers are correct (new version > old version)
- Make sure `sparkle:version` and `sparkle:shortVersionString` are set

### Update downloads but won't install
- Verify the zip file is properly created with `ditto -c -k --keepParent`
- Check that frameworks are re-signed
- Test on a fresh Mac

## Quick Reference

| Action | Command |
|--------|---------|
| **Create Update** | `./Tools/create-update.sh 0.2.0` |
| **Sign Manually** | `./bin/sign_update app.zip` |
| **Test Appcast** | Open in browser: `https://ahmedsam.com/idmmac/appcast.xml` |
| **Upload Files** | `scp file user@server:/path/` |

## Server Directory Structure

```
/var/www/idmmac/
├── appcast.xml                    # Update feed
├── downloads/
│   ├── NanoJetApp-0.1.0.zip       # Old version
│   └── NanoJetApp-0.2.0.zip       # New version
└── releases/                      # Optional release notes
    ├── 0.1.0.html
    └── 0.2.0.html
```

## Need Help?

- Check `Tools/SPARKLE_CONFIGURED.md` for Sparkle setup
- See `Tools/UPDATE_WORKFLOW.md` for detailed workflow
- Visit: https://sparkle-project.org/documentation/

---

Happy updating! 🚀

