# ContraCompiler — Implementation Guide

> **What this doc is for.** The other three docs say *what is true*:
> `fundamentals.md` is the domain state-model (the hall, the matrix, dancers,
> progression), `architecture.md` is the execution model (the pipeline and its
> resolved design decisions), and `taxonomy.md` is the figure catalogue (one
> entry per move, with its params and rulings).
>
> **This doc says where that lives in the code and how to change it safely.**
> It is the orientation an incoming session needs before touching anything: the
> layering, the load-bearing invariants, the traps that have actually bitten,
> and the checklist for adding a figure. When this doc and the code disagree,
> **the code is right** — fix this doc.

---

## 1. The one-paragraph model

A dance is an ordered list of parameterized **figures** applied to an immutable
**formation** (a 6-wide matrix of dancers), followed by a check of the resulting
state against an independently computed **oracle**. Everything is a pure
function; errors are values, never exceptions. The compiler's whole job is to
run the fold and answer one question — *did the dancers end up where the dance
claims they would?*

```
JSON record ──parse──▶ Dance ──compile──▶ Compiled | Mismatch | CompileError
                         │                    ▲
                         │                    │
                    figures[]            actual == expected
                         │                    │
                    fold over ──────▶ actual  │
                                              │
              success criterion ────▶ expected┘   (computed from the INPUT alone)
```

---

## 2. Package map

```
lib/
  contra_compiler.dart          barrel — the public surface
  src/
    domain/                     the state model. no behaviour beyond geometry-free accessors
      dancer.dart               DancerId (invariant) + DancerState (mutable) + bitmask codec
      formation.dart            Formation: entity map -> matrix projection, equality
      formation_type.dart       DupleImproper / BecketCw / BecketCcw + end-number rules
      facing.dart               Facing enum + turnedLeft/turnedRight/reversed
      position.dart             Position(row, col), kColumnCount
      role.dart                 Lark / Robin + bitmask
      couple_number.dart        CoupleNumber one/two + bitmask
      starting_formations.dart  formation type + size -> concrete starting matrix
    geometry/
      geometry.dart             bands, groupings, waiting-out, rings, travel direction
    ops/
      operation.dart            sealed Operation base + `part` directives for every figure
      figures/*.dart            21 part files, one family each
      params.dart               shared param enums (Hand, WhoSet, Direction, ...)
      who.dart                  who-set resolution + cross-hands-four refusal
      transforms.dart           reusable state transforms (swaps, reflections, waves)
      diagnostics.dart          ErrorKind / OpError / WarningKind / Warning
    engine/
      compiler.dart             Dance + compile() — the pipeline
      invocation.dart           OperationInvocation — figure + progression flag
      sizing.dart               computeHandsFour
      success_criterion.dart    the oracle
      end_normalization.dart    §10.2 progression end behaviour
      compile_result.dart       sealed Compiled / Mismatch / CompileError
      result.dart               Result<T, E> — Ok / Err
    io/
      dance_json.dart           the name->constructor registry and the parse boundary
      roles_notation.dart       "R1-A . . . L1-A" <-> Formation, for tests and fixtures
```

**Dependency direction is strictly downward:** `io -> engine -> ops -> geometry
-> domain`. Nothing in `domain` knows a figure exists. `ops` never imports
`engine`.

### 2.1 Why the figures are `part` files

`Operation` is **sealed**, so the taxonomy is a closed set no code outside this
library can extend. Dart only allows a sealed hierarchy to span files via
`part`, so every figure file is a `part of '../operation.dart'`. The cost is
real and worth knowing: **a figure file has no import list of its own** — every
import it needs must be declared in `operation.dart`. Adding a figure that needs
a new type means adding that import at the top of `operation.dart`.

### 2.2 What the barrel does and does not export

`transforms.dart` is **not** exported. It is internal vocabulary; consumers get
`operation.dart`, `who.dart`, `params.dart`, `diagnostics.dart` and the domain.
Anything inside `lib/` that needs a transform imports it directly
(`compiler.dart` does exactly this for `normalizeWaveOffsets`).

---

## 3. The state model

### 3.1 Entity-primary, matrix-derived

