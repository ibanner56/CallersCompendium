#!/usr/bin/env python3
"""The brand mark, raised, for the middle of a Show code QR code (#2334).

The Mac installer window (``generate_dmg_background.py``) draws the brand's
small mark "standing raised" on a pressed-in floor: a face barely lighter than
the floor, lit along its top edge, darker along its bottom edge, with a small
soft shadow, all in pale tone on tone. This script gives the Show code screen
the same look, using the installer's own shading helpers, palette and
proportions, so the two read as one family.

The output is a small rounded-square badge: the pale installer floor, pressed
in (shadowed upper rim, lit lower rim), with the mark raised on it. The app
draws it over the white clear zone at the middle of a code. It is baked
(opaque, floor included) rather than drawn at run time because the effect only
reads on the grey floor; a highlight on pure white would vanish.

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
    # the upper rim, light along the lower rim and on the lip outside it.
    rim_shadow = ImageChops.subtract(outline, dmg.shifted(outline, 0, 2.2 * s))
    rim_shadow = ImageChops.multiply(
        rim_shadow.filter(ImageFilter.GaussianBlur(2.8 * s)), outline)
    img = dmg.tint(img, dmg.RIM_SHADOW, dmg.faded(rim_shadow, 0.42))
    rim_light = ImageChops.subtract(outline, dmg.shifted(outline, 0, -1.2 * s))
    rim_light = ImageChops.multiply(
        rim_light.filter(ImageFilter.GaussianBlur(0.6 * s)), outline)
    img = dmg.tint(img, dmg.WHITE, dmg.faded(rim_light, 0.65))

    # The raised mark: the installer's recipe, layer for layer.
    origin = ((side - mark.width) / 2, (side - mark.height) / 2)

    def placed(dy_pt: float = 0, alpha: float = 1.0, blur: float = 0) -> Image.Image:
        layer = Image.new("L", img.size, 0)
        layer.paste(mark, (round(origin[0]), round(origin[1] + dy_pt * s)))
        if blur:
            layer = layer.filter(ImageFilter.GaussianBlur(blur * s))
        return dmg.faded(layer, alpha)

    img = dmg.tint(img, dmg.MARK_SHADOW, placed(1.2, 0.14, 1.4))
    img = dmg.tint(img, dmg.MARK_LOWER_EDGE, placed(0.4, 0.5))
    img = dmg.tint(img, dmg.WHITE, placed(-0.4, 0.6))
    face = tuple(round(c + (255 - c) * 0.18) for c in FLOOR)
    img = dmg.tint(img, face, placed())

    out = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    out.putalpha(outline.resize((SIZE, SIZE), Image.LANCZOS))
    return out


def main() -> None:
    image = badge()
    image.save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
