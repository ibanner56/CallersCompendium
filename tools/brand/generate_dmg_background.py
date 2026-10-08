#!/usr/bin/env python3
"""Background art for the macOS installer disk image (the ``.dmg`` window).

The window that opens when a user double-clicks the ``.dmg`` is laid out by
``packaging/macos/dmg_settings.py``: the app icon on the left, an
``Applications`` shortcut on the right, at fixed positions. This script draws
the picture behind them — a heading, an arrow from the app's slot to the
Applications slot, and a one-line hint about what to do after copying — so the
window says what to do instead of leaving a bare icon and folder.

The arrow is pressed into the background (an inset with a shadowed upper rim
and a lit lower rim), with the brand's small mark — the one the Collection
pane shows when no dance is selected — standing raised on its floor. The two
icons get a soft hovering shadow. Finder draws the icons themselves on top of
this picture, so their shadows are painted here, shaped to each icon's visible
outline at its fixed position.

The geometry is read from ``dmg_settings.py`` itself (``WINDOW_SIZE``,
``APP_POS``, ``APPLICATIONS_POS``, ``ICON_SIZE``), so moving an icon there and
re-running this script keeps the arrow and shadows with the icons.
``tools/release/test_macos_dmg.py`` fails if the committed images no longer
match that geometry's size.

Outputs (committed; the release job only reads them):

* ``packaging/macos/dmg-background.png``    — 1x, ``WINDOW_SIZE`` pixels
* ``packaging/macos/dmg-background@2x.png`` — 2x, for Retina displays

``dmgbuild`` finds the ``@2x`` sibling by name and combines the pair into one
multi-resolution TIFF with ``tiffutil`` at build time.

Dependencies (local only — this script does **not** run in CI):
``Pillow`` and ``cairosvg`` (``pip install pillow cairosvg``; the latter
rasterises ``app/assets/brand/mark-small.svg``). Fonts are the app's own
bundled ``Fraunces`` (heading) and ``Atkinson Hyperlegible`` (body) from
``app/assets/fonts/``.

Re-run from the repo root::

    python3 tools/brand/generate_dmg_background.py
"""

from __future__ import annotations

import ast
import io
import math
from pathlib import Path

import cairosvg
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
PACKAGING = ROOT / "packaging" / "macos"
SETTINGS = PACKAGING / "dmg_settings.py"
FONTS = ROOT / "app" / "assets" / "fonts"
MARK_SVG = ROOT / "app" / "assets" / "brand" / "mark-small.svg"

# Palette: exact values from app/lib/src/theme/color_schemes.dart (light scheme).
SURFACE = (0xF4, 0xF6, 0xFA)
SURFACE_HIGHEST = (0xE3, 0xE8, 0xEF)
ON_SURFACE = (0x1A, 0x22, 0x2C)
ON_SURFACE_VARIANT = (0x48, 0x51, 0x5C)
OUTLINE_VARIANT = (0xC7, 0xCD, 0xD6)
WHITE = (0xFF, 0xFF, 0xFF)
# Shading inks for the inset. Cool greys, so the arrow stays neutral.
FLOOR_INK = (0x8A, 0x93, 0x9E)
RIM_SHADOW = (0x5C, 0x66, 0x72)
MARK_SHADOW = (0x4A, 0x52, 0x5E)
MARK_LOWER_EDGE = (0xA8, 0xAF, 0xB8)

HEADING = "Install Caller’s Compendium"
INSTRUCTION = "Drag the app onto the Applications folder"
FOOTER = "Then open Caller’s Compendium from your Applications folder."

# Arrow shape, in points.
SHAFT_HEIGHT = 40
HEAD_HEIGHT = 68
HEAD_LENGTH = 46
CORNER_RADIUS = 4
# Its length is the span between the two 112 pt icon boxes less this much at
# each end (171 pt with the current geometry). Where it sits is chosen
# separately, from the icons' visible edges: see arrow_mask().
ARROW_INSET = 18
# Share of the free space between the icons' visible edges that goes on the
# flat (app) side; the rest goes at the tip. A point beside a flat edge reads
# as more space than the same distance between two flat edges, so the tip
# gets less.
FLAT_SIDE_SHARE = 3 / 5

