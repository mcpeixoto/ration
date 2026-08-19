# Teaser builder

Builds the square social teaser for Ration: 1080×1080, 60 fps, 22 s, H.264 + AAC,
cut to a 128 BPM grid. Everything comes from assets already in this repo —
`docs/images/dex-set01.jpg` (the 50 card faces), `docs/images/demo.mp4` (real app
footage) and `Resources/AppIcon.icns` — plus two OFL display fonts fetched at
build time. No stock footage, no licensed music.

## Build

```sh
tools/teaser/build.sh          # needs python3 + ffmpeg; ~15 min, mostly frame rendering
```

Output: `tools/teaser/build/ration-teaser-1x1.mp4` (git-ignored, ~26 MB).

The finished video is published as a release asset rather than committed here, so
the clone stays small:

<https://github.com/mcpeixoto/ration/releases/download/v0.6.0/ration-teaser-1x1.mp4>

## What each piece does

| File | Role |
|---|---|
| `slice_cards.py` | Cuts the 50 card faces out of the dex sheet. Columns are a fixed grid; card heights vary per row, so each column strip is segmented on its own. Also samples each card's border colour, used for its glow. |
| `music.py` | Synthesises the soundtrack from scratch with numpy: chiptune kit, square bass, pulse lead, riser, crashes, plus the SFX (pack rip, whooshes, impacts, sparkles). 128 BPM, 22 s. |
| `render.py` | Draws all 1320 frames with Pillow/numpy and pipes raw RGB into ffmpeg. `--preview 4.2 9.5` writes single frames instead, which is the fast way to iterate. |
| `post_to_x.py` | Posts the finished file to X. Needs OAuth 1.0a user keys with write access; `--dry-run` checks auth and prints the text without posting. |
| `build.sh` | Runs the whole chain and normalises the audio to −14 LUFS / −1.5 dBTP for social. |

## Timeline

The cut is locked to the beat (128 BPM, one beat = 0.469 s):

| t | scene |
|---|---|
| 0.0–1.9 | ring gauge fills to 87%, "YOU BURN TOKENS", Claude Code · Codex · Cursor |
| 1.9–2.8 | "YOU GET CARDS" |
| 2.8–3.75 | booster pack shaking, riser underneath |
| 3.75 | rip: radial flash, particle burst, punch zoom |
| 4.2–13.1 | 25 cards, one per beat then double time — 3D flip, ghost trails, speed lines, holo sheen on landing, counter to 50 |
| 13.1–17.5 | all 50 fly into a 10×5 binder, camera pulls back, holo sweep |
| 17.5–20.0 | real app footage, push-in |
| 20.0–22.0 | wordmark, "Free · Open source · macOS", repo link |

Changing copy or timing means editing `render.py` and rebuilding; the scene
functions are named after the rows above.
