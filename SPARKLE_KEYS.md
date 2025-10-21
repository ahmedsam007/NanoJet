# Sparkle EdDSA Keys - Configured ✅

Your Sparkle update signing keys have been generated and configured!

## 🔑 Keys Information

### Public Key (Already Added to Info.plist)
```
yV8yqP+FQ12R82ya1T/khpSwar0R9JadjTK9ITUbCkY=
```

This key is now in your `IDMMacApp/Resources/Info.plist` file and will be used to verify update signatures.

### Private Key (Stored in macOS Keychain)

Your private key is securely stored in your macOS Keychain with the name:
- **Keychain Item**: "Sparkle Signing Private Key"
- **Service**: com.github.sparkle-project.Sparkle

You can view it in **Keychain Access.app** → **login** keychain.

**⚠️ IMPORTANT: Keep this private key secure!**
- Never commit it to Git
- Never share it publicly
- Back it up securely (1Password, encrypted backup, etc.)

## 📦 How to Sign Updates

### Quick Method (Using Helper Script)

1. **Export your built app** from Xcode:
   - Product → Archive → Distribute App → Developer ID
   - Place `IDMMacApp.app` in the project root

2. **Run the signing script**:
   ```bash
   cd /Users/ahmed/Documents/IDMMac
   ./Tools/sign_update.sh 0.1.0
   ```

3. **Follow the output** - it will:
   - Create a ZIP of your app
   - Sign it with your private key from Keychain
   - Generate the appcast XML entry for you
   - Show upload instructions

### Manual Method

```bash
# Create ZIP
ditto -c -k --keepParent IDMMacApp.app IDMMacApp-0.1.0.zip

# Sign (private key will be read from Keychain automatically)
./bin/sign_update IDMMacApp-0.1.0.zip

# Output will be your EdDSA signature
```

## 🔄 Exporting/Backing Up Private Key

To export your private key from Keychain (for backup or use on another machine):

1. Open **Keychain Access** app
2. Search for "Sparkle Signing"
3. Right-click → Export "Sparkle Signing Private Key"
4. Save as `.p12` file with a strong password
5. Store in secure location (1Password, encrypted drive, etc.)

### To Import on Another Machine

```bash
# Import the private key to Keychain
security import SparkleSigningKey.p12 -k ~/Library/Keychains/login.keychain-db
```

Or double-click the `.p12` file and enter the password.

## 🌐 Appcast Feed Setup

Your appcast feed should be hosted at:
```
https://ahmedsam.com/idmmac/appcast.xml
```

See `SPARKLE_SETUP.md` for complete appcast XML format and examples.

## ✅ What's Configured

- ✅ EdDSA key pair generated
- ✅ Public key added to Info.plist
- ✅ Private key stored in Keychain
- ✅ Update feed URL configured
- ✅ Automatic checks enabled (every 24 hours)
- ✅ Helper script created at `Tools/sign_update.sh`

## 🧪 Testing Updates

To test the update mechanism:

1. **Temporarily lower your app's version** in `project.yml`:
   ```yaml
   MARKETING_VERSION: 0.0.1  # Lower than your test update
   ```

2. **Rebuild and run the app**

3. **Create and sign a test update** with version 0.1.0

4. **Set up your appcast.xml** with the test update

5. **Click "Check for Updates"** in your app

Sparkle should detect and offer to install the update!

## 🔒 Security Notes

- The private key never leaves your Mac (stored in Keychain)
- Sparkle will automatically use it when signing
- Updates are verified on users' machines using the public key
- Users cannot install tampered updates without your signature

## 📚 Additional Resources

- Full setup guide: `SPARKLE_SETUP.md`
- Sparkle documentation: https://sparkle-project.org/documentation/
- Sign updates script: `Tools/sign_update.sh`

---

**Generated on:** October 20, 2025  
**Sparkle Version:** 2.6.4  
**Public Key:** yV8yqP+FQ12R82ya1T/khpSwar0R9JadjTK9ITUbCkY=

