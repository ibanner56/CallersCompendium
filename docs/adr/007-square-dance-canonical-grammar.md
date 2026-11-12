# ADR-007: Square dance canonical call grammar

- **Status**: Proposed (12 November 2026). For maintainer review before
  anything is implemented.
- **Roadmap item**: "ECD and Squares support" (Later milestones in
  [ROADMAP.md](../ROADMAP.md))
- **Deciders**: Maintainers

**What we're asking the reviewer for:** a decision on each principle in §5,
corrections to the registry in §7, and answers to the
[open questions](#10-open-questions).

In the template's terms: §2–§3 are the *context*, §5–§8 the proposed
*decision*, §5 the *rationale*, and §9–§11 the *consequences* and *revisit
triggers*. Once accepted, the square taxonomy follows the versioning process in
[figure-taxonomy.md](../design/figure-taxonomy.md), as the contra one does.

Timing figures in §7 are reprinted with permission of CALLERLAB (§4.1).

---

## Contents

1. [Summary](#1-summary)
2. [Background: how square dance differs](#2-background-how-square-dance-differs)
3. [Where the app stands today](#3-where-the-app-stands-today)
4. [Sources and licensing](#4-sources-and-licensing)
5. [Design principles](#5-design-principles)
6. [Shared vocabulary](#6-shared-vocabulary)
7. [The call registry](#7-the-call-registry)
8. [Dance structure, entry, glossary and import](#8-dance-structure-entry-glossary-and-import)
9. [Delivery phases](#9-delivery-phases)
10. [Open questions](#10-open-questions)
11. [Consequences and revisit triggers](#11-consequences-and-revisit-triggers)
12. [Appendix A: worked examples](#appendix-a-worked-examples)
13. [Appendix B: sources](#appendix-b-sources)

---

## 1. Summary

Caller's Compendium stores contra figures as structured data: a canonical
move plus named parameters. This ADR proposes the same for Modern Western
Square Dance (MWSD), with a **separate taxonomy** that owns every call ID. A
call such as Allemande Left or Dosado is defined in the square taxonomy on
its own terms, even where contra has a figure with the same name. This
follows the approach ADR-006 proposed for English Country Dance.

### 1.1 Maintainer requirements

The maintainer set these requirements in the planning conversation that led
to this ADR (12 November 2026; quoted in the pull request that adds it). They
are inputs to the design, not proposals:

- The square taxonomy is **fully independent** of the contra taxonomy, as
  ADR-006 proposes for ECD, even where figures share a name.
- **Mainstream and Plus** are the success criteria. Advanced and Challenge
  are stretch goals, to be included if they turn out to be trivial once the
  framework exists.
- Calls carry **beat counts**.
- Dance entry has a **toggle for free-form patter** that does not follow
  fixed phrasing.
- The glossary offers a **switcher between contra and squares** that can
  take ECD later, so it is not a two-way toggle.
- [Taminations](https://github.com/bradchristie/taminations-flutter) is a
  **reference only**. No code is ported or copied from it, so the project
  takes on no licensing or attribution obligation.

### 1.2 The proposal in brief

Everything below is proposed by this ADR's author for the maintainer to
accept or change.

- **One taxonomy per dance form**, with square call IDs carrying an `sq_`
  prefix so they can never be mistaken for contra moves, including by older
  builds (§5.1).
- **Program membership is data that depends on the CALLERLAB edition**
  (§5.2). CALLERLAB replaced its Basic, Mainstream and SSD programs with a
  new Mainstream program on 1 September 2026, and moved several calls into a
  new Plus. A call's ID never changes when its program does.
- **Beats are stored on every call**, with defaults from CALLERLAB's
  published timing (§5.3).
- **Formations belong to calls, not to dances** (§5.4). The app does not
  simulate dancer positions.
- **Some calls take another call as an argument**, such as "(anything) and
  Roll" and "Clover and (anything)". This needs a new structural construct
  (§5.6), the largest new piece of model work in this ADR.
- **A `freeForm` flag** implements the patter toggle (§8.1).
- **The glossary's dance-form selector** is built over `DanceForm` values
  (§8.3).

Advanced is judged **moderate, not trivial** (§9), and Challenge **not
cheap**.

## 2. Background: how square dance differs

Contra dances are fixed 64-beat sequences, repeated, and their figures name
pairs of dancers (partners, neighbors, shadows). Square dance differs in four
ways that drive this design:

1. **Calls are a shared, standardized vocabulary.** CALLERLAB publishes
   definitions, timing, styling and standard applications for each program.
   Callers expect a call's name to mean the CALLERLAB definition, and the
   programs are cumulative: Plus dancers know all Mainstream calls.
2. **Most calling is improvised.** In patter ("hash") calling, the caller
   builds sequences on the fly and does not phrase them to the music. Only
   singing calls are phrased: a fixed 64-beat figure danced four times,
   between breaks.
3. **Formations change constantly.** A square starts in a static square, but
   between calls dancers may be in ocean waves, two-faced lines, columns,
   diamonds, a thar, and so on. Whether a call is proper depends on the
   formation it is called from.
4. **Dancers are named by position and identity more than by relationship.**
   Heads, sides, centers, ends, leaders, trailers, boys and girls, and
   couple numbers are used much more than partner and corner.

## 3. Where the app stands today

These facts were checked against the code on 12 November 2026:

- `DanceForm` already has a `square` value
  ([enums.dart](../../packages/compendium_core/lib/src/model/enums.dart)), and
  search can filter on it.
- The Caller's Companion importer maps a dance whose `Type` contains "square"
  to `DanceForm.square`, maps the "Square" formation family to
  `FormationShape.other` with detail "Square", and sets `mixer` from a
  square's `SubType` ("Mixer, H H S S")
  ([callers_companion_mapping.dart](../../packages/compendium_core/lib/src/imports/callers_companion_mapping.dart)).
  It parses the figure lines of these dances with the **contra** vocabulary
  (`parseFigureLinesFanOut`). So square dances imported so far hold contra
  moves (`swing`, `circle`, `promenade`, ...) or custom text. §8.4 deals
  with them.
- ECD dances also exist today (the same importer maps "English" to
  `DanceForm.ecd`). They hold contra moves too, because there is no ECD
  taxonomy yet.
- `FormationShape` has no square value.
- The taxonomy is per-form by design (`Taxonomy.form`). In practice 61
  non-test Dart files under `packages/` and `app/` refer to `contraTaxonomy`
  by name, 56 of them under a `lib/` directory. Some are contra-only by
  nature (the ContraDB and Caller's Box importers). The rest handle any dance
  and would need to resolve the taxonomy from the dance (§11).
- `MoveDef` supports a beat default per move and a `ParamBeats` table that
  picks beats from **one** parameter's value.
- Figures of your own already record a dance form
  (`UserFigureDefinition.form`, defaulting to `contra`), as do compound
  definitions. What is missing is the glossary and editor filtering on it.
- Dialect move wordings are keyed by move ID (`kMoveWordingBranchKeys` in
  [dialect.dart](../../packages/compendium_core/lib/src/dialect/dialect.dart)
  has a `promenade` entry).
- Structural containers (`meanwhile`, `modifier`, `sequence`) are a fixed
  set (`containerMoves` in
  [figure.dart](../../packages/compendium_core/lib/src/model/figure.dart)),
  with a maximum depth of two (`kMaxContainerDepth`).

## 4. Sources and licensing

### 4.1 CALLERLAB documents

The registry in §7 is built from the CALLERLAB documents in the project's
shared files. Appendix B lists them, and they cover:

- **Definitions** for Mainstream (rev. 29 March 2026), Plus (rev. 25 August
  2026, and the superseded 20 August 2025 edition), Advanced (rev. 27 August
  2026), C-1 (rev. 14 March 2026), C-2 (rev. 15 August 2026) and C-3A
  (rev. 1 September 2024).
- **Timing** for Mainstream and Plus (rev. 5 July 2026, effective 1
  September 2026) and Advanced (rev. 12 June 2025).
- **Standard Applications** for Basic (2022), Mainstream (2020) and Plus
  (2021).
- The **new Plus teaching order**, the Plus supplement guide, the Advanced
  booklet and the 2011 Definition Guide.

The definition documents allow reprints and derivative works without royalty
if their copyright notice appears, but say the information "shall not be
changed nor revised in any derivation". The timing lists allow reproduction
with the notice "Reprinted with permission of CALLERLAB." Because §7 of this
document reproduces most of the Mainstream and Plus timing lists, it carries
that notice at the top.

**Proposed by this ADR's author:** the app ships CALLERLAB call names,
program membership, formation names and timing numbers as data, and writes
**every glossary definition in its own words**. No definition text, styling
text or diagram is copied. Writing our own definitions keeps us clear of the
"not changed" condition, and lets definitions use the app's role-neutral
tokens. Whether the app's `THIRD_PARTY_NOTICES.md` also carries the CALLERLAB
reprint line for the timing data is Q1.

### 4.2 Taminations

Per the maintainer's requirement (§1.1), **no code, data files, animations,
formation geometry or definition text from Taminations may be copied, ported
or translated into this repository.** It may be consulted to cross-check how
a call is danced. It was not consulted for this draft, and the
implementation PRs should each say whether it was consulted and confirm
nothing was taken.

## 5. Design principles

Each principle is a proposal by this ADR's author. None has been decided
yet.

### 5.1 Squares own their call IDs, and the IDs carry a prefix

The square taxonomy is a separate `Taxonomy(form: DanceForm.square)`. Every
call in it has its own definition, defaults, display template and glossary
text. Where a square call and a contra move share a concept, they share
**parameter names** (`who`, `hand`, `fraction`, `beats`), as ADR-006 §5.1
proposes for ECD. They never share a definition.

Every square move ID starts with `sq_`: `sq_dosado`, `sq_swing`,
`sq_square_thru`. At least nine of the proposed calls have the same name as a
contra move or alias (`swing`, `allemande`, `circle`, `promenade`, `star`,
`box_the_gnat`, `california_twirl`, `courtesy_turn`, `balance`, and contra's
`see_saw` alias). With unprefixed IDs:

- **Older builds would misread square dances without any error.** A build
  from before this work that receives a square dance by sync, archive or
  share resolves every figure through `contraTaxonomy`, so `swing` and
  `circle` would render with their contra meaning and defaults. With a
  prefix the old build sees an unknown move: the renderer shows the raw ID
  and validation flags `unknown_move`. That is visible, not wrong.
- **Anything keyed by move ID would collide**: dialect move wordings,
  shorthand tables, and editor display defaults. A contra wording for
  `promenade` would reword the square call.
- **The legacy square imports (§3) become detectable.** An unprefixed ID in
  a square dance is known to be a contra move from an earlier import.

*Alternative rejected:* plain IDs, matching ADR-006's style, with the dance's
form as the only discriminator. It lost on the three points above. If this
is accepted, ADR-006 should probably adopt an `ecd_` prefix for the same
reasons (§11).

**Resolving a taxonomy.** Code that needs a taxonomy takes it from the dance:

- `square` → the square taxonomy for `sq_` IDs. Unprefixed IDs in a square
  dance resolve through the contra taxonomy as legacy figures until they are
  migrated (§8.4).
- `ecd` → the contra taxonomy, as today, until ADR-006 ships.
- `contra` → the contra taxonomy.

### 5.2 Program membership depends on the edition, and is data

CALLERLAB's 2025 "Proposal" restructured the programs from 1 September 2026:

- The **new Mainstream** program has 50 calls or call families and replaces
  the old Basic, Mainstream and SSD programs.
- The **new Plus** program has 50 entries, some of them from older lists.
  Do Paso and See Saw were legacy Basic calls. The August 2026 Advanced
  definitions record that Clover and (anything), Pair Off, Partner Hinge,
  Partner Tag, Pass the Sea, the Quarter Thru family, Scoot and Dodge and
  Triple Trade moved from A-1 to Plus.
- Advanced timing published before the change (June 2025) still lists some
  of those calls under A-1.

Callers' existing dances and notes use both the old and new program names,
so a call's program cannot be a fixed property of the call. Each square call
carries a map from **edition** to **program**:

```text
programs: { callerlab2026: plus, callerlabLegacy: a1 }
```

- Editions: `callerlabLegacy` (the lists in force before 1 September 2026)
  and `callerlab2026`. New editions are added as data.
- Programs: `basic`, `mainstream`, `plus`, `a1`, `a2`, `c1`, `c2`, `c3a`.
  `basic` appears only in the legacy edition.
- **A program can depend on where the call starts.** Some calls move up a
  program when danced from a less common start. Recycle from a wave is
  Mainstream but from facing couples is A-2, and the Advanced definitions
  also lift Plus restrictions on Explode and (anything), Coordinate and
  Linear Cycle. These calls get an optional `from` parameter naming the
  start (for Recycle: `wave` or `facingCouples`), and the program entry is
  keyed by its value, using the same mechanism as beats (§5.3). When `from`
  is `unspecified`, the lower program is assumed. `from` is stated by the
  caller, never computed (§5.4).
- A user setting chooses the edition the app shows, defaulting to
  `callerlab2026` (Q2).
- A dance's **required program** is derived, never stored: the highest
  program among its calls under the chosen edition. It is separate from the
  dance's user-defined difficulty level (ADR-005), which stays the caller's
  own judgment.

### 5.3 Beats are stored, with CALLERLAB timing as the default

ADR-006 §5.5 keeps timing out of ECD movement parameters. Squares keep
`beats` as a figure parameter, as contra does, because the maintainer
requires beat counts (§1.1), CALLERLAB publishes a standard count for nearly
every call through Advanced, and singing-call figures must fit 64 beats.

- **Default beats** come from the CALLERLAB timing tables, which count from
  the point of contact.
- **Defaults can depend on more than one parameter.** Square Thru takes 2,
  5, 7 or 8, or 10 beats for 1 to 4 hands. Circle takes 16, 12, 8 or 4 for a
  full, three-quarter, half or quarter circle of eight, and half that for a
  circle of four. `ParamBeats` must be extended to read several parameters.
- **From a static square.** The Mainstream definitions' Squared Set
  Convention says "Moving into the center adds 2 beats to the timing for the
  move". Where the timing table gives its own static-square value, that value
  wins: Pass Thru 4, Right and Left Thru 8, Flutterwheel 10 or 12. Square
  Thru's entry says "SS odd numbers: add 2 to previous count". ⚠ This ADR
  reads that as: only odd counts add 2 from a static square, so Heads Square
  Thru 4 stays 10. The other reading, that every count adds 2, gives 12
  (Q9). The +2 applies only to calls defined from facing dancers or facing
  couples, which is what the Convention covers. The app cannot tell where
  the dancers are (§5.4), so the adjustment is driven by an explicit
  `fromStaticSquare` flag. For a `singingCall` or `break` the editor sets it
  on the first call; for `patter` it starts off, because a module may begin
  anywhere. The caller can set or clear it on any line.
- **Ranges and "variable".** A range such as "4 to 6" sets `goodBeats` and
  the lower value as the default. "Variable, at least 4" (Swing) sets a
  default of 4 and no upper warning. As in contra, beat counts outside
  `goodBeats` are warnings, never errors, and the caller can always override.
- **Calls with no published timing** (all of Challenge, and concepts such as
  As Couples) default to `unspecified` beats.

### 5.4 Formations describe calls, not dances

Every square dance starts and ends in a squared set. So at dance level the
formation is simply a new `FormationShape.square`, and the importer stops
using `other` + "Square".

At call level each call in the registry records:

- `startFormations`: the usual formations the call is danced from. Like
  CALLERLAB's own lists, they are **not restrictive** unless marked `only`.
- `endFormation`: what the call produces from each start formation, where
  that is fixed.
- `rules`: which CALLERLAB conventions apply (Ocean Wave Rule, Facing
  Couples Rule, Squared Set Convention).

These are shipped taxonomy data, not stored on figures. The glossary shows
them, and the editor may use them for **hints** (for example, "Spin the Top
is usually called from an ocean wave"). **The app does not track or simulate
dancer positions.** It does not check that a sequence resolves, and it does
not warn that a call is improper from the previous call's formation. A
position simulator is a large project of its own, and the area where copying
from Taminations would be most tempting. It is out of scope (§11).

Whether a stored call should also be able to record a formation the caller
*states* ("from a zero box", "in normal lines") is Q4.

### 5.5 Selectors name dancers the way callers do

`who` is a single selector token, as in contra. ADR-006 §5.2 makes ECD's
`who` a list because ECD figures often name two groups ("2s and 3s"). Square
calls name one group, and CALLERLAB's identifiers already cover combined
groups (`centerFour`, `heads`), so a single token is enough. §6.2 lists the
square selectors. Two rules carry over from the existing taxonomy:

- **Role-neutral storage.** Boys and girls are stored as `role1s` and
  `role2s`, and shown in the caller's chosen terms by the dialect system.
  Square callers often want "boys and girls" or "men and ladies" while
  calling contra with "larks and robins", so the dialect needs role terms
  per dance form (§11).
- **Heads and sides mean the original heads and sides**, as CALLERLAB
  defines them. "Those in the head position" is a separate selector.

### 5.6 Calls that take a call

Some calls are built around another call:

- Mainstream: "Square Thru, on the third hand (anything)".
- Plus: "(anything) and Roll", "(anything) and Spread", "Clover and
  (anything)", "Explode and (anything)".
- Advanced: "Cross Clover and (anything)", "Transfer and (anything)", "Any
  Hand (anything)", and concepts such as "As Couples (anything)".

These calls get a `call` parameter whose value is **one nested figure**,
encoded with the same figure codec.

This is a **new structural construct**, not a small extension. Today the
only figures that nest other figures are the three containers, and every
site that walks figures asks `isContainerMove`. A figure-valued parameter
on an ordinary call must be taught to the codec, the archive and share
sanitizer, validation, the renderer, the search and full-text indexer, the
editor, and sync. Phase 2 (§9) carries that cost.

Rules proposed for it:

- A call-taking call counts as one level toward the existing
  `kMaxContainerDepth` of two. "As Couples (Swing Thru and Roll)" fits.
  Deeper stacking, such as "As Couples (Clover and (Square Thru, on the third
  hand Spin the Top))", does not, and stays a `custom` line with its text.
- Display substitutes the nested call's rendering into the template, for
  example `Clover and {call}`.
- Beats: the call's default comes from a rule over the nested call's beats
  ("the greater of 4 and the call", "2 plus the call"). Where CALLERLAB's
  timing overlaps the two calls ("Transfer and (anything): 8, anything starts
  on 5"), the default is the stated total plus whatever the nested call takes
  beyond the overlap, and the caller can override it.

Split Two is **not** a call-taking call. Its timing is "2 plus the next
call", but the next call is an ordinary following line.

*Alternatives rejected:*

- Recording "Clover and Pass Thru" as a `sequence` of two figures loses the
  fact that the two calls are danced together, with one timing.
- The `modifier` container renders "X, Y-ing", which reads wrongly for
  "Swing Thru and Roll".
- One move per combination ("clover_and_pass_thru") cannot list every
  combination.

### 5.7 Parts of a call are not stored

"Recycle" or "Spin the Top" is one line. The app does not break a call into
its CALLERLAB parts or dance actions. As in ADR-006 §5.3, a parameter the
source does not state is stored as `unspecified`, unless CALLERLAB defines
the bare call's meaning (Square Thru means Square Thru 4, so `count`
defaults to 4).

## 6. Shared vocabulary

### 6.1 Parameter names

| Name | Meaning | Example values |
| --- | --- | --- |
| `who` | Who dances the call | `everyone`, `heads`, `centers`, `role2s` |
| `hand` | The hand used, or a left-hand version of the call | `right`, `left` |
| `fraction` | How far | `quarter`, `half`, `threeQuarters`, `full` |
| `count` | A number of hands or parts | Square Thru 1–5, Eight Chain 1–8 |
| `direction` | A turning or travel direction | `left`, `right`, `in`, `out` |
| `reverse` | The reverse version of the call | yes/no (Flutterwheel, Wheel Around) |
| `variant` | A named family member | Run: `run`, `crossRun` |
| `size` | Dancers in a circle or star | `2`, `4`, `8` |
| `around` | How many dancers to go around | `1`, `2` (Separate) |
| `into` | Where a Separate ends | `line`, `middle` |
| `fourLadies` | All four ladies chain | yes/no |
| `fullAround` | The "full around" version | yes/no (Shoot the Star) |
| `onHand` | The hand on which a nested call starts | `2`–`5` (Square Thru) |
| `fromStaticSquare` | The call starts from a static square (§5.3) | yes/no |
| `from` | The stated start, where it changes the program (§5.2) | `wave`, `facingCouples`, `line` |
| `call` | One nested call (§5.6) | a figure |
| `beats` | Beats, as in contra (§5.3) | `0`–`64` |

### 6.2 Selectors

- Everyone: `everyone`.
- Identity in the square: `heads`, `sides`, `headPosition`, `sidePosition`,
  `couple1` to `couple4`, `role1s` (boys), `role2s` (girls),
  `headRole1s`, `headRole2s`, `sideRole1s`, `sideRole2s`.
- Relationships: `partners`, `corners`, `opposites`, `rightHandRole2`,
  `leftHandRole2` (CALLERLAB's "right-hand lady", rendered by dialect).
- Position in the formation: `centers`, `ends`, `centerFour`,
  `outsideFour`, `centerSix`, `outsideSix`, `veryCenters`, `veryEnds`,
  `leaders`, `trailers`. Advanced adds `beaus` and `belles`.
- `unspecified`.

### 6.3 Formation names

The vocabulary for §5.4 follows CALLERLAB's formation names: squared set
(static square), circle of eight, facing couples, facing dancers,
back-to-back couples, tandem couples, right- and left-hand ocean waves,
mini-waves and tidal waves, two-faced lines (right and left hand), facing
lines, eight chain thru, trade by, columns, 1/4 tag and 3/4 tag, diamonds,
thar and wrong-way thar, alamo ring, promenade, and right and left grand
circle. Advanced adds the hourglass. The full list is fixed in the first
implementation PR.

## 7. The call registry

Timing below is reprinted with permission of CALLERLAB, from the timing
tables in §4.1, as numbers only. "SS" means from a static square. IDs are
shown without the `sq_` prefix (§5.1) to keep the tables readable. Each
entry's ID, parameters and defaults are proposals. Entries marked ⚠ have a
point for the reviewer.

### 7.1 Mainstream (2026 edition)

| ID | Parameters | Default beats (timing) | Notes |
| --- | --- | --- | --- |
| `arm_turn` | `who`, `hand`, `fraction` | ½: 4, ¾: 4–6, full: 6–8 | |
| `allemande` | `who`, `hand`, `fraction` | ½: 4–6, ¾: 6–8, full: 8 | "Allemande Left" and "Left Allemande" are aliases with `hand=left`. ⚠ Separate from `arm_turn` because callers treat it as a named call with a corner default (Q8). |
| `bend_the_line` | `who` | line of 4: 4, line of 8: 6 | |
| `box_the_gnat` | `who` | 4 | |
| `california_twirl` | `who` | 4 | |
| `cast_off_three_quarters` | `who` | 6 | |
| `centers_in` | none | 2 | |
| `circle` | `who`, `direction`, `fraction`, `size` | 8 dancers: full 16, ¾ 12, ½ 8, ¼ 4; 4 dancers: 8 / 6 / 4 / 2; 2 dancers: 7 / 5 / 4 / 2 | `size=2` is CALLERLAB's "single circle". |
| `circulate` | `who`, `variant` (`couples`, `named`, `all8`, `singleFile`, `box`, `split`) | 4 | 2 when the circulate is a pass thru. |
| `courtesy_turn` | `who` | 4 | |
| `dive_thru` | `who` | diving couple: 2, arching couple: 6 | ⚠ Default 6, the time until both couples finish. |
| `dosado` | `who` | SS across the set: 8; otherwise 6 | |
| `double_pass_thru` | `who` | 4 | |
| `extend` | `who` | 2 | |
| `ferris_wheel` | `who` | 6 | |
| `first_couple_go` | `direction` | 6 | "First couple go left, next go right"; `direction` is the first couple's. |
| `flutterwheel` | `who`, `reverse` | facing couples: 8, SS heads or sides: 10, SS all: 12 | |
| `fold` | `who`, `variant` (`fold`, `crossFold`) | 2 / 4 | |
| `forward_and_back` | `who` | lines close together: 4, otherwise 8 | A CALLERLAB descriptive term with a timing entry. |
| `grand_square` | none | 32 | |
| `half_sashay` | `who`, `variant` (`halfSashay`, `rollaway`, `ladiesInMenSashay`) | 4 | |
| `hinge` | `who`, `variant` (`single`, `couples`), `hand` | single: 2, couples: 3 | |
| `ladies_chain` | `who`, `fraction` (`half`, `threeQuarters`), `fourLadies` | two ladies from facing couples: 6, SS: 8; four ladies from SS: 8, ¾: 10 | "Across" is stored as `half`. |
| `chain_down_the_line` | none | 8 | |
| `lead` | `who`, `direction` | 4 | Lead Right / Lead Left. |
| `alamo_style` | none | 4 | Ocean Wave family. |
| `balance` | `who` | 4 | Ocean Wave family. |
| `step_to_a_wave` | `who`, `hand` | 2 | |
| `dosado_to_a_wave` | `who` | 6 | |
| `single_circle_to_a_wave` | `who` | 4 | |
| `pass_the_ocean` | `who` | 4 | |
| `pass_thru` | `who` | facing dancers: 2, SS heads or sides: 4 | |
| `promenade` | `who`, `fraction`, `variant` (`couples`, `singleFile`, `star`, `wrongWay`) | couples or wrong way, SS: full 16, ¾ 12, ½ 8, ¼ 4; single file, 4 inside: 8; star: full 12, ¾ 9, ½ 6, ¼ 3, full with back out at home 16 | ⚠ "Promenade home" in a singing call is usually more than ¼; the default follows the stored fraction. |
| `recycle` | `who`, `from` | 4 | From a wave. From facing couples it is A-2, 6 beats (§5.2). |
| `right_and_left_grand` | `variant` (`grand`, `weaveTheRing`, `wrongWayGrand`) | 10 | |
| `right_and_left_thru` | `who` | facing couples or ocean wave: 6, SS heads or sides: 8 | |
| `run` | `who`, `variant` (`run`, `crossRun`), `direction` | 4 / 6 | |
| `scoot_back` | `who` | 6 | |
| `separate` | `who`, `around`, `into` | the table times "Pass Thru, Separate": around 1 to a line 8, around 2 10; into the middle 8 / 12 | ⚠ The default should probably subtract the Pass Thru's 2, since the Pass Thru is its own line. |
| `slide_thru` | `who` | 4 | |
| `spin_the_top` | `who`, `hand` | 8 | |
| `split_two` | `who` | 2 | Timing is "2 plus the next call"; the next call is its own line (§5.6). |
| `square_thru` | `who`, `hand`, `count`, `onHand`, `call` | 1: 2, 2: 5, 3: 7–8, 4: 10; SS odd counts add 2 | `count` defaults to 4. `onHand` and `call` are for "on the third hand (anything)" (§5.6). |
| `star` | `who`, `hand`, `fraction`, `size` | 4 dancers: full 8, ¾ 6, ½ 4, ¼ 2; 8 dancers: 16 / 12 / 8 / 4 | |
| `star_thru` | `who` | 4 | |
| `sweep_a_quarter` | `who` | two couples: 2, four couples: 4 | |
| `swing` | `who` | 4, no upper limit | "Variable, at least 4". |
| `swing_thru` | `who`, `hand` | 6 | |
| `tag_the_line` | `who`, `fraction`, `direction` | full 6, ¾ 5, ½ 4, ¼ 3 | |
| `touch_a_quarter` | `who`, `hand` | 2 | |
| `trade` | `who`, `variant` (`couples`, `named`, `partner`, `handTrade`) | couples: 6 from a two-faced line, 8 from a one-faced line; named, in a mini-wave: 3, in a couple: 4; partner: 4 | `handTrade` is CALLERLAB's Right/Left Hand Trade, with `hand`. |
| `trade_by` | none | 4 | |
| `turn_back` | `who`, `variant` (`uTurnBack`, `backtrack`) | 2 | |
| `veer` | `who`, `direction` | 2 | |
| `wheel_and_deal` | `who` | 4 | |
| `wheel_around` | `who`, `reverse` | 4 | |
| `zoom` | `who` | 4 | |

### 7.2 Plus (2026 edition)

Listed in CALLERLAB's suggested teaching order, with the four Quarter Thru
entries (14a to 14d) in one row. Timing is the Plus table's.

| ID | Parameters | Default beats | Notes |
| --- | --- | --- | --- |
| `acey_deucey` | none | 4 | |
| `cloverleaf` | `who` | 8 active dancers: 8, 4 active: 6 | |
| `ping_pong_circulate` | none | 6 | |
| `turn_thru` | `who`, `hand` | 4 | |
| `pass_to_the_center` | none | new centers: 2, new ends: 6 | ⚠ Default 6. |
| `spin_chain_thru` | `who`, `hand` | ends: 3, centers: 16 | ⚠ Default 16. |
| `scoot_and_dodge` | none | 8 | |
| `pair_off` | `who` | 2, SS 4 | |
| `teacup_chain` | `who` | 32 | |
| `dixie_style_to_a_wave` | `who` | facing couples or tandems: 6, SS all: 8 | |
| `walk_around_the_corner` | none | 8 | |
| `see_saw` | `who` | 8 | |
| `load_the_boat` | none | 12 | |
| `quarter_thru` | `who`, `hand`, `variant` (`quarter`, `threeQuarter`, `grandQuarter`, `grandThreeQuarter`) | 6 / 8 / 6 / 8 | |
| `walk_and_dodge` | `who` | 4 | |
| `spin_chain_the_gears` | `hand` | 24 | |
| `grand_swing_thru` | `hand` | 6 | |
| `triple_scoot` | none | 6 | |
| `track_two` | none | 8 | |
| `and_roll` | `call` | 2 after the call | §5.6. |
| `diamond_circulate` | none | 3 | |
| `pass_the_sea` | `who` | 6 | |
| `flip_the_diamond` | none | 3 | |
| `follow_your_neighbor` | `who` | 6 | "And Spread" is `and_spread` around it. |
| `cut_the_diamond` | none | 6 | |
| `thar` | `variant` (`allemandeThar`, `allemandeLeftToThar`, `wrongWayThar`) | ½ arm turn to thar: 2; SS allemande left, forward two to thar: 12 | |
| `slip_the_clutch` | none | 2 | |
| `triple_trade` | none | 4 | |
| `shoot_the_star` | `fullAround` | 4, full around: 6 | |
| `peel_off` | `who` | 4 | |
| `coordinate` | `from` | 8 | Advanced lifts a Plus restriction on the start (§5.2). |
| `and_spread` | `call` | 2 after the call | §5.6. |
| `fan_the_top` | `who` | 4 | |
| `relay_the_deucey` | `hand` | 20 | |
| `partner_tag` | `who` | 3 | |
| `dixie_grand` | none | 6 | |
| `explode_the_wave` | none | 6 | |
| `crossfire` | none | 6 | |
| `explode_and` | `call`, `from` | 2 plus the call | §5.6. From waves only at Plus; from lines it is A-1 (§5.2). |
| `partner_hinge` | `who`, `hand` | 2 | |
| `spin_chain_and_exchange_the_gears` | `hand` | 26 | |
| `linear_cycle` | `from` | 8–10 | From waves only at Plus; Advanced lifts the restriction (§5.2). |
| `peel_the_top` | none | 6 | |
| `circle_to_a_line` | `who` | 8 | |
| `chase_right` | `who` | 6 | |
| `clover_and` | `call` | the greater of 4 and the call | §5.6. |
| `trade_the_wave` | none | 6 | |
| `eight_chain_thru` | `count` | eight hands: 20, four: 10; each odd part 2, each even part 3 | `count` 1–8. |
| `all_eight_spin_the_top` | none | 10 | |
| `do_paso` | none | 12 | |

### 7.3 Advanced (A-1 and A-2), stretch

The August 2026 Advanced definitions have 33 top-level table-of-contents
entries for A-1 and 26 for A-2, several of them families. The Advanced timing
table times nearly every call; concepts such as Any Hand and As Couples are
marked "not timed". Beyond Mainstream and Plus, Advanced needs:

- **Concepts that wrap a call:** "As Couples", "Any Hand", "All 4 Couples"
  and "All 8", using the `call` parameter of §5.6.
- **More call-taking calls:** "(anything) and Cross", "Cross Clover and
  (anything)", and "Transfer and (anything)", whose timing overlaps the
  nested call (§5.6).
- **Programs that depend on the start** (§5.2): Recycle from facing
  couples, and Explode and (anything), Coordinate and Linear Cycle from
  starts that Plus does not allow, are Mainstream and Plus calls that become
  Advanced. Their `from` values for Advanced are added then.
- **A name clash:** A-2's "Swing" (in Slip / Slide / Swing / Slither, 3
  beats) is a different call from the Mainstream Swing. It becomes a
  `variant` of a `slip_slide_swing_slither` family, never `swing`.
- **New selectors and formations:** beaus and belles (§6.2), and the
  hourglass.

The registry rows for A-1 and A-2 are written in the Advanced PR (§9), not
here.

### 7.4 Challenge (C-1 and above), deferred

The C-1, C-2 and C-3A definitions give **no timing**, and much of each list is
concepts and meta-calls that change other calls: Tandem, Siamese, Phantom,
Concentric, Stretch, Magic, "(main call) But (anything)", "Substitute", and
fractions of calls. Representing these faithfully needs a concept grammar
(concepts that stack, replace parts of a call, or apply to imaginary
dancers), and stacking would exceed the two-level depth of §5.6. That is a
design of its own. §9 proposes a cheap first step and a later ADR.

## 8. Dance structure, entry, glossary and import

### 8.1 What a square dance record is

A square dance in the app is one of three kinds, held in a new
`squareKind` field (only meaningful when `form == square`):

| Kind | What it holds | Phrasing |
| --- | --- | --- |
| `singingCall` | The 64-beat figure that is danced four times | Phrased: `phraseStructure` is `1*32*2`, one 64-beat phrase |
| `break` | An opener, middle break or closer | Phrased: `1*32*2` by default |
| `patter` | A patter sequence or module (get-in, get-out, zero, equivalent) | Free form by default |

A new square dance gets the `phraseStructure` shown, not the empty default,
which means the contra structure of four 16-beat phrases. With one 64-beat
phrase the editor warns when the calls do not total 64 beats. Today every
line of a one-phrase dance would be labelled "A1"; phase 1 hides section
labels for square dances, since "A1" means nothing to a square caller.

**The free-form toggle** (maintainer requirement, §1.1). Every square dance
has a `freeForm` flag that the editor shows as a toggle. It defaults on for
`patter` and off for the other kinds, and the caller can change it. When it
is on:

- the editor does not derive section labels or check phrase lengths,
- the dance shows only a total beat count,
- `phraseStructure` is kept but ignored.

**Singing-call details.**

- The **heads/sides order** of the four figures (`HHSS`, `HSHS`, or other)
  is a new optional field. Caller's Companion's `SubType` (for example
  "Keeper, H S H S") already carries it.
- **Keeper or mixer** uses the existing `mixer` flag, which the importer
  already sets from the same `SubType`.
- The **record or tune** uses the existing `tunes` field.
- A singing call and its usual break can be linked with the existing
  `DanceLink` (Q6).

`progression` is unused for squares, and contra-only formation choices do
not appear in the square editor.

### 8.2 Entering calls

The figure editor offers the square registry when the dance's form is
`square`. Each line is one call, with its parameters and beats as in contra.
Lines that the registry cannot express are `custom`, with free text and
beats. Callers' text shorthand ("ST4", "RLT", "PT") gets a square shorthand
table, kept separate from contra's.

### 8.3 Glossary dance-form selector

The glossary screen gains a **dance-form selector** (maintainer requirement,
§1.1). It lists every `DanceForm` that has a shipped taxonomy, in
`DanceForm` order. Today that is Contra and Square; ECD appears once its
taxonomy ships. The selector is a segmented control while there are up to
three forms, and a dropdown beyond that. It is never a two-way switch.

- The selected form is remembered as a new per-device setting, classified in
  the privacy registry in the same PR.
- The square glossary groups calls by program under the chosen edition, and
  shows each call's own-words definition, parameters, default timing and
  usual formations.
- Figures of your own already carry a `form` (§3). The glossary shows only
  those for the selected form, and a new one takes the selected form.

### 8.4 Import and existing square dances

- **Caller's Compendium archives and shares** carry the new fields, with the
  same additive rules the figure codec already follows.
- **Caller's Companion** is the only current source that marks dances as
  square. From phase 3, its square dances are parsed with a square line
  parser. Lines it cannot read stay `custom` with their text, as today.
- **Dances already imported as square** hold contra moves or custom text
  (§3). Most of their structured lines kept no source text, so the existing
  "re-parse custom figures" flow cannot help: it only touches import-gap
  custom lines. The plan:
  - **Phase 1** leaves them alone. Their unprefixed IDs resolve through the
    contra taxonomy (§5.1), so they display exactly as they do today.
  - **Phase 3** adds a migration that the caller runs per dance or for all
    of them. It maps contra moves whose meaning is clear (`swing`,
    `circle`, `promenade`, `star`, `allemande`, `courtesy_turn`, ...) to the
    square calls, re-reads custom lines with the square parser, and leaves
    anything else as it is. The caller can also re-import from the original
    file, through the existing re-import flow.
- Other square sources (for example the output of Sd, or plain-text
  sequences) are Q7.

## 9. Delivery phases

1. **Framework and Mainstream.** Taxonomy resolution from the dance (§5.1),
   the square taxonomy with the §7.1 registry and own-words definitions,
   multi-parameter beats, edition data, `squareKind`, `freeForm`,
   `FormationShape.square`, the glossary selector, and tests.
2. **Plus.** The §7.2 registry, and the `call` parameter (§5.6) with all the
   surfaces it touches.
3. **Entry and import.** Square editor behavior, shorthand, the Caller's
   Companion square parser, and the migration of earlier square imports.
4. **Advanced (stretch).** Judgment: **moderate, not trivial.** Phase 2
   provides the main mechanism, but Advanced adds parameter-dependent
   programs, overlapping timing, the Swing name clash and new formations
   (§7.3), plus own-words definitions for about 60 entries. Recommendation:
   decide after phase 2, when the cost of the call-taking construct is
   known.
5. **Challenge (deferred).** Judgment: **not cheap.** A cheap first step is
   possible: list C-1 to C-3A calls in the glossary by name and program, and
   let the editor record them with `unspecified` beats and free-text
   arguments. A structured concept grammar needs a separate ADR.

## 10. Open questions

**Q1. CALLERLAB notice in the app.** Should `THIRD_PARTY_NOTICES.md` carry
"Reprinted with permission of CALLERLAB" for the shipped timing data? It
costs one line. *Recommendation: yes.*

**Q2. Edition default.** Default to the 2026 edition, or ask the caller
once? Should the setting sync between devices or stay per device?
*Recommendation: default to 2026; sync it, since it is a preference about
the caller's vocabulary.*

**Q3. Required program display.** Where should a dance's derived required
program (§5.2) appear: on the dance card, in search filters, or both?

**Q4. Formation checkpoints.** Should a call line be able to record a
formation the caller states ("from a zero box", "normal lines"), as an
optional, never-computed parameter? Useful for modules, but not needed for
phase 1. *Recommendation: defer.*

**Q5. ID prefix.** §5.1 proposes `sq_`. Is that acceptable, and should
ADR-006 adopt `ecd_` to match?

**Q6. Breaks.** Should a singing call's break be a separate `break` record
linked by `DanceLink`, as proposed, or stored inside the singing-call record?

**Q7. Import sources.** Besides Caller's Companion, which sources of square
choreography do you use and want imported?

**Q8. Allemande.** Keep `allemande` separate from `arm_turn` (§7.1), or make
Allemande Left an alias of a left arm turn with the corner?

**Q9. Square Thru from a static square.** Is Heads Square Thru 4 timed 10
(only odd counts add 2, as §5.3 reads the table) or 12? *Recommendation: 10, pending
confirmation from a caller.*

## 11. Consequences and revisit triggers

**Becomes easier:** callers can store, search and print singing calls and
patter with the same structure contra has, and the glossary becomes a
reference for squares. Adding ECD later is a taxonomy plus data, with no
change to the glossary selector.

**Becomes harder, or costs:**

- **Taxonomy resolution.** About 60 files name `contraTaxonomy` (§3). Each
  one that can see a non-contra dance must resolve the taxonomy from the
  dance. Phase 1 adds a test that fails if an `sq_` figure is ever validated
  or rendered with the contra taxonomy.
- **The `call` parameter** (§5.6) is new structure that the codec,
  sanitizer, validation, renderer, search indexing, editor and sync must all
  handle, with the same depth and size limits as containers.
- **Dialect per form.** Role terms (boys/girls versus larks/robins) need to
  differ by dance form. The dialect system has one set today.
- **Schema and privacy.** `squareKind`, `freeForm` and the heads/sides order
  are new persisted fields, and the glossary form and CALLERLAB edition are
  new settings. Each needs a privacy-registry classification in the PR that
  adds it.
- **Glossary text.** Own-words definitions for about 100 Mainstream and Plus
  calls are real writing work, and need review by someone who calls squares.
- **Two editions.** Program membership must be kept for both editions until
  callers stop using the legacy names.
- **ADR-006.** If the prefix in §5.1 is accepted, ADR-006 should be revised
  to match before ECD is built.

**Explicitly out of scope:** simulating dancer positions, checking that a
sequence resolves, animations, and any code, data or text from Taminations.

**Revisit when:**

- CALLERLAB publishes another program change (add an edition, §5.2).
- Callers ask for resolution checking or formation tracking (§5.4, Q4).
- Work on Challenge starts (§9 phase 5).
- The ECD taxonomy ships, to confirm the glossary selector needed no change.

---

## Appendix A: worked examples

These encodings illustrate the storage rules. They were written for this ADR
and have not been checked as choreography (that the sequence flows or
resolves). Please correct them freely.

### A.1 A singing-call figure

```text
Heads square thru four; dosado; swing thru; boys run; ferris wheel;
centers square thru three; swing the corner; promenade.
```

```text
squareKind=singingCall  freeForm=false  order=HHSS  phraseStructure=1*32*2

sq_square_thru    who=heads  hand=right  count=4  fromStaticSquare=yes  beats=10
sq_dosado         who=everyone  beats=6
sq_swing_thru     who=everyone  hand=right  beats=6
sq_run            who=role1s  variant=run  beats=4
sq_ferris_wheel   who=everyone  beats=6
sq_square_thru    who=centers  hand=right  count=3  beats=8
sq_swing          who=corners  beats=8
sq_promenade      who=everyone  fraction=full  variant=couples  beats=16
```

- The first Square Thru is from a static square, but under §5.3's reading
  an even count adds nothing, so it stays 10 (Q9).
- Square Thru 3 is timed "7 or 8". Its default is 7; the caller set 8.
- The swing is set to 8, above its minimum of 4. The figure totals 64 beats.
  With the swing left at 4 the editor would warn that it is 4 beats short.

### A.2 A patter get-out

```text
From a zero box: swing thru, boys run, bend the line, slide thru,
left allemande.
```

```text
squareKind=patter  freeForm=true  (fromStaticSquare=no on every line)

sq_swing_thru     who=everyone  hand=right  beats=6
sq_run            who=role1s  variant=run  beats=4
sq_bend_the_line  who=everyone  beats=4
sq_slide_thru     who=everyone  beats=4
sq_allemande      who=corners  hand=left  fraction=unspecified  beats=8
```

Free form is on, so the dance shows a total of 26 beats and no section
labels. "From a zero box" stays in the dance's notes unless Q4 adds
formation checkpoints.

### A.3 A Plus call that takes a call

```text
Clover and Pass Thru
```

```text
sq_clover_and  call=( sq_pass_thru who=centers beats=2 )  beats=4
```

The default is the greater of 4 and the nested call's beats, so 4.

## Appendix B: sources

CALLERLAB documents, held in the project's shared files:

- Mainstream Dance Program Definitions, revised 29 March 2026.
- Mainstream Timing, revised 5 July 2026, effective 1 September 2026.
- Standard Mainstream Applications, revised May 2020.
- Standard Basic Applications, revised August 2022.
- Definition Guide for Basic/Mainstream, 7 February 2011.
- Plus Definitions, revised 25 August 2026, and the earlier edition revised
  20 August 2025.
- Plus Timing, revised 5 July 2026, effective 1 September 2026.
- (New) Plus Program Suggested Teaching Order, effective 1 September 2026.
- Plus Standard Applications, revised 22 February 2021.
- Plus Supplement Guide.
- Advanced Definitions, 27 August 2026; Advanced Timing (A-1 and A-2),
  revised 12 June 2025; Advanced Dancing booklet.
- Basic Challenge (C-1) Definitions, 14 March 2026; C-2 Definitions, 15
  August 2026; C-3A Definitions, 1 September 2024.

Reference named by the maintainer, under §4.2's rules: Taminations,
<https://github.com/bradchristie/taminations-flutter>. It was not consulted
for this draft, and nothing in it is taken from Taminations.
