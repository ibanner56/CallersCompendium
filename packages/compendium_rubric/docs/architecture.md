# ContraCompiler — Architecture (Execution Model)

> Companion to `fundamentals.md` (the domain state-model). This doc captures the
> **compiler design / execution model**. **The user defines all decisions**; this records
> what has been explicitly decided, plus clearly-labeled open questions.

---

## 1. Guiding Design Principle

**The core is effectively stateless and follows functional-programming principles.**

- **Formations are immutable values.** An operation never mutates its input; it returns a
  new formation.
- **Operations are pure functions.** Output depends only on the input formation and the
  operation's parameters — no shared/global/hidden state, deterministic.
- **Execution is a fold** over the ordered operation list, threading each operation's output
  as the next operation's input.
- **Errors are values.** A failed precondition returns an **error result** rather than a
  formation — a short-circuit exit from the execution loop (an `Either`/`Result`-style
  outcome), never an exception used for control flow.

---

## 2. Inputs (what the user supplies)

1. **Input formation** — the starting formation *type* (e.g. **Duple Improper**), not a
   pre-sized concrete matrix. The compiler instantiates the concrete matrix (see §3.1).
2. **Success condition** — a named criterion (e.g. **Single** = single progression) from a
   shared taxonomy. It defines the *expected* end state as a function of the input (§3.4).
3. **Ordered, parameterized operations** — a list drawn from a **known shared taxonomy**
   (the same taxonomy the user and compiler agree on). Each entry names an operation and
   carries its parameters (including the flag that marks an operation as *the progression*).

---

## 3. Compilation Pipeline

```
supplied: inputFormationType, successCondition, [op0, op1, … opK]

  ┌─ 3.1 PRE-SCAN ──────────────────────────────────────────────┐
  │ scan the operation list → determine how many hands four are   │
  │ required to evaluate coherently → instantiate the concrete    │
  │ input matrix in the requested formation at that size.         │
  └───────────────────────────────────────────────────────────────┘
              │  state ← concrete input formation
              ▼
  ┌─ 3.2 EXECUTE (fold) ─────────────────────────────────────────┐
  │ for op in [op0 … opK]:                                         │
  │     result ← op(state, op.params)     // pure                  │
  │     if result is Error:  return Error(op, reason)   // 3.3     │
  │     state ← result                    // output → next input   │
  │ actual ← state                                                │
  └───────────────────────────────────────────────────────────────┘
              │
              ▼
  ┌─ 3.4 REFERENCE ──────────────────────────────────────────────┐
  │ expected ← successCondition(inputFormation)                    │
  │   (computed independently from the ORIGINAL input;             │
  │    itself realistically an operation — see §3.4)               │
  └───────────────────────────────────────────────────────────────┘
              │
              ▼
  ┌─ 3.5 VERIFY ─────────────────────────────────────────────────┐
  │ actual == expected ?  → Compiled (success)                     │
  │                else   → Did-not-compile (mismatch)             │
  └───────────────────────────────────────────────────────────────┘
```

### 3.1 Pre-scan (set sizing) — additive contribution model

The required number of hands four is **not** fixed; it is computed by a static scan up
front. Each contributor carries a **pre-configured h4 contribution** that the pre-scan
**sums onto a base**:

- **Base:** the minimum needed to evaluate (neighbor interaction / single progression) =
  **2 hands four**.
- **Success condition:** its appearance may add h4 (e.g. a **double** progression adds room
  a single does not, contributing `count - 1`).
- **Each operation instance:** a parameterized operation can be pre-configured to expand the
  grid; the contribution is counted **per instance** (three expanding occurrences ⇒ +3, not
  +1).
- **The longest reach along the set:** a figure naming a distance dancer set
  (`nextNeighbors`, `thirdNeighbors`, …) needs room to reach that far. This term is a
  **maximum, not a sum** — see below.

```
required h4 = base
            + Σ(success-condition contribution)
            + Σ(per-instance operation contributions)
            + max(effective dancer-set reach over all figures)
```

**Why reach is a maximum while everything else sums.** Reaching is *transient*: a figure
naming a distance set is danced in another band phase and always hands that phase back
(taxonomy, "The neighbor-distance sets"). So a figure reaching three groupings along the set
needs three groupings of room to reach across, and a later figure reaching two dances inside
that same room — the two do not stack. Summing them would size the set larger than any dance
ever needs. Implemented at `Dance.requiredHandsFour` (`lib/src/engine/compiler.dart`), which
folds the reaches with `max` and passes a single term into `computeHandsFour`.

