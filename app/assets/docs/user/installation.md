# Installation

This guide helps you download Caller's Compendium and get it running on your
computer, tablet, or phone — including any one-time security prompt your system
shows the first time you open it, and how to keep the app up to date.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Settings**, **Assets**, and **Open**. File names
> and anything you type appear in `monospace`. The first time a dance term
> appears it links to the [Glossary](./glossary.md), so you can get a
> plain-language definition without losing your place.

## Before you start

Caller's Compendium is **local-first**: there's no account to create and nothing
to sign in to. Installing is just downloading the right file for your device and
opening it — the same as any other app.

Caller's Compendium is in **open beta**: the app is complete and in everyday
use, and new versions are released regularly. Two things are worth knowing
before you begin:

- **Each platform handles app signing differently.** The **macOS** build is
  signed with an Apple Developer ID and notarized, and the **Windows** build is
  code-signed, so both open like any other app. **Linux** builds are not signed,
  but Linux doesn't show a signing prompt. If your system does show a prompt,
  [The first-time security warning](#the-first-time-security-warning-explained)
  explains what to do.
- **Keep a backup habit.** Your work lives on your own device, so export a
  backup from time to time — and before installing a new version. You can do
  this any time from **Settings › General**; see
  [Backup & portability](./backup-portability.md).

### Find the download

All downloads live on the project's **Releases** page:

**https://github.com/ibanner56/CallersCompendium/releases**

1. Open the [Releases page](https://github.com/ibanner56/CallersCompendium/releases).
2. Choose the **latest release** at the top. During the beta it's marked
   **Pre-release**.
3. Expand its **Assets** list to see the downloadable files.

Each file is named `CallersCompendium-<version>-<platform>-<arch>` so you can
tell at a glance which one is for you — for example, a name ending in
`-windows-x64.exe` is the Windows installer. Pick the file that matches your
device from the sections below.

Alongside the app downloads you'll also see a `SHA256SUMS` file. It's optional —
see [Verify your download](#verify-your-download-optional) if you'd like to
double-check a file — and three files that you can ignore: `beta.json` and
`beta.json.sig` (which the app uses to check for updates) and
`sbom-<version>.cdx.json` (a technical list of what's inside the app).

## Install on Linux

There are two downloads for Linux (x64); either works.

**What you need:** a 64-bit Linux with glibc 2.35 or newer and the GTK 3
desktop libraries. Ubuntu 22.04, Debian 12, Fedora 36 and later releases of
each meet this, as do distributions based on them (such as Linux Mint 21). If
the app won't start and a terminal shows a message that a `GLIBC_` version was
"not found", your system is older than this.

- **AppImage** (`...-linux-x64.AppImage`) — a single file. It uses the system
  libraries above rather than carrying its own.
  1. Download the AppImage.
  2. Mark it as runnable. In your file manager, open the file's
     **Properties**, find the permissions, and allow it to run as a program. If
     you're comfortable with a terminal, `chmod +x` on the file does the same
     thing.
  3. Open the AppImage to launch the app.
- **Archive** (`...-linux-x64.tar.gz`) — no setup needed.
  1. Extract the archive to a folder you like.
  2. Open `compendium_app` inside that folder.
  3. Optional: to add the app to your applications menu, copy
     `org.callerscompendium.compendiumApp.desktop` from that folder into
     `~/.local/share/applications/`, and `compendium_app.png` into
     `~/.local/share/icons/hicolor/512x512/apps/`. Then edit the copied
     `.desktop` file so its `Exec=` line gives the full path to
     `compendium_app` in the folder where you extracted it.

> **AppImage won't open?** The AppImage needs a `fusermount` (or `fusermount3`)
> program, which some recent distributions don't install by default. If you see
> "No suitable fusermount binary found on the $PATH", install your
> distribution's `fuse3` package (`fuse3` on Debian, Ubuntu and Fedora). You can
> also run it without FUSE by typing
> `./CallersCompendium-*.AppImage --appimage-extract-and-run` in a terminal, or
> use the archive instead.

## Install on macOS

macOS has one universal download that runs on both Intel and Apple Silicon Macs.

- **Disk image** (`...-macos-universal.dmg`) — the usual way.
  1. Open the downloaded `.dmg`. A window opens with the app on the left and
     your **Applications** folder on the right.
  2. Drag the Caller's Compendium app onto the **Applications** folder,
     following the arrow.
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
  2. Open `compendium_app.exe` inside that folder to run it.

## Install on Android

There are two ways to get Caller's Compendium on Android, and you only need one:

- **Google Play (closed testing)** — the app is in a **closed test** on the
  Google Play Store. It installs and updates like any Play app, so it's the
  most convenient option, and each tester helps prepare the app for wider
  release on Google Play. **A place on the tester list is tied to a Google
  account, so joining means sharing the Google-account email you use on that
  device** (see below). If you'd rather not, the direct download works just as
  well.
- **Direct download (`...-android-universal.apk`)** — one file that works on all
  supported phones and tablets. You install it yourself (sometimes called
  *sideloading*), and it doesn't need a Google account or the tester list.

### Join the Google Play closed test

1. Give us the **Google-account email** you use on the Android device you'll test
   on. The easiest way is the platform question and email field on the
   **[Join the beta](https://github.com/ibanner56/CallersCompendium/issues/new?template=beta_signup.yml)**
   form; you can also reach out through the [beta guide](../beta/beta-guide.md)
   contact links.
2. Once we've added you to the tester list, you'll get an **opt-in link**. Open
   it on your device and accept to become a tester.
3. Install **Caller's Compendium** from the Play Store page the link takes you
   to. From then on, Play handles updates for you automatically.

### Install the `.apk` directly

1. Download the `.apk` to your device.
2. Open it. Android may say it needs permission to **install unknown apps** for
   whatever you opened it with — your browser or file manager. This is expected
   for an app installed outside the Play Store.
3. Allow installing from that app, then continue.
4. Finish the install and open Caller's Compendium.

> **Pick one lane and stay in it.** The Play Store build and the direct `.apk`
> are signed with **different keys**, so Android treats them as two separate
> apps. You can't upgrade from one to the other in place — installing the Play
> version won't replace a sideloaded `.apk` (or the other way around), and your
> data doesn't carry across on its own. If you ever need to switch, do it
> deliberately: open the app you have and **export a backup** (Settings ▸ General
> ▸ Export a backup), **uninstall** it, install the other one, then **restore**
> from that backup. Choosing one route from the start avoids all of this.

> **Still running `v0.1.0-beta.1` on Android?** That first build used a
> different internal app identifier, so newer builds install *alongside* it
> rather than replacing it, and your data does **not** carry over on its own.
> To move across: open the old app, **export a backup** (Settings ▸ General ▸
> Export a backup), uninstall it, install the current `.apk`, then **restore**
> from that backup.

## On iPhone and iPad

The iOS/iPadOS build is delivered through **TestFlight**, Apple's app for beta
testing, rather than the Releases page above. It's an **open beta** — anyone can
join, no invitation needed — but it is not yet listed on the App Store.

1. Install **TestFlight** from the App Store if you don't have it.
2. Open the public join link on your device:
   **<https://testflight.apple.com/join/REgW311w>**.
3. Accept in TestFlight and install Caller's Compendium from there. TestFlight
   handles updates for you when a new version is released.

It runs on both iPhone and iPad.

## The first-time security warning, explained

Most people won't see a warning at all: the **macOS** build is signed and
notarized, the **Windows** build is code-signed, and **iOS** comes through
TestFlight. If a prompt does appear, nothing is wrong with the download.

- **Windows.** Windows SmartScreen can still show a blue **Windows protected
  your PC** prompt, most often for a newly released version it hasn't seen
  widely yet. Choose **More info**, then choose **Run anyway**.
- **Linux.** Linux builds are not code-signed, but Linux doesn't show a signing
  prompt. Make sure the AppImage is marked as runnable (see
  [Install on Linux](#install-on-linux)), or use the `tar.gz` archive instead.

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

During the beta, two things are worth knowing:

- **Turn on the Beta channel.** Every release so far is a beta, and with the
  **Beta channel** switch off (its default) the app only looks for stable
  releases — so it won't find new betas. Switch on **Beta channel** in
  **Settings › Updates**, and optionally **Check automatically**.
- **The Releases page always has the newest version.** You can also watch the
  [Releases page](https://github.com/ibanner56/CallersCompendium/releases) and
  download a new version the same way you did the first time.

When the app does find an update: on **desktop** it can download it, verify it
hasn't been tampered with, and hand it to your system's installer to finish. On
**phones and tablets** it links you to the release so you can download it the
usual way for your device. (If you installed on Android through the **Google Play
closed test**, you don't need any of this — Play updates you automatically, the
same as any other Play app.)

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
