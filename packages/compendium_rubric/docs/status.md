# Implementation status

> Measured on September 15, 2026, from branch `rubric` after merging
> `origin/main` at `8f180a9` and applying taxonomy-v35 compatibility.
> The corpus is the 24,107-file local Caller's Box mirror described in
> [`implementation.md`](implementation.md). These numbers are a snapshot:
> re-run the corpus harness after figure, parser, or `compendium_core` changes.
>
> **Stale since the taxonomy-v40 sync.** `main` was merged again at `a5281105`
> (taxonomy v40), which changed what an omitted parameter means for eleven
> moves (v37's `courtesy_turn` and v38's ten; `arch_and_dive` among them was not
> implemented then), made `long_lines` an alias of `forward_and_back` (v39),
> added `hand_cast` as an alias of `gate` (v40), and added five moves this
> compiler then deferred (`circular_hey`, `trade_the_wave`, `starburst`,
> `hey_for_three`, `cast`), on top of many Caller's Box adapter changes. The
> figures below have not been re-measured since; see `implementation.md` §15
> for the current vocabulary.
>
> **Added since (2026-11-22):** `slice`, `butterfly_whirl` and `revolving_door`
> are built on user rulings (`taxonomy.md` has each entry). Measured on the
> same mirror against `rubric` at `eb52b309`, they took the in-scope count
> from 2,517 to 2,759 compiled, and Hudson's Seattle core set from 360 to 391,
> with no previously compiling dance lost. `arch_and_dive` and
> `contra_corners` followed, also on rulings: against `rubric` at `11b1860a`
> they took the count from 2,759 to 2,795 and the core set from 391 to 397,
> again losing nothing. The tables below count all six figures added since
> (with `circular_hey`, below) in their new rows but keep the September
> per-figure numbers.
>
> **Becket progressions (2026-11-23):** the Caller's Box bridge now places a
> Becket dance's progression on its first diagonal `chain` or `pass_through`
> along the set, and a Becket progression with no whole couple at an end is
> held until one gets there (both user-ruled). Measured against `rubric` at
> `e88bc9ce`: 2,795 to 2,843 compiled in scope (49 gained, 1 lost: *More
> Summer Haze*, whose pass through along goes to the previous neighbours), and
> the core set from 397 to 410. Holding was then extended to every formation
> (user-ruled the same day). Against `rubric` at `ee39d32f` that changed no
> dance's outcome (3,031 compiled in scope, core set 435): 21 dances that
> already mismatched gain a `heldProgressionUnfinished` warning.
>
> **Diagonal `chain` (2026-11-23)** pairs the dancers who stand on the
> diagonal rather than pairing by couple number (user-ruled). Against
> `rubric` at `64c2803e`, together with an across chain falling back to
> pairing by line when the numbers name no pair (the agent's call), it took
> the count from 3,298 to 3,352 compiled in scope (36 refused and 18
> mismatched dances now compile), and the core set from 473 to 485, with no
> previously compiling dance lost. 8 dances that refused now mismatch and 3
> that mismatched now refuse.
>
> **`circular_hey` (2026-11-23)** is built on the agent's reading of the core
> definition, not yet ruled. Against `rubric` at `5f683503` it took the count
> from 2,843 to 2,849 compiled in scope, with the core set unchanged at 410 and
> nothing lost.
>
> **`cast` (2026-11-23)** is built on Hudson's ruling for up and down casts,
> one place only. Against `rubric` at `2bf7a0e1` it compiles no new dance yet:
> 147 of the 202 dances it unblocked first stop at a `down_the_hall` led by part
> of the set (mostly "ones lead down"), which was then deferred (built since;
> see below). The count stays
> at 2,849 (the in-scope denominator grows from 4,506 to 4,539), the core set at
> 410, and nothing is lost.
>
> **`modifier` and `meanwhile` (2026-11-23)** are built on user rulings
> (`taxonomy.md`, "Containers"). Against `rubric` at `14ada564` they took the
> count from 2,849 to 3,031 compiled in scope (the denominator grew too, from
> 4,539 to 4,824, as dances these had blocked now reach a verdict), and the
> core set from 410 to 435, with no previously compiling dance lost. No
> corpus dance has two meanwhile parts moving the same dancer.
>
> **Hall figures led by part of the set (2026-11-23)** are built on Hudson's
> rulings ("ones lead down/up" and "go down/up the outside" move the set like a
> cast). Against `rubric` at `ee39d32f` they took the count from 3,031 to
> 3,116 compiled in scope (the denominator grew from 4,824 to 4,970), with the
> core set unchanged at 435 and no previously compiling dance lost. Of the 85
> new passes, 36 are triple-minor dances, which this compiler reads as Duple
> Improper (with its existing warning). Five of the 85 (two duple, three
> triple) lead past two couples in their text, which the import drops, and
> compile on a one-place reading. Five dances that refused now mismatch.
>
> **Side-opening half heys (2026-11-23)** are built on Hudson's ruling: they
> end like a centre-opening half hey, each pair exchanging. Against `rubric` at
> `f18e1b68` they took the count from 3,116 to 3,236 compiled in scope (the
> denominator grew from 4,970 to 5,104), and the core set from 435 to 458, with
> no previously compiling dance lost. All 120 new passes are duple improper or
> Becket; 17 dances that refused now mismatch.
>
> **Hall round trips (2026-11-23)** follow Hudson's ruling that a lead out
> immediately followed by a lead back moves nobody else. Against `rubric` at
> `29402576` they took the count from 3,245 to 3,253 compiled in scope (the
> denominator grew from 5,102 to 5,111), with the core set unchanged at 459
> and no previously compiling dance lost or changed.

The compiler implements 53 canonical figures. Twenty-eight have no deliberately
deferred parameter values, 25 have an implemented core with explicit
deferrals, and one of the figures this table has tracked since September
remains entirely deferred (taxonomy v36 to v40 added five more, of which
`circular_hey` and `cast` are now built; see `implementation.md` §15). The
`meanwhile` and `modifier` structural containers are built too, but they are
not normal taxonomy moves and are therefore counted separately. A top-level
`sequence` container is danced as the figures it holds (`implementation.md`
§10.1), and one nested in a container is danced in order (`taxonomy.md`,
"Containers").

The current headline result is **2,035 of 3,254 in-scope dances compiled
(62.5%)**. "In scope" means the dance parsed without a custom/free-text figure
and was not stopped by a deliberately deferred move, vocabulary value, or
parameter value.

## Implementation summary

"Full parameter surface" means the accepted parameter surface contains no
deliberate `unsupportedParam` branch. It does not mean every dance containing
the figure compiles: another figure may fail, the final state may mismatch, or
the implementation may have a defect.

| Status | Count | Figures |
| --- | ---: | --- |
| **Full parameter surface** | 28 | `arch_and_dive`, `balance`, `balance_the_ring`, `box_circulate`, `box_the_gnat`, `butterfly_whirl`, `california_twirl`, `circle`, `contra_corners`, `courtesy_turn`, `facing_star`, `form_a_long_wave`, `form_long_waves`, `give_and_take`*, `pass_by`, `pass_the_ocean`, `petronella`, `revolving_door`, `roll_away`, `rory_o_more`, `slide_along_set`, `square_through`, `stand_still`, `star`, `star_through`, `turn_alone`, `turn_as_couples`, `zig_zag` |
| **Implemented with explicit deferrals** | 25 | `allemande`, `cast`, `chain`, `circular_hey`, `cross_trails`, `do_si_do`, `down_the_hall`, `figure_8`, `form_short_waves`, `gate`, `hey`, `long_lines`, `mad_robin`, `orbit`, `pass_through`, `poussette`, `promenade`, `pull_by`, `right_left_through`, `shoulder_round`, `slice`, `star_promenade`, `swing`, `two_hand_turn`, `up_the_hall` |
| **Entirely deferred canonical figures** | 1 | `dolphin_hey` |
| **Structural containers** | 3 | `meanwhile` (simultaneous figures by different dancers), `modifier` (a main figure changed by ordered modifier figures) and a nested `sequence`; none is an ordinary taxonomy move. Built 2026-11-23 |

The external vocabulary (`supportedMoves`) reports 63 supported names: the 53
canonical implementations, the three containers, and seven aliases that resolve
onto the canonical figures:

- `meltdown_swing` resolves to `swing`;
- `pull_by_dancers` and `pull_by_direction` resolve to `pull_by`;
- `see_saw` resolves to `do_si_do`;
- `swat_the_flea` resolves to `box_the_gnat`;
- `hand_cast` resolves to `gate`;
- `long_lines` resolves to `forward_and_back`, which the table above lists as
  `long_lines` because only its long-lines formation is built.

\* `give_and_take` has no deliberate parameter deferral, but it refuses a
hands four whose two takers stand on the same side of the set; see
[Known crashes](#known-crashes).

## Corpus results by implemented figure

Each dance is counted once for every canonical figure it contains. **Pass**
means the complete dance compiled to its claimed progression. **Mismatch**,
**refused**, and **crash** are also whole-dance outcomes, so those columns show
correlation rather than necessarily blaming the listed figure.

**At figure** is the directly attributable subset: the listed figure was the
first operation to refuse. Unsupported and unstructured records are excluded
from this table because the compiler never ran against them. **Pass rate** is
`pass / (pass + mismatch + refused + crash)`.

| Figure | Status | Pass | Mismatch | Refused | Crash | At figure | Pass rate |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `allemande` | Partial | 1,239 | 144 | 745 | 2 | 96 | 58.2% |
| `balance` | Full | 92 | 6 | 44 | 0 | 4 | 64.8% |
| `balance_the_ring` | Full | 403 | 22 | 146 | 0 | 0 | 70.6% |
| `box_circulate` | Full | 44 | 6 | 17 | 0 | 0 | 65.7% |
| `box_the_gnat` | Full | 165 | 18 | 71 | 0 | 15 | 65.0% |
| `california_twirl` | Full | 255 | 12 | 72 | 0 | 0 | 75.2% |
| `chain` | Partial | 995 | 85 | 504 | 2 | 0 | 62.7% |
| `circle` | Full | 1,376 | 142 | 846 | 1 | 0 | 58.2% |
| `courtesy_turn` | Full | 6 | 4 | 19 | 0 | 1 | 20.7% |
| `cross_trails` | Partial | 28 | 2 | 14 | 0 | 0 | 63.6% |
| `do_si_do` | Partial | 629 | 56 | 415 | 0 | 53 | 57.2% |
| `down_the_hall` | Partial | 146 | 23 | 147 | 0 | 14 | 46.2% |
| `facing_star` | Full | 25 | 3 | 4 | 0 | 0 | 78.1% |
| `figure_8` | Partial | 7 | 6 | 39 | 0 | 1 | 13.5% |
| `form_a_long_wave` | Full | 51 | 10 | 76 | 1 | 1 | 37.0% |
| `form_long_waves` | Full | 88 | 15 | 86 | 0 | 0 | 46.6% |
| `form_short_waves` | Partial | 151 | 16 | 210 | 1 | 62 | 39.9% |
| `gate` | Partial | 14 | 1 | 15 | 0 | 8 | 46.7% |
| `give_and_take` | Full* | 118 | 13 | 51 | 2 | 0 | 64.1% |
| `hey` | Partial | 687 | 103 | 492 | 0 | 211 | 53.6% |
| `long_lines` | Partial | 753 | 72 | 454 | 3 | 0 | 58.7% |
| `mad_robin` | Partial | 128 | 11 | 54 | 0 | 11 | 66.3% |
| `orbit` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `pass_by` | Full | 137 | 20 | 77 | 0 | 0 | 58.5% |
| `pass_the_ocean` | Full | 44 | 8 | 46 | 0 | 11 | 44.9% |
| `pass_through` | Partial | 468 | 52 | 297 | 1 | 0 | 57.2% |
| `petronella` | Full | 281 | 36 | 113 | 0 | 0 | 65.3% |
| `poussette` | Partial | 34 | 5 | 15 | 0 | 0 | 63.0% |
| `pull_by` | Partial | 112 | 20 | 96 | 1 | 7 | 48.9% |
| `right_left_through` | Partial | 384 | 47 | 252 | 0 | 76 | 56.2% |
| `roll_away` | Full | 201 | 19 | 87 | 0 | 10 | 65.5% |
| `rory_o_more` | Full | 4 | 0 | 70 | 0 | 55 | 5.4% |
| `shoulder_round` | Partial | 154 | 37 | 121 | 0 | 29 | 49.4% |
| `slide_along_set` | Full | 163 | 45 | 154 | 1 | 2 | 44.9% |
| `square_through` | Full | 114 | 16 | 53 | 1 | 6 | 62.0% |
| `stand_still` | Full | 0 | 0 | 0 | 0 | 0 | - |
| `star` | Full | 721 | 83 | 354 | 0 | 0 | 62.3% |
| `star_promenade` | Partial | 17 | 2 | 12 | 0 | 1 | 54.8% |
| `star_through` | Full | 60 | 2 | 17 | 0 | 1 | 75.9% |
| `swing` | Partial | 2,004 | 229 | 1,239 | 3 | **584** | 57.7% |
| `turn_alone` | Full | 58 | 16 | 45 | 0 | 0 | 48.7% |
| `turn_as_couples` | Full | 1 | 0 | 0 | 0 | 0 | 100.0% |
| `two_hand_turn` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `up_the_hall` | Partial | 146 | 23 | 146 | 0 | 0 | 46.3% |
| `zig_zag` | Full | 37 | 12 | 47 | 0 | 0 | 38.5% |

## Explicit deferrals inside implemented figures

### Rotation and wave landings

- `allemande`, `do_si_do`, and `shoulder_round` defer across-the-set
  quarter-turn landings.
- `two_hand_turn`, `mad_robin`, `orbit`, and `star_promenade` defer quarter and
  three-quarter amounts entirely.

### Direction and axis

- `pass_through` and the direction-selected form of `pull_by` support the
  along/across axes only.
- `cross_trails`, `right_left_through`, and `form_short_waves` support across
  only.
- `chain dir:along` is deferred as four-facing-four choreography.
- `promenade` supports `where: across` for side-by-side pairs only. Single-file
  promenades, stated destinations, every other `where`, and a `direction`
  stated `unspecified` are deferred. (A Caller's Box promenade that imports
  with no `where` is not a deferral: see "Entirely deferred impact".)
- Diagonal `hey` is deferred behind diagonal `right_left_through`, which it
  must agree with.

### Dancer sets

- `shadows` is modelled (`taxonomy.md`, "Shadows"). `secondShadows` and the
  corner sets are still refused at parse time as unmodelled vocabulary values.

### Amounts and fractions

- `poussette` and `figure_8` support half and full amounts only.
- `hey` defers mid-pass lengths and late ricochets that cannot occur at the
  stated length. A side-opening half hey is built (user-ruled 2026-11-23).

### Hall figures

- A whole-hands-four `down_the_hall` or `up_the_hall` requires `moving:all`.
- Led by part of the set (`who:ones`, `twos`, `role1s` or `role2s`; user-ruled
  2026-11-23), the leaders move one place and the dancers they pass step back
  one. They take `moving:center` or `outsides`, `facing:forward`, and the
  `none` or `turnAlone` enders; leads by `partners`, a single lead ending
  `turnCouple`, and the rest stay deferred.
- A lead out immediately followed by the same leaders' lead back is a round
  trip (user-ruled 2026-11-23): nobody else moves, and the leaders end where
  they started, or in their partner's place after a `turnCouple`. Role-set
  leaders cannot trade, so their `turnCouple` stays deferred.
- The `cozy`, `cloverleaf`, `threadNeedle`, and `rightHandHigh` enders remain
  deferred.

### Other boundaries

- `slice` supports `by: couple` with a straight or diagonal return; `by: dancer`
  and `return: none` are deferred.
- `gate` turns a fractional amount (¼, ¾, 1¼) only between a complete hands
  four and a line of four; a landing that would be a two-faced line (what a
  same-sense gate from the ring makes) stays deferred. An unstated turn is
  refused except for a bare hand cast closing a line of four, which lands as
  `bendTheLine` does. `face:along` is refused.
- `long_lines` requires `goBack:true`.
- `swing` supports side-column landings but not `where:center`.
- Couple-`who` `orbit` executes under the existing ruling, but its true
  compound `meanwhile` interaction remains unresolved. It is less strongly
  grounded than the same-role case.

## Failure hotspots

The largest directly attributable first-refusal populations are:

| Figure | First refusals |
| --- | ---: |
| `swing` | **584** |
| `hey` | **211** |
| `allemande` | **96** |
| `right_left_through` | **76** |
| `form_short_waves` | **62** |
| `rory_o_more` | **55** |
| `do_si_do` | **53** |

`swing` is the largest genuine gap in the active denominator. Most of its
refusals are `whoMismatch`: the named relationship does not match the dancers
physically standing in swing position.

The largest mismatch associations are `swing` 229, `allemande` 144, `circle`
142, `hey` 103, `chain` 85, `star` 83, and `long_lines` 72. These are
not causally attributed. A mismatch is detected only after the entire dance
runs.

## Entirely deferred impact

"Dances mentioning it" includes dances already blocked elsewhere or rejected
as unstructured. "First unsupported blocker" is the direct coverage
opportunity.

| Deferred surface | Dances mentioning it | First unsupported blocker |
| --- | ---: | ---: |
| `dolphin_hey` | 0 | 0 |

`promenade` left this table when its `across` form was built, and
`butterfly_whirl`, `slice`, `revolving_door`, `arch_and_dive` and
`contra_corners` when they were (2026-11-22), and `meanwhile` when it was
(2026-11-23).
On the Caller's Box mirror, 98 more dances hold a promenade that imports with no `where`
(whole-set, counter-rotating, around-a-dancer and mixer promenades). They are
reported as `unstructured`, an import-pipeline problem, not as a deferral.

## Overall corpus state

| Outcome | Count |
| --- | ---: |
| Compiled | 2,035 |
| Final-state mismatch | 241 |
| Figure refused | 1,259 |
| Compiler crashed | 3 |
| Unsupported before compilation | 1,430 |
| Custom/free-text figure present | 6,531 |
| No figures supplied | 9,017 |
| Adapter failed | 3,591 |
| **Total** | **24,107** |

- **In-scope success:** 2,035 / 3,254, **62.5%**.
- **All-attempted success:** 2,035 / 3,538, **57.5%**.
- **Deferred exclusions:** 1,714 dances.
- The in-scope rate is a conservative floor. A genuine early refusal may hide
  a later deferred figure, leaving the dance in the denominator.
- The upstream source ceiling remains material: 6,531 records contain at least
  one figure left as `custom`. Standing policy rejects the whole dance rather
  than compiling around unknown choreography.

## Known crashes

The tables and headline above were measured before the changes below, so they
still count three crashes.

No dance currently escapes the operation error channel.

*Gypsy for Chris & Sara* (9779) used to collide at `r0,c2`. It opens with a
slide left, which leaves a couple standing out in each end row, and
`form_a_long_wave` stepped the standing-out dancers into the centre too. The
next settle does not cover those rows, so the other role's step-in landed on
them. `form_a_long_wave` now steps in only the dancers of active hands fours,
as `fundamentals.md` §10.3.2 already required of every figure. Measured on the
Caller's Box mirror against `rubric` at `f18e1b68`: the dance now refuses at
its later allemande, 9 dances that refused or mismatched now compile (1 in the
core set: *Toward Your Partner*), and none is lost.

*The Digital Divide* (12771) and *Road to Rochester* (4292) used to collide at
`r0,c0` inside `give_and_take`: both takers of one hands four stood on the same
side of the set, so each slid along that column into the cell the other's
taken partner was entering. `give_and_take` now refuses that state as an
`unresolvableDancerSet` before moving anyone. *(Proposed as the agent's call on
2026-11-22; user-ruled 2026-11-23: a refusal rather than a crash.)* Measured in a local corpus
sweep on 2026-11-22: both dances now end `FIGUREREFUSED` at their
`give_and_take`. The evidence so far points at an earlier wrong position rather
than at the permutation: both dances progress mid-dance (*The Digital Divide*
repeats its 64 beats with N2; *Road to Rochester* walks forward to N2 in A1),
the importer places the progression on a late figure, and a step trace of *The
Digital Divide* shows that after the N2 swing the original band phase is handed
back, so its first hands four holds two 2s couples when the second
`give_and_take` runs. Neither dance is checked in as a regression case, because the
committed Caller's Box corpus is deliberately one dance.

## Coverage blind spots

- `orbit`, `stand_still`, and `two_hand_turn` have no compiler-attempted corpus
  dances.
- `orbit` appears in four source records, but none reaches compilation: one is
  unsupported and three are unstructured. (September figures. Since
  2026-11-23 an orbit inside a `meanwhile` is compiled, as in *Binary System*
  (Caller's Box #10296), so this no longer holds; not re-counted.)
- `turn_as_couples` has one attempted example, so its nominal 100% rate is not
  meaningful.
- `rory_o_more` is now recognized in 74 attempted dances. Only four compile;
  its 55 direct refusals are a newly visible implementation hotspot. (Since
  2026-11-23 a Rory O'More danced from the side lines first forms the wave its
  slide implies, *user-ruled*. Measured on the Caller's Box mirror against
  `rubric` at `29402576`, together with the figure no longer sliding a couple
  standing out (§10.3.2): 45 dances that refused now compile (14 in the core
  set), 2 that refused now mismatch (*Mistletoe*, 15972, and *Mongoose
  Stomp*, 18142, both with the progression assumed at a later figure), and
  none is lost. The table above is not re-counted.)

## Validation and refresh

At this snapshot:

- `fvm dart analyze` is clean;
- `fvm dart test` passes **1,019 tests**, with one skipped corpus test.

The headline corpus report can be refreshed with:

```powershell
fvm dart run bin\callersbox_harness.dart --quiet $env:RUBRIC_TCB_CORPUS
```

The per-figure table uses the same `DanceRun` results, canonicalizes aliases
through `compendium_core`'s contra taxonomy, and counts each dance once for
each canonical figure it contains. It additionally parses the first
`figureRefused` result to populate the **At figure** attribution column.
