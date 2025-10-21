#!/bin/bash

# IDMMac - Prepare GitHub Release
# Everything you need for GitHub-hosted updates

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   IDMMac - GitHub Release Prep        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo

if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Version number required${NC}"
    echo "Usage: $0 <version>"
    echo "Example: $0 0.1.0"
    exit 1
fi

VERSION="$1"

echo -e "${CYAN}📝 Preparing version ${VERSION} for GitHub${NC}"
echo

# Step 1: Export the app
echo -e "${YELLOW}⚙️  Step 1: Building and signing app...${NC}"
"$SCRIPT_DIR/export-for-sharing.sh" "$VERSION"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Export failed!${NC}"
    exit 1
fi

echo

# Step 2: Sign for Sparkle
echo -e "${YELLOW}⚙️  Step 2: Generating Sparkle signature...${NC}"

ZIP_FILE="$HOME/Documents/IDMMac/builds/IDMMac-v${VERSION}/IDMMacApp-v${VERSION}.zip"

if [ ! -f "$ZIP_FILE" ]; then
    echo -e "${RED}❌ Zip file not found: $ZIP_FILE${NC}"
    exit 1
fi

SIGN_UPDATE="$PROJECT_DIR/bin/sign_update"

if [ ! -f "$SIGN_UPDATE" ]; then
    echo -e "${RED}❌ sign_update tool not found${NC}"
    exit 1
fi

# Generate signature
SIGNATURE_OUTPUT=$("$SIGN_UPDATE" "$ZIP_FILE" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to sign update${NC}"
    echo "$SIGNATURE_OUTPUT"
    exit 1
fi

ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')

if [ -z "$ED_SIGNATURE" ]; then
    echo -e "${RED}❌ Failed to extract signature${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Signature: ${ED_SIGNATURE:0:40}...${NC}"
echo

# Get file info
FILE_SIZE=$(stat -f%z "$ZIP_FILE" 2>/dev/null || stat -c%s "$ZIP_FILE" 2>/dev/null)
FILE_SIZE_HR=$(du -h "$ZIP_FILE" | cut -f1)

OUTPUT_DIR="$HOME/Documents/IDMMac/builds/IDMMac-v${VERSION}"

# Generate appcast entry
echo -e "${YELLOW}⚙️  Step 3: Generating deployment files...${NC}"

cat > "$OUTPUT_DIR/appcast-entry.xml" << EOF
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[
                <h3>What's New in IDMMac ${VERSION}</h3>
                <ul>
                    <li>Improvements and bug fixes</li>
                </ul>
            ]]></description>
            <pubDate>$(date -R)</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url="https://github.com/YOUR_USERNAME/idmmac-releases/releases/download/v${VERSION}/IDMMacApp-v${VERSION}.zip"
                length="${FILE_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
EOF

# Generate complete appcast template
cat > "$OUTPUT_DIR/appcast-template.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>IDMMac Updates</title>
        <link>https://YOUR_USERNAME.github.io/idmmac-releases/appcast.xml</link>
        <description>Updates for IDMMac - Fast macOS Download Manager</description>
        <language>en</language>
        
        <!-- Add new versions here at the top -->
        
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[
                <h3>What's New in IDMMac ${VERSION}</h3>
                <ul>
                    <li>Improvements and bug fixes</li>
                </ul>
            ]]></description>
            <pubDate>$(date -R)</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url="https://github.com/YOUR_USERNAME/idmmac-releases/releases/download/v${VERSION}/IDMMacApp-v${VERSION}.zip"
                length="${FILE_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
        
    </channel>
</rss>
EOF

# Generate GitHub instructions
cat > "$OUTPUT_DIR/GITHUB_INSTRUCTIONS.txt" << EOF
╔══════════════════════════════════════════════════════════════╗
║       IDMMac v${VERSION} - GitHub Deployment Guide               ║
╚══════════════════════════════════════════════════════════════╝

📦 FILES READY:
   ✓ IDMMacApp-v${VERSION}.zip (${FILE_SIZE_HR})
   ✓ Sparkle Signature: ${ED_SIGNATURE:0:40}...

╔══════════════════════════════════════════════════════════════╗
║                    FIRST TIME SETUP                          ║
╚══════════════════════════════════════════════════════════════╝

If this is your FIRST release, follow these steps:

┌──────────────────────────────────────────────────────────────┐
│ 1. Create GitHub Repository                                  │
└──────────────────────────────────────────────────────────────┘

1. Go to: https://github.com/new

2. Repository name: idmmac-releases

3. Public ✓ (recommended for unlimited bandwidth)

4. Initialize: Add a README ✓

5. Click "Create repository"

┌──────────────────────────────────────────────────────────────┐
│ 2. Enable GitHub Pages                                       │
└──────────────────────────────────────────────────────────────┘

1. Go to repo → Settings → Pages

2. Source: Deploy from a branch

3. Branch: main / root

4. Click Save

5. Your URL will be:
   https://YOUR_USERNAME.github.io/idmmac-releases/

┌──────────────────────────────────────────────────────────────┐
│ 3. Add appcast.xml to Repository                             │
└──────────────────────────────────────────────────────────────┘

1. Clone your repo:
   
   cd ~/projects
   git clone https://github.com/YOUR_USERNAME/idmmac-releases.git
   cd idmmac-releases

2. Create appcast.xml in the root:
   
   # Copy content from: appcast-template.xml
   # Save as: appcast.xml

