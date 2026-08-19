"""Original chiptune bed + SFX for the Ration teaser. 128 BPM, 22 s, 48 kHz stereo."""
import os
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'track.wav')

SR = 48000
BPM = 128.0
BEAT = 60.0 / BPM          # 0.46875 s
BAR = 4 * BEAT             # 1.875 s
DUR = 22.0
N = int(DUR * SR)

L = np.zeros(N, dtype=np.float32)
R = np.zeros(N, dtype=np.float32)


def t_of(beat):
    return beat * BEAT


def add(buf_l, buf_r, sig, t, pan=0.0, gain=1.0):
    i = int(t * SR)
    if i >= N:
        return
    s = sig[: N - i] * gain
    buf_l[i:i + len(s)] += s * (1.0 - max(0.0, pan))
    buf_r[i:i + len(s)] += s * (1.0 + min(0.0, pan))


def env(n, a=0.002, d=0.08, s=0.0, r=0.05, sus=0.0):
    """Simple ADSR over n samples."""
    e = np.zeros(n, dtype=np.float32)
    ai, di, ri = int(a * SR), int(d * SR), int(r * SR)
    ai = min(ai, n); di = min(di, max(0, n - ai)); ri = min(ri, max(0, n - ai - di))
    si = max(0, n - ai - di - ri)
    p = 0
    if ai: e[p:p + ai] = np.linspace(0, 1, ai); p += ai
    if di: e[p:p + di] = np.linspace(1, s if s else sus, di); p += di
    if si: e[p:p + si] = s if s else sus; p += si
    if ri: e[p:p + ri] = np.linspace(e[p - 1] if p else 1, 0, ri)
    return e


def note_hz(semi):
    """Semitones relative to A4 = 440."""
    return 440.0 * 2 ** (semi / 12.0)


def pulse(freq, dur, duty=0.5, detune=0.0):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    ph = (tt * freq * (1 + detune)) % 1.0
    return np.where(ph < duty, 1.0, -1.0).astype(np.float32)


def tri(freq, dur):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    ph = (tt * freq) % 1.0
    return (4 * np.abs(ph - 0.5) - 1).astype(np.float32)


def noise(dur):
    n = int(dur * SR)
    rng = np.random.default_rng(int(dur * 1e6) % 99991)
    return rng.standard_normal(n).astype(np.float32)


