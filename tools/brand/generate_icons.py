#!/usr/bin/env python3
"""Launcher-icon generator for Caller's Compendium — "Dancers rising from a book".

The brand mark is now a full-colour illustration (two role-neutral dancers
spinning up out of an open book), so — unlike the previous pure-geometry mark —
it can no longer be rendered from the Python standard library alone. This script
rasterises the committed SVG sources in ``app/assets/brand/`` and composites the
per-platform tiles.

Dependencies (local only — this script does **not** run in CI; its outputs are
committed):

* ``librsvg`` / ``rsvg-convert`` on ``PATH`` (SVG rasteriser)
* ``Pillow`` (``pip install pillow``) for compositing + the Windows ``.ico``

Policy (see app/assets/brand/README.md):

* Full illustration is used at >= 48 px; the simplified two-dancers-on-a-book
  "small mark" is used at <= 32 px so it stays legible.
* The default tile everywhere is **Soft Dark** (``#1E2A38``). iOS additionally
  ships Dark and Tinted appearance variants (Any = Soft Dark).
* Android keeps an adaptive icon (Soft Dark background + full-illustration
  foreground) plus a monochrome themed layer (the small-mark silhouette).

Re-run from the repo root::

    python3 tools/brand/generate_icons.py
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from typing import List, Sequence, Tuple

from PIL import Image

# --- repo layout ------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
APP = os.path.join(REPO, "app")
BRAND = os.path.join(APP, "assets", "brand")

# --- palette (exact values from app/lib/src/theme/color_schemes.dart) -------
SOFT_DARK = "#1E2A38"   # default tile — Soft Dark scheme surface
DARK = "#121A24"        # dark scheme surface (iOS Dark variant)
LIGHT = "#F4F6FA"       # light scheme surface
TILE_RADIUS_RATIO = 28.4 / 128.0  # rounded-tile corner radius (~22.2%)

# Small-mark crossover: at or below this pixel size use the simplified mark.
SMALL_MAX = 32
# At or below this pixel size, scale the small mark up so its content sits a
# single pixel from the tile edge at the narrowest side (maximum legibility at
# the tiniest icon slots — Windows .ico 16px, macOS 16pt).
TIGHT_FIT_MAX = 16
TIGHT_FIT_BORDER_PX = 1


# --- brand source content ---------------------------------------------------
def _inner(svg_name: str, strip_bg: bool = True) -> str:
    s = open(os.path.join(BRAND, svg_name), encoding="utf-8").read()
    body = s[s.index(">", s.index("<svg")) + 1: s.rindex("</svg>")]
    if strip_bg:
        body = re.sub(r'<rect width="2048" height="2048"[^>]*/>', "", body, count=1)
    return body.strip()


FULL = _inner("mark.svg")               # full illustration, transparent, vb 2048
SMALL_CREAM = _inner("mark-small.svg")  # simplified mark, cream pages
SMALL_TAN = _inner("mark-small-light.svg")  # simplified mark, tan pages (light bg)


def content_for(size: int, light: bool = False) -> str:
    if size <= SMALL_MAX:
        return SMALL_TAN if light else SMALL_CREAM
    return FULL


# --- rasterisation ----------------------------------------------------------
_BBOX_CACHE: dict = {}


def _content_bbox(content: str):
    """Tight (x0, y0, x1, y1) alpha bounding box of `content`, in 2048 units."""
    if content in _BBOX_CACHE:
        return _BBOX_CACHE[content]
    probe = 1024
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2048 2048" '
        'width="%d" height="%d">%s</svg>' % (probe, probe, content)
    )
    box = rasterize(svg, probe).split()[3].getbbox()  # alpha channel bbox
    scale = 2048.0 / probe
    bbox = tuple(v * scale for v in box)
    _BBOX_CACHE[content] = bbox
    return bbox


def _fit_transform(content: str, size: int, border_px: int) -> str:
    """Wrap `content` so its bbox sits `border_px` from the edge at the narrowest
    side of a `size`x`size` render (uniform scale, centred)."""
    x0, y0, x1, y1 = _content_bbox(content)
    w, h = x1 - x0, y1 - y0
    border = 2048.0 * border_px / size  # border expressed in 2048 units
    avail = 2048.0 - 2.0 * border
    f = avail / max(w, h)
    tx = (2048.0 - w * f) / 2.0 - x0 * f
    ty = (2048.0 - h * f) / 2.0 - y0 * f
    return '<g transform="translate(%.4f %.4f) scale(%.6f)">%s</g>' % (
        tx, ty, f, content,
    )


def _compose_svg(size: int, content: str, bg, rounded: bool) -> str:
    tile = ""
    if bg is not None:
        if rounded:
            r = 2048 * TILE_RADIUS_RATIO
            tile = '<rect width="2048" height="2048" rx="%.3f" fill="%s"/>' % (r, bg)
        else:
            tile = '<rect width="2048" height="2048" fill="%s"/>' % bg
    if size <= TIGHT_FIT_MAX:
        content = _fit_transform(content, size, TIGHT_FIT_BORDER_PX)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2048 2048" '
        'width="%d" height="%d">%s%s</svg>' % (size, size, tile, content)
    )


def rasterize(svg: str, size: int) -> Image.Image:
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
        path = f.name
    try:
        out = path + ".png"
        subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), path, "-o", out],
            check=True,
        )
        return Image.open(out).convert("RGBA").copy()
    finally:
        os.unlink(path)
        if os.path.exists(path + ".png"):
            os.unlink(path + ".png")


def render_tile(size: int, bg, rounded: bool, light: bool = False) -> Image.Image:
    """Composited tile: (optional) background + size-appropriate content."""
    return rasterize(_compose_svg(size, content_for(size, light), bg, rounded), size)


def write_png(path: str, img: Image.Image, rgb: bool = False) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    if rgb:  # iOS wants opaque, no alpha
        Image.open(path).convert("RGB").save(path, "PNG")
    print("  png %4dpx  %s" % (img.width, os.path.relpath(path, REPO)))


def write_text(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("  txt        %s" % os.path.relpath(path, REPO))


# --- Android VectorDrawable (flatten transforms into path coords) -----------
# Content lives in a 2048 box; adaptive layers map it into the 108 viewport,
# scaled 0.80 about centre so it lands inside the 66dp themed safe circle:
#   q = p * (108/2048) * 0.80 + 54*(1 - 0.80)
_K = (108.0 / 2048.0) * 0.80
_T = 54.0 * (1.0 - 0.80)


def _fmt(n: float) -> str:
    s = ("%.3f" % n).rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def _flatten_d(d: str) -> str:
    # The committed brand SVGs are pre-baked to transform-free, *absolute*
    # M/L/C/Z paths (see app/assets/brand/*.svg), so every number is an (x, y)
    # coordinate the uniform 108-viewport map applies to. Both letter cases are
    # accepted (Z/z close) so a stray lowercase close is never dropped.
    out: List[str] = []
    for cmd, args in re.findall(r"([MLCZmlcz])([^MLCZmlcz]*)", d):
        upper = cmd.upper()
        if upper == "Z":
            out.append("Z")
            continue
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", args)]
        mapped = [_fmt(v * _K + _T) for v in nums]  # uniform k,t on every coord
        out.append(upper + ("" if not mapped else " " + " ".join(mapped)))
    return "".join(out)


def _rgb_to_hex(fill: str) -> str:
    m = re.match(r"rgb\((\d+),\s*(\d+),\s*(\d+)\)", fill)
    if not m:
        return fill if fill.startswith("#") else "#000000"
    return "#{:02X}{:02X}{:02X}".format(*(int(x) for x in m.groups()))


def _paths_from(content: str, force_color) -> List[Tuple[str, str]]:
    result = []
    for p in re.findall(r"<path[^>]*/>", content):
        d = re.search(r'd="([^"]*)"', p).group(1)
        fill = re.search(r'fill="([^"]*)"', p)
        color = force_color or _rgb_to_hex(fill.group(1) if fill else "#000000")
        result.append((color, _flatten_d(d)))
    return result


def android_vector(content: str, force_color) -> str:
    paths = "\n".join(
        '    <path\n        android:fillColor="%s"\n'
        '        android:pathData="%s" />' % (color, d)
        for color, d in _paths_from(content, force_color)
    )
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Generated by tools/brand/generate_icons.py \u2014 do not edit by hand. -->\n"
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n    android:height="108dp"\n'
        '    android:viewportWidth="108"\n    android:viewportHeight="108">\n'
        "%s\n</vector>\n" % paths
    )


# --- ICO (Pillow) -----------------------------------------------------------
def write_ico(path: str, sizes: Sequence[int]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ordered = sorted(sizes)
    imgs = [render_tile(s, SOFT_DARK, rounded=True) for s in ordered]
    imgs[-1].save(path, format="ICO", sizes=[(s, s) for s in ordered],
                  append_images=imgs[:-1])
    print("  ico        %s  sizes=%s" % (os.path.relpath(path, REPO), ordered))


# --- platforms --------------------------------------------------------------
def android(res: str) -> None:
    print("Android:")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, s in legacy.items():
        write_png(os.path.join(res, "mipmap-%s" % dpi, "ic_launcher.png"),
                  render_tile(s, SOFT_DARK, rounded=True))
    drawable = os.path.join(res, "drawable")
    write_text(os.path.join(drawable, "ic_launcher_foreground.xml"),
               android_vector(FULL, force_color=None))
    write_text(os.path.join(drawable, "ic_launcher_monochrome.xml"),
               android_vector(SMALL_CREAM, force_color="#000000"))
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        "</adaptive-icon>\n"
    )
    write_text(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), adaptive)
    write_text(os.path.join(res, "values", "colors.xml"),
               '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
               '    <color name="ic_launcher_background">%s</color>\n'
               "</resources>\n" % SOFT_DARK)


def ios(root: str) -> None:
    print("iOS:")
    d = os.path.join(root, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith(".png"):
                os.unlink(os.path.join(d, f))
    any_img = render_tile(1024, SOFT_DARK, rounded=False)   # Any = Soft Dark
    dark_img = render_tile(1024, DARK, rounded=False)       # Dark
    tinted = render_tile(1024, DARK, rounded=False).convert("L").convert("RGBA")
    write_png(os.path.join(d, "Icon-App-1024.png"), any_img, rgb=True)
    write_png(os.path.join(d, "Icon-App-1024-dark.png"), dark_img, rgb=True)
    write_png(os.path.join(d, "Icon-App-1024-tinted.png"), tinted, rgb=True)
    contents = (
        '{\n  "images" : [\n'
        '    {\n      "filename" : "Icon-App-1024.png",\n'
        '      "idiom" : "universal",\n      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n    },\n'
        '    {\n      "appearances" : [\n        {\n'
        '          "appearance" : "luminosity",\n          "value" : "dark"\n        }\n      ],\n'
        '      "filename" : "Icon-App-1024-dark.png",\n'
        '      "idiom" : "universal",\n      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n    },\n'
        '    {\n      "appearances" : [\n        {\n'
        '          "appearance" : "luminosity",\n          "value" : "tinted"\n        }\n      ],\n'
        '      "filename" : "Icon-App-1024-tinted.png",\n'
        '      "idiom" : "universal",\n      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    write_text(os.path.join(d, "Contents.json"), contents)


def macos(root: str) -> None:
    print("macOS:")
    d = os.path.join(root, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for s in (16, 32, 64, 128, 256, 512, 1024):
        margin = round(s * 0.10)
        inner = s - 2 * margin
        tile = render_tile(inner, SOFT_DARK, rounded=True)
        canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        canvas.paste(tile, (margin, margin), tile)
        write_png(os.path.join(d, "app_icon_%d.png" % s), canvas)


def windows(root: str) -> None:
    print("Windows:")
    write_ico(os.path.join(root, "windows", "runner", "resources", "app_icon.ico"),
              (16, 24, 32, 48, 64, 128, 256))


def linux_packaging() -> None:
    print("Linux packaging:")
    write_png(os.path.join(REPO, "packaging", "linux", "icon.png"),
              render_tile(512, SOFT_DARK, rounded=True))


def main() -> None:
    android(os.path.join(APP, "android", "app", "src", "main", "res"))
    ios(APP)
    macos(APP)
    windows(APP)
    linux_packaging()
    print("done.")


if __name__ == "__main__":
    main()