`Formation` stores `Map<DancerId, DancerState>`. The matrix is a **projection**
computed on demand by `toMatrix()`. This is the single most consequential design
choice in the codebase:

- **Facing, number and waiting-out travel with the dancer automatically.** A
  figure moves a person; it does not have to remember to carry three other
  fields alongside the position.
- **Equality is over the projection**, so facing and waiting-out state are
  excluded from success comparison *for free* — they were never in the cell
  value. This is `architecture.md` §3.5 implemented by construction rather than
  by a comparison that remembers to skip fields.
- **The cost:** the map cannot structurally prevent two dancers sharing a cell.
  `toMatrix()` re-imposes that and **throws `FormationProjectionError`** on a
  collision or an off-grid dancer. The `Formation` factory calls `toMatrix()`
  eagerly and discards the result purely to validate.

> **Trap.** `FormationProjectionError` is a genuine *compiler defect* signal, not
> a dance error. If a figure can produce a collision from legal input, catch it
> in that figure's preconditions and return an `OpError` instead. Never let it
> reach the caller — and never wrap the fold in a `try` to make it go away.

### 3.2 Identity vs. state

| | Type | Changes during a dance? |
|---|---|---|
| couple letter + role | `DancerId` | **never** — safe map key |
| position, number, facing, waitingOut | `DancerState` | yes |

`DancerId.coupleIndex` is what `homeGrouping(id) = coupleIndex ~/ 2` reads, and
that is *home*, not *here* — the grouping a couple started the repetition in.
That distinction is load-bearing for the distance-named dancer sets (§6.3).

### 3.3 The cell encoding

`encodeDancer(id, number) = coupleBits | (number.bit << 2) | role.bits`, with the
couple id as a **one-hot** field from bit 3 up. One-hot means a couple's
contribution is stable regardless of set size (A is always 8). `decodeDancer`
validates one-hot-ness and returns `null` for anything malformed.

**Facing is deliberately absent from the encoding.** That is the mechanism
behind §3.5's equality rule.

---

## 4. The execution pipeline, in code

### 4.1 `compile(Dance)` — `engine/compiler.dart`

```
1. seed warnings   <- dance.warnings (parse-time) + _oneSidedHallWarnings (dance-level pre-scan)
2. refuse          <- _unperformedProgression: claims a progression, flags none
3. size + build    <- dance.requiredHandsFour, then dance.instantiate()
4. fold            <- for each figure:
                        a. figure.operation.lint(state)  -> warnings, stamped with opIndex
                        b. figure.apply(state, progressions:)
                        c. Err  -> return CompileError(opIndex, opName, error, warnings)
                        d. Ok   -> state = value; if flagged, progressions++
5. oracle          <- expected = dance.success.expected(input)      // from the INPUT
6. compare         <- normalizeWaveOffsets(state) == expected
                        ? Compiled(state)      // note: the RAW state, offsets and all
                        : Mismatch(actual: state, expected: expected)
```

Two subtleties worth internalizing:

- **The oracle is computed from `input`, never from `state`.** That independence
  is the entire value of the check. Any change that lets the oracle see the
  figure list turns the compiler into a tautology.
- **Settle-before-compare is a comparison rule, not a state change.** A dance may
  legitimately *end* in a wave, which sits at `{c0,c1,c3,c4}`. The comparison
  settles offsets so a correct dance is not failed for standing where it ends;
  the **reported** state is still the raw one. *(User-ruled.)*

### 4.2 `OperationInvocation.apply` — `engine/invocation.dart`

The progression flag lives here, not on `Operation`, because the same figure
progresses in one dance and not in another. Ordering:

```
operation.apply(...)                       the figure's own transform
  └─ if progression flag:
       applyEndNormalization(next, servedRound: waitingCouples(BEFORE))
       └─ if the figure also reached along the set: toggleBandPhase(...)
```

- **`servedRound` is read from the state the figure *started* in.** Only
  `slide_along_set` can tell the difference — it sets its own waiting-out state,
  and reading the served list afterwards would retire the couples it had just
  sent out.
