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

Caller's Compendium is complete for its first release and in **open beta**:
anyone can download it, and callers are using it for real gigs today. The beta
program is how we make sure it holds up everywhere callers work — at a noisy
hall, on a tablet propped on a music stand, the night before a gig — before the
first stable release and wider store availability.

Taking part doesn't mean extra work. You call dances the way you already do,
with the app in the mix, and tell us how it went.

## What to test

Every part of the app is ready for you to rely on, including:

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
- **Device Sync** *(experimental)* — keep your library in step across your own
  devices. It is off until you turn it on, under **Settings › Experimental**; see
  the [Device Sync section](../user/settings.md#device-sync) of the Settings guide.

## What to expect

- **Some platforms are still on test channels.** iPhone and iPad builds come
  through **TestFlight open beta** — join with a public link, no invitation
  needed — and Android is in a **Google Play closed test** alongside the direct
  `.apk` download. [How to install](#how-to-install) covers each platform.
- **You may find bugs.** Finding them is what the beta is for — when you do,
  please tell us (see [How to give feedback](#how-to-give-feedback)).

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

A good habit: **export a backup before you try something new or update
the app**, and keep that file somewhere outside the app (a cloud drive, a USB stick,
an email to yourself). If anything ever goes sideways, you can restore in a few
steps. The [Backup & portability guide](../user/backup-portability.md) covers this
in more depth.

## How to join

1. Read this guide and skim the [test charter](./test-charter.md) so you know the
   kinds of things we are hoping you will try.
2. **On iPhone or iPad?** Skip the form and join straight away with the public
   TestFlight link: <https://testflight.apple.com/join/REgW311w>. No signup, no
   invitation, no personal details needed.
3. Everyone else — or if you also want the **Android Google Play closed test** —
   fill out the **[Join the beta](https://github.com/ibanner56/CallersCompendium/issues/new?template=beta_signup.yml)**
   form to tell us which platforms you call on. A free GitHub account is all you
   need. **Heads-up: the signup issue is public.** The form asks for one contact
   detail if you want into the Android closed test: the **Google-account email**
   on your device. That's the only personal detail to include — please leave
   everything else out. Prefer not to post an email publicly? Email it to
   [compendium@contra.dance](mailto:compendium@contra.dance) instead, or just say
   hello in
   [GitHub Discussions](https://github.com/ibanner56/CallersCompendium/discussions)
   if you'd rather start with a conversation.
4. Install the app (below) and start using it for your real dances.

You can step back at any time, and you never have to share anything you would
rather keep private.

## How to install

Builds for Linux, macOS, Windows, and Android are on the
[Releases page](https://github.com/ibanner56/CallersCompendium/releases), and the
[Installation guide](../user/installation.md) walks through each platform. The
macOS build is signed and notarized and the Windows build is code-signed, so
both open like any other app.

- **Android:** join the **Google Play closed test**, which installs and updates
  like any Play app and helps prepare the app for wider release on Google Play,
  or install the signed **`.apk`** directly. The two are signed with different
  keys, so [pick one route and stay with it](../user/installation.md#install-on-android).
- **iPhone and iPad:** builds are delivered through **TestFlight**, and it's an
  **open beta** — join straight from the public link, no invitation needed:
  <https://testflight.apple.com/join/REgW311w>. See
  [How to join](#how-to-join).
- **Staying up to date:** every release during the beta is a beta release, so
  turn on **Beta channel** in **Settings › Updates** if you want the app to tell
  you when a new version is out. See
  [Keeping the app up to date](../user/installation.md#keeping-the-app-up-to-date).

Prefer to run from source, or want to help with the code? The
[Getting started section of CONTRIBUTING.md](../../CONTRIBUTING.md#getting-started)
walks through installing Flutter (via FVM) and running the app on desktop, an
emulator, or a connected phone. If you get stuck, ask in
[Discussions](https://github.com/ibanner56/CallersCompendium/discussions) and we
will help.

## How to give feedback

All feedback is voluntary and goes through GitHub, where it stays public and
searchable so others can benefit. Nothing is collected automatically — **the app
has no telemetry** and never phones home. You choose what to send and when.

Pick the channel that fits:

- **Bug report** — something is broken or wrong? Use the **Bug report** form.
  Include your platform and, for anything notation-related, the dance's source so
  we can reproduce it.
- **General feedback** — after a dance or a session with the app, share what
  worked, what felt awkward, or a "why does it do *that*?" moment. These
  impressions are some of the most valuable feedback we get.
- **Ideas and open-ended talk** belong in
  [Discussions](https://github.com/ibanner56/CallersCompendium/discussions), where
  we can chat before anything becomes a formal request.

All of the issue forms live on the
[new-issue chooser](https://github.com/ibanner56/CallersCompendium/issues/new/choose):
**Bug report**, **Feature request**, **General feedback**, and **Join the beta**. Not sure which to pick? Start a
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
