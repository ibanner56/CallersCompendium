# Caller's Compendium

An open-source, local-first dance organizer for Contra (and eventually ECD and
Squares) callers — on desktop, tablet, and phone.

> **Status: our first public beta is out.** The core app is built and working —
> collection management, search, programs, and performance mode are complete
> (roadmap Phases 0–5, plus the Caller's Companion parity backfill and the
> named-dialect library manager), importing from community sources and migrating
> from Caller's Companion have landed (Phase 6), and the release pipeline
> (Phase 7) now produces downloadable builds for every platform. **Download the
> latest beta from the
> [Releases page](https://github.com/ibanner56/CallersCompendium/releases)** —
> pick the newest release (marked *Pre-release*) and expand its **Assets** for
> Linux, macOS, Windows, and Android. Not sure which file to grab, or hitting the
> first-launch security prompt? The
> [Installation guide](docs/user/installation.md) walks you through it. **iPhone
> and iPad** builds are delivered through **TestFlight** to invited testers rather
> than the Releases page; the macOS build is now signed and notarized (Linux and
> Windows remain unsigned). See [docs/ROADMAP.md](docs/ROADMAP.md) for
> the detailed, item-by-item status.

## What it does

- **Collection** — catalog dance transcriptions with structured, searchable
  figures; search by title, author, type, formation, level, figures (even
  "chain then swing in B2"), and your own custom fields. Enter figures with the
  structured editor, or turn on free-text entry to type them — with your own
  shorthands — and have them parsed into structured, editable figures. _(built)_
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
  Caller's Companion; everything is stored locally and the app is fully usable
  offline. _(built: in-app import from The Caller's Box and ContraDB by link/id,
  from Caller's Companion — both its formatted-text copy and its binary `.USR`
  library file — and from our own Compendium JSON, all through a
  review-and-commit queue.)_

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

Maybe that means something to you, maybe you're just reading this because you like Isaac Banner rants (I don't understand why, but I'm glad you're here). Either way, if you like what this project is doing and you'd like to support it, you can donate through either of these:

- **❤️ [GitHub Sponsors](https://github.com/sponsors/ibanner56)** — one-time or recurring; GitHub takes no platform cut (standard payment-processing fees may still apply).
- **[PayPal](https://paypal.me/IsaacBanner)** — quick one-time tip, no GitHub account needed.

Sponsorships and donations go directly toward development time and keeping the project free for everyone. You can also support the project without spending a cent — star the repo, file issues, and contribute (see [Contributing](#contributing)).

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

[AGPL-3.0](LICENSE)

[^1]: Barriers tending to, y'know, get in the way and keep people out of things, rather than welcoming and supporting them.
[^2]: But we don't necessarily promise to do anything about it.