- **A reaching figure that is also flagged advances twice.** Stepping out to the
  next neighbours is itself movement along the set; the flag names more.
  `slide_along_set` is exempt via `isItsOwnProgression`, because for it the
  displacement *is* the progression.

### 4.3 `Operation.apply` — `ops/operation.dart`

```
1. settle wave offsets      unless preservesWaveOffsets
2. reaching sets            if the figure names a cross-hands-four set:
                              - more than one distinct set -> unresolvableDancerSet
                              - exactly one -> _applyReaching (see §6.3)
3. checkPreconditions       -> Err short-circuits
4. perform                  the figure's transform (@protected)
```

> **Trap.** `perform` is `@protected`. A figure delegating to another figure must
> call the public `.apply(...)` so the delegate's own preconditions run. See
> `PassTheOcean`, which delegates to `FormShortWaves` exactly this way.

### 4.4 Sizing — `engine/sizing.dart` + `Dance.requiredHandsFour`

```
required = kBaseHandsFour (2)
         + success.hands4Contribution           // (count - 1) for progressions
         + Σ per-figure-instance hands4Contribution
         + max over figures of reachAfter(progressions-so-far)
```

Reach is a **max**, everything else **sums**. Reaching is transient — the figure
steps into another band phase and hands it back — so two figures reaching three
and two groupings need three of room, not five.

Reach is also **effective, not nominal**: the distance sets are anchored at the
start of the dance, so each progression that runs first closes the gap by one.
`_widestReach` walks the list in order counting progressions. *Airpants* is the
worked case — it progresses and only then names its next neighbours, so it sizes
to two hands four where a nominal reading would demand three and then refuse.

---

## 5. Geometry — the vocabulary figures are written in

`geometry/geometry.dart` is small and every function in it is load-bearing.

### 5.1 Bands, groupings, and waiting-out

- **`waitingOutRows`** — rows where *every* dancer present is marked out. An
  **empty** row is not a waiting row (a line of four empties the partner row of
  an active band).
- **`handsFourBands`** — pairs off the non-waiting rows top to bottom. Derived
  from **waiting-out state**, not couple numbers or orientation. Those earlier
  signals were only readable on a settled shape, and every state a figure sees
  is mid-dance; they were empirically unresolvable on intermediate states of
  both golden fixtures. This rule is **total** and formation-independent.
- **`groupingsDownTheSet`** — bands *plus* single-row waiting couples, ordered by
  top row. The diagonal figures are defined over **groupings**, because a
  waiting couple still participates as its own single-couple grouping. This is
  why `chain`'s pairing rule is stated in couple *number* rather than column.
- **`toggleBandPhase`** — the band grid has exactly two phases: aligned (bands
  from row 0, nobody out) and shifted (from row 1, ends stranded). Toggling is
  what a figure does when it carries dancers into the grouping beside them.
  Idempotent **only if no dancer moved in between**, since the marking is
  positional.

### 5.2 `travelDirection(formation, id)`

Which way "on down the set" points for one dancer. **Duple Improper:** by
number, 1s `+1` (down), 2s `-1`. **Becket:** by line and Becket sense — under CW
the c4 line shifts down, CCW mirrors.

Shared deliberately between the progression oracle and the distance-named dancer
sets, so "on down the set" cannot come to mean two different things.

### 5.3 Rings

`handsFourRing(band)` is the clockwise corner ring `[TL, TR, BR, BL]` — the
middle columns are never part of it. `rotateHandsFourRings(steps:)` applies
`new[O[k]] = old[O[(k + steps) % 4]]`; **positive is counter-clockwise**. Bands
whose four corners are not all occupied are **skipped**.

> **Trap.** `CircleDirection.left` is *clockwise* and `right` is
> *counter-clockwise* — the reverse of the naive reading. Both `CircleDirection`
> and `SpinDirection` expose `ringSign` so this is stated once per vocabulary
> rather than re-derived per figure.

---

## 6. The `who` system

### 6.1 Two predicates that are not interchangeable

| | Question | Note |
|---|---|---|
| `whoMatches(f, a, b, who)` | are **a and b** in this relationship? | relational; used to *pair* and to *validate* |
| `whoIncludes(f, id, who)` | is **id** one of these dancers? | unary; the relational sets are **total** — every dancer has a partner and a neighbour, so `partners`/`neighbors` include everyone |

