# Design: UX — information architecture & core screens

*Roadmap item 1.11 · v0.1 (2026-07-10). Conforms to
research/accessibility-baseline.md; every screen below ships with semantics
annotations and keyboard/AT acceptance criteria in its implementation issue.
Visual design: Material 3 adaptive (Flutter), light/dark/high-contrast themes.*

## Information architecture

```
┌ Collection (default)   – the dance library
├ Programs               – event set lists
├ Perform                – performance mode (entered from a program or dance)
└ Settings               – dialect(s), data sources, custom fields, appearance
```

- **Phones/tablets**: bottom navigation (Collection, Programs, Settings);
  Perform is a mode, not a tab — entered explicitly, exits back to context.
- **Desktop**: left nav rail; list/detail split panes; full keyboard map,
  global search shortcut (Ctrl/Cmd-K).
- Responsive breakpoints: single pane (phone) / list+detail (tablet landscape,
  desktop) — same screens, adaptive layout, no separate "mobile app".

## Screens

### 1. Collection (browse + search)
- Virtualized list: title, authors, formation chip, tags, custom list fields.
  Sort by title/author/recently-added/last-called.
- Search bar = unified FTS; **filter panel** for structured search: formation,
  progression, author, tags, custom fields, and figure queries ("contains
  petronella in B1", "chain **then** swing") built with a friendly query
  builder (ContraDB ez-query lesson: common cases one-tap, advanced tree
  behind "advanced").
- Search input is dialect-canonicalized; result counts announced politely to AT.
- Actions: new dance, import, duplicate, batch tag.

### 2. Dance detail / card
- Header: title, authors, formation, hook, tags, status banner (deprecated/
  broken), provenance line ("via The Caller's Box · CC-BY-NC").
- Figure table grouped by derived section (A1…), beats column, progression ¶
  marker; dialect applied. Toggle: canonical ⇄ dialect view.
- Side panel/tabs: calling notes, links (source/video/related), calling
  history (from performed programs), custom fields.
- Actions: edit, duplicate, add-to-program, print/share, Perform this dance.

### 3. Dance editor
- **Keyboard-first figure entry** (the CC "Insert Call" lesson): type-ahead
  move picker — typing "sw" offers swing; Enter accepts defaults (who/beats);
  Tab cycles named params with sensible defaults from the taxonomy; running
  beat count per section shown continuously (overflow = inline warning, not
  error). Full entry of a standard dance must be achievable in <1 min without
  the mouse.
- Custom figure = just typing free text where no move matches; lingo-line
  feedback (recognized terms underlined, discouraged struck) as you type.
- Figure reordering: drag handle **plus** move-up/down buttons + cut/paste
  (WCAG 2.5.7).
- Metadata form with author autocomplete (choreographer table), formation
  picker, custom fields.
- Autosave drafts; explicit save commits; undo history.

### 4. Programs list & builder
- Builder: two-pane — program (ordered slots) | collection picker with the
  same filter panel as Collection.
- Slots: dance slots + free-text slots (break, waltz, announcements); **ALT
  flag** renders as an indented alternate under its primary (color + icon +
  text, never color alone).
- Reorder: drag + non-drag alternative; slot notes inline.
- **Matrix view** tab: figures × dances grid computed from structured data
  (moves as columns, per-dance presence + first-figure highlight) — CC's
  programming matrix without the manual checklist. Horizontally scrollable,
  row/column headers pinned, AT-navigable as a table.
- Header: event date/venue/notes; duplicate program; print/export (PDF, text);
  "mark performed" stamps performedAt on called slots (feeds calling history).

### 5. Performance mode
- Full-screen card: current dance, huge type (user-set size/weight/spacing,
  no upper bound), 7:1 contrast themes (dark-stage default), wake-lock on.
- Navigation: giant next/prev hit zones at screen edges (44pt+), swipe,
  arrow keys/page keys, jump-to-slot overview. ALT dances one tap to swap.
- Zero destructive actions reachable; exit via deliberate gesture/button with
  confirm. Optional: per-slot timer/clock display.
- On-the-fly: reorder remaining slots, insert from quick-search, add ad-hoc
  note — all in an "adjust" sheet, never disturbing the reading view.

### 6. Settings
- **Dialect manager**: named dialects, preset picker, role/move term editor
  with live preview + collision validation; discouraged-terms list editor;
  quick-switch also exposed on dance card / perform screens.
- Data sources: snapshot URL(s), update check/download with progress + review
  queue entry point; import from file (CC .USR, JSON).
- Custom field definitions; appearance (theme gallery — System / Light / Dark /
  High-contrast plus IDE-inspired palettes; see ux-modernization.md §4A; text
  scale); backup/export.

## Cross-cutting UX rules

- Undo/soft-delete everywhere (restore within 30 days), destructive confirms
  only where undo is impossible.
- Empty states teach: first-run Collection offers "download the community
  collection" (snapshot) and "import your data".
- All lists virtualize; search-as-you-type debounced; target <50 ms query
  budget (storage design).
- Every interactive element: visible focus, name/role/state semantics, 24px+
  targets (44pt in Perform), traversal order = visual order.
- No color-only meaning anywhere (chips/badges pair icon+text).

## Deliverables next

Low-fi wireframes per screen (Excalidraw/Figma, committed as SVG/PNG under
docs/design/wireframes/) before Phase 3 implementation of each screen; this
doc is the contract for what they must contain.
