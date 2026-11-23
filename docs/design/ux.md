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

- **Phones held upright** (window below 720 px; most phones on their side are
  720 px or wider and get the rail, the smallest stay below it): bottom navigation (Collection, Programs,
  Glossary when turned on, Settings, Guide);
  Perform is a mode, not a tab — entered explicitly, exits back to context.
  There is no combined search of dances and programs on the bottom-bar
  layout: the Collection's own search field is its search, and the Programs
  list's app-bar search covers programs only (maintainer, 2026-11-18).
  Ctrl/Cmd-K still searches both.
- **Tablets and desktop** (720 px and wider): left nav rail, whose Search and
  Guide buttons take the destinations' pill (filled only while selected; Search
  never is). Search's ⌘K / Ctrl K hint shows only when a hardware keyboard is
  likely present: always on macOS, Windows and Linux, and on iOS and Android
  from the first letter, Tab, Control, Command or Alt key (keys an on-screen
  keyboard or Android's volume and Back buttons also send do not count). From 900 px, list/detail split panes, where the row open in
  the detail pane carries a `primary` bar down its left edge (plus a `primary`
  title; `selectedRowShape`, issue #2156 — a bar and not a fill, because the
  gallery palettes leave text no contrast to spare for a fill under it). In
  Collection batch selection mode the bar marks the checked rows instead, on
  every width;
  global search shortcut
  (Ctrl/Cmd-K); and a desktop keyboard map (PLAT-7), bound to Control and
  Command alike (in a macOS text field Ctrl-F and Ctrl-N keep moving the
  cursor): Ctrl/Cmd-S saves the open dance or program editor,
  Ctrl/Cmd-N opens a new dance, Ctrl/Cmd-F focuses the Collection's search box
  (global search anywhere else), Ctrl/Cmd-A selects every dance in the
  Collection's current results (only while focus is in the list, never in a
  text field, and it never deselects), Ctrl/Cmd-, opens Settings, and Esc or
  Ctrl/Cmd-W goes back. A mouse's Back button goes back too, and a right-click
  on a Collection or Programs row opens that row's ⋮ menu. "Back" closes
  whatever a tap outside would close first (a menu, a sheet, a text field's
  toolbar or an autocomplete's options), then leaves the page as system back
  does, so an editor with unsaved changes asks first. New dance, Settings and
  the macOS menu bar's Import and Guide leave pushed pages first through each
  page's own back guard, stop at one that would ask (and ask it), and do
  nothing while a dialog is open or while performing. On macOS a small menu bar (PLAT-8) runs the same commands:
  Settings…, File (New Dance, Import Dances…, Close), View (the system's full
  screen item), Window and Help (User Guide). It replaces the template menu
  whole, so there is no Edit menu; text editing keys and the selection
  right-click menu still work. The binding table is
  `app/lib/src/widgets/app_shortcuts.dart`.
- Responsive breakpoints, one set for every screen (maintainer, 2026-11-18;
  `app/lib/src/theme/app_breakpoints.dart`), measured on the window: below
  720 px, bottom bar and one pane; 720–899 px, rail and one pane (an 11-inch
  iPad in portrait, at 820 pt, is here), Settings included; from 900 px, rail
  and list beside detail, Settings' section list beside the open section, and
  the program builder's picker beside its slots. Same screens, adaptive
  layout, no separate "mobile app". Below 600 px (Material 3's compact width)
  app bars fold secondary actions into "⋮" and dense widgets take their phone
  form. Settings opens on General; its section list is as wide as its
  longest label (180–280 px), and when even one word of a label would not fit
  at 280 px (very large text) Settings keeps its one-pane layout rather than
  break the word. A window under 480 px tall (a phone in landscape) is short:
  there each screen's labelled floating button ("New dance", "Edit") folds to
  its icon, with the label as its tooltip.

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
- The row of search tools (with the online source selector) and the result
  count are pinned headers in the Collection's scroll view; the open tool's
  panel scrolls between them. Each stays pinned only while the pinned headers
  together cover at most half the list's viewport, so large text on a short
  screen falls back to scrolling (`PinnedWhileRoomSliver`).
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
- Actions: new dance, import, duplicate, batch tag, level, rating, status, tunes, custom field and delete (with Select all over the
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
- Header: title, authors with the composed year ("Pat Shaw (1951)"),
  interpreters with the interpreted year on their own line ("Interpreted by
  Cecil Sharp (1916)"; either line shows a year alone, labelled, when there
  are no names), formation, meter and key (one labelled line, only
  when either is set), hook, tags, status banner (deprecated/broken),
  provenance line ("via The Caller's Box · CC-BY-NC").
- Figure table grouped by derived section (A1…), beats column, progression ¶
  marker; dialect applied. Toggle: canonical ⇄ dialect view. A `meanwhile`
  container (#590/#594) renders its concurrent sides joined by "while" on one
  row with a single shared beat count — never split, never double-counted.
- Sections after the figures include tunes and, when set, the Barnes
  reference ("Barnes books").
- Side panel/tabs: calling notes, links (source/video/related), calling
  history (from every program the dance is in by default; only from programs
  with the slot marked performed when *Require "mark performed"* is on, and an
  alternate counts only once marked performed either way), custom fields.
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
- Unrecognized figure = just typing free text where no move matches; a beats field
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
  ordinary figures when the dance is saved, or kept as an unrecognized figure bearing
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
- **Width**: content is left-aligned and fills the window; it is not capped or
  centred. A 760 px centred column was tried in v0.9.0-beta and reverted
  because it left too much of a wide window empty. Keeping a figure's beats
  near its words on wide windows is tracked in
  [#2231](https://github.com/ibanner56/CallersCompendium/issues/2231).
- Autosave drafts; explicit save commits; undo history.

### 4. Programs list & builder
- List: sort by title/recently-updated/event date; opens in the saved default
  sort and direction (Settings ▸ Defaults, added by issue #895 — Programs
  previously had none; the direction control by issue #1841, natural unless
  changed), or the last-used sort and direction if that mode is selected.
  Survives crossing the
  list/detail split-pane breakpoint, same as Collection above.
- Archived programs are hidden from the list. The ⋮ menu's **Show archived**
  (just above Recently deleted) lists them too, marked with an "Archived"
  chip, and then reads **Hide archived**. The choice is session-only: it
  survives opening programs and the builder and crossing the breakpoint, and
  resets when another top-level destination is chosen or the app restarts.
  A row's ⋮ menu offers Archive (Unarchive on an archived row) after
  Duplicate; the summary and the builder offer it after Duplicate too, and
  archiving there leaves the program as Delete does. On the wide layout, the
  open program also closes when it stops being listed (archived from its row
  or elsewhere, hidden by Hide archived, or by the Show archived reset when
  Programs is left), including a selection handed over by a rotation. Restoring a program from Recently deleted
  unarchives it; a delete's Undo does not.
- New program (#2337): with two or more program templates, New program first
  opens a short bottom sheet titled "Start from a template", listing the
  templates in the user's order with the Default template first and marked
  "Default", and **Blank program** (first and marked when it is the default,
  otherwise last). Dismissing the sheet cancels. With zero or one template
  there is no sheet: the builder opens on the Default template, so the common
  case costs no extra tap. The templates are managed in Settings ▸ Defaults ▸
  Program defaults ▸ Program templates, a full-screen manager that floats
  **New template** once it has a list (the empty state carries its own
  button), reorders by drag or move up / move down, and offers Rename,
  Duplicate and Delete (with Undo) from each row's ⋮ menu.
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
  [maintainer-decisions-2026-10-29.md](../dev/audits/2026-10-behavior/maintainer-decisions-2026-10-29.md).
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
  no upper bound), 7:1 contrast themes (dark-stage default), wake-lock on.
  The header adds the composed year to the authors line, the interpreters and
  interpreted year on their own line, the dance's meter and key on one
  labelled row when either is set, and its Barnes reference on a labelled row
  of its own ("Barnes: BIII p. 92") when set. A `meanwhile` container
  (#590/#594) shows both concurrent sides on one card row joined by "while",
  on their single shared beat span; the screen-reader announcement reads the
  pair as one continuous "A while B" phrase.
- Full screen (PLAT-9): phones and tablets go immersive for the whole view.
  Desktop offers a toolbar toggle plus F11 (Ctrl-Cmd-F on macOS); Esc leaves
  full screen but never Perform. Ctrl/Cmd-W and mouse Back reach Perform's
  exit confirmation, as system back does, while **Confirm before leaving
  Perform** is on (the default); with it off, all three leave at once. The app-wide shortcuts
  (Ctrl/Cmd-K, -N, -F, -,) do nothing while performing. Exit restores the window's entry state, and no
  window frame is persisted while the window is full screen.
- Navigation: giant next/prev hit zones at screen edges (44pt+), on-screen
  prev/next buttons, arrow keys/page keys, jump-to-slot overview. There is no
  swipe (horizontal drag) navigation: a swipe does not change slot. ALT dances
  one tap to swap.
  ↓/Page Down scroll an overflowing card to its end before advancing, and
  ↑/Page Up scroll to its top before going back; ←/→ always change slot, and a
  new slot opens at its top (PLAT-10). A single dance's Perform view has no
  slot to advance to, so those four keys only scroll its card (or its
  walkthrough while that is open), stopping at the ends.
- Zero destructive actions reachable; exit via deliberate gesture/button with
  confirm by default (Settings › Program › Performance). Optional: per-slot timer/clock display.
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
- **One rule for delete**, in `utils/confirm_delete.dart`: Undo wherever the
  data can be restored, one shared permanent-delete confirmation for
  everything else, swipe-to-delete left as it is, and a setting for how long
  the Undo prompt stays, which also stays while hovered or focused:
  - A delete whose data can be restored deletes at once and offers Undo:
    dances, programs, tags, authors, sources, venues and custom fields
    (database rows), and shorthands, dialects, custom themes, walkthrough
    snippets and matrix columns (settings values; Undo writes the removed
    entry back). It asks first only through `confirmDeleteIfEnabled`, when
    *Confirm before delete* is on.
  - A delete nothing can bring back confirms every time through
    `confirmPermanentDelete`, which adds "This can't be undone." and is not
    switched off by *Confirm before delete*.
  - Swipe-to-delete never asks: the swipe reveals a Delete button that takes a
    second tap, and that tap is the confirmation.
  - Every confirmation that removes, resets, overwrites or discards uses
    `destructiveFilledButtonStyle` and names its action ("Delete", "Reset",
    "Replace", "Disconnect"), never "Continue" or "OK". "Delete" destroys;
    "Remove" takes something out of a list without destroying it.
  - The Undo prompt (`utils/undo_snack_bar.dart`) stays for the user's *Undo
    prompt* setting (10 s unless changed; `undo_prompt_seconds`), stays while it
    is hovered or keyboard focus is inside it, and never times out with a
    screen reader running or when the user chose "Until I close it".
- Empty states teach: first-run Collection offers "download the community
  collection" (snapshot) and "import your data".
  - Every screen and pane that can be empty uses `EmptyState` (a glyph, a
    heading that screen readers can jump to, a body, at most one action), not a
    bare line of text; a short list inside a section of a larger screen uses
    its `inline` form. A one-line note remains for a small list inside a
    dialog or a field group, and for read-only and Perform views, where
    nothing can be added. Where there is something to create, the body names the
    button ("Choose New shorthand to add one.") and the action is that button;
    where entries come from elsewhere, the body says where.
  - A screen whose whole body failed to load uses `LoadErrorView`: Retry when
    trying again can succeed, Back when the thing is gone and the screen has
    somewhere to go back to, so a failure is not a message with no button. A
    pane with nowhere to leave (the wide Collection's detail pane) shows the
    plain message, since the list beside it is the way on.
  - The brand mark is a quiet touch on empty states, as the Programs list and
    the "select a dance" and "select a program" panes show it; the other empty
    states lead with a muted glyph.
- All lists virtualize; search-as-you-type debounced; target <50 ms query
  budget (storage design).
- Every interactive element: visible focus, name/role/state semantics, 24px+
  targets (44pt in Perform), traversal order = visual order.
- No color-only meaning anywhere (chips/badges pair icon+text).
- **Where Save, New and the record's name go** (maintainer decision D-11 of the
  October 2026 UX audit, UX6-2, for the record's name; Save and the floating
  button revised in November 2026, as marked):
  - **Save.** Every full-screen editor saves from its top bar (maintainer,
    2026-11-18): dance, program, theme, compound, compound shorthand,
    shorthand mapping and dialect. Save is the bar's last action, a labelled
    button that becomes a check icon when the word does not fit; in the two
    long editors, dance and program, it is always the icon below 600 dp, so
    the title keeps room (an implementation choice of November 2026; the
    alternative, the word, left the dance editor's title about 66 dp at
    320 dp). The autosaving calling-card layout editor shows no "saved"
    marker (maintainer, 2026-11-18). A sheet (venue, custom field) keeps its
    own Cancel and Save row.
  - **Perform** starts from a program's summary, not from the program
    builder, which is for editing (maintainer, 2026-11-19).
  - **The floating button** creates, on a list, or opens a record from its
    read view: Edit on dance detail and the program summary (maintainer,
    2026-11-19), and Import on a dance previewed from an online search,
    which takes the same slot (an implementation choice of November 2026; the
    alternative was a top-bar action). It never saves. While an empty state
    or the Collection's first-run card shows its own New button, nothing
    floats (maintainer, 2026-11-18); sort and direction controls also wait
    until there is something to sort. Content under a floating button leaves
    `AppSpacing.fabClearance` below its last row.
  - **New.** A full-screen manager (Collection, Programs, venues, custom
    fields, your figures, shorthands) floats New once it has a list; a list
    inside a settings section (dialects, custom themes, the compound
    shorthands section) creates with an inline button. The Glossary keeps its
    "+" in the top bar, as a reference screen whose entries a floating button
    would cover (left unchanged in November 2026; not revisited by the
    maintainer).
  - **The record's name.** On a record screen with a top bar, the bar keeps its
    generic title and carries the record's actions; the full name keeps its own
    line in the body. The full-screen program summary does this ("Program";
    Export, Mark all performed, Duplicate, Archive and Delete in the bar,
    Perform as a full-width body button; below 600 dp the last four fold into
    the existing
    "⋮" menu). Dance detail already shows the name in a body card. The wide
    Programs split pane has no top bar and keeps its actions on the name's row
    in the body; whether it should change is a separate maintainer call.

## Deliverables next

Low-fi wireframes per screen (Excalidraw/Figma, committed as SVG/PNG under
docs/design/wireframes/) before Phase 3 implementation of each screen; this
doc is the contract for what they must contain.