> **Trap.** `whoMatches` deliberately **collapses all five neighbour sets** into
> one test. By the time a figure asks, `Operation.apply` has already re-banded
> the set, so your next neighbours are simply the neighbours you are standing
> with. Any check that needs the *distance* must ask separately — see
> `FormLongWaves._holds` and `crossHandsFourRefusal`.

### 6.2 `resolveWhoPairs` / `whoPairsInSet`

`resolveWhoPairs` pairs greedily within one band and marks dancers taken, so no
dancer is in two pairs. `whoPairsInSet` maps it over every band.

### 6.3 Reaching across hands four

A `WhoSet` with a non-null `distance` is cross-hands-four. `Operation.apply`
routes those through `_applyReaching`:

```
distance = who.distance! - progressions
distance == 0  ->  dance in place (the progression already delivered us)
otherwise      ->  phase = distance.isOdd ? toggleBandPhase(f) : f
                   crossHandsFourRefusal(...)      // sizing + relationship checks
                   perform(phase)
                   toggle back if we toggled
```

**Phase is fixed by the parity of the distance**, not by toggling from wherever
the set happens to be. The band grid has two phases, so only parity survives —
and deriving it from the distance is what lets a figure list *retrace*: a grand
right and left goes out to the fourth neighbours and comes back past the third
and second, and each must land in the phase its own label names.

`crossHandsFourRefusal` checks the relationship against each couple's
**`homeGrouping`**, not against where they are standing now. An earlier version
read the grouping off the formation and had to be abandoned — half way through a
grand right and left the third neighbours stand *one* grouping apart, not two.

---

## 7. Diagnostics

### 7.1 Errors — five kinds, and that is the whole set

| Kind | Means |
|---|---|
| `whoMismatch` | the stated `who` relation is not in position |
| `notAdjacent` | the pair have no hand to give (diagonal) |
| `unresolvableDancerSet` | the named dancers cannot be resolved to a figure this set can dance |
| `unsupportedParam` | representable, legal upstream, **not implemented here** |
| `unperformedProgression` | dance-level: claims a progression, flags none |

`unsupportedParam` is the deferral channel and it is used heavily and on
purpose. The param enums (`Direction` especially) are **deliberately wider than
any figure implements**, because "valid but out of scope" is only expressible if
the parser can *represent* the value. Narrowing the enums would collapse that
into "malformed input".

`unperformedProgression` is the only **dance-level** error and carries no figure
index.

### 7.2 Warnings — five kinds

| Kind | Raised by | When |
|---|---|---|
| `oneSidedHall` | engine pre-scan | a hall figure with no matching return |
| `hallFacingConflict` | figure lint | the line was already facing the other way along the hall; it turns around before travelling |
| `facingPrecondition` | figure lint | dancers are not facing the way the figure assumes |
| `anchorMismatch` | figure lint | a descriptive param contradicts the derived arrangement |
| `unrecognizedFormation` | **the parser** | unknown shape; falls back to `dupleImproper` |

Three rules about warnings:

1. **Facing is only ever a warning, never an error.** *(User-ruled, repeatedly.)*
   Dancers turn on the spot; a figure that would be danceable after a quarter
   turn must not be refused.
2. **`Operation.lint(Formation)` returns warnings without an `opIndex`** — the
   engine stamps it, because only the engine knows where the figure sits.
   Linting happens against the state the figure is **handed**, before it runs.
3. **`Dance.warnings` is the parse-time channel.** Everything else is an
   observation about a formation; `unrecognizedFormation` is a fact about the
   *notation*, already absorbed by the time a `Dance` exists. Carrying it on the
   `Dance` is what stops it being dropped between parser and result.

---

## 8. Anchors — a recurring pattern worth naming

Several params **describe** an arrangement the figure already derives. The ruled
treatment (*user-ruled on `form_long_waves`*) is:

> If it is there and it can eliminate ambiguity, **use it**. If it is present and
> impossible, treat it as a **compiler warning** — never let it move anybody.

