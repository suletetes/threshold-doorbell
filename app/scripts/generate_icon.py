#!/usr/bin/env python3
"""
Threshold branded app icon generator.

Produces two 1024x1024 PNGs using only Python stdlib (no Pillow, no Cairo):
  assets/icon/app_icon.png           -- full icon (background + foreground)
  assets/icon/app_icon_foreground.png -- foreground only (transparent bg)

The icon is a stylised doorbell button with a speech-bubble waveform, drawn
in brand blue (#1565C0) against the dark navy background (#0C0E13).

Run from the app/ directory:
  python scripts/generate_icon.py
Then:
  dart run flutter_launcher_icons
"""

import os
import struct
import zlib
import math

# ---------------------------------------------------------------------------
# Brand constants
# ---------------------------------------------------------------------------
SIZE = 1024
BG_COLOR = (0x0C, 0x0E, 0x13, 0xFF)      # dark navy -- app background
BRAND_BLUE = (0x15, 0x65, 0xC0, 0xFF)    # brand primary blue
BLUE_LIGHT = (0xA9, 0xC7, 0xFF, 0xFF)    # inversePrimary / highlight
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
TRANSPARENT = (0x00, 0x00, 0x00, 0x00)


# ---------------------------------------------------------------------------
# Minimal PNG writer (no dependencies)
# ---------------------------------------------------------------------------

def _chunk(tag: bytes, data: bytes) -> bytes:
    c = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", c)


def encode_png(pixels: list, width: int, height: int) -> bytes:
    """Encode a list of (R,G,B,A) tuples as a PNG bytestring."""
    raw_rows = []
    for y in range(height):
        row = b"\x00"  # filter type None
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            row += bytes([r, g, b, a])
        raw_rows.append(row)
    compressed = zlib.compress(b"".join(raw_rows), level=9)
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr_data)
        + _chunk(b"IDAT", compressed)
        + _chunk(b"IEND", b"")
    )


# ---------------------------------------------------------------------------
# Rasterisation helpers (pure math, no external deps)
# ---------------------------------------------------------------------------

def lerp(a, b, t):
    return a + (b - a) * t


def srgb_blend(src, dst):
    """Alpha-composite src over dst (premultiplied in float)."""
    sa = src[3] / 255.0
    da = dst[3] / 255.0
    out_a = sa + da * (1 - sa)
    if out_a < 1e-6:
        return TRANSPARENT
    out_r = int((src[0] * sa + dst[0] * da * (1 - sa)) / out_a)
    out_g = int((src[1] * sa + dst[1] * da * (1 - sa)) / out_a)
    out_b = int((src[2] * sa + dst[2] * da * (1 - sa)) / out_a)
    out_aa = int(out_a * 255)
    return (
        max(0, min(255, out_r)),
        max(0, min(255, out_g)),
        max(0, min(255, out_b)),
        max(0, min(255, out_aa)),
    )


def aa_circle(cx, cy, r, px, py):
    """Anti-aliased coverage of pixel (px,py) for a filled circle."""
    # Sample 4x4 grid inside the pixel
    coverage = 0.0
    for sy in range(4):
        for sx in range(4):
            spx = px + (sx + 0.5) / 4.0
            spy = py + (sy + 0.5) / 4.0
            dist = math.sqrt((spx - cx) ** 2 + (spy - cy) ** 2)
            if dist <= r:
                coverage += 1.0
    return coverage / 16.0


def aa_ring(cx, cy, r_outer, r_inner, px, py):
    """Anti-aliased coverage for a ring (annulus)."""
    coverage = 0.0
    for sy in range(4):
        for sx in range(4):
            spx = px + (sx + 0.5) / 4.0
            spy = py + (sy + 0.5) / 4.0
            dist = math.sqrt((spx - cx) ** 2 + (spy - cy) ** 2)
            if r_inner <= dist <= r_outer:
                coverage += 1.0
    return coverage / 16.0


def aa_rounded_rect(x0, y0, x1, y1, radius, px, py):
    """Anti-aliased coverage for a filled rounded rectangle."""
    coverage = 0.0
    for sy in range(4):
        for sx in range(4):
            spx = px + (sx + 0.5) / 4.0
            spy = py + (sy + 0.5) / 4.0
            # Distance from point to rounded-rect edge
            qx = max(x0 + radius, min(spx, x1 - radius)) - spx
            qy = max(y0 + radius, min(spy, y1 - radius)) - spy
            # Inside the rect body
            if (x0 <= spx <= x1) and (y0 <= spy <= y1):
                corner_dist = math.sqrt(qx * qx + qy * qy)
                if corner_dist <= radius or (abs(qx) < 1e-6 or abs(qy) < 1e-6):
                    coverage += 1.0
                    continue
                # Check corners
                if (spx < x0 + radius or spx > x1 - radius) and (
                    spy < y0 + radius or spy > y1 - radius
                ):
                    if math.sqrt(qx * qx + qy * qy) <= radius:
                        coverage += 1.0
    return coverage / 16.0


def paint_color(pixels, width, height, x, y, color, coverage):
    """Blend color at (x,y) with given coverage (0..1)."""
    if x < 0 or x >= width or y < 0 or y >= height:
        return
    src = (color[0], color[1], color[2], int(color[3] * coverage))
    idx = y * width + x
    pixels[idx] = srgb_blend(src, pixels[idx])


