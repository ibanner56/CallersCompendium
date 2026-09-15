# Implementation status

> Measured on September 15, 2026, from branch `rubric` at commit `9fcef5b`.
> The corpus is the 24,107-file local Caller's Box mirror described in
> [`implementation.md`](implementation.md). These numbers are a snapshot:
> re-run the corpus harness after figure, parser, or `compendium_core` changes.

The compiler implements 46 canonical figures. Twenty-five have no deliberately
deferred parameter values, 21 have an implemented core with explicit
deferrals, and seven current `compendium_core` taxonomy figures remain entirely
deferred. The `meanwhile` structural container is also deferred, but it is not
a normal taxonomy move and is therefore counted separately.

The current headline result is **1,950 of 3,285 in-scope dances compiled
(59.4%)**. "In scope" means the dance parsed without a custom/free-text figure
and was not stopped by a deliberately deferred move, vocabulary value, or
parameter value.

## Implementation summary

"Full parameter surface" means the accepted parameter surface contains no
deliberate `unsupportedParam` branch. It does not mean every dance containing
the figure compiles: another figure may fail, the final state may mismatch, or
the implementation may have a defect.

| Status | Count | Figures |
| --- | ---: | --- |
| **Full parameter surface** | 25 | `balance`, `balance_the_ring`, `box_circulate`, `box_the_gnat`, `california_twirl`, `circle`, `courtesy_turn`, `facing_star`, `form_a_long_wave`, `form_long_waves`, `give_and_take`*, `pass_by`, `pass_the_ocean`, `petronella`, `pull_by_dancers`, `roll_away`, `rory_o_more`, `slide_along_set`, `square_through`, `stand_still`, `star`, `star_through`, `turn_alone`, `turn_as_couples`, `zig_zag` |
| **Implemented with explicit deferrals** | 21 | `allemande`, `chain`, `cross_trails`, `do_si_do`, `down_the_hall`, `figure_8`, `form_short_waves`, `gate`, `hey`, `long_lines`, `mad_robin`, `orbit`, `pass_through`, `poussette`, `pull_by_direction`, `right_left_through`, `shoulder_round`, `star_promenade`, `swing`, `two_hand_turn`, `up_the_hall` |
| **Entirely deferred canonical figures** | 7 | `arch_and_dive`, `butterfly_whirl`, `contra_corners`, `dolphin_hey`, `promenade`, `revolving_door`, `slice` |
| **Deferred structural construct** | 1 | `meanwhile`, which represents simultaneous figures rather than an ordinary taxonomy move |

The external vocabulary reports 49 supported names because three aliases
resolve onto the 46 canonical implementations:

- `meltdown_swing` resolves to `swing`;
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
| `allemande` | Partial | 1,197 | 207 | 748 | 2 | 98 | 55.6% |
| `balance` | Full | 88 | 11 | 43 | 0 | 4 | 62.0% |
| `balance_the_ring` | Full | 343 | 78 | 151 | 0 | 0 | 60.0% |
| `box_circulate` | Full | 53 | 17 | 33 | 0 | 0 | 51.5% |
| `box_the_gnat` | Full | 162 | 21 | 71 | 0 | 15 | 63.8% |
| `california_twirl` | Full | 226 | 45 | 68 | 0 | 0 | 66.7% |
| `chain` | Partial | 952 | 135 | 509 | 2 | 0 | 59.6% |
| `circle` | Full | 1,308 | 239 | 834 | 1 | 0 | 54.9% |
| `courtesy_turn` | Full | 6 | 4 | 19 | 0 | 1 | 20.7% |
| `cross_trails` | Partial | 26 | 5 | 13 | 0 | 0 | 59.1% |
| `do_si_do` | Partial | 616 | 75 | 413 | 0 | 62 | 55.8% |
| `down_the_hall` | Partial | 143 | 26 | 147 | 0 | 14 | 45.3% |
| `facing_star` | Full | 23 | 5 | 4 | 0 | 0 | 71.9% |
| `figure_8` | Partial | 7 | 6 | 39 | 0 | 1 | 13.5% |
| `form_a_long_wave` | Full | 50 | 16 | 86 | 1 | 1 | 32.7% |
| `form_long_waves` | Full | 89 | 15 | 91 | 0 | 0 | 45.6% |
| `form_short_waves` | Partial | 173 | 20 | 203 | 1 | 81 | 43.6% |
| `gate` | Partial | 14 | 1 | 15 | 0 | 8 | 46.7% |
| `give_and_take` | Full* | 114 | 22 | 47 | 2 | 0 | 61.6% |
| `hey` | Partial | 661 | 140 | 496 | 0 | 212 | 51.0% |
| `long_lines` | Partial | 719 | 117 | 453 | 3 | 0 | 55.7% |
| `mad_robin` | Partial | 124 | 15 | 56 | 0 | 13 | 63.6% |
| `orbit` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `pass_by` | Full | 134 | 23 | 78 | 0 | 0 | 57.0% |
| `pass_the_ocean` | Full | 41 | 11 | 47 | 0 | 11 | 41.4% |
| `pass_through` | Partial | 473 | 63 | 293 | 1 | 0 | 57.0% |
| `petronella` | Full | 257 | 67 | 111 | 0 | 0 | 59.1% |
| `poussette` | Partial | 31 | 7 | 16 | 0 | 0 | 57.4% |
| `pull_by_dancers` | Full | 111 | 22 | 96 | 1 | 7 | 48.3% |
| `pull_by_direction` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `right_left_through` | Partial | 370 | 60 | 258 | 0 | 78 | 53.8% |
| `roll_away` | Full | 84 | 126 | 98 | 0 | 11 | 27.3% |
| `rory_o_more` | Full | 0 | 0 | 0 | 0 | 0 | - |
| `shoulder_round` | Partial | 380 | 89 | 271 | 1 | 45 | 51.3% |
| `slide_along_set` | Full | 178 | 59 | 186 | 1 | 2 | 42.0% |
| `square_through` | Full | 115 | 18 | 50 | 1 | 6 | 62.5% |
| `stand_still` | Full | 0 | 0 | 0 | 0 | 0 | - |
| `star` | Full | 711 | 100 | 356 | 0 | 0 | 60.9% |
| `star_promenade` | Partial | 17 | 2 | 12 | 0 | 1 | 54.8% |
| `star_through` | Full | 58 | 4 | 17 | 0 | 1 | 73.4% |
| `swing` | Partial | 1,919 | 350 | 1,239 | 3 | **587** | 54.7% |
| `turn_alone` | Full | 75 | 24 | 140 | 0 | 0 | 31.4% |
| `turn_as_couples` | Full | 1 | 0 | 0 | 0 | 0 | 100.0% |
| `two_hand_turn` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `up_the_hall` | Partial | 143 | 26 | 146 | 0 | 0 | 45.4% |
| `zig_zag` | Full | 36 | 14 | 46 | 0 | 0 | 37.5% |

