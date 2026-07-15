# Contributing to Caller's Compendium

Thanks for helping build a community-maintained tool for dance callers! The
best starting point is the [roadmap](docs/ROADMAP.md) and the design docs in
[docs/design/](docs/design/).

## Ground rules

- Be kind. See our [Code of Conduct](CODE_OF_CONDUCT.md).
- The project is **AGPL-3.0**; all contributions are accepted under that
  license.
- Significant design changes start as a discussion or an ADR proposal
  (see below) — not as a surprise PR.

## How we work

### Branches & commits
- Branch from `main`; short-lived feature branches named
  `kebab-case-description`.
- Commits: imperative subject ≤ 72 chars, body explaining *why*. Keep commits
  atomic and self-explanatory — reviewers and future maintainers read history.
- PRs must pass CI (build, tests, lint, formatting) before review.

### Testing expectations
All business logic ships with comprehensive tests covering happy paths,
error paths, and edge cases. UI changes include widget tests where practical
and must satisfy the [accessibility baseline](docs/research/accessibility-baseline.md)
(semantics, keyboard, contrast) — a11y is an acceptance criterion, not polish.

### Architecture decisions
Non-trivial, hard-to-reverse choices are recorded as ADRs in
[docs/adr/](docs/adr/) using [the template](docs/adr/template.md). Propose one
by opening a PR adding a `Proposed` ADR.

### Dance-domain conventions
- Stored data is always **canonical** (role IDs, canonical move names);
  user-facing terms go through the [dialect system](docs/design/dialect.md).
- The figure taxonomy is versioned data — changes to it follow the process in
  [docs/design/figure-taxonomy.md](docs/design/figure-taxonomy.md).

## Getting started

The app is a Flutter [pub workspace](pubspec.yaml): the `app/` Flutter app plus a
pure-Dart domain core in `packages/compendium_core/` (which must not import
Flutter — ADR-001, enforced in CI). Flutter is pinned to the version in
[`.fvmrc`](.fvmrc) (currently 3.44.6); [FVM](https://fvm.app/) is the easy way to
match it.

```sh
flutter pub get                 # resolve the whole workspace
dart format --output=none --set-exit-if-changed .   # formatting (CI-enforced)
flutter analyze                 # lint
(cd packages/compendium_core && dart test)          # core unit tests
(cd app && flutter test)        # app/widget tests
(cd app && flutter run)         # run the app on your device/desktop
```

CI runs all of the above plus a release build matrix across Linux, macOS,
Windows, Android, and iOS. Getting the roadmap's open items moving — see
[docs/ROADMAP.md](docs/ROADMAP.md) — plus doc review, design feedback, and
test-corpus contributions (interesting dances that stress the figure model!)
are all welcome. Open an issue or start a discussion.

## Reporting bugs / requesting features

Use the issue templates. For dance-notation questions, include the dance's
source (book/site/id) so we can look at the original.
