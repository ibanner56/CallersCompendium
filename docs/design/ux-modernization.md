# Design: UX modernization — visual design system & interaction polish

*New initiative (not previously on the roadmap), drafted 2026-07-13. Conforms to
[research/accessibility-baseline.md](../research/accessibility-baseline.md) and
upgrades the screens defined in [design/ux.md](ux.md) without re-scoping their
information architecture. Visual approach: **Refined Material 3** — stay native,
add a real design-system layer. No heavy third-party UI kit.*

## 0. Summary & decisions

The app is functional but visually unfinished: the entire theme is two inline
lines in `app/lib/main.dart` —
`ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo)` for light and the
same seed for dark. There are no design tokens, no custom typography, no
component/density styling, and the light/**dark**/**high-contrast** trio promised
in `ux.md` is missing its high-contrast theme. Dense, form-heavy screens (dance
editor, facet panel, advanced query builder, program builder, matrix) inherit
default Material styling and read as cluttered.

This document is the contract for fixing that. Decisions locked with the tech
lead:

| Decision | Choice |
|---|---|
| Visual approach | Refined Material 3, native, no third-party UI kit |
| Brand palette | **"Blue Hour"** — cool daylight/petrol canvas with warm lantern-amber accents (evolved from the original warm "Hearth") |
| Typography | **Fraunces** (display/headings) + **Atkinson Hyperlegible** (body/UI/Perform) |
| Fonts delivery | Bundled offline as `pubspec.yaml` assets — **no `google_fonts`** runtime fetch (local-first) |
| High-contrast | One dark-based HC theme, **shared with Phase 5 Perform mode** |
| Theme selection | User-selectable: System / Light / Dark / High-contrast |
| Theme gallery (net-new) | Beyond System/Light/Dark/HC, a curated set of **IDE-inspired palettes** (Solarized, Atom One, Monokai, One Dark Pro, Noctis…). Each is a full, contrast-validated `ColorScheme` that bakes in its own contrast **and** background darkness ("omega": true-black / deep / charcoal / grey). Users pick a whole theme — **no separate contrast/omega sliders.** Extends the §4 switcher (see §4A). |

*Considered alternative:* palette "Fiddle & Brass" (garnet / forest / brass) —
bolder and more saturated, but its garnet primary visually competes with the red
`error` role, so Hearth was chosen for calmer long-session legibility and to keep
green free to mean "ready/valid".

## 1. Design-system foundation

### 1a. Color tokens — palette "Blue Hour" *(default)*

Full `ColorScheme`s (not just a seed — a seed cannot reliably hit the 7:1 Perform
target). Every pairing below was validated with WCAG contrast math; ratios are
targets to re-confirm in a contrast test during UX-0. The default evolved from
the original warm "Hearth" palette to **"Blue Hour"**: a cool daylight/petrol
canvas with a shared warm lantern-amber accent family, so light and dark read as
one identity.

**Light** *(cool daylight canvas, warm amber accents)*

| Role | Hex | On-color | Ratio |
|---|---|---|---|
| primary | `#9A5312` (amber) | `#FFFFFF` | 5.80 |
| primaryContainer | `#FFDCC2` | `#331200` | 13.26 |
| secondary | `#8C4A43` (dusty rose) | `#FFFFFF` | 6.61 |
| secondaryContainer | `#FFDAD3` | `#3A0906` | 13.28 |
| tertiary | `#6E5A16` (wheat-gold) | `#FFFFFF` | 6.69 |
| tertiaryContainer | `#F5E7A8` | `#221B00` | 13.78 |
| error | `#BA1A1A` | `#FFFFFF` | 6.46 |
| surface / onSurface | `#F4F6FA` | `#1A222C` | 14.83 |
| onSurfaceVariant | `#48515C` | (on surface) | 7.44 |
| surfaceContainerHighest | `#E3E8EF` | (on surface) | 13.03 |
| outline (borders, ≥3:1) | `#727C87` | — | 3.92 |

**Dark** *(default "Blue Hour" — deep petrol-indigo canvas with warm lantern-amber accents)*

| Role | Hex | On-color | Ratio |
|---|---|---|---|
| primary | `#FFB784` | `#4A2400` | 8.01 |
| primaryContainer | `#6B3D12` | `#FFDCC2` | 7.07 |
| secondary | `#E4A9A0` | `#45201C` | 7.10 |
| secondaryContainer | `#5E332E` | `#FFDAD3` | 8.16 |
| tertiary | `#D8C98A` | `#382F09` | 8.01 |
| tertiaryContainer | `#4F461F` | `#F5E7A8` | 7.57 |
| error | `#FFB4AB` | `#690005` | 7.72 |
| surface / onSurface | `#121A24` | `#E7ECF1` | 14.73 |
| onSurfaceVariant | `#B4C1CE` | (on surface) | 9.56 |
| surfaceContainerHighest | `#253241` | (on surface) | 10.96 |
| outline (borders, ≥3:1) | `#7B8896` | — | 4.84 |

