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
| Brand palette | **"Hearth"** — terracotta / pine / ochre (off default indigo) |
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

### 1a. Color tokens — palette "Hearth"

Full `ColorScheme`s (not just a seed — a seed cannot reliably hit the 7:1 Perform
target). Every pairing below was validated with WCAG contrast math; ratios are
targets to re-confirm in a contrast test during UX-0.

**Light**

| Role | Hex | On-color | Ratio |
|---|---|---|---|
| primary | `#9C4A2F` (terracotta) | `#FFFFFF` | 6.12 |
| primaryContainer | `#FFDBCF` | `#3A0B00` | 13.26 |
| secondary | `#4E6B4F` (pine) | `#FFFFFF` | 5.93 |
| secondaryContainer | `#D0E8CF` | `#0B2010` | 13.13 |
| tertiary | `#7A5900` (ochre) | `#FFFFFF` | 6.45 |
| tertiaryContainer | `#FFDF9E` | `#261A00` | 13.25 |
| error | `#BA1A1A` | `#FFFFFF` | 6.46 |
| surface / onSurface | `#FBF7F2` | `#201A17` | 16.12 |
| onSurfaceVariant | `#52443C` | (on surface) | 8.75 |
| surfaceContainerHighest | `#F0E4DC` | (on surface) | 13.78 |
| outline (borders, ≥3:1) | `#857066` | — | 4.37 |

**Dark**

| Role | Hex | On-color | Ratio |
|---|---|---|---|
| primary | `#FFB59B` | `#5A1B08` | 7.73 |
| primaryContainer | `#7C3218` | `#FFDBCF` | 7.00 |
| secondary | `#B4CCB1` | `#203622` | 7.58 |
| secondaryContainer | `#364E37` | `#D0E8CF` | 7.01 |
| tertiary | `#EFC048` | `#3F2E00` | 7.68 |
| tertiaryContainer | `#5B4300` | `#FFDF9E` | 7.25 |
| error | `#FFB4AB` | `#690005` | 7.72 |
| surface / onSurface | `#1A120E` | `#EDE0D9` | 14.31 |
| onSurfaceVariant | `#D7C3B8` | (on surface) | 10.90 |
| surfaceContainerHighest | `#3B302A` | (on surface) | 9.90 |
| outline (borders, ≥3:1) | `#A08D82` | — | 5.83 |

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
  // — IDE-inspired gallery (net-new) —
  solarizedLight, solarizedDark,
  atomOneLight,   atomOneDark,
  monokai,
  oneDarkPro, oneDarkProDarker,   // "Darker" = deeper omega variant
  noctis,     noctisLux,          // dark + light siblings
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
| **Hearth** *(default, ships in UX-0)* | light+dark+HC | `#FBF7F2` / `#1A120E` | `#201A17` / `#EDE0D9` | terracotta `#9C4A2F` · pine `#4E6B4F` · ochre `#7A5900` | house palette (§1a/§1b) |
| Solarized Light | light | `#FDF6E3` warm paper | `#657B83` | `#268BD2` `#859900` `#B58900` `#DC322F` `#6C71C4` `#2AA198` | Solarized (Ethan Schoonover, MIT) |
| Solarized Dark | dark | `#002B36` deep teal | `#839496` | *(same accent set)* | Solarized (MIT) |
| Atom One Light | light | `#FAFAFA` cool white | `#383A42` | `#4078F2` `#50A14F` `#E45649` `#A626A4` `#0184BC` | Atom One Light |
| Atom One Dark | dark | `#282C34` blue-grey | `#ABB2BF` | `#61AFEF` `#98C379` `#E06C75` `#C678DD` `#56B6C2` `#E5C07B` | Atom One Dark |
| One Dark Pro | dark | `#282C34` blue-grey | `#ABB2BF` | *(refined One Dark accents)* | One Dark Pro |
| One Dark Pro Darker | dark | `#21252B` near-black | `#ABB2BF` | *(as above)* | One Dark Pro "Darker" (deeper omega) |
| Monokai | dark | `#272822` warm charcoal | `#F8F8F2` | `#F92672` `#A6E22E` `#E6DB74` `#FD971F` `#AE81FF` `#66D9EF` | Monokai (Wimer Hazenberg / Sublime) |
| Noctis | dark | `#1B2932` teal blue-black | `#D6DEEB` | teal/green forward | Noctis (Liviu Schera) |
| Noctis Lux | light | `#F9F6F2` | `#53606C` | teal/green forward | Noctis Lux |

The set deliberately spans the **omega spectrum** — paper-white → cool-white →
warm-charcoal → blue-grey → near-black → deep-saturated-teal — so users get real
variety, not ten shades of the same dark. A true-black AMOLED entry can be added
later if requested; it's a natural extension of the same registry.

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

## 5. Component direction — before → after

Grounded in the real widgets, with code-verified notes.

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
