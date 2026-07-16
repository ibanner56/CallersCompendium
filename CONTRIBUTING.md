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

### Database schema migrations
The local database schema is versioned by `schemaVersion` in
[`packages/compendium_core/lib/src/storage/database.dart`](packages/compendium_core/lib/src/storage/database.dart).
When you change the schema:

- Bump `schemaVersion`, add the matching `MigrationStrategy` step, and ship a
  migration test/fixture (`test/storage/migration_test.dart` and/or a
  `test/storage/fixtures/` fixture). CI **fails** a PR that bumps
  `schemaVersion` without adding or changing such a test/fixture.
- **Never bump `schemaVersion` in a PATCH release.** A schema change is a
  data-format change and rides at least a MINOR version bump.

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
   fvm flutter analyze                                 # lint
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