def lp(x, cutoff):
    """One-pole low-pass."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):          # short buffers only
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def hp(x, cutoff):
    return x - lp(x, cutoff)


# ---------------------------------------------------------------- drums
def kick(dur=0.28):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    f = 130 * np.exp(-tt * 32) + 46
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-tt * 9)
    click = noise(0.008) * np.exp(-np.arange(int(0.008 * SR)) / SR * 400)
    out = body.astype(np.float32)
    out[:len(click)] += click * 0.5
    return np.tanh(out * 1.7) * 0.95


def snare(dur=0.22):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    nz = hp(noise(dur), 900) * np.exp(-tt * 22)
    tone = (np.sin(2 * np.pi * 190 * tt) + np.sin(2 * np.pi * 330 * tt)) * np.exp(-tt * 30) * 0.4
    return (nz * 0.9 + tone).astype(np.float32) * 0.8


def hat(dur=0.05, open_=False):
    d = 0.16 if open_ else dur
    n = int(d * SR)
    tt = np.arange(n) / SR
    return (hp(noise(d), 6000) * np.exp(-tt * (14 if open_ else 60))).astype(np.float32) * 0.35


def crash(dur=1.4):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    return (hp(noise(dur), 3500) * np.exp(-tt * 3.2)).astype(np.float32) * 0.5


# ---------------------------------------------------------------- musical material
# A minor: i VI III VII  ->  Am F C G  (roots as semitones from A4)
PROG = [-24, -29, -21, -26]          # A2, F2, C3, G2  (bar roots)
CHORD = {-24: [0, 3, 7], -29: [0, 4, 7], -21: [0, 4, 7], -26: [0, 4, 7]}

# section boundaries, in beats
B_DROP = 8          # 3.75 s   pack rip
B_REVEAL_END = 28   # 13.125 s
B_BREAK = 37.333    # 17.5 s   app footage
B_CTA = 42.667      # 20.0 s
B_END = 47.0

beat = 0.0
bar_i = 0
while beat < B_END:
    b_in_bar = int(beat) % 4
    root = PROG[(int(beat) // 4) % 4]
    drop = beat >= B_DROP
    peak = B_REVEAL_END <= beat < B_BREAK
    brk = B_BREAK <= beat < B_CTA
    cta = beat >= B_CTA

    # --- drums
    if drop and not brk:
        if b_in_bar in (0, 2) or (peak and b_in_bar == 3):
            add(L, R, kick(), t_of(beat), gain=1.0)
        if b_in_bar in (1, 3):
            add(L, R, snare(), t_of(beat), gain=0.75 if not peak else 0.9)
        for k in range(2):
            add(L, R, hat(open_=(k == 1 and b_in_bar == 3)), t_of(beat + k * 0.5),
                pan=0.25 if k else -0.25, gain=0.8)
    elif brk:
        if b_in_bar == 0:
            add(L, R, kick(), t_of(beat), gain=0.6)
        add(L, R, hat(), t_of(beat + 0.5), gain=0.4)

    # --- bass: eighth-note chip bass
    if drop:
        for k in range(2):
            f = note_hz(root + (12 if (k and b_in_bar in (1, 3)) else 0))
            d = BEAT * 0.46
            sig = pulse(f, d, duty=0.5) * env(int(d * SR), a=0.003, d=d * 0.9, r=0.03)
            add(L, R, sig.astype(np.float32), t_of(beat + k * 0.5),
                gain=0.30 if not brk else 0.16)

    # --- chord stabs
    if drop and b_in_bar in (0, 2) and not brk:
        for iv in CHORD[root]:
            f = note_hz(root + 24 + iv)
            d = BEAT * 0.42
            sig = pulse(f, d, duty=0.25) * env(int(d * SR), a=0.004, d=d, r=0.04)
            add(L, R, sig.astype(np.float32), t_of(beat), pan=0.15 * (iv - 3) / 4,
                gain=0.11 if not peak else 0.14)

    # --- lead: 16th arpeggio, pentatonic, doubles at the peak
    if drop and not brk:
        scale = [0, 3, 5, 7, 10, 12, 15, 12, 10, 7, 5, 3]
        for k in range(4):
            step = int((beat * 4 + k)) % len(scale)
            semi = root + 36 + scale[step]
            if peak:
                semi += 0 if k % 2 else 12
            d = BEAT * 0.22
            sig = pulse(note_hz(semi), d, duty=0.32, detune=0.004 * (k % 2))
            sig = sig * env(int(d * SR), a=0.002, d=d * 0.8, r=0.02)
            add(L, R, sig.astype(np.float32), t_of(beat + k * 0.25),
                pan=-0.3 + 0.2 * k, gain=0.085 if not peak else 0.105)
    elif brk:
        if b_in_bar == 0:
            for iv in CHORD[root]:
                f = note_hz(root + 24 + iv)
                d = BEAT * 3.2
                sig = tri(f, d) * env(int(d * SR), a=0.08, d=d, r=0.4)
                add(L, R, sig.astype(np.float32), t_of(beat), gain=0.09)

    # --- intro: sparse pluck + rising tension before the drop
    if not drop:
        semi = root + 36 + [0, 7, 3, 10][int(beat) % 4]
        d = BEAT * 0.5
        sig = tri(note_hz(semi), d) * env(int(d * SR), a=0.004, d=d, r=0.05)
        add(L, R, sig.astype(np.float32), t_of(beat), gain=0.13)

    beat += 1.0

# --- riser into the drop, crash on the drop and on the binder peak
ris_d = BEAT * 4
n = int(ris_d * SR)
tt = np.arange(n) / SR
sweep = np.sin(2 * np.pi * np.cumsum(300 + 2400 * (tt / ris_d) ** 2) / SR).astype(np.float32)
riser = (hp(noise(ris_d), 1500) * 0.5 + sweep * 0.4) * (tt / ris_d) ** 2
add(L, R, riser.astype(np.float32), t_of(B_DROP) - ris_d, gain=0.42)
add(L, R, crash(), t_of(B_DROP), gain=0.75)
add(L, R, crash(1.8), t_of(B_REVEAL_END), gain=0.8)
add(L, R, kick(0.4), t_of(B_REVEAL_END), gain=1.0)

# --- final CTA stab: Am chord ring-out
for iv in (0, 3, 7, 12):
    d = 2.0
    sig = (pulse(note_hz(-12 + iv), d, duty=0.4) * 0.5 + tri(note_hz(-12 + iv), d) * 0.5)
    sig = sig * env(int(d * SR), a=0.005, d=1.6, r=0.4)
    add(L, R, sig.astype(np.float32), t_of(B_CTA), pan=0.1 * iv / 12, gain=0.10)
add(L, R, kick(0.45), t_of(B_CTA), gain=1.0)
add(L, R, crash(1.9), t_of(B_CTA), gain=0.7)

# ---------------------------------------------------------------- SFX
def whoosh(dur=0.30, up=True):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    f = np.linspace(400, 5000, n) if up else np.linspace(4000, 500, n)
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25 + hp(noise(dur), 800) * 0.6
    shape = np.sin(np.pi * tt / dur) ** 1.6
    return (sig * shape).astype(np.float32)


def impact(dur=0.18):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (90 * np.exp(-tt * 20) + 55) * tt) * np.exp(-tt * 26)
    tick = hp(noise(0.02), 4000) * np.exp(-np.arange(int(0.02 * SR)) / SR * 260)
    out = thump.astype(np.float32) * 0.8
    out[:len(tick)] += tick * 0.6
    return out


def sparkle(dur=0.7, seed=1):
    n = int(dur * SR)
    out = np.zeros(n, dtype=np.float32)
    rng = np.random.default_rng(seed)
    for k in range(9):
        f = note_hz(24 + rng.integers(0, 12) + 12 * rng.integers(0, 2))
        d = 0.12
        s = (np.sin(2 * np.pi * f * np.arange(int(d * SR)) / SR)
             * np.exp(-np.arange(int(d * SR)) / SR * 26)).astype(np.float32)
        off = int(rng.uniform(0, dur - d) * SR)
        out[off:off + len(s)] += s * 0.35
    return out


def rip(dur=0.5):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    tear = hp(noise(dur), 2200) * np.exp(-tt * 7) * (1 + 0.6 * np.sin(2 * np.pi * 60 * tt))
    boom = np.sin(2 * np.pi * (70 * np.exp(-tt * 14) + 40) * tt) * np.exp(-tt * 8)
    return (tear * 0.7 + boom * 0.9).astype(np.float32)


# pack shake ticks, then the rip on the drop
for k in range(4):
    add(L, R, impact(0.10), t_of(B_DROP - 2 + k * 0.5), gain=0.25 + 0.1 * k)
add(L, R, rip(), t_of(B_DROP), gain=0.9)
add(L, R, sparkle(1.0, seed=7), t_of(B_DROP) + 0.05, gain=0.5)

# one whoosh + impact per revealed card
reveal_beats = list(np.arange(B_DROP + 1, 22, 1.0)) + list(np.arange(22, B_REVEAL_END, 0.5))
for i, b in enumerate(reveal_beats):
    add(L, R, whoosh(0.22), t_of(b) - 0.16, pan=(-0.35 if i % 2 else 0.35), gain=0.30)
    add(L, R, impact(), t_of(b), gain=0.45)
    if i % 4 == 3:
        add(L, R, sparkle(0.5, seed=i), t_of(b), gain=0.35)

# binder assembly: layered whooshes + a shimmer wash
for k in range(8):
    add(L, R, whoosh(0.35, up=(k % 2 == 0)), t_of(B_REVEAL_END) + k * 0.10,
        pan=-0.4 + 0.1 * k, gain=0.22)
add(L, R, sparkle(1.6, seed=21), t_of(B_REVEAL_END) + 0.15, gain=0.45)
add(L, R, whoosh(0.5, up=False), t_of(B_BREAK) - 0.4, gain=0.35)
add(L, R, whoosh(0.4), t_of(B_CTA) - 0.35, gain=0.4)

# ---------------------------------------------------------------- master
def master(x):
    x = np.tanh(x * 1.05)
    fade = np.ones(N, dtype=np.float32)
    f = int(0.9 * SR)
    fade[-f:] = np.linspace(1, 0, f)
    fade[:int(0.02 * SR)] = np.linspace(0, 1, int(0.02 * SR))
    return x * fade

L, R = master(L), master(R)
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * 0.94, R / peak * 0.94

stereo = np.stack([L, R], axis=1)
pcm = (stereo * 32767).astype(np.int16)
with wave.open(OUT, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('wrote', OUT, round(len(pcm) / SR, 2), 's  peak', round(float(peak), 3))
