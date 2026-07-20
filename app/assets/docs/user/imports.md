# Imports & migration

This guide is about getting dances *into* [Caller's Compendium](./glossary.md#callers-compendium)
and moving your whole library between devices. It covers bringing in single
dances from [The Caller's Box](./glossary.md#the-callers-box) and
[ContraDB](./glossary.md#contradb), importing a Caller's Compendium file, moving
a whole library across from Caller's Companion, and backing up and restoring
everything you own. Where a feature is still on the way, it says so plainly.

## Your data stays yours

Caller's Compendium is **local-first**. Your [collection](./glossary.md#collection)
lives on your own device, the app works fully offline, there is no account to
create, and nothing you do is sent anywhere for tracking. Importing and
exporting are the doors your dances walk through — the ways you bring
material in from the wider community and carry your own library from one machine
to the next. Nothing leaves your device unless you ask for it (an online search
or a single dance import reaches out once, when you tell it to), and nothing
changes your collection until you say so.

## Nothing gets lost when a dance comes in

Every import follows one promise: **bringing a dance in never loses the dance.**

When the app reads a dance from another source, it recognises the
[figures](./glossary.md#figure) it can and turns them into structured moves you
can search and rework. Anything it does not recognise — an unusual phrasing, a
complicated sequence, a note the choreographer tucked into a line — is kept
word-for-word as a plain-text figure instead of being dropped. A dance can
arrive entirely as plain text and still land safely in your collection, still be
searchable, and still be yours to tidy up later. You are never left wondering
what the app quietly threw away, because it throws nothing away.

## Bring in single dances from an online archive

Caller's Compendium can reach two community archives —
[The Caller's Box](./glossary.md#the-callers-box) and
[ContraDB](./glossary.md#contradb) — two ways: a live **online search**, and
importing a single dance **by its link or ID number**. Both need an internet
connection, and both bring in **one dance at a time** so you can look before you
keep.

### Search an archive online and import a dance

1. Open **Collection**.
2. Open the **Advanced** panel above the dance list and turn on the
   **Online search** switch. (Your local filters do not apply while online
   search is on — you are searching the archive, not your own library.)
3. Choose which archive to search — **The Caller's Box** or **ContraDB** — from
   the online source selector.
4. Type a dance **title** in the search box. Results appear as you type. With
   The Caller's Box you can also narrow by the figures a dance contains, using
   the same **By-Phrase** panel as a local search; ContraDB search is by title
   only.
5. Select a result to open a **preview** of that dance.
6. If it is the one you want, choose **Import** to add it to your collection.

If the dance is already in your collection from an earlier import, the app tells
you so and does not add a second copy — see
[Avoiding duplicates](#avoiding-duplicates) below.

> _Screenshot (added once packaged builds are available): the Collection screen
> with the Online search switch turned on, an archive selector, and three
> results listed below a search for a dance title._

### Import a dance by link or ID

If you already have a dance's web address — or even its number — you can import
it directly:

1. Open **Settings**, go to the **Import** section, and choose **Import…**.
2. In the source selector, choose **The Caller's Box** or **ContraDB**.
3. Paste the dance's **web address** — for The Caller's Box a `dance.php?id=…`
   link, for ContraDB a `…/dances/N` link — or enter its **ID number** (for
   example `1`) in the address field, then choose **Fetch**. Paste a recognised
   address and the app selects the matching source for you.
4. Review the dance and commit it, as described in
   [Review before anything changes](#review-before-anything-changes).

A few honest notes about these online imports:

- They bring in **one dance at a time** and need an internet connection.
- The app reads each archive's public dance page, so it depends on how that page
  is laid out; if a page changes or a dance has no figures listed, the dance
  still comes in with whatever the app could read (its title, formation, and
  notes), following the *nothing gets lost* promise above.
- Figures come in as recognised moves where the app can read them and as
  plain-text figures otherwise, the same as every other import.

## Import a Caller's Compendium file

Dances shared as a **Caller's Compendium** file (the app's own `.json` format)
come in through the same review flow:

1. Open **Settings**, go to the **Import** section, and choose **Import…**.
2. Leave the source set to **a Caller's Compendium JSON file** (the default).
3. Choose the file with **Choose file…**, paste its contents, or enter a URL and
   choose **Fetch**.
4. Review and commit.

This is the format the app uses for sharing between callers and for the whole
library backup described next. Importing a file **adds to** your collection
through the review queue; it does not replace what you already have. To move an
entire library and replace what is on a device, use **Restore** instead — see
below.

### Open a shared program someone sent you

If another caller shares a **program bundle** with you — the
**Share (program + dances)** file described in
[Programs & matrix](./programs.md#print-export-and-email-a-program) — you don't
have to go through **Settings › Import** by hand. Caller's Compendium registers
itself as a place that can open those files, so you can just **open the file**:
AirDrop it (on a Mac, iPhone, or iPad), use your system's **Open with** /
**Share** menu, or tap it wherever it arrives. The app launches, imports the
program and every dance it references, and **opens the program for you**
automatically.

This intake is deliberately safe: the file is treated as untrusted input (it's
size-checked and validated against the expected format, and a bad file is turned
away with a message rather than doing any harm), and it's **identity-first** —
dances and programs you already have are matched and updated, never duplicated.
Because it opens straight into the program, this path doesn't stop at the
step-by-step review queue the way a manual import does. Nothing is ever deleted:
dances and programs you already have are updated in place rather than
duplicated, brand-new material is added, and if anything couldn't be matched the
app tells you.

## Bring your library across from Caller's Companion

Moving from **Caller's Companion**? Caller's Compendium can read its exported
`.USR` library file and bring your material across in one pass:

1. Open **Settings**, go to the **Import** section, and choose **Import…**.
2. In the source selector, choose **a Caller's Companion .USR file**.
3. Choose your `.USR` file when the app asks for it.
4. Review and commit, as described in
   [Review before anything changes](#review-before-anything-changes).

A `.USR` import brings across both your **dances** and your **program history**
(Caller's Companion "sets"), and — like every other import — it is reviewable
before it commits and undoable right after. Dances and programs you have imported
before are recognised and offered as updates rather than duplicated.

A few things do not come across yet: saved **venues**, custom **glossary terms**,
and **related-dance links** stay behind for now. Your dances, their figures and
notes, and your programs are the parts that migrate today.

## Move your whole library: backup and restore

A single Caller's Compendium file can hold **everything** — your dances,
[programs](./glossary.md#program), custom fields,
[dialects](./glossary.md#dialect), themes, and settings. This is how you keep a
safety copy and how you move your whole library from an old machine to a new
one. Because a backup you export can be restored (or imported) again exactly,
moving between devices is a clean round trip: what you save is what you get back.

For step-by-step backup and restore, see
[Backup & portability](./backup-portability.md). In short:

- **Export a backup** — open **Settings › General**, find **Export a backup**,
  and choose **Export**. The app writes one `.json` file containing your entire
  collection, programs, custom fields, dialects, themes, and settings. Keep it
  somewhere safe or copy it to another device.
- **Restore from a backup** — in the same section, choose **Restore** and pick a
  backup file. Restoring **replaces everything** currently in the app with the
  contents of the backup, so use it when you are setting up a device or
  recovering, not to merge two libraries. This cannot be undone, so the app asks
  you to confirm first.
- **Backup reminder** — set a reminder cadence of **Off**, **Weekly**, or
  **Monthly**, and see when you last backed up, so a safety copy never drifts too
  far out of date.

## Review before anything changes

Importing from a file or a URL opens the **import review** screen, and nothing
touches your collection until you commit there. It works the same whichever
source you pick:

1. **Choose a source and give it something to read** — pick the source, then add
   a file, paste text, or enter a URL or ID. (Paste a recognised web address and
   the app selects the matching source for you.)
2. **See the plan** — the app reads the material without changing anything and
   lists every dance it found, with a sense of how much of each dance it could
   turn into structured figures versus keep as plain text, plus any notes about
   a particular dance.
3. **Decide dance by dance** — each dance can be brought in as **new**, updated
   as a **re-import** of one you imported before, **linked** to an existing
   dance, kept as a separate **duplicate**, or **skipped**. Anything the app is
   unsure about defaults to **skip**, so it never guesses its way into your
   library.
4. **Commit** — only now are the dances you accepted written to your collection.
5. **Undo** — right after committing, the summary offers **Undo**, which removes
   everything that import added. This is the review-and-undo queue for
   bringing in more than one dance at a time.

> _Screenshot (added once packaged builds are available): the import review
> screen showing a source selector, a URL field, and a list of found dances each
> with an action set to New, and an Undo button on the summary._

## Avoiding duplicates

Re-importing the same dances should not clutter your collection, so the app
watches for matches:

- **Same dance, same source.** If you import a dance you have imported before
  from the same source, the app recognises it and offers to **update** the one
  you already have rather than adding a copy. (This is how the Caller's Box
  online import can tell you a dance *"is already in your collection."*)
- **Looks like something you already have.** If a dance closely matches one
  already in your collection by title and author but did not come from the same
  source, the app marks it as **unsure** and asks you to choose: **link** the two,
  keep both as a **duplicate**, or **skip** the new one. It never merges dances
  on its own.

## Importing whole programs

Everything above brings in **dances**. You can also import a **whole program**
— a night's set list — in one go, and Caller's Compendium matches each dance to
your collection (or imports it for you) as it reads the list:

- **From a plain-text list of dance titles** you already have written down, and
- **From a ContraDB event**, by pasting its link or searching for it by name.

Both live in the **Import program** menu on the **Programs** screen rather than
the **Import…** flow here, because they build a program, not just add dances. For
step-by-step instructions, see
[Programs & matrix › Import a program from ContraDB](./programs.md#import-a-program-from-contradb)
and [Build from a list of titles](./programs.md#build-from-a-list-of-titles).

## Where to go next

- New to the app? Start with [Getting started](./getting-started.md).
- Keeping your library safe and moving it between devices:
  [Backup & portability](./backup-portability.md).
- Want imported dances to read in your own words and role names? See
  [Dialect](./dialects.md).
- Unsure about a term used here? The [Glossary](./glossary.md) has plain
  definitions.