# Visible outlines inside each icon's square box, as fractions of its side.
# App: the standard macOS tile, measured from AppIcon (102-922 of 1024 px,
# ~185 px corner). Folder: the system folder body, approximate (~5% side
# margin, ~13-86% vertically) — check on a Mac after changing these.
APP_VISIBLE = (102 / 1024, 922 / 1024)
APP_CORNER = 185 / 1024
FOLDER_VISIBLE_X = (0.05, 0.95)
FOLDER_VISIBLE_Y = (0.13, 0.86)
FOLDER_CORNER = 0.07

# Raised mark: height in points, and how far right of the shaft's centre it
# sits (the shaft ends where the head begins, so its centre reads slightly
# left of where the eye expects).
MARK_HEIGHT = 22
MARK_NUDGE = 8

# Icon hover shadow: opacity of ON_SURFACE, blur and drop in points.
ICON_SHADOW_ALPHA = 0.432
ICON_SHADOW_BLUR = 14
ICON_SHADOW_DROP = 6

# Draw at this multiple of the output and downsample, for smooth edges.
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


def font(name: str, size: float, variation: bytes | None = None) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(str(FONTS / name), round(size))
    if variation:
        face.set_variation_by_name(variation)
    return face


def centered_text(draw: ImageDraw.ImageDraw, cx: float, y: float, text: str,
                  face: ImageFont.FreeTypeFont, fill: tuple[int, int, int]) -> None:
    left, _, right, _ = draw.textbbox((0, 0), text, font=face)
    draw.text((cx - (right - left) / 2 - left, y), text, font=face, fill=fill)


def tint(img: Image.Image, colour: tuple[int, int, int], mask: Image.Image) -> Image.Image:
    return Image.composite(Image.new("RGB", img.size, colour), img, mask)


def shifted(mask: Image.Image, dx: float, dy: float) -> Image.Image:
    """``mask`` moved by (dx, dy) pixels, sub-pixel accurate."""
    return mask.transform(mask.size, Image.AFFINE, (1, 0, -dx, 0, 1, -dy),
                          resample=Image.BILINEAR)


def faded(mask: Image.Image, alpha: float) -> Image.Image:
    return mask.point(lambda v: int(v * alpha))


def mark_alpha() -> Image.Image:
    """The small brand mark as a cropped alpha mask, rasterised large so the
    later downscale (one factor on both axes) keeps its exact proportions."""
    png = cairosvg.svg2png(url=str(MARK_SVG), output_width=2048, output_height=2048)
    alpha = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A")
    return alpha.crop(alpha.getbbox())


def scaled_uniformly(mask: Image.Image, k: float) -> Image.Image:
    """``mask`` scaled by ``k`` on both axes (not resized to whole-pixel width
    and height, which would nudge the aspect ratio)."""
    size = (math.ceil(mask.width * k), math.ceil(mask.height * k))
    # Box-reduce first: bicubic straight from a far larger source aliases.
    pre = max(1, int(1 / k / 2))
    if pre > 1:
        mask, k = mask.reduce(pre), k * pre
    return mask.transform(size, Image.AFFINE, (1 / k, 0, 0, 0, 1 / k, 0),
                          resample=Image.BICUBIC)


