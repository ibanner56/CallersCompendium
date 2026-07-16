# Caller's Compendium — brand mark

Source of truth for the app icon / brand mark (review item **4.1**) and the
platform launcher icons generated from it (review item **3.5**).

## Concept — "Progression bars"

Two bold vertical bars represent the two facing lines of a longways contra set.
The right bar is stepped **up** to imply progression up the set — what a caller
sees on the floor, rendered in an understated, modern (VS Code / GitHub) style.

## Palette

Pulled verbatim from `app/lib/src/theme/color_schemes.dart` — do not eyeball.

| Token | Hex | Role |
| --- | --- | --- |
| Petrol / "Blue Hour" dark surface | `#121A24` | dark tile / adaptive background |
| Lantern amber (dark primary) | `#FFB784` | glyph on the dark tile |
| Light scheme surface | `#F4F6FA` | light-ground tile |
| Light primary | `#9A5312` | glyph on the light tile |
| onSurfaceVariant (dark) | `#B4C1CE` | muted in-app mark tint |

## Geometry (128-unit box)

The glyph is two rounded rectangles, centered at (64, 64):

| Bar | x | y | w | h | rx |
| --- | --- | --- | --- | --- | --- |
| left | 38 | 44 | 18 | 56 | 9 |
| right | 72 | 28 | 18 | 56 | 9 |

Full-color tile = the glyph on a rounded square, corner radius `28.4`
(≈ 22.2% of 128). Legibility was validated at 16/32/48 px — the two staggered
bars stay distinct, so the canonical width (18) is kept.

## Variants (this folder — SVG is the source of truth)

| File | Purpose |
| --- | --- |
| `icon.svg` | full-color rounded tile (amber on petrol) |
| `icon-light.svg` | light-ground tile (light primary on light surface) |
| `icon-foreground.svg` | Android adaptive foreground (108 vb, glyph scaled 0.80 about center → inside the 66dp safe circle) |
| `icon-background.svg` | solid petrol background (mirrors `@color/ic_launcher_background`) |
| `icon-monochrome.svg` | flat single-color glyph for Android 13+ themed icons / maskable PWA (currentColor) |
| `mark.svg` | glyph only, no tile, `currentColor` — reference for the in-app painter |

The in-app reuse path is **not** SVG: `app/lib/src/widgets/brand_mark.dart` is a
dependency-free `CustomPainter` that paints the same 128-unit geometry, so the
rail mark / empty-state mark (items 4.3 / 4.4) can reuse it without adding
`flutter_svg`.

## How the raster PNGs / .ico were generated (reproducible)

This repo's environment has **no** SVG rasterizer (`rsvg-convert`, `inkscape`,
ImageMagick, `cairosvg`, `node`) and no Pillow. Because the mark is pure
rounded-rect geometry, the launcher icons are rendered directly by a
**standard-library-only** Python script — no native dependencies, fully
deterministic — and the outputs are committed (the script does **not** run in
CI). To regenerate, from the repo root:

```sh
python3 tools/brand/generate_icons.py
```

It renders each rounded rect from an analytic signed-distance field (≈1px
anti-alias band, equivalent to heavy supersampling) and writes PNGs / the
Windows `.ico` with hand-rolled `zlib` + `struct` encoders. It also emits the
two Android vector drawables from the same geometry. Outputs:

- **Android** `app/android/app/src/main/res/`
  - `mipmap-{m,h,xh,xxh,xxx}dpi/ic_launcher.png` — legacy full-color tile (API < 26)
  - `mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon (foreground + background + monochrome)
  - `drawable/ic_launcher_foreground.xml`, `drawable/ic_launcher_monochrome.xml` — vector layers
  - `values/colors.xml` — `ic_launcher_background` = `#121A24`
- **iOS** `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` — opaque, **no alpha**, full-bleed petrol (iOS applies its own mask)
- **macOS** `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png` — rounded tile with the standard ~10% transparent squircle margin
- **Windows** `app/windows/runner/resources/app_icon.ico` — multi-resolution 16/24/32/48/64/128/256 (BMP entries < 256, PNG at 256); referenced by `windows/runner/Runner.rc`

Web and Linux runners are not present in this repo, so no icons are generated
for them.
