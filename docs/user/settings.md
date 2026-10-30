# Settings

**Settings** is where you tune Caller's Compendium to fit the way you work — how
your library sorts, how [dances](./glossary.md#dance) look on stage, which
[dialect](./glossary.md#dialect) names appear, and how the app protects your data.
Most of what you'll find here has a dedicated guide of its own, so think of this
page as a tour: it shows you where each control lives and points you to the
details.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Settings**, **Appearance**, and **Defaults**. The
> first time a dance term appears it links to [App terms](./glossary.md), so
> you can get a plain-language definition without losing your place.

*The Settings screen with the section list beside the controls for the Dialect
section.*
![The Settings screen with the section list on the left and the Dialect section open, showing the dialect presets and wording switches](images/settings-dialect.png)

## Finding Settings

**Settings** is a top-level destination, marked with a gear icon and labelled
**Settings**. On a narrow screen (like a phone) it's a tab in the bottom
navigation; on a wide screen (a tablet or desktop) it's in the side navigation
rail.

Inside, a list of sections sits beside the controls for the section you've
chosen. On a narrow screen you pick a section and it opens as its own page, then
you step back to switch sections. There are ten sections, always in this order:

1. **General**
2. **Program**
3. **Appearance**
4. **Dialect**
5. **Language & region**
6. **Defaults**
7. **Updates**
8. **Diagnostics**
9. **Experimental**
10. **About**

## General

The **General** section gathers everyday behavior into small groups.

### Library

- **Ignore leading articles when sorting** (on by default) — alphabetizes titles
  by their first meaningful word. With this on, "The Nice Combination" files under
  **N**, not **T**. It applies to the Collection, the program dance picker, the
  Programs list, and the order of [quick search](./collection.md#jump-straight-to-a-dance-or-program)
  results.
- **Capitalize figures** (off by default) — starts each
  [figure](./glossary.md#figure) in the dance view, [Perform mode](./perform.md) and
  the figure editor with a capital letter. Off, figures are shown as written
  (built-in figures start in lower case, as in ContraDB). Only the look in those
  places changes; exports, search, sync comparisons and screen-reader wording are
  unaffected.

### Accessibility

- **Reduce motion** — trims animations and movement. Follows your device's system
  *Reduce Motion* setting by default; turn this switch on to
  switch off the app's animations and the fade between themes even when your
  device allows motion. Turning it off stops the app removing its own
  animations, but cannot restore animations your device's setting has already
  shortened. This setting belongs to this device: it is not synced to your
  other devices, but a backup includes it.
- **Always show verbose figure text** — shows the full spoken-style
  [figure](./glossary.md#figure) wording on screen in the dance view, not only to
  screen readers. Turn it off for the terse notation. This affects the dance view;
  [Perform mode](./perform.md) has its own text-size controls.
- **Show turns as decimals** — shows turn and rotation amounts as decimals (0.75)
  instead of fractions (¾). Screen-reader wording is unaffected.
- **Confirm before delete** — adds a prompt before you delete a dance or program.
  Deletes are still undoable either way.

These are the highlights; the [Accessibility guide](./accessibility.md) gives you
the full picture.

### Deleted items

- **Keep deleted items for** — choose **30 days**, **90 days**, or **Never**
  (default is **30 days**). Deleted dances and deleted programs are held for
  this long and then purged. If you use [Device Sync](#device-sync), the
  setting syncs and applies on all your devices: when a shared item's time is
  up, its content is erased everywhere, as if you had deleted it permanently,
  and only a small deletion record is kept (with the dance's title, while a
  program or another dance still includes it). Choosing
  **Permanently delete** on one item in **Recently deleted** removes only that
  item. For how soft-delete and restore
  work, see [Collection & search](./collection.md).

### Import

- **Import dances** — the entry point for bringing dances in from other sources.
  See [Imports & migration](./imports.md).
- **Published collections** — browse signed collections from the trusted catalog
  and send one through the review flow. See
  [Imports & migration](./imports.md#import-a-published-collection).
- **Convert ECD dances?** is a question the app asks when it opens, not a
  setting here. Choosing **Don't show this again** in it stops the question;
  answering **Not now** without it asks again next time. A conversion can be
  undone straight after. See
  [Imports & migration](./imports.md#dances-tagged-ecd).
- **Re-check custom figures** — re-reads imported dances whose figures were kept
  as plain custom text only because the app couldn't recognise them at the time.
  You preview and confirm before anything changes, and your tags, ratings, and
  notes are preserved. See
  [Write & edit dances](./authoring.md#fix-figures-an-import-could-not-read).

### Backup & restore

- **Export a backup** and **Restore from a backup** — save a copy of everything or
  bring a copy back.
- **Backup reminder** — set to **Off**, **Weekly**, or **Monthly**, with a "last
  backup" date so you know where you stand.

For the whole workflow, see [Backup & portability](./backup-portability.md).

## Program

The **Program** section gathers the settings that shape how you build, check, and
perform your [programs](./glossary.md#program) — venues, the programming matrix,
Perform mode, and calling history.

### Venues

- **Use reusable venue records** (off by default) — turns a program's
  [venue](./glossary.md#venue) into a reusable record with address, contacts, and
  schedule that many programs can share and you edit in one place. When off, a
  program's venue is a simple free-text field. Switching is **lossless and
  reversible**: your typed venue text and any linked record are both kept, so
  flipping the toggle never discards either.
- **Manage venues** — browse, edit, and delete your saved venue records. You can
  also add a venue on the fly while editing a program (when reusable venue records
  are on). A deleted venue doesn't go to Recently deleted, so you can't restore
  it on its own. To keep you from stranding a program, a venue can't be
  deleted while any program is still linked to it; change or remove the venue on
  those programs first, then delete it. A program in **Recently deleted**
  doesn't count, so it won't stop you deleting the venue, and restoring that
  program brings the venue back.

Whether the toggle is on or off, a program that's linked to a saved venue always
shows and exports that venue's full details (the linked record wins over free
text). See [Programs](./programs.md) for how the venue field behaves in each mode,
and [Share, print & export](./sharing.md#what-stays-private) for how venue contact
details are handled when you export.

### Programs

- **Flag exact beat overlap only** (on by default) — controls how the
  [programming matrix](./programs.md#check-your-evening-with-the-matrix)'s alert
  marker decides that a move repeating in two back-to-back dances is worth a
  second look. On (the default), only a move whose beats actually **overlap**
  between the two dances is flagged. Off, any move that merely lands in the same
  **named phrase** (A1, A2, B1, B2…) is flagged, even if its beats don't overlap
  at all. The screen legend and the printed PDF legend always agree with
  whichever mode is on.

- **Auto-save program changes** (off by default) — when on, valid changes are
  saved as you work, so leaving the program editor never asks whether to
  discard them. Leave it off to save programs yourself.

- **Matrix columns** — opens a dedicated editor for the columns of the
  [programming matrix](./programs.md#check-your-evening-with-the-matrix). These
  changes are saved and apply to **every** program, both on screen and in the
  printed PDF — distinct from the per-session eye icon in a matrix's own header,
  which only hides a column until you reopen that program. In the editor you can:
  - **Reorder** columns by dragging the handle on the left of each row.
  - **Rename** a column with a name that suits your callers; leave the field
    empty to fall back to the built-in name (shown as a hint).
  - **Remove** a column you never use, or **restore** one you removed earlier —
    removed columns stay listed here (struck through) so you can always bring
    them back.
  - While [Custom Figures](#glossary-and-custom-figures) is on, each of your
    new figures is listed as a column, so you can arrange it before any program
    uses it. A new one is listed after the built-in moves and before **Custom**,
    or, once you have moved columns, after the ones you placed. Columns you
    placed keep their place while Custom Figures is off.
  - **Restore removed columns** brings back everything you removed and returns the
    built-in columns to their original order, while keeping your renames and any
    custom columns.
  - **Restore all defaults** clears every customisation and returns the matrix to
    how it ships. Because it discards your renames and custom columns, it asks
    you to confirm first.

### Performance

- **Auto-size Perform cards** (on) — scales each card so it fits the screen in
  [Perform mode](./glossary.md#perform-mode). Turn it off when you'd rather size
  the text yourself using the **A−** and **A+** buttons while performing. See
  [Perform mode](./perform.md) for more. Like the stage theme and the text size
  you pick in Perform, this setting belongs to this device: it is not synced to
  your other devices, but a backup includes it.
- **Show timer for individual Perform** (on) — shows an elapsed timer and
  pause/resume control while performing a single dance. Turn it off when you
  want individual Perform to stay timer-free.
- **Show caller notes in program Perform** (on) — shows each non-empty
  per-slot caller note above the dance title while performing a program. Turn it
  off when you want the program card to show only the dance's own details.

### Calling history

- **Require "mark performed" for calling history** (off) — when on, a dance's
  calling history lists only the [programs](./glossary.md#program) whose
  [slot](./glossary.md#slot) was actually marked performed, rather than every
  program the dance appears in. Either way, an
  [alternate](./glossary.md#alt) counts only once you mark that slot performed;
  **Mark all performed** and the **Performed** status skip alternates, so mark
  the ones you used yourself.
- **Show mark-performed toggles** (on) — adds a circle to the end of each dance
  row on a saved program's summary, alternates included, so you can mark that
  dance performed (or clear the mark) without opening the editor. Marking or
  clearing offers an **Undo**. Turn it off and rows only show a check on dances
  already marked performed. The change applies straight away.
- **Require an event date for calling history** (off) — when on, a program with
  no event date counts nowhere calling history is read (the "called ×N" count,
  the **Called** filter, a dance's history list, the **Last called** sort, and
  the repeated-venues and half summaries) until you give it a date. Duplicated
  programs and programs another caller sends you arrive without a date. When
  off, a program counts whether or not it has a date. It applies on top of the
  other calling-history settings (all must pass).
- **Track calling history for all callers** (off) — when off *and* you've set a
  [default caller for new programs](#program-defaults), a dance's calling history
  and "called ×N" counts include only programs led by that caller (plus any
  programs with no caller recorded, which are treated as your own). Turn it on —
  or leave the default caller blank — to track every program that contains the
  dance. Matching ignores surrounding spaces and letter case, and applies on top
  of the *Require "mark performed"* setting (both must pass). Collection's
  counts and **Last called** sort follow a change to the default caller straight
  away.
- **Repeated venues in calling history** (3) — shows the top venues where a
  dance was called more than once. Set this to 0 to hide the summary, or choose
  up to 10 venues.

## Appearance

The **Appearance** section controls how the app looks.

### Theme

A gallery of built-in themes: **System** (follows your device), **Light**,
**Dark**, and a set of named color palettes, including high-contrast and
editor-inspired schemes. Selecting a theme previews and applies it right away.
There's a **High contrast** theme for maximum legibility — see the
[Accessibility guide](./accessibility.md) for when it helps.

### Custom themes

- **New custom theme** — opens an editor seeded from your current theme, so you
  start from something familiar. You can tune any colour in it.
- Saved custom themes can be selected, edited, duplicated, or deleted at any time.
  They sync to your other devices along with your other settings when sync is on, and deleting a theme deletes it on those devices too.

### Easter eggs

- **Colour-named dances tint the theme** (off by default) — a playful surprise:
  open a dance whose title names a colour, like *Baby Rose* or *Blue Boy*, and its
  view is tinted that colour. It steps aside when a high-contrast theme is active,
  so readability always wins.

### Set lists

- **Colour-code set-list rows** — tints each dance row in a program's set list
  (both the read-only summary and the builder) by its
  [formation](./glossary.md#formation) family — contras, triplets, mixers,
  circles, and squares each get their own accent, so you can read the *shape* of a program at a
  glance. Dances marked as [mixers](./glossary.md#mixer) always get the mixer
  accent regardless of their formation, so a mixer-flagged Improper reads as
  a mixer rather than a contra. The formation (and "Mixer" when applicable) is
  always shown as text on the row too, so rows stay fully readable without relying
  on colour, and the accents adapt to the High contrast theme. On by default; turn
  it off to hide the tints.

### Formation colours

- **Formation label colours** — highlight individual formations in your own
  colours (for example Becket clockwise in yellow and Becket counter-clockwise in
  pink). Your choices show on dance cards, in dance detail, and in the Perform
  header.

### Tag colours

- **Tag colours** — give a tag its own colour so it stands out wherever it
  appears, on dance cards and in dance detail. Only the tags you colour change;
  every other tag looks exactly as it does now. The tag's name is always shown
  beside the colour, so tags stay readable without relying on colour, and the
  app picks a black or white label automatically so your colour stays legible in
  every theme.

## Dialect

The **Dialect** section is your library of [dialects](./glossary.md#dialect) — the
role names and wording the app uses when it describes dances.

- **New dialect** starts a dialect of your own, and **Duplicate from…** copies
  an existing one as a starting point.
- Preset dialects are read-only, but you can **Duplicate to customize** to make
  your own version.
- Custom dialects can be edited (**Edit terms**), renamed, or deleted.
- One dialect is active at a time; select a dialect in the list to make it
  active.

### Dance details & shorthands

- **Canonical figure text** (off by default) — allow dance details to show
  canonical role and move names. When it is off, dance details open in your
  active dialect and do not show the in-detail **Canonical** switch.
- **Auto-convert all discouraged terms** (on by default) — show supported
  discouraged terms in canonical wording across read-only dance details,
  shorthands, notes, Perform mode, and exports. Saved text and entry fields are
  unchanged.
- **Open dance details in canonical terms** — when this and **Canonical figure
  text** are both on, dance details open in canonical wording. While
  **Canonical figure text** is off, this preference is kept but has no effect.
- **Free-text entry** (off by default) — when on, adding a figure lets you type
  a whole line (for example "neighbor balance & swing") instead of building it
  field by field. A figure already in the dance still opens in the full editor,
  but a line typed into its move and entered replaces it with what the line
  reads as, and a new dance starts with no figures unless you have saved
  starting figures. See [Free-text entry](./authoring.md#free-text-entry).
- **Figure shorthands** — map short tokens to one or more figures you can insert
  during free-text entry. This row is greyed out until **Free-text entry** is on. See
  [Figure shorthands](./authoring.md#figure-shorthands).
- **Walkthrough snippets** — manage your personal, per-figure walkthrough
  wording. These settings are independent of canonical figure text.

This is the entry point — see [Dialect](./dialects.md) for the full story on
choosing and customizing wording.

## Language & region

The **Language & region** section handles formats and localization.

### Formats

- **Date format** — choose **System default**, **Year-month-day**,
  **Day/month/year**, **Month/day/year**, or **Custom…**. A live example shows the
  result, and your choice controls how program event dates appear: in the
  Programs list and editor, in a dance's calling history, and in printed and
  emailed set lists and PDFs. **System default** always includes the year and
  follows your **device's region** (not the app language): on a phone in
  Denmark, an English-language app shows `15.7.2026`, whether the phone itself
  is set to Danish or English. It uses all-numbers dates, so a date never mixes
  two languages' month names. A few multilingual regions (Belgium, say) have no
  single order and use your device language's default. Pick a fixed format or
  **Custom…** if you want one layout everywhere.

  A custom pattern is built from these tokens:

  | Token | Meaning |
  |---|---|
  | `yyyy` or `yy` | Year |
  | `MM` | Month as digits |
  | `MMM` | Month as a short name |
  | `MMMM` | Month as a full name |
  | `d` or `dd` | Day |

  Separate them with a hyphen, slash, dot, comma, or space. If a pattern isn't
  recognised the app says so and falls back to the system default until you
  correct it.

- **First day of week** — choose **System default**, **Sunday**, **Monday**, or
  **Saturday**. This sets which day starts the week in the date views the app
  draws for itself — today that is the "this week" strip at the top of the
  Programs list, which reorders the moment you change the setting. Date *entry*
  still uses the system picker, which follows the app's active language.

### Language

- **App language** — choose **System default** or one of the bundled languages
  (currently English, German, French, Japanese, Danish, and Dutch). Changing it
  re-renders the app immediately and is remembered next time you open the app.
  With **System default**, the app follows your device's language when it is one
  of those bundled languages and otherwise uses English. The language belongs to
  this device: it is not synced to your other devices, so each one can use its
  own, but a backup includes it.
  Your dance content — figure and call wording — is governed by your chosen
  [dialect](./dialects.md), independent of the interface language.

## Defaults

The **Defaults** section sets starting points: how lists open, what dance rows
show, and what new programs and dances begin with. Every default here can still
be changed on each item later — they save you repetitive setup.

### Display defaults

- **Collection sort order** and **Programs sort order** — the order your
  library and your Programs list use when you open them. Choose a fixed order,
  or **Last used** to open with the sort and direction you last used while
  browsing. You can still change the sort while browsing. The program dance
  picker also opens in the Collection sort order; a sort you choose in the
  picker is not remembered as the last used.
- **Ascending / Descending** — shown under a fixed sort order. It sets which
  way that list opens, so you can have Programs always open newest event first.
  Each order starts in its natural direction (Title and Event date ascending,
  Recently updated descending), and choosing a different sort order puts the
  direction back to that sort's natural one. It is hidden under **Last used**,
  which remembers the direction itself.

### Collection card fields

Choose which details appear on each dance row in your collection and in the
program dance picker: **Authors**, **Times called**, **Formation**, **Status**,
**Level**, **Rating**, **Tags**, and **Custom fields**. All of them are shown by
default.

### Shared dance fields

Choose which details appear when you share, copy, or export a program or dance:
**Authors**, **Formation**, **Level**, **Mixer**, **Status**, **Phrase**,
**Calling notes**, **Walkthrough**, and **Tunes**. Authors are shown by default
and tunes are hidden until you turn them on. See
[Choose which dance fields appear](./sharing.md#choose-which-dance-fields-appear).

### Collection filters

Choose which filters appear in the **Filters** panel on the Collection screen and
when you pick dances for a program. Every filter is shown until you untick it,
and each of your searchable custom fields has its own checkbox. Hiding a filter
only removes it from the panel: it does not delete anything, and the Advanced
search can still use the same properties. This differs from a custom field's own
**Searchable** setting, which also keeps the field's values out of the search
bar (see [Make your own fields](./collection.md#make-your-own-fields)). If you hide a filter that is currently
narrowing the list, its selection is cleared. A filter that is narrowing the
list when you open a dance's tag from its detail page stays visible until you
clear it.

### Program defaults

Select **Program defaults** to open this group.

- **Default caller** and **Default band** — prefilled into each new program, and
  editable per program.
- **Starting program** — an ordered template of dances, caller notes, breaks,
  and free-text entries for programs you create by hand. Dances that are no
  longer in your collection are skipped. It applies only when you create a
  program in the editor; imports, duplicates, and “create with this dance” keep
  their own slots.

### Import defaults

Select **Import defaults** to open this group.

- **Tags for imported dances** — tick the tags you want added to each new dance
  you import on its own: from the import screen (including a pasted list of
  titles), from an online search (including the one in the program editor's
  dance picker), or from a shared dance link. It applies only
  to dances the import creates, including those from a file someone shared with
  you, alongside the tags the sender gave them. A dance an import updates in
  place, and a dance created for a program slot while importing a program (from
  a file, from a title list, or from ContraDB), keep whatever tags they already
  have. A program in a Caller's Companion file, a shared file, or a published
  collection is still imported, but only its dances receive the tags. You can choose up to 50 tags. The choice is remembered by tag name, so it
  survives a sync or a merge restore. If you later delete one of the tags,
  imports simply skip it. Dances you create in the editor are not tagged either.
  Choosing tags here does not change dances already in your collection, and
  **Undo** on an import removes the dances it created along with their tags
  (the tags themselves stay).

### Dance-authoring defaults

These help if you write your own dances. Select **Dance-authoring defaults** to
open this group. You can override any of them per dance, and
[Write & edit dances](./authoring.md) covers them in context.

- **Level** — open this to manage the difficulty levels used by dance editors,
  collection filters, and batch actions. Add a level, rename it, or drag it into
  a different position; renaming keeps existing dances attached to that level.
  A level can't be removed while any dance uses it. A dance in **Recently
  deleted** doesn't count, so it won't stop you removing a level, and restoring
  that dance brings the level back. Once no dance
  uses it, you can remove any level, including the ones that ship with the app. Removing a level asks nothing first and shows
  **Undo** for a few seconds, which puts the level back in its place.
- **Type**, **Formation**, and **Progression** — the starting choices for a new
  dance.
- **Default phrase structure** — leave blank for the standard 4×16 A1 A2 B1 B2, or
  set your own.
- **Starting figures** — the figures a new dance begins with; defaults to eight
  stand stills of eight beats each, or to none while **Free-text entry** is on.
  Clear it for a blank new dance.
- **Meanwhile defaults** — the ordinary side figures used when you choose **Add
  meanwhile** while authoring a dance. Leave this list empty to start with two
  blank sides, or configure up to six ordinary sides. If only one side is
  configured, the app adds a blank second side so the container can be completed.
  Invalid or unavailable saved defaults use two stand-still sides.
- **Modifier defaults** — the core and modifier figures used when you choose
  **Add modifier** while authoring a dance. Leave this list empty to start with
  two blank figures, or configure up to six figures. If only one figure is
  configured, the app adds a blank second one. Invalid or unavailable saved
  defaults use two stand-still figures.
- While [Custom Figures](#glossary-and-custom-figures) is on, each of these three
  lists also offers your own new figures for the **Type** set above, as the
  dance editor offers them for a dance's form. A list keeps a figure it
  already holds when you change the form.
- **Move defaults** — preferred parameter values applied automatically when you
  insert a [move](./glossary.md#move) while writing, whether you pick it or type
  it with **Free-text entry**. These override that move's built-in defaults, but
  not a value you type in the line (`half hey`), and you can still change any
  parameter afterwards. While
  Custom Figures is on, **Your figures' defaults** lists each of your new
  figures that can be used (not one marked **Needs repair**): a figure keeps its own defaults, the values it starts with and its
  beats, so choosing one opens it to change them.
- **Aggressively recompute figure beats** (off by default) — when on, changing a
  figure's move or a parameter that affects timing recalculates its beat count
  immediately, even overwriting a beat count you typed in by hand. When off, a
  beat count you've edited is only changed automatically when you switch a
  balance option on or off, which adds or removes 4 beats.

## Updates

The **Updates** section lets the app tell you when a newer version is out — and,
on desktop, help you install it. Nothing here happens behind your back: the app
never updates itself automatically, and no update is ever downloaded or installed
without you choosing to.

- **Check for updates** — check right now, any time. It shows the version you're
  on and whether a newer one is available. If it can't check, for example because
  you're offline, it says so in the same line rather than reporting that nothing
  was found; it never interrupts you with an error dialog. If the update service
  has a release in a form this version can't read, the line says a newer version
  is available from the Releases page.
- **Beta channel** (off by default) — turn this on to be offered pre-release beta
  versions. Left off, you're only offered stable releases. While Caller's
  Compendium is in beta, every release is a beta release, so turn this on if you
  want the app to tell you about new versions.
- **Check automatically** (off by default) — when on, the app quietly checks for a
  newer version as it starts up. If that check can't complete, it stays quiet.
  Left off, checking only happens when you ask.

When an update is available, a dismissible banner points you to the release so you
can read what's new before deciding.

How you installed the app decides what Updates offers:

- **Installed from an app store** (iOS, or Android through Google Play): the
  store updates the app. Updates shows a note saying so, with no **Check for
  updates** button or **Beta channel** switch, and the app never offers an
  update. With **Check automatically** on, it still looks for an end-of-support date; the notice
  appears here and as a banner, and **Get update** opens the store (TestFlight on
  iOS, Google Play on Android).
- **Portable copy** (the Windows .zip or the Linux .tar.gz): the app checks as
  usual, but instead of **Download & install update** it tells you to download
  the new archive from the release. Tap the row (or **View release** on the
  banner) to open the release page. Replace this copy with the new archive
  yourself; the app doesn't unpack it for you.
- **Everything else** (the Windows installer, the Linux AppImage, macOS, and the
  Android APK from the Releases page) works as described below.

Occasionally a version of the app reaches the end of its support, for example
when a later release changes something older versions can't keep up with. If an
update check finds that your version has an end-of-support date, a banner tells
you the date you need to update by. On that date and afterward it says that
support has ended. **Get update** opens the newer release. **Later** hides the banner until you
next open the app. It comes back after that, because you can't skip an end of
support the way you can skip one update. The notice is also shown at the top of
the **Updates** section. The app remembers it, so it still appears when you're
offline. Once you've updated, the notice goes away. Versions up to and including
0.6.0-beta were released before these notices existed and can't show them.

On **desktop** (a portable copy excepted), once an update is found you can **Download & install update**: the
app downloads it, verifies it hasn't been tampered with, then hands it to your
system's installer to finish — it never replaces itself in place. On **macOS**,
you first choose where to save the disk image. If you pick an existing file and
confirm **Replace**, the new download replaces it; if a folder or a symbolic link
already has that name, the app asks you to choose another name or folder. After
it is verified, choose **Update now** to open the image and close the app; you
can then replace the app in **Applications**. Choose **Not now** to keep working and use **Update and
restart** from the banner or Updates section later. On **Windows**, clicking
**Download & install update** authorizes the verified installer to run; it handles
closing and replacing the existing installation. On **Linux**, the verified
download is shown in your file manager for you to run yourself; the app never
runs it for you. On Windows and Linux, the downloaded file stays in your
system's temporary folder after a successful download, and the next time the
app starts it deletes update downloads there that are a week old. It never
deletes the folder of the copy you are running, but on Linux, if you want to
keep the AppImage, move it out of the temporary folder to somewhere permanent
(your home folder, say) before then. On phones and tablets, the
banner's link takes you to the release to download it the usual way for your
platform.

If the download fails, the message says why: your connection, an error from the
update server, a full disk, or a folder the app cannot write to. Free some space
(on macOS, you can also choose another location), then try again. **View release** is always there as
a manual fallback. A failure during the transfer or while saving the file is also recorded in
**Settings** → **Diagnostics**, without file paths.

Your privacy is built in: an update check downloads a small version file over a
secure connection and nothing else. No information about you, your device, or how
you use the app is ever sent.

## Diagnostics

When something goes wrong, the app writes a short technical note to a log on your
own device — not just outright crashes, but also errors you see reported on
screen (like a failed import). **It is never sent anywhere — there is no
telemetry.** The **Diagnostics** section is where you read that log, hand a
copy to a bug report, or wipe it.

### Recent entries

A list of the most recent entries, newest first, so you can see whether anything
was captured around the time the trouble happened. If nothing has ever gone wrong
you'll see **No errors recorded**. If the log can't be read, the app says so and
still lets you try to export or clear it.

### Export

- **Include full detail (may contain your content)** — **off by default**. Left
  off, the export removes the text of error messages, your content, file paths,
  email addresses, and phone numbers. The one exception is the short, fixed
  description the app itself writes for a failed update download, online import
  or published-collection download (such as a timeout or an HTTP status
  code), which has no content or path in it and stays, so a report can tell a
  timeout from a 404. Turn it on only when you mean to share the full,
  unredacted log.
- **Export / share log** — hands the log to your system's share or save dialog.
  The row tells you which kind you're about to send: a scrubbed copy safe to
  attach to a bug report, or the full unredacted log. If the app can't prepare a
  safe scrubbed copy it saves nothing and tells you, rather than sending more than
  you asked for.

If Device Sync is on or has done anything since the app opened, the export
ends with a short **Device Sync** part: how the last sync went (the same short
code **Copy details** gives, plus the step and HTTP status), how full the store
is if the app knows, and which kinds of notice are showing with how many of
each and for which kinds of record. It never includes your sync phrase, the
server's address, titles, or anything that identifies a device or a record, so
it's in the scrubbed copy too. This part is always in English, like the rest
of the export.

If there is nothing in the log and Device Sync has nothing to report, the app
says **No diagnostics to export** instead of producing an empty file.

### Clear log

- **Clear log** — deletes the local crash log from this device. The app asks first
  and is blunt about it: this cannot be undone. If the log can't be cleared (for
  example, another program has the file open), the app says so and the entries
  stay listed.

Filing a bug? A scrubbed log attached to a
[GitHub issue](https://github.com/ibanner56/CallersCompendium/issues) is the most
useful thing you can send.

## Experimental

The **Experimental** section holds features that are still in development —
today, that's the **Glossary**, **Device Sync** and **Developer Options**. Anything here can change
before it becomes a regular setting. Each feature sits in its own section: select its heading to
open or close it.

### Glossary and Custom Figures

**Show Glossary** adds a **Glossary** destination to the navigation, between
**Programs** and **Settings**. It is **off by default**, and the section starts
closed while both Show Glossary and Custom Figures are off.

The Glossary is a reference to the figures built into the app. Search it by a
figure's name, an older name for it, or a word from its definition. Select a
figure to see:

- a one-line definition and a short description of how it's danced
- an **Example** of how the figure is written
- its **Parameters**, the details you can set on it in the dance editor
- other names it is **Also known as**, with discouraged terms struck through
- **Your notes** on it: choose **Add notes** or **Edit notes** to write your
  own, such as how you call it or what to watch for. Clear the text to remove
  them.

Names, definitions and examples follow your active
[dialect](dialects.md), so role words read the way you call them. The built-in
figures come with the app, and turning the Glossary off only removes it from
the navigation; your notes are kept, and come back when you turn it on again.
The built-in definitions and descriptions are in English whatever language the
app is set to; only the Glossary's labels and buttons are translated.

While [Device Sync](#device-sync) is on and a store is connected, a **Sync now**
button sits beside **+** in the Glossary toolbar, the same as on Collection and
Programs, so your terms and notes can be pulled from another device.

**Your terms** are words you define yourself, with no figure: a name and a
definition (both required), **More Details** (optional), other names they can be found by,
notes, and the **Dance form** they're for. They are listed in the Glossary
alongside the built-in figures, marked **Custom**, and found the same way.
Choose **+** in the Glossary to add one (with Custom Figures on, choose
**Term** under **What it is**); select one to **Edit** or **Delete** it. Terms
need only Show Glossary, not Custom Figures. A name already taken can't be
saved, as for your figures below; one of your own figures keeps its name even
while Custom Figures is off and it isn't shown, and saving says so. Terms can
also come from a Caller's Companion file (see [Bring your glossary terms
across](./imports.md#bring-your-glossary-terms-across)); such a term's page shows
its **Source** as the file had it.

**Custom Figures** lets you make your own figures and use them in dances. It
is **off by default**, and it doesn't need Show Glossary: with the Glossary
hidden you can still turn it on, and use your figures everywhere. If you turned
it on in version 0.8.0-beta or before and later turned the Glossary off, it was
greyed out but kept its setting. It now takes effect, and your figures
show again everywhere Custom Figures shows them. Turn Custom Figures off here
to hide them. While it is on, the **Your figures** row under the switch opens them: see your figures,
choose **+** to add one, or select one to **Edit** or **Delete** it. The row
is greyed out while Custom Figures is off.
The Glossary lists them too, when it is shown. While it is on:

- Choose **+**, on that screen or in the Glossary, to add a figure of your own: a name and a
  definition (both required), **More Details** (optional), other names it can be found by,
  notes, and the **Dance form** it's for.
- Under **What it is**, choose a **Combination**, which becomes figures that
  come with the app when you save a dance, a **New figure**, which stays
  one figure with your own wording, or, when you add from the Glossary, a
  **Term**. An entry keeps the kind it
  was saved with, except that a term can be given a figure: select it and
  choose **Make it a figure** to give it wording and parameters as a new
  figure. It keeps its name and other fields, and can't be turned back into a
  term.
- To start from a figure that comes with the app, open it in the Glossary and
  choose **Copy as your own figure**. The editor opens on a new figure named
  after it with **(copy)** (numbered if you already have one), with its
  definition and More Details, its beats, its wording, and the parameters that
  wording uses, with their defaults (a variant, such as *pull by neighbors*,
  starts from its own). The wording is the figure's plain one where the app
  words it in a way of its own, so read it through before you save. Its
  `{move}` is the copy's name, so rename it to what a dance should say.
  Nothing is added until you save. The copy is yours alone: the built-in
  figure doesn't change, and later changes to the app's figure don't reach
  the copy. Its page says what it was copied from.
- Build a combination from figures that come with the app, in order, the same
  way as in the dance editor. Custom figures and meanwhile, modifier and
  sequence groups can't be used as parts.
- Give a new figure its **Wording**, how it reads in a dance: put a parameter
  in braces, such as `{who}`, use `{move}` for the figure's name and `{beats}`
  for its beats, and put a part in square brackets to leave it out when its
  parameters are empty. To word it differently in some cases, start the
  square brackets with `if`, such as `[if who is robins then … else …]` (see
  [Word it differently in some cases](./dialects.md#word-it-differently-in-some-cases)).
  A parameter whose kind has an opposite, such as a hand, also offers it, such
  as `{otherHand}`. **Reads as** shows the wording
  with each parameter's **Default**. A parameter can be an **option** you name
  the choices of, and an on/off parameter has its own **Wording when on**. Set
  its **Default beats**; a dance can change them each time.
- Add **Parameters** for what can differ from one use to the next, such as
  *who* and *which hand*. In a combination, under **Filled in by parameters**,
  choose which of each figure's settings come from them. A setting can also take the **opposite** of
  a parameter — the other hand, the other role, or partners for neighbors and
  neighbors for partners — where that has one. A choice
  that can't be used, because the kinds differ or no value would fit every
  setting it fills, is shown greyed out with the reason.
- If a parameter fills nothing, or a new figure's wording leaves it out, saving
  asks whether to go **Back to editor** or **Save anyway**; a parameter a
  condition tests counts as used. Wording that uses something the figure
  doesn't have can't be saved.
- A parameter can't be named `if`, `then`, `else`, `not`, `and`, `or` or `is`:
  conditions are written with those words. A figure saved with one before
  conditions arrived is marked **Needs repair** until you rename it.
- A name already taken can't be saved: a built-in figure's name or one of its
  other names, a figure's name in one of your dialects, one of your
  shorthands, or another of your figures or terms.
- In the dance editor, your figures for the dance's form are offered when you
  choose a figure's move. A combination becomes the figures it stands for when
  you save the dance; a new figure stays one figure that reads with your
  wording (see [Your own figures](./authoring.md#your-own-figures)). You can
  also give either kind a [shorthand](./authoring.md#figure-shorthands) with
  set values.
- In the Collection's **Advanced** search, a **Has figure** row offers your new
  figures, to find the dances that use one (see
  [Search by the moves a dance contains](./collection.md#search-by-the-moves-a-dance-contains)).
  In a program's [matrix](./programs.md#check-your-evening-with-the-matrix),
  each new figure a dance uses gets a column of its own, which **Matrix
  columns** lists so you can move, rename or remove it.
- Your figures are marked **Custom** in the list. Select one to see what a
  combination **Expands to** (folded until you open it), or a new figure's
  **Wording** and an **Example** with its defaults, and to **Edit** or
  **Delete** it. Deleting a new figure says how many dances use it; each keeps
  the wording it shows now, as plain text. It also says how many dances in the
  Trash use it, which keep the line each last stored, and whether your default
  figures use it; they keep its current wording as plain text, like the
  dances. Each dialect's name and wording for it, and its column's place, name
  and hiding in **Matrix columns**, are removed too. Deleting a combination or
  a new figure also says how many of your shorthands are for it: they stay,
  and once the figure is gone, typing one is read as an ordinary line (see
  [Figure shorthands](./authoring.md#figure-shorthands)). A figure that can no longer be used
  is marked **Needs repair**; one whose name is also another figure's is
  marked **Rename needed**.
- If a later version of the app comes with a figure that has the name of one
  of your new figures, your figure's page says so, with two choices.
  **Rename mine** opens it to give it another name. **Switch to the app's figure**
  opens a page where you choose which of the app's figure's parameters each of
  yours becomes, and which of its values each of your options becomes; where a
  name matches, it is chosen for you. An option can become any parameter that
  takes words, such as a hand or who; any other parameter, one of the same
  kind that takes all its values. Two of yours can't become the same one.
  Every one must be chosen, so a parameter the app's figure has nothing for
  stops the switch: remove it from your figure first, or rename yours.
  **Switch** then says how many dances use your figure, as deleting does, and
  once you confirm, each of them uses the app's figure instead, with the same
  beats, and your figure is removed. Your default figures switch the same way,
  and your shorthands for it insert the app's figure (but one whose values
  your figure no longer has, or whose name another shorthand also has, stays
  as it is). A line whose wording was edited in an older version of the app,
  or that holds a value your figure no longer has, keeps its wording as plain
  text, and dances in the Trash keep the line each last stored. As with
  deleting, each dialect's name and wording for your figure, and its column in
  **Matrix columns**, are removed: the app's figure has its own.

Turning Custom Figures off hides your figures; it doesn't delete them. They are
kept in your backups.

With [Device Sync](#device-sync) on, your own figures and terms, your notes on
built-in figures, the Custom Figures setting and your shorthands for your own
figures sync to your other devices too, once every device connected to your
store has this version of the app or a later one. Until then changes to them
aren't sent to your other devices, and Device Sync shows a note naming the
device that is holding them back (see [New kinds of data wait for every
device](#new-kinds-of-data-wait-for-every-device)). One exception, while the app
is in beta: a figure or term saved with **More Details** left blank, or an edit
that clears it, isn't picked up by a device on an older version of the app,
which keeps what it had until it is updated.

Your figures and your notes on built-in figures share a size limit, which
keeps what you add from growing too large to back up. It is far more than most
callers will use (thousands of short figures). If you reach it, saving says that
your Glossary has reached its size limit: delete or shorten some figures or
notes to make room, then try again. Shortening or deleting is always allowed.
Figures and notes that arrive from another device with Device Sync, or from a
backup you restore, are always kept, even if they take you past the limit; you
can then edit them down but not add more.

### Device Sync

**Device Sync** keeps your library in step across your own devices. It is **off
until you turn it on** with **Turn on Device Sync**, and while it is off the app
sends nothing anywhere. Turning it on does not send anything by itself; nothing
is exchanged until you connect a store. The section starts closed while Device
Sync is off and open while it is on.

- **Sync only on Wi-Fi** is on by default. On a mobile-data connection automatic
  sync waits, and pressing **Sync now** tells you why. In this section it points
  at this setting; from the sync icon on **Collection** or **Programs** it tells
  you to turn the setting off here in Settings.
  A pass that was skipped runs the next time sync is triggered — when you
  change something, open the app, or come back to it — and you do not need
  to do anything.
- **Closing the app during a sync.** The app says **Closing…**, saves any
  open editor's draft first, and then gives a sync that is still running up to
  ten seconds to finish before it closes anyway. Your changes are already saved
  on this device; a sync cut short this way runs again the next time you open
  the app.
- **Skip unused imported dances** is off by default. If you have a large
  imported collection, turning it on cuts what this device uploads — but a
  dance that's actually used in one of your programs, or linked from another
  dance, is always included, so nothing that's still in use loses anything.
  Turning it on removes nothing already on your other devices; this device
  stops advertising the rest. Turning it back off republishes them.
- **Status** opens with **Your sync phrase** — the phrase this device is
  connected with — so you can add another device later even if you didn't write
  it down when you first connected. It stays hidden behind bullets until you
  choose the eye button, and **Copy** puts it on the clipboard without showing it,
  which is all you need to type or paste it into the other device. Keep it to
  yourself: the phrase is where your shared library lives, so anyone who has it
  can open that library — read everything you sync, change or delete any of it
  on every connected device, and delete the whole store from the server.
  Changing the phrase means moving every device to a new one.
- **Status** names the server this device is syncing with, written out in full
  as an address. That's the Caller's Compendium server unless you set your own
  when you connected; a server that isn't the default one is flagged, because
  whoever runs it can read and change everything you sync.
- **Status** also tells you when a first connection merged duplicate dances —
  "Found and merged 3 duplicate dances", say. Connecting a device that already
  holds some of the same dances joins them up silently, and this is what tells
  you it happened. It shows after any first connection to a store: when you
  pair, when you reconnect a store that went missing, and when this device
  rejoins a store that was replaced. It stays put for the rest of the time the
  app is open, rather than flashing past while you're not looking, but it is
  **not** kept once you close the app — so if the number matters to you, write
  it down. The dances are already merged either way; the count is a report, not
  something waiting to be dealt with.
- **Status** also shows when this device last synced. **Sync is not a backup:**
  a store that goes unused for 30 days is removed, so keep making file backups.
  From three weeks of disuse the status also warns that the store is close to
  expiring.
- **When a sync can't finish for a reason that sorts itself out** — the sync
  server couldn't be reached or took too long, the server had a problem of its
  own, or it asked this device to slow down — the status calmly says **Waiting
  to sync. Your changes are saved here.** Nothing is wrong with your library,
  and you don't need to do anything: the app tries again by itself, waiting a
  little longer each time (from a minute up to half an hour, and never sooner
  than the server asked), and also tries when you come back to the app. The
  server limits how quickly one device can send and fetch. The app fetches
  records from your other devices and sends its own in batches, so connecting
  a device to a large library usually finishes in one try, or a few for a very
  large one. With a self-hosted server that hasn't been updated for batches,
  fetching or sending goes one record at a time and can take several of these
  tries: roughly a minute for every few hundred records, or for every sixty
  against an older server still. Each try keeps what it got through, so while it is
  still getting further the app tries again every minute rather than waiting
  longer, and nothing it hasn't fetched yet is reported as skipped. If the
  server has a problem sending another device's latest list, changes to
  records your devices already share wait until it can, so the status says
  **Waiting to sync** even though anything new still arrived. A small
  **Details** line still names the step that stopped and the HTTP status, if
  you're curious. If this goes on for weeks, the expiry warning below is what
  tells you.
- **When a sync fails for a reason you need to deal with**, the status shows a
  warning and says why: your store is out of space, something was too large to
  upload, the server refused what was sent or didn't accept the sync phrase, it
  sent a reply the app couldn't use, another device's latest list was missing
  or unreadable during a first connection (a problem on the server's side
  while fetching it is the calm kind above), or something went wrong inside
  the app. Each
  comes with what you can do about it, and — where it's known — a **Details**
  line naming the step that stopped and the HTTP status the server answered
  with. If the server refused what was sent, the advice depends on the server:
  on the Caller's Compendium server it means this version of the app is newer
  than the server, your changes are saved here, and they'll sync once the
  server is updated; on a server you run yourself, it asks you to update that
  server. These are not retried by themselves, because waiting won't fix
  them. The **Sync now** button on the Collection, Programs and Glossary pages reports a
  failed sync the same way — calmly or with the reason — so you don't need to
  come here to find out.
- **Copy details** sits beside every warning. It puts a short code on the
  clipboard — something like `SYNC-STORE-FULL upload 507` — that you can paste
  into a message to whoever helps you. The code names the problem and nothing
  else: no phrase, no titles, nothing about your devices. Nothing is sent
  anywhere; you choose where to paste it.
- **When your store is almost full** — 80% or more of the space or the number
  of items the server allows — the status warns **Your sync store is almost
  full.** If **Skip unused imported dances** is still off, the warning offers
  a **Skip unused imported dances** button that turns it on, since imported
  dances are usually most of what a store holds.
- **Notices** appear under that last-synced line when a sync had something to
  report. A sync can finish successfully and still leave one of these standing,
  which is the point of them: the conditions they name are ones the app will
  not guess its way out of. You'll see a notice when the same record was
  changed on two devices in the same moment and isn't something you can pick
  a version of here (if it's listed under **Sync decisions**, choose there;
  otherwise edit either one to settle it); when something created here was kept rather
  than removed by a device that had never seen it; when something on *this*
  device has a date the app can't trust, so it isn't being sent anywhere
  (check this device's clock); when some dances here have saved figures or
  tunes the app can't read, so they aren't being sent (nothing is deleted —
  enter those figures or tunes again to send them); when another device is
  using a newer version of the app, so this device can't read some of what it
  shared — in a newer format, with details this version can't keep, such as
  new details inside a dance's figures (those dances are marked as having
  figures only a newer version can read), or as a kind of data this version
  doesn't have yet, in which case everything else from that device still
  arrives. That one is a warning, says
  how many of each kind of record are waiting when it can tell (for example "2
  programs, 1 setting"), lists only those records, and is fixed by updating the
  app on this device; when records here carry other details a newer version
  of the app added, which this version keeps and shares back unchanged so they
  aren't lost when you edit the record here — that one is information only, the
  records still sync, and updating the app shows the details; when records from
  another device couldn't be used and were skipped; when another device's clock
  looks far off; when an
  update arrived while you were editing the same record, so it waits for the
  next sync; when another device is syncing but isn't taking changes from
  this one; and when this device is holding back a new kind of data because
  another device runs a version of the app that couldn't read it yet. That one
  names the device by its tag from **Other devices**, is information only —
  the data is safe here — and goes away once that device is updated or removed
  from **Other devices**, when the data starts syncing. Choose **See other devices**
  on it to open that list. Each notice lists the records it is
  about, the first few individually and the rest as a count, so you know
  which ones to look at. Dances, programs, choreographers, tags and venues are
  named by the title or name this device has for them, and one this device
  doesn't have is listed as not on this device; other kinds of record —
  settings, custom fields, difficulty levels, published sources, your own
  figures and your notes on figures — are listed by kind only. A notice about records
  from other devices also says how many devices they came from. A notice is
  only ever a message — it
  never blocks an edit, never holds up a sync, and there is nothing to dismiss.
  It stays until a sync no longer finds the condition, then goes away on its
  own. One kind is deliberately stickier: a record refused from another device
  is only mentioned once per run of the app, so its notice stays for the rest
  of that run rather than disappearing at the next sync and leaving you with
  nothing. Notices are not kept when you close the app; anything still true is
  reported again by the next sync.
- **"Needs you"** marks the notices that ask you to do something, and each
  has **Copy details** beside it. One is the newer-version notice above, which
  you fix by updating the app on this device. The other is a device that is
  syncing — it has shared its own changes at least twice since this device
  shared some — but still hasn't taken them. It names that device
  by its tag from **Other devices**, says how many changes it isn't taking,
  and has a button to open that list. Your changes are safe on this device
  either way. The usual causes are that the other device needs an app update,
  or that this device's date and time are wrong, so the other device refuses
  its changes as coming from the future. A device that simply hasn't been
  opened since doesn't raise this notice: it just shows changes waiting for it
  under **Other devices**. Like every notice, it never blocks anything and goes
  away on its own once the other device catches up.

  This notice can also point the wrong way for a while after an update. A
  device still on an older version of the app may say an *updated* device
  isn't taking some of its changes, and that the updated device may need an
  app update. This happens when the older device has set **App language**,
  **Reduce motion**, **Auto-size Perform cards** or Perform's stage theme. Those
  settings now stay on each device, so the updated device leaves them alone. To
  clear the notice, update the app on the older device.
- These settings belong to this device. They are not synced to your other
  devices, and they are not included in a backup, so restoring a backup never
  turns sync on.
- A few other settings depend on the screen they are used on, so they stay on
  each device too: **App language**, **Reduce motion**, **Auto-size Perform
  cards**, and Perform's stage theme and text size. Unlike the sync settings
  above, a backup includes them. Your theme and custom themes do sync. A
  device still on an older version of the app keeps syncing these with other
  older devices, but this device ignores what it sends. Until you update it,
  that older device may wrongly say this one isn't taking its changes; see
  **"Needs you"** above.

**Connecting.** Once Device Sync is on, choose **Connect**, then either:

- **Create a new store** — you get a phrase to read aloud or share with your
  other device. You can replace it with one of your own: four words separated
  by hyphens. If you type your own, the screen asks you to keep personal
  information out of it — no names, addresses or birthdays — because the phrase
  goes to the server with every request and gets read out or typed on each
  device you connect. If your phrase also looks easy to guess, the screen says
  so. Neither warning stops you using it.
- **Connect to an existing store** — enter the phrase shown on the device you
  already set up.

The screen tells you which you're doing; it never guesses.

The **Server** field is pre-filled with the Caller's Compendium sync server,
`https://athenaeum.callerscompendium.com/`; leave it alone unless you run your
own. If you change it, the screen warns you that whoever runs that server can
read, change, and delete everything you sync. Whichever server you end up on,
the status shows its address once you're connected. The address must start with
`https://` (plain `http://` is accepted only for `localhost` or `127.0.0.1`,
for testing a server on the same machine).

Along the way the screen explains three things worth knowing before you commit
to sharing a phrase. A second device using the same phrase can edit the same
records, and if both of you touch the same dance or program at once, one
edit silently wins — there is no merge and no warning. The phrase is where your
shared library lives rather than a password in front of it — there's nothing to
sign in to — so anyone you give it to, and anyone who simply comes by it, can
open that library: read everything you sync, change or delete any of it on
every device you've connected, and delete the whole store off the server. There
is no version of a phrase that does less. And nothing anywhere else records it:
lose it and the library stays where it is with no way back to it, and telling
someone the phrase can't be untold. Moving every device to a new phrase just
starts a second library elsewhere; the first one is still there for anyone who
kept the old phrase — see **Deleting the store** below.

Before connecting, you're offered an optional one-time backup of your library — accepting or
skipping it doesn't change what connecting does.

When connecting finishes, the app says so and tells you what actually happened
to the first sync: that it has finished, that it didn't finish and will try
again (with the reason, as on the status), or that it's waiting — for Wi-Fi if **Sync only on Wi-Fi** is on and
you're on mobile data, or for a connection if you're offline. It never claims a
sync is running while you read it. It repeats there that sync is not a backup,
and reports any duplicate dances the first connection merged.

**Disconnecting.** To stop syncing on this device without turning Device Sync
off, choose **Disconnect this device** and confirm. The device forgets its phrase
and the server it was using, and stops syncing: your library here stays as it
is, and your other devices carry on syncing with everything they have.
Disconnecting removes this device from the sync store if your other devices
already have everything from it. If they don't, it stays listed under **Other
devices** until you remove it there. That removal is one quick try made just
after the phrase is forgotten, and only on a connection that **Sync only on
Wi-Fi** would allow; it never holds up disconnecting, and if it can't be made it
isn't tried again. To reconnect — to the
same store or a different one — choose **Connect** again; you'll need the phrase,
so keep it somewhere safe, along with the server address if you changed it.
Each time this device connects, it makes up a new identifier for itself
rather than reusing the one from its last connection, so if an entry from an
earlier connection was left under **Other devices**, it stays there until you
remove it.
Disconnecting really does forget the phrase, so copy it from **Your sync phrase**
first if it isn't written down anywhere else. Turning **Device Sync** off and on again, by contrast, keeps this device
connected.

**Your other devices.** **Other devices** lists everything else connected to
this store, and lets you remove one you no longer use — a phone you've replaced,
or one that's been lost. Removing a device frees the place it was taking up
straight away; a store holds 32 devices, so a run of replaced phones can
eventually leave no room for a new one. The store also drops that device's list
of what it shared, though the shared items themselves are cleared up later, in
the server's own time, so the space they use doesn't come back immediately.
Nothing is deleted from the removed device, and nothing is deleted from yours.

Removing is for a device that's genuinely gone. It doesn't disconnect anything
and it isn't a ban: a device that's still running will publish its list again
the next time it syncs and reappear in this list, and any device can connect to
this store again with the phrase. To stop a device syncing you have to
disconnect it on that device.

Each device makes up its own random identifier, and a new one every time it
connects, so the list shows each device as a short tag from that identifier —
"Device 7c02Lm", say — never a name. This device isn't in the list, but its own
tag is shown above it ("This device: k7mQ2x"), so you can look it up in the list
on your other devices. Under each device you'll see when it last shared changes
— today, a number of days ago, or roughly how many weeks — rounded to the day,
never a time; and, if some changes from this device haven't reached it yet, how
many are waiting for it. Those lines come from this device's last sync, so a
device that sync couldn't see, or one that connected since, shows its tag only
until the next one.

A device that disconnected and connected again can appear twice: once for its
earlier connection, which no longer changes and so never shares anything new,
and once for its current one. If you can't tell which is which, it's safe to
leave them, but an extra entry isn't free. It takes one of the 32 places, and
the store keeps the items it shared until it's removed. Because it still has
everything this device had shared before it disconnected, its "waiting" line
counts only what changed since. Removing an entry you know is an old connection
avoids all of that.

**Deleting the store.** **Disconnect all devices and delete the store** removes
everything the store holds from the server, for every device at once, and it
can't be undone. Your library stays on this device and on each of your other
devices, but anything that had only ever reached another device through syncing
won't arrive here. This device disconnects and forgets its phrase; your other
devices find the store gone the next time they sync and are asked whether to
start a new one, the same question as any store that's no longer there.

If the store is deleted but this device can't disconnect from it, a message says
so: the store is gone and can't be brought back, and this device still holds its
phrase. Choose **Disconnect this device** to finish.

This is what to use if someone else has seen your sync phrase. A leaked phrase
can't be revoked, and moving your devices to a new phrase doesn't help on its
own — whoever has the old one can still read and change everything in the old
store. Deleting the store is the only thing that takes that away immediately.
It is not the answer to running out of room, though: remove a device you don't
use instead.

If a store this device used to sync with is no longer there, the app asks
before creating a replacement: it may have gone unused past its 30-day limit,
or it may have been removed — the app can't tell which. Reconnecting re-sends
your whole library, so it follows **Sync only on Wi-Fi** like everything else:
on mobile data with that setting on, nothing is sent and the app points you at
the setting, with the question still waiting once you're back on Wi-Fi. If a
reconnection doesn't go through, the question comes back and says so, and you
can try again or leave it. Declining makes no network request and leaves the choice for later. Sync then **pauses**: the
status says so and keeps saying so, and automatic syncs stop running rather
than asking again every time. Nothing is lost while it is paused. When you
want to decide, choose **Sync now** in this section — that reopens the same
question, and the paused line goes once a sync completes.

**Venues sync partially.** A venue's name, website, schedule, and notes sync
like everything else, but its address and both contact blocks stay on each
device — there's no channel for them to travel through. While Device Sync is
on, the [venue](./glossary.md#venue) editor shows a note on a venue whose
address and contact fields are blank, naming exactly those fields. (Notes
does sync — if you've put contact information there, it travels with the
note.)

#### New kinds of data wait for every device

Some things this version syncs can't be read by earlier versions of the app:
your [own figures and terms, and your notes on built-in
figures](#glossary-and-custom-figures), the Custom Figures setting, and your
shorthands for your own figures. They start syncing only once every device
connected to your store has an up-to-date app. Until then changes to them
aren't sent to your other devices, and nothing already on a device is removed;
you can keep using and editing them on each device.

While something is held back, Device Sync shows a note naming the device that
is holding it back, by its tag in **Other devices**. Update the app on that
device, or remove it from **Other devices** if you no longer use it, and they
sync on the next pass. Nothing is lost or deleted while they wait. Holding
data back never stops this device receiving what other devices send.

Because of this, the screen for connecting a device says **Every device needs
an up-to-date app**: update each device before you connect it, since one on an
earlier version may not be able to connect.

#### Choosing which version to keep

Sometimes the same item is changed on two of your devices before they've
synced — the same setting changed in the same second, say, or your dialects
edited on both a laptop and a phone. The app can't tell which change you meant
to keep, so it doesn't pick one: both versions stay as they are, and it asks
you.

It only asks when the versions differ in something you can see. When they look
exactly the same — the same choreographer added on two devices before they
synced, say — the app keeps one of them for you, the same one on every device,
and doesn't ask.

- On the **Collection**, **Programs** and **Glossary** pages, the **Sync now**
  button shows a number badge while anything is waiting for your choice. When a
  sync you started finds something new to choose, the choice opens straight
  away.
- In **Device Sync**, **Choose which version to keep** lists everything that's
  waiting.

For each item you see **This device** and **Another device**, with a short
description of each version and, when they were changed at different times,
when each was last changed. Under them, a line sums up what differs — for
example "1 only on this device · 1 only on the other device" for a list such
as your shorthands, or "Differs in: Figures, Calling notes" for a dance.

To see exactly what's different, look at the comparison. With one item it's
shown straight away; with several, choose **Show differences** on an item. The
comparison shows:

- for a list such as dialects, themes, shorthands or walkthrough snippets: what
  is only on this device, what is only on the other device, and what both have
  but differently — with the two versions side by side. For a dialect, that
  means the terms that differ in each section; for a theme, whether it's light
  or dark and each colour that differs;
- for a dance: each detail that differs, with both versions. Figures are
  compared line by line under the part of the dance they start in (A1, A2, B1,
  B2), and figures that match aren't repeated; when a figure reads the same in
  both, its note, its own walkthrough or wording, or its beats show what
  differs. Links show where they go, what kind they are and whether they join
  the related-dance group; published sources show their page and number; and
  **Origin** shows where the dance came from and its licence;
- for a program: each detail that differs, then the dances only one version
  has (a dance is matched by which dance it is, not its title, and repeats are
  counted), whether the dances they share are in a different order, and
  whether their timings, alternates or other details differ;
- for a tag, venue or choreographer: each detail that differs, such as a tag's
  colour or a venue's sponsor, schedule or price.

Nothing is selected for you. Pick the version you want for each item, then
choose **Keep selected**; with several items, **Keep all
from this device** or **Keep all from the other device** fills in every choice
at once, and you still confirm. **Decide later** closes the list and changes
nothing.

The version you keep becomes the newest edit, so your other devices take it
the next time they sync and stop asking — with one exception for the sets
described next. If you choose on two devices before
either has synced, the later choice wins — unless you made different choices
in the same second, in which case you're asked again.

Your dialects, custom themes, figure shorthands and walkthrough snippets are
each one whole set. Your shorthands for combinations are one more, with its own
limit. If both devices changed one, you can keep either device's set, or choose
**Combine both** to keep everything from both. If both devices have the same
item — the same dialect, say — but changed it differently, the app asks you
which version of that item to keep before it saves. **Combine both** isn't
offered when the combined list would be longer than the app keeps (128
dialects, 500 in any one shorthand set, or 2,000 snippets); it says so instead.

Once you choose for one of these sets, the device where you chose stops asking
about it, even if the other device hasn't synced yet. The other device, if it
also changed that set, asks you once more the next time it syncs, because it
can't tell your choice apart from an ordinary change. That doesn't happen if you
kept that device's set. When it asks:

- keep the version you chose on the first device, and neither device asks
  again;
- keep that device's own set, and it saves that set as a new version, which
  your first device hasn't chosen against, so the first device asks you again.

**Changing your mind.** After you save your choices, a message offers **Undo**
for a few seconds. It reopens the items you just decided with the versions you
chose between, and nothing changes until you choose again and save — closing it
leaves your earlier choice in place. If something newer has arrived from
another device in the meantime, Undo tells you so and leaves things as they
are.

#### Sync decisions

- **Sync decisions**, under **Device Sync** while a store is connected — review
  conflicts that Device Sync couldn't settle on its own, and choose how each one is resolved. Three kinds of
  conflict offer a decision:
  - **A device deleted something another device still has.** One of your
    devices deleted a choreographer, tag, custom field, or difficulty level
    that this device had already created on its own under the same name,
    before either device had seen the other's copy. **Merge** accepts the
    deletion, so this device's copy goes too. **Keep both** gives this
    device's record a new, distinct name so it survives alongside the
    deletion. Dances never enter this decision; they use the dance one below.
  - **Another device renamed a record onto a name this device already uses.**
    Both records already exist here — they may well be two different people or
    two different tags — so nothing is merged behind your back. **Merge** keeps
    one record and points everything that referred to the other at it.
    **Keep both** asks you for a new name for the record that currently holds
    the name, and then applies the other device's rename. Until you choose, the
    other device's change is not applied.

    Merging two choreographers is the one case that loses something: an email
    address, location, and deceased marker are kept only on your own device and
    are never sent to your other devices, so the ones on the record that is not
    kept cannot be recovered. The app asks you to confirm before this happens.
  - **Two devices independently created dances with the same title but
    different choreography.** This turns up when a device first connects to a
    store that already has dances in it. **Merge** combines the two dances into
    one. **Keep both** renames one of the dances so both are kept separately.
  Any other kind of conflict is listed and kept as it is, with no action to
  choose. When the same item was simply changed differently on two devices,
  you choose between the versions instead — see
  [Choosing which version to keep](#choosing-which-version-to-keep).

### Developer Options

This section is closed until you open it. Today it holds one action.

**Reset database** deletes everything on this device and restarts the app as if
it had just been installed: every dance, program, collection, note and setting
is gone. It cannot be undone. Take a [backup](#backup--restore) first if you
want to keep anything.

Choosing it opens a confirmation. **Reset database** in the dialog stays
disabled until you tick the box saying you understand this can't be undone and
that you've already taken a backup if you wanted one.

If this device is [connected to a Device Sync store](#device-sync), it first
removes itself from the store, so it isn't left behind as a device that never
comes back. This removal is not the careful one **Disconnect this device** does,
which only goes ahead when your other devices already have everything: anything
this device had not yet synced is lost. If the store can't be reached (for
example, you're offline), nothing is reset and the device stays connected;
connect and try again. If the store is gone for good, choose **Disconnect this
device** first, then reset. If the removal succeeds but the wipe itself then
fails, your data is unchanged but the device has already left the store. Your other devices and the store itself are not touched.

## About

The **About** section tells you what you're running and where it comes from.

- App name, **Version**, and the app's tagline.
- A **User guide** link that opens the built-in offline guides — the same pages
  you're reading now. The guide is written in English only; when the app is set
  to another language, each guide page starts with a one-line notice saying so.
- License info: the app is free software under **AGPL-3.0**, with **View source on
  GitHub**.
- Bundled-font credits — Fraunces, Atkinson Hyperlegible, and Roboto, under the
  SIL Open Font License.
- Theme-palette and dance-data attributions, including The Caller's Box
  (CC BY-NC).
- **View licenses** — the full license texts, including the bundled fonts,
  `fmptools` (MIT), the project the Caller's Companion importer is ported from,
  the EFF long wordlist (CC BY 3.0 US) that generated sync IDs are drawn from,
  ContraDB (AGPL-3.0), whose figure wording the dance-text renderer follows, and,
  on Linux and Windows, PDFium (BSD-3-Clause, with the notices of the libraries
  built into it), which the app uses there to print and preview PDFs.

## Where to go next

- [Dialect](./dialects.md) — customize the role names and wording your dances use.
- [Backup & portability](./backup-portability.md) — export, restore, and set
  backup reminders.
- [Imports & migration](./imports.md) — bring dances in from other sources.
- [Accessibility](./accessibility.md) — reduce motion, verbose figure text,
  high-contrast themes, and more.
- [Write & edit dances](./authoring.md) — authoring defaults, shorthands, and
  walkthrough snippets in context.
- [Collection & search](./collection.md) — custom fields and restoring deleted
  dances.
