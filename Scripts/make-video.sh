#!/bin/bash
#
# Encodes the demo frames into an MP4 (for X/social) and a GIF (for the README).
#
# Frames come from `swift run RationPreview video`, which renders the real
# SwiftUI views frame by frame — the motion is the app, not a mockup.
#
# Usage: ./Scripts/make-video.sh [frames-dir] [output-dir]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FRAMES="${1:-.build/video-frames}"
OUT="${2:-docs/images}"
FPS=30

command -v ffmpeg >/dev/null || { echo "error: ffmpeg not installed (brew install ffmpeg)" >&2; exit 1; }
[ -d "$FRAMES" ] || { echo "error: no frames at $FRAMES — run 'swift run RationPreview video' first" >&2; exit 1; }

COUNT="$(find "$FRAMES" -name 'frame-*.png' | wc -l | tr -d ' ')"
[ "$COUNT" -gt 0 ] || { echo "error: no frames found in $FRAMES" >&2; exit 1; }
echo "==> $COUNT frames at ${FPS}fps ($(echo "scale=1; $COUNT/$FPS" | bc)s)"

mkdir -p "$OUT"

# H.264 + yuv420p is the combination that plays everywhere, including in
# X's inline player and on iOS. Dimensions must be even for yuv420p.
echo "==> Encoding MP4"
ffmpeg -y -loglevel error \
    -framerate "$FPS" -i "$FRAMES/frame-%05d.png" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" \
    -c:v libx264 -preset slow -crf 18 -movflags +faststart \
    "$OUT/demo.mp4"

# A palette pass keeps the orange gradient from banding — a straight GIF
# encode of this footage looks noticeably worse.
echo "==> Encoding GIF"
PALETTE="$(mktemp -t ration-palette).png"
ffmpeg -y -loglevel error \
    -framerate "$FPS" -i "$FRAMES/frame-%05d.png" \
    -vf "fps=20,scale=420:-1:flags=lanczos,palettegen=stats_mode=diff" "$PALETTE"
ffmpeg -y -loglevel error \
    -framerate "$FPS" -i "$FRAMES/frame-%05d.png" -i "$PALETTE" \
    -lavfi "fps=20,scale=420:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    "$OUT/demo.gif"
rm -f "$PALETTE"

echo "==> Wrote:"
ls -lh "$OUT/demo.mp4" "$OUT/demo.gif" | awk '{print "    " $9 "  " $5}'
