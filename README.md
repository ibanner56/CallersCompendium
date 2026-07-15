# Caller's Compendium

An open-source, local-first dance organizer for Contra (and eventually ECD and
Squares) callers — on desktop, tablet, and phone.

> **Status: in active development.** The core app is built and working —
> collection management, programs, and performance mode are all implemented
> (roadmap Phases 0–5, plus the Caller's Companion parity backfill). Imports
> from community sources and release packaging are the main remaining work.
> See [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed, item-by-item status.

## What it does

- **Collection** — catalog dance transcriptions with structured, searchable
  figures; search by title, author, type, formation, level, figures (even
  "chain then swing in B2"), and your own custom fields. _(built)_
- **Programs** — create, edit, duplicate, and print/email set lists for events,
  with alternate dances, free-text slots, and a programming matrix computed from
  the choreography itself. _(built)_
- **Performance mode** — a large-print, high-contrast, stage-ready calling
  view with wake-lock, program navigation, on-the-fly adjustments, and
  screen-reader-friendly figure rendering. _(built)_
- **Dialect** — your terms, your phrasing: role names, move substitutions,
  dancer-term substitutions, and discouraged-term flags are fully editable
  presentation settings applied over a
  standardized canonical vocabulary, so search always works and data stays
  portable. Ships role-neutral presets (Larks/Robins by default, Leads/Follows);
  gendered or house-specific terms are entered via the custom role-terms editor.
  _(built; a named-dialect library manager is in progress)_
- **Imports** — connect to community sources (The Caller's Box snapshot,
  ContraDB exports) and migrate seamlessly from Caller's Companion. Everything
  is stored locally; the app is fully usable offline. _(planned — the import
  pipeline framework is in place; source adapters are the next milestone)_

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