### 1b. High-contrast / Perform tokens (shared, dark-based, target ≥7:1)

High-contrast defeats tonal/elevation cues, so components in this theme are
**outline-driven** (real borders) with a high-visibility focus ring. This theme
is co-owned with Phase 5 Perform mode.

| Pairing | Hex | Ratio |
|---|---|---|
| onSurface `#FFF3EC` / surface `#0A0705` | body | 18.44 |
| onPrimary `#000000` / primary `#FFD9C9` | actions | 16.02 |
| onSecondary `#000000` / secondary `#B2F1BD` | accents | 16.21 |
| error `#FFB4AB` / surface | alerts | 11.83 |
| focus ring `#FFD54A` / surface (≥3:1) | focus | 14.22 |
| outline `#FFF3EC` / surface (≥3:1) | borders | 18.44 |

### 1c. Typography

- **Display / headings: Fraunces** — a warm optical-size serif; character
  without kitsch. Variable font (opsz/wght).
- **Body / UI / Perform: Atkinson Hyperlegible** — designed by the Braille
  Institute for low-vision legibility. Directly serves the older-caller audience
  and the accessibility baseline; crisp small, scales without bound in Perform.

Proposed M3 `TextTheme` (sizes in logical px):

| Style | Family / weight | display | headline | title | body | label |
|---|---|---|---|---|---|---|
| large | — | 57 Fraunces w600 | 32 Fraunces | 22 Atkinson w700 | 16 Atkinson w400 | 14 Atkinson w600 |
| medium | — | 45 | 28 | 16 | 14 | 12 |
| small | — | 36 | 24 | 14 | 12 | 11 |

Perform mode uses its own scale (Atkinson Bold, ~28px floor, **no upper bound**,
user-adjustable size/weight/line-spacing).

### 1d. Spacing, density, shape, elevation

- **Spacing:** 4px base grid — tokens `space` 4 / 8 / 12 / 16 / 24 / 32 / 48.
- **Density:** desktop lists/tables/matrix use `VisualDensity.compact`; touch
  surfaces use comfortable density; selected adaptively by platform.
- **Shape:** corner radii 8 / 12 / 16, dialogs 28.
- **Elevation:** prefer tonal `surfaceContainer` tiers over drop shadows (M3
  idiom); HC theme swaps tonal cues for outlines.

### 1e. Structure — new `app/lib/src/theme/`

Replaces the two inline lines in `main.dart`:

- `color_schemes.dart` — three `const ColorScheme`s (light / dark / high-contrast).
- `app_typography.dart` — `TextTheme` + font-family constants.
- `app_spacing.dart`, `app_shapes.dart` — spacing/shape tokens.
- `component_themes.dart` — sub-themes for FilledButton/OutlinedButton, Chip,
  Card, ListTile, **InputDecoration**, NavigationRail/NavigationBar, Dialog.
- `app_theme_extension.dart` — a `ThemeExtension` for semantic tokens M3 lacks
  (see §2); always paired with icon+text, never color-only.
- `app_theme.dart` — assembles `AppTheme.light` / `.dark` / `.highContrast`;
  consumed by `main.dart`; theme mode driven from Settings (§4).

## 2. Semantic extension tokens (`AppThemeExtension`)

Mapped onto palette roles so they auto-adapt across light/dark/HC. **Every token
pairs color with an icon + text label** — no color-only meaning
(accessibility-baseline "Perceivable"). Keyed to the **actual** domain enums in
`compendium_core` (verified against the code):

**`ProgramStatus` — `{ draft, finalized, performed }`** (already rendered as
icon+text by `program_status_chip.dart`; tokens add theme-driven color):

- `statusDraft` → neutral/outline + `edit_note_outlined` "Draft"
- `statusFinalized` → secondary (green) + `check_circle_outline` "Finalized"
- `statusPerformed` → tertiary + `event_available_outlined` "Performed"

**`DanceStatus` — `{ active, deprecated, broken }`** (already icon+text in
`dance_list_tile.dart`):

- `statusActive` → no chip (default)
- `statusDeprecated` → onSurfaceVariant + `history_toggle_off` "Deprecated"
- `statusBroken` → error + `report_problem_outlined` "Broken"

**Other semantic tokens:**

- `dialectAccent` → tertiary hue as a leading border/underline on dialect-scoped
  terms, always with a small "dialect" badge.
- `perform*` → `performSurface` / `performOnSurface` / `performAccent` /
  `performFocus` = the HC tokens in §1b.

> Correction from an earlier draft: the invented `inProgress` / `ready` /
> `conflict` / `archived` statuses do **not** exist in the model and were dropped.

## 3. Fonts — `app/pubspec.yaml` registration

