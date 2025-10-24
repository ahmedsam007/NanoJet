#!/bin/bash

# NanoJet - Create Update for Existing Users
# This script creates a Sparkle-signed update for auto-update

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   NanoJet - Create Update Package      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo

# Check if version argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Version number required${NC}"
    echo "Usage: $0 <new_version>"
    echo "Example: $0 0.2.0"
    echo ""
    echo "This will:"
    echo "  1. Build the new version"
    echo "  2. Sign it for Sparkle updates"
    echo "  3. Generate update signature"
    echo "  4. Update appcast.xml"
    exit 1
fi

NEW_VERSION="$1"

echo -e "${CYAN}📝 Creating update for version ${NEW_VERSION}${NC}"
echo

# Step 1: Update version in project
echo -e "${YELLOW}⚙️  Step 1: Updating version number...${NC}"
echo -e "${CYAN}   Please update MARKETING_VERSION to ${NEW_VERSION} in Xcode:${NC}"
echo "   1. Open NanoJet.xcodeproj in Xcode"
echo "   2. Select the project in the navigator"
echo "   3. Under 'Identity' section, change 'Version' to ${NEW_VERSION}"
echo "   4. Save the project"
echo ""
read -p "Press Enter when you've updated the version in Xcode..."

# Step 2: Build the app
echo ""
echo -e "${YELLOW}⚙️  Step 2: Building release version...${NC}"

OUTPUT_DIR="$HOME/Desktop/NanoJet-Update-v${NEW_VERSION}"
mkdir -p "$OUTPUT_DIR"

cd "$PROJECT_DIR"

xcodebuild -scheme NanoJetApp \
    -configuration Release \
    -derivedDataPath "$OUTPUT_DIR/DerivedData" \
    build \
    | grep -E "^(Build|▸) " || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build succeeded${NC}"
echo

# Find the built app
BUILT_APP="$OUTPUT_DIR/DerivedData/Build/Products/Release/NanoJetApp.app"

if [ ! -d "$BUILT_APP" ]; then
    echo -e "${RED}❌ Built app not found at: $BUILT_APP${NC}"
    exit 1
fi

# Copy to output directory
cp -r "$BUILT_APP" "$OUTPUT_DIR/"

# Step 3: Re-sign frameworks
echo -e "${YELLOW}⚙️  Step 3: Re-signing frameworks...${NC}"
"$SCRIPT_DIR/resign-frameworks.sh" "$OUTPUT_DIR/NanoJetApp.app"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Re-signing failed!${NC}"
    exit 1
fi

echo

# Step 4: Create and sign zip for Sparkle
echo -e "${YELLOW}⚙️  Step 4: Creating update package...${NC}"

cd "$OUTPUT_DIR"
ZIP_NAME="NanoJetApp-${NEW_VERSION}.zip"

# Create zip
ditto -c -k --keepParent "NanoJetApp.app" "$ZIP_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create zip file${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Zip created: $ZIP_NAME${NC}"
echo

# Step 5: Sign with Sparkle
echo -e "${YELLOW}⚙️  Step 5: Signing update for Sparkle...${NC}"

SIGN_UPDATE="$PROJECT_DIR/bin/sign_update"

if [ ! -f "$SIGN_UPDATE" ]; then
    echo -e "${RED}❌ sign_update tool not found at: $SIGN_UPDATE${NC}"
    echo "Make sure Sparkle's signing tool is in the bin/ directory"
    exit 1
fi

# Generate signature
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_NAME" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to sign update${NC}"
    echo "$SIGNATURE"
    exit 1
fi

# Extract signature from output
ED_SIGNATURE=$(echo "$SIGNATURE" | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')

if [ -z "$ED_SIGNATURE" ]; then
    echo -e "${RED}❌ Failed to extract signature${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Update signed${NC}"
echo

# Get file size
ZIP_SIZE=$(stat -f%z "$ZIP_NAME")
ZIP_SIZE_HR=$(du -h "$ZIP_NAME" | cut -f1)

# Clean up build artifacts
rm -rf "DerivedData"

# Step 6: Generate appcast entry
echo -e "${YELLOW}⚙️  Step 6: Generating appcast entry...${NC}"

APPCAST_ENTRY_FILE="$OUTPUT_DIR/appcast-entry.xml"

cat > "$APPCAST_ENTRY_FILE" << EOF
        <item>
            <title>Version ${NEW_VERSION}</title>
            <sparkle:releaseNotesLink>https://ahmedsam.com/idmmac/releases/${NEW_VERSION}.html</sparkle:releaseNotesLink>
            <pubDate>$(date -R)</pubDate>
            <enclosure 
                url="https://ahmedsam.com/idmmac/downloads/NanoJetApp-${NEW_VERSION}.zip"
                sparkle:version="${NEW_VERSION}"
                sparkle:shortVersionString="${NEW_VERSION}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${ZIP_SIZE}"
                type="application/octet-stream"
            />
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        </item>
EOF

echo -e "${GREEN}✅ Appcast entry generated${NC}"
echo

# Clean up DerivedData
rm -rf DerivedData

# Display summary
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Update Package Ready! 🎉        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}📂 Output directory:${NC} $OUTPUT_DIR"
echo -e "${GREEN}📦 Update file:${NC} $ZIP_NAME ($ZIP_SIZE_HR)"
echo -e "${GREEN}🔐 Signature:${NC} ${ED_SIGNATURE:0:40}..."
echo
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          DEPLOYMENT STEPS              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}1. Upload the update file to your server:${NC}"
echo "   scp \"$ZIP_NAME\" user@ahmedsam.com:/var/www/idmmac/downloads/"
echo
echo -e "${YELLOW}2. Create release notes (optional):${NC}"
echo "   Create a file: releases/${NEW_VERSION}.html"
echo "   Or remove the releaseNotesLink from appcast.xml"
echo
echo -e "${YELLOW}3. Update your appcast.xml:${NC}"
echo "   Copy the content from: appcast-entry.xml"
echo "   Add it as the FIRST item in Tools/appcast.xml"
echo
echo -e "${YELLOW}4. Upload the updated appcast.xml:${NC}"
echo "   scp Tools/appcast.xml user@ahmedsam.com:/var/www/idmmac/"
echo
echo -e "${CYAN}📄 Appcast Entry Preview:${NC}"
echo -e "${BLUE}─────────────────────────────────────────${NC}"
cat "$APPCAST_ENTRY_FILE"
echo -e "${BLUE}─────────────────────────────────────────${NC}"
echo
echo -e "${GREEN}✨ All users with auto-updates enabled will receive the update automatically!${NC}"
echo
echo -e "${CYAN}💡 Tip:${NC} Test the update on a machine with the old version first"
echo

# Open output directory
open "$OUTPUT_DIR"

