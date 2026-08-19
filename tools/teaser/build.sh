#!/usr/bin/env bash
# Builds the 1:1 teaser from repo assets: docs/images/dex-set01.jpg + demo.mp4.
# Everything lands in tools/teaser/build/ (git-ignored).
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"
REPO="$(cd ../.. && pwd)"
BUILD="$HERE/build"
mkdir -p "$BUILD/fonts" "$BUILD/app"

command -v ffmpeg >/dev/null || { echo "ffmpeg is required"; exit 1; }

if [ ! -d .venv ]; then
  python3 -m venv .venv
  ./.venv/bin/pip install -q -r requirements.txt
fi
PY=./.venv/bin/python

# 1. display fonts (SIL Open Font License, fetched rather than vendored)
[ -f "$BUILD/fonts/Anton.ttf" ] || curl -sL -o "$BUILD/fonts/Anton.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/anton/Anton-Regular.ttf"
[ -f "$BUILD/fonts/Inter.ttf" ] || curl -sL -o "$BUILD/fonts/Inter.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf"

# 2. app icon, straight out of the .icns
$PY - <<'EOF'
import io, os, re
from PIL import Image
raw = open(os.path.join('..', '..', 'Resources', 'AppIcon.icns'), 'rb').read()
best = None
for m in re.finditer(re.escape(b'\x89PNG\r\n\x1a\n'), raw):
    try:
        im = Image.open(io.BytesIO(raw[m.start():])); im.load()
        if best is None or im.width > best.width:
            best = im
    except Exception:
        pass
best.convert('RGBA').save(os.path.join('build', 'icon.png'))
print('icon', best.size)
EOF

# 3. the 50 card faces, cut out of the dex sheet
$PY slice_cards.py

# 4. footage: the Pokemon binder inside the popover, square-cropped at 60 fps
ffmpeg -v error -ss 13.2 -t 2.7 -i "$REPO/docs/images/demo.mp4" \
  -vf "crop=1120:1120:1430:121,fps=60,scale=1080:1080" "$BUILD/app/f_%04d.png" -y

# 5. original chiptune bed + SFX
$PY music.py

# 6. 1320 frames -> H.264, then loudness-normalised audio for social (-14 LUFS)
$PY render.py
ffmpeg -v error -i "$BUILD/ration-teaser-raw.mp4" -i "$BUILD/track.wav" \
  -map 0:v -map 1:a -c:v copy -af "loudnorm=I=-14:TP=-1.5:LRA=11" \
  -c:a aac -b:a 192k -movflags +faststart -shortest "$BUILD/ration-teaser-1x1.mp4" -y

echo "built $BUILD/ration-teaser-1x1.mp4"
