# ContraCompiler

A stateless, functional "compiler" for contra-dance choreography. It applies an
ordered sequence of parameterized **operations** (figures) to a **formation**
matrix and verifies the resulting state against a named **success criterion**
(e.g. a single progression of a Duple Improper dance).

- **Domain model:** [`docs/fundamentals.md`](docs/fundamentals.md)
- **Execution model / architecture:** [`docs/architecture.md`](docs/architecture.md)
- **Current implementation status:** [`docs/status.md`](docs/status.md)

## Status

Early development. Scope is currently **duple** formations only; other formations
are stubbed for the future.

## Toolchain

Pure Dart (Flutter-free), matching the
[CallersCompendium](https://github.com/ibanner56/CallersCompendium) toolchain:

- **Flutter 3.44.6 / Dart 3.12** pinned via [FVM](https://fvm.app) (`.fvmrc`).
- Strict analyzer settings; `dart format` clean; `dart test` with coverage.

### Common commands

```sh
fvm dart pub get         # resolve dependencies
fvm dart analyze         # static analysis
fvm dart test            # run tests
fvm dart format .        # format
```

This package is structured to drop into the CallersCompendium pub workspace as a
pure-Dart member alongside `compendium_core`.
