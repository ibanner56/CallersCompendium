# Backup & portability

Caller's Compendium keeps everything on your own device — there's no
cloud account and nothing gets synced somewhere else without you asking.
That's great for privacy and for working offline at a hall with spotty
signal, but it also means you are the keeper of your own safety copy. A
backup is a single file that holds your whole library, ready to bring
back if a device is lost, replaced, or wiped.

> **Finding your way around these words.** On-screen buttons and screens
> are written in **bold** — like **Settings**, **Export**, and
> **Restore**. The first time a dance term appears it links to the
> [Glossary](./glossary.md), so you can get a plain-language
> definition without losing your place.

## Why back up

Because your work lives locally, a backup is simply your insurance. One
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
3. Choose **Export a backup**.

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

Every backup does carry a built-in **integrity checksum**. Think of it as a
checksum, not a lock or a security seal: it doesn't hide anything and it can't
stop a determined editor (who could simply recalculate it), but it lets the app
notice if the file was accidentally corrupted or changed after you exported
it. If a restore ever detects a mismatch, it stops before touching your
data (see [Restore from a backup](#restore-from-a-backup) below) instead of
importing something damaged.

### What's inside a backup

A backup holds **everything** you've built, including:

- Your whole collection of dances — figures, notes, tunes, links, and
  any [custom field](./glossary.md#custom-field) values you've filled in,
  including fields marked **Include in sharing** off, along with where each
  dance was imported from.
- All your programs, with their [slots](./glossary.md#slot),
  [alternates](./glossary.md#alt), event details, and which dances
  you've marked as performed.
- Your custom fields, tags, and choreographers. A sharing opt-out keeps a custom
  field out of files you send to other people; it does not remove the field from
  your own backup.
- Your custom [dialects](./dialects.md) and which one is active.
- Your custom themes and which one is active.
- Your settings and preferences.

A few device-specific odds and ends are left out on purpose, so a
restored device feels right at home instead of inheriting the old one's
quirks — things like window size and position, any half-finished edits
you hadn't saved yet, and the backup-reminder bookkeeping itself. You
don't need to think about these; the important part is that all your
real content comes along.

## Restore from a backup

Restoring loads a backup file back into the app. Use it when you're
setting up a new device or recovering after a problem.

1. Open **Settings**, then choose **General**.
2. Find the **Backup & restore** section.
3. Choose **Restore from a backup**, then choose **Restore**.
4. Either choose **Choose file…** (a picker that shows `.json` backups)
   or paste the backup text directly.
5. Confirm with **Replace all data**.

On success, you'll see a **Backup restored.** confirmation. If a few
items in the file couldn't be read, the app still restores everything
else and tells you how many were skipped. And if the file turns out to
be invalid or corrupt, the restore is safely stopped *before* any of
your current data is touched — so you never lose what you already have
by trying.

> **If your settings don't come back, your dances still did.** Occasionally a
> restore succeeds for your content but fails while re-applying your saved
> settings. The app says so plainly — *your dances and programs were restored,
> but applying your saved settings failed* — and offers **Retry settings**.
> Choose it and the app tries again, confirming with **Settings applied.** Your
> restored content is safe either way.

> **A broken integrity seal never harms your data.** If a backup was
> corrupted or altered after it was exported, its integrity check won't
> match and the app tells you it can't safely restore the file, then
> stops. Nothing is imported and your current library is left exactly as
> it was. Re-export a fresh backup and try again with that.

> **Have an older `.ccbackup` file?** Earlier betas offered an optional
> passphrase-encrypted backup saved as `.ccbackup`. That option has been
> retired, and the app can no longer open those files. If you're updating
> from an older beta and still have data only in a `.ccbackup`, restore it
> with the older build first, then export a fresh `.json` backup.

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
round trip. Because a backup restores exactly, what you save is what you
get back:

1. On your **old** device, export a backup (see above).
2. Transfer the file to the new device — through a cloud drive, a USB
   stick, or email to yourself.
3. On your **new** device, restore from that backup.

That's it. Your collection, programs, dialects, themes, and settings all
arrive intact.

## Backup reminders

If you'd like a nudge to stay current, the **Backup & restore** section
includes a **Backup reminder** setting. You can choose:

- **Off** (the default)
- **Weekly**
- **Monthly**

The setting also shows **Last backup: never** or the date of your most
recent backup, so you always know where you stand. When a backup is
overdue, the app shows a gentle reminder to export one — no pressure,
just a friendly tap on the shoulder.

## Backups happen automatically too

Beyond the backups you make, the app quietly keeps its own recovery
snapshot before any major internal upgrade. This means your data stays
protected across app updates without you doing anything at all. There's
no button to press and nothing to manage — it's simply there as an extra
safety net.

This automatic snapshot is a bonus, not a replacement. Your own exported
backups are still the copies you can move between devices and store
wherever you like.

## Backups vs. sharing vs. importing

It's easy to mix up three related-but-different features:

- **Backup & restore** (this guide) works with your *entire* library at
  once — one file in, one file out.
- **Sharing a single dance or program** as text or PDF is a separate
  thing that lives on each individual dance or program, not here. See
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
