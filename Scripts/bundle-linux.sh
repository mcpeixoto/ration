#!/usr/bin/env bash
# Builds a release tarball of the Linux build: the CLI, the tray, its icons,
# a desktop entry, and an installer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
PRODUCT="ration-${VERSION}-linux-$(uname -m)"
STAGING=".build/${PRODUCT}"
ARCHIVE=".build/${PRODUCT}.tar.gz"

# Distributions split the C libraries into runtime and -dev packages, and not
# every machine can install the -dev half. A user-local prefix holding the
# headers and .so symlinks is honoured when one is present, so the build works
# without root. Extra flags can also be passed in RATION_BUILD_FLAGS.
BUILD_FLAGS=()
PREFIX="${RATION_PREFIX:-$HOME/.local}"
if [[ ! -f /usr/include/sqlite3.h && -f "$PREFIX/include/sqlite3.h" ]]; then
  BUILD_FLAGS+=(-Xcc "-I$PREFIX/include")
fi
if [[ -d "$PREFIX/lib" ]]; then
  BUILD_FLAGS+=(-Xlinker "-L$PREFIX/lib")
fi
# shellcheck disable=SC2206
BUILD_FLAGS+=(${RATION_BUILD_FLAGS:-})

echo "Building ration ${VERSION} for Linux…"
swift build -c release --product ration "${BUILD_FLAGS[@]}"

# The tray needs GTK, Cairo and libayatana-appindicator3. A build host without
# them still produces a usable CLI tarball, so this half is allowed to fail.
TRAY_BUILT=0
if swift build -c release --product ration-tray "${BUILD_FLAGS[@]}"; then
  TRAY_BUILT=1
else
  echo "warning: ration-tray did not build; packaging the CLI only" >&2
fi

BIN=".build/release/ration"
if [[ ! -x "$BIN" ]]; then
  echo "error: ${BIN} not found" >&2
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp "$BIN" "$STAGING/ration"
cp LICENSE README.md "$STAGING/"

if [[ "$TRAY_BUILT" == 1 ]]; then
  cp ".build/release/ration-tray" "$STAGING/ration-tray"

  # Icons are drawn by the tray itself, so the tarball carries no binary blob
  # that cannot be regenerated from source.
  for size in 32 48 64 128 256 512; do
    "$STAGING/ration-tray" --write-icon \
      "$STAGING/icons/hicolor/${size}x${size}/apps/ration.png" --icon-size "$size" >/dev/null
  done

  cat > "$STAGING/ration.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Ration
GenericName=AI coding usage
Comment=Your Claude, Codex and Cursor usage, in the tray
Exec=ration-tray
Icon=ration
Terminal=false
Categories=Utility;Monitor;
StartupNotify=false
X-GNOME-UsesNotifications=true
DESKTOP
fi

cat > "$STAGING/install.sh" <<'INSTALL'
#!/usr/bin/env sh
# Installs Ration for the current user. No root, nothing outside $HOME.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

# Both binaries link against the Swift 6 runtime. Distribution packages put it
# on the loader path; a toolchain installed with swiftly does not, so in that
# case the launcher points at it rather than leaving the user with
# "libswiftCore.so: cannot open shared object file".
RUNTIME=""
if ! ldconfig -p 2>/dev/null | grep -q libswiftCore.so; then
  for candidate in "$HOME"/.local/share/swiftly/toolchains/*/usr/lib/swift/linux; do
    [ -f "$candidate/libswiftCore.so" ] && RUNTIME="$candidate"
  done
fi

LIBEXEC="${XDG_DATA_HOME:-$HOME/.local/share}/ration"

install_binary() {
  name="$1"
  if [ -z "$RUNTIME" ]; then
    install -m 755 "$HERE/$name" "$BIN/$name"
  else
    mkdir -p "$LIBEXEC"
    install -m 755 "$HERE/$name" "$LIBEXEC/$name"
    cat > "$BIN/$name" <<LAUNCHER
#!/bin/sh
# Points $name at the Swift runtime this machine keeps outside the loader path.
LD_LIBRARY_PATH="$RUNTIME\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$LIBEXEC/$name" "\$@"
LAUNCHER
    chmod 755 "$BIN/$name"
  fi
  echo "Installed $BIN/$name"
}

mkdir -p "$BIN"
install_binary ration

if [ -f "$HERE/ration-tray" ]; then
  install_binary ration-tray

  if [ -d "$HERE/icons" ]; then
    cp -r "$HERE/icons/." "$SHARE/icons/"
  fi
  mkdir -p "$SHARE/applications"
  install -m 644 "$HERE/ration.desktop" "$SHARE/applications/ration.desktop"
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$SHARE/applications" >/dev/null 2>&1 || true
  echo "Installed the desktop entry and icons"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Note: $BIN is not on your PATH." ;;
esac
INSTALL
chmod +x "$STAGING/install.sh"

tar -C ".build" -czf "$ARCHIVE" "$(basename "$STAGING")"
echo "Wrote ${ARCHIVE}"
