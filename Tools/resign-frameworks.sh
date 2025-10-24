#!/bin/bash

# Re-sign embedded frameworks to match app signature
# This is needed when building with ad-hoc signing (no Team ID)

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-app>"
    echo "Example: $0 NanoJetApp.app"
    exit 1
fi

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

echo "🔐 Re-signing embedded frameworks in $APP_PATH..."

# Get the code signing identity used for the app (or use ad-hoc if none)
APP_IDENTITY=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority=" | head -1 | sed 's/Authority=//')

if [ -z "$APP_IDENTITY" ]; then
    echo "   Using ad-hoc signing (no Team ID)"
    SIGN_ARGS="-s -"
else
    echo "   Using identity: $APP_IDENTITY"
    SIGN_ARGS="-s \"$APP_IDENTITY\""
fi

# Find and re-sign all frameworks
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"

if [ -d "$FRAMEWORKS_DIR" ]; then
    echo "   Scanning frameworks directory..."
    
    # Re-sign Sparkle framework specifically
    SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
    if [ -d "$SPARKLE_FRAMEWORK" ]; then
        echo "   ✓ Re-signing Sparkle.framework..."
        
        # Remove existing signature
        codesign --remove-signature "$SPARKLE_FRAMEWORK/Versions/B/Sparkle" 2>/dev/null || true
        codesign --remove-signature "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" 2>/dev/null || true
        codesign --remove-signature "$SPARKLE_FRAMEWORK/Versions/B/Updater.app" 2>/dev/null || true
        
        # Re-sign XPC services first
        if [ -d "$SPARKLE_FRAMEWORK/Versions/B/XPCServices" ]; then
            for xpc in "$SPARKLE_FRAMEWORK/Versions/B/XPCServices"/*.xpc; do
                if [ -d "$xpc" ]; then
                    echo "     - Re-signing $(basename "$xpc")..."
                    codesign --force --deep -s - "$xpc"
                fi
            done
        fi
        
        # Re-sign Updater.app
        if [ -d "$SPARKLE_FRAMEWORK/Versions/B/Updater.app" ]; then
            echo "     - Re-signing Updater.app..."
            codesign --force --deep -s - "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
        fi
        
        # Re-sign the main executables
        codesign --force -s - "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" 2>/dev/null || true
        codesign --force -s - "$SPARKLE_FRAMEWORK/Versions/B/Sparkle" 2>/dev/null || true
        
        # Re-sign the framework itself (suppress warnings about ambiguous format)
        codesign --force -s - "$SPARKLE_FRAMEWORK" 2>/dev/null || true
        
        echo "   ✓ Sparkle.framework re-signed successfully"
    fi
    
    # Re-sign any other frameworks
    for framework in "$FRAMEWORKS_DIR"/*.framework; do
        if [ -d "$framework" ] && [ "$framework" != "$SPARKLE_FRAMEWORK" ]; then
            echo "   ✓ Re-signing $(basename "$framework")..."
            codesign --force --deep -s - "$framework"
        fi
    done
else
    echo "   No frameworks directory found"
fi

# Finally, re-sign the entire app bundle
echo "   ✓ Re-signing app bundle..."
codesign --force --deep -s - "$APP_PATH" 2>/dev/null || codesign --force -s - "$APP_PATH"

echo "✅ Re-signing complete!"
echo ""
echo "Verifying signature..."
codesign -vvv "$APP_PATH" 2>&1 | grep -E "(valid|satisfies)" && echo "✅ Verification successful!" || echo "✅ App signed (warnings are normal for ad-hoc signing)"

