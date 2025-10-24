#!/bin/bash
# Helper script to sign updates for Sparkle
# Usage: ./sign_update.sh <version>
# Example: ./sign_update.sh 0.1.0

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.1.0"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIGN_UPDATE="$PROJECT_DIR/bin/sign_update"
APP_PATH="NanoJetApp.app"
ZIP_NAME="NanoJetApp-${VERSION}.zip"

echo "🔐 Signing update for version ${VERSION}..."
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: $APP_PATH not found"
    echo "   Please build and export your app first"
    exit 1
fi

# Check if sign_update tool exists
if [ ! -f "$SIGN_UPDATE" ]; then
    echo "❌ Error: sign_update tool not found at $SIGN_UPDATE"
    exit 1
fi

# Create ZIP
echo "📦 Creating ZIP archive..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"
echo "   Created: $ZIP_NAME"

# Get file size
SIZE=$(stat -f%z "$ZIP_NAME")
echo "   Size: $SIZE bytes"
echo ""

# Sign the update (private key is in keychain)
echo "🔑 Signing update..."
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_NAME")

if [ -z "$SIGNATURE" ]; then
    echo "❌ Error: Failed to generate signature"
    exit 1
fi

echo "   Signature: $SIGNATURE"
echo ""

# Generate appcast entry
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Update signed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Add this to your appcast.xml:"
echo ""
cat << EOF
<item>
    <title>Version ${VERSION}</title>
    <description><![CDATA[
        <h3>What's New in NanoJet ${VERSION}</h3>
        <ul>
            <li>Add your changes here</li>
        </ul>
    ]]></description>
    <pubDate>$(date -R)</pubDate>
    <sparkle:version>1</sparkle:version>
    <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    <enclosure 
        url="https://ahmedsam.com/idmmac/downloads/${ZIP_NAME}"
        length="${SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}" />
</item>
EOF
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Next steps:"
echo "   1. Upload ${ZIP_NAME} to https://ahmedsam.com/idmmac/downloads/"
echo "   2. Update your appcast.xml with the entry above"
echo "   3. Test the update in your app"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

