#!/usr/bin/env python3
"""Deterministic, dependency-free launcher-icon generator for Caller's Compendium.

This environment has no SVG rasterizer (rsvg-convert / inkscape / imagemagick /
cairosvg / node) and no Pillow. The brand mark is pure geometry (two rounded
bars on a rounded tile), so we render it directly with the Python standard
library only: an analytic rounded-rectangle signed-distance field for crisp
anti-aliased coverage, and hand-rolled PNG / ICO encoders (zlib + struct).

Everything is derived from ONE 128-unit "Progression bars" glyph so all
platforms stay in sync. Outputs (PNGs, the Windows .ico, and the two Android
vector drawables) are generated here and committed; this script does NOT run in
CI. Re-run from the repo root:  python3 tools/brand/generate_icons.py

See app/assets/brand/README.md for the concept, palette and geometry.
"""

from __future__ import annotations

import math
import os
import struct
import zlib
from typing import List, Optional, Sequence, Tuple

# --- repo layout ------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
APP = os.path.join(REPO, "app")

# --- palette (exact values from app/lib/src/theme/color_schemes.dart) -------
PETROL = (0x12, 0x1A, 0x24, 255)         # dark surface / "Blue Hour" petrol
AMBER = (0xFF, 0xB7, 0x84, 255)          # dark primary — lantern amber
LIGHT_SURFACE = (0xF4, 0xF6, 0xFA, 255)  # light scheme surface (light tile)
LIGHT_PRIMARY = (0x9A, 0x53, 0x12, 255)  # light primary (light-ground bars)

# --- canonical glyph geometry, 128-unit box ---------------------------------
# left bar and right bar (right stepped UP -> progression up the set).
# (x, y, w, h, r)
LEFT_BAR = (38.0, 44.0, 18.0, 56.0, 9.0)
RIGHT_BAR = (72.0, 28.0, 18.0, 56.0, 9.0)
TILE_RADIUS = 28.4                       # rounded tile corner radius in 128 box
UNIT = 128.0

Rect = Tuple[float, float, float, float, float]
Op = Tuple[Rect, Tuple[int, int, int, int]]


def glyph_ops(bar_color: Tuple[int, int, int, int]) -> List[Op]:
    return [(LEFT_BAR, bar_color), (RIGHT_BAR, bar_color)]


def scale_rect(r: Rect, s: float, cx: float = 64.0, cy: float = 64.0) -> Rect:
    x, y, w, h, rad = r
    return (cx + s * (x - cx), cy + s * (y - cy), w * s, h * s, rad * s)


def scale_ops(ops: Sequence[Op], s: float) -> List[Op]:
    return [(scale_rect(r, s), c) for r, c in ops]


# --- rounded-rectangle signed distance field --------------------------------
def rrect_sdf(px: float, py: float, rect: Rect) -> float:
    """<0 inside, >0 outside; magnitude in glyph units."""
    x, y, w, h, r = rect
    r = max(0.0, min(r, w / 2.0, h / 2.0))
    cx, cy = x + w / 2.0, y + h / 2.0
    hx, hy = w / 2.0, h / 2.0
    dx = abs(px - cx) - (hx - r)
    dy = abs(py - cy) - (hy - r)
    ox, oy = max(dx, 0.0), max(dy, 0.0)
    outside = math.hypot(ox, oy)
    inside = min(max(dx, dy), 0.0)
    return outside + inside - r


def render(size: int, ops: Sequence[Op],
           opaque_bg: Optional[Tuple[int, int, int, int]]) -> bytearray:
    """Render ops (in 128-unit space) to `size`x`size` RGBA bytes.

    Coverage is analytic: a ~1px anti-alias band from the rounded-rect SDF
    (equivalent to very high supersampling but O(pixels) instead of O(samples)).
    `opaque_bg`, when given, fills the canvas first and forces alpha 255.
    """
    px_unit = UNIT / size          # glyph units per output pixel
    out = bytearray(size * size * 4)

    if opaque_bg is not None:
        br, bgc, bb, _ = opaque_bg
        base = (float(br), float(bgc), float(bb), 255.0)
    else:
        base = (0.0, 0.0, 0.0, 0.0)

    for j in range(size):
        gy = (j + 0.5) * px_unit
        row = j * size * 4
        for i in range(size):
            gx = (i + 0.5) * px_unit
            r_acc, g_acc, b_acc, a_acc = base
            for rect, (sr, sg, sb, sa) in ops:
                d = rrect_sdf(gx, gy, rect)
                cov = 0.5 - d / px_unit
                if cov <= 0.0:
                    continue
                if cov > 1.0:
                    cov = 1.0
                a = (sa / 255.0) * cov
                if a <= 0.0:
                    continue
                inv = 1.0 - a
                r_acc = sr * a + r_acc * inv
                g_acc = sg * a + g_acc * inv
                b_acc = sb * a + b_acc * inv
                a_acc = sa * cov + a_acc * inv
            o = row + i * 4
            out[o] = int(r_acc + 0.5)
            out[o + 1] = int(g_acc + 0.5)
            out[o + 2] = int(b_acc + 0.5)
            out[o + 3] = 255 if opaque_bg is not None else int(a_acc + 0.5)
    return out