# ---------------------------------------------------------------------------
# Icon drawing
# ---------------------------------------------------------------------------

def draw_icon(include_background: bool) -> list:
    """Draw the Threshold icon. Returns flat pixel list."""
    pixels = [TRANSPARENT] * (SIZE * SIZE)
    cx = SIZE / 2.0
    cy = SIZE / 2.0

    # --- Background (skip for foreground-only layer) ---
    if include_background:
        bg = BG_COLOR
        for i in range(SIZE * SIZE):
            pixels[i] = bg

        # Subtle radial vignette: slightly lighter in centre
        vignette_r = SIZE * 0.45
        for y in range(SIZE):
            for x in range(SIZE):
                dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
                t = max(0.0, 1.0 - dist / vignette_r)
                if t > 0:
                    alpha = int(t * 18)   # very subtle
                    src = (0xFF, 0xFF, 0xFF, alpha)
                    pixels[y * SIZE + x] = srgb_blend(src, pixels[y * SIZE + x])

    # --- Outer glow ring (blue, very transparent) ---
    glow_r = SIZE * 0.44
    glow_w = SIZE * 0.04
    for y in range(SIZE):
        for x in range(SIZE):
            cov = aa_ring(cx, cy, glow_r + glow_w, glow_r - glow_w, x + 0.5, y + 0.5)
            if cov > 0:
                paint_color(pixels, SIZE, SIZE, x, y,
                            (BRAND_BLUE[0], BRAND_BLUE[1], BRAND_BLUE[2], 60), cov)

    # --- Doorbell button: large filled circle ---
    bell_r = SIZE * 0.35
    for y in range(SIZE):
        for x in range(SIZE):
            cov = aa_circle(cx, cy, bell_r, x + 0.5, y + 0.5)
            if cov > 0:
                paint_color(pixels, SIZE, SIZE, x, y, BRAND_BLUE, cov)

    # --- Inner highlight arc (top-left quarter, lighter blue) ---
    hl_r = bell_r * 0.88
    hl_ring_w = bell_r * 0.08
    for y in range(SIZE):
        for x in range(SIZE):
            cov = aa_ring(cx, cy, hl_r + hl_ring_w, hl_r - hl_ring_w,
                          x + 0.5, y + 0.5)
            if cov > 0 and (x < cx) and (y < cy):  # top-left quadrant
                paint_color(pixels, SIZE, SIZE, x, y,
                            (BLUE_LIGHT[0], BLUE_LIGHT[1], BLUE_LIGHT[2], 180), cov)

    # --- Sound-wave bars (white, centred, 5 vertical bars) ---
    # Bars represent the "two-way audio / caption" concept of the product.
    bar_count = 5
    bar_w = SIZE * 0.028
    bar_gap = SIZE * 0.036
    total_w = bar_count * bar_w + (bar_count - 1) * bar_gap
    bar_x0 = cx - total_w / 2.0

    # Heights (tallest in centre, shorter on sides)
    heights = [0.10, 0.17, 0.24, 0.17, 0.10]

    for i, h_frac in enumerate(heights):
        bx0 = bar_x0 + i * (bar_w + bar_gap)
        bx1 = bx0 + bar_w
        bh = SIZE * h_frac
        by0 = cy - bh / 2.0
        by1 = cy + bh / 2.0
        bar_radius = bar_w / 2.0

        for y in range(int(by0) - 2, int(by1) + 3):
            for x in range(int(bx0) - 2, int(bx1) + 3):
                if 0 <= x < SIZE and 0 <= y < SIZE:
                    cov = aa_rounded_rect(bx0, by0, bx1, by1, bar_radius,
                                         x + 0.5, y + 0.5)
                    if cov > 0:
                        paint_color(pixels, SIZE, SIZE, x, y, WHITE, cov)

    # --- Small doorbell button dot below bars ---
    dot_r = SIZE * 0.030
    dot_cy = cy + SIZE * 0.18
    for y in range(SIZE):
        for x in range(SIZE):
            cov = aa_circle(cx, dot_cy, dot_r, x + 0.5, y + 0.5)
            if cov > 0:
                paint_color(pixels, SIZE, SIZE, x, y, WHITE, cov)

    return pixels


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    app_dir = os.path.dirname(script_dir)
    icon_dir = os.path.join(app_dir, "assets", "icon")
    os.makedirs(icon_dir, exist_ok=True)

    print("Generating full icon (background + foreground)...")
    full_pixels = draw_icon(include_background=True)
    full_png = encode_png(full_pixels, SIZE, SIZE)
    full_path = os.path.join(icon_dir, "app_icon.png")
    with open(full_path, "wb") as f:
        f.write(full_png)
    print(f"  Written {len(full_png):,} bytes -> {full_path}")

    print("Generating foreground layer (transparent background)...")
    fg_pixels = draw_icon(include_background=False)
    fg_png = encode_png(fg_pixels, SIZE, SIZE)
    fg_path = os.path.join(icon_dir, "app_icon_foreground.png")
    with open(fg_path, "wb") as f:
        f.write(fg_png)
    print(f"  Written {len(fg_png):,} bytes -> {fg_path}")

    print()
    print("Done. Now run from the app/ directory:")
    print("  dart run flutter_launcher_icons")


if __name__ == "__main__":
    main()
