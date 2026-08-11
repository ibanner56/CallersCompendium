# Contributing to Caller's Compendium

Thanks for helping build a community-maintained tool for dance callers! The
best starting point is the [roadmap](docs/ROADMAP.md) and the design docs in
[docs/design/](docs/design/).

## Ground rules

- Be kind. See our [Code of Conduct](CODE_OF_CONDUCT.md).
- The project is **AGPL-3.0**; all contributions are accepted under that
  license, together with the [App Store / managed-marketplace distribution
  exception](LICENSE-EXCEPTION.md) (an AGPL-3.0 §7 additional permission) — so
  the app can be published on the App Store and Google Play while the source
  stays fully AGPL-3.0.
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

### Database schema migrations
The local database schema is versioned by `schemaVersion` in
[`packages/compendium_core/lib/src/storage/database.dart`](packages/compendium_core/lib/src/storage/database.dart).
When you change the schema:

- Bump `schemaVersion`, add the matching `MigrationStrategy` step, and ship a
  migration test/fixture (`test/storage/migration_test.dart` and/or a
  `test/storage/fixtures/` fixture). CI **fails** a PR that bumps
  `schemaVersion` without adding or changing such a test/fixture.
- Add a drift schema dump for the new version under
  [`packages/compendium_core/drift_schemas/`](packages/compendium_core/drift_schemas/README.md).
  `test/storage/schema_verification_test.dart` asserts that migrating from
  every recorded version reproduces the schema a fresh database gets at head,
  so a missing dump is a failing test rather than a silent coverage hole. The
  README there covers regeneration — note that `drift_dev` cannot run from this
  workspace and is driven from a throwaway project.
- **Never bump `schemaVersion` in a PATCH release.** A schema change is a
  data-format change and rides at least a MINOR version bump.

