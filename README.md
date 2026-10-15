# Caller's Compendium

[![Latest release](https://img.shields.io/github/v/release/ibanner56/CallersCompendium?include_prereleases&sort=semver)](https://github.com/ibanner56/CallersCompendium/releases)
[![License: AGPL-3.0](https://img.shields.io/github/license/ibanner56/CallersCompendium)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android%20%7C%20iOS-lightgrey)  
[![CI](https://github.com/ibanner56/CallersCompendium/actions/workflows/ci.yml/badge.svg)](https://github.com/ibanner56/CallersCompendium/actions/workflows/ci.yml)
[![Made with Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Caller's Compendium** is a free, open-source, local-first dance organizer for
contra dance callers. Keep your collection of dances, plan programs for your
events, and call from a large-print, stage-ready view — on your computer,
tablet, or phone, with or without an internet connection.

**[Website](https://ibanner56.github.io/CallersCompendium/)** ·
**[Download](https://github.com/ibanner56/CallersCompendium/releases)** ·
**[User Guide](docs/user/README.md)** ·
**[Join the beta](docs/beta/beta-guide.md)**

## Availability

Caller's Compendium is in **open beta**. The full feature set described below is
available today, and new releases ship regularly.

| Platform | How to get it |
|---|---|
| Linux (x64; glibc 2.35 or newer, such as Ubuntu 22.04 or later) | AppImage or `.tar.gz` from the [Releases page](https://github.com/ibanner56/CallersCompendium/releases) |
| macOS (Intel and Apple silicon) | Signed and notarized `.dmg` or `.zip` from the Releases page |
| Windows (x64) | Code-signed installer or portable `.zip` from the Releases page |
| Android | Google Play closed test, or a signed `.apk` from the Releases page |
| iPhone and iPad | TestFlight open beta — [join directly](https://testflight.apple.com/join/REgW311w), no invitation needed |

On the Releases page, choose the newest release and expand its **Assets**. The
[Installation guide](docs/user/installation.md) explains which file to choose
for each platform, what to expect the first time you open the app, and how to
stay up to date.

## Features

- **Collection** — Catalog dances with structured, searchable figures. Search by
  title, author, type, formation, level, your own custom fields, or the
  choreography itself — even "a chain, then a swing, in B2." Enter figures with
  the structured editor or type them as free text, using your own shorthands,
  and have them parsed into editable figures. Keep a step-by-step
  **Walkthrough** on each dance, pre-filled from a reusable snippet library, and
  group your collection by category to find the right dance mid-evening.
- **Programs** — Build, duplicate, print, and email set lists for your events,
  with alternates, free-text slots, and reusable venues. A programming matrix,
  computed from the choreography, shows the shape and variety of your evening
  at a glance. Start a program from a plain-text list of titles or from a
  ContraDB event, and share a program together with every dance it uses.
- **Perform mode** — A large-print, high-contrast calling view with program
  navigation, on-the-fly adjustments, a screen that stays awake, and
  screen-reader-friendly figure text.
- **Dialect** — Role names, move wording, and discouraged-term flags are all
  yours to set, and are applied as a presentation layer over a standard
  vocabulary, so search keeps working and your data stays portable. The app
  ships role-neutral presets (Larks/Robins by default, and Leads/Follows); you
  can build your own dialects, preview edits live, and switch dialects per gig.
- **Imports** — Bring dances in from The Caller's Box and ContraDB by link or
  ID, migrate from Caller's Companion (its formatted-text export or its `.USR`
  library file), or open a Caller's Compendium file. Every import passes through
  a review queue before anything reaches your collection.
- **Device Sync** *(experimental, opt-in)* — Keep your library in step across
  your own devices, with no account and no sign-in. It is off until you turn it
  on; see [Device Sync](docs/user/settings.md#device-sync) in the Settings guide.
- **Backup & portability** — Export your whole collection, programs, and
  settings to a single dated file, and restore it on any supported device. An
  optional reminder prompts you to take a fresh copy. See the
  [Backup & portability guide](docs/user/backup-portability.md).
- **Private by design** — Your library is stored on your device, and the app is
  fully usable offline. There is **no analytics, tracking, or telemetry**. The
  app goes online only for actions you start — an import, an update check, or
  Device Sync — and automatic update checks are **off by default**. See the
  [privacy policy](https://ibanner56.github.io/CallersCompendium/privacy/).
- **Verified updates** — The optional in-app update check reads a
  **cryptographically signed** manifest and only accepts downloads from
  GitHub-hosted addresses. On desktop, the assisted installer **verifies each
  download's SHA-256 checksum** before handing it to your operating system.
- **Accessible throughout** — Keyboard-reachable controls, screen-reader support,
  and a high-contrast stage theme run through the whole app, not only Perform
  mode. See the [Accessibility guide](docs/user/accessibility.md).
- **Your language** — The interface is available in English, German, French,
  Japanese, Danish, and Dutch, or can follow your device's language. Your dance
  terminology is set separately, through your dialect.
- **Help built in** — The complete [User Guide](docs/user/README.md) ships
  inside the app, so it is available offline at the hall.

## Documentation

| For | Start here |
|---|---|
| Callers using the app | [User Guide](docs/user/README.md) — also inside the app and on the [website](https://ibanner56.github.io/CallersCompendium/guide/) |
| Beta testers | [Beta guide](docs/beta/beta-guide.md) and [test charter](docs/beta/test-charter.md) |
| Contributors | [CONTRIBUTING.md](CONTRIBUTING.md) and the [developer docs map](docs/dev/README.md) |
| What's planned | [Roadmap](docs/ROADMAP.md) |
| Architecture decisions | [docs/adr/](docs/adr/) — for example, the choice of Flutter in [ADR-001](docs/adr/001-application-stack.md) |
| Designs | [docs/design/](docs/design/) — domain model, figure taxonomy, dialect, storage, imports, sync, and UX |
| Research | [docs/research/](docs/research/) — including the [accessibility baseline](docs/research/accessibility-baseline.md) |
| Security | [SECURITY.md](SECURITY.md) — how to report a vulnerability |

## Feedback and the beta program

If you call dances, your feedback shapes what comes next. The
[Beta guide](docs/beta/beta-guide.md) explains how to take part, what to try,
and how to send feedback. Taking part is voluntary, feedback goes through
GitHub, and the app collects nothing automatically.

- **Join the beta** with the
  [signup form](https://github.com/ibanner56/CallersCompendium/issues/new?template=beta_signup.yml).
- **Report a problem or suggest an idea** from the
  [issue chooser](https://github.com/ibanner56/CallersCompendium/issues/new/choose),
  which offers **Bug report**, **Feature request**, and **General feedback**
  forms.
- **Ask a question or start a conversation** in
  [Discussions](https://github.com/ibanner56/CallersCompendium/discussions).
- **Prefer email?** Write to
  [compendium@contra.dance](mailto:compendium@contra.dance).

## Contributing

Contributions are welcome — from callers and dancers as much as from developers.
Documentation fixes, dance-notation expertise, translations, and bug reports are
all valuable. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and please read the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Supporting

This project is made available free-of-charge (free of a kind, the birds and the frees, Staying Alive by the Free-Gees, etc.) under the GNU Affero General Public License, because the developer does not believe in putting financial barriers between aspiring callers and accessible calling resources[^1] and because Open Source Software has always been the one true path forward in the modern digital era. 

Maybe that means something to you, maybe you're just reading this because you like Isaac Banner rants (I don't understand why, but I'm glad you're here). Either way, if you like what this project is doing and you'd like to support it, you can do so by sharing it with other callers in your local community. As of right now, this project is not accepting donations or sponsorship, but I appreciate the thought and maybe you can buy me a coffee sometime.

## Choreography and Copyright

>“Social dances, simple routines, and other uncopyrightable movements are not ‘choreographic works’ under Section 102(a)(4) of the Copyright Act. As such, they cannot be registered, even if they contain a substantial amount of original, creative expression … Examples of social dance include the following:
>  - Ballroom dances. 
>  - Folk dances. 
>  - Line dances. 
>  - Square dances. 
>  - Swing dances. 
>  - Break dances.
> 
>"Choreographic works are compositions that are intended to be performed by skilled dancers, typically for the enjoyment of an audience. By contrast, social dances are intended to be performed by members of the general public …
>Given the express language in the House and Senate Reports concerning the meaning of the term ‘choreographic works’ and given the absence of any limitation on the public performance right with respect to dance, the Office has concluded that social dances do not constitute copyrightable subject matter under Section 102(a)(4) of the Copyright Act.”  
–	*Chapter 800, section 805.5, Compendium of U.S. Copyright Office Practices, Third Edition*

All dances made available for download and import into Caller's Compendium are offered rights-free and without license. If this ruffles your feathers and you'd prefer that a particular dance or a subset of dances were not available for access to users of this application, feel free to reach out to the developer and we promise to at least have a respectful, nuanced conversation about the issue.[^2]

## Acknowledgements

This project draws on prior work from:  
[Caller's Companion](http://callerscompanion.com/) (Will Loving),  
[ContraDB](https://github.com/contradb/contra) (David Morse, AGPL-3.0), and  
[The Caller's Box](https://www.ibiblio.org/contradance/thecallersbox/)
(Chris Page & Michael Dyck).

## License

[AGPL-3.0](LICENSE), with an [additional permission](LICENSE-EXCEPTION.md) that
allows Caller's Compendium to be distributed through managed application
marketplaces (Apple's App Store, Google Play, and comparable stores) under those
stores' required terms — while the source stays fully AGPL-3.0 and every user
keeps their rights to it.

Code we ported from other projects keeps their licenses; the notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

[^1]: Barriers tending to, y'know, get in the way and keep people out of things, rather than welcoming and supporting them.
[^2]: But we don't necessarily promise to do anything about it.
