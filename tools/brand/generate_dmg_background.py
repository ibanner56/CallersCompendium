#!/usr/bin/env python3
"""Background art for the macOS installer disk image (the ``.dmg`` window).

The window that opens when a user double-clicks the ``.dmg`` is laid out by
``packaging/macos/dmg_settings.py``: the app icon on the left, an
``Applications`` shortcut on the right, at fixed positions. This script draws
the picture behind them — a heading, an arrow from the app's slot to the
Applications slot, and a one-line hint about what to do after copying — so the
window says what to do instead of leaving a bare icon and folder.

The geometry is read from ``dmg_settings.py`` itself (``WINDOW_SIZE``,
``APP_POS``, ``APPLICATIONS_POS``, ``ICON_SIZE``), so moving an icon there and
re-running this script keeps the arrow pointing between the two icons.
``tools/release/test_macos_dmg.py`` fails if the committed images no longer
match that geometry's size.

Outputs (committed; the release job only reads them):

* ``packaging/macos/dmg-background.png``    — 1x, ``WINDOW_SIZE`` pixels
* ``packaging/macos/dmg-background@2x.png`` — 2x, for Retina displays

``dmgbuild`` finds the ``@2x`` sibling by name and combines the pair into one
multi-resolution TIFF with ``tiffutil`` at build time.

Dependencies (local only — this script does **not** run in CI):
``Pillow`` (``pip install pillow``). Fonts are the app's own bundled
``Fraunces`` (heading) and ``Atkinson Hyperlegible`` (body) from
``app/assets/fonts/``.

Re-run from the repo root::

    python3 tools/brand/generate_dmg_background.py
"""

from __future__ import annotations

import ast
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
PACKAGING = ROOT / "packaging" / "macos"
SETTINGS = PACKAGING / "dmg_settings.py"
FONTS = ROOT / "app" / "assets" / "fonts"

# Palette: exact values from app/lib/src/theme/color_schemes.dart (light scheme).
SURFACE = (0xF4, 0xF6, 0xFA)
SURFACE_HIGHEST = (0xE3, 0xE8, 0xEF)
ON_SURFACE = (0x1A, 0x22, 0x2C)
ON_SURFACE_VARIANT = (0x48, 0x51, 0x5C)
PRIMARY = (0x9A, 0x53, 0x12)        # lantern amber, light-scheme primary
OUTLINE_VARIANT = (0xC7, 0xCD, 0xD6)

HEADING = "Install Caller’s Compendium"
INSTRUCTION = "Drag the app onto the Applications folder"
FOOTER = "Then open Caller’s Compendium from your Applications folder."

# Draw at this multiple of the 2x output and downsample, for smooth curves.
SUPERSAMPLE = 2


def layout() -> dict[str, tuple[int, ...] | int]:
    """Read the window geometry constants out of dmg_settings.py.

    Parsed with ``ast`` rather than executed: the settings file is written for
    dmgbuild's loader, which supplies a ``defines`` mapping this script has no
    business inventing.
    """
    wanted = {"WINDOW_SIZE", "APP_POS", "APPLICATIONS_POS", "ICON_SIZE"}
    found: dict[str, tuple[int, ...] | int] = {}
    tree = ast.parse(SETTINGS.read_text(encoding="utf-8"), filename=str(SETTINGS))
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name) and target.id in wanted:
                found[target.id] = ast.literal_eval(node.value)
    missing = wanted - found.keys()
    if missing:
        raise SystemExit(f"{SETTINGS.name} does not define {sorted(missing)}")
    return found


def font(name: str, size: float, variation: str | None = None) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(str(FONTS / name), round(size))
    if variation:
        face.set_variation_by_name(variation)
    return face


def centered_text(draw: ImageDraw.ImageDraw, cx: float, y: float, text: str,
                  face: ImageFont.FreeTypeFont, fill: tuple[int, int, int]) -> None:
    left, _, right, _ = draw.textbbox((0, 0), text, font=face)
    draw.text((cx - (right - left) / 2 - left, y), text, font=face, fill=fill)


def bezier(p0, p1, p2, steps: int = 200) -> list[tuple[float, float]]:
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    return pts


