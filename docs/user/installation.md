# Installation

This guide helps you download Caller's Compendium and get it running on your
computer, tablet, or phone — including the one-time security prompt you'll see
the first time you open a beta build, and how to get the next beta when it's
ready.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Settings**, **Assets**, and **Open**. File names
> and anything you type appear in `monospace`. The first time a dance term
> appears it links to the [Glossary](./glossary.md), so you can get a
> plain-language definition without losing your place.

## Before you start

Caller's Compendium is **local-first**: there's no account to create and nothing
to sign in to. Installing is just downloading the right file for your device and
opening it — the same as any other app.

This is a **pre-release beta**. It may be a little rough in places, and that's
the point: you're among the first callers to use it for real, and what you run
into shapes the finished 1.0. Two things worth knowing before you begin:

- **Signing varies by platform.** The **macOS** build is now signed with an Apple
  Developer ID and notarized, so it opens normally. **Windows** and **Linux**
  builds aren't code-signed yet, so those operating systems show a caution the
  first time you open the app — the builds are fine, and signing is a step planned
  for a later release. The steps below show you exactly how to get past that
  prompt where it appears.
- **Keep a backup habit.** Since your work lives on your own device, it's worth
  exporting a backup now and then — especially during a beta. You can do this any
  time from **Settings › General**; see [Backup & portability](./backup-portability.md).

### Find the download

All downloads live on the project's **Releases** page:

**https://github.com/ibanner56/CallersCompendium/releases**

