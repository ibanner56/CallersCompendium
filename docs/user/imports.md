# Imports & migration

This guide is about getting dances *into* [Caller's Compendium](./README.md#glossary)
and moving your whole library between devices. It covers bringing in single
dances from [The Caller's Box](./README.md#glossary) and
[ContraDB](./README.md#glossary), importing a Caller's Compendium file, and
backing up and restoring everything you own. Where a feature is still on the way,
it says so plainly.

## Your data stays yours

Caller's Compendium is **local-first**. Your [collection](./README.md#glossary)
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
[figures](./README.md#glossary) it can and turns them into structured moves you
can search and rework. Anything it does not recognise — an unusual phrasing, a
complicated sequence, a note the choreographer tucked into a line — is kept
word-for-word as a plain-text figure instead of being dropped. A dance can
arrive entirely as plain text and still land safely in your collection, still be
searchable, and still be yours to tidy up later. You are never left wondering
what the app quietly threw away, because it throws nothing away.

## Bring in dances from The Caller's Box

The Caller's Box is a large community archive of contra dances. Caller's
Compendium can reach it two ways: a live **online search**, and importing a
single dance **by its link or ID number**. Both need an internet connection, and
both bring in **one dance at a time** so you can look before you keep.

### Search The Caller's Box and import a dance

1. Open **Collection**.
2. Open the **Advanced** panel above the dance list and turn on the
   **Online search** switch. (Your local filters do not apply while online
   search is on — you are searching the archive, not your own library.)
3. Type a dance **title** in the search box. Results from The Caller's Box
   appear as you type.
4. Select a result to open a **preview** of that dance.
5. If it is the one you want, choose **Import** to add it to your collection.

If the dance is already in your collection from an earlier import, the app tells
you so and does not add a second copy — see
[Avoiding duplicates](#avoiding-duplicates) below.

> _Screenshot (added once packaged builds are available): the Collection screen
> with the Online search switch turned on and three Caller's Box results listed
> below a search for a dance title._

### Import a Caller's Box dance by link or ID

If you already have a dance's web address — or even its number — you can import
it directly:

1. Open **Settings**, go to the **Import** section, and choose **Import…**.
2. In the source selector, choose **The Caller's Box**.
3. Paste the dance's **web address** — its URL, for example a `dance.php?id=…`
   link — or enter its **ID number** (for example `1`) in the address field,
   then choose **Fetch**.
4. Review the dance and commit it, as described in
   [Review before anything changes](#review-before-anything-changes).

## Bring in a dance from ContraDB

ContraDB is another online contra-dance database, and Caller's Compendium can
import a single dance from it **by link or ID**:

1. Open **Settings**, go to the **Import** section, and choose **Import…**.
2. In the source selector, choose **ContraDB**.
3. Paste a ContraDB dance's **web address** (a `…/dances/N` URL) or enter its
   **ID number**, then choose **Fetch**.
4. Review and commit the dance.

A few honest notes about ContraDB imports:

- They bring in **one dance at a time** and need an internet connection.
- The app reads the public dance page, so it depends on how that page is laid
  out; if the page changes or a dance has no figures listed, the dance still
  comes in with whatever the app could read (its title, formation, and notes),
  following the *nothing gets lost* promise above.
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

## Move your whole library: backup and restore

A single Caller's Compendium file can hold **everything** — your dances,
[programs](./README.md#glossary), custom fields,
[dialects](./README.md#glossary), themes, and settings. This is how you keep a
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

## Coming soon

These migration paths are planned but **not available yet**. When they land,
this guide will gain step-by-step instructions for each.

- **Caller's Companion migration.** Bringing your dances and sets across from
  Caller's Companion — both from its exported `.USR` file and from its
  "copy formatted dance" text — is in progress and not yet something you can do
  from the app.
- **Community collection download.** A one-step "bootstrap" that downloads a
  large, cleaned-up snapshot of the Caller's Box archive so you can start with a
  full library instead of importing dances one at a time. This is planned and not
  yet available; for now, use the Caller's Box **online search** and
  **by-link** imports above.

## Where to go next

- New to the app? Start with [Getting started](./getting-started.md).
- Keeping your library safe and moving it between devices:
  [Backup & portability](./backup-portability.md).
- Want imported dances to read in your own words and role names? See
  [Dialect](./dialects.md).
- Unsure about a term used here? The [Glossary](./README.md#glossary) has plain
  definitions.
