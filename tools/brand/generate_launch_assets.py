#!/usr/bin/env python3
"""Launch-screen mark rasters for iOS and Android (no Pillow needed).

Renders ``app/assets/brand/mark.svg`` (the full illustration, transparent) with
``rsvg-convert`` (``brew install librsvg``) into:

* iOS ``LaunchImage.imageset`` -- 1x/2x/3x at 120 pt, a light-ground variant
  (open-book pages tan, because cream vanishes on ``#F4F6FA``) and a dark
  appearance variant (the committed cream pages).
* Android ``drawable-*dpi/launch_mark.png`` (default / light ground, tan pages)
  and ``drawable-night-*dpi/launch_mark.png`` (cream pages), 120 dp.

The page-colour swap mirrors ``mark-small-light.svg`` (see
``app/assets/brand/README.md``). Local, one-off tool: not run in CI; outputs are
committed. Re-run from the repo root::

    python3 tools/brand/generate_launch_assets.py
"""

from __future__ import annotations

import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
APP = os.path.join(REPO, "app")
MARK = os.path.join(APP, "assets", "brand", "mark.svg")

CREAM_PAGES = "rgb(240,218,194)"
TAN_PAGES = "rgb(224,178,120)"
MARK_DP = 120  # on-screen edge length of the mark, in points / dp


def render(svg_text: str, px: int, out: str) -> None:
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "mark.svg")
        with open(src, "w", encoding="utf-8") as f:
            f.write(svg_text)
        subprocess.run(
            ["rsvg-convert", "-w", str(px), "-h", str(px), src, "-o", out],
            check=True,
        )


def main() -> None:
    dark = open(MARK, encoding="utf-8").read()
    assert CREAM_PAGES in dark, "mark.svg page colour changed; update this tool"
    light = dark.replace(CREAM_PAGES, TAN_PAGES)

    ios = os.path.join(APP, "ios", "Runner", "Assets.xcassets", "LaunchImage.imageset")
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        render(light, MARK_DP * scale, os.path.join(ios, f"LaunchImage{suffix}.png"))
        render(dark, MARK_DP * scale, os.path.join(ios, f"LaunchImageDark{suffix}.png"))

    res = os.path.join(APP, "android", "app", "src", "main", "res")
    for density, factor in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2),
                            ("xxhdpi", 3), ("xxxhdpi", 4)):
        px = int(MARK_DP * factor)
        render(light, px, os.path.join(res, f"drawable-{density}", "launch_mark.png"))
        render(dark, px, os.path.join(res, f"drawable-night-{density}", "launch_mark.png"))


if __name__ == "__main__":
    main()
