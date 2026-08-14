#!/usr/bin/env python3
"""The vault field's design mock and fixture generator.

This is the source the two native ports mirror (`AsciiFieldVault` in
ios/CashuWallet/Views/Components/AsciiField.swift and
android/.../ui/onboarding/AsciiField.kt) and the generator for the parity
vectors pasted into `AsciiFieldVaultTests` / `AsciiFieldVaultTest`. Retuning
the vault is a keep-in-lockstep edit of this file, both platform files, and
both test files — run it, eyeball the render, paste the regenerated vectors.

All ops are float64, matching Swift/Kotlin Double. Stencil indexing rounds
half toward +∞ (`floor(v + 0.5)`) — Kotlin `Math.round` semantics; Swift must
NOT use its half-away `.rounded()`. The fixture pins both boundary signs.

The glyphs printed here are terminal stand-ins for the real ramp
(levels 0-2 = · / ,   level 3 = $¥€ by position hash   level 4 = ₿).
"""
import math

CELL_W, CELL_H = 12.0, 14.0
LEVEL_MIN = [40, 90, 140, 200, 216]
PEAK_BOOST = 208
GLYPH = ["·", "/", ",", "$", "₿"]

# --- Vault constants (grid units: pt/dp; fixed size — the vault recenters,
# --- never scales) ---
OUTER_R = 146.0
OUTER_W = 11.0
OUTER_B = 196.0
INNER_R = 92.0
INNER_W = 9.0
INNER_B = 168.0
FACE_R = 152.0
FACE_B = 52.0
SPOKE_MIN_D = 24.0
SPOKE_MAX_D = 96.0
SPOKE_B = 176.0
SPOKE_ARC = 8.0
BOLT_R = 121.0
BOLT_HALF = 8.0
BOLT_B = 212.0
# 221, not a rounder number: at LIVE_GAIN 0.28 the monogram shows ₿ ~83% of
# the time with ~8 glyph trades/sec across its cells — one point lower reads
# $-heavy, one higher goes static (measured against the terrain's own
# liveliness; see the tuning notes in the PR that introduced the living ink).
STENCIL_PEAK_B = 221.0
STENCIL_CURRENCY_B = 202.0
# The living ink: the vault's brightness is modulated by the *live terrain
# brightness at the same cell* — the landing screen's ridgelines keep
# crawling through the door's structure. Terrain's motion is its contour
# cliffs (the mod-spacing discontinuity), which no amount of smooth noise
# shimmer reproduces; borrowing the terrain field wholesale is what makes the
# vault move exactly like the welcome screen.
LIVE_GAIN = 0.28
LIVE_PIVOT = 128.0
EXTENT_RADIUS = OUTER_R + OUTER_W  # 157: beyond this, ink < 40 — never draws
# Outside the vault the ink is LIVE_GAIN·(terrain − LIVE_PIVOT) alone, whose
# maximum 0.28·(255−128) = 35.6 sits under the first draw threshold (40) —
# the renderer's settled-vault fast path skips those cells and relies on it.

# The central ₿ monogram: 2 = peak ink, 1 = currency-strength ink.
STENCIL = [
    "....2....",
    ".222222..",
    ".2....22.",
    ".2.....2.",
    ".2....22.",
    ".222222..",
    ".2....22.",
    ".2.....2.",
    ".2....22.",
    ".222222..",
    "....2....",
]


def noise(x, y, t):
    """AsciiFieldTerrain.noise, verbatim web."""
    return (math.sin(0.8 * x + 0.3 * t) * math.cos(0.6 * y + 0.2 * t) * 0.5
            + 0.25 * math.sin(1.6 * x + 1.2 * y + 0.15 * t)
            + math.sin(0.3 * x - 0.4 * t) * math.cos(0.4 * y + 0.25 * t) * 0.6
            + 0.3 * math.sin(0.5 * (x + y) + 0.35 * t)
            + math.sin(2.5 * x + 0.1 * t) * math.cos(2.8 * y - 0.12 * t) * 0.15)


def ring(d, r, w):
    return max(0.0, 1.0 - abs(d - r) / w)


