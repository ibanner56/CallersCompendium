# Implementation status

> Measured on September 15, 2026, from branch `rubric` after merging
> `origin/main` at `8f180a9` and applying taxonomy-v35 compatibility.
> The corpus is the 24,107-file local Caller's Box mirror described in
> [`implementation.md`](implementation.md). These numbers are a snapshot:
> re-run the corpus harness after figure, parser, or `compendium_core` changes.

The compiler implements 45 canonical figures. Twenty-four have no deliberately
deferred parameter values, 21 have an implemented core with explicit
deferrals, and seven current `compendium_core` taxonomy figures remain entirely
deferred. The `meanwhile` structural container is also deferred, but it is not
a normal taxonomy move and is therefore counted separately.

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
| **Full parameter surface** | 24 | `balance`, `balance_the_ring`, `box_circulate`, `box_the_gnat`, `california_twirl`, `circle`, `courtesy_turn`, `facing_star`, `form_a_long_wave`, `form_long_waves`, `give_and_take`*, `pass_by`, `pass_the_ocean`, `petronella`, `roll_away`, `rory_o_more`, `slide_along_set`, `square_through`, `stand_still`, `star`, `star_through`, `turn_alone`, `turn_as_couples`, `zig_zag` |
| **Implemented with explicit deferrals** | 21 | `allemande`, `chain`, `cross_trails`, `do_si_do`, `down_the_hall`, `figure_8`, `form_short_waves`, `gate`, `hey`, `long_lines`, `mad_robin`, `orbit`, `pass_through`, `poussette`, `pull_by`, `right_left_through`, `shoulder_round`, `star_promenade`, `swing`, `two_hand_turn`, `up_the_hall` |
| **Entirely deferred canonical figures** | 7 | `arch_and_dive`, `butterfly_whirl`, `contra_corners`, `dolphin_hey`, `promenade`, `revolving_door`, `slice` |
| **Deferred structural construct** | 1 | `meanwhile`, which represents simultaneous figures rather than an ordinary taxonomy move |

The external vocabulary reports 50 supported names because five aliases
resolve onto the 45 canonical implementations:

- `meltdown_swing` resolves to `swing`;
- `pull_by_dancers` and `pull_by_direction` resolve to `pull_by`;
- `see_saw` resolves to `do_si_do`;
- `swat_the_flea` resolves to `box_the_gnat`.

\* `give_and_take` has no deliberate parameter deferral, but it has a known
runtime defect described under [Known crashes](#known-crashes).

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
- Diagonal `hey` is deferred behind diagonal `right_left_through`, which it
  must agree with.

### Amounts and fractions

- `poussette` and `figure_8` support half and full amounts only.
- `hey` defers mid-pass lengths, late ricochets that cannot occur at the stated
  length, and side-opening heys shorter than full.

### Hall figures

- `down_the_hall` and `up_the_hall` require `who:everyone` and `moving:all`.
- The `cozy`, `cloverleaf`, `threadNeedle`, and `rightHandHigh` enders remain
  deferred.

### Other boundaries

- `gate` requires a stated whole or half turn and refuses `face:along`.
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
| `promenade` | 1,194 | **546** |
| `butterfly_whirl` | 322 | **175** |
| `slice` | 260 | **146** |
| `meanwhile` structural container | 1,540 | **131** |
| `revolving_door` | 75 | **44** |
| `contra_corners` | 201 | **40** |
| `arch_and_dive` | 0 | 0 |
| `dolphin_hey` | 0 | 0 |

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

Three dances currently escape the operation error channel and throw a cell
collision:

| Caller's Box id | Dance | Collision | Current attribution |
| ---: | --- | --- | --- |
| 12771 | The Digital Divide | `r0,c0` | Contains `give_and_take`; consistent with the known give-and-take collision |
| 4292 | Road to Rochester | `r0,c0` | Contains `give_and_take`; consistent with the known give-and-take collision |
| 9779 | Gypsy for Chris & Sara | `r0,c2` | Separate centre-cell collision in a dance containing long-wave and simultaneous-figure choreography; exact operation not yet isolated |

Earlier implementation notes attributed all three crashes to `give_and_take`.
The current evidence corrects that: `give_and_take` accounts for two of the
three. The third needs a separate investigation.

## Coverage blind spots

- `orbit`, `stand_still`, and `two_hand_turn` have no compiler-attempted corpus
  dances.
- `orbit` appears in four source records, but none reaches compilation: one is
  unsupported and three are unstructured.
- `turn_as_couples` has one attempted example, so its nominal 100% rate is not
  meaningful.
- `rory_o_more` is now recognized in 74 attempted dances. Only four compile;
  its 55 direct refusals are a newly visible implementation hotspot.

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
