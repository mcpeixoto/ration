"""Renders the Ration teaser: 1080x1080, 60 fps, 22 s, cut to a 128 BPM grid.

Everything is drawn from repo assets (the 50 sliced card faces, the app icon,
and a crop of docs/images/demo.mp4) plus procedural shapes.

  .venv/bin/python render.py                 -> ration-x-teaser.mp4
  .venv/bin/python render.py --preview 1.2 5 -> preview_*.png for those seconds
"""
import json
import math
import os
import subprocess
import sys
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W = H = 1080
FPS = 60
DUR = 22.0
NF = int(DUR * FPS)
GW = 540                      # glow layer works at half res

BEAT = 60.0 / 128.0
def tb(b):                    # time of beat b
    return b * BEAT

T_LINE2 = tb(4)               # 1.875  "you get cards"
T_PACK = tb(6)                # 2.8125 pack drops in and shakes
T_RIP = tb(8)                 # 3.75   drop / pack rip
T_BINDER = tb(28)             # 13.125 wall of 50
T_APP = tb(37.333)            # 17.5   real app footage
T_CTA = tb(42.667)            # 20.0   call to action

REVEAL_BEATS = [9 + i for i in range(13)] + [22 + 0.5 * i for i in range(12)]
REVEAL_TIMES = [tb(b) for b in REVEAL_BEATS]

ORANGE = (228, 126, 84)
ORANGE_HOT = (255, 168, 116)
WHITE = (247, 244, 241)
DIM = (150, 140, 136)

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(ROOT, '..', '..'))
BUILD = os.path.join(ROOT, 'build')
CARDS = [Image.open(f'{BUILD}/cards/card_{i:02d}.png').convert('RGBA') for i in range(50)]
META = json.load(open(f'{BUILD}/cards/index.json'))
ICON = Image.open(f'{BUILD}/icon.png').convert('RGBA')
APP_FRAMES = sorted(os.listdir(f'{BUILD}/app'))

# cards from rows 1..8 are complete faces in the source sheet; rows 0 and 9 are
# clipped there, so heroes come from the middle and the wall uses all 50.
HERO = [i for i in range(50) if 5 <= i <= 44]
REVEAL_ORDER = [HERO[(i * 7 + 3) % len(HERO)] for i in range(len(REVEAL_TIMES))]


# ----------------------------------------------------------------- easing
def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))

def ease_out_cubic(x):
    return 1 - (1 - x) ** 3

def ease_out_quart(x):
    return 1 - (1 - x) ** 4

def ease_in_cubic(x):
    return x ** 3

def ease_out_back(x, s=1.7):
    return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2

def lerp(a, b, x):
    return a + (b - a) * x

def smooth(a, b, t):
    return lerp(a, b, clamp(t))


# ----------------------------------------------------------------- text
@lru_cache(maxsize=64)
def font(kind, size, weight=700):
    if kind == 'anton':
        return ImageFont.truetype(f'{BUILD}/fonts/Anton.ttf', size)
    f = ImageFont.truetype(f'{BUILD}/fonts/Inter.ttf', size)
    f.set_variation_by_axes([32.0, float(weight)])
    return f

