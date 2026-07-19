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
app works fully offline. The only time it reaches the internet is when you choose
to [import](./glossary.md#import) dances from an online source such as
[The Caller's Box](./glossary.md#the-callers-box) or
[ContraDB](./glossary.md#contradb).

### Where is my data stored?

On your device, and only on your device. Nothing is uploaded to a server and
there's no cloud sync happening behind the scenes. That's great for privacy and
offline use — and it means *you* keep the safety copy. See
[Backup & portability](./backup-portability.md) for how.

### What does it cost? Is it really open source?

It's free and open source, licensed under **AGPL-3.0**. You'll find the version,
license, and a link to the source under **Settings › About**.

### Which devices does it run on?

Desktop (Linux, macOS, Windows) and mobile (Android, iOS/iPadOS). Step-by-step
install instructions are coming once packaged builds are available.

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
Leave **Auto-size** on to fit each card to the screen, or turn it off and use
**A−** / **A+** to set the size yourself. See [Perform mode](./perform.md), and
[Accessibility](./accessibility.md) for more ways to adjust text, contrast, and
input.

### How do I share a single dance or a program?

Open the dance or program and use its share/export options — you can share as
text or export a PDF. A program also offers **Share (program + dances)**, which
bundles the set list together with every dance it uses into one file the
recipient can import in a single step — dances and all, not just a list of
titles. This is separate from a full backup. See
[Collection & search](./collection.md) for dances and
[Programs & matrix](./programs.md#print-export-and-email-a-program) for programs.

### How do I get updates?

The app can check for a newer version itself. Open **Settings › Updates** and
choose **Check for updates** any time; on desktop it can download and install the
update for you, and on phones and tablets it links you to the download. Nothing
updates automatically unless you turn on **Check automatically**, and you can opt
into pre-release builds with the **Beta channel** switch. See
[Settings](./settings.md#updates).

## Troubleshooting

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

Usually, yes. Deleted dances are kept for a while before they're removed for good
— by default **30 days** (adjustable under **Settings › General › Keep deleted
dances for**). You can restore them within that window; see
[Collection & search](./collection.md). To avoid slips in the first place, turn on
**Confirm before delete** under **Settings › General**.

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