**Why the reach is *effective* rather than nominal.** The distance sets are anchored at the
start of the dance, so every progression that runs before a figure closes that figure's gap by
one grouping (taxonomy, "The distance sets are absolute"). Sizing therefore walks the figure
list in order, counting progressions as it goes, and asks each figure how far it *still* has to
travel — `Operation.reachAfter(progressions)`. A dance that progresses and only then names its
next neighbours is already standing with them and needs no extra room: *Airpants* sizes to two
hands four, where a nominal reading of the same record would demand three and then refuse.

> **Example.** A **double** progression (`+1`) together with a figure whose params also
> trigger grid expansion (`+1`) ⇒ **four hands four** total. *Sleepless at Pinewoods* is the
> worked case for the reach term: its grand right and left goes out to the fourth neighbours
> (`+3`) *before anything has progressed*, giving **five**.

The compiler then instantiates the concrete input matrix in the requested formation at the
computed size.

> **Open item (§6):** the per-item contribution values are carried by each operation and
> criterion (`hands4Contribution`, `reachAfter`) and are set as the taxonomy defines each
> figure, so this list grows with it.

### 3.2 Execute (the fold)

The operations are applied strictly in order; the output formation of operation *i* is the
input formation to operation *i+1*. Each operation is a pure function
`(Formation, Params) → Formation | Error`.

**Progression handling.** When an operation's parameters flag it as **the progression**,
then after the operation's own transformation the **end-normalization** is applied: the
couples in the top row and bottom row turn to face into the set, switch number, and
re-normalize (see `fundamentals.md` §10.2). Progression is only ever triggered by this
explicit flag — never inferred from state (`fundamentals.md` §10.1).

### 3.3 Preconditions (early error exit)

Some operations carry **preconditions**. If a precondition is not met, the operation returns
an **error result** instead of an output formation. This short-circuits the execution loop —
an additional exit case distinct from the normal completion path. No `expected`/`actual`
comparison is performed in this case.

### 3.4 Reference state (`expected`)

The expected success formation is computed **independently** from the **original input
formation** and the success condition: `expected = successCondition(inputFormation)`. The
success-criterion evaluator is **itself realistically an operation** — e.g. "single
progression of a Duple Improper dance" is expressible with the same operation vocabulary as
the sequence being verified. It does **not** depend on the user's operation list; it is the
independent oracle the list is checked against.

### 3.5 Verify (match)

The final `actual` formation is compared against `expected`. A match ⇒ the sequence
**compiles successfully**; a non-match ⇒ it **does not compile** (mismatch).

**Equality is strict over `position + role + number + couple identity`.** Tracked **facing
is the only excluded factor** — it is NOT a rigid part of success-state equality (two states
matching on position/role/number/identity are not disqualified by a facing difference).

> **Consequence.** The per-dancer bitmask encodes couple-id + number + role, and facing is
> stored *outside* the matrix (§ facing storage, `fundamentals.md` §6). So `actual == expected`
> is exactly **cell-by-cell decimal equality of the two matrices** — facing is naturally
> excluded because it never lived in the cell value.

**Wave offsets are settled before the comparison.** A dance may legitimately *finish* standing
in a wave, and a wave sits at `{c0,c1,c3,c4}` rather than on the side lines — so a literal
comparison would call a correct dance a mismatch purely because it had not yet stepped out of
the formation it ends in. The success oracle walks a **settled** set, so `actual` is projected
through the same §8.5.4 normalization the next figure would have applied to it, and the two are
compared on that footing. *(User-ruled.)*

The projection is **how the two are compared, not a claim about where the dancers stand**: both
`Compiled` and `Mismatch` still carry the **raw** final formation, so the reported end state is
the wave the dance actually left people in.

---

## 4. Result Outcomes

| Outcome | When | Carries |
|---|---|---|
| **Compiled** | all ops ran; `actual == expected` | (optionally) the final formation |
| **Mismatch** | all ops ran; `actual != expected` | `actual` vs `expected` for diffing |
| **Error** | an operation's precondition failed | offending op + reason; no final state |

> **Resolved (D8, §8.3):** the three outcomes are a sealed `CompileResult`;
> `Mismatch` and `CompileError` stay distinct, each with typed metadata.

---

## 5. Worked Example (end-to-end)

Input formation: **Duple Improper**; success condition: **Single** (single progression).
Pre-scan ⇒ **two hands four** (4×5).