3. Edit appcast.xml:
   
   Replace: YOUR_USERNAME
   With: Your actual GitHub username

4. Commit and push:
   
   git add appcast.xml
   git commit -m "Add appcast for v${VERSION}"
   git push

5. Wait 2-3 minutes for GitHub Pages to build

6. Verify: https://YOUR_USERNAME.github.io/idmmac-releases/appcast.xml

┌──────────────────────────────────────────────────────────────┐
│ 4. Update Info.plist in Your App                             │
└──────────────────────────────────────────────────────────────┘

1. Open: IDMMacApp/Resources/Info.plist

2. Find: <key>SUFeedURL</key>

3. Change the URL to:
   <string>https://YOUR_USERNAME.github.io/idmmac-releases/appcast.xml</string>

4. Save and rebuild your app with the new URL

╔══════════════════════════════════════════════════════════════╗
║                   CREATE THIS RELEASE                        ║
╚══════════════════════════════════════════════════════════════╝

Now upload v${VERSION}:

┌──────────────────────────────────────────────────────────────┐
│ 5. Create GitHub Release                                     │
└──────────────────────────────────────────────────────────────┘

1. Go to: https://github.com/YOUR_USERNAME/idmmac-releases/releases

2. Click "Create a new release"

3. Fill in:
   
   Tag version: v${VERSION}
   Release title: IDMMac v${VERSION}
   Description:
   
   ## What's New
   - Feature 1
   - Feature 2
   - Bug fixes

4. Upload file:
   
   Drag and drop: IDMMacApp-v${VERSION}.zip

5. Click "Publish release"

✅ DONE! The release is now available at:
   https://github.com/YOUR_USERNAME/idmmac-releases/releases/download/v${VERSION}/IDMMacApp-v${VERSION}.zip

╔══════════════════════════════════════════════════════════════╗
║                      TESTING                                 ║
╚══════════════════════════════════════════════════════════════╝

Test the setup:

1. Build your app with the new Info.plist URL

2. Install and run the app

3. Menu: IDMMac → Check for Updates...

4. Should say: "You're up to date!" (if this is the latest)

To test actual updates:
1. Keep v${VERSION} installed
2. Release v0.2.0 following the same process
3. Add v0.2.0 entry to appcast.xml (at the TOP)
4. Open v${VERSION} → Check for Updates
5. Should show update available!

╔══════════════════════════════════════════════════════════════╗
║                   FUTURE RELEASES                            ║
╚══════════════════════════════════════════════════════════════╝

For v0.2.0 and beyond:

1. Update version in Xcode

2. Run this script again:
   ./Tools/prepare-github-release.sh 0.2.0

3. Edit appcast.xml - add new entry at the TOP:
   
   cd ~/projects/idmmac-releases
   # Edit appcast.xml
   # Add new <item> above the old one
   git add appcast.xml
   git commit -m "Release v0.2.0"
   git push

4. Create new GitHub Release with the new zip

5. Done! Users get automatic updates

╔══════════════════════════════════════════════════════════════╗
║                    KEY INFORMATION                           ║
╚══════════════════════════════════════════════════════════════╝

Version: ${VERSION}
Zip File: IDMMacApp-v${VERSION}.zip
File Size: ${FILE_SIZE} bytes (${FILE_SIZE_HR})
Signature: ${ED_SIGNATURE}

Important:
• Do NOT modify the zip after signing
• Always add new versions at the TOP of appcast.xml
• Keep the signature with the correct zip file
• GitHub Pages takes 2-3 minutes to update

╔══════════════════════════════════════════════════════════════╗
║                    QUICK REFERENCE                           ║
╚══════════════════════════════════════════════════════════════╝

Your URLs (replace YOUR_USERNAME):
• Appcast: https://YOUR_USERNAME.github.io/idmmac-releases/appcast.xml
• Download: https://github.com/YOUR_USERNAME/idmmac-releases/releases/download/v${VERSION}/IDMMacApp-v${VERSION}.zip

Files in this folder:
• IDMMacApp-v${VERSION}.zip - Upload to GitHub Release
• appcast-entry.xml - Copy to your appcast.xml
• appcast-template.xml - Complete appcast example
• README.txt - User installation guide
• GITHUB_INSTRUCTIONS.txt - This file

Need help? See Tools/GITHUB_SETUP.md

EOF

echo -e "${GREEN}✅ All files generated${NC}"
echo

# Summary
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Ready for GitHub! 🚀            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}📂 Location:${NC} $OUTPUT_DIR"
echo
echo -e "${GREEN}📦 Files:${NC}"
echo "   • IDMMacApp-v${VERSION}.zip (${FILE_SIZE_HR})"
echo "   • appcast-entry.xml"
echo "   • appcast-template.xml"
echo "   • GITHUB_INSTRUCTIONS.txt"
echo "   • README.txt"
echo
echo -e "${CYAN}📖 Next Steps:${NC}"
echo "   1. Read: GITHUB_INSTRUCTIONS.txt"
echo "   2. Create GitHub repo (if first time)"
echo "   3. Enable GitHub Pages"
echo "   4. Upload appcast.xml to repo"
echo "   5. Create GitHub Release with the zip"
echo "   6. Test!"
echo
echo -e "${YELLOW}💡 Tip:${NC} First time? Follow GITHUB_INSTRUCTIONS.txt step-by-step"
echo

# Open folder
open "$OUTPUT_DIR"