1. Open the [Releases page](https://github.com/ibanner56/CallersCompendium/releases).
2. Choose the **latest release** at the top. During the beta it's marked
   **Pre-release** — that's expected.
3. Expand its **Assets** list to see the downloadable files.

Each file is named `CallersCompendium-<version>-<platform>-<arch>` so you can
tell at a glance which one is for you — for example, a name ending in
`-windows-x64.exe` is the Windows installer. Pick the file that matches your
device from the sections below.

Alongside the app downloads you'll also see a `SHA256SUMS` file. It's optional —
see [Verify your download](#verify-your-download-optional) if you'd like to
double-check a file — and a couple of files the app itself uses that you can
ignore.

## Install on Linux

There are two downloads for Linux (x64); either works.

- **AppImage** (`...-linux-x64.AppImage`) — a single self-contained file.
  1. Download the AppImage.
  2. Mark it as runnable. In your file manager, open the file's
     **Properties**, find the permissions, and allow it to run as a program. If
     you're comfortable with a terminal, `chmod +x` on the file does the same
     thing.
  3. Open the AppImage to launch the app.
- **Archive** (`...-linux-x64.tar.gz`) — if you'd rather not deal with
  permissions.
  1. Extract the archive to a folder you like.
  2. Open the app binary inside that folder.

## Install on macOS

macOS has one universal download that runs on both Intel and Apple Silicon Macs.

- **Disk image** (`...-macos-universal.dmg`) — the usual way.
  1. Open the downloaded `.dmg`.
  2. Drag the Caller's Compendium app onto your **Applications** folder.
  3. Open the app from **Applications**. Because the macOS build is signed and
     notarized, it opens normally — you may just see a single confirmation the
     first time.
- **Archive** (`...-macos-universal.zip`) — unzip it and move the app wherever
  you keep your applications, then open it the same way.

## Install on Windows

There are two downloads for Windows (x64).

- **Installer** (`...-windows-x64.exe`) — a normal setup program.
  1. Open the downloaded `.exe`.
  2. If you see a blue **Windows protected your PC** prompt, follow
     [The first-time security warning](#the-first-time-security-warning-explained)
     below.
  3. Follow the installer, then open Caller's Compendium from your Start menu.
- **Portable copy** (`...-windows-x64.zip`) — no installer needed.
  1. Unzip the folder somewhere convenient.
  2. Open the app inside that folder to run it.

## Install on Android

Android has one download that works on all supported phones and tablets:
`...-android-universal.apk`. Caller's Compendium isn't on the Google Play Store
yet, so you install this file directly (sometimes called *sideloading*).

1. Download the `.apk` to your device.
2. Open it. Android may say it needs permission to **install unknown apps** for
   whatever you opened it with — your browser or file manager. This is expected
   for an app installed outside the Play Store.
3. Allow installing from that app, then continue.
4. Finish the install and open Caller's Compendium.

> **Upgrading from the very first beta (`v0.1.0-beta.1`)?** That early Android
> build used a different internal app identifier, so a newer build installs
> *alongside* it rather than over the top, and your data does **not** carry over
> on its own. Before you switch: open the old app, **export a backup** (Settings ▸
> General ▸ Export a backup), uninstall the old app, install the new `.apk`, then
> **restore** from that backup. This one-time step only affects testers coming
> from `beta.1`.

## On iPhone and iPad

The iOS/iPadOS build is delivered through **TestFlight**, Apple's app for beta
testing — not from the Releases page above. Because it's an early beta, it goes
out to **invited testers** rather than the public App Store.

1. Ask to join the beta (see [Feedback & beta](../beta/beta-guide.md), or reach
   out through the project's contact links). If you're added, you'll get a
   TestFlight invitation by email or a link.
2. Install **TestFlight** from the App Store if you don't have it.
3. Open the invitation, accept it in TestFlight, and install Caller's Compendium
   from there. TestFlight handles updates for you when a new beta lands.

It runs on both iPhone and iPad.

## The first-time security warning, explained

The **Windows** and **Linux** builds aren't code-signed yet, so the first time
you open the app your operating system may show a caution. Nothing is wrong with
the download — signing is a step planned for a later release. (The **macOS**
build is signed and notarized, so it opens normally, and **iOS** comes through
TestFlight, which needs no workaround.) Here's how to get past the prompt where
it appears.

- **Windows (SmartScreen).** On the blue **Windows protected your PC** prompt,
  choose **More info**, then choose **Run anyway**.
- **Linux.** There's no signing prompt to bypass. Just make sure the AppImage is
  marked as runnable (see [Install on Linux](#install-on-linux)), or use the
  `tar.gz` archive instead.

## Verify your download (optional)

This step is for readers who like to double-check a download, and it's entirely
optional — most callers can skip it.

The `SHA256SUMS` file in the release **Assets** lists an expected *checksum* (a
long unique fingerprint) for each download. If you want, you can calculate the
checksum of the file you downloaded and compare it to the matching line in
`SHA256SUMS`. If they match, your download arrived intact.

## Keeping the app up to date

Caller's Compendium can tell you when a newer version is out, and nothing ever
updates behind your back — you're always the one who chooses. You'll find the
controls in **Settings › Updates**; the [Settings guide](./settings.md#updates)
explains them in full.

During the beta, a couple of things are worth knowing:

- **Automatic checks and the Beta channel switch are off by default**, and the
  in-app checker may not catch every new beta yet.
- **So the reliable way to get the next beta is to watch the
  [Releases page](https://github.com/ibanner56/CallersCompendium/releases).**
  When a new one appears, download it the same way you did the first time.

When the app does find an update: on **desktop** it can download it, verify it
hasn't been tampered with, and hand it to your system's installer to finish. On
**phones and tablets** it links you to the release so you can download it the
usual way for your device.

## Where to go next

You're ready to open the app and start calling.

- **New here?** The [Getting started guide](./getting-started.md) walks you
  through your first launch, a tour of the app, and adding your first
  [dance](./glossary.md#dance).
- **Bringing your library along?** [Backup & portability](./backup-portability.md)
  covers moving your [collection](./glossary.md#collection) onto this device.
- **Hit a snag?** The [FAQ & troubleshooting guide](./faq.md) has fixes for the
  most common bumps.
- **Not sure what a word means?** The [Glossary](./glossary.md) has plain
  definitions for every term used across these guides.