```
Input : [[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B],[R1-C,0,0,0,L1-C],[L2-D,0,0,0,R2-D]]
J-out : [[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A],[L2-D,0,0,0,R2-D],[R1-C,0,0,0,L1-C]]
K-out : [[R2-B,0,0,0,L1-A],[L2-B,0,0,0,R1-A],[R2-D,0,0,0,L1-C],[L2-D,0,0,0,R1-C]]
L-out : [[L2-B,0,0,0,R1-A],[R2-B,0,0,0,L1-A],[L2-D,0,0,0,R1-C],[R2-D,0,0,0,L1-C]]
M-out : [[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A],[L2-D,0,0,0,R2-D],[R1-C,0,0,0,L1-C]]
N-out : [[R1-B,0,0,0,L1-B],[R1-A,0,0,0,L1-A],[L2-D,0,0,0,R2-D],[L2-C,0,0,0,R2-C]]  ← N flagged = progression;
                                                                                     top & bottom rows normalized
```

Independent reference for **Single** progression of the input:

```
Singl : [[R1-B,0,0,0,L1-B],[R1-A,0,0,0,L1-A],[L2-D,0,0,0,R2-D],[L2-C,0,0,0,R2-C]]
```

`N-out == Singl` ⇒ **the dance compiles without error.**

(Interior figures J–M are illustrative; nothing is inferred from the row labels. Note
M-out is the pre-progression state, and N applies the §10.2 end-normalization.)

---

## 6. Open / Deferred Decisions

- **Pre-scan contribution values** — the base + each operation's/criterion's configured h4
  contribution (mechanism decided in §3.1; per-item values set with the taxonomy).
- **Equality** — rigid over `position + role + number + couple identity`; facing is the only
  excluded factor, so the check is cell-by-cell matrix equality (§3.5). *(resolved)*
- **Result taxonomy** — final shape/metadata of Compiled / Mismatch / Error. *(§4)*
- **Operation & success-criterion schema** — the concrete parameter schema, incl. the
  progression flag, per-item h4 contribution, and how a success condition maps to its
  reference operation. *(with the taxonomy)*
- Domain-model open items continue to live in `fundamentals.md` §12.

---

## 7. Toolchain & Integration (D1 — resolved)

