# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Added

- **Balance figures now carry an optional hand (right / left / unspecified).**
  When The Caller's Box writes `(RH)` or `(LH)` on a balance line, the hand
  is now preserved instead of being silently dropped — 1,066 instances measured
  corpus-wide. The hand defaults to unspecified, so balances that don't name one
  stay neutral.

- **You can now mark a dance as a mixer.** A mixer is a dance where you change
  partners each time through, so you dance with lots of different people rather
  than staying with one. Tick **Mixer** in the dance editor, just under the
  formation, and the flag shows on the dance's detail page. It's kept separate
  from the formation on purpose: a mixer can be danced in all sorts of shapes,
  and not every circle dance is a mixer — so the two are set independently. When
  you import from The Caller's Box, dances already marked as mixers there come in
  ticked, and Circle Mixers and Scatter Mixers are recognised even when the
  source forgot to flag them.

- **Mixer partner positions are now available as named dancer groups.** When you
  author a figure that involves a mixer's successive partners — the person you'll
  swing after a grand right and left, or the one beyond that — you can now name
  them directly: **prev partners** (the partner before your current one), **next
  partners**, **third partners**, **fourth partners**, and **fifth partners**.
  These appear in the dancer-group dropdown for mixer dances, using the same
  naming pattern: a caller who already knows "next neighbors" can read "next
  partners" without looking anything up. If a figure in a non-mixer dance already
  has one of these stored, it stays visible and editable on that figure — the
  dropdown just doesn't offer them to new figures until you mark the dance a mixer.

- **Mixers are now findable and visible across your whole collection.** A
  **Mixer** chip appears on each mixer dance in your collection list (alongside
  the formation chip). The search and filter panel gains a **Mixer** facet so you
  can filter to mixers in one tap — it only appears if your collection actually
  contains any. In a program, mixer rows get the mixer accent colour (the same
  pink used for scatter mixers), and the word "Mixer" is added to the row text,
  regardless of what formation the dance is in — so a mixer duple improper reads
  as a mixer, not a contra. Mixer dances also show the **Mixer** label on their
  printed and exported dance cards.

- **The app now tells you what to do when your data is too old to open.**
  Previously, a database written by a build older than the supported schema
  floor would show a generic error with a Retry button that could never succeed.
  Now the app shows a dedicated recovery screen that explains the situation and
  offers a concrete path forward: install **v0.1.0-beta.6** (the bridge release),
  open the app once to let it update your data, then install this version again
  — your data is recoverable. If you prefer to start fresh, **Back Up + Reset**
  saves a copy of your database first (fail-closed: if the backup can't be
  written, nothing is wiped), and **Reset Only** warns explicitly that it is
  irreversible before proceeding. A diagnostic log is written alongside the
  backup so you can hand both to a support conversation.

- **You can now import a list of dance titles straight into your collection.**
  Choose **a list of titles** in the import source list, paste your titles one
  per line, and the app checks each against your own collection first, then
  looks up anything you don't already have in The Caller's Box — without
  building a program. Every title you pasted is listed for review, grouped by
  what happened to it: the ones ready to import, the ones you **already have**
  (named with the choreographer, since two dances can share a title), and the
  ones **nothing was found** for — and that last group says which kind of "not
  found" it was, because "the archive has never heard of it" and "the archive
  couldn't be reached" need very different follow-up. A dance is only ever taken
  when exactly one result matches your title exactly; near matches are never
  imported on a guess. Nothing is added until you confirm on the review screen,
  and anything uncertain is set to Skip by default. Blank lines are ignored, a
  repeated title is only looked up once, and you can watch the progress and
  **Cancel** at any point. Lists are limited to 100 titles, and a longer one is
  refused outright rather than partly imported, so you are never left thinking a
  list came in whole when it didn't. Even when nothing turns out to be
  importable, you still get the answer to "which of these do I already have?"

- **The Caller's Box importer now recognises mixer partner-series codes in
  pass lists and prose.** Figures like `Grand right and left (P1R;P2L;P3R;P4L)`
  now decompose into the correct `pull_by_dancers` sequence instead of
  importing as a custom figure. Prose lines like `P2 partner swing` now parse
  as a swing with the named partner set. The range matches the vocabulary: `P`
  and `P1` both mean your current partner, `P0` the previous one, and `P2`–`P5`
  the next through fifth. Pass lists already understood `P` and `P1`; the rest
  of the range is new there, and in prose every one of them is new. `P6` and
  beyond, and any negative form (`P-1`, etc.), continue to decline to custom —
  the taxonomy has no token for them and importing them as a nearer partner
  would be wrong.

- **You can now give your tags colours.** Settings → Appearance → Tag colours
  lists every tag you've created and lets you pick a colour for any of them; the
  colour then shows on that tag's chip in the collection list and on dance
  detail. Tags start with no colour and look exactly as they always have until
  you choose one, and each row has a reset button to take a colour back off. The
  tag's name is always shown beside the colour, and the app picks a black or
  white label automatically so your colour stays readable in every theme,
  including High Contrast. The colour is only ever applied to the tag's own chip
  — never to the row it sits on or to any other chip beside it.

- **Dances already in your program are now marked in the picker.** When you open
  the add-dance sheet or the inline pane, any dance already in the program shows a
  marker on its row. If you've added the same dance more than once, the marker shows
  a count. Nothing changes in the brief confirmation you already see when you tap
  the add button — that still flashes a check for a moment, and the new marker is
  separate from it.
- **Custom figures now have a beats field.** When you edit a custom figure, you
  can set how many beats it takes — the same control you get for any structured
  figure. Previously the model tracked beats for custom figures but the editor
  never showed the field, so there was no way to set or change it.
- **You can now choose which details appear on each dance row in the collection.**
  Settings → Defaults → Collection card fields lets you turn off any of the eight
  chips — authors, times called, formation, status, level, rating, tags, and custom
  fields — to keep your list compact and easy to scan. All chips are on by default.
  Nothing changes in the add-to-program sheet.

- **Importing a single dance that closely matches one you already have now asks
  what you want to do.** When you import from Caller's Box or ContraDB and the
  title and caller match a dance already in your collection — but the figures
  differ — the app now shows a prompt rather than silently adding a second copy.

  You get three choices:

  - **Import as a variation** — adds the incoming dance as a new entry in your
    collection, separate from the existing one.
  - **Same dance** — treats the incoming version as the authoritative one. It
    links the import record to your existing dance and replaces that dance's
    figures, notes, tags and rating with the incoming version. Your call
    history is preserved, since program slots refer to the dance by identity
    rather than content. **This cannot be undone** — if the existing dance has
    edits you want to keep, import as a variation instead.
  - **Cancel** — writes nothing.

  Program import is unchanged and does not prompt. When a program references a
  dance you already have, it links to your existing copy as before.

- **The app is now fully translated in every language it ships in.** German,
  French, Japanese, Danish, and Dutch each had 100 user-facing strings that still
  appeared in English — the meanwhile/concurrent-figure editor, the full month
  names used by custom date formats, the ContraDB "already imported" markers, the
  settings-restore messages, the collection-card field toggles, the tag-colour
  settings, the pasted title-list import and its review groups, the
  shorthand-seeding step, and the custom-field sharing notice. All five languages
  now cover every string in the app.