The existing `assets/fonts/Roboto-VariableFont.ttf` entry is a raw **asset**, not
a registered font family, so `fontFamily: 'Roboto'` won't reliably resolve to the
bundled asset until it's registered — depending on platform/system fonts it may
instead pick up a system Roboto or the platform default. We establish the
convention (keeping Roboto as a documented fallback):

```yaml
flutter:
  fonts:
    - family: Fraunces                 # display / headings (serif, OFL)
      fonts:
        - asset: assets/fonts/Fraunces-VariableFont.ttf
    - family: AtkinsonHyperlegible     # body / UI / Perform (OFL, low-vision)
      fonts:
        - asset: assets/fonts/AtkinsonHyperlegible-Regular.ttf
        - asset: assets/fonts/AtkinsonHyperlegible-Bold.ttf
          weight: 700
        - asset: assets/fonts/AtkinsonHyperlegible-Italic.ttf
          style: italic
    - family: Roboto                   # fallback
      fonts:
        - asset: assets/fonts/Roboto-VariableFont.ttf
```

Atkinson ships static weights; Fraunces is variable (opsz/wght) — drive headings
via `FontVariation`, or register named instances for fixed weights.

## 4. Theme-switcher wiring (net-new)

Verified in code: `settings_screen.dart` currently hosts only the dialect
`RadioGroup`; there is no `ThemeMode` selector. We copy the existing dialect
pattern exactly. Because high-contrast is not a `ThemeMode` value, model four
explicit selections:

```dart
enum AppThemeSelection { system, light, dark, highContrast }
```

- `app/lib/src/data/app_theme_scope.dart`: `AppThemeScope extends
  InheritedNotifier<ValueNotifier<AppThemeSelection>>` — placed **alongside the
  existing `ActiveDialectScope`** (verified to live in `src/data/`), not under
  `src/theme/`. The `src/theme/` foundation (tokens, `ColorScheme`s, `AppTheme`)
  stays presentation-only; the scope is runtime app state, so it belongs with the
  other data scopes.
- Persist via `repos.settings.set(kAppThemeKey, …)`, load on boot — mirrors
  `kActiveDialectKey` + `_onDialectChanged`. Define a `const String kAppThemeKey =
  'theme_mode';` next to `kActiveDialectKey` in `settings_screen.dart` rather than
  a bare string literal.
- `main.dart` `MaterialApp`:
  ```dart
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  highContrastTheme: AppTheme.highContrast,      // bonus: OS a11y HC flag
  highContrastDarkTheme: AppTheme.highContrast,
  themeMode: selection.toThemeMode(),            // system / light / dark
  // when selection == highContrast: force theme + darkTheme = AppTheme.highContrast
  ```
  The `AppThemeScope` slots into the existing `builder:` next to
  `ActiveDialectScope`.
- `settings_screen.dart`: add an **"Appearance"** section — a `RadioGroup`
  (System / Light / Dark / High-contrast), each option labelled + described, with
  a small live preview swatch. Our in-app selector is the source of truth; the OS
  high-contrast flag is a bonus path, not the only route to HC.

## 4A. Theme gallery — palette picker (net-new; extends §4)

The default Hearth palette + System/Light/Dark/High-contrast (§4) covers the
baseline, but callers coming from code editors expect their favorite look. This
section adds a **theme gallery**: a curated set of selectable palettes inspired
by the most-used IDE themes. Each gallery palette bakes in its own brightness,
contrast character, and **background darkness ("omega")** — true-black vs
deep-saturated vs warm-charcoal vs blue-grey vs paper-white. The user selects a
*whole theme*; there are **no separate contrast or omega sliders** (that
complexity is pre-resolved by curating the set).

This is purely additive to the UX-0 foundation shipping in **PR #45** — it
reuses `AppColorSchemes`, `AppTheme`, `AppThemeScope`, and the Settings
"Appearance" plumbing rather than introducing a parallel system.

### 4A.1 Model — extend, don't replace

Grow the existing `AppThemeSelection` (§4) from a 4-value *mode* enum into a
small **palette registry**. `system` stays special (follows the OS light/dark
setting using the Hearth family); every other value pins one specific,
contrast-validated `ColorScheme`.

```dart
enum AppThemeSelection {
  system,               // follow OS → Hearth light/dark (unchanged)
  light,                // Hearth light   (unchanged)
  dark,                 // Hearth dark    (unchanged)
  highContrast,         // ≥7:1, shared with Perform (unchanged)
  // Gallery palettes (§4A) — light.
  blulocoLight, githubLight,
  catppuccinLatte, gruvboxLight, everforestLight, rosePineDawn,
  ayuLight, tokyoNightLight, nordLight, kanagawaLotus,
  noctisLilac, materialLight,
  // Gallery palettes (§4A) — dark.
  oneDarkPro, monokai, noctis, dracula, nord,
  tokyoNight, gruvboxDark, catppuccinMocha, githubDark,
  everforestDark, rosePine, ayuMirage, cutiePro, pinkAsHeck,
  zenburn, shadesOfPurple, palenight, synthwave84,
}
```