def vault_brightness(px, py, cx, cy, t):
    dx, dy = px - cx, py - cy
    d = math.hypot(dx, dy)
    b = 0.0
    if d < FACE_R:
        b = FACE_B
    b = max(b, OUTER_B * ring(d, OUTER_R, OUTER_W))
    b = max(b, INNER_B * ring(d, INNER_R, INNER_W))
    ang = math.atan2(dy, dx)
    if SPOKE_MIN_D < d < SPOKE_MAX_D:
        a = (ang + math.pi) % (math.pi / 3)
        arc = min(a, math.pi / 3 - a) * d
        b = max(b, SPOKE_B * max(0.0, 1.0 - arc / SPOKE_ARC))
    a12 = (ang + math.pi) % (math.pi / 6)
    bolt_d = math.hypot(d - BOLT_R, min(a12, math.pi / 6 - a12) * BOLT_R)
    if bolt_d < BOLT_HALF:
        b = max(b, BOLT_B)
    col = int(math.floor(dx / CELL_W + 0.5)) + len(STENCIL[0]) // 2
    row = int(math.floor(dy / CELL_H + 0.5)) + len(STENCIL) // 2
    if 0 <= row < len(STENCIL) and 0 <= col < len(STENCIL[0]):
        c = STENCIL[row][col]
        if c == "2":
            b = max(b, STENCIL_PEAK_B)
        elif c == "1":
            b = max(b, STENCIL_CURRENCY_B)
    # Same cell→noise mapping the renderer uses for the terrain itself, so a
    # warped vault sample rides the identical warped terrain sample.
    tb = terrain_brightness(px / CELL_W * 0.13, py / CELL_H * 0.13, t)
    return b + LIVE_GAIN * (tb - LIVE_PIVOT)


def level(b):
    if b >= PEAK_BOOST:
        return 4
    for i in range(len(LEVEL_MIN) - 1, -1, -1):
        if b >= LEVEL_MIN[i]:
            return i
    return -1


def render(cx, cy, t, cols=33, rows=26):
    top = cy - rows * CELL_H / 2
    out = []
    for row in range(rows):
        py = top + row * CELL_H + CELL_H / 2
        line = []
        for colx in range(cols):
            px = colx * CELL_W + CELL_W / 2
            lv = level(vault_brightness(px, py, cx, cy, t))
            line.append(GLYPH[lv] if lv >= 0 else " ")
        out.append(" ".join(line))
    return "\n".join(out)


# Terrain (verbatim web) for the one full-pipeline mixed fixture.
def fractal(x, y, t):
    return (noise(x, y, t) + 0.4 * noise(2.2 * x, 2.2 * y, 0.7 * t)
            + 0.15 * noise(4.5 * x, 4.5 * y, 0.4 * t))


def terrain_brightness(x, y, t):
    r = min(1.0, max(0.0, (fractal(x, y, t) + 1.8) / 3.6))
    s = (r % 0.08) / 0.08
    on_contour = s < 0.12 or s > 0.88
    b = math.floor((200 * r + 55) + 0.5) if on_contour else math.floor(140 * r + 0.5)
    if on_contour:
        gx = noise(x + 0.01, y, t) - noise(x - 0.01, y, t)
        gy = noise(x, y + 0.01, t) - noise(x, y - 0.01, t)
        dd = 12 * math.hypot(gx, gy)
        if dd > 0.5:
            b = min(255, b + math.floor(40 * dd + 0.5))
    return int(b)


if __name__ == "__main__":
    print(render(cx=195.0, cy=300.0, t=2.5))
    print()
    CX, CY = 195.0, 300.0
    print("=== Parity vectors (px, py, t) -> brightness, level  [cx=195, cy=300] ===")
    pts = [
        (195.0, 154.0, 2.5),   # outer ring top
        (195.0, 300.0, 2.5),   # hub: stencil peak
        (195.0, 258.0, 2.5),   # face fill above the wheel
        (243.0, 300.0, 2.5),   # horizontal spoke
        (195.0, 208.0, 2.5),   # inner ring top
        (287.0, 300.0, 2.5),   # inner ring on the spoke axis
        (261.0, 300.0, 2.5),   # mid-spoke
        (247.0, 248.0, 2.5),   # off-spoke face fill
        (316.0, 300.0, 2.5),   # bolt center -> peak boost
        (309.0, 235.0, 2.5),   # between bolts
        (195.0, 450.0, 2.5),   # face edge below the wheel
        (30.0, 60.0, 2.5),     # far outside: living ink alone, sub-threshold
        (201.0, 307.0, 0.0),   # +half-cell stencil boundary (dx=W/2, dy=H/2)
        (189.0, 293.0, 0.0),   # -half-cell stencil boundary (dx=-W/2, dy=-H/2)
        (219.0, 244.0, 2.5),   # stencil top bar, right reach
        (159.0, 300.0, 2.5),   # stencil left bar
    ]
    for (px, py, t) in pts:
        b = vault_brightness(px, py, CX, CY, t)
        print(f"  ({px:7.1f}, {py:7.1f}, t={t}) -> {b!r}   level={level(b)}")

    print()
    print("=== Full-pipeline mixed pin (mix 0.5) ===")
    px, py, t = 219.0, 328.0, 2.5
    sx, sy = px / CELL_W * 0.13, py / CELL_H * 0.13
    tb = terrain_brightness(sx, sy, t)
    v = vault_brightness(px, py, CX, CY, t)
    mixed = tb + (v - tb) * 0.5
    print(f"  terrain({sx!r}, {sy!r}) = {tb}")
    print(f"  vault({px}, {py}) = {v!r}")
    print(f"  mixed@0.5 = {mixed!r}   level={level(mixed)}")
