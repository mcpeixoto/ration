#!/usr/bin/env bash
# Builds a release tarball of the Linux CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
PRODUCT="ration-${VERSION}-linux-$(uname -m)"
STAGING=".build/${PRODUCT}"
ARCHIVE=".build/${PRODUCT}.tar.gz"

echo "Building ration ${VERSION} for Linux…"
swift build -c release --product ration

BIN=".build/release/ration"
if [[ ! -x "$BIN" ]]; then
  echo "error: ${BIN} not found" >&2
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp "$BIN" "$STAGING/ration"
cp LICENSE README.md "$STAGING/"

tar -C ".build" -czf "$ARCHIVE" "$(basename "$STAGING")"
echo "Wrote ${ARCHIVE}"