Implemented on `FormLongWaves` (`whom`, `hand`) and `HeyForFour` (`pass2`). The
shape:

- the param is **nullable**, so "absent" stays distinct from any value — supplying
  a baseline default on the record's behalf would let the figure refuse itself
  for a contradiction of our own making;
- when the primary selector is absent, the anchor may **resolve** it, but only if
  exactly one candidate fits — never guess;
- when both are present and disagree, raise `anchorMismatch` and proceed with the
  primary selector;
- **an anchor is not in `dancerSets`.** It describes a hold; it does not reach for
  one. Listing it there would silently enlarge the set (`reachAfter`) for a
  figure where nobody travels.

---

## 9. Waves

Waves are the subtlest geometry in the codebase; `fundamentals.md` §8.5 is the
authority. Implementation notes:

- Offsets are a **sub-position within the side columns**, derived from facing —
  they are not a separate grid state and there is **no stored wave flag**.
- `Operation.apply` **settles offsets before every figure** except those with
  `preservesWaveOffsets` — which is exactly `balance`, `stand_still` and
  `rory_o_more`. The test is the figure's *premise* (is it danceable while
  standing in a wave?), **not** whether it happens to move anybody.
  `balance_the_ring` and `long_lines` move nobody and still settle, because
  neither shape is a wave.
- `RoryOMore` refuses on geometry it cannot express, using
  `unresolvableDancerSet` *(user-ruled: no new error kind)*.

> **Trap.** `waveOffsetColumn` returns **0 displacement for across-facing** and
> silently holds off-grid values. Both are deliberate no-ops in context and both
> are silent. Never reuse it without guarding for those two cases.

---

## 10. The IO boundary

`io/dance_json.dart` is the single place raw maps exist. Past it, everything is
typed.

- **`_registry`** maps `move` string -> builder. **46 entries.** A move not in the
  table is an error, never a skip: silently dropping a figure would change the
  dance and then compare the result against the oracle anyway.
- **`_Params`** helpers: `enumOr` (with default), `optionalEnum` (no default),
  `intOr`, `numberOr`, `boolOr`, `optionalString`, `optionalNumber`.
- **The `unspecified` sentinel** is handled centrally in `_first`, so *every*
  param gets it for free. Upstream is explicit that the set of params admitting
  it is a moving target, so enumerating them would drift.
- **Alias lists** let a wire spelling and our own name both be accepted
  (`['turn', 'circling']`, `['endFacing', 'face']`). `_blameKey` reports the
  spelling **the author actually wrote**, so a refusal points at a key that is
  really in their file.
- **`_parseFormation(raw, warnings)`** warns and falls back to `dupleImproper` on
  an unknown shape *(user-ruled)*, rather than refusing.
- **Aliases are resolved, not reimplemented.** `compendium_core` names three
  moves as aliases of others with parameters pinned — `see_saw` → `do_si_do`
  `{shoulder: left}`, `swat_the_flea` → `box_the_gnat` `{hand: left}`,
  `meltdown_swing` → `swing` `{prefix: meltdown}`. `_parseFigure` reads
  `contraTaxonomy.aliases` directly rather than keeping a table of its own, and
  the pinned params **overwrite** the record's: the pins *are* the alias, so a
  `see_saw` that also said `shoulder: right` would not be one. `supportedMoves`
  lists aliases alongside the registry.
- **Upstream defaults govern what an omitted parameter means** *(user-ruled)*.
  Where `compendium_core`'s taxonomy states a `defaultValue`, this parser
  supplies it — even where a better value is available and even where the
  taxonomy is wrong. See §15 for the one case where it is wrong.

> **`turn` is polymorphic — resolve it per move.** `taxonomy.md` rules **three
> meanings**: a rotation *amount* (`allemande`, `do_si_do`, `gate`, `mad_robin`,
> `shoulder_round`, `star_promenade`, `two_hand_turn`), a *spin sense*
> (`facing_star`, `orbit`, `poussette`, `promenade`), and a *direction*
> (`circle`, `zig_zag`).
>
> In code that third meaning resolves through **two different types**: `circle`
> reads `CircleDirection`, `zig_zag` reads `Hand` (it is a shoulder, not a ring
> sense — both happen to be `{left, right}`). So there are three *semantic*
> meanings but **four** Dart resolution targets, and picking the wrong type is a
> compile error rather than a silent mis-read. The builders carry a comment at
> each site.