@lru_cache(maxsize=256)
def text_img(s, size, color, kind='anton', weight=700, track=0, glow=0.0):
    """Rendered line of text as RGBA, optionally with a baked glow."""
    f = font(kind, size, weight)
    pad = int(size * 0.9) + 30
    widths = [f.getlength(ch) for ch in s]
    total = sum(widths) + track * max(0, len(s) - 1)
    img = Image.new('RGBA', (int(total) + pad * 2, int(size * 1.9) + pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = pad
    for ch, w in zip(s, widths):
        d.text((x, pad // 2), ch, font=f, fill=color + (255,))
        x += w + track
    if glow > 0:
        halo = img.filter(ImageFilter.GaussianBlur(int(size * 0.28)))
        a = np.asarray(halo).astype(np.float32)
        a[..., 3] *= glow * 1.6
        halo = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        halo.alpha_composite(img)
        img = halo
    return img


def paste(layer, img, cx, cy, scale=1.0, alpha=1.0, rot=0.0):
    if alpha <= 0.003 or scale <= 0.004:
        return
    w, h = max(1, int(img.width * scale)), max(1, int(img.height * scale))
    im = img.resize((w, h), Image.LANCZOS if scale < 1 else Image.BILINEAR)
    if abs(rot) > 0.05:
        im = im.rotate(rot, resample=Image.BILINEAR, expand=True)
    if alpha < 0.997:
        a = np.asarray(im).astype(np.float32)
        a[..., 3] *= alpha
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    layer.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def text(layer, s, cx, cy, size, color=WHITE, kind='anton', weight=700, track=0,
         glow=0.0, scale=1.0, alpha=1.0):
    paste(layer, text_img(s, size, color, kind, weight, track, glow), cx, cy, scale, alpha)


# ----------------------------------------------------------------- background
def build_base():
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    top = np.array([9, 9, 11], dtype=np.float32)
    bot = np.array([44, 21, 16], dtype=np.float32)
    grad = top + (bot - top) * (y ** 1.35)
    base = np.repeat(grad[:, None, :], W, axis=1)
    xx, yy = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    vig = 1.0 - 0.55 * np.clip((xx ** 2 + yy ** 2) ** 0.85, 0, 1)
    return base * vig[..., None]

BASE = build_base().astype(np.float32)

_xx, _yy = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
RADIAL = np.clip(1.25 - (_xx ** 2 + _yy ** 2) ** 0.7, 0, 1).astype(np.float32)[..., None]

RNG = np.random.default_rng(7)
GRAIN = [RNG.normal(0, 1, (H, W, 1)).astype(np.float32) for _ in range(6)]

def grain_full(k):
    return GRAIN[k % len(GRAIN)]


# ----------------------------------------------------------------- card art helpers
@lru_cache(maxsize=1024)
def card_scaled(idx, w, h):
    return CARDS[idx].resize((max(1, w), max(1, h)), Image.LANCZOS)

@lru_cache(maxsize=1)
def card_back():
    w, h = 275, 400
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=16, fill=(26, 16, 14, 255),
                        outline=ORANGE + (255,), width=4)
    ic = ICON.resize((110, 110), Image.LANCZOS)
    img.alpha_composite(ic, (w // 2 - 55, h // 2 - 75))
    t = text_img('RATION', 34, ORANGE, 'anton', track=6)
    img.alpha_composite(t, (w // 2 - t.width // 2, h // 2 + 40))
    return img


def draw_card(layer, glow_d, idx, cx, cy, height, rot=0.0, spin=0.0, alpha=1.0, glow=0.0):
    """spin is a y-axis rotation in degrees; the back face shows past 90 deg."""
    c = math.cos(math.radians(spin))
    src = CARDS[idx] if c >= 0 else card_back()
    ratio = src.width / src.height
    h = max(2, int(height))
    w = max(2, int(h * ratio * abs(c)))
    im = card_scaled(idx, w, h) if c >= 0 else card_back().resize((w, h), Image.BILINEAR)
    if abs(rot) > 0.05:
        im = im.rotate(rot, resample=Image.BILINEAR, expand=True)
    if alpha < 0.997:
        a = np.asarray(im).astype(np.float32)
        a[..., 3] *= alpha
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    layer.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))
    if glow > 0.01:
        col = META[idx]['accent']
        r = int(h * 0.42 * (0.8 + glow))
        gx, gy = cx / 2, cy / 2
        glow_d.ellipse([gx - r / 2, gy - r / 2, gx + r / 2, gy + r / 2],
                       fill=tuple(int(v * glow * 0.55) for v in col))


# ----------------------------------------------------------------- particles
class Particles:
    def __init__(self):
        self.p = []          # x, y, vx, vy, life, born, col, size
        self.rng = np.random.default_rng(11)

    def burst(self, t, x, y, n, col, speed=520, life=0.8, size=7):
        for _ in range(n):
            a = self.rng.uniform(0, 2 * math.pi)
            s = speed * self.rng.uniform(0.25, 1.0)
            self.p.append([x, y, math.cos(a) * s, math.sin(a) * s,
                           life * self.rng.uniform(0.5, 1.2), t,
                           col, size * self.rng.uniform(0.5, 1.5)])

    def draw(self, t, gd):
        alive = []
        for q in self.p:
            age = t - q[5]
            if age < 0 or age > q[4]:
                if age <= q[4]:
                    alive.append(q)
                continue
            u = age / q[4]
            x = q[0] + q[2] * age * (1 - u * 0.55)
            y = q[1] + q[3] * age * (1 - u * 0.55) + 260 * age * age
            f = (1 - u) ** 1.5
            r = q[7] * f
            col = tuple(int(min(255, c * f * 1.15)) for c in q[6])
            gd.ellipse([x / 2 - r, y / 2 - r, x / 2 + r, y / 2 + r], fill=col)
            alive.append(q)
        self.p = alive

PARTS = Particles()


# ----------------------------------------------------------------- scenes
def ring(layer, cx, cy, radius, thick, prog, alpha=1.0, hot=0.0):
    ss = 2
    box = int((radius + thick) * 2.4)
    img = Image.new('RGBA', (box * ss, box * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = box * ss / 2
    r = radius * ss
    d.arc([c - r, c - r, c + r, c + r], 0, 360, fill=(56, 40, 36, 255), width=thick * ss)
    if prog > 0.001:
        col = tuple(int(lerp(o, hh, hot)) for o, hh in zip(ORANGE, ORANGE_HOT))
        d.arc([c - r, c - r, c + r, c + r], -90, -90 + 360 * prog,
              fill=col + (255,), width=thick * ss)
        a = math.radians(-90 + 360 * prog)
        tipx, tipy = c + r * math.cos(a), c + r * math.sin(a)
        tr = thick * ss * 0.62
        d.ellipse([tipx - tr, tipy - tr, tipx + tr, tipy + tr], fill=ORANGE_HOT + (255,))
    img = img.resize((box, box), Image.LANCZOS)
    paste(layer, img, cx, cy, 1.0, alpha)


def scene_hook(t, layer, gd):
    if t > T_PACK + 0.15:
        return
    fade = 1.0 if t < T_PACK - 0.25 else smooth(1, 0, (t - (T_PACK - 0.25)) / 0.4)
    p = ease_out_cubic(clamp((t - 0.12) / 1.25))
    prog = p * 0.87
    shrink = smooth(1.0, 0.55, (t - T_LINE2) / 0.55) if t > T_LINE2 else 1.0
    pulse = 1 + 0.05 * math.exp(-((t % BEAT) / 0.10))
    ring(layer, W // 2, 470, int(196 * shrink * pulse), max(3, int(34 * shrink)),
         prog, alpha=fade, hot=clamp((t - T_LINE2) / 0.4))
    n = int(prog * 100)
    text(layer, f'{n}%', W // 2, 470, 120, WHITE, 'anton',
         scale=shrink * pulse, alpha=fade)
    if t < T_LINE2:
        u = clamp((t - 0.42) / 0.36)
        text(layer, 'YOU BURN TOKENS', W // 2, 782, 86, WHITE, 'anton', track=6,
             glow=0.25, scale=lerp(1.25, 1.0, ease_out_back(u)) if u < 1 else 1.0,
             alpha=clamp(u * 2) * fade)
        text(layer, 'CLAUDE CODE  ·  CODEX  ·  CURSOR', W // 2, 874, 40, (215, 205, 199),
             'inter', weight=700, track=5, alpha=clamp((t - 0.6) * 2.4) * fade)
    else:
        u = clamp((t - T_LINE2) / 0.3)
        s = lerp(1.4, 1.0, ease_out_back(u)) if u < 1 else 1.0
        text(layer, 'YOU GET', W // 2, 760, 74, WHITE, 'anton', track=6,
             scale=s, alpha=fade)
        text(layer, 'CARDS', W // 2, 856, 108, ORANGE, 'anton', track=8, glow=0.55,
             scale=s, alpha=fade)
        text(layer, 'FOR CLAUDE CODE, CODEX AND CURSOR', W // 2, 946, 30, DIM, 'inter',
             weight=700, track=4, alpha=clamp((t - T_LINE2 - 0.15) * 3) * fade)
        gd.ellipse([W / 4 - 105, 470 / 2 - 105, W / 4 + 105, 470 / 2 + 105],
                   fill=tuple(int(c * 0.22 * fade) for c in ORANGE))


@lru_cache(maxsize=1)
def pack_img():
    w, h = 400, 560
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    grad = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        k = y / h
        gd.line([(0, y), (w, y)],
                fill=(int(lerp(232, 120, k)), int(lerp(132, 52, k)), int(lerp(92, 40, k)), 255))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=26, fill=255)
    img.paste(grad, (0, 0), mask)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=26, outline=(255, 205, 175, 220), width=4)
    d.line([(0, 92), (w, 92)], fill=(255, 220, 195, 90), width=3)
    ic = ICON.resize((150, 150), Image.LANCZOS)
    img.alpha_composite(ic, (w // 2 - 75, 175))
    t1 = text_img('RATION', 54, (26, 14, 12), 'anton', track=8)
    img.alpha_composite(t1, (w // 2 - t1.width // 2, 340))
    t2 = text_img('SET 01  ·  50 CREATURES', 24, (48, 22, 18), 'inter', weight=700, track=3)
    img.alpha_composite(t2, (w // 2 - t2.width // 2, 415))
    sheen = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon([(-60, h), (110, 0), (210, 0), (40, h)],
                                  fill=(255, 255, 255, 55))
    img.alpha_composite(sheen)
    return img


def scene_pack(t, layer, gd):
    if not (T_PACK - 0.2 <= t <= T_RIP + 0.5):
        return
    if t < T_RIP:
        u = clamp((t - (T_PACK - 0.2)) / 0.28)
        k = clamp((t - T_PACK) / (T_RIP - T_PACK))
        amp = 3 + 30 * k * k
        dx = math.sin(t * 47) * amp
        dy = math.cos(t * 39) * amp * 0.6
        rot = math.sin(t * 33) * 4 * (0.3 + k)
        s = lerp(0.35, 1.0, ease_out_back(u)) * (1 + 0.10 * k)
        paste(layer, pack_img(), W / 2 + dx, H / 2 + dy, s, clamp(u * 2), rot)
        r = 150 + 260 * k
        gd.ellipse([W / 4 - r / 2, H / 4 - r / 2, W / 4 + r / 2, H / 4 + r / 2],
                   fill=tuple(int(c * (0.25 + 0.75 * k)) for c in ORANGE))
        text(layer, 'OPENING', W // 2, 168, 46, DIM, 'inter', weight=700, track=10,
             alpha=clamp(u))
    else:
        u = clamp((t - T_RIP) / 0.45)
        half = pack_img()
        left = half.crop((0, 0, half.width // 2, half.height))
        right = half.crop((half.width // 2, 0, half.width, half.height))
        off = 300 * ease_out_cubic(u)
        a = 1 - u
        paste(layer, left, W / 2 - 100 - off, H / 2 + 40 * u, 1.0 + 0.3 * u, a, 22 * u)
        paste(layer, right, W / 2 + 100 + off, H / 2 + 40 * u, 1.0 + 0.3 * u, a, -22 * u)


def reveal_state(t, j):
    """Position/size/opacity of the j-th revealed card at time t, or None."""
    t0 = REVEAL_TIMES[j]
    fly = 0.20
    if t < t0 - fly:
        return None
    later = sum(1 for k in range(j + 1, len(REVEAL_TIMES)) if REVEAL_TIMES[k] <= t)
    side = (-1) ** j
    if t < t0:                                   # flying in
        u = ease_out_quart(clamp((t - (t0 - fly)) / fly))
        x = lerp(W / 2 + side * 900, W / 2, u)
        y = lerp(H / 2 + 260 * (1 if j % 3 else -1), H / 2 - 10, u)
        return dict(x=x, y=y, h=lerp(320, 700, u), rot=lerp(side * 38, 0, u),
                    spin=lerp(170, 0, u), alpha=clamp(u * 3), glow=0.15)
    age = t - t0
    settle = ease_out_back(clamp(age / 0.22))
    h = 700 * lerp(1.10, 1.0, settle)
    x, y, rot, alpha = W / 2, H / 2 - 10, 0.0, 1.0
    if later:                                    # pushed back into the fan
        k = ease_out_cubic(clamp(later / 3.0))
        ang = (later * 11) * side
        h = lerp(h, 330, k)
        x = lerp(x, W / 2 + side * (120 + 34 * later), k)
        y = lerp(y, H / 2 + 150 + 10 * later, k)
        rot = lerp(0, ang, k)
        alpha = max(0.0, 0.80 - 0.14 * (later - 1))
    return dict(x=x, y=y, h=h, rot=rot, spin=0.0, alpha=alpha,
                glow=max(0.0, 0.9 - age * 4))


def scene_reveals(t, layer, gd):
    if t < REVEAL_TIMES[0] - 0.25 or t > T_BINDER + 0.3:
        return
    out = 1.0 if t < T_BINDER else smooth(1, 0, (t - T_BINDER) / 0.22)
    shown = [j for j in range(len(REVEAL_TIMES)) if reveal_state(t, j)]
    for j in shown:
        st = reveal_state(t, j)
        if t < REVEAL_TIMES[j]:                       # ghost trail while flying in
            for back, a in ((0.055, 0.16), (0.028, 0.26)):
                gh = reveal_state(t - back, j)
                if gh:
                    draw_card(layer, gd, REVEAL_ORDER[j], gh['x'], gh['y'], gh['h'],
                              gh['rot'], gh['spin'], a * out, 0.0)
            col = META[REVEAL_ORDER[j]]['accent']
            u = clamp((REVEAL_TIMES[j] - t) / 0.2)
            for k in range(10):
                a0 = k * 36 + t * 40
                r0, r1 = 150 + 240 * u, 430 + 320 * u
                x0 = GW / 2 + math.cos(math.radians(a0)) * r0 / 2
                y0 = GW / 2 + math.sin(math.radians(a0)) * r0 / 2
                x1 = GW / 2 + math.cos(math.radians(a0)) * r1 / 2
                y1 = GW / 2 + math.sin(math.radians(a0)) * r1 / 2
                gd.line([(x0, y0), (x1, y1)], width=2,
                        fill=tuple(int(c * 0.22 * u) for c in col))
        draw_card(layer, gd, REVEAL_ORDER[j], st['x'], st['y'], st['h'], st['rot'],
                  st['spin'], st['alpha'] * out, st['glow'])
        age = t - REVEAL_TIMES[j]
        if 0 <= age < 0.26:                            # holo sheen over the new card
            k = age / 0.26
            cw = st['h'] * CARDS[REVEAL_ORDER[j]].width / CARDS[REVEAL_ORDER[j]].height
            x0 = (st['x'] - cw / 2 - 60) + (cw + 120) * k
            y0, y1 = (st['y'] - st['h'] / 2) / 2, (st['y'] + st['h'] / 2) / 2
            v = int(60 * math.sin(math.pi * k))
            gd.polygon([(x0 / 2 - 14, y1), (x0 / 2 + 14, y1),
                        (x0 / 2 + 52, y0), (x0 / 2 + 24, y0)], fill=(v, v, v))
    n = sum(1 for tt in REVEAL_TIMES if tt <= t)
    if n:
        last = max(tt for tt in REVEAL_TIMES if tt <= t)
        pop = 1 + 0.4 * math.exp(-(t - last) * 16)
        text(layer, f'{min(50, n + 25):02d} / 50', 200, 980, 62, WHITE, 'anton', track=4,
             scale=pop, alpha=out)
        text(layer, 'UNLOCKED', 200, 1032, 24, DIM, 'inter', weight=700, track=6, alpha=out)
    text(layer, 'SET 01', W - 170, 980, 62, ORANGE, 'anton', track=4, alpha=out)
    text(layer, 'CLAUDE CODE · CODEX · CURSOR', W - 260, 1032, 24, DIM, 'inter', weight=700, track=2, alpha=out)


BIND_RNG = np.random.default_rng(3)
BIND_START = [(float(BIND_RNG.uniform(-500, W + 500)), float(BIND_RNG.uniform(-600, H + 600)),
               float(BIND_RNG.uniform(-70, 70))) for _ in range(50)]

def grid_cell(k, cam):
    cols, rows = 10, 5
    gap = 9
    cw = (960 - gap * (cols - 1)) / cols
    ch = cw * 1.56
    gw = cols * cw + gap * (cols - 1)
    gh = rows * ch + gap * (rows - 1)
    c, r = k % cols, k // cols
    x = (W - gw) / 2 + c * (cw + gap) + cw / 2
    y = (H - gh) / 2 + 26 + r * (ch + gap) + ch / 2
    x = W / 2 + (x - W / 2) * cam
    y = H / 2 + (y - H / 2) * cam
    return x, y, ch * cam


def scene_binder(t, layer, gd):
    if not (T_BINDER - 0.05 <= t <= T_APP + 0.05):
        return
    e = t - T_BINDER
    cam = lerp(1.35, 1.0, ease_out_cubic(clamp(e / 1.7)))
    out = 1.0 if t < T_APP - 0.3 else smooth(1, 0, (t - (T_APP - 0.3)) / 0.3)
    for k in range(50):
        d = 0.011 * ((k * 17) % 50)
        u = ease_out_cubic(clamp((e - d) / 0.62))
        if u <= 0:
            continue
        gx, gy, gh = grid_cell(k, cam)
        sx, sy, srot = BIND_START[k]
        x, y = lerp(sx, gx, u), lerp(sy, gy, u)
        h = lerp(gh * 2.4, gh, u)
        draw_card(layer, gd, k, x, y, h, lerp(srot, 0, u), lerp(150, 0, u),
                  clamp(u * 2.2) * out, glow=0.5 * (1 - u))
    if e > 1.5:                                        # holo sweep across the wall
        s = (e - 1.5) / 1.5
        if s < 1:
            cx = lerp(-200, W + 200, s) / 2
            gd.polygon([(cx - 60, 0), (cx + 60, 0), (cx + 190, GW), (cx + 70, GW)],
                       fill=(70, 52, 44))
    u2 = clamp((e - 1.2) / 0.4)
    if u2 > 0:
        text(layer, '50 CREATURES', W // 2, 92, 78, WHITE, 'anton', track=6, glow=0.3,
             scale=lerp(1.3, 1.0, ease_out_back(u2)) if u2 < 1 else 1.0, alpha=u2 * out)
        text(layer, 'ONE LOCAL BINDER  ·  SET 01', W // 2, 1010, 32, ORANGE, 'inter',
             weight=700, track=8, alpha=clamp((e - 1.6) * 3) * out)


@lru_cache(maxsize=1)
def scrim():
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(210):
        d.line([(0, y), (W, y)], fill=(6, 5, 6, int(215 * (1 - y / 210) ** 1.4)))
    for y in range(180):
        d.line([(0, H - 1 - y), (W, H - 1 - y)], fill=(6, 5, 6, int(215 * (1 - y / 180) ** 1.4)))
    return img


def scene_app(t, layer, gd):
    if not (T_APP - 0.05 <= t <= T_CTA + 0.05):
        return
    e = t - T_APP
    out = 1.0 if t < T_CTA - 0.25 else smooth(1, 0, (t - (T_CTA - 0.25)) / 0.25)
    idx = min(len(APP_FRAMES) - 1, max(0, int(e * FPS)))
    fr = Image.open(f'{BUILD}/app/{APP_FRAMES[idx]}').convert('RGBA')
    s = lerp(0.97, 1.08, clamp(e / 2.5))
    paste(layer, fr, W / 2, H / 2 + 16, s, clamp(e * 6) * out)
    paste(layer, scrim(), W / 2, H / 2, 1.0, out)
    gd.ellipse([W / 4 - 260, H / 4 - 260, W / 4 + 260, H / 4 + 260],
               fill=tuple(int(c * 0.22 * out) for c in ORANGE))
    u = clamp((e - 0.1) / 0.3)
    text(layer, 'LIVE PLAN LIMITS, ALL TOOLS', W // 2, 84, 62, WHITE, 'anton', track=5, glow=0.35,
         scale=lerp(1.2, 1.0, ease_out_back(u)) if u < 1 else 1.0, alpha=u * out)
    text(layer, 'CLAUDE CODE · CODEX · CURSOR — ONE MENU BAR', W // 2, 1012, 29, WHITE,
         'inter', weight=700, track=4, alpha=clamp((e - 0.5) * 3) * out)


def scene_cta(t, layer, gd):
    if t < T_CTA - 0.05:
        return
    e = t - T_CTA
    fade = 1.0 if t < DUR - 0.45 else smooth(1, 0, (t - (DUR - 0.45)) / 0.45)
    for i, k in enumerate((12, 20, 28, 36, 44)):
        ang = -26 + i * 13
        x = W / 2 + (i - 2) * 190
        y = 790 + abs(i - 2) * 30 + math.sin(e * 1.5 + i) * 8
        draw_card(layer, gd, k, x, y, 330, ang, 0, 0.30 * clamp(e * 2) * fade)
    u = ease_out_back(clamp(e / 0.42))
    paste(layer, ICON, W / 2, 300, 0.30 * (u if e < 0.42 else 1.0), clamp(e * 4) * fade)
    text(layer, 'RATION', W // 2, 520, 150, WHITE, 'anton', track=10, glow=0.45,
         scale=lerp(1.25, 1.0, u) if e < 0.42 else 1.0, alpha=clamp(e * 4) * fade)
    text(layer, 'FREE  ·  OPEN SOURCE  ·  macOS', W // 2, 626, 34, (208, 198, 192), 'inter',
         weight=700, track=6, alpha=clamp((e - 0.25) * 3) * fade)
    text(layer, 'CLAUDE CODE  ·  CODEX  ·  CURSOR', W // 2, 680, 30, ORANGE, 'inter',
         weight=700, track=5, alpha=clamp((e - 0.35) * 3) * fade)
    text(layer, 'github.com/mcpeixoto/ration', W // 2, 966, 44, ORANGE, 'inter',
         weight=800, track=1, alpha=clamp((e - 0.4) * 3) * fade)
    gd.ellipse([W / 4 - 190, 300 / 2 - 190, W / 4 + 190, 300 / 2 + 190],
               fill=tuple(int(c * 0.20 * fade) for c in ORANGE))


# ----------------------------------------------------------------- frame assembly
def flash_at(t):
    f = 0.0
    for tt, amp in [(T_RIP, 1.0), (T_BINDER, 0.55), (T_CTA, 0.4)] + \
                   [(x, 0.16) for x in REVEAL_TIMES]:
        if t >= tt:
            f = max(f, amp * math.exp(-(t - tt) * 30))
    return f


def shake_at(t):
    s = 0.0
    for tt, amp in [(T_RIP, 26), (T_BINDER, 16)] + [(x, 7) for x in REVEAL_TIMES]:
        if 0 <= t - tt < 0.35:
            s = max(s, amp * math.exp(-(t - tt) * 13))
    if s < 0.4:
        return 0.0, 0.0
    return math.sin(t * 90) * s, math.cos(t * 77) * s


def spawn_events(t, dt):
    """Particle bursts fire once, as the timeline crosses their cue."""
    for j, tt in enumerate(REVEAL_TIMES):
        if t - dt < tt <= t:
            PARTS.burst(t, W / 2, H / 2 - 10, 16, META[REVEAL_ORDER[j]]['accent'],
                        speed=620, life=0.65, size=6)
    if t - dt < T_RIP <= t:
        PARTS.burst(t, W / 2, H / 2, 150, ORANGE_HOT, speed=1100, life=1.1, size=9)
        PARTS.burst(t, W / 2, H / 2, 60, WHITE, speed=700, life=0.9, size=6)
    if t - dt < T_BINDER <= t:
        PARTS.burst(t, W / 2, H / 2, 90, ORANGE, speed=900, life=1.0, size=7)
    if t - dt < T_CTA <= t:
        PARTS.burst(t, W / 2, 300, 70, ORANGE_HOT, speed=800, life=1.2, size=7)


def render_frame(i):
    t = i / FPS
    spawn_events(t, 1.0 / FPS)
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    glow = Image.new('RGB', (GW, GW), (0, 0, 0))
    gd = ImageDraw.Draw(glow)

    scene_hook(t, layer, gd)
    scene_pack(t, layer, gd)
    scene_reveals(t, layer, gd)
    scene_binder(t, layer, gd)
    scene_app(t, layer, gd)
    scene_cta(t, layer, gd)
    PARTS.draw(t, gd)

    glow = glow.filter(ImageFilter.GaussianBlur(7)).resize((W, H), Image.BILINEAR)
    frame = BASE + np.asarray(glow).astype(np.float32) * 0.95
    beat_k = 1 + 0.035 * math.exp(-((t % BEAT) / 0.09)) * (1 if T_RIP < t < T_APP else 0)
    frame *= beat_k
    img = Image.fromarray(np.clip(frame, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    img.alpha_composite(layer)

    out = np.asarray(img.convert('RGB')).astype(np.float32)
    f = flash_at(t)
    if f > 0.004:
        out = out + 255.0 * f * RADIAL
    if t < 0.25:                                   # open from black
        out *= ease_out_cubic(clamp(t / 0.25))
    out = out + grain_full(i % 6) * 3.2
    dx, dy = shake_at(t)
    z = 1.0
    if T_RIP < t < T_APP:
        z += 0.016 * math.exp(-((t % BEAT) / 0.085))
    for tt, amp in ((T_RIP, 0.09), (T_BINDER, 0.05), (T_CTA, 0.05)):
        if 0 <= t - tt < 0.5:
            z += amp * math.exp(-(t - tt) * 9)
    res = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGB')
    if dx or dy or z > 1.001:
        k = 1.0 / z
        res = res.transform((W, H), Image.AFFINE,
                            (k, 0, dx + W * (1 - k) / 2, 0, k, dy + H * (1 - k) / 2),
                            Image.BILINEAR)
    return res


def main():
    if '--preview' in sys.argv:
        for s in sys.argv[sys.argv.index('--preview') + 1:]:
            i = int(float(s) * FPS)
            for k in range(0, i + 1):              # keep particle state consistent
                if k == i:
                    render_frame(k).save(f'{BUILD}/preview_{float(s):05.2f}.png')
                else:
                    spawn_events(k / FPS, 1.0 / FPS)
            print('preview', s)
        return

    cmd = ['ffmpeg', '-y', '-v', 'error',
           '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
           '-i', f'{BUILD}/track.wav',
           '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-profile:v', 'high', '-level', '4.1', '-movflags', '+faststart',
           '-c:a', 'aac', '-b:a', '192k', '-shortest',
           f'{BUILD}/ration-teaser-raw.mp4']
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(NF):
        p.stdin.write(render_frame(i).tobytes())
        if i % 120 == 0:
            print(f'  {i}/{NF}', flush=True)
    p.stdin.close()
    p.wait()
    print('done')


if __name__ == '__main__':
    main()
