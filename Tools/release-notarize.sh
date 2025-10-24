#!/usr/bin/env bash
set -euo pipefail

# NanoJet release helper
#
# Prereqs:
# - Xcode CLT installed
# - A Developer ID Application cert in your keychain
# - A notarytool keychain profile configured, e.g.:
#   xcrun notarytool store-credentials AC_PROFILE --apple-id "you@example.com" --team-id TEAMID1234 --password "app-specific-password"
#
# Usage examples:
#   ./Tools/release-notarize.sh --app "NanoJetApp.app" --profile AC_PROFILE --bundle-id com.example.idmmac --team TEAMID1234
#   ./Tools/release-notarize.sh --archive xcarchive.xcarchive --profile AC_PROFILE
#
# Options:
#   --archive <path>    Use an existing .xcarchive (preferred)
#   --app <path>        Use an existing .app bundle
#   --out <dir>         Output directory (default: ./dist)
#   --profile <name>    notarytool keychain profile name
#   --bundle-id <id>    Bundle identifier (required if resigning .app)
#   --team <TEAMID>     Team ID (optional; for codesign --teamid)
#   --dmg               Build a DMG instead of ZIP (both if repeated)

ARCHIVE=""
APP_PATH=""
OUT_DIR="$(pwd)/dist"
PROFILE=""
BUNDLE_ID=""
TEAM_ID=""
MAKE_DMG="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2;;
    --app) APP_PATH="$2"; shift 2;;
    --out) OUT_DIR="$2"; shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --bundle-id) BUNDLE_ID="$2"; shift 2;;
    --team) TEAM_ID="$2"; shift 2;;
    --dmg) MAKE_DMG="true"; shift 1;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "--profile is required"; exit 1
fi

mkdir -p "$OUT_DIR"

if [[ -n "$ARCHIVE" ]]; then
  echo "Exporting .app from xcarchive: $ARCHIVE"
  APP_EXPORT_DIR="$OUT_DIR/app"
  rm -rf "$APP_EXPORT_DIR" && mkdir -p "$APP_EXPORT_DIR"
  APP_PATH="$APP_EXPORT_DIR/NanoJetApp.app"
  # Try to find the app within the archive
  FOUND_APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name "*.app" | head -n1)
  if [[ -z "$FOUND_APP" ]]; then
    echo "Could not find .app inside archive"; exit 1
  fi
  cp -R "$FOUND_APP" "$APP_PATH"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"; exit 1
fi

echo "Codesigning with Hardened Runtime..."
CODE_SIGN_ARGS=(--force --options runtime --timestamp)
if [[ -n "$TEAM_ID" ]]; then
  CODE_SIGN_ARGS+=(--teamid "$TEAM_ID")
fi

codesign "${CODE_SIGN_ARGS[@]}" --deep -s "Developer ID Application" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ZIP_PATH="$OUT_DIR/NanoJetApp.zip"
echo "Creating ZIP: $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting for notarization using profile $PROFILE..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait

echo "Stapling ticket..."
xcrun stapler staple -v "$APP_PATH"

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
echo "ZIP SHA-256:"; cat "$ZIP_PATH.sha256"

if [[ "$MAKE_DMG" == "true" ]]; then
  DMG_PATH="$OUT_DIR/NanoJetApp.dmg"
  echo "Creating DMG: $DMG_PATH"
  rm -f "$DMG_PATH"
  hdiutil create -volname "NanoJet" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait
  echo "Stapling DMG..."
  xcrun stapler staple -v "$DMG_PATH"
  shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
  echo "DMG SHA-256:"; cat "$DMG_PATH.sha256"
fi

echo "Done. Artifacts in $OUT_DIR"