## Explicit deferrals inside implemented figures

### Rotation and wave landings

- `allemande`, `do_si_do`, and `shoulder_round` defer across-the-set
  quarter-turn landings.
- `two_hand_turn`, `mad_robin`, `orbit`, and `star_promenade` defer quarter and
  three-quarter amounts entirely.

### Direction and axis

- `pass_through` and `pull_by_direction` support the along/across axes only.
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
| `swing` | **587** |
| `hey` | **212** |
| `allemande` | **98** |
| `form_short_waves` | **81** |
| `right_left_through` | **78** |
| `do_si_do` | **62** |
| `shoulder_round` | **45** |

`swing` is the largest genuine gap in the active denominator. Most of its
refusals are `whoMismatch`: the named relationship does not match the dancers
physically standing in swing position.

The largest mismatch associations are `swing` 350, `circle` 239, `allemande`
207, `hey` 140, `chain` 135, `roll_away` 126, and `long_lines` 117. These are
not causally attributed. A mismatch is detected only after the entire dance
runs.

## Entirely deferred impact

"Dances mentioning it" includes dances already blocked elsewhere or rejected
as unstructured. "First unsupported blocker" is the direct coverage
opportunity.

| Deferred surface | Dances mentioning it | First unsupported blocker |
| --- | ---: | ---: |
| `promenade` | 1,194 | **547** |
| `butterfly_whirl` | 322 | **175** |
| `slice` | 260 | **146** |
| `meanwhile` structural container | 1,545 | **132** |
| `revolving_door` | 75 | **42** |
| `contra_corners` | 201 | **40** |
| `arch_and_dive` | 0 | 0 |
| `dolphin_hey` | 0 | 0 |

## Overall corpus state

| Outcome | Count |
| --- | ---: |
| Compiled | 1,950 |
| Final-state mismatch | 362 |
| Figure refused | 1,259 |
| Compiler crashed | 3 |
| Unsupported before compilation | 1,435 |
| Custom/free-text figure present | 6,490 |
| No figures supplied | 9,017 |
| Adapter failed | 3,591 |
| **Total** | **24,107** |

- **In-scope success:** 1,950 / 3,285, **59.4%**.
- **All-attempted success:** 1,950 / 3,574, **54.6%**.
- **Deferred exclusions:** 1,724 dances.
- The in-scope rate is a conservative floor. A genuine early refusal may hide
  a later deferred figure, leaving the dance in the denominator.
- The upstream source ceiling remains material: 6,490 records contain at least
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

- `pull_by_direction`, `rory_o_more`, `stand_still`, and `two_hand_turn` have no
  compiler-attempted corpus dances.
- `orbit` appears in four source records, but none reaches compilation: one is
  unsupported and three are unstructured.
- `turn_as_couples` has one attempted example, so its nominal 100% rate is not
  meaningful.
- `rory_o_more` remaining entirely absent strongly suggests an upstream
  recognition gap rather than genuine corpus absence.

## Validation and refresh

At this snapshot:

- `fvm dart analyze` is clean;
- `fvm dart test` passes **1,015 tests**, with one skipped corpus test.

The headline corpus report can be refreshed with:

```powershell
fvm dart run bin\callersbox_harness.dart --quiet $env:RUBRIC_TCB_CORPUS
```

The per-figure table uses the same `DanceRun` results, canonicalizes aliases
through `compendium_core`'s contra taxonomy, and counts each dance once for
each canonical figure it contains. It additionally parses the first
`figureRefused` result to populate the **At figure** attribution column.