---

## 11. Adding a figure — the checklist

Worked most recently on `hey` (`ops/figures/hey.dart`). In order:

1. **Get the rulings first.** Do not implement on conjecture. Derive the
   permutation independently, check it against any worked example you were
   given, and **ask** about anything the examples do not pin down. Model the
   *rule*, not the Duple-Improper evaluation of the rule — several figures read
   as a fixed same-role swap from a DI start and are nothing of the kind.
2. **New part file** in `ops/figures/`, or extend an existing family file.
3. **Register the `part`** in `ops/operation.dart`, and add any imports the new
   file needs *to `operation.dart`* (§2.1).
4. **Implement:** `name`, `dancerSets`, `hands4Contribution`,
   `progressionEligible`, `preservesWaveOffsets` (rarely), `checkPreconditions`,
   `lint`, `perform`, plus `==` / `hashCode` / `toString`.
5. **Defer honestly.** Any param value you have not modelled gets
   `unsupportedParam` with a message saying *why*, not a silent approximation.
6. **Register the builder** in `io/dance_json.dart` `_registry` + a `_buildX`.
7. **Tests** — a dedicated `test/ops/<figure>_test.dart` covering the
   permutation, every refusal, and the metadata; plus rows in
   `test/io/parser_defaults_test.dart` (registry defaults) and
   `test/ops/value_semantics_test.dart` (every param participates in equality).
   Both are **exhaustive-by-construction** harnesses and *will* fail until the
   new figure is added.
8. **Taxonomy entry** in `docs/taxonomy.md`, and delete its row from the Held
   table if it had one.
9. **Gate:** `fvm dart analyze`, `fvm dart format .`, `fvm dart test`.

---

## 12. Testing topology

| Path | Covers |
|---|---|
| `test/domain/`, `test/geometry/` | the state model and geometry primitives |
| `test/ops/<figure>_test.dart` | one figure or family, in depth |
| `test/ops/figure_families_test.dart` | shared behaviour across a family |
| `test/ops/operation_framework_test.dart` | `apply`, reaching, sizing, lint plumbing |
| `test/ops/value_semantics_test.dart` | **every figure**: `==`, `hashCode`, `toString`, and that each param participates |
| `test/io/parser_defaults_test.dart` | **every registry entry** and its defaults |
| `test/io/core_taxonomy_alignment_test.dart` | **every move**, cross-checked against `compendium_core`'s taxonomy |
| `test/io/known_upstream_defects_test.dart` | upstream taxonomy bugs we reproduce on purpose — **written to fail when fixed** |
| `test/golden/*.json` + `golden_dances_test.dart` | whole real dances, end to end |

**Golden dances are sourced, never authored.** *(User-ruled, absolute.)* The only
acceptable ingestion path from the legacy corpus is the CallersCompendium
adapter — `packages/compendium_core/lib/src/imports/callersbox_adapter.dart`.
**If any figure in a dance parses to `custom`, the dance is rejected outright**:
a custom figure can never compile, so a fixture containing one is not a test, it
is a guaranteed failure. Never hand-translate a dance record into a fixture.

---

## 13. Standing rules (carried across sessions)

1. **§1.1 governing rule.** When a legacy-project claim or an inherited doc
   contradicts this model, **assume this implementation is correct and ask.**
   Zero exceptions without explicit confirmation. The legacy project has a
   different data model and taxonomy; its answers are evidence, not authority.
   *(And check whether the legacy actually validated the thing it appears to
   implement — its ricochet hey is real code that its own docs list as
   unimplemented and its corpus filters out.)*
2. **Never implement on conjecture.** Read the code or doc in full; verify
   empirically with a probe before believing a derivation.
