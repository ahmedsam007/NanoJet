#!/bin/bash

# IDMMac - Export for Sharing
# Creates a properly signed, shareable version of the app

set -e

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
echo -e "${BLUE}║   IDMMac - Export for Sharing          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo

# Get version from command line or use default
VERSION="${1:-0.1.0}"

echo -e "${BLUE}📦 Version: ${VERSION}${NC}"
echo

# Create output directory in Documents/IDMMac
OUTPUT_DIR="$HOME/Documents/IDMMac/builds/IDMMac-v${VERSION}"
mkdir -p "$OUTPUT_DIR"

echo -e "${YELLOW}⚙️  Step 1: Building app...${NC}"

cd "$PROJECT_DIR"

# Build the app
xcodebuild -scheme IDMMacApp \
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
BUILT_APP="$OUTPUT_DIR/DerivedData/Build/Products/Release/IDMMacApp.app"

if [ ! -d "$BUILT_APP" ]; then
    echo -e "${RED}❌ Built app not found at: $BUILT_APP${NC}"
    exit 1
fi

# Copy to output directory
echo -e "${YELLOW}⚙️  Step 2: Copying app to Desktop...${NC}"
cp -r "$BUILT_APP" "$OUTPUT_DIR/"

# Copy README for users
if [ -f "$SCRIPT_DIR/README_FOR_USERS.md" ]; then
    cp "$SCRIPT_DIR/README_FOR_USERS.md" "$OUTPUT_DIR/README.txt"
fi

echo -e "${GREEN}✅ App copied${NC}"
echo

# Re-sign frameworks
echo -e "${YELLOW}⚙️  Step 3: Re-signing frameworks...${NC}"
"$SCRIPT_DIR/resign-frameworks.sh" "$OUTPUT_DIR/IDMMacApp.app"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Re-signing failed!${NC}"
    exit 1
fi

echo

# Create zip file
echo -e "${YELLOW}⚙️  Step 4: Creating zip file...${NC}"

cd "$OUTPUT_DIR"
ZIP_NAME="IDMMacApp-v${VERSION}.zip"
ditto -c -k --keepParent "IDMMacApp.app" "$ZIP_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create zip file${NC}"
    exit 1
fi

# Clean up build artifacts
rm -rf "DerivedData"

echo -e "${GREEN}✅ Zip file created${NC}"
echo

# Get file size
ZIP_SIZE=$(du -h "$OUTPUT_DIR/$ZIP_NAME" | cut -f1)

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Export Complete! 🎉           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}📂 Output directory:${NC}"
echo -e "   ${OUTPUT_DIR}"
echo
echo -e "${GREEN}📦 Shareable file:${NC}"
echo -e "   ${ZIP_NAME} (${ZIP_SIZE})"
echo
echo -e "${YELLOW}📝 To share with friends:${NC}"
echo "   1. Send them the zip file: $ZIP_NAME"
echo "   2. They should extract it and drag IDMMacApp.app to Applications"
echo "   3. On first launch, they need to right-click → Open"
echo "      (This bypasses Gatekeeper for unsigned apps)"
echo
echo -e "${BLUE}💡 Tip:${NC} Upload to Dropbox, Google Drive, or any file sharing service"
echo

# Open the output directory
open "$OUTPUT_DIR"