def render(scale: int) -> Image.Image:
    """Render the background at ``scale`` pixels per point."""
    geo = layout()
    width, height = geo["WINDOW_SIZE"]
    app_x, app_y = geo["APP_POS"]
    apps_x, apps_y = geo["APPLICATIONS_POS"]
    icon = geo["ICON_SIZE"]
    s = scale * SUPERSAMPLE  # pixels per point while drawing

    img = Image.new("RGB", (width * s, height * s), SURFACE)

    # A barely-there vertical wash, lighter at the top, so the window does not
    # read as a flat grey sheet.
    wash = Image.linear_gradient("L").resize((width * s, height * s))
    lower = Image.new("RGB", img.size, SURFACE_HIGHEST)
    img = Image.composite(lower, img, wash.point(lambda v: v * 0.55))

    # Soft "slots" under each icon: a hint of where things sit and where the
    # app should land, without competing with the icons themselves.
    slots = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(slots)
    r = icon * 0.62 * s
    for cx, cy in ((app_x, app_y), (apps_x, apps_y)):
        sd.ellipse((cx * s - r, cy * s - r, cx * s + r, cy * s + r), fill=255)
    slots = slots.filter(ImageFilter.GaussianBlur(18 * s))
    img = Image.composite(Image.new("RGB", img.size, (0xFF, 0xFF, 0xFF)), img,
                          slots.point(lambda v: v * 0.85))

    draw = ImageDraw.Draw(img)
    cx = width / 2

    # Heading and instruction, above the icon row.
    centered_text(draw, cx * s, 34 * s, HEADING,
                  font("Fraunces-VariableFont.ttf", 26 * s, b"SemiBold"), ON_SURFACE)
    centered_text(draw, cx * s, 74 * s, INSTRUCTION,
                  font("AtkinsonHyperlegible-Regular.ttf", 15 * s), ON_SURFACE_VARIANT)

    # Arrow from the app slot to the Applications slot: a gentle arc that clears
    # both icons, in the brand's amber.
    gap = icon / 2 + 22
    start = (app_x + gap, app_y)
    end = (apps_x - gap, apps_y)
    control = ((start[0] + end[0]) / 2, app_y - 34)
    path = [(x * s, y * s) for x, y in bezier(start, control, end, steps=600)]
    stroke = 4.5 * s
    # Stamped round dabs rather than a wide polyline: Pillow's line joins leave
    # visible notches on a curve this gentle.
    for x, y in path:
        draw.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2),
                     fill=PRIMARY)
    # Arrowhead aligned with the curve's final tangent.
    (x1, y1), (x2, y2) = path[-20], path[-1]
    angle = math.atan2(y2 - y1, x2 - x1)
    head_len, head_half = 20 * s, 12 * s
    tip = (x2 + math.cos(angle) * head_len * 0.75, y2 + math.sin(angle) * head_len * 0.75)
    back = (tip[0] - math.cos(angle) * head_len, tip[1] - math.sin(angle) * head_len)
    normal = (-math.sin(angle), math.cos(angle))
    draw.polygon([
        tip,
        (back[0] + normal[0] * head_half, back[1] + normal[1] * head_half),
        (back[0] - normal[0] * head_half, back[1] - normal[1] * head_half),
    ], fill=PRIMARY)

    # Divider and follow-up hint, below the icon labels, clear of the bottom
    # edge.
    footer_y = height - 74
    draw.line(((cx - 150) * s, (footer_y - 14) * s, (cx + 150) * s, (footer_y - 14) * s),
              fill=OUTLINE_VARIANT, width=max(1, s))
    centered_text(draw, cx * s, footer_y * s, FOOTER,
                  font("AtkinsonHyperlegible-Regular.ttf", 13 * s), ON_SURFACE_VARIANT)

    return img.resize((width * scale, height * scale), Image.LANCZOS)


def main() -> None:
    for scale, name in ((1, "dmg-background.png"), (2, "dmg-background@2x.png")):
        out = PACKAGING / name
        image = render(scale)
        # Finder reads the HiDPI pair by pixel size; 72/144 dpi keeps Preview
        # and tiffutil agreeing on the point size too.
        image.save(out, optimize=True, dpi=(72 * scale, 72 * scale))
        print(f"wrote {out.relative_to(ROOT)} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
