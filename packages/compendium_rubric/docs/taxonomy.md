# ContraCompiler — Operation Taxonomy (Figures)

> Companion to [`fundamentals.md`](fundamentals.md) (domain state-model) and
> [`architecture.md`](architecture.md) (execution model). Captures each operation
> ("figure") in the shared taxonomy. **The user defines each figure**; this doc records
> exactly what's decided, one figure at a time.

---

## Status

Building incrementally (**D11**), figure by figure. Preconditions per figure feed the error
taxonomy (**D12**). Scope: **duple** formations only (fundamentals §2).

---

## JSON invocation shape (recap — architecture §9)

```json
{"schemaVersion":1,"move":"<id>","params":{ },"progression":false}
```

`move` = the figure id / registry key · `params` = figure-specific · `progression` = shared
flag (when `true`, end-normalization per fundamentals §10.2 runs after the move).

---

## Per-figure definition template

Each figure below is captured with these fields:

- **`move`** — snake_case id / registry key (+ aliases)
- **summary** — one-line description
- **params** — each: name · type/enum · allowed values · default · meaning
- **preconditions** (D12) — input conditions that must hold, else `CompileError(kind)`
- **effect** — transform semantics: how positions / roles / numbers / facing change
- **normalization** — any post-effect facing-relative position normalization
- **facing** — facing each dancer is left with (concrete up/down/across, **flexible**, or unchanged)
- **h4 contribution** (D7) — default 0; param-dependent grid expansion if any
- **progression-eligible?** — may it carry `progression:true`, and any constraint

---

## Shared parameter vocabulary

Reusable params/enums accumulated across figures (filled in as figures are defined):

| Param | Type / values | Meaning |
|---|---|---|
| `beats` | int [0–16] | timing/duration; **carried by all figures**; no effect on end-state |
| `turn` | ⚠️ **polymorphic — resolve per move** (see below) | three distinct meanings across the taxonomy; never assume which one applies |
| `places` | int [1–10] | number of position-steps around a ring (effective = `places mod 4` for a 4-ring) |
| `who` | figure-specific value set | which dancer(s) the figure acts on — a role (`chain`: `role1s`/`role2s`) or a rich relationship set (`swing`: `partners`, `neighbors`, `ones`/`twos`, the distance sets, …) |
| `hand` | enum {`left`, `right`} | which hand is used (e.g. `chain` pull-by hand; `star` center hand); also sets rotation direction for `box_circulate` |
| `dir` | enum {`across`, `along`, `rightDiagonal`, `leftDiagonal`, …} | direction of travel (figure-specific value set) |
| `grip` | enum {`wrist_grip`, `hands_across`} | handhold style (e.g. `star`); no effect on end-state |
| `prefix` | enum {`none`, `balance`, `meltdown`} | optional lead-in to a figure (e.g. `swing`) |
| `face` | enum {`up`, `down`, `in`, `out`} | explicit finishing facing (e.g. `swing`); `in`/`out` are relative to the set per the dancer's side. **Ours**; upstream spells it `endFacing` |
| `where` | enum {`center`, `sides`} | where in the h4 a figure resolves (e.g. `swing`); with `face`, fixes the finishing position. **Ours only** — no upstream counterpart, so no record carries it |
| `shoulder` | enum {`left`, `right`} | which shoulder dancers pass (e.g. `do_si_do`); **right = clockwise, left = counter-clockwise** orbit |
| `circling` | number [0.25–2.5], step 0.25 | how far around an orbit goes (e.g. `do_si_do`); 1 = once around = back to place. **Ours**; on the wire this is `turn` — see the polymorphism note below |
| `amount` | number, rotation | rotation fraction — used **only** by `orbit`, which spends its `turn` slot on the direction |
| _(more added as figures are defined)_ | | |

### Spelling: this document's names vs what arrives on the wire

The upstream compendium's JSON is the **source of truth for the input schema**, and its canonical
spelling is **camelCase** — `rightDiagonal`, `nextNeighbors`, `endFacing`, `role1s`. Where this
document reads more naturally with a different name, the parser resolves both and normalizes to
the canonical one. There are three kinds of divergence, and it is worth keeping them apart:

| Kind | Examples | How the parser treats it |
|---|---|---|
| **Legacy spelling** — the same param, spelled another way | `right_diagonal` → `rightDiagonal`, `larks` → `role1s`, `1s` → `ones`, `partner` → `partners`, `neighbor` → `neighbors` | both accepted on input, normalized to the canonical key |
| **Our name for an upstream param** — a rename we made for clarity | `circling` (wire: `turn`), `face` (wire: `endFacing`) | canonical spelling read **first**, ours accepted as a synonym |
| **Ours only** — no upstream counterpart at all | `where` | always takes its default in practice, since no record carries it |

Two consequences worth stating plainly. Where the divergence is a **key** rather than a value —
`turn`/`circling`, `endFacing`/`face` — the parser takes the **first key present, canonical
first**, so a record carrying both is resolved by precedence rather than refused. That case is
unreachable from real data (the second spelling in each pair is ours, so no upstream record has
one), but it is a rule and not an accident. And an **ours-only param cannot be relied on for
fidelity** — `where` is readable so a hand-written fixture can set it, but a dance imported from
upstream will never exercise it.

The `unspecified` sentinel is handled once, centrally, rather than per figure: a key carrying it
is treated as **absent**, which is what it means. Upstream is explicit that the set of params
admitting the sentinel is a moving target, so enumerating them here would drift.

> Defaults are recorded per figure rather than here, because upstream's default and ours
> occasionally differ and the difference is only meaningful next to the figure it belongs to. The
> notable case is `chain.hand`, below.

### ⚠️ Polymorphic keys — resolve them per move

**Three keys carry different meanings on different moves**: `turn`, `endFacing` and `face`. Each
must be resolved from the move's own parameter kind; there is no global rule for any of them, and
assuming one is a live source of bugs. `turn` is the worst of the three and gets its own table
below; the other two are summarized here.

| Key | On | Means | Domain |
|---|---|---|---|
| `endFacing` | `swing` | the finishing **facing** | cardinal — {`up`, `down`, `in`, `out`} |
| `endFacing` | `courtesy_turn` | the dancer you finish **facing** | a **dancer set**, not a cardinal |
| `face` | `swing` | our name for the above | cardinal — {`up`, `down`, `in`, `out`} |
| `face` | `gate` | the finishing facing | cardinal, but a **wider set** — the four above **plus `along`** |

`endFacing` is the more dangerous of the two, because the two domains do not merely differ in
size, they are unrelated: a swing's is a compass direction and a courtesy turn's is a person.
There is no value that is valid for both, so a global rule would not silently mis-resolve — it
would fail outright — but it also means the key tells you nothing until you know the move.

`face` is the subtler one precisely because the domains *overlap*. `up`, `down`, `in` and `out`
mean the same thing on `swing` and `gate`, so three of the four cases work by coincidence under a
wrong global rule; only `face: "along"` distinguishes them, and it is valid on `gate` and an
unrecognized value on `swing`. Note also that `swing.face` and `gate.face` were named apart
upstream *deliberately*, to keep them separately addressable — which is why `swing` reads
`endFacing` first and treats `face` as our synonym, while `gate` reads only `face`.

#### `turn` — three meanings

`turn` carries **three different meanings** depending on the figure.

| `turn` means | CallersCompendium `ParamKind` | Moves |
|---|---|---|
| **Rotation amount** (how far) — number [0.25–2.5], step 0.25; 1 = once around = back to place | `rotation` | `allemande`, `do_si_do`, `gate`, `mad_robin`, `shoulder_round`, `star_promenade`, `two_hand_turn` |
| **Spin direction** — {`clockwise`, `counterclockwise`} | `spinDirection` | `facing_star`, `orbit`, `poussette`, `promenade` |
| **Direction** — {`left`, `right`}; `left` = clockwise, `right` = counter-clockwise | `choice` | `circle`, `zig_zag` |

Notes:

- The **amount** sense is CallersCompendium's baseline name for the concept our `do_si_do` calls
  `circling`. That synonym is **`do_si_do`'s alone** — no other move accepts `circling`, because
  no other move is documented here under that name.
- Two moves carry **both** senses in separate slots: `mad_robin` and `gate` each pair a `turn`
  *amount* with a separate `direction`. `orbit` is the mirror case — its `turn` is the direction
  and its **`amount`** holds the fraction.
- Where `turn` is a direction, it generally has **no net-position effect** for whole/half
  rotations (180° lands the same either way); it matters for quarters, which land in a wave for
  `do_si_do` and `allemande` and are deferred elsewhere.

---

## Error kinds (D12)

Precondition/error kinds accumulated as figures are defined:

| Kind | Raised when | Scope |
|---|---|---|
| `whoMismatch` | the stated `who` relation is not in position. Two cases: a `swing`'s relation isn't in swing position (e.g. a `sides` swing where the column-mate isn't the stated relation), **or** a distance dancer set names a grouping that isn't the one standing there — checked by home grouping, see "The neighbor-distance sets" | figure |
| `notAdjacent` | a trade figure requires the two interacting dancers to be **adjacent** — same row or same column — but they are diagonal, so neither can give the other a hand (e.g. `box_the_gnat`). This is about *where dancers stand*, not which way they face, which is why it survives the ruling below. **Renamed from `notFacing`**, which named the symptom rather than the cause and read as an exception to that ruling; the kind has never been serialized outside this repository | figure |
| `unresolvableDancerSet` | a `who` / pair selection cannot be resolved in the current arrangement (e.g. `turn_as_couples` where the pair isn't standing together; `down_the_hall` where the column pairs aren't complete) | figure |
| `unsupportedParam` | a parameter value is valid in the baseline but **deliberately not implemented** — the Held-table cases (e.g. quarter-turn `gate` / `two_hand_turn`, `down_the_hall` `moving: center`, the four held hall `ender`s) | figure |
| `unperformedProgression` | a dance claims a progression in its success criterion but flags **no figure** as performing it, so the progression could never happen. The **only dance-level** kind: it is owned by no single figure, so `CompileError.opIndex` and `.opName` are `null` (§10.1). Deliberately not inferred onto the last eligible figure — guessing which figure progresses is exactly the judgement the flag exists to record | dance |

> **⚠️ Ruled: facing is never fatal.** There was an `invalidFacing` kind here. There is no
> longer, and the removal is the point rather than a tidy-up: **no figure may refuse a dance
> over which way a dancer is facing.** Facing is the softest thing the matrix holds — many
> figures resolve it, several leave it deliberately undetermined (`Flexible`), and an imported
> record that omits an intermediate turn is still describing a dance that works on a real
> floor. A figure handed the wrong facing therefore **runs**, as though the dancers had turned
> to face the way it needs, and reports the **`facingPrecondition` warning** instead.
>
> The kind was deleted rather than left unreachable so that nothing in this table describes an
> outcome the compiler can no longer produce, and so that a later figure cannot quietly
> reintroduce a fatal facing check by reaching for a value that was still lying around.
> `test/ops/operation_framework_test.dart` asserts its absence.

**Warnings** (non-fatal; the compile continues):

| Kind | Raised when |
|---|---|
| `oneSidedHall` | a dance contains a `down_the_hall` without a corresponding `up_the_hall`, or vice versa. Non-fatal because the two need not be adjacent. Not raised when `facing: forwardThenBackward` completes the round trip within one figure. This is a **dance-level lint**, not a per-figure precondition — the first diagnostic in the taxonomy evaluated over the whole figure list rather than a single state transition. |
| `hallFacingConflict` | a hall figure is danced from a line of four that is already facing *against* the figure's travel facing, so the line turns around on the spot before travelling. The figure still runs and `facing` still wins; the warning reports the uncalled turn. **State-dependent**, so unlike `oneSidedHall` it is raised by the operation against the formation it is handed, and stamped with its index by the engine. |
| `facingPrecondition` | a figure is danced by dancers facing the wrong way for it (e.g. `pass_through dir:along` from dancers left facing across the set). The figure runs as though they had turned to it first; the warning reports the turn nobody called. Dancers whose facing is `Flexible` are skipped entirely — this figure is what resolves them, so there is nothing to report. **State-dependent**, raised by the operation and stamped by the engine. |
| `anchorMismatch` | a **descriptive anchor** contradicts the arrangement the figure produced — `form_long_waves` naming a `whom`/`hand` hold the wave it forms cannot offer. An anchor states a fact the figure does not need in order to run, so the figure runs unchanged and only the description is at fault. Anchors are still worth carrying: they **disambiguate** (a record naming the hold but not the pair has said everything needed) and they **corroborate** (a claim about the arrangement can be checked rather than trusted). **State-dependent**, raised by the operation and stamped by the engine. *(User-ruled.)* |
| `unrecognizedFormation` | a record declares a starting formation shape this compiler does not model (`"other"` is already in the corpus). Read as **Duple Improper** rather than refused: the shape vocabulary is owned upstream and grows, and the declared type does less work than its name suggests — it fixes the starting matrix and never tracks where the dancers stand (`architecture.md` §3.2), so a dance whose own opening figures establish its arrangement is fully determined regardless. **Raised at parse time**, not by any figure, and carried on the `Dance` so the compile it belongs to reports it — the first diagnostic that is not an observation about a formation at all. *(User-ruled.)* |

---

## The `who` vocabulary

`who` names the dancers a figure acts on. **Canonical spelling is plural, and roles are
numbered** — matching the form real dance records arrive in:

| Canonical | Means | Accepted aliases (parse boundary only) |
|---|---|---|
| `role1s` | the **Larks** | `larks`, `lark` |
| `role2s` | the **Robins** | `robins`, `robin` |
| `ones` | the **#1 couples** | `1s`, `one` |
| `twos` | the **#2 couples** | `2s`, `two` |
| `partners` | each dancer with their partner | `partner` |
| `neighbors` | each dancer with their current neighbor | `neighbor` |
| `prevNeighbors` | the couple **one grouping back** against the direction of travel — a **cross-h4** reference (see "Interaction scope") | `prevNeighbor` |
| `nextNeighbors` | the couple **one grouping on** in the direction of travel — a **cross-h4** reference (see "Interaction scope") | `nextNeighbor` |
| `thirdNeighbors` | the couple **two groupings on** — a **cross-h4** reference (see "Interaction scope") | `thirdNeighbor` |
| `fourthNeighbors` | the couple **three groupings on** — a **cross-h4** reference (see "Interaction scope") | `fourthNeighbor` |
| `everyone` | all four dancers of the grouping | `all` |

> **`ones`/`twos` are couple numbers; `role1s`/`role2s` are roles.** Two different concepts with
> uncomfortably similar spellings — `ones` is the couple that started the hands four as the #1
> couple, while `role1s` is every Lark regardless of number. The taxonomy already uses `ones`
> and `twos`, and they stay.

Aliases are resolved **at the JSON parse boundary**, so the pure core only ever sees canonical
tokens. Shadow sets (`shadow_*`) and corner sets (`firstCorners`, `secondCorners`) are not yet
specified — see the deferred items.

## Interaction scope (within-h4 vs. cross-h4)

By default, a figure is processed **entirely within each complete hands four**: it never
reaches another group, and any couple **waiting out** at the top/bottom of the set is simply
not involved (e.g. `circle`).

A figure reaches **outside its hands four** only when it:

1. **progresses** — carries the progression flag / moves couples on to new neighbors (§10 of
   `fundamentals.md`),
2. **interacts with future/past neighbors or shadows** — couples in adjacent groups met as the
   dance progresses (a *shadow* is a secondary cross-group partner; no figure uses it yet), or
3. **acts along a diagonal** — reaches into an adjacent grouping (e.g. `chain`
   `leftDiagonal` / `rightDiagonal`).

Only these **cross-h4** figures involve **waiting-out couples** (treated as single-couple
groupings — see `chain`), and only they can carry a non-zero **h4 contribution** (D7).
Within-h4 figures always contribute 0.

### The neighbor-distance sets (`nextNeighbors` and friends) — **ruled**

The distance sets are the one `who` family that names dancers the current hands four does not
contain. They resolve like this:

**Resolution.** A dancer's next neighbors are the **opposite-number couple in the grouping one
place on in their direction of travel** — the 1s look one grouping down the hall, the 2s one
grouping up. `thirdNeighbors` is two groupings on, `fourthNeighbors` three, and `prevNeighbors`
one grouping *back*. Direction of travel is §10.3.1's: Duple Improper couples share a row and
travel by **number**, Becket couples share a column and travel by **line**. This is the same
number-based, grouping-based shape the diagonal `chain` already uses.

### ⭐ The distance sets are **absolute**, and only `neighbors` is relative — **ruled**

A distance label names **the same couple for the whole dance**. `nextNeighbors` is fixed at the
start of the figure list and does not re-anchor as the set advances: the couple you called your
next neighbors before the progression is *still that couple* after it. What a progression
changes is not who they are but **how far away they are** — each one closes the gap by one
grouping.

So the distance a figure actually has to travel is

> **effective distance = *d* − (progressions already performed)**

and a set whose effective distance has fallen to **0** is not a reach at all: the progression
already delivered the dancer to them, so the figure is danced **in place**, with no phase shift
and no cross-hands-four check.

**`neighbors` is the single exception.** It always means whoever is in the current hands four,
which is why it needs no arithmetic — it carries no distance to subtract from.

*The worked example.* **Airpants** (`test/golden/airpants.json`) closes with

```
circle left 3  →  pass through along  (progression)  →  do si do nextNeighbors
```

and the record means "do si do with the couple you just progressed to". Under the absolute
reading its effective distance is `1 − 1 = 0`, the figure is danced with the couple already
standing there, and the dance lands. Under a *relative* reading — reach measured from wherever
the set happens to be standing — the same figure goes looking one grouping **past** the couple
it means, demands a third hands four to reach into, and is refused. Both readings agree on
every dance that never progresses before it reaches, which is why the corpus tolerated the
wrong one for as long as it did: *Sleepless*, *Becky's* and *Jet Lag* all do their reaching in
A1, before anything has progressed.

*Consequences worth stating.* Sizing is affected: `requiredHandsFour` measures each figure's
reach against the progressions that run **before it**, so a dance that progresses and only then
names its next neighbors needs no extra room at all (Airpants: 2 hands four, not 3). And the
`whoMismatch` check compares against the effective distance, so naming a *further* set instead
is still refused — which is what keeps the absolute reading distinguishable from no reading at
all.

**Reaching one grouping on is danced in the other band phase.** Rather than resolving pairs
across bands, the engine moves the band grid to its other phase and runs the figure there. The
grid has two phases — aligned to row 0 (`(0,1)`, `(2,3)`, …, nobody out) or shifted one row
(`(1,2)`, …, with the end rows stranded) — and standing with your next neighbors *is* the
shifted phase. Every band-scoped resolver inside the figure then pairs the right dancers
knowing nothing about any of this.

**Which phase: parity of the distance.** A figure naming a distance-*d* set is danced *d*
places from the phase it was handed, and **always hands that phase back**. The grid has exactly
two phases, so only `d.isOdd` survives: odd distances dance in the other phase, even distances
dance in the one they were given. Reaching is **transient** — you step out along the set to
meet them and you step back. The *d* here is the **effective** distance above, so a figure
whose reach has been spent by an earlier progression shifts no phase.

*Why parity, and not history.* An earlier rule toggled the phase and kept the toggle whenever
the transform had moved somebody. It works for a single reaching figure and cannot **retrace**.
*Sleepless at Pinewoods* (`test/golden/sleepless_at_pinewoods.json`) is the worked example that
settled it: its A1 is a grand right and left out to the fourth neighbors and back in, and the
figure at the far end is a *whole-turn* allemande, which moves nobody. Under the history rule
that figure's step out was undone, so the return leg walked onward instead of back. Under
parity the whole trace lands, and after the second `nextNeighbors` pull-by the formation is
byte-identical to the state after the first figure — everyone back beside their original
neighbor, ready for the A2 balance and swing.

| op | who | *d* | phase | A's row |
| --- | --- | --- | --- | --- |
| 0 | `neighbors` | 0 | 0 | r0 → r1 (pulls by B) |
| 1 | `nextNeighbors` | 1 | 1 | r1 → r2 (D) |
| 2 | `thirdNeighbors` | 2 | 0 | r2 → r3 (F) |
| 3 | `fourthNeighbors` | 3 | 1 | r3 (allemande H, whole turn, nobody moves) |
| 4 | `thirdNeighbors` | 2 | 0 | r3 → r2 (F) |
| 5 | `nextNeighbors` | 1 | 1 | r2 → r1 (D) |
| 6 | `swing neighbors` | 0 | 0 | r1, beside B |

**Reach does not stack.** Because reaching is transient, a figure list's required hands four
takes the **maximum** reach across its figures, not the sum. Sleepless needs five — the base
two plus the three the fourth neighbors reach — not the eleven a summing rule asked for.

**Precondition: they must be the couples they are named as.** A figure is only danced when the
couples the reaching phase stands together are genuinely that distance apart. This is checked
against each couple's **home grouping**, which is fixed by its letter: both starting formations
lay couple `2k` and couple `2k+1` out as hands four `k`, so home grouping is `coupleIndex ~/ 2`
and needs no stored state. If the arithmetic does not hold — asking for the next neighbors
straight off the start, say, where reaching stands B beside C — the figure is **refused**
(`whoMismatch`) rather than danced with whoever is to hand.

*Home, not here.* The check deliberately measures from where a couple **started**, not from
where it is standing. An earlier version read the grouping off the formation and had to be
abandoned: travel invalidates it, because half way through a grand right and left the third
neighbors stand *one* grouping apart, not two — the set has strung out along the hall and the
couples run off the ends have become their own single-couple groupings. A home grouping does
not move, so the same arithmetic holds at every point in a figure list, including on the way
back. There is no positional substitute: at Sleepless op 5 the set is, in the reaching phase,
indistinguishable from a set standing at home, and only identity separates them.

A set with fewer groupings than the distance reaches is refused too
(`unresolvableDancerSet`): there is nowhere to reach, and reaching would leave no active hands
four at all, turning the figure into a silent no-op. And a figure naming **two different**
distances is refused (`unresolvableDancerSet`): reaching puts the set into one phase, which can
satisfy one distance, so honouring both would mean dancing the figure in two places at once.

**The ends look after themselves.** The couples who travel off the end of the set are left
beside another couple of their **own** number — two 2s at the top, two 1s at the bottom, which
never happens in a set standing at home. Every neighbor-ish `who` requires a #1 with a #2, so
those bands simply produce no pairs and nobody moves. No special-casing is needed, and because
the reach is handed back they are not left marked out either.

**A progression flag advances the set a second time.** Stepping out along the set to dance with
a couple further along *is* movement along the set, and a progression flag on top of that names
more — so a flagged reaching figure finishes one phase past where an ordinary one would. The
couples at the ends collect their end numbers from the normalization and then step straight
back in beside whoever has arrived next to them. `slide_along_set` is the **exception** — the
slide *is* the progression, so flagging it names displacement the figure has already made
rather than asking for more, and it advances once. That difference is
carried by `Operation.isItsOwnProgression` rather than by naming the slide, so a future figure
that is likewise its own progression inherits it.

**h4 contribution** is the distance reached: `+1` for `nextNeighbors` and `prevNeighbors`,
`+2` for `thirdNeighbors`, `+3` for `fourthNeighbors` — exactly as a diagonal `chain`.
Contributions across a figure list are taken as a **maximum**, not a sum, because reaching is
transient.

**Every distance is now enabled**, each with a worked example on record. The forward sets come
from *Sleepless at Pinewoods*; `prevNeighbors` comes from *Becky's Brouhaha* and *Jet Lag*.

*Reaching backward needs no travel first — reaching forward does.* This asymmetry falls out of
the geometry rather than being arranged. The reaching phase bands `(1,2)`, `(3,4)`, …, which
pairs a 2s couple with the couple one row **below** it — and a 2s couple travels *up*, so the
couple below is always the one it has just left. Your previous neighbors are therefore in
position from a standing start, while your next neighbors are not: the set has to open up
first, which is why *Sleepless* leads with a pull by and the fixture in
`test/ops/next_neighbors_test.dart` is reached by a `pass_through`.

Both `prevNeighbors` dances reach it the same way and it is worth recording, because it is not
obvious that anything has happened: **balance & box the gnat with the neighbors, then pull by**.
The box the gnat swaps the pair and turns them to face each other; the pull by swaps them back
and lets them keep walking. Everyone finishes in their own row facing *the way they came*, so
the couple behind is standing in front of them — and the couples at the two ends of the set have
nobody behind them at all, fall outside every band in the reaching phase, and sit the figure out
without anything having to special-case them.

The sign is load-bearing, not decorative. Reaching stands the same two couples together
whichever direction is named, so only the sign distinguishes the meeting the choreographer wrote
from a mistake — naming `nextNeighbors` in either of those dances is refused, and naming
`prevNeighbors` against the *Sleepless* fixture is refused too.

---

## Held figures (reviewed, deferred to a directed conversation)

Figures present in the CallersCompendium taxonomy that we reviewed against the prior verifier and
**deliberately deferred** (the prior implementation was unreliable and would risk polluting ours).
To be defined later with worked examples.

> **Wave geometry is settled, and every wave figure is now built.**
> `form_short_waves`, `form_long_waves`, `form_a_long_wave`, `rory_o_more` and
> `pass_the_ocean` have all moved out of this table into full entries below — **no row here is
> wave-blocked any more**. The formation's ruled representation is `fundamentals.md` §8.5 (the
> facing-relative offset rule, side vs. centre long waves, concrete alternating facing,
> automatic normalization on exit, and no stored wave flag). The **quarter-turn landing is
> ruled too** — see `do_si_do` and `allemande` below, which dance a quarter into a wave. The
> remaining quarter-turn refusals in the figure entries are held for their **own** reasons (no
> direction token, no clean model, or a landing that is a line of four rather than a wave), not
> because the wave has no representation.