### Changed

- **On a tablet or desktop, saving a new dance now selects it automatically in
  the detail pane.** Previously, creating a dance and saving left the detail pane
  showing whatever was selected before — or the empty placeholder. Now, after a
  successful save, the new dance is immediately selected and shown beside the
  list. Cancelling the editor still leaves the previous selection unchanged. On a
  phone the editor closes as before — the list and detail are not side by side
  there.

- **The import screen now opens on The Caller's Box.** It previously opened on
  *a Caller's Compendium JSON file*. The source list is also reordered — a list
  of titles, The Caller's Box, ContraDB, a Caller's Compendium JSON file, a
  Caller's Companion .USR file — so the list order and the starting selection are
  now separate things. If you import Compendium JSON files, you will need to pick
  that source from the list rather than finding it already selected. This affects
  both the import pane in Collection and Settings → Import.

- **Qualifier notes on The Caller's Box figures now come through structured.**
  Lines from The Caller's Box that carry a qualifier — for example, a promenade
  "across the set", or one followed by a right and left through — previously imported
  as unstructured custom figures because the note tripped a guard designed for
  other sources. The guard is now skipped for Caller's Box lines, so those figures
  arrive as named moves with the qualifier in a note, exactly as the source states.

  If you re-import a dance from The Caller's Box, figures that previously appeared
  as custom text may now appear as structured ones. Nothing changes in dances you
  do not re-import.

- **Imported dances no longer keep a copy of the page they came from.** When you
  imported a dance from ContraDB, The Caller's Box or a Caller's Companion file,
  the app also stored the original record verbatim — for a web import, the entire
  page. Nothing in the app ever read it back, so it was pure weight: several
  kilobytes per imported dance, carried in your library and in every backup you
  made. It is now removed on upgrade, and no longer stored on new imports.

  Re-importing and duplicate detection are unaffected — those match on the
  source and its record id, and re-fetch from the source when you ask them to.

  **This is not reversible.** Upgrading deletes those stored copies. If you want
  them, export a backup *before* upgrading. Nothing you can see or edit in the
  app is affected: dances, figures, notes, tags, programs and the rest are
  untouched, as is where each dance came from (source, record id, import date,
  permission and license).

### Removed

- An internal `snapshots` table that was never written to. It existed for a
  planned "a newer version of this collection is available" prompt against a
  hosted archive — a feature that was dropped in favour of importing directly
  from the source.
- **Support for collections last opened by beta.1 or earlier.** Caller's
  Compendium will no longer open a collection file that old; it stops rather
  than upgrading it halfway, which would leave the file quietly incomplete.
  Every tester is on beta.2 or later, so in practice no collection is affected.
  If you do still have a pre-beta.2 file, open it once with beta.2 — or any
  later release you already have — and it will be upgraded normally, after which
  this release can open it.

### Fixed

- **Importing a `.ccshare` file through the manual Import picker now includes the
  program.** Previously, picking a `.ccshare` file from the "Choose file" button
  silently dropped any program it contained — you'd see the dances arrive but the
  program (with its event details, venue, and slot order) was quietly lost. Now
  the program, venue, and all slot details are imported alongside the dances,
  exactly as they are when you open the file directly from Files. The import can
  be undone in one tap.

- **Aliased moves now re-route when their defining param is toggled.** Setting
  `hand: left` on a box the gnat makes it a swat the flea (and vice versa); the
  same applies to do si do ⇄ see saw on shoulder. Previously the move's name and
  data could disagree — the figure would read "swat the flea" while carrying
  right-hand data. The fix lives in the taxonomy so every writer (import, editor,
  share) benefits, not just the editor.

- **The Caller's Box balance + box/swat import fold now preserves handedness.**
  A balance with `(RH)` followed by a box the gnat imports as one figure with
  the hand set, rather than losing the hand annotation.

