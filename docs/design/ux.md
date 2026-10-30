# Design: UX — information architecture & core screens

*Roadmap item 1.11 · v0.1 (2026-07-10). Conforms to
research/accessibility-baseline.md; every screen below ships with semantics
annotations and keyboard/AT acceptance criteria in its implementation issue.
Visual design: Material 3 adaptive (Flutter), light/dark/high-contrast themes.*

## Information architecture

```
┌ Collection (default)   – the dance library
├ Programs               – event set lists
├ Glossary               – built-in figure reference, with the user's notes,
│                          terms, and own figures, combinations and new
│                          figures with their own wording (Experimental, off
│                          by default; #695, #709, #1023)
├ Perform                – performance mode (entered from a program or dance)
└ Settings               – dialect(s), data sources, custom fields, appearance
```

- **Phones/tablets**: bottom navigation (Collection, Programs, Glossary when
  turned on, Settings, Guide);
  Perform is a mode, not a tab — entered explicitly, exits back to context.
- **Desktop**: left nav rail; list/detail split panes; full keyboard map,
  global search shortcut (Ctrl/Cmd-K).
- Responsive breakpoints: single pane (phone) / list+detail (tablet landscape,
  desktop) — same screens, adaptive layout, no separate "mobile app".

## Screens

### 1. Collection (browse + search)
- Virtualized list: title, authors, formation chip, tags, custom list fields.
  Sort by title/author/recently-added/last-called; opens in the saved
  default sort (Settings ▸ Defaults) and direction (ascending or descending,
  the sort's natural direction unless changed there, issue #1841), or in
  whatever sort and direction were last used if "Last used" is selected there
  (issue #895). Sort survives crossing the
  list/detail split-pane breakpoint (e.g. a tablet rotation), which used to
  discard the list's state.
- Search bar = unified FTS; **filter panel** for structured search: formation,
  progression, author, tunes, tags (with an "Untagged" chip, and an "All tags
  / Any tag" choice once two are picked, FIND-14), calling history
  (Called / Not called, narrowed by venue and time window;
  `history-filters.md`), custom fields, and figure queries ("contains
  petronella in B1", "chain **then** swing") built with a friendly query
  builder (ContraDB ez-query lesson: common cases one-tap, advanced tree
  behind "advanced").
- Search input is dialect-canonicalized; result counts announced politely to AT.
  The calling-history facet follows the active caller and performed-only scope;
  it is omitted when that scope has no qualifying calls.
- Which filter sections appear is a per-user display preference (Settings ▸
  Defaults ▸ Collection filters, issue #1419), applied to the Collection page
  and the dance picker alike. It is a deny-list of section ids
  (`collection_hidden_facets`), so every filter — including a custom field
  created later — is shown until hidden. Hiding is display-only: it clears the
  facet's current selection, but a hidden section that holds a selection (the
  detail page's tag chip selects one) stays visible until it is cleared, so no
  control-less filter can narrow the list. When every available section is
  hidden the panel says so rather than reporting an empty collection.
- Actions: new dance, import, duplicate, batch tag (with Select all over the
  current results; picks a search hides stay selected and are counted as "not
  shown", N4). Group by category stays on while selecting; each section
  header carries a tri-state checkbox for its shown rows, as one semantics node
  with checked/mixed state and a tap action (N4-S2). Each row's ⋮ menu also
  offers Duplicate, Add to program, Add tags (one dance, same picker and Undo
  as batch tag) and Delete (#1416). Add to program opens a sheet whose pinned
  first row creates a new program with the dance. Its list shows open programs
  first (soonest event, then last edit), a status on each row, Performed ones
  collapsed under "Performed (N)", and a search over title and venue above eight
  programs (N3-A2). A program already holding the
  dance, as a main slot or an alternate, is marked "In this program" and asks
  before adding it again (N3-A1; `docs/design/add-to-program-sheet.md`).

### 2. Dance detail / card
- Header: title, authors, formation, hook, tags, status banner (deprecated/
  broken), provenance line ("via The Caller's Box · CC-BY-NC").
- Figure table grouped by derived section (A1…), beats column, progression ¶
  marker; dialect applied. Toggle: canonical ⇄ dialect view. A `meanwhile`
  container (#590/#594) renders its concurrent sides joined by "while" on one
  row with a single shared beat count — never split, never double-counted.
- Side panel/tabs: calling notes, links (source/video/related), calling
  history (from performed programs), custom fields.
- Actions: edit, duplicate, add-to-program (same sheet and marker as the
  Collection row menu), print/share, Perform this dance.
- Text selection (desktop only, N5-S1; `docs/design/selectable-text.md`): on
  Windows, macOS and Linux the body is one `SelectableContent` region, so a drag
  selects across the title, hook, figures, notes and links, and a secondary tap
  shows Copy / Select all. Tag chips, the beats column and the import-gap badge
  are `SelectionContainer.disabled`; phones and Perform are unchanged.

### 3. Dance editor
- **Keyboard-first figure entry** (the CC "Insert Call" lesson): type-ahead
  move picker — typing "sw" offers swing; Enter accepts defaults (who/beats).
  Enter takes the option named exactly by the text first ("star" is star, not
  star through), then, with free-text entry on, a shorthand with that token,
  and only then the first option offered (audit AUTH-8);
  Tab cycles named params with sensible defaults from the taxonomy; running
  beat count per section shown continuously (overflow = inline warning, not
  error). Full entry of a standard dance must be achievable in <1 min without
  the mouse.
- Custom figure = just typing free text where no move matches; a beats field
  sets the figure's duration; lingo-line feedback (recognized terms underlined,
  discouraged struck) as you type.
- Figure reordering: drag handle **plus** move-up/down buttons + cut/paste
  (WCAG 2.5.7).
- **Meanwhile (simultaneous figures)**: a figure row's overflow menu can group
  it with the next row into one 2–6-side concurrent group, each side authored
  with the same figure editor and one shared beats field for the whole group;
  removing down to 1 side auto-collapses back to a plain figure (#590/#593).
  Until the author types a count there, the field follows the sides: the
  longest side's, or a modifier group's core's (audit AUTH-11).
- **The user's own compound figures** (#709), while Custom Figures is on: the
  move picker of a top-level row lists matching ones first, marked as the
  user's own in words. Picking one makes the row an editor-only placeholder —
  the figure's name and one editor per parameter, narrowed to the values it
  accepts, with progression and note but no walkthrough or wording override —
  which is never grouped into a container and is expanded into
  ordinary figures when the dance is saved, or kept as a custom figure bearing
  its name when it no longer expands.
  Both lists, compounds and new figures, offer only entries tagged with the
  dance's form (untagged ones count as contra).
- **The user's own new figures** (#1023), while Custom Figures is on: offered
  the same way, and inside meanwhile, modifier and sequence children too.
  Picking one makes
  the row a free-text figure carrying a soft reference to it, seeded with its
  defaults and default beats; the row edits one value per declared parameter
  (choices by their labels) and its beats (not inside a meanwhile side or
  modifier child, whose group owns them; a sequence step keeps its own), with progression and note but no line of its own, walkthrough or
  wording override. The row reads with the figure's current wording, and a save
  stores that line beside it. A row whose figure is gone says so and keeps its
  line.
- Metadata form with author autocomplete (choreographer table), formation
  picker, custom fields.
- **Field labels**: a text field or dropdown carries a floating label inside
  the field (Title, Type, Formation); a chip group (authors, tags) or a
  repeating group of fields (tunes, links, sources, related dances, custom
  fields) keeps a heading above it, because a floating label belongs to one
  field, not a group.
- **Reading width**: dance detail, this form, the Settings panes and the user
  guide's text stop growing at 760 px and stay centred, with the scrollbar at
  the window edge (`widgets/readable_width.dart`; maintainer decision D-8,
  2026-10-29). The program screens are not yet capped.
- Autosave drafts; explicit save commits; undo history.

### 4. Programs list & builder
- List: sort by title/recently-updated/event date; opens in the saved default
  sort and direction (Settings ▸ Defaults, added by issue #895 — Programs
  previously had none; the direction control by issue #1841, natural unless
  changed), or the last-used sort and direction if that mode is selected.
  Survives crossing the
  list/detail split-pane breakpoint, same as Collection above.
- Builder: two-pane — program (ordered slots) | collection picker with the
  same filter panel as Collection, including caller-scoped Called / Not called
  history filtering, and Collection's Search in, sort (session-only, opening in
  the Collection default sort and never written back) and card-field choice;
  online search takes Search in's Title / Author / Figure as Collection does
  (FIND-7, PRES-15; shared controls in `widgets/collection_search_controls.dart`). A sustained primary press is an optional, temporary preview
  shortcut: a picker result replaces the program pane while held and a dance
  slot replaces the picker pane while held. Each eligible result and dance slot
  also exposes a visible, keyboard-operable **View details** action that opens
  an explicitly closable, read-only preview; short taps keep their add/import
  behavior.
- Slots: dance slots + free-text slots (break, waltz, announcements); **ALT
  flag** renders as an indented alternate under its primary (color + icon +
  text, never color alone). A free-text slot's overflow menu offers **create a
  dance from this**, opening the dance editor pre-filled from the note and
  linking the slot to the saved dance (issue #881). A non-break note slot also
  offers **Replace…**, clearing the note while preserving its timing details.
  A dance slot's edit dialog offers **Replace…**, swapping its dance via the
  collection picker while preserving the slot's note/guest caller/planned
  minutes/mark-performed status (issue #964).
- Reorder: drag + non-drag alternative; slot notes inline. Below the 600dp
  compact breakpoint (or in a program pane narrower than the full row), a slot
  row keeps only its drag handle and overflow menu; move up / move down lead
  that menu, followed by View details and cut. This is maintainer decision
  D-2 of the October 2026 UX audit: "(a) Drag handle and ⋮ only. View, Up,
  Down and Cut move into ⋮, with Up and Down first." It is recorded in
  [maintainer-decisions-2026-10-29.md](https://github.com/ibanner56/CallersCompendium/blob/c650d90c2839619f6b9987dbe260cdf8c3d76cf9/docs/dev/audits/2026-10-behavior/maintainer-decisions-2026-10-29.md).
- **Matrix view** tab: figures × dances grid computed from structured data
  (moves as columns, per-dance presence + program-debut and dance-first-figure
  highlights) — CC's
  programming matrix without the manual checklist. Horizontally scrollable,
  row/column headers pinned, AT-navigable as a table. When columns overflow,
  the pinned header strip shows a gradient-plus-chevron edge cue on whichever
  side(s) have more content, so off-screen columns are discoverable without
  relying on colour alone. A pinned **Formation** column (icon + text, plain —
  no colour tint) sits next to the dance-title column so each dance's
  formation stays visible while scrolling through moves; the compact
  (phone-width) view surfaces it on each dance chip instead, visually only for
  non-default formations to avoid clutter, always via semantics for screen
  readers. The programming-matrix PDF export mirrors the same pinned
  formation column. A transient **Show phrase labels** control can replace
  comparable cell markers with ordered phrase labels (A1, A2, B1, B2…);
  custom and compound columns retain their markers. Each figure of your own
  whose uses render live has a column of its own while Custom Figures is on,
  labelled by its name, which takes phrase labels and flags repeats like a
  built-in move (#1023); otherwise its uses are in the custom column. The control is editor-owned,
  survives Matrix/Build switches and window resizing, resets when the editor
  closes, and does not affect PDF output or the legend.
- Header: event date/venue/notes; duplicate program; print/export (PDF, text);
  "mark performed" stamps performedAt on called slots (feeds calling history).

### 5. Performance mode
- Full-screen card: current dance, huge type (user-set size/weight/spacing,
  no upper bound), 7:1 contrast themes (dark-stage default), wake-lock on. A
  `meanwhile` container (#590/#594) shows both concurrent sides on one card
  row joined by "while", on their single shared beat span; the screen-reader
  announcement reads the pair as one continuous "A while B" phrase.
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
  only where undo is impossible. One named exception, by maintainer decision
  (N3-4): the add-to-program sheet asks "Add it again?" before adding a dance
  the program already holds, though the add is undoable. Cancel keeps the sheet
  open. Other flows do not cite the exception.
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
