# Caller's Compendium

An open-source, local-first dance organizer for Contra (and eventually ECD and
Squares) callers — on desktop, tablet, and phone.

> **Status: pre-implementation.** The roadmap, research, and designs are done;
> the Flutter implementation is beginning. See [docs/ROADMAP.md](docs/ROADMAP.md).

## What it will do

- **Collection** — catalog dance transcriptions with structured, searchable
  figures; search by title, author, type, formation, figures (even "chain then
  swing in B2"), and your own custom fields.
- **Programs** — create, edit, duplicate, and print set lists for events, with
  alternate dances, free-text slots, and a programming matrix computed from
  the choreography itself.
- **Performance mode** — a large-print, high-contrast, stage-ready calling
  view with wake-lock and one-handed navigation.
- **Dialect** — your terms, your phrasing: role names (Larks/Robins,
  Gents/Ladies, …) and figure terms are presentation settings applied over a
  standardized canonical vocabulary, so search always works and data stays
  portable.
- **Imports** — connect to community sources (The Caller's Box snapshot,
  ContraDB exports) and migrate seamlessly from Caller's Companion. Everything
  is stored locally; the app is fully usable offline.

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

## Acknowledgements

This project stands on the shoulders of
[Caller's Companion](http://callerscompanion.com/) (Will Loving),
[ContraDB](https://github.com/contradb/contra) (David Morse, AGPL-3.0), and
[The Caller's Box](https://www.ibiblio.org/contradance/thecallersbox/)
(Chris Page & Michael Dyck) — thank you for decades of tools and curation for
this community. We are a new, independent project — not a fork of any of them,
and we do not seek to replace or diminish them.

## License

[AGPL-3.0](LICENSE)
