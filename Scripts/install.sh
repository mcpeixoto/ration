#!/bin/bash
#
# Builds Ration, signs it, and installs it into /Applications.
#
# This is the "run it on my own machine" path — the DMG in Releases is for
# everyone else. Nothing here notarises: a locally built copy never crosses a
# quarantine boundary, so Gatekeeper never asks about it.
#
# Usage: ./Scripts/install.sh [debug|release]
#
# Set DEVELOPER_ID to sign with a Developer ID Application identity. Without
# it, bundle.sh's own signing applies (a "Ration Development" certificate if
# you have one, ad-hoc otherwise).

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILT="$ROOT/.build/Ration.app"
DEST="/Applications/Ration.app"

"$ROOT/Scripts/bundle.sh" "$CONFIG"

if [ -n "${DEVELOPER_ID:-}" ]; then
    "$ROOT/Scripts/sign.sh" "$BUILT"
fi

# A running bundle cannot be replaced underneath itself. Ask it to quit, and
# only escalate if it does not.
if pgrep -x Ration >/dev/null; then
    echo "==> Quitting the running copy"
    osascript -e 'quit app "Ration"' 2>/dev/null || true
    for _ in $(seq 1 20); do
        pgrep -x Ration >/dev/null || break
        sleep 0.5
    done
    pgrep -x Ration >/dev/null && pkill -x Ration || true
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
# ditto, not cp: it preserves the extended attributes and symlinks inside
# Sparkle.framework that the signature is sealed against.
ditto "$BUILT" "$DEST"

echo "==> Launching"
open "$DEST"

echo "==> Installed $DEST"