| Figure | Why held |
|---|---|
| `promenade` | Prior verifier conflates `promenade across` (vertical/Becket couples) with `right_left_through across` (horizontal couples) — different formations — and no-ops every other promenade (around / single-file / home). Multi-meaning; needs examples. |
| `butterfly_whirl` | Prior verifier reduces it to no-op + reorient to lark-left/robin-right facing in. No `who` param, so scope (which couples) and "facing in" resolution are under-specified; real choreography unconfirmed. Needs a directed conversation with examples. |
| `arch_and_dive` | Prior verifier makes it an unconditional row swap `(r0,c)↔(r1,c)` with **baked-in progression** and **ignores `who`**. **User-ruled: the unconditional row swap is correct** — this is the one place the prior verifier's reading governs over ours (§1.1 waived by explicit confirmation). Still held on the **progression** half: their baked-in progression conflicts with our explicit-flag model, and `who` needs a reading. Needs a worked example for those two points only. |
| `revolving_door` | **No verifier implementation** to consult. Net permutation ambiguous (Larks-swap-across-with-Robins-pivoting vs. a 180° half-star-promenade → diagonal swap); Compendium decomposition leans on `star_promenade` (undefined) + "drop off on far side". Needs a worked example. |
| `orbit` — couple `who` (**meanwhile**) | The move itself is **implemented** (see `orbit`); this row holds only the **couple-`who` (`ones`/`twos`) semantics**. A true 180° orbit carries a couple onto the *other* couple's cells, so it resolves only in combination with the centre figure — the **meanwhile** mechanism. *(Replaces the former `allemande_orbit` row: that fused move was **retired at Compendium v19** and its figures migrated to `meanwhile[allemande, orbit]`, so the name no longer exists in the taxonomy.)* The prior verifier also lists `^ones orbit` in its unsupported-patterns table. Revisit with the meanwhile conversation. |
| hall `ender` values — `cozy`, `cloverleaf`, `threadNeedle`, `rightHandHigh` | `down_the_hall` / `up_the_hall` are **implemented** (see their entries); this row holds only these four `ender` values, which raise `UnsupportedParam`. No verifier basis for any: there is **no handler at all** for `cozy`, `threadNeedle`, or `slidingDoors`; `TryCloverleaf` (FigureSimulator.cs:1224) is a **different, standalone** figure (an h4 ring rotation) and "cloverleaf turn single" sits in the unsupported-patterns list (:800); `TryRightHandHigh` (:4229) needs a named pivot dancer parsed from free text, and the structured ender carries no dancer param, so it is degenerate. Each needs a worked example. |
| hall `moving` values — `center`, `outsides` | Held with the above. They move only part of the line, leaving a shape that is **not a line of four**, so §8.1 does not cover the result. Revisit with a worked example. |
| `slice` | Alias of the Becket **shift/progression** (`TryShift`). Real mechanics live in the discarded grid/mirror model (`HandleBecketShift`); only a degenerate "swap rows" fallback survives. `return` (straight/diagonal/none) and `by` (couple/dancer) change the outcome, and it interacts with our progression/normalization machinery. Revisit with the progression conversation. |
| `contra_corners` | Verifier `TryContraCorners` is a **no-op** (no usable logic). Compendium models it as a **container with a free-text `custom` param** — arbitrary embedded turning figures, so no single fixed permutation. 16-beat variant-dependent sequence. Needs a worked example. |
| `dolphin_hey` | Hey variant (a couple travels as a unit — a "dolphin" — led by `whom`), so it needs a rule for how a *pair* occupies one place in the line of four that the base `hey` weaves along; `hey` itself is now **implemented** (see its entry) and no longer blocks this. Verifier has **no implementation** (in the unsupported-patterns list). Needs a worked example. |

---

## Figures

### `circle`

- **summary:** A clockwise or counter-clockwise rotation of the four dancers in each hands
  four.
- **params** (meets CallersCompendium baseline `{turn, places, singleFile, beats}`):
  - `turn` — enum {`left`, `right`}. `left` = clockwise, `right` = counter-clockwise.
  - `places` — int [1–10], baseline default 4. Position-steps around the ring; effective rotation
    is `places mod 4` (4 = full turn = identity).
  - `singleFile` — flag, default `false`. Dancers circulate the ring **single-file** rather than
    hand-in-hand (Compendium v27/v30: a "single file promenade … (circle, clockwise)"). **Styling
    only** — the ring positions and the rotation rule are unchanged.
  - `beats` — int [0–16]. Timing (universal); no effect on end-state.
- **preconditions:** none.
- **effect:** For each **complete** hands four (boundaries per fundamentals §10.3), treat its
  four occupied corner cells as a ring in clockwise order
  `O = [ (topRow,c0), (topRow,c4), (botRow,c4), (botRow,c0) ]` (TL→TR→BR→BL). Each dancer
  token — role, number, and couple-identity preserved — advances `places` steps along `O`:
  **clockwise for `turn=left`**, counter-clockwise for `turn=right`. With `p = places mod 4`:
  `turn=left ⇒ new[O[k]] = old[O[(k−p) mod 4]]`; `turn=right ⇒ new[O[k]] = old[O[(k+p) mod 4]]`.
  Middle columns (c1–c3) stay empty.
- **normalization:** none.
- **h4 contribution:** 0.
- **progression-eligible:** yes — when `progression:true`, the §10.2 end-normalization runs on
  the top/bottom rows after the rotation.
- **verified against:** Op1 (left/3), Op2 (right/2), Op3 (right/1 ≡ Op1), Op4 (left/4 = identity
  + progression) — both hands four, all four examples.
- **facing:** `circle` leaves each participating dancer in **Flexible** facing
  (fundamentals §6) — the following figure resolves it to up/down/across as it requires. (A
  same-operation `progression` still normalizes the end couples to concrete up/down per §10.2.)
  **A full turn is exempt:** `places mod 4 == 0` is the identity, so nobody is anywhere new and
  there is no new facing to resolve — the dancers keep what they had.

  > **This was drift until *Airpants*.** The contract was written here from the start but never
  > implemented: `circle` moved dancers and carried their *previous* facing forward. It went
  > unnoticed because most dances follow a circle with something positional that never asks
  > about facing, so the stale value was never read. `test/golden/airpants.json` circles three
  > places and then passes through *along* the set — the first record in the corpus to ask —
  > and was refused for a facing its dancers should never still have been holding. The
  > consumers had been written to the contract all along: `pass_through` and its family skip
  > any dancer whose facing is not concrete. Only the producers were wrong. Pinned by
  > `test/ops/ring_figures_test.dart`.
- **interaction scope:** entirely **within the hands four** — no cross-h4 interaction, so
  waiting-out end couples are never involved (see "Interaction scope").

### `chain`

- **summary:** A pull-by to a courtesy turn, trading places with another dancer.
- **params:**
  - `who` — enum {`role1s`, `role2s`} (legacy `larks` / `robins`). The role that chains across
    (the crossing dancers). Default `role2s`.
  - `hand` — enum {`left`, `right`}. The pull-by hand. Default `right`.

    ⚠️ **Upstream has no default here.** Its schema carries an `unspecified` sentinel and most
    records leave the hand unstated, so the value very often arrives absent. We substitute
    `right` rather than modelling the sentinel, which is safe only because the pull-by hand is
    recorded for fidelity and **has no end-state effect** — the chain trades the same dancers to
    the same cells either way. If a figure is ever added whose hand *does* move someone, this
    substitution stops being harmless and the sentinel has to be modelled properly.
  - `dir` — enum {`across`, `along`, `rightDiagonal`, `leftDiagonal`}. Direction of the chain.
  - `beats` — int [0–16]. Timing (universal).
- **preconditions (D12):** none that can refuse. `dir` describes the direction the chain
  travels, and the input facing is expected to match it — `along` → facing **up** or **down**;
  `across`, `rightDiagonal`, `leftDiagonal` → facing **into the set** (toward the opposite line:
  `across→` from c0/west, `across←` from c4/east). *(interpretation — to confirm)* A mismatch is
  reported as the **`facingPrecondition` warning** and the chain runs, per the ruling that
  facing is never fatal. A **Flexible** input facing (fundamentals §6) is not reported at all —
  it resolves to whatever the figure needs.