Old schema versions are **retired** once they fall below the oldest supported
release: `kMinSupportedSchemaVersion` is the floor, a database stamped below it
is refused rather than partially migrated, and CI fails any PR that reintroduces
a fixture, generator or dump for a retired version. Raising the floor is
user-visible — those databases stop opening — so it needs an `app/CHANGELOG.md`
entry in user-facing terms. See
[Retiring a schema version](docs/design/storage.md#retiring-a-schema-version)
for the full checklist.

### Data classification
Every field the app persists is classified by what kind of data it is, whose
data it is, and whether it may leave the device. The catalogue lives in
[`packages/compendium_core/lib/src/privacy/`](packages/compendium_core/lib/src/privacy/)
and is documented in
[docs/dev/data-classification.md](docs/dev/data-classification.md).

**Any new column, settings key, or data-entry surface must be classified in the
same PR that introduces it.** This is enforced, not aspirational — CI fails on
an unclassified column or settings key. When you add one:

- Add an entry to `fieldClassifications` (database columns, keyed
  `table.column` with the SQL names) or `settingsClassifications` (settings
  keys).
- Say **why** in the entry's `note` when the call is not obvious. A reviewer
  should never have to guess why a personal-data field is `shareable`.
- Regenerate the catalogue:
  `fvm dart run packages/compendium_core/tool/generate_data_classification_doc.dart`
- If you added a whole new table — including a raw or virtual one drift does not
  type — declare it in `untypedTables` in the coverage test, or its columns
  escape classification silently.

Categories use the [W3C Data Privacy Vocabulary](https://w3c-cg.github.io/dpv/2.3/dpv/)
v2.3, pinned. It is freely readable, so you can check your own classification
against the source.

### Raw SQL reads from the settings table

Every raw `SELECT … FROM settings WHERE key` read must include
`AND deleted_at IS NULL`. This is enforced by
`tools/ci/check_settings_marker_reads.py` and its test
`test_check_settings_marker_reads.py`, wired into `_checks.yml`.

The invariant is load-bearing: `repositories.dart` performs a deliberate hard
`DELETE` to clear the rebuild marker and justifies that design choice in a
comment by asserting that every raw read already filters deleted rows. A future
unfiltered read would silently falsify that justification too — the dependency
exists only in a comment, and the two locations are ninety lines apart.

The ratchet handles Dart adjacent-string concatenation, so a read split across
two lines is also checked. The hard `DELETE` (which has no `deleted_at IS NULL`
and is intentionally correct) is excluded by name in the script rather than by
narrowing the detection pattern.

### Architecture decisions
[docs/adr/](docs/adr/) using [the template](docs/adr/template.md). Propose one
by opening a PR adding a `Proposed` ADR.

### Dance-domain conventions
- Stored data is always **canonical** (role IDs, canonical move names);
  user-facing terms go through the [dialect system](docs/design/dialect.md).
- The figure taxonomy is versioned data — changes to it follow the process in
  [docs/design/figure-taxonomy.md](docs/design/figure-taxonomy.md).

### User documentation
The guides under [docs/user/](docs/user/) are the source of truth **and** ship
inside the app **and** are published as the hosted
[user guide](https://ibanner56.github.io/CallersCompendium/guide/), so they are
code as much as prose. Two rules:

- Follow the [user-docs style guide](docs/user/style-guide.md) — voice,
  terminology, accessibility, and the hub's structure.
- After editing any guide, run `python3 tools/ci/sync_user_docs.py --write` and
  commit the regenerated `app/assets/docs/`. A CI check fails if they drift.

The hosted pages are **generated at publish time** by
`tools/site/render_user_docs.py` and never committed, so there is nothing to
regenerate for them — but a broken cross-link, an `#anchor` with no matching
heading, two headings that collide on one anchor, or a link to a repo file that
isn't in the tree all fail CI. Check your links locally with:

```sh
python3 tools/site/render_user_docs.py --check
```

Write only what the app actually does today. If a guide and the app disagree, one
of them is a bug — say which in your PR.

### Changelog

`app/CHANGELOG.md` records what changed from the user's seat, not from the
developer's. It has exactly **two triggers**:

1. **A user-visible change** earns a bullet under `## [Unreleased]`. Write it
   as user-facing prose in second person — "You can now…", "X no longer…" —
   and put it in the matching subsection (`Added` / `Changed` / `Fixed` /
   `Removed`).

2. **Cutting a release** moves the accumulated `[Unreleased]` content into a
   dated version section and resets `[Unreleased]` to `_Nothing yet._`. That is
   the only reason to edit the file on a release PR; it touches the file on a
   different trigger, not the same one.

**What does not qualify for an `[Unreleased]` entry:**

- Pure refactors or internal restructuring the user cannot observe
- Docs, design docs, CI, tooling, or release infrastructure changes
- Tests, fixtures, or CI ratchets
- Performance improvements the user cannot notice without a benchmark

When in doubt, ask: *"Would a user notice if I shipped this without telling
them?"* If the honest answer is no, no entry is needed.

**A failure mode to watch for:** if a question about the changelog arrives
pre-framed — *"should this entry go in section A or B?"*, *"which of these
lands first?"* — answer the narrower question **and** state the rule it rests
on. If the rule cannot be stated, that is the signal to derive it rather than
answer the narrower question. A convention measured only against recent output
will look like whatever you have been doing; widening the sample can reverse
the answer.

### Localization (i18n)
User-visible strings are internationalized with `flutter_localizations` +
`gen-l10n`, with **English as the source locale**. Add or change strings in
`app/lib/l10n/app_en.arb` (not inline in widgets), then use them via
`AppLocalizations.of(context)`. Translating the app needs **no handwritten
Dart**: copy `app_en.arb` to `app_<locale>.arb`, translate the values with
`arb_translate.py extract`/`apply` so per-key English-source markers are
recorded, then
regenerate the committed localizations (a one-line `gen-l10n` step) and, for
iOS, add the locale to the Runner's `Info.plist`. See
[docs/dev/localization.md](docs/dev/localization.md) for the key-naming
convention, how to add a string, and the full translation steps.

## Getting started

The app is a Flutter [pub workspace](pubspec.yaml): the `app/` Flutter app plus a
pure-Dart domain core in `packages/compendium_core/` (which must not import
Flutter — ADR-001, enforced in CI). Flutter is pinned to the version in
[`.fvmrc`](.fvmrc), which is the **single source of truth** for the Flutter
version: [FVM](https://fvm.app/) reads it to keep everyone on that exact SDK
locally, and CI derives its Flutter version from the very same file (via
`subosito/flutter-action`'s `flutter-version-file`). Bumping `.fvmrc` therefore
updates local development *and* every CI job together — there is no second
version to keep in sync. Install FVM, then from the repo root:

```sh
fvm install                     # fetch the pinned Flutter version (.fvmrc)
fvm flutter pub get             # resolve the whole workspace
```

All commands below use `fvm flutter` / `fvm dart` so they run against the pinned
SDK. (If you'd rather not prefix every command, `fvm use` sets up a `.fvm/`
symlink you can point your editor/PATH at — see the FVM docs.)

## Making a change

1. Branch from `main` (`kebab-case-description`).
2. Make your change. Domain logic (taxonomy, dialect, storage, imports) belongs
   in `packages/compendium_core/` and must stay Flutter-free; the UI lives in
   `app/`.
3. Run the checks CI enforces, from the repo root:

   ```sh
   fvm dart format .                                   # format (CI fails on diffs)
   fvm flutter analyze --fatal-infos                   # lint (CI treats infos as errors)
   (cd packages/compendium_core && fvm dart test)      # core unit tests
   (cd app && fvm flutter test)                        # app / widget tests
   ```

4. Open a PR; it must pass CI (build, tests, lint, formatting) before review.

## Running & viewing locally

Run the app with hot reload against a connected device, emulator, or your
desktop. `fvm flutter devices` lists what's available; `-d <id>` picks one.

```sh
cd app
fvm flutter run                 # default device (prompts if several)
fvm flutter run -d macos        # macOS desktop
fvm flutter run -d windows      # Windows desktop
fvm flutter run -d linux        # Linux desktop
fvm flutter run -d chrome       # quick web preview (not a shipping target)
fvm flutter run -d <android-id> # Android device/emulator (see `flutter devices`)
fvm flutter run -d <ios-id>     # iOS simulator/device (macOS host only)
```

Desktop targets have host prerequisites: **Linux** needs
`ninja-build` + `libgtk-3-dev` (and `clang`/`cmake`/`pkg-config`); **Windows**
needs Visual Studio with the "Desktop development with C++" workload; **macOS**
and **iOS** need Xcode; **Android** needs the Android SDK/NDK. Run
`fvm flutter doctor` to see what's missing for the platforms you want to build.

### Emulators & simulators

No physical phone required — you can test the mobile targets on emulated
devices. `fvm flutter emulators` lists the ones already configured.

**Android emulator** (any host with the Android SDK):

```sh
fvm flutter emulators                        # list configured emulators
fvm flutter emulators --launch <emulator-id> # boot one (or start it from Android Studio)
cd app && fvm flutter run                    # runs on the booted emulator
```

Create an emulator first with `fvm flutter emulators --create` (or via Android
Studio's Device Manager) if the list is empty.

**iOS simulator** (macOS host with Xcode only — Apple does not permit the iOS
simulator on Linux or Windows):

```sh
open -a Simulator                    # boot the iOS Simulator
cd app
fvm flutter devices                  # find the booted simulator's id/name
fvm flutter run -d "<simulator>"     # target it by name (or paste its device id)
```

`-d` matches a device **id or name**, not a platform — there is no `-d ios`
shortcut, so pick a booted simulator from `fvm flutter devices` and pass its
name (whatever your installed Xcode/SDK offers, e.g. an iPhone model) or its
UDID. If `fvm flutter run` finds only one mobile target it will use it
automatically.

Once a simulator/emulator is booted it shows up in `fvm flutter devices`, so you
can also select it with `-d <id>` when several targets are attached. Hot reload
(`r`) and hot restart (`R`) work the same as on physical devices and desktop.

To build release artifacts locally (the same set CI produces across Linux,
macOS, Windows, Android, and iOS):

```sh
cd app
fvm flutter build linux --release
fvm flutter build macos --release
fvm flutter build windows --release
fvm flutter build apk --release          # or: appbundle
fvm flutter build ios --release --no-codesign
```

Getting the roadmap's open items moving — see [docs/ROADMAP.md](docs/ROADMAP.md)
— plus doc review, design feedback, and test-corpus contributions (interesting
dances that stress the figure model!) are all welcome. Open an issue or start a
discussion.

## Reporting bugs / requesting features

Use the issue templates. For dance-notation questions, include the dance's
source (book/site/id) so we can look at the original.

## Feedback & beta

Caller's Compendium runs a beta program for real callers, and community feedback
is one of the most valuable ways to help — no code required. Everything here is
**voluntary and goes through GitHub**; the app itself is local-first and has **no
telemetry**, so nothing is ever collected automatically. You decide what to share.

- **New to the beta?** Start with the [Beta guide](docs/beta/beta-guide.md) — what
  the beta is, how to join, and how to send feedback — then skim the
  [test charter](docs/beta/test-charter.md) for concrete things to try, all
  centered on calling a real dance from **Perform mode**.
- **Filing something?** The
  [new-issue chooser](https://github.com/ibanner56/CallersCompendium/issues/new/choose)
  now carries the full set of forms: **Bug report** and **Feature request**,
  the beta-specific **General feedback** (rough edges), **Beta check-in** (how a
  session or gig went), and **Import source problem** (a dance imported wrong),
  plus a **Join the beta** signup. For open-ended ideas, start a
  [Discussion](https://github.com/ibanner56/CallersCompendium/discussions).
- **Curious what happens next?** Maintainers sort every report using the
  [triage rubric](docs/beta/triage-rubric.md), which maps to the label taxonomy in
  [`.github/labels.yml`](.github/labels.yml) so you can follow an issue from
  `status: triage` to `status: fixed-pending-release`.
- **Worried about your data?** Don't be — export a backup from
  **Settings → General** first. Backup and restore are built in, so testing a
  pre-release build never puts your collection at risk.