# --- PNG encoder ------------------------------------------------------------
def _chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def encode_png(size: int, rgba: bytes, rgb_only: bool = False) -> bytes:
    if rgb_only:
        color_type = 2
        stride = size * 3
        raw = bytearray((stride + 1) * size)
        p = 0
        for j in range(size):
            raw[p] = 0
            p += 1
            src = j * size * 4
            for i in range(size):
                s = src + i * 4
                raw[p] = rgba[s]
                raw[p + 1] = rgba[s + 1]
                raw[p + 2] = rgba[s + 2]
                p += 3
    else:
        color_type = 6
        stride = size * 4
        raw = bytearray((stride + 1) * size)
        p = 0
        for j in range(size):
            raw[p] = 0
            p += 1
            src = j * stride
            raw[p:p + stride] = rgba[src:src + stride]
            p += stride
    comp = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, color_type, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", comp) + _chunk(b"IEND", b""))


def write_png(path: str, size: int, ops, opaque_bg=None, rgb_only=False) -> None:
    rgba = render(size, ops, opaque_bg)
    with open(path, "wb") as f:
        f.write(encode_png(size, rgba, rgb_only=rgb_only))
    print(f"  png {size:>4}px  {os.path.relpath(path, REPO)}")


# --- ICO encoder ------------------------------------------------------------
def _bmp_dib(size: int, rgba: bytes) -> bytes:
    """32-bit BGRA BMP (DIB) with AND mask, for ICO entries < 256px."""
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    pix = bytearray(size * size * 4)
    p = 0
    for j in range(size - 1, -1, -1):  # bottom-up
        src = j * size * 4
        for i in range(size):
            s = src + i * 4
            pix[p] = rgba[s + 2]      # B
            pix[p + 1] = rgba[s + 1]  # G
            pix[p + 2] = rgba[s]      # R
            pix[p + 3] = rgba[s + 3]  # A
            p += 4
    mask_stride = ((size + 31) // 32) * 4
    mask = bytes(mask_stride * size)  # all-zero: opaque via alpha channel
    return header + bytes(pix) + mask


def write_ico(path: str, sizes: Sequence[int], ops, opaque_bg=None) -> None:
    entries = []
    for s in sorted(sizes):
        rgba = render(s, ops, opaque_bg)
        data = encode_png(s, rgba) if s >= 256 else _bmp_dib(s, rgba)
        entries.append((s, data))
    count = len(entries)
    header = struct.pack("<HHH", 0, 1, count)
    offset = 6 + 16 * count
    dir_bytes = b""
    blob = b""
    for s, data in entries:
        w = h = 0 if s >= 256 else s
        dir_bytes += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(data), offset)
        blob += data
        offset += len(data)
    with open(path, "wb") as f:
        f.write(header + dir_bytes + blob)
    print(f"  ico       {os.path.relpath(path, REPO)}  sizes={sorted(sizes)}")


# --- Android vector drawable path data --------------------------------------
def _fmt(n: float) -> str:
    s = f"{n:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def rrect_path(rect: Rect) -> str:
    x, y, w, h, r = rect
    r = max(0.0, min(r, w / 2.0, h / 2.0))
    f = _fmt
    return (
        f"M{f(x + r)},{f(y)}"
        f"L{f(x + w - r)},{f(y)}"
        f"A{f(r)},{f(r)},0,0,1,{f(x + w)},{f(y + r)}"
        f"L{f(x + w)},{f(y + h - r)}"
        f"A{f(r)},{f(r)},0,0,1,{f(x + w - r)},{f(y + h)}"
        f"L{f(x + r)},{f(y + h)}"
        f"A{f(r)},{f(r)},0,0,1,{f(x)},{f(y + h - r)}"
        f"L{f(x)},{f(y + r)}"
        f"A{f(r)},{f(r)},0,0,1,{f(x + r)},{f(y)}Z"
    )


