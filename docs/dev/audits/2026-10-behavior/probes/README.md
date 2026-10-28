# Audit probes

Throwaway scripts the auditors ran outside the repository. Re-run them only in a scratch copy, never in the tree.

- `parser/` (AUTH-4, AUTH-8, AUTH-16): a standalone Dart package with a path dependency on `packages/compendium_core`. Copy it out of the repo, run `dart pub get`, then `dart run bin/probe.dart` (and probe2–probe6).
- `share-import/out_probe_test.dart` (OUT-1, OUT-2): copy `packages/compendium_core` to a scratch directory, place this file in its `test/`, then run `dart test test/out_probe_test.dart` there. It uses the package's own `test/storage/test_database.dart` helper.
