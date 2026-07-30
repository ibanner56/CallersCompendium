# Caller's Compendium — brand mark

Source of truth for the app icon / brand mark and the platform launcher icons
generated from it.

## Concept — "Dancers rising from a book"

Two role-neutral dancers, inside hands joined mid-turn, spin up out of an open
book — the caller's collection brought to life. It ties the app's two halves
together: the **book** is the curated library of dances; the **dancers** are the
movement the caller calls from it. Role-neutral figures match the app's
role-neutral dialect defaults.

## Palette

Pulled verbatim from `app/lib/src/theme/color_schemes.dart` — do not eyeball.

| Token | Hex | Role |
| --- | --- | --- |
| Soft Dark surface | `#1E2A38` | **default** tile / Android adaptive background / iOS "Any" |
| Petrol / "Blue Hour" dark surface | `#121A24` | iOS **Dark** appearance tile |
| Light scheme surface | `#F4F6FA` | light-ground tile |
| Lantern amber (dark primary) | `#FFB784` | one dancer / warm accent |
| Rosy terracotta | `#E4A9A0` | the other dancer |
| Cream / honey pages | `#FFECDB` / `#D8C98A` | open-book pages (dark tiles) |
| Tan pages | `#E0B278` | open-book pages on the **light** tile (cream vanishes on white) |

## Default + theme policy

- **Soft Dark (`#1E2A38`) is the default tile** on every platform.
- **iOS** ships appearance variants (iOS 18+): **Any** = Soft Dark, **Dark** =
  petrol `#121A24`, **Tinted** = grayscale (the system applies the user's tint).
- **Android** keeps an adaptive icon (Soft Dark background + full-illustration
  foreground) plus a **monochrome** themed layer (the small-mark silhouette,
  tinted by the system on Android 13+).
- **Small-mark crossover:** the full illustration is used at ≥ 48 px; at ≤ 32 px
  a simplified **two-dancers-on-a-book** mark is used so it stays legible.

## Variants (this folder — SVG is the source of truth)

| File | Purpose |
| --- | --- |
| `icon.svg` | full-colour default tile (illustration on Soft Dark) |
| `icon-dark.svg` | dark-tile variant (petrol `#121A24`) — iOS Dark reference |
| `icon-light.svg` | light-ground tile |
| `icon-small.svg` | simplified small mark on the Soft Dark tile (≤ 32 px) |
| `mark.svg` | full illustration, no tile, transparent — in-app + Android foreground source |
| `mark-small.svg` | simplified small mark, no tile (cream pages) — in-app small / silhouette source |
| `mark-small-light.svg` | simplified small mark, tan pages (for light grounds) |
| `icon-foreground.svg` | Android adaptive foreground (108 vb, illustration scaled 0.80 into the 66dp safe circle) |
| `icon-background.svg` | solid Soft Dark background (mirrors `@color/ic_launcher_background`) |
| `icon-monochrome.svg` | single-colour small-mark silhouette (`currentColor`) for Android 13+ themed icons |

The in-app reuse path (`app/lib/src/widgets/brand_mark.dart`) now renders these
SVGs via **`flutter_svg`** so the nav-rail mark / empty-state marks stay
pixel-identical to the launcher icons. (The previous geometry-only mark was a
bespoke `CustomPainter`; the illustration is multi-path vector art and needs an
SVG runtime.) The brand SVGs are bundled through the pubspec `assets/brand/`
entry.

## Regenerating the raster PNGs / .ico / Android drawables

Unlike the previous pure-geometry mark, the illustration needs an SVG
rasteriser. `tools/brand/generate_icons.py` renders the SVGs above and
composites the per-platform tiles. It is a **local, one-off** tool (it does
**not** run in CI; its outputs are committed). Dependencies:

- **`librsvg`** / `rsvg-convert` on `PATH` (e.g. `brew install librsvg`,
  `apt-get install librsvg2-bin`)
- **Pillow** (`pip install pillow`) — compositing + the Windows `.ico`

Re-run from the repo root:

```sh
python3 tools/brand/generate_icons.py
```

Outputs:

- **Android** `app/android/app/src/main/res/`
  - `mipmap-{m,h,xh,xxh,xxx}dpi/ic_launcher.png` — Soft Dark tile (API < 26)
  - `mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon (foreground + background + monochrome)
  - `drawable/ic_launcher_foreground.xml`, `drawable/ic_launcher_monochrome.xml` — vector layers
  - `values/colors.xml` — `ic_launcher_background` = `#1E2A38`
- **iOS** `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` — single-size 1024
  with **Any / Dark / Tinted** appearance variants (opaque, no alpha)
- **macOS** `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png`
  — rounded tile with the standard ~10% transparent squircle margin
- **Windows** `app/windows/runner/resources/app_icon.ico` — 16/24/32/48/64/128/256
- **Linux packaging** `packaging/linux/icon.png` — 512px Soft Dark tile

The `site/` marketing assets (`logo.svg`, `favicon.svg`, `social-card.svg`) embed
the same small mark and are maintained by hand from these sources.
