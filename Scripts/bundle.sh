#!/bin/bash
#
# Assembles Ration.app from the SwiftPM executable.
#
# SwiftPM cannot emit a macOS .app bundle on its own, so we build the binary
# and lay out the bundle by hand. This keeps the repo free of a binary
# .xcodeproj: everything here is reviewable plain text.
#
# Usage: ./Scripts/bundle.sh [debug|release]

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION 2>/dev/null || echo "0.1.0")"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo "1")"

APP="$ROOT/.build/Ration.app"
CONTENTS="$APP/Contents"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product Ration

BIN="$(swift build -c "$CONFIG" --product Ration --show-bin-path)/Ration"
[ -f "$BIN" ] || { echo "error: binary not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/Ration"

# Copy any SwiftPM resource bundles (String Catalogs, assets) next to the binary.
BINDIR="$(dirname "$BIN")"
for b in "$BINDIR"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$CONTENTS/Resources/"
done

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
    ICON_ENTRY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
    ICON_ENTRY=''
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ration</string>
    <key>CFBundleDisplayName</key><string>Ration</string>
    <key>CFBundleIdentifier</key><string>com.mcpeixoto.Ration</string>
    <key>CFBundleExecutable</key><string>Ration</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    $ICON_ENTRY
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT licensed. Not affiliated with Anthropic.</string>
</dict>
</plist>
PLIST

# Sign the bundle.
#
# macOS ties a keychain "Always Allow" grant to the app's code signature. An
# ad-hoc signature changes on every build, so the grant is void each time and
# you get a password prompt. If a stable identity is available, use it — set
# RATION_SIGN_IDENTITY, or create a self-signed "Ration Development"
# certificate via Keychain Access > Certificate Assistant.
IDENTITY="${RATION_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null \
        | grep -q "Ration Development"; then
    IDENTITY="Ration Development"
fi

if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
else
    codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
        echo "warning: ad-hoc codesign failed; app may still run"
    echo "note: ad-hoc signed. macOS will ask for your password once per launch."
    echo "      See Scripts/bundle.sh for how to avoid that during development."
fi

echo "==> Built $APP ($VERSION build $BUILD)"
