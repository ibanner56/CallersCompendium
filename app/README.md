# compendium_app

The Flutter application for [Caller's Compendium](../README.md) — the desktop,
tablet, and phone UI for the collection, program, and performance-mode features.
It targets Linux, macOS, Windows, Android, and iOS from this single codebase.

All domain logic (the figure taxonomy, dialect engine, storage, and import
pipeline) lives in the Flutter-free [`compendium_core`](../packages/compendium_core)
package; this app is the UI layer over it. Local persistence uses drift/SQLite
on-device via `drift_flutter`.

## Running

Flutter is pinned to the version in [`../.fvmrc`](../.fvmrc);
[FVM](https://fvm.app/) is the way we match it, so commands are prefixed with
`fvm`. From the repo root:

```sh
fvm flutter pub get      # resolve the pub workspace (app + core)
cd app
fvm flutter run          # run on the connected device / desktop
fvm flutter test         # widget + unit tests
```

See the repo [CONTRIBUTING guide](../CONTRIBUTING.md) for the full workflow and
the [roadmap](../docs/ROADMAP.md) for current status and open work.