- **Programs recorded before you set a default caller now appear in calling
  history and "called ×N" counts.** With "Track calling history for all
  callers" off and a default caller configured, any program whose caller field
  was blank or never filled in was silently excluded — so setting your own name
  as default caller would make your entire pre-existing history disappear. Those
  programs are now treated as your own and included alongside programs that
  explicitly match the default caller. Programs led by a different, non-blank
  caller remain excluded as before. (#850, supersedes the null-caller exclusion
  from #583)

- **A figure with 0 beats at the end of a dance no longer creates a ghost
  section.** If the last figure in your dance takes no beats of its own — like
  a "form short waves" placed right at the end — it used to appear as a brand
  new A1 section below B2 instead of staying at the bottom of B2. Similarly,
  a 0-beat figure at any phrase boundary was quietly filed one phrase too late.
  Both are now corrected. The fix also updates section-filtered search, so
  searching for "B2, form short waves" now finds dances where that figure
  was affected. Existing dances are recomputed on first open.

- **Individual dancers now read by name everywhere, and you can reword them.**
  Where a figure names one dancer rather than a pair — the lead of a figure 8,
  the dolphin in a dolphin hey, or any "who"/"whom" you set to a single dancer —
  the people picker showed the internal `twos role2` instead of "second robin".
  So did the figure line, Perform mode and PDF export. All of them now use your
  dialect's role terms. If you'd rather say "robin two", Settings → Dialect →
  dancer terms now lists these four dancers so you can enter your own wording;
  they were missing from that list entirely. Nothing about your saved dances
  changes — this was only how they were displayed, and search results are
  unaffected.

- **Meanwhile containers now report their true structure quality, and the reparse
  screen can now upgrade figures inside them.** Both the import review quality
  chip and the "reparse custom figures" screen previously counted a meanwhile
  group — two moves that happen at the same time — as fully structured even when
  its concurrent sides were unstructured custom text. Quality chips will now show
  lower scores for dances that contain such groups, and the reparse screen will
  offer to upgrade sides inside them that the parser can now handle.

- **Opening a program now takes you to the program, not the builder.** Two
  places dropped you straight into the program editor instead of the
  read-focused summary: the list of programs in a dance's calling history, and
  picking a program from the global search palette (Ctrl/Cmd-K). Both now open
  the same summary you get by tapping a program in the programs list — with
  "Perform this program" front and centre, and "Edit program" a tap away if you
  did want to change something.

- **Square-through pass lists from The Caller's Box now decode correctly.**
  Lines of the form "Square through 2 (N2R;SL)" carry a compact pass list that
  specifies which dancers and which hands for each pass. Previously the pass list
  was stripped before recognition, leaving the figure with the move's generic
  defaults: the wrong dancer pair and a balance the line never calls. The pass
  list is now decoded — dancer pairs come from the codes, hands alternate by
  parity, and no balance is added unless the source line states one.

- **"Followed by" search no longer matches both directions of a simultaneous
  figure.** If a dance has two figures that happen at the same time (a "meanwhile"
  or "while" container), searching for one followed by the other used to match
  both `Then(X, Y)` and `Then(Y, X)`, even though neither side comes before the
  other. It now only matches genuine sequences where one figure actually precedes
  the next.

- **Star grip and single-file flag now appear in the figure display.** When a
  star figure specifies a grip (`wrist grip` or `hands across`) and when a
  promenade or circle specifies single-file, those details are now shown in the
  figure text. Previously they were stored correctly on import but invisible in
  every rendered form.

- **Adding a dance to a program now visibly confirms itself.** On a phone the
  dance picker opens as a panel covering almost the whole screen, and the
  "Added …" message appeared *behind* it — so on the one screen where you build
  a program, tapping `+` looked like it did nothing. The dance was always added,
  and the message was always announced to screen readers; you just couldn't see
  it. The `+` on the row you tapped now briefly becomes a check, then returns to
  a `+` so you can add the same dance again. The message still appears as before
  everywhere it was already visible.

- **Importing a dance from a different source that you already have now prompts
  you instead of silently adding a second copy.** When a dance from ContraDB or
  Caller's Box matches one you already imported from the other source — same
  title, same caller, same figures — the app now asks what you want to do rather
  than creating a duplicate. You can choose **Same dance** to link the import to
  your existing copy — this replaces your version of the dance with the online
  record's, including its figures, notes, tags, rating, and custom fields; its
  place in your programs and its calling history are kept — **Import a second
  copy** to
  add it alongside your existing dance and keep both source records, or
  **Cancel** to leave your collection as it is.

  This prompt is for the identical-figures case only. When a confident match has
  *different* figures, you still see the three-option variation prompt introduced
  earlier. Program import is not affected.

## [0.1.0] - 2026-08-01

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.6`** (this pre-release) builds
on **`v0.1.0-beta.5`** and is the largest beta so far. Its theme is **getting your
existing library in, faithfully**: Caller's Companion files now bring their
choreography across (previously they arrived with no figures at all), and
thousands of Caller's Box and ContraDB lines that used to land as unstructured
text — balanced waves, courtesy turns, mad robins, walk-forward figures, spelled-out
shorthands — now import as real, searchable figures. Alongside that: **"meanwhile"
(simultaneous) figures** are supported end to end, **pickers finally work on a
phone**, and a **three-audit security and robustness pass** landed. The changes
**since beta.5** are grouped first; the standing feature overview and install notes
follow.

> Upgrading rewrites some stored figures (schema 15 → 20). It is automatic and
> preserves every dance's timing — see **Data / Migrations** below.

### Added

- **"Courtesy turn" is now a real figure.** Until now, a Caller's Box dance that
  called a courtesy turn on its own line landed in the unrecognized "custom"
  bucket — around 115 lines across the whole Caller's Box collection. They now
  import as a proper figure you can search, edit and swap the dialect on, with
  the pairing ("partner", "neighbor", "N2 neighbor"), the direction when the
  source gives one, and the dancer you end up facing when it says
  "…, face N2".
  - The app only records what the source actually says. A courtesy turn is
    clockwise unless told otherwise, so the direction is only spelled out when
    it isn't — and notes like "(in center)" or "(continued)" are kept
    word-for-word next to the figure rather than being dropped.
  - Anything the app can't represent exactly is still kept as plain text, so
    nothing is quietly lost or guessed at: a ladies' chain that mentions its own
    courtesy turn, an "arky" courtesy turn (roles reversed), a courtesy turn
    with a stated amount like "3/4", and dancers the app doesn't model
    ("phantom partner", "P2 partner", "next corner") all stay as written.
  - As a bonus, thirteen dances that spell a "modified ladies chain" or "wheel
    chain" out into its parts now import those parts too — previously the whole
    block stayed unrecognized because one of its steps was the courtesy turn.
  - Beat counts and section placement are unchanged for every existing dance.

- **Caller's Box imports now understand shorthand figures written as their
  parts.** A grand right and left that lists its passes — e.g.
  `Grand right and left (N1R;N2L)` — imports as the individual pull-bys it is
  made of. And when The Caller's Box spells a named figure out into indented
  sub-figures, those sub-figures are now imported instead of the whole block
  landing in the unrecognized "custom" bucket — flutterwheel, interrupted square
  through, modified right and left through, open ladies chain, Georgia rang
  tang, hey along sides and many more. The figure's own name is kept as a note
  on the first part, so nothing you'd search for is lost. Beat counts and
  A1/A2/B1/B2 section placement are unchanged. Anything the app cannot represent
  faithfully — a pass with a dancer we have no name for, extra wording on the
  line, or a sub-figure we don't recognize — is still kept verbatim rather than
  guessed at.

- **Aggressively recompute figure beats (opt-in).** New Settings toggle under
  Defaults > Dance-authoring defaults: "Aggressively recompute figure beats".
  Off by default (today's behavior is unchanged) — a figure's beat count is
  only auto-derived from its move's default while you haven't taken ownership
  of the value. When turned on, changing a figure's move or any parameter that
  affects timing immediately recalculates its beat count, even overwriting a
  beat count you typed in by hand; the setting's subtitle states this
  explicitly so the trade-off is never a surprise. Closes #689.

- **Balanced waves from The Caller's Box import as real figures.** TCB writes
  "Balance wave of four (NR,WL)" or "Balance long wave (NR, women face in)" as
  its own line — 4,613 lines across the full Caller's Box corpus, and by far the
  biggest reason an imported dance still showed rows of unstructured text. Those
  lines now come in as a proper wave figure that carries its balance, with the
  hands and roles TCB stated ("who's in the centre, by which hand") preserved
  rather than dropped. A balanced wave now also *says* so on screen: figures
  read "form short waves - … - and balance". Timing is untouched — every dance's
  beat totals and A1/A2/B1/B2 placement are byte-identical to before. Lines we
  can't model faithfully (waves of two or three, interlocking or intersecting
  waves, annotations naming two hand-holds at once) deliberately stay as text
  rather than being guessed at. Closes #296 and part of #295.

- **"Form a wave" is now called "form short waves".** The figure covers the
  whole set's short waves, which is how The Caller's Box always writes it, so
  the picker and every rendered figure use the clearer name. Your existing
  dances are updated automatically the first time you open the app after
  updating; the old name still finds the move when you search.

- **Mad robins and butterfly whirls import as real figures.** Caller's Box
  dances that write "Mad robin clockwise around neighbor" or "Partner butterfly
  whirl counterclockwise" used to land as unstructured custom text, because the
  figure model had nowhere to put the direction or the dancer you go around.
  Both moves now carry those details, so those lines import as proper figures —
  searchable, editable in the figure editor (new **Direction** and **Whom**
  fields), and rendered in your dialect. Nothing is invented: a line that
  doesn't state both facts still imports verbatim as a custom figure, and
  existing dances are untouched.

- **First day of week is live.** The Language & region settings dropdown for
  first day of week (System default / Sunday / Monday / Saturday) is no
  longer disabled — it now has a real consumer, the Programs list's "this
  week" header strip, which reorders its weekday columns to match your
  choice (falling back to your app language's convention for System
  default). Closes #636.

- **Hide columns you don't need in the program matrix, with a one-tap
  reset.** Each move column in the wide grid now has a small eye glyph — always
  visible (not hover-only, so it works on touch and for keyboard/AT users too)
  and focusable — that hides that column from view. A "Show all columns"
  button next to the PDF-export button clears every hidden column at once; it's
  disabled whenever nothing is hidden. Hiding is a session-only view
  preference (it resets whenever you reopen the program) and only affects
  what's on screen — the PDF/print export always includes every column,
  hidden or not. The pinned Formation column isn't hideable, since it's part
  of each dance's identity rather than a move. Closes #669.

- **The program matrix now shows each dance's formation.** A new pinned
  "Formation" column sits next to the dance title in the wide grid — always
  visible while scrolling through moves, so callers can spot too many
  non-improper formations (Becket, triple minor, 4x4, …) stacking up in a
  row. The compact (phone-width) view announces the formation on every dance
  chip for screen readers, and shows it visually only for the atypical,
  non-duple-improper case, keeping the common-case chip uncluttered.
  Deliberately plain (icon + text, no colour tint) — the issue chose a
  dedicated column over colour-coding formations. The programming-matrix PDF
  export gets the same pinned formation column, so the on-screen and printed
  matrices stay in sync. Closes #663.

- **Comma-separated dates and single-digit days in your custom date format.**
  The custom date-format pattern (Settings ▸ Language & region ▸ Date format ▸
  Custom) now accepts a comma as a separator and a single, non-zero-padded `d`
  day token alongside the existing `dd` — so `MMMM d, yyyy` reads and renders
  the natural "June 3, 2026" (previously only "June 03 2026", via `dd`, was
  accepted). `d MMMM yyyy` similarly renders "3 June 2026". The comma also
  works when reading the same layout from a ContraDB program title on import.
  As before, the pattern stays an untrusted, strictly allowlisted input —
  only these two well-scoped additions were made, no arbitrary format strings
  are accepted, and every other rule (length cap, one field of each kind,
  bounded ReDoS-safe matching, 1900–2100 calendar validation) is unchanged.
  Follow-up to the written-out month support from the previous release.
  Closes #668.

- **"Meanwhile" (simultaneous) figures now display as "A while B" (#594).**
  The dance detail figure table, Perform view, plain-text export, and PDF
  export all show a simultaneity pair together on one row/line, joined by
  "while", with the shared beat count shown once — never split into two
  rows/lines and never double-counted.

- **Importing a simultaneous-action line now keeps both sides instead of one
  opaque blob (#591).** The Caller's Box `||` operator (e.g. "Women allemande
  left 1 || Men orbit clockwise ½") and ContraDB free-text joined by
  "while"/"whiles" (e.g. "ladles allemande left 1½ around while the
  gentlespoons orbit clockwise ½ around") now import as a "meanwhile"
  container with each side parsed independently, instead of the whole line
  becoming a single unstructured custom figure. A side that isn't recognized
  still imports safely as its own custom sub-figure — nothing is dropped or
  invented — and the shared beat count is counted once. Re-syncing an
  existing dance upgrades any older `||`/"while" line the same way. Part of
  #572.

- **Author simultaneous ("meanwhile") figures in the figure editor.** A figure
  row's overflow menu now offers **Group with next as meanwhile**, merging it
  with the row right after into one editable group of 2–6 concurrent sides —
  each authored with the same move-picker/param/note editor as any other
  figure, plus a single **shared beats** field for the whole group (a side's
  own beats is display-only and hidden to avoid a confusing dead control).
  Add or remove a side with clear inline controls; removing down to 1 side
  automatically collapses the group back to a plain figure. The group is
  always **flat** — a side can never itself become a meanwhile group — and
  the 2–6 side range is enforced right in the editor with a clear message at
  the cap, not just a thrown error. Undo/redo and autosave carry a group
  through losslessly. Builds on the `meanwhile` model container (#590).
  (#593, part of #572)

- **Write out the month in your custom date format.** The custom date-format
  pattern (Settings ▸ Language & region ▸ Date format ▸ Custom) now understands
  written-out month tokens alongside the numeric ones: `MMM` renders a short
  month name (e.g. `dd MMM yyyy` → `03 Jun 2026`) and `MMMM` a full one
  (e.g. `MMMM dd yyyy` → `June 03 2026`). Month names are localized — they
  reuse the app's existing translated short names, with English full names where
  a translation isn't available yet. The token legend under the field documents
  the new tokens, and the live example plus the inline "unrecognized pattern"
  warning work with them too. When a ContraDB program title contains a written
  month (e.g. `Spring Fling — 12 May 2026`), a custom pattern that uses `MMM`/
  `MMMM` now reads that date on import. As before, the pattern is untrusted
  input: it is length-capped, month names are matched against a fixed allowlist
  (no catastrophic-backtracking risk), and anything unrecognized simply falls
  back to the system default. Follow-up to the custom date format from the
  previous release.

- **Partial heys can name the dancer you run until you meet.** When a hey is set
  to **less than half** or **between half and full**, the editor now offers a
  **meet target** — the pair you weave until you meet (e.g. partners, neighbors,
  larks/robins). The dance then reads "…until neighbors meet" instead of the
  generic "…until someone meets". Leave it **unspecified** (the default) and
  everything renders exactly as before; the field only appears for those two
  partial lengths, and clears itself if you switch the hey back to a half or full
  hey. The target is an allow-listed set of pairs, so imported or hand-edited data
  can never inject unexpected text. (#576)

- **See which ContraDB programs you've already imported.** When you search or
  preview a program in **Import program ▸ From ContraDB**, rows you've likely
  already brought in are marked: a firm **Imported** badge (with the import date
  in its tooltip) when the exact ContraDB program was imported before, and a
  softer **Possibly imported** badge when a program with the same title already
  exists but isn't linked to that event. Each badge pairs an icon with a label so
  colour is never the only signal, and the same hint shows atop the preview.
  Re-importing is still always allowed. ContraDB program imports now record the
  source program id so the firm match works; programs imported earlier (with no
  stored id) fall back to the title-only hint. ContraDB titles and ids are treated
  as untrusted input — normalized, length-capped, and matched with ReDoS-safe
  comparisons. (#586)

- **Custom date format.** The **Settings ▸ Language & region ▸ Date format**
  picker gains a **Custom…** option that reveals a text box for your own pattern
  (e.g. `MM.DD.YY`), with an always-visible token legend (`yyyy`/`yy` = year,
  `MM` = month, `dd` = day; separators `-` `/` `.` or space), a live example, and
  an inline warning when the pattern isn't recognized. A valid custom pattern
  renders program event dates and helps disambiguate numeric dates when
  auto-detecting the event date from a ContraDB program title. The pattern is
  treated as untrusted input — length-capped, allowlist-validated, and
  ReDoS-safe — and any empty, unrecognized, or corrupted value falls back to the
  system default everywhere until it's corrected. (#584)

- **Scope calling history to your own programs.** A new **General ▸ Calling
  history** setting, **Track calling history for all callers** (off by
  default), lets a caller who has set a *default caller for new programs*
  (**Settings ▸ Defaults**) count only the programs **they** led toward each
  dance's calling history and "called ×N" totals. With the toggle off and a
  default caller set, history and counts include only programs whose host
  caller matches that name (ignoring surrounding spaces and letter case);
  turning it on — or leaving the default caller blank — tracks every program
  that contains the dance, exactly as before. The filter matches on the
  program's host caller (per-slot guest callers are not considered) and applies
  on top of the existing *Require "mark performed" for calling history* gate
  (both must pass). (#583)

- **Program matrix flags same-figure-same-phrase repeats between neighbouring
  dances.** In the Matrix tab, a cell now shows an alert marker instead of the
  plain check when the same move lands in the *same phrase* (A1/A2/B1/B2…) in
  two dances that run **back-to-back** in the program — the kind of adjacent
  repeat that can make two dances feel samey on the floor. Only the two
  colliding cells are flagged; repeats that are non-adjacent or in a different
  phrase are left alone. The alert carries into the landscape **PDF matrix
  export** and its legend, and — like the existing star/flag/check markers — is
  conveyed with a distinct shape plus a localized screen-reader announcement,
  never colour alone (WCAG 1.4.1). (#582)

- **Your Caller's Companion library now imports its choreography, not just its
  dance list.** A `.USR` import previously brought across every dance's metadata
  and your programs but **no figures at all** — Caller's Companion keeps the
  actual transcription in a separate place the importer never read. Those
  figures now come across, routed through the same recognizer the other sources
  use, so a migrated dance arrives with real A1/A2/B1/B2 choreography you can
  search and edit instead of an empty body. Beat prefixes written the many ways
  Caller's Companion allows — compound `(4,12)`, bare, or malformed — are read
  correctly, and anything unrecognized is kept verbatim as text rather than
  guessed at.
- **Your Caller's Companion "call buttons" can become figure shorthands.** If
  your `.USR` file carries Caller's Companion's call buttons, the import now
  offers to turn them into your own **figure shorthands**, so the wording you
  already type expands the same way it did in the old app. It is opt-in and
  previewed before anything is added.
- **Caller's Companion venues become real venues.** Set locations from a `.USR`
  import now link to actual venue entries — matching one you already have where
  it is clearly the same place, and creating one where it isn't — so migrated
  programs join the rest of your venue list instead of carrying a plain text
  label. Ambiguous matches deliberately create a fresh venue rather than guess.
  (Applies when venue entities are turned on; otherwise the text label is kept
  exactly as before.)
- **Related dances survive the move from Caller's Companion.** Dances that
  pointed at each other in your `.USR` library now arrive linked as **related
  dances**, so those connections open from the dance detail screen instead of
  being dropped on import.
- **Import spots variations of a dance you already have.** When an import
  matches a dance in your collection but the *figures* differ, it now tells you
  it looks like a **variation** and shows exactly which lines differ, so you can
  import it as a separate dance, treat it as the same one, or skip it —
  instead of silently creating a near-duplicate.
- **Pickers work properly on a phone.** Type-ahead fields — choreographer,
  venue, move, dance and source pickers, plus the author and move filters in
  search — used to open a suggestion list that the software keyboard covered,
  and that vanished if you tried to scroll it from the wrong spot. On phones
  those fields now open a **keyboard-aware sheet** you can scroll and search
  normally; on tablet and desktop the familiar inline list is unchanged.
- **"Walk forward" is a real figure.** Caller's Box lines built on a plain walk
  forward — over 300 of them — previously blocked the whole line from being
  understood. They now map onto the moves the app already models, so those
  dances import structured instead of as unstructured text.
- **The user guide is now readable on the website.** The guides are published as
  browsable pages at
  <https://ibanner56.github.io/CallersCompendium/> rather than sending you to
  raw files on GitHub. The same guide still ships **inside the app** for offline
  use.

### Changed

- **"Gate" is now a single figure instead of two identical-looking ones.** The
  move picker used to show two rows both labelled "gate" — one from ContraDB's
  vocabulary and one from The Caller's Box's — with no way to tell them apart.
  They are now one figure that holds the direction, the number of beats **and**
  the facing the gate ends in. Existing dances are converted automatically the
  first time you open the app; beat counts and section placement are unchanged.

- **Gates no longer claim an ending facing the source never gave.** The app used
  to work the facing out from the rotation, assuming dancers always start a gate
  facing across the set. That assumption is often wrong — a half gate right
  after a down-the-hall ends facing **up**, but the app said "out of the set".
  Imported Caller's Box gates now show no facing at all (that source doesn't
  state one) and you can set the correct one yourself; ContraDB dances, which do
  state it, show exactly what their source says. **If you have gates in your
  collection you may want to check their facing** — some will have been showing
  the wrong one.

- **"Allemande orbit" figures are now stored as two concurrent moves.** The
  combined "one couple allemandes while the other orbits" figure is no longer a
  single fused move — it's now an allemande and a first-class *orbit* happening
  at the same time (a "meanwhile"), matching how callers actually notate the
  two sides. Existing collections are upgraded automatically on first launch: a
  one-time database migration rewrites any stored allemande-orbit figures into
  the new form, deriving each side faithfully from the saved values, so no
  dance loses its choreography. (#295)

### Removed

- **The automatic "can carry progression" hint is gone from the figure
  editor.** Swing and allemande no longer show an info-icon/tooltip nudge
  beside the Progression toggle. The manual **Progression** toggle is
  unaffected — you can still flag any figure as the progression yourself.
  The underlying `progressionCapable` taxonomy flag (non-serialized static
  metadata) was removed along with it. Closes #551.

### Fixed

- **In-app update checks work again for beta testers.** The signature file that
  proves an update manifest is genuine went missing from the update site on
  29 July, and because the updater is deliberately **fail-closed** — no valid
  signature means no update — every beta tester's check has quietly reported
  "no update available" ever since, with no error shown. Publishing this build
  restores that file, so update checks resolve normally again. The publisher was
  also fixed so a routine website deploy can no longer delete it.
  **If you are on beta.4 or beta.5, your in-app check could not see this
  release** — grab it from the Releases page once, and checks will work from
  then on.
- **A qualifier on a chain, promenade or right-and-left-through is no longer
  dropped.** The importer strips bracketed asides before it tries to recognize a
  line, so a trailing qualifier used to vanish once the figure matched — and two
  of those wordings, "(without courtesy turn)" and "(optional double courtesy
  turn)", *negate or change* the courtesy turn rather than merely describing it.
  Those qualifiers are now kept word-for-word as a note on the figure, so the
  line still structures without losing what it said.
- **A clause the app can't structure no longer discards the rest of its line.**
  The Caller's Box sometimes packs two actions onto one line with a semicolon
  (`Circle left 3/4; face up`). If either half couldn't be understood, the whole
  line used to collapse back to unstructured text — losing the half that parsed
  perfectly. Now the parts that can be understood become real figures and the
  part that can't is kept word-for-word as a note beside them.
- **Backups no longer lose where an imported program came from.** A program's
  import provenance now survives an export/restore round-trip, so restoring a
  backup and then re-importing the same Caller's Companion file updates your
  existing programs instead of creating a second copy of each one.
- **Searching for a courtesy turn by its ending facing now filters correctly.**
  The facing condition is applied as part of the search itself rather than after
  results come back, so it no longer interacts badly with result limits.
- **"Not stated" can be shown wherever the taxonomy allows it.** Several kinds
  of parameter dropdown — in the figure editor and in the search facets —
  ignored the choices a move actually declares, so a move that legitimately
  records "the source didn't say" could not offer that option. They now honour
  what the move declares. With that fixed, three parameters that had been
  declared as generic choice lists purely to work around the gap — the hand a
  long wave is held by, and the direction of a mad robin and of a butterfly
  whirl — now carry their proper types again. No existing figure's values,
  rendering or search results change; this was verified by diffing every
  observable output of the whole move vocabulary before and after.

- **A turn amount the source never gave no longer looks like "1 turn".** In the
  figure editor, a rotation the app has no value for now reads **"not stated"**
  instead of silently showing 1 turn. Nudging the stepper sets a real value (and
  a new clear button puts it back to not-stated), so a number you never entered
  can't quietly become part of your dance. This matters most for gates imported
  from ContraDB, which state an ending facing but no amount.

- **Caller's Box import keeps the "(ones forward)" detail on a gate.** Lines
  like `Neighbor mirror gate 1 (ones forward)` used to lose the parenthetical
  once the figure was recognized. Now, when it names dancers the app knows, it
  becomes a real part of the figure — you'll see "…, ones forward" on the line
  and can edit it. Anything the app can't represent exactly, such as
  "(men stay put)" or "(M1+W2 forward)", is kept word-for-word as a note
  instead of being guessed at.

- **Figure notes now follow your chosen vocabulary (#715).** Previously an
  imported or dialect-typed figure note was stored and edited verbatim, so an
  imported note showed raw internal role tokens (`role2s`) in the editor. The
  dance editor now renders a figure's stored note into the active dialect on
  load and stores it back in neutral terms on save — including for
  meanwhile-group side notes and figures inserted via free-text entry. A note
  is treated this way (and dance-level prose is not) because it carries
  modifiers for the figure sitting beside it, so its wording has to stay
  consistent with that figure.
  No schema/migration change: canonicalization is a pure, idempotent,
  roles-only rewrite, so existing stored notes simply resolve correctly the
  next time that figure is opened or saved (consistent with the #665
  precedent of not migrating unrelated free-text prose).

- **Some Caller's Box dances imported with inflated beat counts.** When a
  spelled-out figure's beat marker was written as a range (e.g. `(7-12)`), both
  the figure and its sub-figures were counted, pushing later figures into the
  wrong A1/A2/B1/B2 section. Those dances now import with the correct beats and
  sections.

- **Program import no longer silently duplicates a dance already in your
  collection.** Multi-author strings (choreographer fields, Caller's Box
  author arrays, Caller's Companion "by" lines) are now tokenized
  consistently across every import source (see the `compendium_core`
  changelog), so an already-owned dance's author set reliably overlaps on
  re-import instead of scoring a spurious zero. On top of that, the
  non-interactive program-import path (plaintext program import and the
  ContraDB program import's Caller's Box fallback) now consults the local
  dedupe index before importing an online-resolved dance: a confident
  local-duplicate match (exact title + overlapping authors) is skipped
  rather than force-imported, leaving the line on its existing note-slot
  fallback instead of creating a silent duplicate. The interactive
  search-and-tap-Import flow is unchanged. (#685)

- **Off-screen program-matrix columns are now discoverable, and redundant
  column-header tooltips are gone.** The matrix's pinned column-header strip
  gave no visual cue when a program had more moves than fit on screen — a
  hey or half-hey column sitting just off the right edge could go completely
  unnoticed, requiring the caller to already know to scroll sideways. The
  header strip now shows a gradient-fade-plus-chevron edge cue on whichever
  side(s) still have hidden columns, purely decorative and driven by the same
  scroll position as the body (which already has a visible scrollbar);
  presence is conveyed with shape and gradient together, never colour alone
  (WCAG 1.4.1). Separately, every column header's hover tooltip — which just
  repeated the visible heading text — has been removed as pure noise; the
  header's accessible name for screen readers came from an independent
  semantics label all along, so nothing is lost for assistive tech. (#662)

- **The program-matrix PDF export's ★ (program-debut), ▸ (dance's-first-figure),
  and ✓ (present) markers now actually render, instead of silently rendering
  blank.** The bundled Roboto font used for PDF export doesn't include those
  three glyphs, and the `pdf` package silently drops any glyph missing from
  the active font — so exported/printed matrices lost their legend and cell
  markers entirely, even though the on-screen matrix (which uses Material
  icons, not these Unicode glyphs) looked correct. The alert marker (`‼`,
  #582) was unaffected, since Roboto does include it. Rather than swap the
  documented `★`/`▸`/`✓` marks for different characters, PDF export now
  registers a small, static (non-variable, consistent with #614's
  static-font decision), OFL-licensed fallback font — a hand-subsetted
  instance of Google's Noto Sans Symbols 2, trimmed to just these three
  glyphs — as a `fontFallback`, scoped only to the matrix's marker/legend
  text. (#633)

- **A dance or program's autosave draft no longer resurrects itself after a
  save, delete, or discard.** The debounced autosave and the draft cleanup it
  triggers could race: if a save/discard/delete ran while an autosave write to
  the settings store was still in flight, the write could land *after* the
  cleanup removed the draft, silently recreating stale content that would then
  prompt "restore your draft?" the next time you opened the editor — even
  though you'd already saved or intentionally discarded it. Cleanup now waits
  for any in-flight autosave write to finish before removing the draft, so the
  removal always wins. (#616)

- **Figure notes now follow your active dialect.** A figure's note is
  free text alongside calling notes and the walkthrough, but it was the only
  one of those fields displayed verbatim instead of through the same
  dialect-aware renderer. A note authored with a role token (e.g. "role2s
  scoop them up") now reads in your active dialect's terms (e.g. "robins
  scoop them up") everywhere a figure note is shown — the figure table, the
  large-print Perform view, and the exported PDF. (#619)

- **Your hook, calling notes and walkthrough are saved exactly as you type
  them.** An unreleased change had started rewriting the role words in your
  prose into internal terms so they could be re-shown in each reader's
  vocabulary. That turned out to damage ordinary writing: the app matches whole
  words like *man*, *men*, *lady*, *ladies*, *lark* and *robin* wherever they
  appear, so a dance called "Lady of the Lake" was being re-shown as "robin of
  the Lake", "Taught to me by Robin Hayden" became "robin Hayden", and "the
  ladies room is past the stage" became "the robins room". Your capitalisation
  was dropped too. Prose is now stored word-for-word as written. **Nothing you
  have saved was affected — this never reached a release.** Dance and program
  titles were never touched on any version. Figure notes are unchanged: they
  still follow your chosen vocabulary, because they describe the figure sitting
  next to them.

- **A backup restore that saves your content but can't apply your settings now
  says so — and lets you retry.** Restoring writes two independent stores that
  can't share one transaction: your core content (dances, programs, everything
  in the database) commits first, then your saved settings (dialects, themes,
  preferences) are applied separately. If that second step genuinely failed —
  the settings store was momentarily unavailable — the app used to report a
  blanket "couldn't restore the backup," even though your dances and programs
  had in fact been restored. Now that case is handled explicitly: the restored
  content is kept (never rolled back or lost), and you get a clear message that
  your content is safe but settings couldn't be applied, with a **Retry
  settings** action that re-applies just the settings without re-importing
  anything. The retry re-runs the same integrity check and per-setting
  validation (from the previous release) every time, so it can't be used to slip
  an unchecked value through, and it's safe to press more than once. (#608)

- **The single-dance Perform view no longer exits on one stray tap or back
  gesture.** Exiting single-dance Perform mode used to pop the screen
  immediately on a single tap of the close control, with no `PopScope` to
  catch a system/predictive back gesture either — an accidental brush could
  drop a caller out of the stage view mid-dance, losing wake-lock and their
  adjusted text scale. The close control and system back now route through
  the same deliberate confirm dialog ("Exit performance view?" / Cancel /
  Exit) already used by the multi-dance program Perform view (#434), keeping
  the two Perform surfaces consistent. (#612)

- **The program Perform exit dialog can no longer be stacked by rapid taps.**
  A quick double-tap on the close control, or repeated back gestures while
  the confirmation was already up, could open a second "Exit performance
  view?" dialog on top of the first — confirming the top one could then pop
  more than one screen. The exit confirmation is now guarded against
  re-entrancy, matching the guard already added to the single-dance Perform
  view (#612), so only one dialog is ever shown and exactly one screen is
  popped. (#666)

- **A corrupt backup can no longer brick startup.** Restoring a backup applied
  its saved preferences without checking them, and one startup read cast the
  theme preference with an unchecked cast — so a backup carrying a wrong-typed
  or out-of-range value (whether corrupted, truncated, hand-edited, or crafted:
  the file's checksum proves integrity, not that the contents make sense) could
  make the app throw on launch and keep throwing on every launch after, the
  kind of failure only clearing app data recovers from. Restored preferences are
  now validated at the trust boundary against a per-setting type/range schema:
  any value that doesn't fit is dropped so that setting falls back to its safe
  default (with a non-fatal notice), while every valid setting still restores,
  and startup reads the theme defensively so a bad value degrades to the default
  theme instead of crashing. (#609)

- **ContraDB import: single-file promenade, single-file circle, and "take
  neighbors" now recognize instead of falling through to custom.** Deferred
  from the #585 recognizer sweep: `single file promenade …` (e.g. `single
  file promenade along major set to new neighbors`) now imports as
  `promenade`, defaulting to everyone and keeping the trailing path as a note;
  `promenade single file around the circle/ring [N places]` now imports as a
  single-file `circle`; and a bare `<who> take <whom>` with no `give &` clause
  (e.g. `ladles take neighbors`) now imports as `give_and_take` (take-only).
  No new taxonomy moves were introduced — all three reuse existing `promenade`,
  `circle`, and `give_and_take` moves with a new `singleFile` flag on the
  first two. Any figure that doesn't match one of these patterns still falls
  through to editable custom, unchanged. (#634)

- **ContraDB import: figures with a `balance &` prefix now recognize instead of
  falling through to a plain custom figure.** ContraDB renders a balanced move as
  `balance & <move>` (e.g. `balance & Rory O'More right`), and the `&` was being
  left behind, demoting otherwise-matchable Rory O'More, petronella, pull by, box
  circulate, and square-through figures to custom. A trailing parenthetical note
  (e.g. `(in long waves)`) is preserved verbatim on the recognized figure. Notes
  that interrupt a figure mid-phrase still stay custom, and malformed/unbalanced
  parentheses are handled safely. (#578)

- **ContraDB import: more real-world figures recognize instead of falling
  through to custom.** Extended the ContraDB figure recognizers to cover renders
  that were dropping to custom over a single unconsumed qualifier: `star` now
  reads the grip clause (`star left - wrist grip - 4 places`,
  `star right - hands across - 3 places`); `box the gnat` reads a leading
  `<hand> hand balance &` prefix (`neighbors right hand balance & box the gnat`);
  a bare `pass through` recognizes and keeps its trailing qualifier as a note
  (`pass through by the left`, `to next neighbors`); `chain` reads a leading
  `left|right diagonal` and keeps `to shadow` as a note; and the `prev neighbors`
  subject (ContraDB's rendered form) now recognizes. Any leftover text is
  preserved verbatim as the figure's note; unrecognized figures still import as
  editable custom. (#585)

- **Caller's Box import: the trailing balance on "pass the ocean" now merges
  into the ocean instead of importing as a separate figure.** The Caller's Box
  writes the figure across two lines — `(4) Pass the ocean` followed by
  `(4) Balance wave of four …` — and only a _preceding_ balance line was being
  folded in, so the trailing balance-wave was left as its own custom figure. The
  cross-line merge now folds a trailing balance-wave line into the preceding
  ocean/wave figure (`pass the ocean`, `form a wave`, `form a long wave`),
  setting its balance flag and summing the beats (4 + 4 = 8). The match is
  conservative: it only folds a balance-_wave_ line (never a plain dancer balance
  destined for a following swing), only immediately-adjacent lines within a
  phrase, and never drops or fabricates choreography. (#577)

### Security

- **ContraDB dance and program imports are now restricted to the official
  ContraDB host.** `buildContraDbUrl` and `buildContraDbProgramUrl` used to
  preserve whatever host a pasted URL carried, verbatim — trusting any public
  host as "ContraDB" so long as the path looked like `/dances/N` or
  `/programs/N`. Both builders now enforce the same host allowlist
  (`contradb.com` / `www.contradb.com`) already used to auto-detect a pasted
  ContraDB link, rejecting any other host before a URL is even built, and now
  require `https` (a bare `http://` link is rejected as an insecure scheme).
  This mirrors the Caller's Box host allowlist from the previous release
  (#621) and intentionally drops self-hosted-ContraDB-mirror support — the
  existing fetch-time SSRF guard (blocking loopback/private-IP targets)
  remains independent defense-in-depth regardless of host. (#667)

- **Imports can only reach the sources they claim to.** Both Caller's Box and
  ContraDB URL builders now enforce a host allowlist before a request is made,
  so a pasted link that merely *looks* like one of those sites can no longer
  redirect an import at an arbitrary host.
- **Program imports get the same text sanitizing dances already had.** The
  protections against invisible and direction-changing characters that were
  applied to dance imports now cover program imports too, so a crafted file
  can't smuggle deceptive text through the program path.
- **Caller's Companion choreography is read fail-closed.** The newly-read
  transcription table is sanitized and bounded — capped rows and lengths — so a
  malformed or hostile `.USR` cannot exhaust memory or inject control
  characters.
- **Searches containing `%` or `_` no longer over-match.** Those characters are
  wildcards to the database; they are now escaped, so searching for them finds
  them literally.
- **Downloaded updates are written to an unpredictable path, create-only.** The
  update download no longer writes to a guessable filename, closing a local
  symlink-overwrite vector on shared machines.
- **Diagnostics can no longer leak in release builds.** Debug logging that could
  print file paths, errors and user data is now consistently compiled out of
  release builds.
- **Deleting something is now atomic.** Three places checked whether a record
  was still referenced and then deleted it in two separate steps; both halves
  now happen in one transaction, so a concurrent edit can't slip between them.
- **Backups are exported from a single consistent snapshot.** The export now
  reads inside one transaction, so a backup taken while you are editing can't
  capture a half-updated library.
- **Restoring a corrupt backup can no longer brick startup.** Restored settings
  are validated before they are applied, and a bad value falls back to its
  default instead of crashing the app on next launch.
- **Robustness fixes across storage.** Large batch look-ups are chunked so they
  can't exceed the database's variable limit, a malformed custom-field choice no
  longer throws while loading, and the per-dance calling-history queries are
  backed by a new index instead of scanning every program slot.
- **Accessibility consistency.** Announcements now honour the ambient text
  direction rather than assuming left-to-right, and the Perform view's
  auto-sizing respects the system **Reduce motion** setting.
- **Continuous integration now runs the supply-chain suites on every pull
  request** and analysis is stricter, so the checks that protect releases can't
  silently stop running.

### Data / Migrations

- **Schema advances from version 15 to 20 — automatically and losslessly, on
  first launch.** Five steps run in order; nothing needs a reinstall and there
  are no manual data steps. Three of them rewrite stored figures, which is why
  this release also refreshes the derived search index for the rows it touched:
  - **v16** adds an index used by per-dance calling history. No data changes.
  - **v17** does nothing. It was going to rewrite your typed prose, but that
    change was withdrawn before release (see Fixed) and the step is kept as a
    documented no-op so the later numbers don't shift.
  - **v18** converts stored `allemande orbit` figures into the two concurrent
    moves they actually are (an allemande *while* the others orbit), carrying
    the original beat count across as the pair's shared total.
  - **v19** renames stored `form a wave` figures to `form short waves`. Values
    are carried over untouched — only the identity and display name change.
  - **v20** merges the two "gate" moves into one and rewrites stored figures of
    both onto it, materializing each retired move's own defaults so no figure
    changes meaning. Beat counts are carried over verbatim.
  - Every rewrite is per-dance and per-figure fail-safe: anything that cannot be
    remapped cleanly is left exactly as it was rather than dropped or altered.
  - **Upgrading directly from beta.1** still runs the one-time ocean-wave
    migration described in the beta.2 notes, and needs the Android reinstall
    noted below.
- **The move vocabulary advances from version 16 to 23.** New moves and
  parameters (courtesy turn, orbit as its own move, wave balance details, hey
  "run until you meet", single-file promenade and circle, mad robin and
  butterfly whirl details) are additive and do not change how existing figures
  render. The exceptions are the three identity changes above — the wave-move
  rename, the `allemande orbit` split, and the gate merge — and each has a
  migration that updates your data for you.
- **Timing is preserved throughout.** No migration in this release changes any
  dance's beat totals or A1/A2/B1/B2 placement.
- **Back up first if you like.** Upgrading is designed to be safe and automatic,
  but **Settings ▸ General ▸ Export a backup** before a big version jump is
  never a bad idea. Downgrading to an older build after these migrations is not
  supported.

### Known issues

- **On beta.4 or beta.5, your in-app update check can't see this release.** The
  update site lost its manifest signature on 29 July, and the updater is
  fail-closed, so checks have been reporting "no update available". Download this
  build from the Releases page once; publishing it restores the signature and
  in-app checks work normally from then on.
- **Coming from beta.1? A one-time Android reinstall is still required.** beta.2
  unified the Android application identifier with Apple
  (`org.callerscompendium.compendiumApp`), so a beta.1 sideload cannot upgrade in
  place. **Export a backup (Settings ▸ General ▸ Export a backup), uninstall the old
  app, install this build, then restore.**
- **Have an older `.ccbackup` file?** The encrypted-backup format from beta.4 can no
  longer be opened. Restore it with the beta.4 build and export a fresh `.json` backup.
- **Check your gates.** Gates no longer invent an ending facing the source never
  stated (see Changed). If you had gates before this build, some may have been
  showing a facing that was wrong — worth a look.
- **In-app update checks remain opt-in.** Automatic checks and the beta channel are off
  by default and enabled in Settings; when on, updates are signature-verified. Either
  way, you can always watch the GitHub Releases page for new betas.
- **Windows and Linux desktop builds are still unsigned** (see Platforms & install).
- **The user guide has no screenshots yet.** The written guides are current; the
  images pass is still to come.

### What you can do today

- **Build your Collection.** Create, edit, and tag dances, organize them your way, and
  soft-delete/restore anything (with a 30-day Recently Deleted safety net). Group the
  list by category to hot-swap dances of a given "vibe" mid-evening.
- **Plan Programs.** Assemble a set with event date, a reusable venue, ordered slots,
  and alternates; track program status; duplicate a program to reuse a good set.
- **Perform.** Open a program — or a single dance — in a large-print, auto-sizing
  Perform view built for reading across a dim hall, mark dances as you call them, and
  tap out the tempo on a built-in visual metronome.
- **Author the way you teach.** Build figures with the structured editor, or turn on
  free-text entry to type them (with your own shorthands); record a step-by-step
  **Walkthrough** for each dance and let your **snippet library** pre-fill it from
  wording you have used before.
- **Import your existing library.** Bring dances in from a JSON backup, The Caller's
  Box, ContraDB, and Caller's Companion (`.USR`) — with the choreography, your
  venues, related-dance links and call-button shorthands coming across too; import
  **programs** from Caller's Companion (`.USR`) and from **ContraDB** as well. Every
  import is reviewable and undoable with one tap, and near-duplicates are flagged
  before they land.
- **Share between devices.** Send a program and its dances to another device, or open
  one that was shared with you.
- **Search the way you talk.** Dialect-aware search and filtering understands the
  terminology you use, whichever tradition you call in.
- **Keep your data yours.** Export a full backup to a single human-readable JSON file
  (with a built-in integrity check) and restore it on another machine — no account, no
  cloud, no telemetry.

### Platforms & install

- **Android** — a signed universal `.apk`. Install it directly (sideload); you may
  need to allow "install unknown apps" for your browser or file manager. It is **not**
  on the Play Store yet. (If you ran beta.1, see the reinstall note under Known
  issues.)
- **iOS** — delivered through **TestFlight** to invited testers; by design there is
  no `.ipa` on this Releases page.
- **macOS** (universal) — **signed with an Apple Developer ID and notarized**, so it
  opens normally (you may see a single first-launch confirmation).
- **Linux** (x64) and **Windows** (x64) — desktop builds, **still unsigned** for this
  beta, so your OS will warn you before it runs:
  - Windows: **More info → Run anyway** on the SmartScreen prompt.
  - Linux: the **`.tar.gz`** is the no-setup path — extract and run. The `.AppImage`
    needs the **FUSE 2** runtime (`libfuse.so.2`) — package `libfuse2` on
    Debian/Ubuntu, `fuse-libs` on Fedora — which some recent distros don't
    preinstall; install it, or launch with
    `./CallersCompendium-*.AppImage --appimage-extract-and-run`.

### Your data & safety

Everything lives locally on your device. There is no telemetry and nothing is sent
anywhere. Imports are previewed before they commit and are undoable, so trying a new
source is safe. Before a large import — or any upgrade — you can export a backup from
**Settings ▸ General ▸ Export a backup** for extra peace of mind.

### Feedback

Please tell us what breaks or feels wrong:
<https://github.com/ibanner56/CallersCompendium/issues>. Include your platform, the
version (`0.1.0-beta.6`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**, with an
[additional permission](https://github.com/ibanner56/CallersCompendium/blob/main/LICENSE-EXCEPTION.md)
that allows distribution through managed application marketplaces (Apple's App
Store, Google Play, and comparable stores) under those stores' required terms —
while the source stays fully AGPL-3.0 and every user keeps their rights to it. The
source is always available at <https://github.com/ibanner56/CallersCompendium>.
