# Caller's Compendium Beta Guide

Thanks for helping test **Caller's Compendium** — a free, open-source dance
organizer for contra-dance callers. This guide explains what the beta is, how to
join, what to expect, and how to send feedback that actually helps. It is written
for callers and dancers, not developers, so you do not need to know anything about
code to take part.

> **The short version:** install the app, use it for real — catalogue dances,
> build a program, and call from **Perform mode** at an actual gig — then tell us
> what worked and what got in your way. Your feedback is always voluntary, and you
> decide exactly what you share.

## What the beta is

The core of Caller's Compendium is built and working. The beta program invites a
small group of real callers to use it for their own dances before the first public
release, so we can find the rough edges that only show up in the wild — at a noisy
hall, on a tablet propped on a music stand, the night before a gig.

You are not signing up for a chore. You are calling dances the way you already do,
with the app in the mix, and telling us how it went.

## What's ready to test

These parts of the app are built and ready for you to lean on:

- **Collection** — catalogue dances with structured, searchable figures, and
  search by title, author, formation, level, or even the figures themselves.
- **Programs** — build set lists for an event, with alternates and free-text
  slots, plus a **matrix** that shows the shape and variety of your evening.
- **Perform mode** — a large-print, high-contrast, stage-ready calling view with
  the screen kept awake and edge-reachable navigation.
- **Dialect** — put the app in your own words: role names (it ships
  **Larks/Robins** by default, with **Leads/Follows** ready to pick) and move
  wording, switchable on the fly.
- **Imports** — bring dances in from **The Caller's Box**, **ContraDB**,
  **Caller's Companion**, or a **Caller's Compendium** file, through a
  review-and-commit queue.
- **Backup & restore** — save your whole collection to a single file and load it
  back (see [Your data is safe](#your-data-is-safe) below).

## What's still rough

Being honest about the state of things saves everyone time:

- **Signing is uneven across platforms.** The **macOS** build is signed with an
  Apple Developer ID and notarized, and the **Android** APK is signed, so both
  open normally. **Windows** and **Linux** builds aren't code-signed yet, so those
  operating systems show a one-time caution the first time you open the app —
  [How to install](#how-to-install) walks you past it. Code-signing for Windows
  and Linux is planned for a later release.
- **You may hit bugs.** That is the point — when you do, tell us (see
  [How to give feedback](#how-to-give-feedback)).

## Your data is safe

Caller's Compendium is **local-first**: your collection lives on your own device,
the app works fully offline, and there is nothing to sign in to. Because of that,
you are in control of your data, and the app gives you a built-in safety net so a
beta build never has to feel risky.

Open **Settings → General** and you will find:

- **Export a backup** — saves your entire collection, programs, custom fields,
  dialects, themes, and settings to a single file you can keep somewhere safe or
  copy to another device.
- **Restore from a backup** — loads a backup file back into the app.
- **Backup reminder** — an optional nudge (weekly or monthly) so you do not forget.

A good habit for the beta: **export a backup before you try something new or update
the app**, and keep that file somewhere outside the app (a cloud drive, a USB stick,
an email to yourself). If anything ever goes sideways, you can restore in a few
steps. The [Backup & portability guide](../user/backup-portability.md) covers this
in more depth.

## How to join

1. Read this guide and skim the [test charter](./test-charter.md) so you know the
   kinds of things we are hoping you will try.
2. Fill out the **[Join the beta](https://github.com/ibanner56/CallersCompendium/issues/new?template=beta_signup.yml)**
   form — it asks which platforms you call on, and (for iPhone/iPad) the Apple ID
   email for your TestFlight invite. A free GitHub account is all you need. You can
   also just say hello in
   [GitHub Discussions](https://github.com/ibanner56/CallersCompendium/discussions)
   if you would rather start with a conversation.
3. Install the app (below) and start using it for your real dances.

You can step back at any time, and you never have to share anything you would
rather keep private.

## How to install

Packaged beta builds are ready on the
[Releases page](https://github.com/ibanner56/CallersCompendium/releases). The
[Installation guide](../user/installation.md) walks you through downloading and
opening the app on Linux, macOS, Windows, and Android — including the first-time
security warning you will see on the **Windows and Linux** builds, which aren't
code-signed yet (macOS is signed and notarized, so it opens normally). The
**iPhone/iPad** build is delivered through **TestFlight** to invited testers —
ask in the beta channels if you'd like in.

Prefer to run from source, or want to help with the code? The
[Getting started section of CONTRIBUTING.md](../../CONTRIBUTING.md#getting-started)
walks through installing Flutter (via FVM) and running the app on desktop, an
emulator, or a connected phone. If anything feels like a lot, say so in
[Discussions](https://github.com/ibanner56/CallersCompendium/discussions) and we
will help — plenty of testers are callers first and tinkerers second.

## How to give feedback

All feedback is voluntary and goes through GitHub, where it stays public and
searchable so others can benefit. Nothing is collected automatically — **the app
has no telemetry** and never phones home. You choose what to send and when.

Pick the channel that fits:

- **Beta check-in** — after a dance or a session with the app, use the **Beta
  check-in** issue form to tell us how it went overall, even if nothing broke.
  These impressions are gold.
- **Bug report** — something is broken or wrong? Use the **Bug report** form.
  Include your platform and, for anything notation-related, the dance's source so
  we can reproduce it.
- **General feedback** — confusing wording, an awkward workflow, a "why does it do
  *that*?" — the **General feedback** form is the catch-all.
- **Import source problem** — if a dance imports wrong, the **Import source
  problem** form captures the source and what came through.
- **Ideas and open-ended talk** belong in
  [Discussions](https://github.com/ibanner56/CallersCompendium/discussions), where
  we can chat before anything becomes a formal request.

All of the issue forms live on the
[new-issue chooser](https://github.com/ibanner56/CallersCompendium/issues/new/choose):
**Bug report**, **Feature request**, **General feedback**, **Beta check-in**,
**Import source problem**, and **Join the beta** are all available there now. Not
sure which to pick? Start a
[Discussion](https://github.com/ibanner56/CallersCompendium/discussions) — we will
sort it out together. Once you file something, a maintainer sorts it using the
[triage rubric](./triage-rubric.md), so you can see how reports move from "just
arrived" to "fixed."

### What makes a report useful

You do not have to write a bug report like an engineer. A good report usually
answers:

- **What were you trying to do?** ("Build a program for a Saturday gig.")
- **What happened, and what did you expect instead?**
- **Where?** Which screen — **Collection**, **Programs**, **Perform**, or
  **Settings** — and on which device and platform.
- **Can you make it happen again?** Even "not sure" is helpful to know.
- For anything about a specific dance, the **source** (book, site, or an ID) so we
  can look at the original.

## A note on respect and privacy

This is a community project. We use role-neutral language by default and welcome
callers of every background and experience level. Your feedback, your dances, and
your details are yours: share what helps, keep back what does not, and know that
the app is not watching over your shoulder.

## Where to go next

- [Beta test charter](./test-charter.md) — concrete things to try, centered on
  calling a real dance.
- [Triage rubric](./triage-rubric.md) — how your feedback is sorted and tracked.
- [User guide home](../user/README.md) — everything about *using* the app.
- [Project README](../../README.md) — what the project is and how to support it.
