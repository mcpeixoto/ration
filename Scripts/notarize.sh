#!/bin/bash
#
# Notarises a signed Ration.app and produces a distributable DMG.
#
# Requires a stored notarytool profile:
#   xcrun notarytool store-credentials ration-notary \
#     --apple-id "you@example.com" --team-id TEAMID --password <app-specific-password>
#
# Usage: ./Scripts/notarize.sh [path-to-app]

set -euo pipefail

APP="${1:-.build/Ration.app}"
PROFILE="${NOTARY_PROFILE:-ration-notary}"
VERSION="$(cat VERSION)"
DMG=".build/Ration-${VERSION}.dmg"

[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

echo "==> Building $DMG"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Ration" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Submitting for notarisation (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Ready: $DMG"
shasum -a 256 "$DMG"