**Integration target:** `github.com/ibanner56/CallersCompendium` — a Dart/Flutter **pub
workspace** monorepo (`packages/compendium_core` pure-Dart core + `app` Flutter app). Only
its **toolchain/CI config** was inspected (`.fvmrc`, root `pubspec.yaml`,
`analysis_options.yaml`, `.github/workflows/_checks.yml`); its `lib/` and `AGENTS.md` were
deliberately **not** read, to keep our design direction uncontaminated (user's instruction).

**D1 decision:** develop ContraCompiler as a **standalone pure-Dart package** in this
directory, on the target's exact toolchain, **workspace-ready** to drop into `packages/`
beside `compendium_core` later.

**Toolchain contract to match (for clean integration + green Merge Validation):**

| Aspect | Value |
|---|---|
| Flutter | **3.44.6** (stable), single-sourced from `.fvmrc` via FVM |
| Dart | **3.12.x** (`environment: sdk: ^3.12.0`) |
| Core purity | **ADR-001: domain core must be Flutter-free** — our package takes **no** Flutter dep; tested with **`dart test`** (not `flutter test`) |
| Analyzer | strict workspace settings: `strict-casts`, `strict-inference`, `strict-raw-types`; `missing_required_param`/`missing_return` = error; each package layers its own lints |
| Format | `dart format --output=none --set-exit-if-changed .` must be clean |
| Tests/coverage | `dart test`; **≥80% line-coverage floor** on the core (generated `.g.dart`/`.drift.dart` excluded) |
| Deps | `--enforce-lockfile` discipline |

**Joining their workspace later (2-line change):** add `resolution: workspace` to our
package `pubspec.yaml` and list the package path under the root `workspace:` list.

> **Open sub-point:** final package **name/placement** at integration (new
> `packages/<name>` vs. a subsystem inside `compendium_core`). Dev name: `contra_compiler`.

---

## 8. Operation & Success-Criterion Model

### 8.1 Operations (D5 — resolved)

- Sealed **`Operation`** interface; each figure is a **typed, immutable class** with its
  parameters as typed fields (Dart 3 sealed types → exhaustive `switch`, no `dynamic`).
- Each operation exposes: a pure `apply(Formation) → Result<Formation>` (Formation | Error),
  a **precondition** check (→ Error), and **`hands4Contribution`** (may be computed from its
  own params, per D7).
- **Progression** is a **shared per-invocation flag** (not baked per figure) — the
  `progression` boolean in the JSON (§9). When set, the engine applies the §10.2
  end-normalization after the operation's own transform.
- A **name→constructor registry** at the serialization boundary (D9) maps external
  `{op, params}` into typed operation objects; the pure core never handles raw maps.
- Concrete per-figure parameter shapes come from the taxonomy (**D11**).

### 8.2 Success criteria (D6 — resolved)

- Sealed **`SuccessCriterion`** interface; each criterion is a typed class exposing
  `expected(Formation input) → Formation`, built by **composing canonical operations** (the
  independent oracle of §3.4).
- Progression-type criteria are **parameterized by count** (Single = 1, Double = 2,
  Triple = 3) so sizing and logic scale uniformly; leaves room for non-progression criteria
  (e.g. "return to start") later.
- Exposes its own **`hands4Contribution`** (D7). Uses the same **name→constructor registry**
  boundary as operations.
- The per-criterion *computation* (what a double/triple progression actually does) is domain
  content pinned down with the taxonomy (**D11**).

### 8.3 Result type (D8 — resolved)

- Sealed **`CompileResult`** with three cases carrying typed metadata:
  - `Compiled(finalFormation)`
  - `Mismatch(actual, expected)` — both retained for diffing.
  - `CompileError(kind, opIndex?, opName?)` — `kind` drawn from the error taxonomy (**D12**).
    The operation metadata is **nullable**: most refusals are owned by one figure and carry
    its index and name, but a **dance-level** refusal is owned by none. `unperformedProgression`
    — a dance that claims a progression while flagging no figure as performing it — is the
    only such kind today. The pair follows `Warning.opIndex`'s existing precedent for
    whole-dance observations.
- The execution fold threads a `Result<Formation, OpError>` (Either) per step and maps the
  outcome to `CompileResult` at the top level. Exhaustive `switch`; **no exceptions for
  control flow**. `Mismatch` and `CompileError` remain **distinct** exit cases.

---

## 9. Input Format & Entrypoint (D9 — resolved)

- **Canonical external format: JSON**, deserialized via the name→constructor **registry**
  (§8) into typed objects; the pure core never touches raw maps.

- **Operation object schema** (user-provided):

  ```json
  {"schemaVersion":1,"move":"pass_through","params":{"dir":"along","shoulder":"right","beats":4},"progression":true}
  ```

  | Field | Type | Meaning |
  |---|---|---|
  | `schemaVersion` | int | schema versioning |
  | `move` | string | operation/figure name — the **registry key** |
  | `params` | object | figure-specific parameters (sample keys: `dir`, `shoulder`, `beats`) |
  | `progression` | bool | the shared progression flag (§8.1); when `true`, end-normalization (§10.2) applies after the move |

- **Request envelope** — the input `formation`, the `success` criterion (+count), and the
  ordered `operations` array — follows the same JSON approach and versioning; its exact shape
  is finalized alongside the taxonomy (**D11**) / when P7 lands.
- **Library-first**: the pure-Dart core exposes the `compile` API the app calls; a **thin
  CLI** in `bin/` reads a JSON request → runs `compile` → prints the `CompileResult` (ideal
  for golden tests). A human-friendly **text DSL** may layer on later, parsing to the same
  typed objects.

### 9.1 Tolerance, and the parse-time warning channel

The parser reads four things — `title`, `formation.shape`, `progression`, `figures` — and
**ignores everything else**, because the record schema is owned elsewhere and grows over time.
The same reasoning extends to values it *does* read but does not recognize: an
**unrecognized `formation.shape`** is warned about and read as **Duple Improper** rather than
refused (`taxonomy.md`, `unrecognizedFormation`). The declared type fixes the starting matrix
and nothing more — it never tracks where the dancers stand (§3.2) — so a dance whose own
opening figures establish its arrangement is fully determined whatever the record called it.
A **missing** shape is still refused: a record that made no claim has nothing to fall back
from, and guessing would invent the starting matrix outright.

That reading is a diagnostic, and a diagnostic nobody reports does not exist. So `Dance`
carries a `warnings` list and `compile` seeds its result from it. This is the one warning
source that is **not** an observation about a formation: every other warning is either a
figure's own lint against the state it was handed or the engine's pre-scan of the figure list,
whereas this is a fact about the notation, already absorbed by the time there is a `Dance` to
compile.
