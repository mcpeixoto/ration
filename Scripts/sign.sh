#!/bin/bash
#
# Signs Ration.app with a Developer ID and the hardened runtime.
#
# Signing runs inside-out: nested code first, the app bundle last. codesign
# seals each nested bundle's signature into its parent, so anything signed
# after its container invalidates that container. `--deep` appears to do this
# for you but signs in an order Apple no longer supports for notarisation, and
# is deprecated; doing it explicitly is both correct and reviewable.
#
# Requires:
#   DEVELOPER_ID  e.g. "Developer ID Application: Your Name (TEAMID)"
#
# Usage: ./Scripts/sign.sh [path-to-app]

set -euo pipefail

APP="${1:-.build/Ration.app}"
: "${DEVELOPER_ID:?set DEVELOPER_ID to your Developer ID Application identity}"

[ -d "$APP" ] || { echo "error: $APP not found — run Scripts/bundle.sh first" >&2; exit 1; }

# codesign writes each new signature to a .cstemp file and renames it into
# place. An interrupted run leaves those behind, and the next run seals the
# debris into the parent — which then fails verification with "a sealed
# resource is missing or invalid" long after the interrupted run is forgotten.
find "$APP" -name '*.cstemp' -delete

sign() {
    local target="$1"
    [ -e "$target" ] || return 0
    echo "    $(basename "$target")"
    codesign --force \
        --sign "$DEVELOPER_ID" \
        --options runtime \
        --timestamp \
        "$target"
}

# Sparkle ships a framework containing its own helper executables and app
# bundles. Each is independent code and has to be signed before the framework
# version that contains it.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    VERSION_DIR="$SPARKLE/Versions/$(readlink "$SPARKLE/Versions/Current")"
    echo "==> Signing Sparkle.framework"
    for xpc in "$VERSION_DIR"/XPCServices/*.xpc; do
        sign "$xpc"
    done
    sign "$VERSION_DIR/Autoupdate"
    sign "$VERSION_DIR/Updater.app"
    sign "$VERSION_DIR"
fi

echo "==> Signing $APP"
sign "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" || \
    echo "note: spctl will fail until the app is notarised — this is expected"

echo "==> Signed"
