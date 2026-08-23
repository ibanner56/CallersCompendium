# Caller's Compendium

[![Latest release](https://img.shields.io/github/v/release/ibanner56/CallersCompendium?include_prereleases&sort=semver)](https://github.com/ibanner56/CallersCompendium/releases)
[![License: AGPL-3.0](https://img.shields.io/github/license/ibanner56/CallersCompendium)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android%20%7C%20iOS-lightgrey)  
[![CI](https://github.com/ibanner56/CallersCompendium/actions/workflows/ci.yml/badge.svg)](https://github.com/ibanner56/CallersCompendium/actions/workflows/ci.yml)
[![Made with Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

An open-source, local-first dance organizer for Contra (and eventually ECD and
Squares) callers — on desktop, tablet, and phone.

> **Status: our public beta is well underway.** The core app is built and working —
> collection management, search, programs, and performance mode are complete
> (roadmap Phases 0–5, plus the Caller's Companion parity backfill and the
> named-dialect library manager), importing from community sources and migrating
> from Caller's Companion have landed (Phase 6), and the release pipeline
> (Phase 7) now produces downloadable builds for every platform. Releases have
> shipped steadily since `v0.1.0-beta.1`, and we are now on **`v0.1.0-beta.6`**.
> **Download the latest beta from the
> [Releases page](https://github.com/ibanner56/CallersCompendium/releases)** —
> pick the newest release (marked *Pre-release*) and expand its **Assets** for
> Linux, macOS, Windows, and Android. Not sure which file to grab, or hitting the
> first-launch security prompt? The
> [Installation guide](docs/user/installation.md) walks you through it. **iPhone
> and iPad** builds are delivered through **TestFlight** to invited testers rather
> than the Releases page. **Android APKs are signed** and the **macOS build is
> signed and notarized**. Linux desktop artifacts are unsigned; Windows artifacts
> are signed via Azure Trusted Signing when the release workflow's five `AZURE_*`
> repository variables and federated OIDC configuration are present, with an
> unsigned fallback that may show a SmartScreen prompt. See
> [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed, item-by-item status.

## What it does

- **Collection** — catalog dance transcriptions with structured, searchable
  figures; search by title, author, type, formation, level, figures (even
  "chain then swing in B2"), and your own custom fields. Enter figures with the
  structured editor, or turn on free-text entry to type them — with your own
  shorthands — and have them parsed into structured, editable figures. Keep a
  step-by-step **Walkthrough** on each dance, pre-filled from your own reusable
  snippet library, and group your collection by category to hot-swap dances of a
  given "vibe" mid-evening. _(built)_
- **Programs** — create, edit, duplicate, and print/email set lists for events,
  with alternate dances, free-text slots, reusable venues, and a programming matrix
  computed from the choreography itself. Build a program from a plain-text title
  list or straight from a ContraDB event, and share a program together with all the
  dances it uses — or open one you've been sent (AirDrop, "Open with", or a share
  intent) to import the whole program and its dances in one step. _(built)_
- **Performance mode** — a large-print, high-contrast, stage-ready calling
  view with wake-lock, program navigation, on-the-fly adjustments, and
  screen-reader-friendly figure rendering. _(built)_
- **Dialect** — your terms, your phrasing: role names, move substitutions,
  dancer-term substitutions, and discouraged-term flags are fully editable
  presentation settings applied over a
  standardized canonical vocabulary, so search always works and data stays
  portable. Ships role-neutral presets (Larks/Robins by default, Leads/Follows);
  gendered or house-specific terms are entered via the custom role-terms editor.
  _(built, including a named-dialect library — create custom dialects, duplicate a
  preset to customize, preview edits live, and quick-switch dialects per gig)_
- **Imports** — bring dances in from community sources and migrate from
  Caller's Companion, with no re-typing and no lock-in. _(built: in-app import
  from The Caller's Box and ContraDB by link/id,
  from Caller's Companion — both its formatted-text copy and its binary `.USR`
  library file — and from our own Compendium JSON, all through a
  review-and-commit queue.)_
- **Your language** — the interface is available in English, German, French,
  Japanese, Danish, and Dutch, selectable in Settings (or follow your device). Your
  dance terminology stays under your control via Dialects, independent of the
  interface language. _(built)_
- **Backup & portability** — your library lives on your own device, so you keep
  your own safety copy: choosing **Export a backup** in Settings writes your
  whole collection, programs, and settings to a single dated file you can keep
  anywhere (cloud drive, USB stick, email). Restore it on a new phone, tablet,
  or computer — and an optional reminder nudges you to take a fresh copy. No
  cloud account, no lock-in.
  _(built — see the [Backup & portability guide](docs/user/backup-portability.md))_
- **Private by design** — everything is stored locally and the app is fully
  usable offline; there is **no analytics, tracking, or telemetry** — the app
  never "phones home," and nothing about you is collected or transmitted. It
  reaches the internet only for imports you initiate and for an optional update
  check that is **off by default**.
  _(built — see the [privacy policy](https://ibanner56.github.io/CallersCompendium/privacy/))_
- **Updates you can verify** — an optional in-app update check tells you when a
  new release is out. Update manifests are **cryptographically signed** and
  artifacts are restricted to a GitHub-owned host allowlist; on desktop, an
  assisted download **verifies the SHA-256 checksum before handing the file to
  your OS**. Automatic checking and the beta channel are both **off by default**.
  _(built)_
- **Built to be usable** — keyboard-reachable controls, screen-reader support,
  and a high-contrast stage theme run throughout, not just in Perform mode. The
  full **User Guide ships inside the app**, so help is available offline at the
  hall. _(built — see the [Accessibility guide](docs/user/accessibility.md))_

## Design & decisions

| | |
|---|---|
| Plan | [docs/ROADMAP.md](docs/ROADMAP.md) |
| Architecture decisions | [docs/adr/](docs/adr/) — stack: Flutter ([ADR-001](docs/adr/001-application-stack.md)) |
| Designs | [docs/design/](docs/design/) — domain model, figure taxonomy, dialect, storage, imports, UX |
| Research | [docs/research/](docs/research/) — incl. the [accessibility baseline](docs/research/accessibility-baseline.md) |

## Contributing

We'd love your help — especially from callers and dance-community developers.
Start with [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Feedback & beta

Are you a caller? We're running a beta program and would love your feedback. The
[Beta guide](docs/beta/beta-guide.md) explains how to join, what to try, and how
to send feedback — all voluntary, all through GitHub, with no telemetry and
nothing collected automatically. Ready to jump in? Use the
[**Join the beta**](https://github.com/ibanner56/CallersCompendium/issues/new?template=beta_signup.yml)
form, browse downloads on the
[project site](https://ibanner56.github.io/CallersCompendium/), or file a report
from the
[issue chooser](https://github.com/ibanner56/CallersCompendium/issues/new/choose) —
the **Bug report**, **Feature request**, **General feedback**, **Beta check-in**,
and **Import source problem** forms are all live there — or start a conversation in
[Discussions](https://github.com/ibanner56/CallersCompendium/discussions).

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

All dances made available for download and import into Callers Compendium are offered rights-free and without license. If this ruffles your feathers and you'd prefer that a particular dance or a subset of dances were not available for access to users of this application, feel free to reach out to the developer and we promise to at least have a respectful, nuanced conversation about the issue.[^2]

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

[^1]: Barriers tending to, y'know, get in the way and keep people out of things, rather than welcoming and supporting them.
[^2]: But we don't necessarily promise to do anything about it.
