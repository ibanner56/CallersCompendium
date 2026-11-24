#!/usr/bin/env python3
"""The brand mark, raised, for the middle of a Show code QR code (#2334).

The Mac installer window (``generate_dmg_background.py``) draws the brand's
small mark "standing raised" on a pressed-in floor: lit along its top edge,
darker along its bottom edge, with a small soft shadow. This script gives the
Show code screen the same construction: it reuses the installer's shading
helpers, its floor tone, its pressed-in rim (same offsets, blur and strength),
its proportions, and the same layer order for the mark (soft shadow, lower
edge, lit top edge, face).

The mark itself differs on purpose. The installer's is pale on a pale floor,
which is far too faint in the middle of a QR code, so here the mark is dark
enamel: a deep slate face with a vertical sheen (lighter at the top, deeper at
the bottom), a lit top edge, a deeper lower edge and a stronger soft shadow on
the floor. Those layers' offsets, strengths and inks are tuned by hand for a
dark mark, not taken from the installer; the face colours sit around the
app's Soft Dark surface (#1E2A38) but are not scheme tokens. It is a dark mark
with a raised, lit surface, not a flat black shape.

The output is a small rounded-square badge: the pale installer floor, pressed
in (shadowed upper rim, lit lower rim), with the mark raised on it. The app
draws it over the white clear zone at the middle of a code. It is baked
(opaque, floor included) rather than drawn at run time, as the installer's
background is.

The mark's shading is specified in points against the installer's 22 pt mark
height, then scaled with the mark, so the badge keeps the installer's
proportions at any size.

Output (committed; the app only reads it):

* ``app/assets/brand/mark-raised.png`` — ``SIZE`` square, transparent corners

Dependencies (local only — this script does **not** run in CI): ``Pillow`` and
``cairosvg`` (see ``generate_dmg_background.py``).

Re-run from the repo root::

    python3 tools/brand/generate_raised_mark.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# The installer script is the source of the shading helpers and the palette.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_dmg_background as dmg  # noqa: E402

ROOT = dmg.ROOT
OUT = ROOT / "app" / "assets" / "brand" / "mark-raised.png"

SIZE = 512
SUPERSAMPLE = 2
# Corner radius as a fraction of the side. The Show code screen puts this on a
# white clear zone whose corners are rounded the same amount.
RADIUS = 0.10
# The mark's longer side, as a fraction of the badge's side. The rest is the
# floor the mark stands on, and room for its shadow.
MARK_FRACTION = 0.70

# The installer arrow's floor tone, measured from the committed
# packaging/macos/dmg-background.png away from the mark.
FLOOR = (0xE5, 0xE8, 0xEE)

# The mark's dark enamel. The face runs from FACE_TOP to FACE_BOTTOM over the
# mark's height; both sit around the app's Soft Dark surface (#1E2A38, the
# brand tile's colour, `BrandMark.brandBackground`).
FACE_TOP = (0x3B, 0x4B, 0x60)
FACE_BOTTOM = (0x17, 0x21, 0x2D)
LIT_EDGE = (0xA2, 0xB3, 0xC8)
LOWER_EDGE = (0x0B, 0x11, 0x19)
SHADOW = dmg.ON_SURFACE


def badge() -> Image.Image:
    side = SIZE * SUPERSAMPLE
    outline = Image.new("L", (side, side), 0)
    ImageDraw.Draw(outline).rounded_rectangle(
        (0, 0, side - 1, side - 1), RADIUS * side, fill=255)

    source = dmg.mark_alpha()
    k = MARK_FRACTION * side / max(source.size)
    mark = dmg.scaled_uniformly(source, k)
    # Pixels per installer point: the installer's mark is MARK_HEIGHT pt tall.
    s = mark.height / dmg.MARK_HEIGHT

    img = Image.new("RGB", (side, side), FLOOR)

    # Pressed-in floor, as the installer's arrow: a gentle inner shadow under
    # the upper rim and light along the lower rim. (The arrow's light lip
    # outside the shape is left out: the badge has no outside.)
    rim_shadow = ImageChops.subtract(outline, dmg.shifted(outline, 0, 2.2 * s))
    rim_shadow = ImageChops.multiply(
        rim_shadow.filter(ImageFilter.GaussianBlur(2.8 * s)), outline)
    img = dmg.tint(img, dmg.RIM_SHADOW, dmg.faded(rim_shadow, 0.42))
    rim_light = ImageChops.subtract(outline, dmg.shifted(outline, 0, -1.2 * s))
    rim_light = ImageChops.multiply(
        rim_light.filter(ImageFilter.GaussianBlur(0.6 * s)), outline)
    img = dmg.tint(img, dmg.WHITE, dmg.faded(rim_light, 0.65))

    # The raised mark: the installer's construction (soft shadow, lower edge,
    # lit top edge, face) in dark enamel.
    origin = ((side - mark.width) / 2, (side - mark.height) / 2)

    def placed(dy_pt: float = 0, alpha: float = 1.0, blur: float = 0) -> Image.Image:
        layer = Image.new("L", img.size, 0)
        layer.paste(mark, (round(origin[0]), round(origin[1] + dy_pt * s)))
        if blur:
            layer = layer.filter(ImageFilter.GaussianBlur(blur * s))
        return dmg.faded(layer, alpha)

    img = dmg.tint(img, SHADOW, placed(1.6, 0.34, 1.8))
    img = dmg.tint(img, LOWER_EDGE, placed(0.5, 0.9))
    img = dmg.tint(img, LIT_EDGE, placed(-0.5, 0.8))

    # The face: a vertical sheen over exactly the mark's height.
    top = round(origin[1])
    ramp = Image.linear_gradient("L").resize((side, mark.height))
    sheen = Image.new("L", img.size, 0)
    sheen.paste(255, (0, top + mark.height, side, side))
    sheen.paste(ramp, (0, top))
    face = Image.composite(Image.new("RGB", img.size, FACE_BOTTOM),
                           Image.new("RGB", img.size, FACE_TOP), sheen)
    img = Image.composite(face, img, placed())

    out = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    out.putalpha(outline.resize((SIZE, SIZE), Image.LANCZOS))
    return out


def main() -> None:
    image = badge()
    image.save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
