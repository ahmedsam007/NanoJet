# NanoJet Updates with GitHub Only

## 100% Free GitHub Solution

Everything hosted on GitHub - no Vercel needed!

---

## Option 1: GitHub Releases + GitHub Pages (Best!)

### Step 1: Create Repository

```bash
# Create a new repo on GitHub
# Name: idmmac-releases
# Public or Private: Public recommended for free bandwidth
```

### Step 2: Enable GitHub Pages

1. Go to your repo: `https://github.com/YOUR_USERNAME/idmmac-releases`
2. Settings → Pages
3. Source: Deploy from a branch
4. Branch: `main` / `root`
5. Save

Your site will be: `https://YOUR_USERNAME.github.io/idmmac-releases/`

### Step 3: Create Repository Structure

```bash
cd ~/projects
git clone https://github.com/YOUR_USERNAME/idmmac-releases.git
cd idmmac-releases

# Create structure
mkdir downloads
touch appcast.xml
```

### Step 4: Create appcast.xml

Create `appcast.xml` in the root:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>NanoJet Updates</title>
        <link>https://YOUR_USERNAME.github.io/idmmac-releases/appcast.xml</link>
        <description>Updates for NanoJet - Fast macOS Download Manager</description>
        <language>en</language>
        
        <item>
            <title>Version 0.1.0</title>
            <description><![CDATA[
                <h3>NanoJet 0.1.0</h3>
                <ul>
                    <li>Initial release</li>
                    <li>Fast multi-connection downloads</li>
                    <li>YouTube support</li>
                    <li>Browser integration</li>
                </ul>
            ]]></description>
            <pubDate>Mon, 21 Oct 2025 10:00:00 +0000</pubDate>
            <sparkle:version>0.1.0</sparkle:version>
            <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url="https://github.com/YOUR_USERNAME/idmmac-releases/releases/download/v0.1.0/NanoJetApp-v0.1.0.zip"
                length="FILE_SIZE_HERE"
                type="application/octet-stream"
                sparkle:edSignature="SIGNATURE_HERE" />
        </item>
        
    </channel>
</rss>
```

### Step 5: Commit and Push

```bash
git add appcast.xml
git commit -m "Add appcast"
git push
```

### Step 6: Create Release with Zip

1. Go to Releases tab
2. Create new release
3. Tag: `v0.1.0`
4. Upload: `NanoJetApp-v0.1.0.zip`
5. Publish

### Step 7: Update Info.plist

Change your app's update URL:

```xml
<key>SUFeedURL</key>
<string>https://YOUR_USERNAME.github.io/idmmac-releases/appcast.xml</string>
```

**That's it!** Everything is on GitHub.

---

## Option 2: GitHub Raw URL (Simpler but less pretty)

You can use GitHub's raw file URL for appcast.xml:

```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/YOUR_USERNAME/idmmac-releases/main/appcast.xml</string>
```

Same setup as Option 1, but skip enabling GitHub Pages.

**Pros:**
- ✅ No GitHub Pages setup needed
- ✅ Instant updates (no Pages rebuild delay)

**Cons:**
- ⚠️ Less professional URL
- ⚠️ No custom domain support

---

## Complete Workflow

### Initial Release (v0.1.0)

```bash
# 1. Build and sign
cd /Users/ahmed/Documents/NanoJet
./Tools/export-for-sharing.sh 0.1.0

# 2. Sign for Sparkle
./bin/sign_update ~/Desktop/NanoJet-v0.1.0/NanoJetApp-v0.1.0.zip

# Copy the signature from output

# 3. Get file size
ls -l ~/Desktop/NanoJet-v0.1.0/NanoJetApp-v0.1.0.zip | awk '{print $5}'

# 4. Update appcast.xml with signature and file size

# 5. Commit and push
cd ~/projects/idmmac-releases
git add appcast.xml
git commit -m "Release v0.1.0"
git push

# 6. Create GitHub Release
# Upload NanoJetApp-v0.1.0.zip

# 7. Update Info.plist with GitHub Pages URL

# 8. Rebuild your app with new Info.plist
```

### Future Updates (v0.2.0)

```bash
# 1. Update version in Xcode (0.1.0 → 0.2.0)

