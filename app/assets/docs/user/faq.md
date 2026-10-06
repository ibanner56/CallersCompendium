# FAQ & troubleshooting

Quick answers to the questions that come up most, and fixes for the snags people
hit along the way. If your question isn't here, the guide it belongs to probably
has more — this page links out to each one.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Settings**, **General**, and **Collection**. The
> first time a dance term appears it links to the [Glossary](./glossary.md), so
> you can get a plain-language definition without losing your place.

## The basics

### Do I need an account or an internet connection?

No account, and no connection for everyday use. Caller's Compendium is
*local-first*: your [collection](./glossary.md#collection),
[programs](./glossary.md#program), and settings live on your own device, and the
app works fully offline. It reaches the internet only when you ask it to — to
[import](./glossary.md#import) dances from an online source such as
[The Caller's Box](./glossary.md#the-callers-box) or
[ContraDB](./glossary.md#contradb), to check for updates, or to sync if you have
turned on Device Sync.

### Where is my data stored?

On your device, in a single database file named `compendium.sqlite`:

- **Windows:** `%LOCALAPPDATA%\org.callerscompendium\Caller's Compendium` (type
  that into the File Explorer address bar). It is deliberately not in
  `Documents`, so OneDrive's folder backup does not sync a live database.
- **Linux:** `$XDG_DATA_HOME/org.callerscompendium.compendiumApp/` (by default
  `~/.local/share/org.callerscompendium.compendiumApp/`).
- **Android, iOS and macOS:** the app's own documents folder (on macOS, inside
  the app's sandbox container).

Earlier versions kept the file in your `Documents` folder on Windows and Linux
(on Linux without a Documents folder configured, that is your home folder). A
few Windows installs instead have it in the Roaming folder,
`%APPDATA%\org.callerscompendium\Caller's Compendium`. The first time you open
the app after updating, it moves your library (and the automatic safety copies
in its `db_backups` folder) to the location above and deletes the old copy only
after the new one is verified.

After the move, the app leaves a *folder* named `compendium.sqlite` where the
old file was, with a `README.txt` inside that says where your library went. An
older version (0.5.4 or earlier on Windows, 0.5.3 or earlier on Linux) does not
look in the new location and cannot open that folder as a library, so going back
to one stops on its startup error screen instead of opening. Your data is not
lost: it is still in the location above. Keep the folder while you might open an
older version. If you delete it, an older version starts a new, empty library in
`Documents`, and when you update again the app reports data in both places; move
the copy in `Documents` out of the way, as described below.

If the app finds data files in the new location *and* in an old one, or in more than
one old location (for example both `Documents` and the Roaming folder), or it
cannot finish the move (the disk is full, the folder is not writable, or another
program is using the file), it stops without changing anything and tells you.
When there is more than one copy, the screen lists each one's size and when it
last changed; the larger, more recently changed copy is usually your library.
Keep the copy you want, move the others out of the way, and reopen the app.

If there is no library in the new location yet and your `Documents` folder
can't be found (for example it is on a network folder or a drive letter that
isn't connected), the app also stops without creating anything, rather than
starting an empty library while yours may still be in `Documents`. Reconnect it
and reopen the app; if you have no `Documents` folder at all, create an empty
one. The app can only tell that the folder is missing: if `Documents` lives on
a drive that is mounted into an empty folder (common on Linux), make sure that
drive is connected before the first launch after updating.

Safety copies the app makes before updating the database go in a `db_backups`
folder beside it.

Nothing is uploaded anywhere unless you choose to turn on
[Device Sync](./settings.md#device-sync) — an optional, experimental feature that
keeps your library in step across your own devices. It is off until you turn it
on. Because your library lives with you, *you* keep the safety copy; see
[Backup & portability](./backup-portability.md) for how.

### What does it cost? Is it really open source?

It's free and open source, licensed under **AGPL-3.0**. You'll find the version,
license, and a link to the source under **Settings › About**.

### Which devices does it run on?

Desktop (Linux, macOS, Windows) and mobile (Android, iOS/iPadOS). Desktop and
Android builds are on the [Releases page](https://github.com/ibanner56/CallersCompendium/releases),
and Android is also available through a Google Play closed test. iPhone and iPad
builds are delivered through TestFlight, and it's an open beta — join straight
from the [public TestFlight link](https://testflight.apple.com/join/REgW311w),
no invitation needed. See the
[Installation guide](./installation.md) for step-by-step instructions.

## Everyday tasks

### How do I move everything to a new phone or computer?

Export a backup on the old device, move the file across, and restore it on the
new one. It's a clean round trip — see
[Backup & portability](./backup-portability.md).

### How do I change the role names (Larks/Robins, Leads/Follows, and so on)?

That's what a [dialect](./glossary.md#dialect) is for. Pick or build one under
**Settings › Dialect**, and the app shows your words everywhere. See
[Dialect](./dialects.md).

### How do I make the text bigger for calling on stage?

[Perform mode](./glossary.md#perform-mode) sizes text to be read at arm's length.
Leave **Auto-size** on to fit each card to the screen, or use **A−** / **A+** to
set the size yourself — which switches auto-size off and remembers your size for
next time. See [Perform mode](./perform.md#set-the-stage), and
[Accessibility](./accessibility.md) for more ways to adjust text, contrast, and
input.

### How do I share a single dance or a program?

Open the dance or program and use its share/export options — you can share as
text or export a PDF. A program also offers **Share (program + dances)**, which
bundles the set list together with every dance it uses into one file — dances and
all, not just a list of titles. The recipient can **open that file directly**
(AirDrop, "Open with", or a share intent), which takes them to the import review
screen already loaded with it, or they can import it from **Settings › General** by
choosing **Import…**.
Either way nothing lands in their collection until they confirm. This is separate
from a full backup. See [Share, print & export](./sharing.md).

### Where can I read these guides on my phone at the gig?

They're already in the app. **Guide** is one of the four destinations in the
navigation, alongside **Collection**, **Programs**, and **Settings**, and it holds
this whole set of guides — bundled in, so it works with no signal in a church
hall. Links between guides work there just as they do here, and you can select
text to copy. Images and the search box are the two things it doesn't have, so
head for the guide list to find your way around.

### How do I get updates?

The app can check for a newer version itself. Open **Settings › Updates** and
choose **Check for updates** any time; on desktop it can download and install the
update for you, and on phones and tablets it links you to the download. The app
only checks on its own if you turn on **Check automatically**. While the app is
in beta, every release is a beta release, so turn on the **Beta channel** switch
too — otherwise the check won't find them. See
[Settings](./settings.md#updates).

## Troubleshooting

### The app shows "Could not prepare the collection."

The app couldn't open or get your collection ready at startup. Try, in order:

1. **Fix the likely cause, then choose Retry.** Retry reopens the database from
   scratch, so it works without relaunching the app once the cause is gone —
   for example, free some disk space, or make sure the folder holding the
   database (see [Where is my data stored?](#where-is-my-data-stored)) exists and
   is writable.
2. **Use Copy details** to copy the error type and its stack trace (the error's message is left out)
   if you want to report the problem. The stack trace can still contain file
   paths, so look it over before you share it.
3. **Look at the diagnostics log.** The app also writes the failure to a
   `diagnostics/crash.log` file in its support folder, which is available even
   when the database can't be opened. On Linux that is
   `~/.local/share/org.callerscompendium.compendiumApp/diagnostics/crash.log`.

On Linux the database lives in the app's support folder whether or not your
machine has a `Documents` folder (for example, one without `xdg-user-dirs`); see
[Where is my data stored?](#where-is-my-data-stored).

### Why can't I find a dance I imported?

A few things to check:

- **Clear your filters and search.** An active filter or leftover search text in
  [Collection & search](./collection.md) can hide dances that are really there.
  Reset them and look again.
- **Check the wording.** Your active [dialect](./glossary.md#dialect) changes how
  role names and [figures](./glossary.md#figure) read, so a dance may not look
  exactly like the words you searched for.
- **Confirm the import finished.** Imports *add* dances to your collection; if you
  didn't confirm the review step, nothing was added. Run it again from
  **Settings › General › Import dances** — see [Imports & migration](./imports.md).
- **Sort by recently added.** Change the [collection](./glossary.md#collection)
  sort order to bring your newest dances to the top.

### I deleted a dance by accident — can I get it back?

Usually, yes. Deleted dances are kept for a while before they're removed
— by default **30 days** (adjustable under **Settings › General › Keep deleted
dances for**). You can restore them within that window; see
[Collection & search](./collection.md). To avoid slips in the first place, turn on
**Confirm before delete** under **Settings › General**.

If a dance had already been shared to your other devices, a small record of the
deletion is kept after that window instead of being removed outright. It holds
no dance content, and it is what tells your other devices the dance was deleted
here rather than never received — without it, they would send it back.

### An imported dance reads differently than I expected.

That's almost always your [dialect](./glossary.md#dialect) at work — it rewords
role names and phrasing to match your style. You can switch how a dance reads
while it's open, or change your active dialect under **Settings › Dialect**. See
[Dialect](./dialects.md).

### On-screen movement is distracting or uncomfortable.

Turn on **Reduce motion** under **Settings › General** to dampen non-essential
animation. More comfort options are covered in [Accessibility](./accessibility.md).

### I want to start over, or something looks wrong after an update.

Your data is safe across updates, and the app keeps its own recovery snapshot
before major internal changes. If you need to reset a device deliberately,
restoring a known-good backup replaces everything with that copy — see
[Backup & portability](./backup-portability.md). (Restoring can't be undone, so
export a fresh backup first if there's anything you haven't saved.)

## Where to go next

- [Getting started](./getting-started.md) — the first-time tour.
- [Backup & portability](./backup-portability.md) — safety copies and moving
  devices.
- [Settings](./settings.md) — every option, section by section.
- [Accessibility](./accessibility.md) — text size, contrast, screen readers, and
  keyboard use.
- [Glossary](./glossary.md) — plain definitions of the terms used here.
