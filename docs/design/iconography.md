# Design: Iconography convention

*UX review item 6.3 · v0.1 (2026-07-15).*

## The rule

**Outlined = idle / unselected. Filled = active / selected.**

Within any one surface, idle and decorative inline icons share a single weight
(**outlined**). The **filled** weight is reserved for genuinely active, selected,
or toggled-on states. This keeps visual weight consistent so the eye isn't
drawn to an arbitrarily "heavier" glyph that carries no extra meaning.

Applies to:

- **Toggles / selectable controls** — supply an outlined `icon` for the idle
  state and the filled counterpart as `selectedIcon`, gated by `isSelected`
  (e.g. the Perform app bar's auto-size, stage, and canonical-terms toggles,
  and the nav rail / navigation bar destinations).
- **Decorative / metadata markers** — the small facet avatars on Collection
  rows (formation, level, mixed-level, rating, tags) and the Perform header's
  meta rows use the **outlined** weight.
- **Status indicators** — status glyphs (`error_outline`,
  `warning_amber_outlined`, `check_circle_outline`) use the outlined weight;
  severity is carried by color + label, not by icon fill.
- **App-bar action icons** — keep one weight within a single bar.

## Centralized glyphs

Concept glyphs live in one place so the same idea always reads the same way:

- `formationIcon` and `progressionIcon` — `app/lib/src/search/facet_labels.dart`.
- **Dialect** = `Icons.groups_outlined` / `Icons.groups` (idle / active). Used by
  the dance-view dialect quick-switch and the Perform canonical-terms toggle.
- **Language & region (app locale)** = `Icons.translate_outlined` /
  `Icons.translate`. `Icons.translate` is reserved for app-language/locale only
  and must **not** be reused for dialect selection (they are different concepts).

## Exceptions

If a glyph has **no** outlined counterpart in the Material Icons set, it is
acceptable to keep the filled glyph rather than substitute a mismatched one that
hurts recognizability. Document any such exception here.

- *(none at present — every idle inline marker in the normalized surfaces has a
  real outlined variant, so no filled exceptions were required.)*

Note: many line-based glyphs (e.g. `search`, `add`, `close`, `sort`,
`more_vert`, `link`) expose an `_outlined` alias that is visually identical to
the base glyph. These carry no filled/outlined distinction, so they are left at
their default name — mechanical renaming would add noise without changing the
rendered UI.