# 2. Build new version
./Tools/export-for-sharing.sh 0.2.0

# 3. Sign it
./bin/sign_update ~/Desktop/NanoJet-v0.2.0/NanoJetApp-v0.2.0.zip

# 4. Edit appcast.xml - add new entry at the TOP
cd ~/projects/idmmac-releases
# Edit appcast.xml

# 5. Push appcast update
git add appcast.xml
git commit -m "Release v0.2.0"
git push

# 6. Create GitHub Release v0.2.0
# Upload NanoJetApp-v0.2.0.zip

# Done! Users get automatic updates
```

---

## Testing

### Test v0.1.0

1. Build with correct GitHub Pages URL in Info.plist
2. Install the app
3. Menu → Check for Updates
4. Should say "You're up to date"

### Test Update (v0.1.0 → v0.2.0)

1. Keep v0.1.0 installed
2. Release v0.2.0 following steps above
3. Open v0.1.0 → Check for Updates
4. Should show update available
5. Click Install → Should update successfully

---

## Advantages of GitHub-Only Setup

✅ **Completely FREE**
- No costs at all
- Unlimited bandwidth (for public repos)
- No credit card needed

✅ **Simple**
- One place for everything
- No multiple services to manage
- Easy version tracking

✅ **Reliable**
- GitHub's global CDN
- 99.9% uptime
- Fast downloads worldwide

✅ **Built-in Version Control**
- Git history for appcast.xml
- Tagged releases
- Easy rollbacks

---

## Repository Structure

```
idmmac-releases/
├── README.md
├── appcast.xml                    ← App checks this
├── releases/                      ← Optional: Release notes
│   ├── 0.1.0.html
│   └── 0.2.0.html
└── Downloads via GitHub Releases:
    ├── v0.1.0/NanoJetApp-v0.1.0.zip
    ├── v0.2.0/NanoJetApp-v0.2.0.zip
    └── ...
```

---

## Custom Domain (Optional)

Want to use `updates.ahmedsam.com` instead of GitHub URLs?

### With GitHub Pages:

1. Add `CNAME` file to your repo:
   ```
   updates.ahmedsam.com
   ```

2. Add DNS record (in Vercel/Cloudflare):
   ```
   CNAME updates.ahmedsam.com YOUR_USERNAME.github.io
   ```

3. Update Info.plist:
   ```xml
   <string>https://updates.ahmedsam.com/appcast.xml</string>
   ```

**Now everything looks professional!**

---

## Comparison

| Feature | GitHub Only | Vercel + GitHub |
|---------|-------------|-----------------|
| **Cost** | FREE | FREE |
| **Setup** | Simple | Medium |
| **Update Speed** | Fast | Fast |
| **Custom Domain** | Yes (via CNAME) | Yes (via Vercel) |
| **Bandwidth** | Unlimited | Unlimited |
| **Professional URLs** | ✓ | ✓ |

**Both are great!** Use what's simpler for you.

---

## Quick Start

```bash
# 1. Create GitHub repo: idmmac-releases
# 2. Enable GitHub Pages
# 3. Clone and create appcast.xml
# 4. Build app with GitHub Pages URL
# 5. Create release with zip
# 6. Test!
```

---

## Troubleshooting

### "appcast.xml not found (404)"

- Wait 2-3 minutes for GitHub Pages to build
- Check Pages is enabled in Settings
- Verify file is in root of repo
- Check URL matches exactly

### "The update is improperly signed"

- Make sure you signed with `./bin/sign_update`
- Copy the FULL signature (including the long string)
- Don't modify the zip after signing

### GitHub Pages not updating

- GitHub Pages can take 1-2 minutes to rebuild
- Clear browser cache
- Use incognito/private window

### Using private repo?

- GitHub Releases work for private repos
- GitHub Pages requires public repo (or GitHub Pro)
- Consider: Make releases repo public, keep main code private

---

## Need Help?

See also:
- `Tools/HOW_TO_SEND_UPDATES.md` - General update workflow
- `Tools/export-for-sharing.sh` - Build script
- GitHub Pages docs: https://pages.github.com


