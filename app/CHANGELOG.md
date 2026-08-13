# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Added

- A note slot in the program builder (e.g. one left behind when a title-list
  import couldn't find a matching dance) can now be turned into a real dance
  in place: its overflow menu offers **Create a dance from this**, which opens
  the dance editor pre-filled from the note and links the slot to the new
  dance once you save. (#881)
- **Both the Collection and Programs lists now offer a "Last used" option** for
  their default sort in Settings ▸ Defaults, alongside the existing fixed
  choices. With "Last used" selected, the sort key **and** direction you pick
  while browsing survive closing and reopening the app; with a fixed sort
  selected, behavior is unchanged from before. The Programs list previously
  had no default-sort setting at all. (#895)
- **Pasted-program title-list import falls back to ContraDB.** "Resolve
  unmatched online" on the pasted-title-list program import now tries The
  Caller's Box first and, for any title Caller's Box cannot resolve
  confidently, ContraDB next — a title that only lives in ContraDB no longer
  has to be imported by hand afterwards. A title either source finds several
  exact matches for (and neither source resolves it confidently) is now
  offered to you to pick from, instead of always silently becoming a note.

### Fixed

- Rotating a tablet across the Collection/Programs split-pane breakpoint
  (900px) no longer resets the list's current sort, search text, filters, or
  scroll position. Previously the list was rebuilt from scratch on that
  transition, discarding all of it. (#895)
- The tag and author/choreographer picker on phones no longer closes after
  every other addition. Adding entries in a row now keeps the picker open
  each time until you save or close it yourself. Fixes an issue where a
  keyboard/screen-reader user who dismissed the picker without picking
  anything also had to navigate past the field twice to reopen it. (#894)

## [0.1.0] - 2026-08-12

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.7`** (this pre-release) builds
on **`v0.1.0-beta.6`** and finishes the jobs beta.6 started. Its theme is **making
what you already have complete and findable**: the app is now **fully translated in
every language it ships in**, **mixers** are supported end to end — marked, searched,
and given named partner positions — and figure details that were previously imported
but invisible (**star grip**, **single-file**, **balance handedness**, **quadruplet**
formations) now show up in display and search. Alongside that: **plain `.json`
program export**, **tag colours**, **per-row collection details**, and a fix for
**undo** so a restored dance reappears everywhere rather than only in the database.
The changes **since beta.6** are grouped first; the standing feature overview and
install notes follow.

> Upgrading rewrites some stored figures (schema 20 → 25). It is automatic and
> preserves every dance's timing — see **Data / Migrations** below.

### Added

- **Quadruplet is now a first-class formation shape.** Dances in a longways
  set for four couples are recognised as "Quadruplet" instead of collapsing to
  "Other". Imports from The Caller's Box, ContraDB (JSON), and ContraDB (HTML)
  now detect the word "quadruplet" and map it to the dedicated shape, which
  means quadruplet dances can be filtered, colour-coded, and reasoned about as a
  distinct formation.

- **Balance figures now carry an optional hand (right / left / unspecified).**
  When The Caller's Box writes `(RH)` or `(LH)` on a balance line, the hand
  is now preserved instead of being silently dropped — 1,066 instances measured
  corpus-wide. The hand defaults to unspecified, so balances that don't name one
  stay neutral.

- **You can now export a program as a plain `.json` file.** The program
  **Export** menu gains **Export as JSON file**, between **Copy set list** and
  **Export / print PDF**. It builds exactly the same content as **Share (program
  + dances)** — the program, every dance it uses with full figures, the
  choreographers, and the venue — but names the file `.json` instead of
  `.ccshare`. A `.ccshare` file is registered to Caller's Compendium and opens
  straight into import review on a device that has the app; a device that
  doesn't may not know what to do with it. Reach for the JSON version when you
  are emailing a program to someone who hasn't installed the app, putting it
  somewhere that rejects unfamiliar file types, or just want to read the file
  yourself. Either one imports back into the app the same way.

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

- **Star grip and single-file formation now appear in dance text — and in search
  (#749, #840, taxonomy v27).** Two figure details were imported and stored but
  never shown:

  - A star with a hands-across or wrist-grip hold now reads **"star right –
    hands across – 4 places"** in every rendered view, matching the way
    ContraDB writes it. Stars with no stated grip are unchanged.

  - A single-file promenade now reads **"single file promenade along"** (or
    "across") in every view. The direction is always included — it was
    previously hidden even when the source stated it. The dancer group is
    omitted; it's an importer artefact and doesn't add meaning.

  - A single-file circle now reads **"single file circle clockwise N places"**
    instead of "circle left N places - single file". Clockwise and
    counterclockwise use their plain English names rather than "left" and
    "right".

  All three forms are now searchable: typing "hands across", "single file", or
  "clockwise" in free-text search will find the relevant figures.

  One thing to expect: re-opening the app after this update will re-index your
  dances in the background. During that short window the new search terms may
  not return results yet.

- **The Caller's Box single-file promenade now imports as a single-file circle
  (#749 Part E).** TCB writes "Single file promenade clockwise" for what the
  app models as a circle in single-file formation. That phrasing is now
  recognised on import and stored as a structured circle figure.

- **ContraDB single-file promenade now captures the stated direction (#749 Part
  A).** A ContraDB dance that says "single file promenade along" now stores
  `dir: along`, so the direction survives a round-trip through import and
  export. Previously the direction was parsed but discarded.

- **Imported figures now keep the hand and dancers The Caller's Box wrote in
  shorthand.** TCB notes handedness and who you're dancing with in a compact
  code beside the figure — the `(NR)` in "Pass through along (NR)", or the
  `(SR;NL)` in "Square through 2 (SR;NL)". That code used to be thrown away on
  import, and the app filled in a default instead — which was sometimes the
  opposite of what the dance actually said. 2,504 imported figures now carry
  what the source stated. 116 of them were previously stored with the wrong
  hand or shoulder and are now right.

  Where the code names dancers the app can represent, they're kept too, so a
  square through records which dancers you pass on each hand rather than
  assuming. Where it names something the app has no way to express — an
  "opposite", a phantom, or a same-role neighbour — the figure is left alone
  rather than guessed at.

  One thing to expect: re-importing a dance you imported before this change may
  now offer it as a variation, because those 116 figures genuinely describe
  different choreography from what was stored. That's the app noticing a real
  difference, not a false alarm.

- **Star promenades no longer claim a hand.** A star promenade used to display
  as "Neighbor star promenade right ½" — but that "right" describes the two
  dancers holding hands in the *centre*, not your connection with the neighbour
  you pick up on the side. Reading it as a hand you take with your neighbour is
  simply wrong, so it has been removed from the figure. Where The Caller's Box
  states the centre — the `(WR)` in `Neighbor star promenade 1/2 (WR)` — it now
  appears as a note beside the figure, reading "robins by the right in the
  center" in your chosen dialect rather than a frozen "W". (That quotation is
  verbatim app output, which uses the US spelling like the rest of the
  interface; the surrounding prose keeps this file's British voice.) 626
  imported figures are affected corpus-wide, and existing dances are updated on
  first launch.

  Two smaller improvements ride along. Anything else written beside a star
  promenade — a qualifier like "(hand-in-hand with neighbor)" or "[with N1]" —
  used to be dropped on import and is now kept. And star promenades imported
  from ContraDB now come in as plain text figures instead: ContraDB records who
  is in the centre rather than whom you pick up, and rather than guess the
  difference we keep its own wording, with only the role names put into your
  chosen dialect.

- **Caller's Box online search no longer offers dances whose figures it won't
  share.** Not every dance in The Caller's Box has permission for its figures to
  be shown; picking one of those used to give you a title and a formation with
  no figures at all, which is almost never what a dance search was for. About
  three in ten results were affected, and it was worst when searching *by
  figure* — a quarter of the answers to "which dances have a balance" were
  dances whose balance you couldn't then read. Those dances are now left out of
  Caller's Box search results, including when a pasted title list looks a title
  up online. You can still bring one in deliberately by importing it by its link
  or ID, which works exactly as before. The **Resolve unmatched online** button
  on a pasted program is deliberately left alone — it imports unattended, so
  changing what it finds would change what it decides to keep. ContraDB
  searches are unaffected.
- **Caller's Box searches now consider every match, not just the first fifty.**
  The Caller's Box returns fifty results at a time; the app now asks for the
  complete set when a search is small enough to make that cheap, so hiding the
  dances above doesn't quietly cost you ones you could have used. Very broad
  searches still show the first fifty, so typing a single letter doesn't pull
  megabytes from a volunteer-run site.

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

- **Undoing a dance you just deleted now brings it back everywhere, not just in
  the database.** If you opened a dance from search, from a link on another
  dance, from a program's set list, or straight after importing it, then deleted
  it and tapped **Undo**, the dance was restored but every list still behaved as
  though it were gone — a related-dance link kept reading "(missing dance)"
  until the app was restarted. Only one route in, tapping a row in the
  Collection, was unaffected. Undo now tells the other views to refresh, the way
  the rest of the app already does (#768).

- **Bare ContraDB box circulates now import correctly (#752).** A ContraDB
  dance written as `larks cross while robins loop` (or any role pair) was not
  recognized as a box circulate. It now imports as `box_circulate`, with the
  crossing dancer set recorded as `who` and the hand recorded when stated — so
  it shows up correctly when filtering or searching by move.

- **Changes you make in one place now show up everywhere, without restarting the
  app.** Editing a dance, adding it to a program, marking slots performed,
  creating or deleting a program, or importing one all used to leave every
  *other* open view showing the data as it was before. So a dance's **called N
  times** badge stayed put after you added it to a program; its **Calling
  history** ignored the program you had just added it to; a program you were
  looking at kept showing a dance's old difficulty level after you edited it;
  and a program arriving through a shared `.ccshare` file did not appear in the
  Programs list at all until the app was relaunched. Every one of those writes
  now tells the views that render the data to refresh, and each view refreshes
  once per change rather than once per edited dance. Opening a dance from a
  **related dance** link and renaming it there also updates the link you came
  from, instead of leaving the old title behind — and deleting it there marks
  the link as missing rather than leaving a link to a dance that is gone
  (#768, #851).

- **Skipping every dance in a shared import no longer disables Import when the
  bundle carries a program.** Previously, if you already owned every dance in a
  shared bundle and set them all to Skip, the Import button went grey — making
  the program unreachable even though it was the only thing you wanted. The fix
  covers both the share-target path (opening a `.ccshare` sent to you) and the
  manual-pick path (choosing a `.ccshare` from "Choose file"). Programs are now
  committed regardless of how dance rows are dispositioned, and a note in the
  review panel tells you a program will be included so the summary is never
  misleading (#869).

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

- **A venue's street address no longer leaves your device when you share,
  export, print, or copy a program.** The address line, city, state or province,
  country, and postcode were being included in shared program files, exported
  PDFs, and the plain-text set list — even though they are classified as
  device-only data, and even though the venue's *contact people* were correctly
  held back behind a tick box. There was never a prompt for the address, so
  there was never a way to say no to it. It is now removed from every export
  path. What still travels is the venue's name, plus its website, schedule,
  price, sponsor, event name, and notes, so a recipient still knows which hall
  you mean. Your own records are untouched: the address is still on the venue,
  and a backup still contains it.

- **A choreographer's deceased mark is no longer included in a shared file.** It
  was travelling alongside the author's name and website, while their email and
  location were correctly stripped. It is personal information about someone who
  cannot object to it being passed on, so it now stays on your device with the
  rest of their private details. The **Choreographer details** dialog and the
  user guide now say so.

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

### Data / Migrations

- **Schema advances from version 20 to 25.** Upgrading is automatic; v21
  removes retired provenance payloads and snapshots, v22 adds figure-group
  correlation for concurrent figures, v23 adds per-field sharing disclosure,
  v24 adds mixer metadata, and v25 adds Device Sync timestamps and tombstones.
  Existing data is preserved by the migration steps and their tests.
- **Taxonomy advances from version 23 to 27.** The additions and
  recognition changes improve mixer partner references, balance hands,
  inverse-pair routing, star-promenade handling, and star-grip/single-file
  rendering and search. This taxonomy version is a documentary marker only:
  nothing reads it at runtime and it does not itself rewrite the database.

### Known issues

- **Coming from beta.1? A one-time Android reinstall is still required.** beta.2
  unified the Android application identifier with Apple
  (`org.callerscompendium.compendiumApp`), so a beta.1 sideload cannot upgrade in
  place. **Export a backup (Settings ▸ General ▸ Export a backup), uninstall the old
  app, install this build, then restore.**
- **Have an older `.ccbackup` file?** The encrypted-backup format from beta.4 can no
  longer be opened. Restore it with the beta.4 build and export a fresh `.json` backup.
- **Check your gates.** Since beta.6, gates no longer invent an ending facing the
  source never stated. If you recorded gates before beta.6, some may still be
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
