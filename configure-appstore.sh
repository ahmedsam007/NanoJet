#!/bin/bash

# NanoJet - Mac App Store Configuration Script
# This script helps you prepare your project for Mac App Store distribution

set -e  # Exit on error

echo "🍎 NanoJet - Mac App Store Configuration"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "NanoJet.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}❌ Error: Please run this script from the NanoJet project root directory${NC}"
    exit 1
fi

echo -e "${BLUE}This script will:${NC}"
echo "  1. Backup your current configuration"
echo "  2. Switch to App Store configuration"
echo "  3. Remove Sparkle framework"
echo "  4. Update entitlements and Info.plist"
echo ""
echo -e "${YELLOW}⚠️  Warning: This will modify your Xcode project${NC}"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1: Getting your Apple Developer Team ID...${NC}"
echo ""
echo "Please enter your Apple Developer Team ID:"
echo "(Find it at: https://developer.apple.com/account#MembershipDetailsCard)"
echo "Example: ABC123XYZ4"
read -p "Team ID: " TEAM_ID

if [ -z "$TEAM_ID" ]; then
    echo -e "${RED}❌ Team ID is required${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 2: Backing up current configuration...${NC}"

# Create backup directory
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup files
cp project.yml "$BACKUP_DIR/project.yml.backup" 2>/dev/null || echo "No project.yml to backup"
cp NanoJetApp/App/NanoJetApp.entitlements "$BACKUP_DIR/NanoJetApp.entitlements.backup"
cp NanoJetApp/Resources/Info.plist "$BACKUP_DIR/Info.plist.backup"

echo -e "${GREEN}✅ Backup created in: $BACKUP_DIR${NC}"

echo ""
echo -e "${BLUE}Step 3: Updating configuration files...${NC}"

# Update ExportOptionsAppStore.plist with Team ID
if [ -f "Tools/ExportOptionsAppStore.plist" ]; then
    sed -i '' "s/REPLACE_WITH_YOUR_TEAM_ID/$TEAM_ID/g" Tools/ExportOptionsAppStore.plist
    echo -e "${GREEN}✅ Updated ExportOptionsAppStore.plist${NC}"
fi

# Update project-appstore.yml with Team ID
if [ -f "project-appstore.yml" ]; then
    sed -i '' "s/REPLACE_WITH_YOUR_TEAM_ID/$TEAM_ID/g" project-appstore.yml
    echo -e "${GREEN}✅ Updated project-appstore.yml${NC}"
    
    # Copy to project.yml
    cp project-appstore.yml project.yml
    echo -e "${GREEN}✅ Applied App Store configuration to project.yml${NC}"
fi

# Use App Store entitlements
if [ -f "NanoJetApp/App/NanoJetApp-AppStore.entitlements" ]; then
    cp NanoJetApp/App/NanoJetApp-AppStore.entitlements NanoJetApp/App/NanoJetApp.entitlements
    echo -e "${GREEN}✅ Updated entitlements for App Store${NC}"
fi

# Use App Store Info.plist
if [ -f "NanoJetApp/Resources/Info-AppStore.plist" ]; then
    cp NanoJetApp/Resources/Info-AppStore.plist NanoJetApp/Resources/Info.plist
    echo -e "${GREEN}✅ Updated Info.plist for App Store (Sparkle removed)${NC}"
fi

echo ""
echo -e "${BLUE}Step 4: Checking for XcodeGen...${NC}"

if command -v xcodegen &> /dev/null; then
    echo -e "${GREEN}✅ XcodeGen found${NC}"
    read -p "Regenerate Xcode project now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        xcodegen generate
        echo -e "${GREEN}✅ Xcode project regenerated${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  XcodeGen not found${NC}"
    echo "   Install with: brew install xcodegen"
    echo "   Or manually update your Xcode project with these settings:"
    echo "   - CODE_SIGN_STYLE = Manual"
    echo "   - DEVELOPMENT_TEAM = $TEAM_ID"
    echo "   - Remove Sparkle framework dependency"
fi

echo ""
echo -e "${GREEN}✅ Configuration complete!${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. ${YELLOW}Open Xcode and configure signing:${NC}"
echo "   - Select project → Target → Signing & Capabilities"
echo "   - Uncheck 'Automatically manage signing'"
echo "   - Set Team: $TEAM_ID"
echo "   - Release: 3rd Party Mac Developer Application"
echo "   - Provisioning Profile: NanoJet App Store Profile"
echo ""
echo "2. ${YELLOW}Remove Sparkle references from code:${NC}"
echo "   - Remove UpdaterManager.swift usage"
echo "   - Remove 'Check for Updates' menu items"
echo "   - Comment out or remove Sparkle import statements"
echo ""
echo "3. ${YELLOW}Apple Developer Portal:${NC}"
echo "   - Create App ID: com.ahmedsam.idmmac"
echo "   - Create Mac App Distribution certificate"
echo "   - Create provisioning profile"
echo ""
echo "4. ${YELLOW}App Store Connect:${NC}"
echo "   - Create new app record"
echo "   - Upload screenshots"
echo "   - Fill in app information"
echo ""
echo "5. ${YELLOW}Build and Archive:${NC}"
echo "   - Product → Archive"
echo "   - Validate → Upload to App Store"
echo ""
echo -e "${BLUE}📚 Read the complete guide:${NC} APP_STORE_SETUP_GUIDE.md"
echo ""
echo -e "${GREEN}Good luck with your App Store submission! 🚀${NC}"