- **Persistence is backward-compatible.** The stored value is still the enum
  `.name` under `kAppThemeKey` (`'theme_mode'`), so existing
  `system`/`light`/`dark`/`highContrast` selections keep resolving; new palettes
  are simply new names.
- Each value gains three resolvers used by the wiring + settings UI:
  `Brightness get brightness`, `ColorScheme get scheme` (from an extended
  `AppColorSchemes`, or a `paletteSchemes` map), and a `group` for the gallery UI
  (System · Default · Light · Dark).
- **No per-palette bespoke code.** `AppTheme._build(ColorScheme)` (§1e, #45)
  already turns *any* `ColorScheme` into full `ThemeData` (typography, adaptive
  density, visible focus, and the `AppThemeExtension` semantic tokens), so a new
  palette is "one validated `ColorScheme` + one enum entry."

### 4A.2 `main.dart` wiring — generalize the high-contrast special-case

UX-0 (#45) special-cases high-contrast by forcing both `theme`/`darkTheme` to
`AppTheme.highContrast` with `themeMode: dark`. Generalize that single branch:

- `system` → `theme: AppTheme.light`, `darkTheme: AppTheme.dark`,
  `themeMode: system` (today's behavior).
- any pinned palette → build its `ThemeData` once, set it on **both** `theme`
  and `darkTheme`, and set `themeMode` from `selection.brightness`
  (light palette ⇒ `ThemeMode.light`, dark palette ⇒ `ThemeMode.dark`).

The `highContrastTheme`/`highContrastDarkTheme` slots and the OS high-contrast
path stay exactly as in §4.

### 4A.3 The initial gallery

Anchor ("identity") colors below make each palette recognizable; the **full
30-role `ColorScheme` per palette is derived and WCAG-validated during
implementation** (§4A.4), the same process that produced Hearth in §1a. Exact
per-role hex against each source palette is an implementation deliverable.

| Palette | Mode | Background — "omega" | Foreground | Signature accents | Inspired by |
|---|---|---|---|---|---|
| **Blue Hour** *(default, ships in UX-0)* | light+dark+HC | `#F4F6FA` / `#121A24` | `#1A222C` / `#E7ECF1` | light: amber `#9A5312` · dusty-rose `#8C4A43` · wheat-gold `#6E5A16` — dark: lantern-amber `#FFB784` · dusty-rose `#E4A9A0` · wheat-gold `#D8C98A` | house palette (§1a/§1b) |
| Bluloco Light | light | `#F9F9F9` cool-neutral | `#383A42` | `#275FE4` `#23974A` `#823FF1` `#D52753` | Bluloco Light (uloco) |
| One Dark Pro | dark | `#282C34` blue-grey | `#ABB2BF` | *(refined One Dark accents)* | One Dark Pro |
| Monokai | dark | `#282C34` charcoal | `#ABB2BF` | `#E06C75` `#98C379` `#C678DD` `#F44747` | One Monokai (azemoh) — Monokai syntax on One Dark's canvas |

*(Noctis is now a single dark entry in the Dark section; Noctis Lilac is a single light entry in the Light section — see the "Noctis" note below.)*

**Expanded gallery (UX-7).** Following UX-6, the gallery was widened with the
most-requested industry/hobbyist favorites, spanning the hue spectrum in both
modes. Each is derived + AA-validated by the same `GalleryPalettes._build`
process (`app/lib/src/theme/palette_schemes.dart`), so
adding one is just "identity colors + one enum entry":

| Palette | Mode | Background | Signature hue | Inspired by |
|---|---|---|---|---|
| GitHub Light | light | `#FFFFFF` | neutral blue | GitHub |
| Catppuccin Latte | light | `#EFF1F5` | pastel mauve | Catppuccin |
| Gruvbox Light | light | `#FBF1C7` | warm amber | Gruvbox |
| Everforest Light | light | `#FDF6E3` | soft green | Everforest |
| Rosé Pine Dawn | light | `#FAF4ED` | rose / iris | Rosé Pine |
| Ayu Light | light | `#FAFAFA` | bright amber | Ayu |
| Tokyo Night Light | light | `#E1E2E7` | crisp indigo | Tokyo Night (Day) |
| Nord Light | light | `#ECEFF4` | arctic blue | Nord (Snow Storm) |
| Kanagawa Lotus | light | `#F2ECBC` | sumi-e ink | Kanagawa (Lotus) |
| Dracula | dark | `#282A36` | purple / pink | Dracula |
| Nord | dark | `#2E3440` | arctic blue | Nord |
| Tokyo Night | dark | `#1A1B26` | neon indigo | Tokyo Night |
| Gruvbox Dark | dark | `#282828` | warm amber | Gruvbox |
| Catppuccin Mocha | dark | `#1E1E2E` | pastel mauve | Catppuccin |
| GitHub Dark | dark | `#0D1117` | neutral blue | GitHub |
| Everforest Dark | dark | `#2D353B` | soft green | Everforest |
| Rosé Pine | dark | `#191724` | rose / iris | Rosé Pine |
| Ayu Mirage | dark | `#1F2430` | amber / slate | Ayu |
| Cutie Pro | dark | `#231F20` | pink pastel | Cutie Pro |
| Pink as Heck | dark | `#2D1E2F` | hot pink | Pink as Heck |
| Material Light | light | `#FFFBFE` | Material purple | Material 3 baseline |
| Zenburn | dark | `#3F3F3F` | low-contrast warm grey | Zenburn |
| Shades of Purple | dark | `#2D2B55` | gold on indigo | Shades of Purple |
| Palenight | dark | `#292D3E` | purple / blue-grey | Material Palenight |
| Synthwave '84 | dark | `#262335` | neon on retro purple | Synthwave '84 |

**Gallery curation.** After the UX-7 expansion the dark set grew redundant, so
it was trimmed by removing palettes that perceptually overlapped a more iconic
sibling (measured by weighted CIELAB ΔE across surface + accents): the One Dark
canvas was collapsed to **One Dark Pro** + **Monokai** (dropping Atom One Dark,
One Dark Pro Darker, One Candy Dark); **Catppuccin** to **Mocha** (dropping
Frappé, Macchiato); **GitHub** to **GitHub Dark** (dropping Soft Dark); the
muted-greens to **Everforest** + **Zenburn** (dropping Matcha); the pink cluster
to **Cutie Pro** + **Pink as Heck** (dropping Cute Pink Dark); plus **Night Owl**
(overlaps GitHub Dark / Tokyo Night) and **Material Dark** (the generic M3
baseline in a crowded lavender group). The surviving set preserves every hue
lead and canvas-darkness band.

**Default redesign + gallery re-curation.** The default palette was re-cut from
warm "Hearth" to **Blue Hour** — a cooler, dustier, more muted pastel story on
both light and dark slots (§1a). Alongside it the gallery was re-curated: the
**Noctis** family (11 variants) was collapsed to two representatives — **Noctis**
(the signature deep-teal dark, folded into the Dark section) and **Noctis Lilac**
(the distinctive lilac light, folded into the Light section) — since the other
nine differed only by canvas while sharing identical accents. To hold the gallery
at 12 light / 18 dark: **Solarized Dark** was dropped as the second teal-canvas
dark (Palenight kept), which orphaned **Solarized Light**; and **Atom One Light**
was orphaned when Atom One Dark was cut earlier. Both orphaned lights were removed
and replaced by **Noctis Lilac** (lilac/lavender gap) and **Bluloco Light** (a
vivid high-saturation light the pastel-heavy set lacked).

**Light additions.** To balance the trimmed dark set, three popular light
palettes joined the gallery: **Tokyo Night Light** (Day) mirrors the dark Tokyo
Night with a crisp indigo daylight canvas; **Nord Light** (Snow Storm) fills the
cool desaturated-blue gap; and **Kanagawa Lotus** brings an on-trend warm sumi-e
paper with ink accents.

**Noctis.** The [Noctis](https://github.com/liviuschera/noctis) family originally
shipped as 11 variants in a dedicated gallery section. Because the eight darks
shared one accent set (differing only by canvas) and the three lights another,
the family was collapsed to two representatives that carry its signature
mint-green / warm-pink / gold syntax accents:

| Palette | Mode | Background | Foreground | Section |
|---|---|---|---|---|
| Noctis | dark | `#052529` deep teal | `#B2CACD` | Dark |
| Noctis Lilac | light | `#F2F1F8` lilac | `#0C006B` | Light |

Shared accents: mint-green `#49E9A6` (light `#00B368`) · warm-pink `#DF769B`
(light `#FF5792`) · gold `#D5971A` (light `#A88C00`) · red `#E34E1C`
(light `#FF4000`).

The standalone Noctis section is dissolved; both survivors fold into the
regular Dark and Light groups. A true-black AMOLED entry can be added later if
requested; it's a natural extension of the same registry.

### 4A.4 Accessibility contract (non-negotiable)

- **Every gallery palette clears the same bar as Hearth**: WCAG 2.2 **AA** per
  `research/accessibility-baseline.md` — body text ≥ 4.5:1, large text &
  non-text UI ≥ 3:1 — validated by the same contrast test used for §1a during
  implementation.
- Several famous themes are **below AA on some pairings** (Solarized is
  intentionally low-contrast; Monokai comments; low-emphasis text on many dark
  themes). Policy: **preserve the identity hue, tune the tone** until the pairing
  reaches AA. We never ship a text role below AA to stay "pixel-accurate" to a
  source theme; identity is in the hues, not the exact luminance.
- **Gallery choice is app-chrome only and cannot weaken Perform mode.** The
  `perform*` tokens in `AppThemeExtension` are fixed to the ≥7:1 high-contrast
  values (§1b/§2) regardless of the active `ColorScheme`, so selecting a
  low-contrast gallery theme leaves Perform legibility untouched. High-contrast
  remains its own gallery entry and the OS high-contrast route (§4) is unchanged.
- **No color-only meaning**, still. Palettes only re-tint the §2 semantic tokens
  via `AppThemeExtension.fromColorScheme`; every status/badge keeps its icon +
  text channel.

### 4A.5 Settings UX — from radio list to swatch gallery

The §4 four-item `RadioGroup` doesn't scale to ~12 palettes. Replace the
Appearance body with a **grouped swatch gallery**:

- Labeled sections — **System · Default (Hearth) · Light · Dark** — each a wrap
  of selectable **preview cards**.
- Each card renders a **mini live sample over that palette's real background**: a
  surface tile, a Fraunces heading + Atkinson body line, three accent chips, and
  a focus-ring demo — so contrast and "omega" are visible *before* selecting.
- Preserve single-selection radio semantics: one selected at a time, each card
  exposes name/role/state, keyboard-traversable in visual order, with a visible
  focus indicator (accessibility-baseline). Selection is instant and persisted
  via the existing `_onThemeChanged` path (live `AppThemeScope` notifier +
  background `repos.settings.set`).

### 4A.6 Attribution & licensing

- **Solarized** — a precise, **MIT-licensed** palette (Ethan Schoonover); we may
  reproduce its exact values and credit it (in an in-app "About themes" note and
  in `docs/`).
- **Monokai / Atom One / One Dark Pro / Noctis** — names and looks associated
  with their authors and editors. We ship **"inspired by" palettes** — our own
  contrast-tuned `ColorScheme`s — credit the inspiration, and avoid implying
  endorsement. If a specific name is a concern, use a descriptive house name with
  an "inspired by X" subtitle. Resolve exact naming in the UX-6 implementation
  issue.

### 4A.7 Scope & sequencing

- **Depends on UX-0 (PR #45)** landing (the registry, `AppTheme`,
  `AppThemeScope`, and the Appearance switcher it extends).
- Lands as its own roadmap step **UX-6 — Theme gallery** (§7). Independent of the
  UX-2→UX-5 component work, but benefits from UX-2's shared component sub-themes
  so the preview cards render faithfully.

## 4B. Custom themes — copy, edit & save locally (net-new; extends §4A)

Beyond the built-in gallery, users can **copy any theme, tune every color, and
save it on-device**. Custom themes are personal to the install; nothing syncs.

### 4B.1 Model & precedence

- `CustomTheme` (`data/custom_theme.dart`) — `{id, name, brightness, Map<String,int> roles}`.
  Rather than mirror the ~30 `ColorScheme` getters, it stores an editable
  **role key → packed ARGB int** map and builds a full scheme via
  `toScheme()` = `ColorScheme.{light,dark}().copyWith(...)`, so any untouched
  role keeps a valid default. JSON uses `Color.toARGB32()` / `Color(int)`.
- A single source of truth (`CustomThemeRoles`) lists every editable role, how
  they group in the editor, and which foreground/background **contrast pairs**
  get a live badge — keeping the model, editor UI, and tests in lockstep.
- `CustomThemesController` (`ChangeNotifier`, backed by `SettingsRepository`
  keys `custom_themes` + `active_custom_theme`) owns the saved list and the
  active id. **Precedence is custom-wins:** a custom theme is active iff
  `activeId != null`. Selecting a built-in clears it; selecting/saving a custom
  sets it.
- `main.dart` resolves the custom theme first (pin its scheme into both slots,
  mode from its brightness), then falls back to the §4/§4A built-in logic.

### 4B.2 Editing & the AA contract

- The editor (`screens/theme_editor_screen.dart`) exposes **all major roles**
  (primary/secondary/tertiary/error + their containers, surfaces & containers,
  outline & effects) via a dependency-free color dialog (hex field + R/G/B
  sliders) and a live preview.
- WCAG contrast is surfaced with per-pair **pass/fail badges** (`theme/wcag.dart`),
  but is **warn-but-allow-save** — the user may intentionally ship a
  low-contrast palette; the editor flags it rather than blocking. (This is the
  one place the otherwise non-negotiable §4A.4 AA guarantee is advisory, and
  only for user-authored themes.)
- Surfaces as a **Custom themes** section in Settings: copy from the current
  theme, then edit / duplicate / delete each saved card.

## 4C. Settings — sectioned master–detail (net-new; extends §4/§4A/§4B)

As Appearance grew (gallery + custom themes) and Dialect is set to expand, the
single scrolling Settings page became unwieldy. Settings is now a **master–detail
shell** (`screens/settings_screen.dart`):

- A `_SettingsSection` enum (currently **Appearance**, **Dialect**) is the single
  source of truth for the sidebar; adding a page is one enum value plus its
  content in `_content`.
- **Wide (≥ 720 px):** a left sidebar list + a content pane side by side
  (`_SettingsSidebar`), selection shown by the highlighted tile **and** a filled
  icon (never color alone). **Narrow:** the sidebar is a list whose rows push the
  section as its own page with a back-navigable app bar.
- Each section is its own widget (`_AppearanceView`, `_DialectView`), so state
  (theme selection, dialect) stays lifted in the screen and the panes rebuild
  live via the existing scopes.

## 5. Component direction — before → after

### 5.1 Collection — `collection_shell` / `dance_list_screen` / `dance_list_tile` / `facet_panel`

```
BEFORE                              AFTER
[ search box............ ]          [ 🔍 Search dances    ⌘K ] [☰ Filters] [⇅ Sort]
□ Reel  □ Jig  □ 32-bar             ── Filters (grouped, collapsible, count badges) ──
Dance A - reel - 32                 ▸ Form (3)  ▸ Level (4)  ▸ Length (2)   [Clear ✕]
Dance B - jig - 48                  ┌───────────────────────────────────────────┐
...flat rows, no hierarchy          │ ◐  Midsummer Night                    ★    │
                                    │    32-bar · Improper · Intermediate        │
                                    └───────────────────────────────────────────┘
```

- `dance_list_tile` is today a plain `ListTile` (default-styled title + a `Wrap`
  of icon+text `Chip`s for formation/level/status/tags). **Delta:** themed
  `titleMedium` (Fraunces), a leading form-type avatar, compact density. The
  chips already pair icon+text, so no a11y channel is missing.
- `facet_panel` is today flat `Column`s of `FilterChip`s (`_FacetSection`) plus
  `_TextFieldFacet` / `_NumberFieldFacet`. **Delta:** wrap each section in an
  `ExpansionTile` with a count badge and add a sticky "Clear filters" bar. The
  `advanced_query_builder` opens in a right-hand sheet; active query summarized as
  chips. `move_autocomplete` gets a styled overlay with a keyboard-highlight row.

### 5.2 Collection detail — `dance_detail_screen` / `figure_table`

```
BEFORE                              AFTER
Title                               ┌ Overview ─────────────┐  header: displaySmall (Fraunces)
key: value                          │ form · level · length  │  on a surfaceContainer card
Figures:                            └────────────────────────┘
A1 balance & swing 8                ┌ Figures ──────────────┐  aligned/monospace beat counts
A2 ...                              │ A1 · Balance & swing · 8│  row separators (outlineVariant)
                                    │ A2 · Circle left ¾  · 6 │  dialect terms: tertiary underline+badge
```

### 5.3 Dance editor — `dance_editor_screen` / `figure_list_editor` / `figure_param_editors` / `move_autocomplete`

```
BEFORE                              AFTER
label [__________]                  ── Details ──  (section header + helper text)
label [__________]                  Name        [ filled input, 12dp radius, focus ring ]
figures:                            ── Figures ──                              [+ Add figure]
[ move ] [ n ]                      ⠿ A1  [Balance & swing ▾]  count[8]  ⋮   ← 24px drag target
(dense, unlabeled)                  ⠿ A2  [Circle left ▾]      count[6]  ⋮
```

- **Verified:** there is **no** shared `InputDecorationTheme`. `dance_editor_screen`
  has ~17 local `const InputDecoration(...)` (several with a bare
  `OutlineInputBorder()`); `figure_param_editors` has 3 more. A single
  app-level `InputDecorationTheme` in `component_themes.dart` unifies all of them
  at once (filled, 12dp radius, visible focus) — high leverage, low risk.
- Reorderable figure rows keep the drag handle **plus** move-up/down + cut/paste
  (WCAG 2.5.7), with 24px+ targets.

### 5.4 Program builder — `program_editor_screen` / `program_slot_list_editor` / `program_matrix_table` / `program_status_chip`

```
BEFORE                              AFTER
Program X                           Program X   [◐ Draft]  [Export ▾]   ← status chip icon+text
1 Dance A                           ┌ 1 · ⠿ Dance A ── reel · 32 ──── ✎ ✕ ┐  slot cards + ordinal
2 Dance B                           ├ 2 · ⠿ Dance B ── jig · 48 ───── ✎ ✕ ┤
[ matrix: raw grid ]                └───────────────────────────────────┘
                                    Matrix ▸ themed (headers + legend already present), compact density
```

- **Verified:** `program_matrix_table` is a custom `Container`-cell grid (not
  `DataTable`) that already colors cells from `theme.colorScheme`, marks
  first-figure with a **star icon** + present with a **check icon** (icon+color,
  not color-only), and **already implements pinned row/column headers** (a
  four-quadrant layout with mirrored `ScrollController`s) **and a legend**
  (`_Legend`). It will auto-adapt to Hearth. **Delta is theming/polish only:**
  apply the §1/§2 tokens, tighten to the compact density (§1d), and restyle the
  existing headers/legend — no structural or behavioral change to the grid.
- `program_status_chip` already maps `ProgramStatus` to icon+text; it gains
  theme-driven color from the §2 tokens. `collection_picker` becomes a
  searchable right-hand sheet reusing the Collection filter panel.

## 6. Shell / navigation polish — `app_shell.dart`

Within the `ux.md` IA (no re-scoping): style the `NavigationRail` (wide, ≥900px)
and `NavigationBar` (narrow) with a pill selected-indicator and themed
icon/label treatment, and add a persistent global-search affordance wired to
**Ctrl/Cmd-K**. Settings stays reachable from each screen's app bar as today.

## 7. Phased implementation plan (drop-in roadmap "Phase UX")

Each step carries accessibility acceptance criteria drawn from
`accessibility-baseline.md`.

- **UX-0 — Foundation.** Create `app/lib/src/theme/`; light + dark `ColorScheme`s;
  typography (bundle + register fonts); spacing/shape; wire `main.dart` and add
  the Settings "Appearance" switcher. *AC: visible focus on every interactive
  element; no visual regressions; light/dark selectable; text scaling to 200%
  without clipping.*
- **UX-1 — High-contrast (co-designed with Phase 5).** HC theme, outline-driven,
  ≥7:1; high-visibility focus ring. *AC: 7:1 verified on Perform/HC text; focus
  ring ≥3px; no color-only meaning.*
- **UX-2 — Component theming.** Buttons, chips, cards, list tiles, the shared
  `InputDecorationTheme`, dialogs, nav sub-themes. *AC: interactive targets ≥24px;
  every status/badge pairs icon + text.*
- **UX-3 — Collection + Dance editor refinement.** Tiles, facet `ExpansionTile`s,
  editor sections. *AC: keyboard traversal order = visual order; 200% text scale
  without clipping; keyboard-first figure entry preserved.*
- **UX-4 — Program builder + matrix.** Slot cards, matrix legend/sticky
  headers/density. *AC: status conveyed non-color; matrix remains AT-navigable as
  a table with pinned headers keyboard-reachable.*
- **UX-5 — Shell / adaptive polish + Cmd-K + full keyboard map.** *AC: complete
  desktop keyboard map; global search shortcut; focus visible throughout.*
- **UX-6 — Theme gallery (palette picker).** IDE-inspired palettes (§4A) as
  contrast-validated `ColorScheme`s; extend `AppThemeSelection` + `AppColorSchemes`;
  generalize the `main.dart` theme-slot wiring; swap the Settings Appearance
  radio list for a grouped swatch gallery with live previews. Depends on UX-0.
  *AC: every palette passes WCAG 2.2 AA (4.5:1 text / 3:1 large & non-text);
  Perform mode still ≥7:1 regardless of selection; gallery is keyboard-navigable
  with visible focus; no color-only meaning.*

**Sequencing:** UX-0 and UX-1 land **before/with Phase 5 (Perform mode)** so
Perform inherits the tokens and shares the high-contrast theme; UX-2→UX-5 follow.
Perform and Imports screens built later inherit the system for free.

## 8. Code-verification appendix

Confirmed directly against the current source before writing this doc:

- `main.dart` theme is the two inline seed lines; `MaterialApp` at lines ~78–96
  has `theme:`/`darkTheme:` and a `builder:` wrapping `RepositoriesScope` +
  `ActiveDialectScope` — clean insertion points for `AppTheme` and `AppThemeScope`.
- `settings_screen.dart` hosts only the dialect `RadioGroup`; the theme switcher
  is net-new; the `kActiveDialectKey` + `_onDialectChanged` + `repos.settings.set`
  pattern is the template to copy.
- No shared `InputDecorationTheme`; ~20 ad-hoc `InputDecoration`s across the dance
  editor and figure param editors.
- `program_matrix_table` uses `Container` cells colored from `colorScheme`, with
  star/check icons for first/present (already not color-only).
- `program_status_chip` and `dance_list_tile` already pair icon+text for status.
- No `google_fonts` dependency; Roboto is bundled only as a raw asset.

## 9. Roadmap integration

This work is **not currently on the roadmap** and is net-new. It should be added
as its own "Phase UX" (items UX-0…UX-6 above), sequenced so UX-0/UX-1 land with
Phase 5 Performance mode. Deliverables to follow this doc: annotated
before/after mockups committed under `docs/design/wireframes/` (optional), and
per-step implementation issues carrying the acceptance criteria above. UX-6 (the
theme gallery, §4A) is optional polish that can slot in any time after UX-0.