3. **Ask before recording a domain decision.**
4. **Facing is only ever a warning.**
5. **Progression is never inferred from state** — only the explicit flag.
6. **Never use the word "gypsy."** The figure is `shoulder_round`.
7. **`compendium_core` is consumed, never modified.** *(User-ruled.)* It owns
   the dance representation and the taxonomy; this package verifies
   choreography against them. An alignment mismatch is always fixed here — and
   where upstream is genuinely wrong, the defect is reproduced and pinned in
   `test/io/known_upstream_defects_test.dart` rather than papered over, because
   silently substituting a better answer means answering for a dance the record
   does not describe. Note this is a **narrowing of rule 1**: §1.1 still governs
   the *legacy .NET project*, but `compendium_core` is upstream, not legacy.
8. **Ask before pushing.**

---

## 14. Environment

- **`dart` is not on PATH — always `fvm dart`.** Dart 3.12.2, pinned via
  `.fvmrc` to Flutter 3.44.6 (the CallersCompendium integration target's
  toolchain — see `architecture.md` §7).
- **Python is not installed.** Use PowerShell.
- **Not a git repository.**
- `fvm dart format --output=none --set-exit-if-changed .` **does not write** — run
  `fvm dart format .` to apply.
- Coverage: `fvm dart test --coverage=coverage` then
  `fvm dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage\lcov.info --report-on=lib --check-ignore`;
  sum `LF:`/`LH:`. **Delete `coverage/` afterwards.** Floor is 80%; recent
  measurements sit around 96%.
- Probe a fixture end-to-end with `fvm dart run tool/probe_dance.dart <file.json>`
  — it prints per-figure state, bands and waiting-out rows, which is far faster
  than reasoning about a mismatch from the final matrix alone.

---

## 15. Current state and known debt

- **966 tests green; `analyze` clean; `format` clean.**
- **46 figures registered**, plus 3 upstream aliases resolved to them.
- **Schema-aligned with `compendium_core`** (`test/io/core_taxonomy_alignment_test.dart`).
  Every move id resolves upstream, every advertised move parses, and every
  default matches the taxonomy's. The check is deliberately mapping-free: it
  builds each figure from an empty param map and again from
  `Taxonomy.effectiveParams`, and compares the two Operations.
- ⚠️ **One reproduced upstream defect.** `form_short_waves`'s baseline defaults
  `centerHand: right` and `center: role2s` are mutually inconsistent from a
  duple-improper start, so a record omitting `centerHand` refuses itself with
  `whoMismatch`. Honouring it is user-ruled (rule 7); the issue is filed with
  the taxonomy's maintainer. `test/io/known_upstream_defects_test.dart` pins the
  behaviour and carries the instructions for backing it out once fixed —
  restore `optionalEnum` for `centerHand` in `dance_json.dart`; the figure
  already implements the `center`-derives-hand path.
- **`hey` has a full `docs/taxonomy.md` entry** and is out of the Held table.
- **No golden dance covers `hey` yet.** Neither corpus dance probed during its
  development discriminates between the candidate permutations (a following
  partner swing normalizes the difference away), so confidence rests on the
  derivation and the user's worked matrices rather than on the corpus. Sourcing
  one through the adapter is the open task.
- **Deferred, with worked examples still needed** (Held table): `promenade`,
  `butterfly_whirl`, `arch_and_dive` (progression half only), `revolving_door`,
  `slice`, `contra_corners`, `dolphin_hey`, `orbit` couple-`who` (the
  **meanwhile** mechanism), hall `ender` values `cozy`/`cloverleaf`/
  `threadNeedle`/`rightHandHigh`, and hall `moving` values `center`/`outsides`.
- **Deferred param values inside implemented figures** all raise
  `unsupportedParam` — notably diagonal and `along` `right_left_through`,
  `chain dir:along`, `swing where:center`, `long_lines goBack:false`, and
  `hey`'s partial lengths and non-`across` `dir`.
- **`hey` diagonals are blocked on a decision:** the user asked for them to follow
  diagonal `right_left_through`, which **is not implemented**. That figure must
  land first.
- `FormLongWaves.hand` **without** `whom` currently asserts nothing falsifiable.
  Deliberate and documented in its test; revisit if a record turns up that means
  something by it.