- **effect:** Chain trades `who`-role dancers by **couple number**, across **groupings**.
  - A **grouping** is a complete hands-four (fundamentals §10.3) **or** a **waiting-out couple**
    at the top/bottom of the set — each waiting couple participates as its own single-couple
    grouping. An h4 grouping has one #1 and one #2 `who`-dancer; a waiting-couple grouping has
    just one (of that couple's number).
  - Each **#2 `who`-dancer** swaps cells with the **#1 `who`-dancer** of:
    - `across` → the **same** grouping,
    - `leftDiagonal` → the grouping **above**,
    - `rightDiagonal` → the grouping **below**.
  - Role, number, and couple-identity travel with each dancer. If the needed partner grouping
    (or its #1 / #2 `who`-dancer) doesn't exist, the dancer **stays put** — e.g. a top
    grouping's #2 has nothing above (`leftDiagonal`); a bottom grouping's #1 has nothing below
    (`rightDiagonal`). Non-`who` dancers and un-paired `who`-dancers stay in place.
  - **Each dancer is swapped at most once — vital.** Iterate the **#2 `who`-dancers** only
    (the initiators); a dancer already involved in a swap is never swapped again. This is the
    invariant the original "only scan c0" rule enforced — in a chain-ready line the #2s sit in
    c0 and #1s in c4, so scanning c0 = iterating the #2s exactly once. The generalized
    invariant is **couple number**, which is what makes the waiting-out ends work (a waiting
    couple's `who`-dancer can sit in either column).
  - `hand` (left/right) does not change end positions (Op1 vs Op2).
  - **Verified against:** base Op1 (across/robins), Op2 (across/larks), Op3 (leftDiagonal),
    Op4 (rightDiagonal), and the waiting-out `leftDiagonal` example (couples B & E out at the
    ends).
- **normalization:** none — not required if implemented correctly. The chain's closing **courtesy
  turn** is a **rigid wheel**, so it *preserves* the couple's left/right relationship rather than
  imposing one: **the crossing (turned) dancer ends on the RIGHT, the stationary turner on the
  LEFT**, relative to the ending facing (§7). Lark-left/robin-right is the common case, not the
  rule — a `who:larks` chain correctly leaves the **larks on the right**, which a plain
  lark↔lark cell swap already produces (DI normalizes to up/down, so its larks already occupy the
  right-hand spots for the across facing). See `courtesy_turn` for the full invariant.
  - **Do not pair with a separate `courtesy_turn` op** — the turn is internal to this figure, and
    emitting both would double-count the figure and its beats.
- **facing (output):** dancers end facing **across** (into the set); can be nuanced later.
- **h4 contribution** (D7): `across` = 0, `along` = 0, `rightDiagonal` = 1, `leftDiagonal` = 1
  (per instance) — the +1 gives a diagonal room to reach the adjacent grouping at the ends.
- **progression-eligible:** yes.
- **`along`:** deferred — believed to occur only in four-facing-four dances (out of scope, §2).

### `star`

- **summary:** With the stated hand in the center, the four dancers rotate around the hands
  four in the direction they're facing.
- **params:**
  - `hand` — enum {`left`, `right`}. Which hand is in the center (sets the rotation direction).
  - `places` — int [1–10]. Position-steps around the ring; effective = `places mod 4`.
  - `grip` — enum {`wrist_grip`, `hands_across`}. Handhold style; **no effect on end-state**.
  - `beats` — int [0–16]. Timing (universal); no effect on end-state.
- **preconditions:** none — no required input facing (a **Flexible** input is accepted).
- **effect:** Identical to `circle`'s rotation, with `hand` selecting direction:
  - `hand=right` ⇒ **circle left** (clockwise): `new[O[k]] = old[O[(k−p) mod 4]]`,
  - `hand=left` ⇒ **circle right** (counter-clockwise): `new[O[k]] = old[O[(k+p) mod 4]]`,

  over the same clockwise corner ring `O = [ (topRow,c0), (topRow,c4), (botRow,c4), (botRow,c0) ]`
  with `p = places mod 4`. Role/number/couple-identity travel with each dancer; `grip` and
  `beats` do not affect the end state.
- **normalization:** none (same as `circle`).
- **facing (output):** **Flexible** (like `circle`) — resolved by the following figure, and for
  the same reason: a dancer part way round a star is still holding it. A full turn
  (`places mod 4 == 0`) is the identity and is exempt, exactly as `circle` is. Implemented
  alongside `circle`'s — see the drift note there.
- **interaction scope:** within the hands four — no cross-h4 interaction; waiting-out couples
  are never involved.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes — `progression:true` runs the §10.2 end-normalization after the
  rotation.

### `swing`

- **summary:** A couples' figure — in modified closed ballroom position the two dancers go
  **clockwise around each other** (walking or buzz step), finishing as a **normalized couple**.
- **params** (meets CallersCompendium baseline `{who, prefix, endFacing, beats}`; we add `where`):
  - `who` — which two dancers swing. **Default `partners`**, matching upstream. Rich value set:
    `partners`, `neighbors`, `role1s`, `role2s`, `ones`, `twos` (the last two typically swung
    **in the center**), and the distance sets `prevNeighbors` / `nextNeighbors` /
    `thirdNeighbors` / `fourthNeighbors`. Singular and role-name legacy spellings (`partner`,
    `neighbor`, `larks`, `robins`, `1s`, `2s`) are accepted and normalized. _(Shadows and
    first / second `corners` **deferred** — see the `who` semantics below.)_
  - `prefix` — enum {`none`, `balance`, `meltdown`}. Optional lead-in. **`prefix:meltdown` is the
    `meltdown_swing` alias.** (Baseline beats key off it: `none`→8, `balance`/`meltdown`→16.)
  - `where` — enum {`center`, `sides`}. Where the swing resolves; with `face`, fixes the
    finishing position. **Ours only** — no baseline counterpart.
  - `face` — enum {`up`, `down`, `in`, `out`}. **Finishing facing** ("the needed direction for
    the next figure"). `in`/`out` = into/out of the set (per the dancer's side); `up`/`down` =
    along the hall. **≡ the CallersCompendium baseline param `endFacing`** (same four tokens,
    baseline default `in`); the Compendium notes it is the same kind of value as the `gate`
    move's `face` and was named apart only to keep the two separately addressable. We accept
    `endFacing` as an input synonym for `face`.
  - `beats` — int. Timing (universal).
- **`who` semantics** (within a hands four `L1-x / R1-x / L2-y / R2-y`), canonical spellings:
  - `ones` = the #1 couple (L1, R1); `twos` = the #2 couple (L2, R2).
  - `role1s` = L1, L2; `role2s` = R1, R2. These *are* the same-role pairings — there is no
    separate `same_roles` value, and naming one would be an unrecognized value, not a synonym.
  - `partners` = same couple/letter (L1-A & R1-A; L2-B & R2-B).
  - `neighbors` = opposite role **and** couple **and** number within the h4 (L1-A & R2-B;
    L2-B & R1-A).
  - `prevNeighbors` = the neighbors one grouping **back** against the direction of travel;
    `nextNeighbors` / `thirdNeighbors` / `fourthNeighbors` reach one, two and three groupings
    **on**. See "The neighbor-distance sets" for how they resolve and why the sign matters.
  - `shadow_1..N` — ⚠️ **not implemented, and not a spelling the parser accepts.** Described
    here as domain knowledge only: the same-number, opposite-role dancer in the h4 above/below;
    bidirectional and **wraps** at the ends with the end number-flip (e.g. `L1-A`'s shadow is
    `R1-C`; wrapping the top also makes `R2-B` a shadow). It needs a worked example the way the
    distance sets did before it can be enabled.
- **preconditions — `who` is a precondition (not the pairing):** the swing pairs whoever is
  physically in swing position; `who` validates their relationship, else
  `CompileError(whoMismatch)`.
  - **`where:sides`:** each dancer must already be **on the same side (column) as their `who`
    dancer** (its column-mate is the `who`-relation). Ex: with column-mates = neighbors,
    `who:partner` **fails**, `who:neighbor` passes.
  - **distance sets** (`nextNeighbors`, `thirdNeighbors`, `fourthNeighbors`, `prevNeighbors`):
    **distinguished, and enforced.** The engine checks the named distance against the couples
    actually standing together, using **home grouping** — `coupleIndex ~/ 2`, which the starting
    formations guarantee and which travel cannot invalidate — so naming the third neighbors when
    the second are in front of you is `whoMismatch`, not a silent wrong answer. See "The
    neighbor-distance sets".

    Within the *current* h4 the invariant still holds: **no one swings with someone outside the
    hands four they are standing in.** Reaching a distance set moves the band grid first, so the
    figure still runs inside a band — it is just a different band.
  - **shadows:** not implemented; see the `who` semantics above.
  - **`where:center`:** precondition depends on alignment (aligned / not-aligned) — _PENDING_.
- **core rule:** a swing is a **normalizing figure** — the swinging pair(s) finish
  **lark-left / robin-right relative to `face`** (§7 geometry). Placement is set by
  `where` × `face`; `who` selects the pair(s).
- **effect — `where: sides`** (verified). Pairs = the two **column pairs** (the c0 pair and the
  c4 pair) — whoever is physically on each side swings; `who` only validates their relationship
  (a precondition, above) and does not change placement. Each pair normalizes
  lark-left/robin-right per `face`. Base input `[[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]]`,
  `who:neighbor`:
  - `face:in` → `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]` — each pair stays in its column,
    stacked; normalized to across-**in** (c0 faces east, c4 faces west).
  - `face:out` → `[[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]]` (= input) — across-**out**.
  - `face:down` → `[[R1-A,L2-B,0,R2-B,L1-A],[0,0,0,0,0]]` — a **line of four** in the **top**
    row; c0-pair at c0/c1, c4-pair at c3/c4 (c2 empty); lark-left/robin-right rel. down.
  - `face:up` → `[[0,0,0,0,0],[L2-B,R1-A,0,L1-A,R2-B]]` — line of four in the **bottom** row;
    lark-left/robin-right rel. up.
- **effect — `where: center`** (partly deferred; depends on input alignment). Base input
  `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]`:
  - **dancers aligned (both swingers already in one row)** — e.g. `who:1s` (the 1s in r1):
    swing in place → **same row + normalization** rel. `face`; the other couple is unchanged.
    - `face:up` → `[[L2-B,0,0,0,R2-B],[L1-A,0,0,0,R1-A]]`
    - `face:down` → `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]`
    - `face:in` → N/A (not meaningful) · `face:out` → **deferred** (context-dependent).
    - _Note (flagged, not implemented):_ if the following figure is a **line of four** (with
      these dancers, or the next h4's when `progression:true`), the up/down result is finessed
      into the `sides` line-of-four form. **The line-of-four side of this is now settled** —
      see §8.1 of `fundamentals.md` and `down_the_hall`: the hall figures **gather** a non-line
      input using this same column-pair rule, so a `where:center` result that is not already a
      line is simply gathered by the following figure. What remains open here is only the
      `where:center` placement itself.
  - **dancers not aligned (swingers diagonally opposite)** — e.g. `who:larks`: highly
    context-dependent on the following figure — **largely deferred**. For now: `face:out` →
    dancers stay put `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]` (placeholder, known-incomplete);
    `face:in` → N/A; `face:up` / `face:down` → deferred.
- **normalization:** yes — lark-left / robin-right relative to `face` (the core rule above).
- **facing (output):** the concrete **`face`** value (up/down/in/out) — **not Flexible**.
- **interaction scope:** within the **current hands four** — a swing always resolves inside it
  (invariant: no one swings with someone outside the hands four they are standing in). A
  distance-set `who` does not break that invariant: the band grid moves first, so the figure
  still runs inside a band. The unimplemented cross-h4 labels (`shadow_*`) are choreographic and
  are set up by prior positioning, not a reach outside during the swing itself.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (a swing may be marked `progression:true`).
- **forward ref:** a **line of four** is a formation/figure to be defined later; the `sides`
  up/down outputs above are its swing-produced form.

### `do_si_do`

- **summary:** Facing someone, walk forward passing the given shoulder, step to the side, and
  fall back to place — the two dancers orbit each other; a full circle returns to place.
- **params** (meets CallersCompendium baseline `{who, shoulder, turn, beats}`; the wire key is
  `turn` and `circling` is our name for it — see "Spelling", above):
  - `who` — **same value set as `swing`** (`partners`, `neighbors`, `ones`/`twos`,
    `role1s`/`role2s`, and the distance sets; shadows and corners deferred). Acts as a
    precondition.
  - `shoulder` — enum {`left`, `right`}. Which shoulder dancers pass (sets the orbit direction).
    **`shoulder:left` is the `see_saw` alias** (CallersCompendium `MoveAlias` `see_saw` →
    `do_si_do` with `pinnedParams: {shoulder: 'left'}`); a left-shoulder do si do, same effect.
  - `circling` — number in **[0.25 .. 2.5], step 0.25**. How far around the orbit goes
    (**1 = once around = back to place**).
  - `beats` — int. Timing (universal).
- **preconditions:** `who` is validated (must be a valid relation), but **more relaxed than
  `swing`** — the `who` dancer **may be in a different column** (no same-column requirement).
  You conceptually face your `who`, but that is **not rigidly enforced** (no hard facing
  prerequisite). Precise checks _PENDING_ (with examples).
- **effect (by `circling`):** the two `who` dancers orbit their shared midpoint:
  - **whole `circling` (1, 2)** ⇒ **no-op / identity** (full orbit(s) back to place).
  - **half `circling` (0.5, 1.5, 2.5)** ⇒ the two `who` dancers **swap cells** (role / number /
    couple-identity / facing travel with them). `shoulder` irrelevant (180° lands opposite
    either way).
    - Examples — input `[[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]]`, `circling:1.5`:
      `who:neighbor` → `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]` (column-mates → vertical swap);
      `who:partner` → `[[L1-A,0,0,0,R1-A],[R2-B,0,0,0,L2-B]]` (different columns → cross-column
      swap, which do si do permits).
  - **quarter `circling` (0.25, 0.75, …)** — **along the set only** (across-the-set quarters are
    **deferred**). The along-the-set (same-column) pair rotates **90°** about its midpoint and
    lands as a **wave of four** — see `docs/fundamentals.md` §8.5.1 for the canonical grids:
    - **rows never change.** A quarter turn slides each dancer one column toward the centre of
      the set; it does not collapse the pair into a single row. Two dancers per row with a
      one-column offset between the rows is what makes the shape a **wave**; emptying one row
      would make it a **line of four**, which is a different figure.
    - `shoulder: right` builds the **canonical wave** — the role2s take the centre cells
      (c1/c3) and the outer pair keeps the long lines. `shoulder: left` builds its **mirror**.
    - **¾ is a half turn and then the same quarter** — the handedness is *not* mirrored. The
      half-turn swaps the couples between rows first, so the **other role** ends up in the
      centre. `¼R ≠ ¾L`.
    - **the wave owns the facing** (§8.5.1): every dancer takes the wave's resting facing for
      the row they land in — top row **down**, bottom row **up** — which overrides do si do's
      usual facing preservation.
    - Examples — input `[[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]]` (facing shown `(u)`/`(d)`):
      **¼ right** → `[[0,R1-A(d),0,0,L1-A(d)],[L2-B(u),0,0,R2-B(u),0]]`;
      **¾ right** → `[[0,L2-B(d),0,0,R2-B(d)],[R1-A(u),0,0,L1-A(u),0]]`;
      **¼ left** → `[[R1-A(d),0,0,L1-A(d),0],[0,L2-B(u),0,0,R2-B(u)]]`.
- **placement rule (lines/waves across):** a **wave** is a line of four with alternating facing,
  carried in the matrix as **two dancers per row** with the rows offset by one column (§8.5.1).
  This is distinct from the single-row collapse the `swing` line-of-four rule describes.
- **normalization:** none — do si do is **not** a normalizing figure (unlike `swing`).
- **facing (output):** **preserved** (unchanged) — dancers keep their original direction. Input
  facing need not rigidly match `who`. **Exception:** the quarter/three-quarter case lands in a
  wave, and the wave imposes its own resting facing (§8.5.1).
- **interaction scope:** within the current h4 (like `swing`), pending cross-h4 `who` handling.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes.

### `allemande`

- **summary:** With the stated hand/forearm, the two dancers take hold and turn around each
  other by `turn` full-turns; the hand sets the direction. Like `do_si_do`, but the pair
  **turns** (rather than sliding), so facing rotates with the turn.
- **params** (meets CallersCompendium baseline `{who, hand, turn, beats}`, progression-capable):
  - `who` — dancer set (our `who` vocabulary; baseline default `neighbors`). A **precondition**,
    like `do_si_do`.
  - `hand` — enum {`left`, `right`}. Which hand/arm is given; **right = clockwise, left =
    counter-clockwise**. (Doesn't change whole/half end positions; sets direction for the
    quarter/wave case.)
  - `turn` — rotation number **[0.25 .. 2.5], step 0.25**, default `1.0`. (Same concept as
    `do_si_do`'s `circling`; baseline names it `turn`.)
  - `beats` — int, default 8.
- **preconditions:** `who` validated (relaxed like `do_si_do` — the `who` dancer may be in a
  different column); no rigid input-facing requirement.
- **effect (by `turn`):**
  - **whole (1, 2)** ⇒ **identity** (position) and **facing unchanged**.
  - **half (0.5, 1.5, 2.5)** ⇒ the two `who` dancers **swap cells**, and each dancer's facing
    becomes the **opposite** (in↔out, up↔down). Role/number/couple-identity travel with them.
  - **quarter (0.25, 0.75, …)** ⇒ **along the set only**; forms a **wave of four** exactly as
    `do_si_do`'s quarter does, with `hand` playing the role of `shoulder` — `hand: right`
    builds the canonical wave, `left` its mirror, and ¾ is a half turn followed by the same
    handed quarter (so the other role ends in the centre). Across-the-set quarters are
    **deferred**.
- **normalization:** none — not a normalizing figure.
- **facing (output):** per the rotation-facing principle (CallersCompendium `gate_facing`): a
  turn-in-place figure ends **unchanged on a full turn, opposite on a half turn**. On a quarter
  the **wave owns the facing** — every dancer takes the wave's resting facing for the row they
  land in (§8.5.1), overriding the rotation. A **Flexible** input stays Flexible on whole and
  half turns (opposite of undetermined is undetermined).
- **interaction scope:** within the current hands four (like `do_si_do`).
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes.
- **vs. `do_si_do`:** do_si_do preserves facing (dancers slide without turning); allemande turns
  the connected pair, so facing follows the rotation (full unchanged / half opposite).
- **sources:** ContraDanceVerifier `DoAllemande` (halfTurns→swap); CallersCompendium taxonomy
  `allemande` MoveDef + `gate_facing` (rotation-facing principle).

### `petronella`

- **summary:** All four dancers move **one place to the right** around the hands four (a
  petronella turn / spin). Mechanically identical to **`circle` right, 1 place**.
- **params** (meets CallersCompendium baseline `{balance, beats}`):
  - `balance` — flag, default `true`. A balance lead-in; **no end-state effect** (like `swing`'s
    `prefix:balance`).
  - `beats` — int, default 8 (baseline: 8 when `balance`, else 4).
- **preconditions:** none.
- **effect:** identical to `circle` with `turn:right, places:1` — over the corner ring
  `O = [ (topRow,c0), (topRow,c4), (botRow,c4), (botRow,c0) ]`, `new[O[k]] = old[O[(k+1) mod 4]]`
  (each dancer advances one place, counter-clockwise-from-above). Role/number/couple-identity
  travel with each dancer. **Does not** form a wave.
  - Example — input `[[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]]` → `[[L1-A,0,0,0,R2-B],[R1-A,0,0,0,L2-B]]`.
- **normalization:** none.
- **facing (output):** **Flexible** (resolved by the following figure) — inherited, not
  restated: this figure is expressed as `circle(right, 1)`, so it gets the ring-rotation facing
  contract from `circle` rather than duplicating it.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** **yes** (a per-invocation flag; D5). *Note: CallersCompendium marks
  `petronella` `progressionCapable:false`, but our model lets any figure carry the progression
  flag, and a user-supplied Becket dance demonstrates petronella carrying the progression.*
- **sources:** ContraDanceVerifier `TryPetronella` (rotate one place); CallersCompendium
  taxonomy `petronella` MoveDef.

### `right_left_through`

- **summary:** Two facing couples pass through and courtesy-turn, trading with the couple across
  — each dancer ends swapped with their **diagonally-opposite** dancer.
- **params** (meets CallersCompendium baseline `{dir, beats}`):
  - `dir` — direction, default `across`. (`along` / diagonals deferred — see note.)
  - `beats` — int, default 8.
- **preconditions:** the two couples must be set up facing across (the standard R&L-through
  formation). Precise checks _PENDING_ (a same-side variant like the `with partner` column
  requirement may be added later).
- **effect (`dir:across`):** **diagonal swap** across the two rows of the hands four —
  `(r0,c0) ↔ (r1,c4)` and `(r0,c4) ↔ (r1,c0)`. Equivalent to "the two larks swap + the two
  robins swap, then courtesy-turn normalize." Role/number/couple-identity travel with each
  dancer.
  - Example — input `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]` → `[[L1-A,0,0,0,R1-A],[R2-B,0,0,0,L2-B]]`.
- **normalization:** the courtesy turn yields lark-left/robin-right relative to the ending
  facing (consistent with the diagonal-swap result above) — but as the **common case, not an
  imposed rule**. The turn is a **rigid wheel** contributing an unconditional row swap within
  each column; it *preserves* handedness, so **the turned dancer ends on the RIGHT and the turner
  on the LEFT** (§7). A couple arriving cleanly inverted ends inverted. See `courtesy_turn`.
  - **Do not pair with a separate `courtesy_turn` op** — the turn is internal to this figure.
- **facing (output):** **into the set** (across) — dancers face back across after the courtesy
  turn.
- **interaction scope:** within the hands four (for `across`).
- **h4 contribution** (D7): 0 for `across`.
- **progression-eligible:** no (baseline `right_left_through` is not progression-capable).
- **`along` / diagonals:** deferred — the baseline `dir` vocabulary allows them, but their
  effect (and any h4 contribution for diagonals) is not yet defined here.
- **sources:** ContraDanceVerifier `TryRightAndLeftThrough` (same-role swaps + courtesy-turn
  normalize); CallersCompendium taxonomy `right_left_through` MoveDef.

### `slide_along_set`

- **summary:** Couples slide **sideways along the set** to the next position — the explicit
  Becket **column-slide** progression (as opposed to the default DI-style progression).
- **params** (meets CallersCompendium baseline `{slide, beats}`):
  - `slide` — enum {`left`, `right`}, default `left`. Direction couples travel along the set.
  - `beats` — int, default 2.
- **preconditions:** both lines standing along the sides of the set. A dancer in a centre
  column is in a line of four (fundamentals §8.1), which has no side lines to slide, and the
  figure is refused (`UnresolvableDancerSet`). Note the figure is otherwise **total**: waiting
  couples slide with everyone else, and the figure is legal whichever phase the band grid is
  in.
- **effect:** each side line shifts **one row** in the direction that line's dancers' own named
  hand points. Facing across the set, the west line's left is up the hall and the east line's
  left is down, so `slide:left` moves the **west line up and the east line down** — the two
  lines counter-rotate, which is what carries each dancer to the next couple along.
  `slide:right` is the exact mirror, and a left followed by a right restores the set exactly.
  A dancer pushed past an end **rounds it**, reappearing in the *other* line in that same end
  row. This happens on every slide, flagged or not; only *number* and *facing* wait on the
  progression flag.
- **re-banding:** moving everyone one row also moves where the hands-four boundaries fall. The
  band grid has two phases — **aligned** to row 0 (`(0,1)`, `(2,3)`, …, nobody out) or
  **shifted** one row (`(1,2)`, …, top and bottom rows stranded) — and **a slide toggles
  between them**. So a slide from a settled set sends both end rows out, and a slide from a set
  that already has couples out at the ends brings them **back in**: they do not trade places
  with a fresh pair going out, they become a hands four with whoever has just arrived beside
  them. The same toggle is what a figure danced with the `nextNeighbors` uses; both are
  `toggleBandPhase`.
  > ⚠️ **The phase rule is load-bearing and held at moderate confidence.** It reproduces all
  > three worked examples on record, but it is an inference from them rather than something the
  > source states. If a dance involving slides ever lands wrong, **investigate here first**.
- **normalization:** out-ness is decided by the phase, **not** by who happens to arrive at an
  end — and the pair stranded at an end is frequently not a couple. Per §10.2.1 a non-couple
  end row is not renumbered, so a slide can leave dancers standing out without giving them an
  end number. Number and facing change only when a whole couple collects at an end **and** the
  slide carries the progression flag. Interior couples keep their vertical arrangement.
- **facing (output):** unchanged by the slide itself (Becket side arrangement preserved);
  rewritten only by the progression's end-normalization, for a whole couple at an end.
- **interaction scope:** cross-h4 (moves dancers between groupings — this is a progression
  figure).
- **h4 contribution** (D7): **+1** (needs room to slide to the adjacent grouping).
- **progression-eligible:** yes — this is the figure that carries the Becket column-slide
  progression. **This is the one known figure where a Becket progression column-slides instead
  of progressing DI-style** (fundamentals §10.6); other single-file-promenade-like figures TBD.
- **its own progression:** the slide **is** the progression, so a progression flag on it names
  displacement the figure has already made rather than asking for more, and the set advances
  **once**. This is what separates it from a figure danced with the `nextNeighbors`, which
  re-bands *and then* progresses ("The neighbor-distance sets", above). Carried by
  `Operation.isItsOwnProgression` rather than by naming the slide.
- **sources:** user (params + role as the explicit slide progression); CallersCompendium
  taxonomy `slide_along_set` MoveDef (`slide` left/right default left, `beats` 2).
- **verified:** a `Becket CW` dance whose only figures are progression-flagged slides compiles
  clean against the independently derived §10.6 net-displacement oracle at both `count: 1` and
  `count: 2`, so **`slide:left` ↔ the CW sense** and `slide:right` ↔ CCW.

### `balance`

- **summary:** A step forward-and-back (balance) with the `who` dancers — a **positional
  no-op**. Distinct from the `balance` *prefix* on `swing` and the `balance` *flag* on
  `petronella`; this is the standalone figure.
- **params** (meets CallersCompendium baseline `{who, hand, beats}`):
  - `who` — dancer set, default `neighbors`. Descriptive (whom you balance with); **no
    end-state effect**.
  - `hand` — handedness, default **`unspecified`** (Compendium v25/#870: most balances state no
    hand, and defaulting to a side would assert something the source never said). **Styling
    only** — no end-state effect.
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** none.
- **effect:** **identity** — no change to position / role / number / facing. Consumes beats only.
- **normalization:** none.
- **facing (output):** unchanged.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline `balance` is not progression-capable; a balance carries
  no net displacement). *Per D5 the per-invocation flag is still mechanically accepted, but it
  would be unusual.*
- **sources:** ContraDanceVerifier `TryBalance` (recognized, no positional change — wave/no-op
  family, FigureSimulator.cs:779); CallersCompendium taxonomy `balance` MoveDef (`who` default
  neighbors, `beats` 4).

### `balance_the_ring`

- **summary:** All four dancers join hands in the ring and balance toward the center and back — a
  **positional no-op**. The ring counterpart of `balance`.
- **params** (meets CallersCompendium baseline `{beats}`):
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** none. (Real-life requires a ring of four with hands joined; positionally it
  doesn't matter since nothing moves.)
- **effect:** **identity** — no change to position / role / number / facing. Consumes beats only.
- **normalization:** none.
- **facing (output):** unchanged.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline is not progression-capable; no net displacement).
- **sources:** ContraDanceVerifier `TryBalance` (`balance ring` branch — no positional change,
  FigureSimulator.cs:783); CallersCompendium taxonomy `balance_the_ring` MoveDef (`beats` 4).

### `box_the_gnat`

- **summary:** Two facing dancers (each `who`-pair) join hands and **trade places** — one turns
  under (the "gnat") — ending facing each other with places exchanged.
- **params** (meets CallersCompendium baseline `{who, hand, balance, beats}`):
  - `who` — dancer set, default `partners`. Which pair trades (both pairs in the h4 participate).
  - `hand` — enum {`left`, `right`}, default `right`. Turning hand; **no end-position effect**
    (`hand:left` is the `swat_the_flea` alias).
  - `balance` — flag, default `false`. Optional balance lead-in; **no end-state effect**.
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** each participating `who`-pair must be **adjacent** — same row (partners across
  the set, c0↔c4) or same column (neighbors up/down, r0↔r1). If the pair is diagonal →
  `CompileError(notAdjacent)`.
- **effect:** **positional swap of each `who`-pair.** Partners → swap across columns within each
  row (`(r,c0) ↔ (r,c4)`); neighbors → swap across rows within each side column
  (`(r0,c) ↔ (r1,c)`). Role/number/couple-identity travel with each dancer.
  - Example — partners in DI top row `[[L1-A,0,0,0,R1-A], …]` → `[[R1-A,0,0,0,L1-A], …]`.
- **normalization:** **none** — box-the-gnat deliberately leaves dancers on the swapped
  (often "wrong") side (it frequently sets up a following pull-by / twirl). Positions are left
  exactly as swapped.
- **facing (output):** **toward each other** across the swap axis (excluded from equality).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline is not progression-capable).
- **sources:** ContraDanceVerifier `TryBoxTheGnat` (facing precondition + `SwapPos` each pair,
  FigureSimulator.cs:2628); CallersCompendium taxonomy `box_the_gnat` MoveDef.

### `box_circulate`

- **summary:** All four dancers in the box **circulate one place** around the hands-four ring;
  the `hand` sets the direction. A parameterized ring rotation (cf. `circle` / `petronella`).
- **params** (meets CallersCompendium baseline `{who, hand, balance, beats}`):
  - `who` — dancer set, default `partners`. Descriptive (the box members — all four circulate).
  - `hand` — enum {`left`, `right`}, default `right`. **Sets rotation direction:** `right` →
    **clockwise** one place; `left` → **counter-clockwise** one place.
  - `balance` — flag, default `false`. Optional balance lead-in; **no end-state effect**.
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** none (a box/wave arrangement is assumed; positionally it's a ring rotation).
- **effect:** rotate the corner ring `O = [ (topRow,c0), (topRow,c4), (botRow,c4), (botRow,c0) ]`
  by one place:
  - `hand:right` (**clockwise-from-above**): `new[O[k]] = old[O[(k−1) mod 4]]` — equivalent to
    `circle turn:left, places:1`.
  - `hand:left` (**counter-clockwise-from-above**): `new[O[k]] = old[O[(k+1) mod 4]]` —
    equivalent to `circle turn:right, places:1` (the `petronella` rotation).
  - Role/number/couple-identity travel with each dancer.
- **normalization:** none.
- **facing (output):** **determinate — carries facing** (per the focus `hand`): with
  `hand:right`, the dancers ending at **(topRow,c0)** and **(botRow,c4)** face **in** and the
  other two (**(topRow,c4)**, **(botRow,c0)**) face **out**; with `hand:left` it is reversed.
  (`in` resolves to Across→ for a c0 dancer / Across← for a c4 dancer; `out` is the reverse. Same
  rule as `shoulder_round`.)
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable); per D5 the per-invocation flag
  is still mechanically accepted.
- **sources:** user (rotation one place — `hand:right` CW / `hand:left` CCW); ContraDanceVerifier
  `TryCirculate` (generic one-place ring rotation, but facing-independent and hand-agnostic —
  superseded by the user's `hand`-directed rule, FigureSimulator.cs:3912); CallersCompendium
  taxonomy `box_circulate` MoveDef.

### `shoulder_round`

- **summary:** Two dancers walk around each other **facing** (eye contact, no hands) — a
  "gypsy"/"gyre". Positionally the **face-to-face twin of `do_si_do`** (whole turn returns to
  place, half turn swaps), but it **carries a determinate output facing** (unlike `do_si_do`).
- **params** (meets CallersCompendium baseline `{who, shoulder, turn, beats}`; keywords
  gypsy/gyre):
  - `who` — same value set as `do_si_do`/`swing`; default `neighbors`. Precondition (relaxed, as
    `do_si_do`).
  - `shoulder` — enum {`left`, `right`}, default `right`. Which shoulder passes = orbit direction
    **and the focus** that sets the output facing (below). Irrelevant to end *position* for
    whole/half turns.
  - `turn` — rotation number (CallersCompendium's name for `do_si_do`'s `circling`), default
    `1.0`. How far around (**1 = once around = back to place**).
  - `beats` — int, default 8 (baseline good=[8]).
- **preconditions:** as `do_si_do` (relaxed; `who` may be a different column). Precise checks
  _PENDING_.
- **effect (by `turn`):** **positions** identical to `do_si_do` with `circling := turn`:
  - **whole `turn` (1, 2)** ⇒ no positional change.
  - **half `turn` (0.5, 1.5, 2.5)** ⇒ the two `who` dancers **swap cells** (role / number /
    couple-identity travel with them).
  - **quarter `turn`** — **along the set only**; forms a **wave of four** exactly as
    `do_si_do`'s quarter does, with `shoulder` fixing the handedness — `right` builds the
    canonical wave, `left` its mirror, and ¾ is a half turn followed by the same handed
    quarter. Across-the-set quarters are **deferred**.
- **normalization:** none (like `do_si_do`).
- **facing (output):** **determinate — carries facing** (this is the key difference from
  `do_si_do`, which preserves facing), per the focus `shoulder`: with `shoulder:right`, the
  dancers ending at **(topRow,c0)** and **(botRow,c4)** face **in** and the other two
  (**(topRow,c4)**, **(botRow,c0)**) face **out**; with `shoulder:left` it is reversed. (Same rule
  as `box_circulate`; `in` resolves to Across→ for a c0 dancer / Across← for a c4 dancer.)
  **Exception — the quarter:** this is the one figure of the three quarter-capable turns that
  normally sets a facing of its own, and on a quarter it loses. The wave owns the facing
  (§8.5.6), so the focus rule is overridden and the dancers take the wave's resting facing,
  which runs **along** the set rather than across it.
- **interaction scope:** within the current h4 (pending cross-h4 `who`).
- **h4 contribution** (D7): 0 (whole/half); a quarter lands in a wave and contributes 0 as well.
- **progression-eligible:** yes (as `do_si_do`; baseline marks `shoulder_round`
  `progressionCapable:false`, but per D5 any figure may carry the flag).
- **sources:** ContraDanceVerifier `TryShoulderRound` ("Like do-si-do; full turn no-op, odd
  half-turns swap", FigureSimulator.cs:2892) for positions; user for the focus-based output
  facing; CallersCompendium taxonomy `shoulder_round` MoveDef (aka gypsy/gyre).

### `long_lines`

- **summary:** The long lines (the two side lines of the set — the `c0` and `c4` columns) go
  **forward and back** — a **positional no-op** for the standard (go-and-return) case.
- **params** (meets CallersCompendium baseline `{goBack, beats}`):
  - `goBack` — flag, default `true`. `true` = forward **and back** (return to place). `beats`
    default 8 when `true`, 4 when `false`.
  - `beats` — int, default 8 (baseline good=[4, 8]).
- **preconditions:** none.
- **effect:**
  - `goBack:true` (default) → **identity** — no change to position / role / number / facing.
  - `goBack:false` (forward only) → **deferred** — dancers would end displaced toward center,
    which our side-column matrix doesn't cleanly represent; not defined here yet.
- **normalization:** none.
- **facing (output):** unchanged.
- **interaction scope:** within the hands four (each line pair steps in place).
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable; no net displacement).
- **sources:** ContraDanceVerifier `TryLongLines` ("No net positional change",
  FigureSimulator.cs:1789 — its roll-away branch belongs to our separate `roll_away` figure);
  CallersCompendium taxonomy `long_lines` MoveDef (`goBack` default true; beats 8/4).

### `pass_through`

- **summary:** Facing dancers walk forward and **pass by** (given shoulder) to exchange places,
  continuing to face their walking direction (end back-to-back / passed through).
- **params** (meets CallersCompendium baseline `{dir, shoulder, beats}`):
  - `dir` — direction, default `along`. `across` = across the set; `along` = up/down the set.
  - `shoulder` — enum {`left`, `right`}, default `right`. Which shoulder passes; **no end-position
    effect** (styling).
  - `beats` — int, default 2 (baseline good=[2]).
- **preconditions:** the only refusal is on `dir` itself — `rightDiagonal` / `leftDiagonal` are
  outside this family's along/across pair and raise `unsupportedParam`. Facing does **not**
  refuse: dancers are expected to face the `dir` axis (`across` needs across-facing, `along`
  needs along-facing), and if they do not, the figure runs as though they turned to it first and
  reports the **`facingPrecondition` warning**. A **Flexible** facing is skipped silently — this
  figure is what resolves it, which is exactly the contract `circle` and `star` rely on when
  they hand their dancers over mid-ring.
- **effect:**
  - `dir:across` → **column swap** within each row: `(r,c0) ↔ (r,c4)` for all dancers.
  - `dir:along` → **row swap** within each side column: `(r0,c) ↔ (r1,c)` for all dancers.
  - Role/number/couple-identity travel with each dancer.
- **normalization:** **none** — dancers pass through to a back-to-back / passed arrangement; they
  are not re-normalized.
- **facing (output):** **preserved** (cardinal direction unchanged — each dancer keeps walking the
  way they went, so lands facing "out" from the new position).
- **interaction scope:** within the hands four. **Progression is not baked in** — unlike the prior
  verifier, `pass_through dir:along` only moves to new neighbors when it carries `progression:true`
  (our explicit flag runs the §10.2 end-normalization); without the flag it is a plain in-h4 swap.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; `dir:along` + `progression:true` is the classic "pass
  through to new neighbors"). Baseline marks `pass_through` `progressionCapable:false`, but our
  model carries progression via the per-invocation flag.
- **sources:** ContraDanceVerifier `TryPassThrough` (across = column swap; along = row swap, with
  their baked-in progression regrouping we deliberately omit, FigureSimulator.cs:2112);
  CallersCompendium taxonomy `pass_through` MoveDef.

### `roll_away`

- **summary:** Two dancers of the `whom` pair **trade places**, one rolling across in front of
  the other (optionally with a half sashay).
- **params** (meets CallersCompendium baseline `{who, whom, halfSashay, beats}`):
  - `who` — dancer set, default `neighbors`. Descriptive/actor context; **no end-position
    effect**.
  - `whom` — dancer set, default `partners`. **The relationship that trades** — names the
    swapping pair.
  - `halfSashay` — flag, default `false`. Styling (sashay vs. roll); **no end-state effect**.
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** the `whom` pair must be resolvable within the h4. Positionally
  **orientation-agnostic** — the pair swaps wherever they stand.
- **effect:** **full position swap** of each `whom` pair (row & col). Role/number/couple-identity
  travel with each dancer.
- **normalization:** none.
- **facing (output):** **preserved** (a roll is a full 360° turn — dancers keep their direction).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable).
- **note — the `who`/`whom` trap:** because `who` is inert here, naming the trading relationship in
  the **`who`** slot is not an error and does not refuse. `whom` silently keeps its `partners`
  default, the wrong pair trades, and the dance runs to completion landing somewhere plausible but
  wrong. *March for Andrea* arrived this way, read as `who: nextNeighbors` with no `whom`, and cost
  a Becket placement investigation before the record — not the engine — turned out to be at fault.
  When a record's `roll_away` names a relationship that is not `partners`, check which slot it is
  in.
- **sources:** ContraDanceVerifier `TryRollAway` / `DoRollAway` (full position swap of the pair,
  orientation-agnostic, FigureSimulator.cs:2506/2542); user (swap the `whom` pair; `who` /
  `halfSashay` are styling); CallersCompendium taxonomy `roll_away` MoveDef.

### `california_twirl`

- **summary:** Each `who` pair (default partners) **turns as a couple to face the opposite
  direction**, swapping sides in the process.
- **params** (meets CallersCompendium baseline `{who, beats}`):
  - `who` — dancer set, default `partners`. **The pair that twirls** — names the swapping pair
    (partners are row-mates in DI, column-mates in Becket).
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** the `who` pair must be resolvable within the h4 (a couple standing together).
- **effect:** two things happen together —
  1. **position swap** of each `who` pair (like `roll_away`/`box_the_gnat`: in DI a
     `(r,c0)↔(r,c4)` swap, in Becket a `(r0,c)↔(r1,c)` swap — defined as "swap the pair" so it
     generalizes across formations); and
  2. **facing reversal** — every twirling dancer flips to the opposite direction
     (Up↔Down, Across→↔Across←). This is the defining feature of the twirl.
  Role/number/couple-identity travel with each dancer.
- **normalization:** none — the swap + facing-reversal already lands the couple consistent with
  their new direction.
- **facing (output):** **reversed** (determinate: each dancer's prior facing flipped 180°).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable).
- **sources:** ContraDanceVerifier `TryCaliforniaTwirl` (swap each who-pair; partner/neighbor/
  default column-swap branches, FigureSimulator.cs:2595 — positions only, no facing); user
  (Option 1: swap the who-pair **and** reverse facing; the twirl turns the couple around).
  CallersCompendium taxonomy `california_twirl` MoveDef (also the model `star_through` mirrors).

### `star_through`

- **summary:** The same couple wheel as `california_twirl`, but the pair finishes facing **into
  the centre of their hands four** rather than reversed.
- **params** (meets CallersCompendium baseline `{who, beats}`):
  - `who` — dancer set, default `partners`. The pair that wheels.
  - `beats` — int, default 4.
- **preconditions:** the `who` pair must be standing together as a couple within the h4 —
  otherwise `unresolvableDancerSet`, exactly as `california_twirl` refuses.
- **effect:** positions are **identical to `california_twirl`** (swap the pair). Facing is where
  the two figures part company: both members finish facing the **same** direction, set toward the
  band centre on the axis **perpendicular to the couple's own axis**.
  - Row-mates (the DI case, a couple standing across the set) finish facing **along** the hall:
    `topRow → down`, otherwise `up`.
  - Column-mates (the Becket case, a couple standing along the set) finish facing **across**:
    `c0/c1 → acrossEast`, `c3/c4 → acrossWest`.
  This is the whole of *"ends facing into the centre of the hands four"* — a star through on the
  side ends facing across, and one across the set ends facing up/down as the dancers would when
  taking hands four. *(User-ruled, with both cases stated.)*
- **why it is stated as "perpendicular to the couple's axis" rather than per formation:** the
  facing outcome is a fact about **where the dancers are standing**, not about what the dance
  declared. `formation.type` never tracks the live arrangement (§3.2), so reading the couple's own
  axis is both simpler and correct in the mixed cases the declared type cannot describe.
- **undefined for a couple in the centre column:** `c2` has no near side, so there is no centre to
  face. No worked example puts a star through there, and the figure does not invent one.
- **normalization:** none beyond §8.5.4.
- **facing (output):** determinate, and **the same for both members** — unlike the twirl, where the
  two keep facing opposite ways.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** user worked example (*"behaves the same as a california twirl except facing ends
  into the center of the hands four"*, with the side and across cases spelled out).
  CallersCompendium taxonomy `star_through` MoveDef. ContraDanceVerifier models positions only
  and so contributes nothing to the defining half.

### `stand_still`

- **summary:** Dancers hold their position for the given beats. A **pure no-op / identity**.
- **params** (meets CallersCompendium baseline `{beats}`):
  - `beats` — int, default 8. Timing only; the Compendium accepts any in-domain beat count
    (no `goodBeats` constraint).
- **preconditions:** none.
- **effect:** none — positions, roles, numbers, couple-identity, and facing are all unchanged.
- **normalization:** none.
- **facing (output):** **preserved** (unchanged).
- **interaction scope:** within the hands four (vacuously).
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable).
- **sources:** CallersCompendium taxonomy `stand_still` MoveDef (`{beats}`, no goodBeats,
  render `stand still`); no ContraDanceVerifier handler (it falls through as a no-op); user
  (implement as a pure no-op).

### `mad_robin`

- **summary:** An orbit **along the set** — each dancer circles the person in their column (up/down)
  while facing across, of the `do_si_do`/`shoulder_round` family. Ends **facing across the set**.
- **params** (meets CallersCompendium baseline `{who, turn, direction, whom, beats}`):
  - `who` — dancer set, default `ones`. The pair that steps **in front first**. On a whole/half
    `turn` it has no distinct positional effect (see effect); descriptive context. *(Compendium
    warns: a different concept from `whom` — do not conflate them.)*
  - `turn` — rotation, default `1.0`. Orbit amount (plays the role `circling` does for do_si_do).
  - `direction` — spin direction {`clockwise`, `counterclockwise`}, default **`unspecified`**
    (Compendium v20/#295). A *clockwise* mad robin begins with the left-hand person going in front.
    **Styling** for whole/half turns (180° lands opposite either way).
  - `whom` — dancer set, default **`unspecified`** (Compendium v20/#295). The pair you travel
    **around**. Descriptive; the along-set axis is already fixed by the effect below.
  - `beats` — int, default 6 (baseline good=[6, 8]).
- **preconditions:** column-mates resolvable within the h4.
- **effect:** by `turn` amount (same rule family as `do_si_do`/`shoulder_round`, axis = **along the
  set** / column-mates):
  - **whole** (integer, incl. default 1.0) → **no net position change** (orbit back to place).
  - **half** (half-integer) → swap each column-mate pair `(r0,c)↔(r1,c)` (verifier `SwapRowsSameCol`).
  - **quarter** → **deferred** (mad robins don't normally resolve to a wave; define later if needed).
  Role/number/couple-identity travel with each dancer.
- **normalization:** none (facing is set directly — see below).
- **facing (output):** **across the set** (determinate, per user) — each dancer faces the opposite
  column: a `c0` dancer faces Across→, a `c4` dancer faces Across←.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable).
- **sources:** ContraDanceVerifier `TryMadRobin` (orbit along the set; full = no net change, half =
  `SwapRowsSameCol`, FigureSimulator.cs:2868); user (do_si_do-family along-set orbit; whole=no-op,
  half=column-mate swap, quarter deferred; **end facing is across the set**); CallersCompendium
  taxonomy `mad_robin` MoveDef.

### `star_promenade`

- **summary:** A **ring rotation** of all four dancers around a central star (couples travel as a
  unit). Same swap-family shape as the orbit figures, but a full-ring rotation.
- **params** (meets CallersCompendium baseline `{who, turn, beats}`):
  - `who` — dancer set, default `role1s`. **The dancer you pick up on the side** (Compendium
    v26/#843 owner ruling — *not* the pair with a hand in the center). **Styling** for the
    whole/half cases (no distinct positional effect).
  - `turn` — rotation, default `0.5`. Rotation amount.
  - *(no `hand`: the Compendium **removed** `star_promenade.hand` at v26/#843 — it described the
    center pair while rendering as though it qualified `who`. We accept `hand` only as an ignored
    legacy key, never as a determinant of the effect.)*
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** four dancers present in the h4.
- **effect:** by `turn` amount (ring O = `[(topRow,c0),(topRow,c4),(botRow,c4),(botRow,c0)]`):
  - **whole** (integer) → **no net position change**.
  - **half** (half-integer, incl. default 0.5) → **diagonal swap** `(r0,c0)↔(r1,c4)` and
    `(r0,c4)↔(r1,c0)` (180° rotation; direction-irrelevant). Verifier-confirmed.
  - **quarter** → **deferred** (a 1-place rotation whose *direction* is undetermined — the
    Compendium removed the `hand` param at v26 and the move carries no other direction token;
    uncommon, so define later with the box_circulate chirality convention if needed).
  Role/number/couple-identity travel with each dancer.
- **normalization:** none.
- **facing (output):** **flexible** (a promenade faces its direction of travel; left undetermined
  for now, to be refined if a determinate rule is needed).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable).
- **sources:** ContraDanceVerifier `TryStarPromenade` (4 dancers rotate around a star; half =
  diagonal/opposite-corner swap, whole = no-op, FigureSimulator.cs:3793); user (implement
  whole=no-op, half=diagonal swap, quarter deferred, facing flexible); CallersCompendium taxonomy
  `star_promenade` MoveDef.

### `give_and_take`

- **summary:** The `who` (taker/giver) draws the `whom` (taken) across to the taker's side; the two
  end as a **column couple** on the taker's side. Across couples → column couples.
- **params** (meets CallersCompendium baseline `{who, whom, give, beats}`):
  - `who` — dancer set, default `role1s` (choices role1s/role2s). **The taker/giver** — stays on
    their side.
  - `whom` — dancer set, default `partners`. **The taken** — crosses to the taker's column.
  - `give` — flag, default `true`. `false` = ContraDB "take-only". **Styling / beat-shaping only**
    (not a render token; no end-position effect).
  - `beats` — int, default 8 (baseline good=[4, 8]: 8 = give & take, 4 = take-only).
- **preconditions:** taker and taken must be **across the set** — same row, different column
  (matches verifier `CheckGiveAndTakeAcross`, fails otherwise).
- **effect:** for each (taker `T` at `(r, cT)`, taken `K` at `(r, cK)`) pair:
  - **K (taken)** → `(r, cT)` — crosses into the taker's column, staying in the shared row.
  - **T (taker)** → `(r̄, cT)` — keeps their column, slides to the **free row** (`r̄ = 1-r`).
  Net: the taker's column holds the taken in the taker's original row and the taker in the free
  row → the couple is now **vertical** on the taker's side. Role/number/couple-identity travel with
  each dancer.
  - *Worked example* — "Larks give & take partner" from improper: start
    `(r0,c0)=Robin1,(r0,c4)=Lark1 / (r1,c0)=Lark2,(r1,c4)=Robin2` →
    `(r0,c0)=Lark2,(r0,c4)=Robin1 / (r1,c0)=Robin2,(r1,c4)=Lark1` (c4 = couple 1, c0 = couple 2).
- **normalization:** none (positions set directly by the rule).
- **facing (output):** **flexible for now** (the couple is set to swing; determinate facing to be
  refined if needed).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable).
- **sources:** user (explicit permutation: taker keeps column + slides to free row, taken crosses
  into taker's column in the shared row; across couples → column couples); ContraDanceVerifier
  `TryGiveAndTake`/`DoGiveAndTake`/`CheckGiveAndTakeAcross` (across precondition; giver stays, taken
  to giver's side — modeled as an overlap we resolve to the free-row rule, FigureSimulator.cs:2377);
  CallersCompendium taxonomy `give_and_take` MoveDef.

### `pull_by_dancers`

- **summary:** A hand pass — the `who` pair take hands and **pull past each other, swapping
  positions**. Same swap-family as `box_the_gnat`/`roll_away`.
- **params** (meets CallersCompendium baseline `{who, balance, hand, beats}`):
  - `who` — dancer set, default `neighbors`. **The pair that pulls by** (swaps).
  - `balance` — flag, default `false`. Styling (a balance before the pull); **no end-state effect**.
  - `hand` — handedness, default `right`. Which hand you pass by; **styling**, no position effect.
  - `beats` — int, default 2 (baseline good=[2, 4]).
- **preconditions:** the `who` pair must be resolvable and able to pass (facing along their axis).
- **effect:** **swap each `who` pair** (default neighbors). Role/number/couple-identity travel with
  each dancer.
- **normalization:** none.
- **facing (output):** **preserved** (you walk forward past the other dancer).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no by itself — a pull-by is a within-h4 swap; progression only when the
  op carries our explicit `progression` flag (**not** baked in, same stance as `pass_through`).
- **sources:** ContraDanceVerifier `TryPullBy` (every case → who-pair `SwapPos`,
  FigureSimulator.cs:3575); user (swap the who-pair; hand/balance styling; facing preserved;
  progression via explicit flag); CallersCompendium taxonomy `pull_by_dancers` MoveDef.

### `pull_by_direction`

- **summary:** A hand pass named by **axis** rather than by dancer — everyone pulls past along the
  given direction, swapping along that axis. Positionally identical to `pass_through`.
- **params** (meets CallersCompendium baseline `{balance, dir, hand, beats}`):
  - `balance` — flag, default `false`. Styling; **no end-state effect**.
  - `dir` — direction, default `along`. The pass axis: `along` → row swap `(r0,c)↔(r1,c)`;
    `across` → column swap `(r,c0)↔(r,c4)`.
  - `hand` — handedness, default `right`. **Styling**, no position effect.
  - `beats` — int, default 2 (baseline good=[2, 4]).
- **preconditions:** dancers present along the `dir` axis to pass (always true in a full h4).
- **effect:** swap along the `dir` axis — `along` = row swap `(r0,c)↔(r1,c)` for each column;
  `across` = column swap `(r,c0)↔(r,c4)` for each row (= `pass_through`). Role/number/couple-identity
  travel with each dancer.
- **normalization:** none.
- **facing (output):** **preserved**.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no by itself — progression only via our explicit `progression` flag
  (not baked in, same stance as `pass_through`).
- **sources:** ContraDanceVerifier `TryPullBy` (pull by → position swap, FigureSimulator.cs:3575);
  user (swap along the dir axis: along=row swap, across=column swap; hand/balance styling; facing
  preserved; progression via explicit flag); CallersCompendium taxonomy `pull_by_direction` MoveDef.

### `cross_trails`

- **summary:** A compound pass — pass `who` in `dir` (across), then pass `who2` along — netting a
  **diagonal swap**. Ends facing along the set (out), per the final pass-along.
- **params** (meets CallersCompendium baseline `{who, dir, shoulder, who2, beats}`):
  - `who` — dancer set, default `partners`. Who you pass on the first (across) pass. **Descriptive**
    (doesn't change the permutation).
  - `dir` — direction, default `across`. Axis of the first pass. **Canonical/default `across`**;
    other values (`along`) degenerate to a no-op and are **deferred / out-of-scope**.
  - `shoulder` — shoulder, default `right`. Dialect/styling; **not a render token, no effect**.
  - `who2` — dancer set, default `neighbors`. Who you pass on the second (along) pass. **Descriptive**.
  - `beats` — int, default 4 (baseline good=[4]).
- **preconditions:** four dancers present (both passes need partners along each axis).
- **effect:** pass across (column swap) ∘ pass along (row swap) = **diagonal swap**:
  `(r0,c0)↔(r1,c4)` and `(r0,c4)↔(r1,c0)` (each dancer to the diagonal-opposite corner;
  positionally = `right_left_through` across / `star_promenade` half). Role/number/couple-identity
  travel with each dancer.
- **normalization:** none (facing is set directly by the pass-along — see below).
- **facing (output):** **determinate, from the final pass-along** (per user): each dancer faces the
  direction they traveled in the along-pass — a dancer **ending in row 0 faces Up**, **ending in row
  1 faces Down** (facing out along the set).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no by itself — progression only via our explicit `progression` flag.
- **sources:** ContraDanceVerifier `TryCross` "cross trail through" (pass partner across + pass
  neighbor along = diagonal swap, `SwapPos(M1,M2)`+`SwapPos(W1,W2)`, "same as R&L through across",
  FigureSimulator.cs:3468); user (Option 1 diagonal swap; **facing = the output facing from the
  pass-along**); CallersCompendium taxonomy `cross_trails` MoveDef.

### `zig_zag`

- **summary:** In a Becket-style line, dancers **weave along the set**, passing an oncoming couple
  by the given shoulder ("zig") — a single along-the-set pass. (Also called *weave the line*.)
- **params** (meets CallersCompendium baseline `{who, turn, ender, beats}`):
  - `who` — dancer set, default `partners`. Descriptive/actor context (who weaves together);
    **no end-position effect**.
  - `turn` — enum {`left`, `right`}, default `left`. Which shoulder starts the weave; **no
    end-position effect** (styling).
  - `ender` — enum {`none`, `ring`, `allemande`}, default `none`. Descriptive tag for what the
    weave leads into; **no end-position effect** in this baseline. A real `ring`/`allemande` ending
    is expressed as a **separate figure** (consistent with our "don't bake in follow-ons" stance).
  - `beats` — int, default 6 (baseline good=[6]).
- **preconditions:** dancers stand along the set (a completed h4). Orientation-agnostic for the
  baseline swap.
- **effect:** **single row swap** within each side column — `(r0,c) ↔ (r1,c)` for all dancers
  (one along-the-set pass; **identical net permutation to `pass_through` `dir:along`**).
  Role/number/couple-identity travel with each dancer.
  - **Note (future):** distance is fixed at one pass **for now**. A `count`/`places` param (the
    number of couples woven past — odd = net row swap, even = net zero, per the verifier's
    couple-pass model) may be added later to support multi-couple weaves.
- **normalization:** none — a weave/pass lands dancers back-to-back, not re-normalized.
- **facing (output):** **flexible** (baseline; excluded from equality per D4). The single pass
  preserves travel direction along the set.
- **interaction scope:** within the hands four. **Progression is not baked in** — like
  `pass_through dir:along`, it only moves to new neighbors when it carries `progression:true`.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; the along pass + `progression:true` weaves to new
  neighbors). Carried via our per-invocation flag.
- **sources:** ContraDanceVerifier `TryWeaveTheLine` (synonym; couple-passes from N/S text
  annotations → odd swaps = row swap `d.Row = 1-d.Row`, even = no change; default fallback
  `swaps=1` = single row swap, FigureSimulator.cs:2257); user (Option 1: net = single along-the-set
  row swap **for now**, with a couple-count param possible later); CallersCompendium taxonomy
  `zig_zag` MoveDef.

### `turn_alone`

- **summary:** Each `who` dancer **turns around individually** (180° in place) to reverse the
  direction they face — no position change.
- **params** (meets CallersCompendium baseline `{who, custom, beats}`):
  - `who` — dancer set, default `everyone`. Which dancers turn; **no position effect**.
  - `custom` — free-text, default `''`. Descriptive embellishment (like `contra_corners`' text);
    **no structured effect** — the canonical turn-alone is a 180° reverse.
  - `beats` — int, default 4 (baseline range 0–4).
- **preconditions:** none (orientation-agnostic; any completed h4).
- **effect:** **position unchanged.** Each `who` dancer's **facing reverses 180°**
  (Up↔Down, Across→↔Across←) — the same facing reversal as `california_twirl`.
  Role/number/couple-identity unchanged.
  - **⚠️ inside a line of four**, "position unchanged" means **column slots** are preserved; the
    line still **migrates rows**, because a line's row is facing-derived (§8.1 of
    `fundamentals.md`). Reversing facing therefore moves the line between its h4's upper and
    lower row while leaving every dancer in the same slot — which is exactly what makes the
    line come back **inverted** relative to the new direction. See the `turnAlone` ender of
    `down_the_hall`.
- **normalization:** none (no slot change to normalize) — and in a line, deliberately **none**:
  the inverted result is physically correct and must not be re-normalized (§8.1).
- **facing (output):** **reversed** (determinate: each `who` dancer flipped 180°).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable; a pure turn).
- **sources:** ContraDanceVerifier `TryTurnAlone` ("Individual 180° turn. No position change." — in
  a line flips travel direction, positionally inert otherwise, FigureSimulator.cs:3070); user
  (implement as facing-only 180° reverse, no position change, `custom` descriptive); CallersCompendium
  taxonomy `turn_alone` MoveDef.
- **note:** facing is excluded from equality (D4), so this is a **no-op for the equality check** but
  it **updates tracked facing**, which downstream figures read (e.g. `pass_through`'s
  `facingPrecondition` warning). Since facing is never fatal, a missing `turn_alone` costs a
  warning rather than a refusal — but it is still the difference between a dance that reads
  correctly and one that quietly implies an uncalled turn.

### `figure_8`

- **summary:** The `who` couple weaves a figure‑eight path around the stationary other couple. A
  **full** 8 returns everyone home; a **half** ends the two actives swapped within their own row.
- **params** (meets CallersCompendium baseline `{who, dir, lead, half, beats}`):
  - `who` — dancer set, default `ones`. The active couple that weaves.
  - `dir` — enum {`none`, `above`, `below`, `across`}, default `none`. Which way the loop is
    traced first; **path/styling only — no net effect** on the half's landing. `across` is
    **deferred** (degenerate/out of scope).
  - `lead` — dancer set, default `onesRole2` (choices onesRole1/onesRole2/twosRole1/twosRole2).
    Which single dancer leads the weave; **descriptive — no net effect**.
  - `half` — fraction, default `half`. `half` (0.5) = one loop; `full` (1.0) = complete 8.
  - `beats` — int, default 8 (baseline: `half`→8, `full`→16).
- **preconditions:** a completed h4 (the `who` couple weaves around the other, stationary couple).
- **effect:**
  - `half:full` (1.0) → **no‑op** (actives trace the whole 8 and return home; inactives never move).
  - `half:half` (0.5) → **swap the two dancers of the `who` couple** with each other, **within their
    own row**: DI `ones` → `(r0,c0)↔(r0,c4)`; `twos` → `(r1,c0)↔(r1,c4)`. Generalizes to "swap the
    who‑couple's two members" (Becket column‑mates → a row swap within their column).
  - The other (inactive) couple **does not move**. Role/number/couple-identity travel with each dancer.
- **normalization:** none — the actives land swapped in place; inactives untouched.
- **facing (output):** **flexible** (excluded from equality per D4).
- **interaction scope:** within the hands four. **Progression is not baked in** — a figure 8 returns
  the actives to their own row (no new-neighbor move); progression only via our explicit flag.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline `progressionCapable:false`; the figure returns actives to
  their row).
- **sources:** ContraDanceVerifier `TryFigureEight` (full = "return to place — no‑op"; half = named
  pair swaps positions, `ones`→`SwapPos(M1,W1)`; `dir`/`lead` ignored, FigureSimulator.cs:3540); user
  (worked-through geometry confirmed: half lands actives swapped within their own row, no
  progression; `dir`/`lead` descriptive, `across` deferred); CallersCompendium taxonomy `figure_8`
  MoveDef.

### `poussette`

- **summary:** Two couples join hands and push/pull each other as units around a shared center. A
  **full** poussette returns home; a **half** trades the two couples' places.
- **params** (meets CallersCompendium baseline `{who, whom, half, turn, beats}`):
  - `who` — dancer set, default `ones`. One of the two couples that poussette.
  - `whom` — dancer set, default `neighbors`. The other couple (the one `who` poussettes with).
  - `half` — fraction, default `half`. `half` (0.5) = trade places; `full` (1.0) = full box home.
  - `turn` — spin direction, default `clockwise`. **Irrelevant for a half** (180° lands the same
    either way); would only matter for quarter turns (deferred).
  - `beats` — int, default 6 (baseline is a range: half→6–8, full→12–16; not list-encodable).
- **preconditions:** the two couples (`who` + `whom`) resolvable within the h4 (DI: couple 1 = row 0,
  couple 2 = row 1).
- **effect:**
  - `half:full` (1.0) → **no‑op** (couples orbit fully and return home).
  - `half:half` (0.5) → **swap the two couples** = **row swap** `(r0,c) ↔ (r1,c)` for all four
    dancers (columns preserved; same net permutation as `pass_through` `dir:along`).
  - **Quarter / ¾ turns are deferred** (like `star_promenade`).
  - Role/number/couple-identity travel with each dancer.
- **normalization:** none — a half lands the couples swapped end‑for‑end.
- **facing (output):** **flexible** (excluded from equality per D4).
- **interaction scope:** within the hands four. **Progression is not baked in** — only via our
  explicit `progression` flag.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; the half's along-set couple trade + `progression:true`).
- **sources:** ContraDanceVerifier `TryPoussette` (standard: full = no‑op; half = `SwapRows(M1,M2)`
  + `SwapRows(W1,W2)` = global row swap; quarter/¾ approximated via circle rotation; draw poussette =
  circle, FigureSimulator.cs:3935); user (implement half = swap the two couples / row swap, full =
  no‑op, `turn` irrelevant for half, quarters deferred, facing flexible); CallersCompendium taxonomy
  `poussette` MoveDef.

### `facing_star`

- **summary:** Two facing couples put a hand in and rotate as a four‑person star. Identical
  mechanics to `star`/`circle`, parameterized by `turn` + `places`.
- **params** (meets CallersCompendium baseline `{who, turn, places, beats}`):
  - `who` — dancer set, default `ones`. **Descriptive** — a star is always four hands; all four
    dancers rotate (matches the verifier ignoring `who`).
  - `turn` — spin direction, default `clockwise`. Sets rotation direction:
    `clockwise` = star `hand:right` / circle‑left; `counterclockwise` = star `hand:left` /
    circle‑right.
  - `places` — int [1–10], default 3. Position‑steps around the ring; effective = `places mod 4`.
  - `beats` — int, default 8 (baseline good=[8]).
- **preconditions:** none — no required input facing (a **Flexible** input is accepted).
- **effect:** identical ring rotation to `star`/`circle` over the clockwise corner ring
  `O = [ (topRow,c0), (topRow,c4), (botRow,c4), (botRow,c0) ]`, with `p = places mod 4`:
  - `turn=clockwise` ⇒ `new[O[k]] = old[O[(k−p) mod 4]]`,
  - `turn=counterclockwise` ⇒ `new[O[k]] = old[O[(k+p) mod 4]]`.
  - All `places` are representable (the ring uses only corner cells c0/c4; middle columns stay
    empty). Role/number/couple-identity travel with each dancer.
- **normalization:** none (same as `star`/`circle`).
- **facing (output):** **Flexible** (like `star`/`circle`) — resolved by the following figure.
  Implemented on the same footing, full turns exempt.
- **interaction scope:** within the hands four — no cross-h4 interaction; waiting-out couples are
  never involved.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes — `progression:true` runs the §10.2 end-normalization after the
  rotation.
- **sources:** ContraDanceVerifier `TryStar` (handles "star left/right" **and** "facing star
  cw/ccw" with identical ring rotation over `cwOrder`, rotates all four, `who` ignored; facing star
  CW = star right = clockwise, CCW = star left, FigureSimulator.cs:1299); user (implement mirroring
  `star`, `turn` sets direction, `places` mod 4, all four rotate, Flexible facing); CallersCompendium
  taxonomy `facing_star` MoveDef.

### `square_through`

- **summary:** A chain of pull‑bys, alternating between the `who` pair (across) and the `who2` pair
  (along), turning to face a new dancer after each pull. `places` = number of pull‑bys.
- **params** (meets CallersCompendium baseline `{who, who2, balance, hand, places, beats}`):
  - `who` — dancer set, default `partners`. The **first / odd** pull‑by relationship (DI: partners
    are **across** → column swap).
  - `who2` — dancer set, default `neighbors`. The **even** pull‑by relationship (DI: neighbors are
    **along** → row swap).
  - `balance` — flag, default true. Optional balance lead‑in; **styling / beats only**.
  - `hand` — handedness, default right. Which hand pulls; **no position effect** (styling).
  - `places` — int [1–10] (typically 2–4), default 4. Number of pull‑bys; effective net =
    `places mod 4`.
  - `beats` — int, default 16 (baseline good=[16]).
- **preconditions:** a completed h4 with dancers facing to begin the first pull‑by (DI: partners
  facing across).
- **effect:** alternate pull‑bys starting with the `who` axis (across / column swap), then the
  `who2` axis (along / row swap), repeating. Net by `p = places mod 4` (verified by hand‑trace):
  - `p==1` → **column swap** `(r,c0) ↔ (r,c4)`.
  - `p==2` → **diagonal swap** (column swap + row swap): each dancer to the opposite corner.
  - `p==3` → **row swap** `(r0,c) ↔ (r1,c)`.
  - `p==0` (e.g. `places=4`) → **no‑op** (dancers return home).
  - Role/number/couple-identity travel with each dancer. All outcomes are corner‑preserving.
- **normalization:** none.
- **facing (output):** **flexible** (excluded from equality per D4; dancers end facing out/along
  depending on parity).
- **interaction scope:** within the hands four. **Progression is not baked in** — only via our
  explicit `progression` flag.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5).
- **sources:** ContraDanceVerifier `TrySquareThrough` (default: `swapCols = count%4 ∈ {1,2}`,
  `swapRows = count%4 ∈ {2,3}`, alternating across/along, FigureSimulator.cs:3127); user (implement
  alternating col/row pull-bys, net by `places` mod 4, hand/balance styling, facing flexible) +
  hand-trace confirmation (square through 4 returns home; 2 = diagonal); CallersCompendium taxonomy
  `square_through` MoveDef.

### `pass_by`

- **summary:** A shoulder pass — the `who` pair walk forward and **pass by (given shoulder),
  swapping positions**. The shoulder-named twin of `pull_by_dancers` (hand-named).
- **params** (meets CallersCompendium baseline `{who, shoulder, beats}`):
  - `who` — dancer set, default `neighbors`. **The pair that passes by** (swaps).
  - `shoulder` — enum {`left`, `right`}, default `right`. Which shoulder passes; **styling**, no
    position effect.
  - `beats` — int, default 2 (baseline good=[2]).
- **preconditions:** the `who` pair must be resolvable and facing to pass (along their axis).
- **effect:** **swap each `who` pair** (default neighbors → column-mates → row swap in DI; partners
  → column swap). Generalizes to "swap the who pair." Role/number/couple-identity travel with each
  dancer.
- **normalization:** none — dancers pass through to a back-to-back / passed arrangement.
- **facing (output):** **preserved** (you walk forward past the other dancer).
- **interaction scope:** within the hands four. **Progression is not baked in** — only via our
  explicit `progression` flag (same stance as `pass_through` / `pull_by_dancers`).
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; the along pass + `progression:true`).
- **sources:** ContraDanceVerifier `TryPass` (named pair → `SwapPos`: `ones`→M1/W1, `women`→W1/W2,
  `partner`→partner swap, FigureSimulator.cs:3634 — no dedicated `pass_by` handler); user (implement
  as the shoulder-pass twin of `pull_by_dancers`: swap the `who` pair, `shoulder` styling, facing
  preserved); CallersCompendium taxonomy `pass_by` MoveDef.

### `gate`

- **summary:** Two dancers join hands; one **backs up** while the other **walks forward**, so the
  pair **orbits about their joined hands**. A half turn lands each gating pair swapped. (Unified
  figure as of CallersCompendium v22 — the former `rotation_gate` was folded into this move and is
  **not** modeled separately.)
- **params** (meets CallersCompendium baseline `{who, whom, pair, direction, turn, face, beats}`):
  - `who` — dancer set. **The side that extends a hand and backs up** (the pivot / inside of the
    arc). **Descriptive** for net position (see effect).
  - `whom` — dancer set. **The side that walks forward** (the outside of the arc). **Descriptive**
    for net position.
  - `pair` — dancer relationship, a `who`-style value (e.g. `neighbors`, `partners`,
    `role1s`/`role2s`). A **third axis**: the *pairing the gate is danced with*, not which side
    moves. **Selects the gating pairs** — see effect. Optional; when absent the default pairing
    applies.
  - `direction` — enum {`clockwise`, `counterclockwise`, `mirror`}. `mirror` = a two-couple gate in
    which the roles rotate in **opposite** senses (this is why it is not a plain spin direction).
    **No net-position effect** for whole or half turns (a 180° rotation lands the same either way).
  - `turn` — amount of rotation. Drives the whole effect.
  - `face` — enum {`up`, `down`, `in`, `out`}. **Stored data** as of v22 (see facing).
  - `beats` — int, default 8.
- **preconditions:** the gating pairs must be resolvable — every `who`-side dancer must have exactly
  one `whom`-side dancer under the operative pairing, and the two must be adjacent (share a row or a
  column). Otherwise `UnresolvableDancerSet`.
- **effect:** first resolve the **gating pairs**, then apply `turn`.
  - **Pairing.** If `pair` is **specified**, each gating pair is a `who`-side dancer and the
    `whom`-side dancer holding that relationship with them — this **may override** the default. If
    `pair` is **unspecified**, pair dancers by **shared column** (the default hands-four adjacency).
  - **`turn` = whole number** (1, 2, …) → **no-op**. Each pair returns to where it started.
  - **`turn` = half** (½, 1½, …) → **swap the two members of each gating pair**. The swap *axis*
    falls out of where the paired dancers currently stand:
    - paired dancers are **column-mates** → **row swap** `(r0,c) ↔ (r1,c)`;
    - paired dancers are **row-mates** → **column swap** `(r,c0) ↔ (r,c4)`.
  - **`turn` = quarter or other fraction** → **deferred / unsupported** (`UnsupportedParam`).
    Fractional gates are used to get into and out of a **line of four**, which is a different
    shape from the wave a quarter `allemande` lands in (a line fills one row and empties the
    other; a wave keeps two per row) and is not modelled.
  - Role, number, and couple identity travel with each dancer.
- **normalization:** none — the gate ends where the rotation puts each dancer.
- **facing (output):**
  - If `face` is **stated**, that is the ending facing (it is stored data, not derived).
  - If `face` is **absent**, **infer from the starting facing and `turn`**: a **half** gate
    **inverts** each participant's facing 180° (Up↔Down, In↔Out i.e. Across→↔Across←); a **whole**
    gate leaves facing unchanged.
  - This inference is deliberately *relative*. CallersCompendium `gate_facing.dart` records that the
    old absolute `gateEndFacing` derivation was **withdrawn as unsound** — an absolute cardinal
    cannot be recovered without simulating all preceding choreography. Because we **track facing
    through the compile**, the relative rule is sufficient for us.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5).
- **worked example** (user-supplied): `ones gate twos clockwise 1/2` from the DI hands-four
  `[[R1,0,0,0,L1],[L2,0,0,0,R2]]`. `pair` unspecified → pair by shared column: c0 = {R1, L2},
  c4 = {L1, R2}. Half turn swaps each pair →
  **`[[L2,0,0,0,R2],[R1,0,0,0,L1]]`** (a row swap).
- **sources:** CallersCompendium taxonomy `gate` MoveDef (v22 unification; `rotation_gate` removed)
  and `gate_facing.dart` (`gateFacings`, `gateDirections`; absolute end-facing derivation withdrawn
  as unsound). User: "Two couples orbit as units, with the `pair` specifying which dancers are
  coupled when it requires additional clarification"; unspecified `pair` defaults to shared column
  (half = row swap, whole = no-op); a specified `pair` may override it (neighbors standing as
  row-mates → column swap); "without a facing note, it's assumed that half gates invert facing";
  fractional gates "are sometimes used to get in and out of a line of four, which we haven't
  modeled yet"; `face` is "yes but it may not always be present and may have to be inferred from
  starting-facing"; plus the worked example above.

### `two_hand_turn`

- **summary:** The two dancers take **both hands** and turn around each other by `turn`
  full-turns. The two-handed hold keeps them **face-to-face throughout**, which is what
  distinguishes it from `allemande` (one hand/forearm) on the facing axis.
- **params** (meets CallersCompendium baseline `{who, turn, beats}`):
  - `who` — dancer set (our `who` vocabulary; baseline default **`partners`**). A **precondition**,
    relaxed like `allemande` / `do_si_do`.
  - `turn` — rotation number **[0.25 .. 2.5], step 0.25**, default `1.0`. (Same concept as
    `do_si_do`'s `circling`.)
  - `beats` — int, default 8 (baseline good=[8]).
  - *(no `hand`: a two-hand turn gives **both** hands, so the move carries **no direction token**
    at all — see the quarter deferral below.)*
- **preconditions:** `who` validated; the pair must be adjacent (share a row or a column) so the
  two-handed hold is physically available. No rigid input-facing requirement.
- **effect (by `turn`)** — the `allemande` rotation family:
  - **whole** (integer, incl. default 1.0) → **identity** (position unchanged).
  - **half** (half-integer) → the two `who` dancers **swap cells**. Column-mates → row swap
    `(r0,c)↔(r1,c)`; row-mates → column swap `(r,c0)↔(r,c4)`. Role, number, and couple-identity
    travel with each dancer.
  - **quarter** → **deferred** (`UnsupportedParam`). `allemande` lands a quarter in a wave
    using `hand` to fix the direction; with **no `hand`** a two-hand turn has no direction
    token, so a quarter is *doubly* undetermined here.
- **normalization:** none — facing is set directly (see below), positions are not re-normalized.
- **facing (output):** **each dancer ends facing the other dancer of their pair**, derived from
  the **final** positions — column-mates → the `r0` dancer faces Down and the `r1` dancer faces Up;
  row-mates → the `c0` dancer faces Across→ and the `c4` dancer faces Across← (both "in", across
  the set). Marked **Flexible**: this is the natural resolution of the two-handed hold, but a
  dancer may finish facing another direction, so it satisfies any downstream facing precondition.
  - **vs. `allemande`:** allemande **inverts** facing on a half turn (rotation-facing principle,
    `gate_facing`). A two-hand turn does **not** — the pair never breaks eye contact, so the
    ending facing is *relational* (toward the other dancer) rather than a rotation of the input.
- **interaction scope:** within the current hands four (like `allemande` / `do_si_do`).
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; the half-turn swap carries the displacement).
- **sources:** CallersCompendium taxonomy `two_hand_turn` MoveDef (new since our previous
  snapshot). ContraDanceVerifier has **no dedicated handler** — `"two-hand turn"` is matched by
  **`TryAllemande`** itself (FigureSimulator.cs:1443, alongside `mirror allemande` and
  `arm left/right`), sharing its `who`/amount parsing and its `halfTurns % 2` swap. User:
  implement as allemande-minus-`hand` (whole = no-op, half = swap, quarters deferred), **except**
  that "endFacing is toward the other dancer in the figure, with flexibility to face a different
  direction too."

### `courtesy_turn`

- **summary:** A couple **wheels 180° as a rigid unit** — one dancer backs up as the pivot while
  the other walks forward around them — ending facing back the way they came. The sub-component
  that `chain` and `right_left_through` each end with, here as TCB's standalone figure
  (CallersCompendium v23).
- **params** (meets CallersCompendium baseline `{who, whom, direction, endFacing, beats}`):
  - `who` — dancer set, default `partners`. **The pairing the turn is danced with** (TCB states it
    on every line: partner ×53, neighbor ×39, N2 neighbor ×13). Selects the couples that wheel.
  - `whom` — dancer set, default **`unspecified`**. The dancer **being turned**, when a source
    names a turner *and* a turnee. **No source does** — it exists for manual authoring only.
  - `direction` — spin direction, default `clockwise`. A courtesy turn wheels clockwise **by
    construction**; `counterclockwise` is unattested in the corpus. **No net-position effect** (a
    180° wheel lands the same either way).
  - `endFacing` — ⚠️ **a DANCER, not a cardinal.** Default `unspecified`. Do **not** read it as
    `swing.endFacing` or `gate.face` — the names match, the domains do not. It holds a dancer
    relationship (`nextNeighbors` / `thirdNeighbors` / `prevNeighbors`) answering *whom* you end up
    facing. Cardinal facings do appear in the corpus (`; face down`, `; face out`) but only on
    semicolon-compound lines, which stay whole-`custom` and never reach this slot. **Advisory /
    descriptive for us** — we do not resolve it (it would need cross-h4 dancer resolution).
  - `beats` — int, default 4.
- **preconditions:** each `who` couple must be **adjacent** (sharing a column or a row) so the
  two-handed couple hold is available; otherwise `UnresolvableDancerSet`.
- **effect:** **swap the two dancers of each participating couple** — the rigid wheel carries each
  dancer to where the other stood. Column-mates (a couple facing across) → **row swap**
  `(r0,c)↔(r1,c)`; row-mates (a couple facing along the hall) → **column swap** `(r,c0)↔(r,c4)`.
  Role, number, and couple-identity travel with each dancer. **Unconditional** — not an
  input-dependent normalization.
- **normalization:** none required — and this is the important part. Because the wheel is **rigid**,
  the couple's mutual left/right relationship is **preserved** through the turn. The invariant is:
  **the dancer being turned ends on the RIGHT; the dancer doing the turning ends on the LEFT**,
  relative to the ending facing (§7 geometry).
  - Lark-left / robin-right is therefore the **common case, not an imposed rule** — it is simply
    what you get because dancers normally arrive in that relationship (the Lark turns the Robin).
  - **Arrive inverted, end inverted.** If a couple begins the figure cleanly inverted (Lark
    unambiguously on the right, Robin on the left), they end that way.
  - **Same-role case.** When one role dances the other's part — e.g. two Larks chaining — the
    crossing/turned Lark ends on the **right** and the stationary Robin on the left. Corroborated
    by the prior verifier's second routine, `ReverseCoupleFacing` (Robin-left/Lark-right),
    commented *"used after cross-role chains where one role does the other's chain."*
- **facing (output):** **reversed 180°** — Up↔Down, Across→↔Across← (in↔out). The couple ends
  facing back the way it came. A **Flexible** input stays Flexible.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; the wheel carries the displacement).
- **not emitted by `chain`.** The Compendium is explicit: `courtesy_turn` is **never emitted by a
  chain**, and the 30 corpus lines writing both together (`Ladies chain … with half courtesy turn
  in center`, `… with double courtesy turn`) stay whole-`custom` — emitting both would double-count
  the figure *and* its beats, and neither model has a slot for the qualifier. We follow suit: a
  `chain` / `right_left_through` carries its courtesy turn internally and must **not** be paired
  with a separate `courtesy_turn` op.
- **sources:** CallersCompendium taxonomy `courtesy_turn` MoveDef (v23; new since our previous
  snapshot — TCB writes it standalone 115× across 24,107 dances, ContraDB models it nowhere).
  ContraDanceVerifier `TryCourtesyTurn` (FigureSimulator.cs:3759) reduces it to
  `NormalizeCoupleFacing()` (:4483) with no permutation — a facing-proxy shortcut forced by that
  model not tracking facing; its c0 = Lark-lower-row / c4 = Lark-higher-row ordering nonetheless
  **exactly reproduces** our §7 across-facing geometry. User: the turned dancer ends right and the
  turner ends left, so lark-left/robin-right is the common case rather than the rule; a cleanly
  inverted couple stays inverted; two Larks doing a right-hand chain end on the right.

### `turn_as_couples`

- **summary:** Each `who` couple **turns 180° as a unit** to face the opposite direction, the two
  dancers swapping sides in the process. The third member of the **rigid couple-wheel** family
  (`california_twirl`, `courtesy_turn`, `turn_as_couples`) — mechanically identical to
  `california_twirl`; the difference is **styling only** (a plain couple wheel rather than a twirl
  under joined hands, and no courtesy hold or `direction` param as in `courtesy_turn`).
- **params** (meets CallersCompendium baseline `{who, beats}`):
  - `who` — dancer set, default `partners`. **The couple(s) that turn.**
  - `beats` — int, default 4 (baseline good=[4]).
  - *(The Compendium models this move on `california_twirl` exactly — same params, same default,
    same `goodBeats`. `star_through` is the third move in that cluster.)*
- **preconditions:** each `who` pair must be resolvable within the h4 and standing together as a
  couple (sharing a row or a column); otherwise `UnresolvableDancerSet`.
- **effect:** two things happen together, exactly as for `california_twirl` —
  1. **position swap** of each `who` pair — "swap the pair" so it generalizes across formations
     (partners are row-mates in DI → `(r,c0)↔(r,c4)`; column-mates in Becket → `(r0,c)↔(r1,c)`);
     and
  2. **facing reversal** — every turning dancer flips 180° (Up↔Down, Across→↔Across←).
  Role, number, and couple-identity travel with each dancer.
- **normalization:** none — as with the rest of the wheel family, the couple's mutual left/right
  relationship is **preserved** by the rigid turn (see `courtesy_turn`), so the swap plus the
  facing reversal already lands the couple consistent with its new direction.
- **facing (output):** **reversed** (determinate: each dancer's prior facing flipped 180°).
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no (baseline not progression-capable, matching `california_twirl`).
- **deferred `who` values:** the **line-of-four** scopings — `centers`, `left-hand`, `right-hand`
  (verifier variants that turn only one adjacent pair of the line) — remain **deferred**
  (`UnsupportedParam`). There is no baseline param for them; they would ride in `who`, and they
  are meaningless outside a line.
  - *Status update:* the line-of-four formation **is now modeled** (§8.1 of `fundamentals.md`),
    so the original blocker is gone and the mechanics are available — `TryTurnAsCouples`
    (FigureSimulator.cs:3030) swaps only slots `{s1,s2}` for `centers`, `{s0,s1}` for
    `left-hand`, `{s2,s3}` for `right-hand`, versus both pairs for the full turn. These are held
    now only pending a **scoping decision**, alongside the parallel `down_the_hall` `moving:
    center` / `outsides` cases in the Held table.
- **sources:** CallersCompendium taxonomy `turn_as_couples` MoveDef (new since our previous
  snapshot; declared alongside and modeled on `california_twirl` / `star_through`).
  ContraDanceVerifier `TryTurnAsCouples` (FigureSimulator.cs:3030) implements it **only inside a
  line of four** — `[a,b,c,d] → [b,a,d,c]` **plus** a line-direction flip `up`↔`down`, i.e. exactly
  swap-the-pair + reverse-facing — with `centers`/`left-hand`/`right-hand` sub-variants; outside a
  line it makes no grid change, which reads as an unimplemented path rather than a claim (the same
  file handles `california_twirl` off-line). User: implement as the `california_twirl` twin, with
  the line-of-four `who` values deferred.

### `orbit`

- **summary:** The `who` dancers travel **around the outside of the hands four** — a rotation about
  the h4 centre — typically while the other dancers turn in the middle. First-class as of
  CallersCompendium v19.
- **params** (meets CallersCompendium baseline `{who, turn, amount, beats}`):
  - `who` — dancer set, default `ones`. The orbiting dancers.
  - `turn` — **spin direction** {`clockwise`, `counterclockwise`}, default `clockwise`. **Not an
    amount here** — `turn` is polymorphic across the taxonomy (see *`turn` is polymorphic* in the
    shared vocabulary); `orbit` is one of four moves that spend the slot on direction, alongside
    `facing_star`, `poussette` and `promenade`. **No net-position effect** for whole/half amounts
    (180° lands the same either way).
  - `amount` — **rotation fraction**, default `0.5`. Holds what `turn` holds in `allemande` /
    `do_si_do` / `two_hand_turn`. `orbit` is the **only** move in the taxonomy using an `amount`
    slot, precisely because its `turn` is taken by the direction. (The `0.5` default matches the
    retired fused move's `outer` value.)
  - `beats` — int, default 8 (baseline good=[8]).
- **preconditions:** the `who` pair must be resolvable within the h4.
- **effect (by `amount`):**
  - **whole** (integer) → **no-op** (all the way round, back to place).
  - **half** (half-integer, incl. default 0.5) → **swap the `who` pair.** Same-role `who` →
    Larks `(r0,c4)↔(r1,c0)` / Robins `(r0,c0)↔(r1,c4)` in DI (a diagonal); couple `who` → the
    couple's two dancers swap (row-mates in DI → column swap). Role, number, and couple-identity
    travel with each dancer.
  - **quarter** → **deferred** (`UnsupportedParam`); the verifier records "no clean 2x2 model."
- **why the same-role case is provable:** in DI the two Larks stand at `(r0,c4)` and `(r1,c0)` —
  **diagonally opposite**. A true 180° rotation about the h4 centre maps exactly those two cells
  onto each other, so "orbit half way round" and "swap the pair" are the *same* operation. Same for
  the two Robins.
- ⚠️ **Known caveat — couple `who` (`ones` / `twos`).** For a couple the swap rule is **not** a
  true orbit. The 1s are row-mates in DI, so rotating them 180° about the h4 centre would carry
  them onto **the 2s' cells**, which only resolves once the centre figure's outcome is known — the
  **meanwhile** dependency (see the Held table). The verifier instead swaps the couple's two
  dancers inside their own row, and independently lists `^ones\s+orbit\b` in its
  **unsupported-patterns** table (FigureSimulator.cs:894), i.e. it declares those `ones`/`twos`
  branches unsupported. **Recorded per the user's ruling to implement all `who` values with the
  swap rule**; flagged here for revisit alongside the meanwhile mechanism. Note the baseline
  default `who` is `ones`, so the default invocation is the caveated case.
- **normalization:** none.
- **facing (output):** **Flexible** (like `circle` / `star`) — an orbit's ending facing is not
  determined by the sources and was not specified; Flexible is the conservative choice (it
  satisfies any downstream facing precondition). Refine if a determinate rule is needed.

  > ⚠️ **Documented, not yet implemented.** When `circle`, `star` and `facing_star` were brought
  > up to this contract, `orbit` was deliberately left out: those three rotate a whole ring, so
  > loosening the whole band is exactly right, whereas an orbit moves only its `who` — usually
  > two of the four. Loosening the band here would discard the facing of dancers who never
  > moved. The fix wants a `who`-scoped loosening, and the question of whether the *orbiting*
  > dancers' facing is genuinely indeterminate (rather than simply unrecorded) should be
  > settled first. Until then `orbit` carries each dancer's previous facing forward.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** yes (per D5; the half-orbit swap carries the displacement).
- **supersedes `allemande_orbit`.** The fused `allemande_orbit` (X allemande while Y orbits) was
  **retired at Compendium v19** and its stored figures migrated to `meanwhile[allemande, orbit]`
  (CompendiumDatabase schema v18). Express that shape as an `allemande` plus an `orbit` under the
  meanwhile mechanism — never as a single fused figure.
- **sources:** CallersCompendium taxonomy `orbit` MoveDef (new since our previous snapshot; issue
  #295 — TCB writes the orbit side standalone, e.g. "Men orbit clockwise 1/2", and is the source
  since ContraDB has only the combined form). ContraDanceVerifier `TryOrbit`
  (FigureSimulator.cs:1403 — `amount 0.5` → `SwapPos` of the `who` pair, full orbit → no-op,
  quarters → "no clean 2x2 model"), with `^ones\s+orbit\b` in the unsupported-patterns list at
  :894. User: implement all `who` values with the swap rule; re-scope the stale `allemande_orbit`
  hold onto the meanwhile mechanism.

### `down_the_hall`

- **summary:** The h4 forms a **line of four** (§8.1 of `fundamentals.md`) and travels **down**
  the hall, finishing with an `ender` that reshapes or reorients the line. Travel itself is
  **positionally inert** — going down the hall is not a matrix transformation, it is a movement
  of the entire matrix — so every real state change comes from the **gather** and the **ender**.
- **params** (meets CallersCompendium baseline `{who, moving, facing, ender, beats}`):
  - `who` — dancer set, default `everyone`. The baseline couples this to `moving`
    (`everyone` ↔ `all`). Only the `everyone` / whole-h4 case is defined here.
  - `moving` — choice `{all, center, outsides}`, default `all`. Only **`all`** implemented;
    `center` / `outsides` → **deferred** (`UnsupportedParam`) — they leave part of the line
    behind, producing a shape that is not a line of four.
  - `facing` — choice `{forward, forwardThenBackward, backward}`, default `forward`. Sets the
    **ending facing** (below); does not affect position, since travel is inert.
  - `ender` — choice, default `turnCouple`. 6 of 10 values implemented (below).
  - `beats` — int, default 8 (baseline good=[8]).
- **preconditions:** the h4 must be **complete** (four dancers). When the input is not already a
  line of four, the gather must be resolvable — two dancers in `c0` and two in `c4`; otherwise
  `UnresolvableDancerSet`.
- **effect — three phases, in order:**

  **1. Gather (conditional).** *Only if the h4 is not already a line of four.* Each **column
  pair** collapses into the two-cell segment on its own side — c0-pair → `{c0, c1}`, c4-pair →
  `{c3, c4}`, `c2` left empty — in the facing-derived row, normalized lark-left/robin-right
  relative to the **ending facing** (§7). This is the `swing` `where:sides` rule verbatim.

  > ⚠️ **The gather is conditional, and must be.** If it re-ran on a line that already exists,
  > it would silently re-normalize it — and `turnAlone` would be erased by the `up_the_hall`
  > that follows it, making "down the hall, turn alone, come back" undo itself. An existing
  > line is passed through **untouched**, inverted or not (§8.1).

  Base ring input `[[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]]`, `facing:forward` (⇒ facing Down):
  - gather → `[[R1-A,L2-B,0,R2-B,L1-A],[0,0,0,0,0]]` — line in the **upper** row.
    (Identical to `swing` `where:sides face:down`, as required.)

  **2. Travel.** **Identity.** No displacement, no facing change. (`long_lines` precedent.)

  **3. Ender.** Applied to the line. Slot indices below are `s0=c0, s1=c1, s2=c3, s3=c4`;
  all examples continue from the gathered line above (facing Down, upper row).

  | `ender` | Effect | Result |
  |---|---|---|
  | `none` | identity — the line stays a line | `[[R1-A,L2-B,0,R2-B,L1-A],[0,0,0,0,0]]` · Down |
  | `turnCouple` | each column pair swaps (`[s1,s0,s3,s2]`) + facing reverses | `[[0,0,0,0,0],[L2-B,R1-A,0,L1-A,R2-B]]` · Up |
  | `turnAlone` | slots **preserved**, facing reverses | `[[0,0,0,0,0],[R1-A,L2-B,0,R2-B,L1-A]]` · Up |
  | `slidingDoors` | the two **halves swap** (`[s2,s3,s0,s1]`) + facing reverses | `[[0,0,0,0,0],[R2-B,L1-A,0,R1-A,L2-B]]` · Up |
  | `bendTheLine` | line folds into a ring — **ends** to the row toward travel, **centers** to the other row, all four to the outer columns; everyone faces **across / in** | `[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A]]` · Across (in) |
  | `circle` | **synonym of `bendTheLine`** — see below | same as `bendTheLine` |

  - **`turnCouple` self-renormalizes.** The pair swap alone lands lark-left/robin-right for the
    reversed direction — no separate normalization step. It is our `turn_as_couples` applied to
    the line (rigid couple wheel: handedness preserved, so reversing the facing reverses which
    slot is "left"). Its result is exactly `swing` `where:sides face:up`.
  - **`turnAlone` and `slidingDoors` leave the line inverted**, and that is correct — both
    reverse facing without reordering slots, so the dancer on your left is now on your right
    (§8.1). Do not normalize these results.
  - **`bendTheLine` lands on the canonical across-in ring** as a *consequence*, not an
    imposition: ends keep their outer columns, centers move to the outer columns of the other
    row, and the result satisfies §8 across-normalization on its own. Its output here is
    identical to `swing` `where:sides face:in`.
  - **`circle` ≡ `bendTheLine`.** As an *ender*, "circle" means only that the line closes into a
    ring; any actual circling is a separate `circle` figure line, which is why the ender carries
    no `places` or direction. **May be merged with `bendTheLine` in a later taxonomy version.**
  - **deferred enders (4):** `cozy`, `cloverleaf`, `threadNeedle`, `rightHandHigh` →
    `UnsupportedParam`. See the Held table.
- **`facing` — sets the ending facing:**
  | value | ending facing | note |
  |---|---|---|
  | `forward` | = travel direction (Down) | ordinary case; facing and travel coincide |
  | `backward` | = **opposite** of travel (Up) | "back down the hall" |
  | `forwardThenBackward` | = travel direction (Down) | the round trip is **complete within this figure** — suppresses the one-sided-hall warning |

  With `backward`, facing and travel disagree. **Normalization keys off facing, never travel**
  (§7 defines left/right by facing), and the row stays **facing-derived** with no exception —
  so a line backing down the hall sits in the *lower* row. The row is a normalization slot, not
  a hall position (§8.1).
- **normalization:** on the **gather** only, relative to ending facing. Never re-applied to an
  existing line, and never applied after an ender.
- **facing (output):** determinate — set by `facing`, then reversed by `turnCouple` /
  `turnAlone` / `slidingDoors`, or set to across-in by `bendTheLine` / `circle`.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0 (no displacement).
- **progression-eligible:** no (travel is inert; no net displacement to carry).
- **diagnostics:** a dance containing a `down_the_hall` with no corresponding `up_the_hall`
  (or vice versa) raises the **`oneSidedHall` warning** — non-fatal, because the two need not be
  adjacent. Not raised when `facing: forwardThenBackward` completes the round trip.
- **ruled:** if the input is *already* a line whose facing runs against this figure's travel
  facing, the figure performs an **un-signalled turn** (e.g. a Down-facing line meeting
  `up_the_hall` `facing:forward`). Mechanically `facing` is authoritative and **wins** — the
  figure runs and the line ends facing where the figure says — but the turn is movement nobody
  called, so it also raises the **`hallFacingConflict` warning**. Compared against the *travel*
  facing rather than the figure's direction, because `facing: backward` legitimately wants the
  line facing against its travel. The common sequence is unaffected — after `turnCouple` the
  line already faces up, so the following `up_the_hall` `facing:forward` agrees.
- **sources:** CallersCompendium taxonomy `down_the_hall` MoveDef (`who` everyone, `moving` all,
  `facing` forward, `ender` **turnCouple**, beats 8; `_downTheHallEnders` shared with
  `up_the_hall`, `bendTheLine` added at v10 when the CallersBox cross-line merge began folding a
  following bend-the-line into the preceding hall). ContraDanceVerifier `TryLineOfFour`
  (FigureSimulator.cs:2939 — transient `("line", order, direction)` state),
  `TryBendTheLine` (:2995 — "going UP: ends above (row 0), inners below (row 1)"; our derivation
  matches independently), `TryTurnAsCouples` (:3030 — `[a,b,c,d]→[b,a,d,c]`),
  `TryLongLines` (:1789 — net-zero precedent). No verifier basis exists for `cozy`,
  `threadNeedle`, or `slidingDoors`; `TryCloverleaf` (:1224) is a **different, standalone**
  figure (h4 ring rotation) and "cloverleaf turn single" sits in the unsupported-patterns list
  (:800); `TryRightHandHigh` (:4229) requires a named pivot dancer from free text we do not
  parse. User: travel is "not a matrix transformation, but a movement of the entire matrix";
  one-sided hall is a warning, not an error; `circle` and `bend the line` are synonymous;
  `slidingDoors` worked example supplied directly.

### `up_the_hall`

- **summary:** Twin of `down_the_hall` — the h4 forms a **line of four** and travels **up** the
  hall. Mechanically identical in every respect; only the travel direction and the default
  `ender` differ.
- **params** (meets CallersCompendium baseline `{who, moving, facing, ender, beats}`): as
  `down_the_hall`, except **`ender` defaults to `circle`** (≡ `bendTheLine`) rather than
  `turnCouple`. `beats` default 8 (good=[8]).
- **preconditions / effect / normalization / facing / diagnostics:** **see `down_the_hall`** —
  the full specification applies unchanged, reading "Up" for the travel direction. Consequently:
  - `facing: forward` ⇒ ending facing **Up** ⇒ the line occupies its h4's **lower** row;
  - the gather from a base ring yields `[[0,0,0,0,0],[L2-B,R1-A,0,L1-A,R2-B]]` — identical to
    `swing` `where:sides face:up`, as required;
  - `bendTheLine` / `circle` place the **ends** in the **upper** row (the row toward travel) and
    the centers in the lower — the mirror of the `down_the_hall` case.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** CallersCompendium taxonomy `up_the_hall` MoveDef (identical params to
  `down_the_hall`; `ender` default **`circle`**, shared `_downTheHallEnders`). Verifier sources
  as `down_the_hall` — `TryLineOfFour` reads `\bup\b` to set the same transient line state
  (FigureSimulator.cs:2939).

### `form_short_waves`

- **summary:** Each hands four steps into a **wave of four across the set** — see
  `fundamentals.md` §8.5.1 for the geometry this entry applies.
- **params** (meets CallersCompendium baseline `{dir, balance, center, centerHand, sides,
  beats}`):
  - `dir` — direction, default `across`. `rightDiagonal` / `leftDiagonal` raise
    `unsupportedParam`: they build the wave across hands-four boundaries and have no worked
    example on record.
  - `balance` — flag, default `false`. **No end-state effect** (styling), as `petronella`'s.
  - `center` — dancer set, default `role2s`. Who the source says ends in the two centre cells.
  - `centerHand` — handedness. The hand the **centre pair** joins — not the hand the wave is
    named for, which is the outer join alternation makes its opposite. **Carried as absent
    rather than defaulted**, diverging from the baseline's `right`: see *the one-bit problem*
    below. *(User-ruled: `centerHand` names the centre join, and the canonical duple-improper
    wave is `centerHand: left` — role2s joining left in the middle, neighbours right on the
    sides.)*
  - `sides` — dancer set, default `neighbors`. Who the source says the facing pairs are.
  - `beats` — int, default 4. Timing only.
- **the one-bit problem (why three params describe one thing):** a wave alternates hands along
  its length, so naming *either* join fixes the other, and fixing either one fixes every
  dancer's offset. `centerHand`, `center` and `sides` therefore all speak to a **single bit** of
  geometry. That makes two of them redundant — and therefore useful: they are **checked against
  the resulting arrangement rather than trusted**, and a contradiction is `whoMismatch`. It is
  also why `centerHand` must be allowed to be absent: a record that says "robins in the middle"
  and no hand has already fixed the geometry, and supplying the baseline default on its behalf
  would let the figure refuse itself for a contradiction of our own making. Concretely, the
  baseline's `centerHand: right` and `center: role2s` cannot both hold from a duple-improper
  start — the canonical wave there is `centerHand: left` — so honouring the literal default
  would make the baseline's own pair of defaults refuse each other. When absent, `center`
  drives; when `center` fails to discriminate too, the canonical wave (centre **left**, sides
  right) is used. *(The divergence from the baseline default is user-ruled, not inferred.)*
- **preconditions:**
  - `dir` other than `across` → `unsupportedParam`.
  - No complete hands four → `unresolvableDancerSet`.
  - `sides` not matching the pairs actually standing face to face → `whoMismatch`.
  - `center` not matching the pair the chosen hand puts in the middle → `whoMismatch`.
  - Facing does **not** refuse (it never does): a band not already looking at itself across the
    set raises the **`facingPrecondition` warning** and the figure runs as though they turned.
  - The **declared formation does not gate the figure**. Everything above is read off where the
    dancers actually stand. `formation.type` is fixed when the dance is loaded and never tracks
    where earlier figures have left people, so a Becket dance that has manoeuvred into an
    along-facing arrangement forms waves like any other set, and a set genuinely standing across
    is covered by the facing warning above. *(User-ruled: an earlier Becket refusal keyed on
    `formation.type` was dropped as testing the wrong thing.)*
- **effect:** each of the four corner dancers steps to `waveOffsetColumn` for their facing and
  the outer hand — **rows never change**, and the dancer whose step would leave the matrix holds
  while their opposite absorbs the whole offset (§8.5.1).
- **which role lands in the middle is an output, not an input.** The offset is derived from
  facing throughout, so the same hand puts different roles in the centre from different
  arrangements. The corpus confirms this directly: `balance wave of four` annotations carry both
  `(neighbor right, robin left)` — 289 occurrences — and `(neighbor right, lark left)` — 102 —
  i.e. the same outer hand with a different centre role.
- **normalization:** none on entry. On **exit**, §8.5.4 settles the offsets automatically for the
  next figure. This figure does not opt out of that rule, so forming short waves twice re-forms
  the wave from `c0`/`c4` rather than compounding two offsets.
- **facing (output):** **concrete alternating** (§8.5.3) — top row Down, bottom row Up. That is
  the facing the pairs already have at rest, read along the wave, so nothing extra is imposed.
- **interaction scope:** within the hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** CallersCompendium taxonomy `form_short_waves` MoveDef (renamed from
  `form_a_short_wave` at v21/#295). ContraDanceVerifier contributes **nothing**: `TryFormWave` is
  literally `return true`, and its `("wave", order, "RH"|"LH")` overlay never touches grid
  positions — a bookkeeping dodge around a 2×2 grid with nowhere to put an offset dancer
  (§8.5.2). Corpus frequencies from `figure_freq.tsv`.

### `form_long_waves`

- **summary:** The two **side lines** become waves running **along** the set. **Nobody moves** —
  this figure is facing and nothing else.
- **params** (meets CallersCompendium baseline `{who, whom, hand, balance, beats}`):
  - `who` — dancer set, **absent by default** rather than the baseline's `role1s`. The pair who
    face **in**; everyone else faces out. Carried as absent for the same reason
    `form_short_waves`'s `centerHand` is — see *the anchors* below.
  - `whom` — dancer set, absent by default (the upstream `unspecified` sentinel). Whom you hold.
    An **anchor**: no end-state effect, but verified.
  - `hand` — handedness, absent by default (same sentinel). The hand you hold `whom` by. An
    anchor on the same footing; unlike a short wave's, it displaces nobody, because nobody steps
    anywhere to reach it.
  - `balance` — flag, default `false`. No end-state effect.
  - `beats` — int, default 0 (good=[0, 4]) — a formation label, or 4 when a balance is folded in.
- **why there is no offset:** §8.5.1's offset exists to let dancers who face *each other* join
  matching hands. In a long wave you join hands with the dancers **beside** you along your own
  line, whom you do not face, and the line already runs the way the wave does. No sideways step
  is needed — which is also why this figure can be danced by the whole set at once, ends
  included, rather than band by band.
- **`who` is a facing selector, not a set of movers** — it can afford to be, because there is no
  movement to scope. The baseline narrows its domain to invertible pairs for exactly this reason.
- **the anchors (`whom` + `hand`) — read twice over:** *(user-ruled)*
  - **They resolve.** A dancer's hands follow from their facing, and their facing follows from
    `who` — so naming the hold fixes the pair exactly as surely as naming the pair does. When
    `who` is absent, each candidate pair is formed and tested against the anchors, and a
    candidate is adopted **only when it is the only one that fits**. Anything less — no anchors,
    anchors that fit both, anchors that fit neither — falls back to the canonical `role1s`, so a
    record is never silently read as a dance it did not describe.
  - **They corroborate.** Once the pair is fixed, the anchor is a claim *about* the arrangement,
    so it is checked rather than trusted — the same move `form_short_waves` makes with `center`
    and `sides`. A contradiction raises the **`anchorMismatch` warning** and the figure runs
    unchanged: it never needed the anchor, so what is wrong is the description.
  - **Why `who` cannot be defaulted.** From a duple-improper start, `whom: neighbors` by the
    `right` is the **robins** facing in, not the baseline's `role1s`. Supplying the baseline
    default on a record's behalf would make it contradict itself over a value it never stated —
    the same self-inflicted contradiction `centerHand` avoids. TCB writes exactly this record:
    *"Balance long wave (NR, women face in)"*.
  - **Worked case:** duple improper, robins facing in ⟺ everyone holds their **neighbours** by
    the **right**. `whom: nextNeighbors` is impossible from there — nobody in a long wave holds
    hands across a grouping boundary — so it warns.
  - **The anchors do not size the set.** `whom` is deliberately *not* reported as a dancer set:
    it describes the hold, it does not reach for it, and a figure where nobody moves has no
    business expanding the set because a record named a distance.
- **preconditions:** none.
- **effect:** positions unchanged. Every dancer standing in a side column is faced **across** the
  set: `who` inward, everyone else outward. A dancer left off the side columns is skipped.
- **normalization:** none on entry beyond §8.5.4's automatic settling, which is what guarantees
  the side columns this figure faces.
- **facing (output):** **across, alternating in and out** — which is what makes balancing a long
  wave a balance right and left along the hall. The alternation follows from the role-scoped
  `who`: roles alternate down a line, so naming one lands the facings in, out, in, out. A `who`
  that does not alternate produces a line of joined hands that is not a wave; the figure still
  runs, since the arrangement is legal and only the label is wrong.
- **interaction scope:** the whole set.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** CallersCompendium taxonomy `form_long_waves` MoveDef (v21/#295 added `whom`,
  `hand` and `balance`; `who` decodes the facing-**in** pair). ContraDanceVerifier contributes
  nothing — see `form_short_waves`.

### `form_a_long_wave`

- **summary:** One role steps into the **centre column** and waves down the middle of the set;
  the other role holds its line.
- **params** (meets CallersCompendium baseline `{who, in, out, balance, beats}`):
  - `who` — dancer set, default `role2s`. Which role forms the wave.
  - `in` — flag, default `true`. Whether `who` steps into the centre column. *(Spelled `stepsIn`
    in code; Dart reserves `in`.)*
  - `out` — flag, default `false`. Whether `who` returns to the side lines. *(`stepsOut`.)*
  - `balance` — flag, default `true`. No end-state effect.
  - `beats` — int, default 8. Timing only.
- **why the figure is role-scoped is structural, not stylistic:** a rank holds **two** dancers
  and `c2` holds **one**, so a centre wave cannot be danced by everyone. Every rank contains
  exactly one of each role, so a role-scoped `who` puts exactly one dancer per rank in the centre
  and the counts land exactly.
- **`out` needs no code.** §8.5.4's normalization has already returned anyone standing in the
  centre to the line they left before this figure runs — and that is the same rule that evicts
  the other role when `who` arrives to take its place. So `in:false` is a positional identity,
  and `in:true` is well defined regardless of who was in the centre beforehand.
- **preconditions:** with `in:true`, every occupied rank must hold exactly two dancers, exactly
  one of them in `who` — otherwise `unresolvableDancerSet`, per the capacity argument above.
  Refusing rather than approximating is deliberate: guessing would strand a dancer in a line that
  is not theirs.
- **effect:** each rank's `who` dancer moves to `c2`. `c2` is **exact — no offset** (see
  `form_long_waves` for why).
- **normalization:** none on entry beyond §8.5.4.
- **facing (output):** each mover faces **the direction they travelled** — from `c0` across-east,
  from `c4` across-west. This alternates down the set for free, because consecutive ranks step in
  from opposite lines, so nothing is invented. Non-movers keep their facing.
- **interaction scope:** the whole set.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** CallersCompendium taxonomy `form_a_long_wave` MoveDef.
  ContraDanceVerifier contributes nothing — see `form_short_waves`.

### `rory_o_more`

- **summary:** Dancers standing in a wave balance and then **slide one place sideways**, keeping
  the wave and swapping which hand is which.
- **params** (meets CallersCompendium baseline `{who, balance, slide, beats}`):
  - `who` — dancer set, default `everyone`. Which dancers slide. *(The baseline also lists
    `centers`; we have no `centers` in `WhoSet`, so a record naming it is a parse error. That is
    the right outcome — inventing a positional `who` value would let it silently mean something
    else.)*
  - `balance` — flag, default `true`. **No end-state effect** (styling).
  - `slide` — hand, default `right`. The side each dancer steps toward.
  - `beats` — int, default 8. Timing only.
- **one rule, both wave orientations:** every sliding dancer steps **one cell toward their own
  named side**, computed from **their own facing** (`turnedRight` / `turnedLeft`, `facing.dart`).
  Because a wave alternates facing, that single sentence produces the two very different-looking
  pictures the figure is known by:
  - **Short wave** (dancers facing along the hall): their sides are **columns**, so the slide moves
    **across** the set and no one changes rank. `[[. R1-A . . L1-A], [L2-B . . R2-B .]]` slides
    right to `[[R1-A . . L1-A .], [. L2-B . . R2-B]]`.
  - **Long waves** (dancers facing across the hall): their sides are **ranks**, so the slide moves
    **along** the set and no one changes column — each band's two ranks trade.
- **facing is unchanged.** A slide changes which hand you give, not where you look. This is what
  makes the return slide an exact inverse.
- **handedness needs no detection.** The slide a given wave cannot take is exactly the one that
  walks a dancer off the end of the matrix, so the grid boundary refuses it and no separate
  reading of the wave's handedness is needed. From the canonical wave a left slide fails; from the
  slid position a right slide fails and a left slide returns everyone home.
- **preconditions** (all `unresolvableDancerSet`):
  - Any slider would land **off the grid** → refused. This is the handedness rule above, and it is
    a refusal rather than a silent hold on purpose: a figure that quietly moved nobody is the one
    outcome worth never producing.
  - Any slider has `Facing.flexible` → refused; there is no side to step toward.
  - A landing is **occupied** — by a held dancer, or by another slider — → refused. (`Formation`
    throws on a shared cell, so this must be caught before projection.)
- **§8.5.4 exemption:** `preservesWaveOffsets => true`. This is a wave figure that reads the wave,
  so normalizing the offsets away before it ran would delete its entire subject. It is the third
  member of that list, alongside `balance` and `stand_still`.
- **effect:** the landings computed above, applied together.
- **interaction scope:** the whole set (waves span bands).
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** user worked examples — all four short-wave cases (right and left from both the
  canonical and the slid position) and both long-wave slides in *United We Dance*.
  CallersCompendium taxonomy `rory_o_more` MoveDef. ContraDanceVerifier `TrySlide` reads its swap
  targets from free-text annotations rather than the structured `who` and falls back to a
  degenerate row swap, so it contributes nothing.

### `pass_the_ocean`

- **summary:** Facing couples **pass across the set** and land in a **wave of four**.
- **params** (mirror `form_short_waves` exactly): `dir` (default `across`), `balance`, `center`
  (default `role2s`), `centerHand` (**nullable** — absent is the baseline's `unspecified`),
  `sides` (default `neighbors`), `beats` (default 4).
- **effect — three composed steps:**
  1. `reflectBands(columns: true)` — everyone crosses over. Each rank keeps its two dancers and
     they trade columns. *(This is the user-confirmed decoding of the verifier's
     `MapWaveToGrid` net effect, and it is what the prose "pass through" describes.)*
  2. **Impose the wave's resting facing** — top row `down`, otherwise `up`.
  3. Delegate to `form_short_waves` with this figure's own wave params, which applies the §8.5.1
     offset and runs that figure's cross-checks.
- **why step 2 is load-bearing rather than decoration:** the §8.5.1 offset is **derived from
  facing**, and `waveOffsetColumn` returns **zero displacement** for an across-facing dancer. The
  entry state this figure requires is across-facing — so without step 2 the delegate would produce
  a **settled set masquerading as a wave**. It is also what makes the wave's handedness follow the
  stated `centerHand` rather than whichever way the set happened to arrive.
- **entry state — a warning, never a refusal:** the standard definition passes through to face
  your partner first, so the figure wants an across-facing set. A set facing along the hall raises
  the **`facingPrecondition` warning** and the figure runs anyway. *(User-ruled, restating the
  standing rule: facing must only ever be a compiler warning.)*
- **worked example** *(user-ruled — the prose reading)*: from
  `[[L2-B . . . R2-B], [R1-A . . . L1-A]]` with everyone facing across, `centerHand: left` gives
  `[[. R2-B . . L2-B], [L1-A . . R1-A .]]`.
- **preconditions:** inherited wholesale from the delegate — including its `sides` / `center`
  cross-checks and its `dir` restriction — because the delegation goes through the public `apply`
  rather than round the outside of it.
- **interaction scope:** the whole set.
- **h4 contribution** (D7): 0.
- **progression-eligible:** no.
- **sources:** user worked example and ruling. CallersCompendium taxonomy `pass_the_ocean`
  MoveDef. ContraDanceVerifier `TryPassTheOcean` (user-confirmed translation, step 1).

### `hey`

- **summary:** A **reel of four** — the dancers weave past each other along a line of four,
  without taking hands.
- **params** (meets CallersCompendium baseline; no `beats`):
  - `pass1` — dancer set, default `role2s`. The pair who begin **in the centre**, and so take
    the first centre meeting. This is the only param that selects anybody.
  - `length` — enum {`lessThanHalf`, `half`, `betweenHalfAndFull`, `full`}, default `half`.
  - `pass2` — dancer set, **nullable**. The pair at the ends. An **anchor** (see below).
  - `meetTarget` — dancer set, **nullable**. Whom the `pass1` pair meet when the weave stops part
    way. Meaningful only for the deferred partial lengths; carried for record fidelity, no
    end-state effect.
  - `shoulder` — hand, default `right`. Which shoulder passes. **Styling only**, as for `pass_by`.
  - `dir` — direction, default `across`. The axis the line of four lies along.
  - `rico1`–`rico4` — flags, default `false`. Ricochets, numbered by centre meeting.

- **⭐ the permutation, derived rather than ported.** A reel is **not** a sequence of pair
  exchanges — composing four literal pair swaps gives the identity, which is plainly wrong for a
  half hey. Each pass instead *advances* a dancer one place along the line. Numbering the line
  `[end, centre, centre, end]` as `[a, b, c, d]`, the four passes of a half hey are:

  | # | pass | line after |
  |---|---|---|
  | 1 | the centres `b, c` meet and pass | `a c b d` |
  | 2 | each pair at the ends passes | `c a d b` |
  | 3 | `a, d` — now the centres — pass | `c d a b` |
  | 4 | each pair at the ends passes | `d c b a` |

  **The line ends reversed.** Reversal maps position 1 ↔ 4 and 2 ↔ 3, so an end lands on the other
  end and a centre on the other centre: **each pair exchanges within its own slot**, and nobody
  moves between the centre and the ends. A full hey is that twice over — the identity.

- **effect:** In each complete hands four, read the band as an across-the-set line of four
  (`west-outer, west-inner | east-inner, east-outer`). The **inner** two are whichever pair
  `pass1` names; the remaining two are the ends **by construction**. Exchange each pair within its
  own slot per the parity rule below. Facing is left `flexible`.
- **state-dependent on purpose.** From a Duple Improper start with `pass1: role2s` the Robins are
  diagonally opposite, so this reads as the familiar same-role **diagonal** swap; had the named
  pair been standing across a rank, the identical rule yields a **within-rank** exchange.
  Hard-coding the Duple Improper answer would be wrong everywhere else in the set. *(The prior
  verifier hard-codes exactly that answer — its fixed same-role swap is the DI evaluation of this
  rule, not a competing model. §1.1 held; nothing needed reconciling.)*

- **⭐ ricochets — a suppressed centre meeting.** The pair approach, bump, and return the way they
  came instead of passing through. Re-walking the reel with pass 1 suppressed gives
  `a b c d → d b c a` (the ends traded, the centres did not), so a ricochet is exactly *"that pair
  does not exchange"*.
  - A half hey has **exactly two centre meetings**: the `pass1` pair at the first, the end pair at
    the second. *Who* meets in the centre alternates — so `rico1`/`rico3` are the **`pass1` pair's**
    two meetings and `rico2`/`rico4` the **end pair's**. They are not "first and second dancer".
  - Because an exchange is an **involution**, two unsuppressed meetings cancel. A pair ends
    swapped exactly when it met an **odd** number of unsuppressed times. This is why a plain full
    hey is the identity, and why `rico1` alone on a full hey *does* produce a swap.
  - **User worked examples**, all from `[[R1-A . . . L1-A], [L2-B . . . R2-B]]`, held verbatim as
    regression anchors in `test/ops/hey_test.dart`:

    | call | result |
    |---|---|
    | plain half | `[[R2-B . . . L2-B], [L1-A . . . R1-A]]` |
    | `rico1` | `[[R1-A . . . L2-B], [L1-A . . . R2-B]]` |
    | `rico2` | `[[R2-B . . . L1-A], [L2-B . . . R1-A]]` |
    | `rico1` + `rico2` | identity |

- **`pass2` is an anchor, not a selector** (the `form_long_waves` precedent): once `pass1` is
  resolved the ends are simply whoever is left, so a stated `pass2` cannot select anyone. It is
  checked against the pair the figure derived and reported through `anchorMismatch` when the two
  disagree. The hey still weaves as `pass1` describes; only the second pass is misdescribed.
- **preconditions:**
  - `dir != across` → `unsupportedParam`. The diagonals lay the line of four across more than one
    hands four, and are **deferred behind diagonal `right_left_through`**, which they would have to
    agree with and which is itself unimplemented.
  - `length` of `lessThanHalf` / `betweenHalfAndFull` → `unsupportedParam`. They stop the weave
    mid-pass, leaving dancers in the middle of the set rather than in the corners the matrix is
    defined over (fundamentals §8). "Valid but out of scope", not "malformed".
  - `rico3` / `rico4` below a **full** hey → `unsupportedParam`. Each pair has only one centre
    meeting in a half, so these name a meeting that never happens — refused rather than ignored.
  - `pass1` does not resolve to **exactly one** pair in a band → `unresolvableDancerSet`.
  - The `pass1` pair stand in the **same column** → `unresolvableDancerSet`; they must be one on
    each side of the set to meet in the centre.
  - A band holds other than four dancers, or there is **no complete hands four** →
    `unresolvableDancerSet`.
- **facing:** `flexible` for all four. A hey ends mid-flow, and what a dancer looks at depends on
  what is called next (fundamentals §6).
- **interaction scope:** one hands four.
- **h4 contribution** (D7): 0.
- **progression-eligible:** **yes** (user-ruled).
- **sources:** derived from first principles and confirmed against **user worked matrices** (the
  four above) and user rulings on ricochet numbering, ending facing and progression-eligibility.
  CallersCompendium taxonomy `hey` MoveDef for the param surface — the adapter structures heys
  natively, with names matching this implementation. ContraDanceVerifier `FigureSimulator.cs`
  contributes the DI special case only; **its ricochet code path is not authoritative** —
  `SYSTEM_REFERENCE.md` lists "Ricochet hey" as intentionally skipped and `DanceData.cs` filters
  ricochet dances out of the corpus, so that code was never validated against a real dance.
- **not yet covered by a golden dance.** Neither corpus dance probed during development
  *discriminates* between the candidate permutations (a following partner swing normalizes the
  difference away), so confidence rests on the derivation and the worked matrices, not on the
  corpus.

<!-- Figure entries will be appended here using the template above. -->
