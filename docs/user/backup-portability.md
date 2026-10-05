# Backup & portability

Caller's Compendium keeps everything on your own device — there's no
cloud account, and nothing leaves your device unless you send it. That's
good for privacy and for working offline at a hall with spotty signal, but
it also means you keep your own safety copy. A backup is a single file that
holds your whole library, ready to bring back if a device is lost,
replaced, or wiped.

> **Finding your way around these words.** On-screen buttons and screens
> are written in **bold** — like **Settings**, **Export**, and
> **Restore**. The first time a dance term appears it links to the
> [Glossary](./glossary.md), so you can get a plain-language
> definition without losing your place.

## Why back up

Because your work lives on your device, a backup is your insurance. One
exported file captures your entire [collection](./glossary.md#collection) of
[dances](./glossary.md#dance), your [programs](./glossary.md#program),
and all your personal settings. Keep a recent copy somewhere safe — a
cloud drive, a USB stick, or your email — and you can recover from
almost anything.

A few good moments to export a backup:

- Before a big cleanup or reorganizing your collection.
- After an evening of building or editing programs for upcoming gigs.
- Whenever you're about to switch to a new phone, tablet, or computer.

## Export a backup

1. Open **Settings**, then choose **General**.
2. Find the **Backup & restore** section.
3. Choose **Export** beside **Export a backup**.

While the backup is prepared, a progress bar shows that the app is
working. It disappears when the share or save sheet is ready.

The app creates a single dated file — something like
`callers-compendium-backup-2026-07-15.json` — and hands it to your
device's normal share or save sheet. From there you decide where it
goes: a cloud drive, your Files area, an email to yourself, or a folder
of your choosing. When it's done, you'll see a **Backup exported.**
confirmation.

### An integrity check, not a lock

A backup is plain, readable text — open it in any text editor and you'll
see your library. It is **not** encrypted or password-protected, so treat
the file the way you'd treat any personal document and store it somewhere
you trust.

Every backup carries a built-in **integrity checksum**. It isn't a lock: it
doesn't hide anything, and it can't stop someone who deliberately edits the
file (they could recalculate it). What it does is let the app notice if the
file was accidentally corrupted or changed after you exported it. If a
restore detects a mismatch, it stops before touching your data (see
[Restore from a backup](#restore-from-a-backup) below) instead of importing
something damaged.

### What's inside a backup

A backup holds **everything** you've built, including:

- Your whole collection of dances — figures, notes, tunes, links, and
  any [custom field](./glossary.md#custom-field) values you've filled in,
  including fields marked **Include in sharing** off, along with where each
  dance was imported from.
- All your programs, with their [slots](./glossary.md#slot),
  [alternates](./glossary.md#alt), event details, and which dances
  you've marked as performed.
- Your custom fields, tags, choreographers, difficulty levels, and saved
  [venues](./glossary.md#venue). A sharing opt-out keeps a custom field out of
  files you send to other people; it does not remove the field from your own
  backup.
- Your custom [dialects](./dialects.md) and which one is active.
- Your custom themes and which one is active.
- Your settings and preferences, including your figure shorthands and
  walkthrough snippets.

A few device-specific things are left out on purpose, so a restored device
doesn't inherit the old one's quirks: window size and position, any
half-finished edits you hadn't saved yet, your last-backup date, and everything about
[Device Sync](./settings.md#device-sync) — so restoring a backup never turns
sync on or connects a device to a store. All your real content comes
along, and so does your reminder cadence (off / weekly / monthly) — but the
last-backup date does not travel, so restoring leaves this device's own
last-backup date as it was.

## Restore from a backup

Restoring loads a backup file back into the app. Use it when you're
setting up a new device or recovering after a problem.

1. Open **Settings**, then choose **General**.
2. Find the **Backup & restore** section.
3. Choose **Restore** beside **Restore from a backup**.
4. Either choose **Choose file…** (a picker that shows `.json` backups)
   or paste the backup text into **Or paste backup JSON**. A chosen file is
   shown as a short summary (its date, how many dances and programs it
   holds, and its size) rather than as text in the box; the box is for
   pasted text only. Choose **Clear** to forget the file.
5. Confirm with **Replace all data**. A progress bar counts the restore
   from start to finish; it can't be dismissed, so wait for it to close.

On success, you'll see a **Backup restored.** confirmation. If any
dance, program or other core item in the file can't be read, the restore
stops *before* anything changes and tells you; only optional extras (custom
dialects and themes) can be skipped, and the app tells you how many. If the file is invalid or
corrupt, comes from a newer version of the app that this one can't
read, or has no app-settings section (an older, hand-edited or incomplete
file that couldn't say what your settings, themes and dialects should
become), the restore stops *before* any of your current data is touched —
so you never lose what you already have by trying.

> **If your settings don't come back, your dances still did.** Occasionally a
> restore succeeds for your content but fails while re-applying your saved
> settings. The app says so plainly — *your dances and programs were restored,
> but applying your saved settings failed* — and offers **Retry settings**.
> Choose it and the app tries again, confirming with **Settings applied.** Your
> restored content is safe either way.

> **A failed integrity check never harms your data.** If a backup was
> corrupted or altered after it was exported, its integrity check won't
> match, so the app tells you it can't safely restore the file and stops.
> Nothing is imported and your current library is left exactly as it was.
> Export a fresh backup and restore from that instead.

> **Have an older `.ccbackup` file?** Some early versions offered an
> optional passphrase-encrypted backup saved as `.ccbackup`. That option
> has been retired, and the app can no longer open those files. If you
> still have data only in a `.ccbackup`, restore it with the older version
> first, then export a fresh `.json` backup.

> **Restoring replaces everything.** A restore swaps out *all* of your
> current dances, programs, settings, and customizations for the
> contents of the backup file, and it **cannot be undone**. The app
> shows a confirmation dialog to make sure this is what you want. If
> there's anything on your device you haven't backed up yet, export a
> fresh backup first.

Because restore replaces rather than combines, it is **not** the way to
merge two libraries together. If you want to add dances from another
source *alongside* what you already have, use the
[import](./imports.md) feature instead — imports add, restore replaces.

## Move to a new device

Moving your whole library to a new phone, tablet, or computer is a clean
round trip — what you save is what you get back:

1. On your **old** device, export a backup (see above).
2. Transfer the file to the new device — through a cloud drive, a USB
   stick, or email to yourself.
3. On your **new** device, restore from that backup.

Your collection, programs, dialects, themes, and settings all arrive
intact.

## Backup reminders

If you'd like a nudge to stay current, the **Backup & restore** section
includes a **Backup reminder** setting. You can choose:

- **Off** (the default)
- **Weekly**
- **Monthly**

The setting also shows **Last backup: never** or the date of your most
recent backup, so you always know where you stand. When a backup is
overdue, a note under the setting suggests exporting one now. The app also
shows a reminder bar on the main screen, once each time you open the app,
with **Export backup** and **Not now** buttons. **Not now** hides it until
the next time you open the app.

## Backups happen automatically too

Before an app update changes how your data is stored, the app saves its
own recovery snapshot on your device. There's nothing to press and
nothing to manage — it's an extra safety net across updates.

This snapshot is a bonus, not a replacement. Your own exported backups are
the copies you can move between devices and store wherever you like.

## Backups vs. sharing vs. importing

Three related features are easy to mix up:

- **Backup & restore** (this guide) works with your *entire* library at
  once — one file in, one file out.
- **Sharing a single dance or program** as text or PDF happens from that
  dance or program, not here. See
  [Collection & search](./collection.md) for sharing dances and
  [Programs & matrix](./programs.md) for sharing programs.
- **Importing** brings dances in from other apps and sources — such as
  The Caller's Box, ContraDB, or another Caller's Compendium file — and
  *merges* them alongside what you already have. See
  [Imports & migration](./imports.md). Remember: imports add, restore
  replaces.

## Where to go next

- [Getting started](./getting-started.md) — the basics of finding your
  way around the app.
- [Collection & search](./collection.md) — build, edit, and share
  individual dances.
- [Programs & matrix](./programs.md) — plan a night's dances and share a
  program.
- [Imports & migration](./imports.md) — merge in dances from other apps
  and sources.
- [FAQ & troubleshooting](./faq.md) — quick
  answers to common questions.
