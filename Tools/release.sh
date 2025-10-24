#!/bin/bash

# NanoJet Release Script
# Automates building, signing, and preparing updates for deployment

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   NanoJet Release Builder & Signer     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo

# Check if version argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Version number required${NC}"
    echo "Usage: $0 <version> [build_number]"
    echo "Example: $0 0.2.0 2"
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="${2:-$(date +%Y%m%d%H%M)}"

echo -e "${BLUE}📦 Building NanoJet v${VERSION} (Build ${BUILD_NUMBER})${NC}"
echo

# Create output directory
OUTPUT_DIR="$HOME/Desktop/NanoJet-Release-${VERSION}"
mkdir -p "$OUTPUT_DIR"

echo -e "${YELLOW}⚙️  Step 1: Building archive...${NC}"

cd "$PROJECT_DIR"

# Build archive
xcodebuild archive \
    -scheme NanoJetApp \
    -archivePath "$OUTPUT_DIR/NanoJetApp.xcarchive" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    | tee "$OUTPUT_DIR/build.log" | grep -E "^(Build|Archive) "

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed! Check $OUTPUT_DIR/build.log${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Archive created successfully${NC}"
echo

echo -e "${YELLOW}⚙️  Step 2: Exporting app...${NC}"

# Export app
xcodebuild -exportArchive \
    -archivePath "$OUTPUT_DIR/NanoJetApp.xcarchive" \
    -exportPath "$OUTPUT_DIR" \
    -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
    | tee -a "$OUTPUT_DIR/build.log" | grep -E "^(Export|Processing)"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Automated export failed, trying manual copy...${NC}"
    cp -r "$OUTPUT_DIR/NanoJetApp.xcarchive/Products/Applications/NanoJetApp.app" "$OUTPUT_DIR/"
fi

echo -e "${GREEN}✅ App exported successfully${NC}"
echo

echo -e "${YELLOW}⚙️  Step 3: Re-signing embedded frameworks...${NC}"

# Re-sign frameworks to match app signature
"$SCRIPT_DIR/resign-frameworks.sh" "$OUTPUT_DIR/NanoJetApp.app"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Framework re-signing failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Frameworks re-signed successfully${NC}"
echo

echo -e "${YELLOW}⚙️  Step 4: Signing update package...${NC}"

# Sign the update
"$SCRIPT_DIR/sign_update.sh" "$OUTPUT_DIR/NanoJetApp.app" "$VERSION"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Signing failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Update signed successfully${NC}"
echo

# Move signed zip to output directory
if [ -f "$PROJECT_DIR/NanoJetApp-${VERSION}.zip" ]; then
    mv "$PROJECT_DIR/NanoJetApp-${VERSION}.zip" "$OUTPUT_DIR/"
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Release Complete! 🎉          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}📂 Output directory: ${OUTPUT_DIR}${NC}"
echo
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Update Tools/appcast.xml with the signature shown above"
echo "2. Upload NanoJetApp-${VERSION}.zip to your server:"
echo -e "   ${BLUE}scp \"$OUTPUT_DIR/NanoJetApp-${VERSION}.zip\" user@ahmedsam.com:/idmmac/downloads/${NC}"
echo "3. Upload the updated appcast.xml:"
echo -e "   ${BLUE}scp Tools/appcast.xml user@ahmedsam.com:/idmmac/appcast.xml${NC}"
echo "4. Test the update on a clean Mac with the old version installed"
echo
echo -e "${GREEN}✨ Happy releasing!${NC}"

