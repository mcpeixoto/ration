"""Cut the 50 card faces out of docs/images/dex-set01.jpg into individual PNGs.

Columns are a fixed grid; card tops/bottoms vary per row, so each column strip is
segmented vertically on its own (background rows have near-zero horizontal variance).
"""
import json
import os
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
SRC = os.path.join(REPO, 'docs', 'images', 'dex-set01.jpg')
OUT = os.path.join(HERE, 'build', 'cards')
COLS = [(27, 302), (319, 594), (612, 887), (905, 1181), (1198, 1472)]

os.makedirs(OUT, exist_ok=True)
im = Image.open(SRC).convert('RGB')
g = np.asarray(im).astype(np.float32).mean(axis=2)

def segments(x0, x1):
    s = g[:, x0:x1].std(axis=1)
    on = s > 6.0
    out, st = [], None
    for i, v in enumerate(on):
        if v and st is None:
            st = i
        elif not v and st is not None:
            if i - st > 100:
                out.append((st, i - 1))
            st = None
    if st is not None:
        out.append((st, len(on) - 1))
    return out

def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=r, fill=255)
    out = img.convert('RGBA')
    out.putalpha(mask)
    return out

def accent(img):
    """Border colour of the card = brightest saturated pixel ring, used for glows."""
    a = np.asarray(img.convert('RGB')).astype(np.float32)
    ring = np.concatenate([a[1:3].reshape(-1, 3), a[-3:-1].reshape(-1, 3),
                           a[:, 1:3].reshape(-1, 3), a[:, -3:-1].reshape(-1, 3)])
    sat = ring.max(axis=1) - ring.min(axis=1)
    sel = ring[sat > np.percentile(sat, 92)]
    c = sel.mean(axis=0) if len(sel) else np.array([200., 120., 60.])
    c = c / max(c.max(), 1.0) * 255.0
    return [int(v) for v in c]

cards, n = [], 0
col_segs = [segments(x0, x1) for x0, x1 in COLS]
for r in range(10):
    for c in range(5):
        x0, x1 = COLS[c]
        y0, y1 = col_segs[c][r]
        card = im.crop((x0, y0, x1, y1 + 1))
        card = rounded(card, max(6, int(card.width * 0.05)))
        path = f'{OUT}/card_{n:02d}.png'
        card.save(path)
        cards.append({'i': n, 'row': r, 'col': c, 'w': card.width, 'h': card.height,
                      'accent': accent(card)})
        n += 1

json.dump(cards, open(os.path.join(OUT, 'index.json'), 'w'), indent=1)
print('cards', n, '| h', min(c['h'] for c in cards), '-', max(c['h'] for c in cards))
