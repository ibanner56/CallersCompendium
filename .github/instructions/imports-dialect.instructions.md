---
applyTo:
  - "packages/compendium_core/lib/src/imports/**"
  - "packages/compendium_core/lib/src/dialect/**"
  - "packages/compendium_core/lib/src/taxonomy/**"
  - "packages/compendium_core/test/imports/**"
  - "packages/compendium_core/test/dialect/**"
  - "packages/compendium_core/tool/check_fixture_validity.dart"
  - "docs/design/dialect.md"
  - "docs/design/figure-taxonomy.md"
  - "docs/design/imports.md"
---

# Importers, dialect, and the figure taxonomy

These rules load for sessions touching the importers, the dialect decoders, or
the taxonomy they validate against.

## Fixtures are validated against the taxonomy — but not by `dart test`

Rendering **substitutes** rather than validates, so an invalid param renders
literally and every test still passes. A drifted fixture is therefore invisible
to a clean local `dart test`, and shows up only in CI — where it reads as
flakiness if you have forgotten that the local suite omits the check.

Run the ratchet yourself whenever you change a move's params:

```sh
(cd packages/compendium_core && fvm dart run tool/check_fixture_validity.dart)
```

or `python3 tools/preflight.py`, which runs it along with everything else.

Every `Figure(...)` in either suite must be valid under `contraTaxonomy`, routed
through `testFigure` (which validates at run time, for fixtures built from
variables), or marked `// invalid-fixture: <reason>`. The marker is checked in
both directions: one that introduces no fixture is a stale claim the next fixture
written under it would silently inherit, so it fails rather than lying quietly.

Background: [incidents.md](../../docs/dev/agents/incidents.md#747-drifted-figure-fixtures-were-invisible-to-dart-test).

## "Declines to custom" depends on the decoder

Do not copy the claim that an absent map entry declines a line to custom. It is
true where the map is the sole recognizer (`figure_parser.dart`'s partner-token
map) and false where decoders fall through to the shared recognizer and only add
params — the line still structures. When you touch one of these maps, judge the
comment in *its* context rather than making the two files agree.

Worked example, including the exact sentences and why a uniform sweep was wrong:
[incidents.md](../../docs/dev/agents/incidents.md#718---721---722-a-false-claim-chased-by-citation).

## Display versus canonical

A rendering change is cheap. Putting the same value into **canonical text**
changes FTS, dedupe and the derived projection, and therefore means a taxonomy
bump, a migration and a derived rebuild. Decide which one an issue is asking for
before scoping it.

A structured param is filterable the moment it exists; it is findable by typing
its words into search only if it reaches canonical text.

## Taxonomy changes falsify comments that never mention the taxonomy

Adding or splitting a move, or changing a `ParamKind`/`choices` pairing, can make
comments elsewhere untrue without any of them citing the taxonomy — and tests
that inject a synthetic taxonomy stay green. After such a change, grep for the
**property** you altered, not just for citations of the file you edited.