def android_vector(color_hex: str, ops: Sequence[Op]) -> str:
    paths = "\n".join(
        f'    <path\n        android:fillColor="{color_hex}"\n'
        f'        android:pathData="{rrect_path(rect)}" />'
        for rect, _ in ops
    )
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by tools/brand/generate_icons.py — do not edit by hand. -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        f"{paths}\n"
        "</vector>\n"
    )


def write_text(path: str, text: str) -> None:
    # Force UTF-8 + LF regardless of the host OS so regenerating on Windows vs
    # macOS/Linux yields byte-identical files (the XML comments contain an
    # em-dash, and Windows would otherwise default to CRLF / cp1252).
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"  xml       {os.path.relpath(path, REPO)}")


# --- scenes -----------------------------------------------------------------
# Full-color rounded tile: petrol tile (rx 28.4) + amber glyph, transparent
# surround. Used for Android legacy mipmaps and the Windows .ico.
ROUNDED_OPS: List[Op] = [((0.0, 0.0, UNIT, UNIT, TILE_RADIUS), PETROL)] + glyph_ops(AMBER)
# iOS: full-bleed opaque petrol square + amber glyph (no alpha, no rounding —
# iOS applies its own superellipse mask). Petrol supplied via opaque_bg.
IOS_OPS: List[Op] = glyph_ops(AMBER)
# macOS: the rounded tile scaled to ~80% (Apple's ~10% transparent margin).
MACOS_OPS: List[Op] = scale_ops(ROUNDED_OPS, 0.80)

# Android adaptive foreground / monochrome: glyph mapped into the 108 viewport
# at scale 0.80 about (64,64) so it lands inside the 66dp themed safe circle.
FG_SCALE = 0.80
FG_LEFT = (54.0 + FG_SCALE * (38.0 - 64.0), 54.0 + FG_SCALE * (44.0 - 64.0),
           18.0 * FG_SCALE, 56.0 * FG_SCALE, 9.0 * FG_SCALE)
FG_RIGHT = (54.0 + FG_SCALE * (72.0 - 64.0), 54.0 + FG_SCALE * (28.0 - 64.0),
            18.0 * FG_SCALE, 56.0 * FG_SCALE, 9.0 * FG_SCALE)
FG_OPS: List[Op] = [(FG_LEFT, AMBER), (FG_RIGHT, AMBER)]


def android(res: str) -> None:
    print("Android:")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, s in legacy.items():
        write_png(os.path.join(res, f"mipmap-{dpi}", "ic_launcher.png"), s, ROUNDED_OPS)
    drawable = os.path.join(res, "drawable")
    os.makedirs(drawable, exist_ok=True)
    write_text(os.path.join(drawable, "ic_launcher_foreground.xml"),
               android_vector("#FFB784", FG_OPS))
    # Monochrome layer (Android 13+ themed icons): flat black; the system tints it.
    write_text(os.path.join(drawable, "ic_launcher_monochrome.xml"),
               android_vector("#000000", FG_OPS))
    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n'
    )
    write_text(os.path.join(anydpi, "ic_launcher.xml"), adaptive)
    values = os.path.join(res, "values")
    os.makedirs(values, exist_ok=True)
    write_text(os.path.join(values, "colors.xml"),
               '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
               '    <color name="ic_launcher_background">#121A24</color>\n</resources>\n')


def ios(root: str) -> None:
    print("iOS:")
    d = os.path.join(root, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    files = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167, "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, s in files.items():
        write_png(os.path.join(d, name), s, IOS_OPS, opaque_bg=PETROL, rgb_only=True)


def macos(root: str) -> None:
    print("macOS:")
    d = os.path.join(root, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for s in (16, 32, 64, 128, 256, 512, 1024):
        write_png(os.path.join(d, f"app_icon_{s}.png"), s, MACOS_OPS)


def windows(root: str) -> None:
    print("Windows:")
    p = os.path.join(root, "windows", "runner", "resources", "app_icon.ico")
    write_ico(p, (16, 24, 32, 48, 64, 128, 256), ROUNDED_OPS)


def main() -> None:
    android(os.path.join(APP, "android", "app", "src", "main", "res"))
    ios(APP)
    macos(APP)
    windows(APP)
    print("done.")


if __name__ == "__main__":
    main()