def arrow_mask(geo: dict, s: int) -> tuple[Image.Image, float]:
    """The arrow's shape at ``s`` px/pt, placed between the icons; also
    returns the horizontal shift (in points) applied to place it."""
    width, height = geo["WINDOW_SIZE"]
    app_x, y = geo["APP_POS"]
    apps_x, _ = geo["APPLICATIONS_POS"]
    icon = geo["ICON_SIZE"]
    x0 = app_x + icon / 2 + ARROW_INSET
    x1 = apps_x - icon / 2 - ARROW_INSET

    mask = Image.new("L", (width * s, height * s), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((x0 * s, (y - SHAFT_HEIGHT / 2) * s,
                         (x1 - HEAD_LENGTH + CORNER_RADIUS) * s, (y + SHAFT_HEIGHT / 2) * s),
                        CORNER_RADIUS * s, fill=255)
    d.polygon([((x1 - HEAD_LENGTH) * s, (y - HEAD_HEIGHT / 2) * s), (x1 * s, y * s),
               ((x1 - HEAD_LENGTH) * s, (y + HEAD_HEIGHT / 2) * s)], fill=255)
    # Ease every corner, the head's points and joins included, by the same
    # small amount.
    mask = mask.filter(ImageFilter.GaussianBlur(1.2 * s)).point(lambda v: 255 if v > 128 else 0)

    # Place the finished shape (easing trims the tip) between the icons'
    # visible edges, splitting the free space FLAT_SIDE_SHARE : rest, and
    # centre it vertically on the icons.
    app_edge = app_x - icon / 2 + icon * APP_VISIBLE[1]
    folder_edge = apps_x - icon / 2 + icon * FOLDER_VISIBLE_X[0]
    bx0, by0, bx1, by1 = mask.getbbox()
    slack = (folder_edge - app_edge) - (bx1 - bx0) / s
    dx = (app_edge + slack * FLAT_SIDE_SHARE) * s - bx0
    dy = y * s - (by0 + by1) / 2
    return shifted(mask, dx, dy), dx / s


def draw_inset_arrow(img: Image.Image, geo: dict, s: int) -> Image.Image:
    app_x, y = geo["APP_POS"]
    apps_x, _ = geo["APPLICATIONS_POS"]
    icon = geo["ICON_SIZE"]
    mask, dx = arrow_mask(geo, s)

    # Floor: one flat tone, the background at the arrow's centre a touch
    # darker, so the icon glows behind the rims do not show through as bands.
    base = img.getpixel((round((app_x + apps_x) / 2 * s), round(y * s)))
    floor_rgb = tuple(round(c + (t - c) * 0.10) for c, t in zip(base, FLOOR_INK))
    floor = Image.new("RGB", img.size, floor_rgb)
    img = Image.composite(floor, img, mask)

    # Gentle inner shadow under the upper rim; light along the lower rim and
    # on the lip just outside it, where the surface turns down into the
    # recess.
    rim_shadow = ImageChops.subtract(mask, shifted(mask, 0, 2.2 * s))
    rim_shadow = ImageChops.multiply(rim_shadow.filter(ImageFilter.GaussianBlur(2.8 * s)), mask)
    img = tint(img, RIM_SHADOW, faded(rim_shadow, 0.42))
    rim_light = ImageChops.subtract(mask, shifted(mask, 0, -1.2 * s))
    rim_light = ImageChops.multiply(rim_light.filter(ImageFilter.GaussianBlur(0.6 * s)), mask)
    img = tint(img, WHITE, faded(rim_light, 0.65))
    lip = ImageChops.subtract(shifted(mask, 0, 0.8 * s), mask)
    img = tint(img, WHITE, faded(lip.filter(ImageFilter.GaussianBlur(0.5 * s)), 0.55))

    # Raised mark on the floor: a face barely lighter than the floor, lit
    # along its top edge, darker along its bottom edge, with a small soft
    # shadow. Edges stay thinner than the mark's internal gaps so its lines
    # survive.
    source = mark_alpha()
    k = MARK_HEIGHT * s / source.height
    mark = scaled_uniformly(source, k)
    x0 = app_x + icon / 2 + ARROW_INSET
    head_base = apps_x - icon / 2 - ARROW_INSET - HEAD_LENGTH
    cx = (x0 + head_base) / 2 + MARK_NUDGE + dx
    origin = ((cx * s - source.width * k / 2), (y * s - source.height * k / 2))

    def placed(dy_pt: float = 0, alpha: float = 1.0, blur: float = 0) -> Image.Image:
        layer = Image.new("L", img.size, 0)
        layer.paste(mark, (round(origin[0]), round(origin[1] + dy_pt * s)))
        if blur:
            layer = layer.filter(ImageFilter.GaussianBlur(blur * s))
        return faded(layer, alpha)

    img = tint(img, MARK_SHADOW, placed(1.2, 0.14, 1.4))
    img = tint(img, MARK_LOWER_EDGE, placed(0.4, 0.5))
    img = tint(img, WHITE, placed(-0.4, 0.6))
    face = tuple(round(c + (255 - c) * 0.18) for c in floor_rgb)
    return tint(img, face, placed())


def draw_icon_shadows(img: Image.Image, geo: dict, s: int) -> Image.Image:
    app_x, y = geo["APP_POS"]
    apps_x, _ = geo["APPLICATIONS_POS"]
    icon = geo["ICON_SIZE"]
    top = y - icon / 2
    shadow = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(shadow)
    left = app_x - icon / 2
    lo, hi = (v * icon for v in APP_VISIBLE)
    d.rounded_rectangle(((left + lo) * s, (top + lo) * s, (left + hi) * s, (top + hi) * s),
                        icon * APP_CORNER * s, fill=255)
    left = apps_x - icon / 2
    d.rounded_rectangle(((left + icon * FOLDER_VISIBLE_X[0]) * s, (top + icon * FOLDER_VISIBLE_Y[0]) * s,
                         (left + icon * FOLDER_VISIBLE_X[1]) * s, (top + icon * FOLDER_VISIBLE_Y[1]) * s),
                        icon * FOLDER_CORNER * s, fill=255)
    shadow = shadow.filter(ImageFilter.GaussianBlur(ICON_SHADOW_BLUR * s))
    shadow = shifted(faded(shadow, ICON_SHADOW_ALPHA), 0, ICON_SHADOW_DROP * s)
    return tint(img, ON_SURFACE, shadow)


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
    img = Image.composite(Image.new("RGB", img.size, SURFACE_HIGHEST), img,
                          wash.point(lambda v: v * 0.55))

    # Soft light pools under each icon.
    slots = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(slots)
    r = icon * 0.62 * s
    for cx, cy in ((app_x, app_y), (apps_x, apps_y)):
        sd.ellipse((cx * s - r, cy * s - r, cx * s + r, cy * s + r), fill=255)
    slots = slots.filter(ImageFilter.GaussianBlur(18 * s))
    img = tint(img, WHITE, slots.point(lambda v: v * 0.85))

    draw = ImageDraw.Draw(img)
    cx = width / 2

    # Heading and instruction, above the icon row.
    centered_text(draw, cx * s, 34 * s, HEADING,
                  font("Fraunces-VariableFont.ttf", 26 * s, b"SemiBold"), ON_SURFACE)
    centered_text(draw, cx * s, 74 * s, INSTRUCTION,
                  font("AtkinsonHyperlegible-Regular.ttf", 15 * s), ON_SURFACE_VARIANT)

    # Divider and follow-up hint, below the icon labels, clear of the bottom
    # edge.
    footer_y = height - 74
    draw.line(((cx - 150) * s, (footer_y - 14) * s, (cx + 150) * s, (footer_y - 14) * s),
              fill=OUTLINE_VARIANT, width=max(1, s))
    centered_text(draw, cx * s, footer_y * s, FOOTER,
                  font("AtkinsonHyperlegible-Regular.ttf", 13 * s), ON_SURFACE_VARIANT)

    img = draw_inset_arrow(img, geo, s)
    img = draw_icon_shadows(img, geo, s)
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
