#!/bin/bash
#
# Signs Ration.app with a Developer ID and the hardened runtime.
#
# Requires:
#   DEVELOPER_ID  e.g. "Developer ID Application: Your Name (TEAMID)"
#
# Usage: ./Scripts/sign.sh [path-to-app]

set -euo pipefail

APP="${1:-.build/Ration.app}"
: "${DEVELOPER_ID:?set DEVELOPER_ID to your Developer ID Application identity}"

[ -d "$APP" ] || { echo "error: $APP not found — run Scripts/bundle.sh first" >&2; exit 1; }

echo "==> Signing $APP"
codesign --force --deep \
    --sign "$DEVELOPER_ID" \
    --options runtime \
    --timestamp \
    "$APP"

echo "==> Verifying"
codesign --verify --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" || \
    echo "note: spctl will fail until the app is notarised — this is expected"

echo "==> Signed"
