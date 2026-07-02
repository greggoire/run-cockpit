#!/usr/bin/env bash
#
# package-developer-id.sh — Build, sign (Developer ID), notarize and staple a
# distributable RunCockpit.dmg for OTHER Macs.
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership.
#   2. A "Developer ID Application" certificate in your login keychain.
#   3. Stored notarytool credentials, e.g.:
#        xcrun notarytool store-credentials runcockpit-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Usage:
#   DEVID_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="runcockpit-notary" \
#   scripts/package-developer-id.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVID_IDENTITY:?Set DEVID_IDENTITY (e.g. 'Developer ID Application: Name (TEAMID)')}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE (your stored notarytool credential profile)}"

CONFIG=Release
BUILD=build
ARCHIVE="$BUILD/RunCockpit.xcarchive"
EXPORT="$BUILD/export"
DMG="$BUILD/RunCockpit.dmg"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "▶︎ Archiving…"
xcodebuild \
  -project RunCockpit.xcodeproj \
  -scheme RunCockpit \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVID_IDENTITY" \
  archive

echo "▶︎ Exporting (Developer ID)…"
cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -exportPath "$EXPORT"

APP="$EXPORT/RunCockpit.app"
[ -d "$APP" ] || { echo "❌ Exported app not found"; exit 1; }

echo "▶︎ Creating DMG…"
hdiutil create -volname "RunCockpit" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo "▶︎ Notarizing (this uploads the DMG to Apple)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶︎ Stapling…"
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"

echo "✅ Notarized DMG ready: $DMG"
