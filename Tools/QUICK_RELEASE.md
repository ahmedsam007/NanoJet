# 🚀 Quick Release Guide

## For Testing Locally

```bash
# 1. Start local server (if not running)
cd /Users/ahmed/Documents/NanoJet/Tools
python3 -m http.server 8000 &

# 2. Build and test
# (Build in Xcode, then test the update flow)
```

---

## For Releasing to Users

### 📦 Automated (Recommended)

```bash
cd /Users/ahmed/Documents/NanoJet

# Build, sign, and package in one command
./Tools/release.sh 0.2.0

# Follow the on-screen instructions
```

### ✍️ Manual Steps

```bash
# 1. Build (in Xcode)
# Product → Archive → Distribute App → Copy App

# 2. Sign
cd /Users/ahmed/Documents/NanoJet
./Tools/sign_update.sh ~/Desktop/YourApp.app 0.2.0

# 3. Copy the signature output and update appcast.xml

# 4. Upload to server
scp NanoJetApp-0.2.0.zip user@ahmedsam.com:/idmmac/downloads/
scp Tools/appcast.xml user@ahmedsam.com:/idmmac/appcast.xml
```

---

## 📋 Pre-Release Checklist

- [ ] Version number updated in Xcode/project.yml
- [ ] Info.plist points to production URL (not localhost)
- [ ] Release notes written in appcast.xml
- [ ] Tested locally with localhost server
- [ ] Built for Release (not Debug)
- [ ] Signed with EdDSA key
- [ ] Uploaded to server
- [ ] Verified appcast.xml is accessible
- [ ] Tested on clean Mac with old version

---

## 🔗 Important URLs

- **Production Appcast**: https://ahmedsam.com/idmmac/appcast.xml
- **Download Directory**: https://ahmedsam.com/idmmac/downloads/
- **Test Server**: http://localhost:8000/

---

## ⚡ Common Commands

```bash
# Build release
./Tools/release.sh 1.0.0

# Sign update
./Tools/sign_update.sh YourApp.app 1.0.0

# Check version in app
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  /Applications/NanoJetApp.app/Contents/Info.plist

# Validate XML
xmllint --noout Tools/appcast.xml

# Test appcast is accessible
curl -I https://ahmedsam.com/idmmac/appcast.xml
```

---

See **DEPLOYMENT_GUIDE.md** for detailed instructions.

