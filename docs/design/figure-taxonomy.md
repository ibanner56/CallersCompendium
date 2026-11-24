# Design: Figure taxonomy v1 (contra)

*Roadmap item 1.8 · v0.1 (2026-07-10). Seeded from ContraDB's libfigure
(AGPL-3.0, attribution retained) with terminology modernized to current
community usage (aligned with The Caller's Box, e.g. "shoulder round" not
"gypsy"/"gyre"). Canonical IDs are permanent; display names go through dialect.*

<!-- section-index -->
> **Section index.** This document is ~95 KB — read the section you
> need rather than the whole file. Line counts indicate size, not position;
> follow the anchor. Keep this index current when you add or retitle a
> section.

- [Structure](#structure) — 27 lines
- [Parameter types](#parameter-types) — 26 lines
- [Move list v1 (~47)](#move-list-v1-47) — 29 lines
- [Implementation status (v0.1 engine, roadmap 2.4)](#implementation-status-v01-engine-roadmap-24) — 657 lines
- [Validation & rendering](#validation--rendering) — 69 lines
- [Taxonomy version history](#taxonomy-version-history) — 647 lines
- [Open questions (to resolve during implementation, with user input)](#open-questions-to-resolve-during-implementation-with-user-input) — 9 lines
<!-- /section-index -->

## Structure

Each **move** definition contains everything about that move (no parallel
metadata tables — ContraDB pitfall #5):

```yaml
id: allemande              # permanent snake_case identifier
displayName: "allemande"   # default English; overridable by dialect
params:                    # NAMED, each with type + default
  who:   {type: dancerPair, default: neighbors}
  hand:  {type: handedness, default: right}
  turn:  {type: rotation, default: 1.0}       # in full turns; 0.25 steps
  beats: {type: beats, default: 8}
renderTemplate: "{who} allemande {hand} {turn}"   # canonical text rendering
searchKeywords: [allemande, almond]
```

- **Taxonomy is versioned data** (`taxonomyVersion`), shipped with the app,
  loaded per dance-form. Adding moves/params is additive; renames are
  migrations. Stored figures carry `schemaVersion` so old data always parses.
- **Each form's taxonomy is chosen by `TaxonomyRegistry`**
  (`shippedTaxonomies`). Contra's owns every move ID with no prefix; another
  form's IDs all carry its prefix (`ecd_`, ADR-006 §5.1; `sq_`, ADR-007
  §5.1), so a stored ID names
  the taxonomy that defines it. `forForm(form)` is what a dance of that form
  is edited and checked with (the form's own taxonomy over contra's, or
  contra's alone while the form has none); `anyForm` reads a stored figure of
  any form, for code with no single dance in hand (programs, the repository,
  sync, search). It resolves IDs; it is not a vocabulary to parse a dance's
  text with, so the repository re-parses a dance's import-gap lines with
  `forForm(dance.form)`. The Glossary lists each form's built-in figures
  from `forForm(form)`; the user's own figures and terms, shorthand and
  Settings defaults surfaces, including decoding a stored compound's figures,
  still use contra's taxonomy directly, until they gain a form of their own.
- **English Country Dance has its own taxonomy** (`ecdTaxonomy`,
  `ecd_taxonomy.dart`): the 52 movements of ADR-006 §7, each stored under an
  `ecd_` ID, and two aliases (`ecd_swat_the_flea`, and `ecd_hand_cast`,
  which is listed as a move of its own). Its `who` is a
  [`dancerList`](#parameter-types), and every value a source can leave out
  defaults to `unspecified` (ADR-006 §5.3); the editor's suggestions
  (`everyone`, a set to the right, a right turn single, forward) are
  `entryDefault`s; a forward and back's double is its stored default, the
  one exception ADR-006 makes to storing what the source says. Its
  templates use ADR-006 §6.3's notation, which `ecd_display.dart` expands:
  `[...]` is dropped when a value inside it is empty, `{?flag}` keeps its
  group only while the flag is set, and a stated `destination` is worded as a
  phrase ("back to place", "to second place"). Contra templates use none of
  it. An ECD sequence may carry one span for steps with no timing of their
  own (`sequenceSpanIssue`, ADR-006 §5.5), as a square's may (ADR-007 Q10;
  `formHasSequenceSpan`). The containers and `custom`
  stay shared and unprefixed.
- **Traditional squares have their own taxonomy** (`squareTaxonomy`,
  `square_taxonomy.dart`): ADR-007 §7.1's traditional core, stored under
  `sq_` IDs whose stems follow their contra namesakes. Its `who` is a single
  `dancerSet` token from ADR-007 §6.2's selectors (`squareSelectors`), and
  every `who`, `whom`, hand and amount a source can leave out defaults to
  `unspecified`; the editor's starting values are `entryDefault`s (everyone,
  a swing's partner, an allemande's corner). Its templates are contra-style.
  A selector that names a role (`headRole1s`, `rightHandRole2`) shows the
  dialect's role term (`squareRoleSelectorWords`). `squareCallPrograms`
  records which calls CALLERLAB also lists, for a glossary label (ADR-007
  §5.2) that nothing shows yet.
- **Aliases** are entries that resolve to a canonical move with pinned params
  (seesaw → dosido{shoulder: left}; swat the flea → box the gnat{hand:
  left}; long lines → forward and back{formation: longLines}). A structured
  search matches the id a figure is stored under, so a search for the move
  does not find its alias's figures. An alias with an `inversePairId` routes
  a figure between itself and its target as the pinned param changes
  (`Taxonomy.resolvedMoveId`).
- **`custom`** is a first-class move: `{text, beats}`; its text is
  dialect-processed and FTS-indexed. `contra corners` and `turn alone` embed an
  optional custom sub-text the same way.
- **A use of a figure of your own** (#1023) is a `custom` figure with three
  more params: `userFigure` (the glossary entry's id), `userFigureArgs` (every
  argument by parameter key, scalars only) and `userFigureCheck` (the first
  eight hex digits of the SHA-256 of `text` as the repository stores it,
  after `normalizeShareableText`). `validateFigure` accepts exactly
  these three on `custom`, checked together by shape; any other extra key is
  still `unknown_param`. `text` holds the line last rendered from the
  definition, which every build shows, so the reference is soft (sync-spec
  §6.15). When `text` no longer matches the check, something that does not
  know the reference edited the line, and the use reads as plain text. The
  renderer renders an attached use live from the definition
  (`FigureRenderer.userFigures`) on every path, canonical included, and falls
  back to `text` when the figure is unknown, no longer decodes, or an argument
  is outside its values. #417's re-parse and figure shorthands never take a
  use (`hasUserFigureReferenceKeys`).

### Namesakes across dance forms

A figure several dance forms name alike (contra `box_the_gnat`, ECD
`ecd_box_the_gnat`) is defined once per taxonomy, and a change to one may need
the same change to the other. Namesakes may legitimately differ, so nothing
enforces it: a PR that changes a figure definition gets an advisory that lists
the same-named figures in the other taxonomies, matched on display name and on
the id after the form's prefix (`tools/ci/report_figure_namesakes.py`). It reads
the forms from `danceFormMovePrefixes` and never fails the build; it is a prompt
to look, not a claim of drift.

## Parameter types

| Type | Values | Notes |
|---|---|---|
| dancerSet | everyone, larks*, robins*, ones, twos, threes, fours, partners, neighbors, sameRoles, shadows, secondShadows, prevNeighbors, nextNeighbors, thirdNeighbors, fourthNeighbors, firstCorners, secondCorners, thirdCorners, opposites, prevPartners, nextPartners, … | *canonical role IDs are `role1`/`role2` — see below. Positional/relational tokens (all except `role1s`/`role2s`) are also **dialect-substitutable** via the dialect `dancers` map. The five mixer partner-series tokens (`prevPartners`/`nextPartners`/`thirdPartners`/`fourthPartners`/`fifthPartners`) are offered in the **figure editor dropdown only when the dance is marked a mixer** — unless the figure already stores one of them, in which case it remains visible and selectable on that figure (see `offerableDancerSets`). The tokens are unrestricted everywhere else (dialect editor, search, etc.). |
| dancerPair | subset of dancerSet valid for the move | |
| handedness / shoulder | right, left | |
| spinDirection | clockwise, counterclockwise | |
| rotation | 0.25 … 2.5 in quarter steps | replaces ContraDB degrees (90–900) |
| places | 1 … 10 int | ring/star travel; replaces ContraDB degrees; renders "N places". `circle.places` and `star.places` may also be `unspecified`, which renders nothing (v39) |
| number | 0 … 99 int | a plain count; renders the digits alone, no unit word. Figures of your own, and `starburst.travel` (v39), the one built-in slot of this kind |
| fraction | 1/4, 1/2, 3/4, full, other | figure 8, poussette; `other` states its amount in the move's `amount` param (v39) |
| beats | 0–64 int | 0 allowed for formation labels |
| direction | along, across, rightDiagonal, leftDiagonal, in, out, up, down | |
| enum(...) | move-specific lists (grips, enders, prefixes…) | e.g. downTheHallEnder |
| text | free string | dialect-aware |
| flag | bool | e.g. withBalance |
| dancerList | a list of dancerSet tokens | ECD's `who` (ADR-006 §5.2): at least one token, none repeated, in the order entered; `everyone` and `unspecified` only on their own. Renders as an English list ("twos and threes") |

### Roles
Canonical role IDs are **`role1` / `role2`** (position semantics: role1 =
left-of-partner facing down… defined precisely in implementation docs). All
display names — Larks/Robins, Leads/Follows, or any custom (incl. gendered)
role terms entered by the user — are dialect, including the default. This is the
lesson from both ContraDB (hardcoded ladles/gentlespoons) and Caller's Companion
(couldn't retrofit gender-free Elements). Default dialect ships as Larks/Robins;
gendered presets are deliberately not baked in.

## Move list v1 (~47)

Adopted from ContraDB, with renames noted:

allemande · arch & dive · balance · balance the ring ·
box circulate · box the gnat (alias: swat the flea) · butterfly whirl ·
California twirl · cast (v40, not in ContraDB) · chain (role-parameterized, not "ladies chain") · circle ·
circular hey (alias: square hey; v36, not in ContraDB) · contra corners · cross trails · **custom** · dosido (alias: seesaw) ·
dolphin hey · down the hall · up the hall · facing star · figure 8 ·
form long wave / ocean wave / long waves · forward and back (alias: long
lines; v39, formations beyond ContraDB) · gate (alias: hand cast, v40) ·
give & take ·
**shoulder round** (was gyre/gypsy; keyword-searchable under old names) ·
hey · hey for three (v39, not in ContraDB) · mad robin · orbit · pass by · pass through · petronella ·
poussette · promenade · pull by (dancers/direction) · revolving door ·
right left through · roll away · Rory O'More · shift (v40, not in ContraDB) ·
slice · slide along set ·
square through · stand still · star · starburst (v39, not in ContraDB) ·
star promenade · swing (alias: meltdown swing) · trade the wave (v39, not in
ContraDB) · turn alone · zig zag

Parameter-level details (per-move param sets, defaults, valid beats) follow
ContraDB's definitions as surveyed in research/contradb.md and are finalized
in the implementation with exhaustive tests; deviations get logged in this doc.

**Beyond ContraDB.** A few moves exist because a *source* states choreography
ContraDB does not model. `courtesy_turn` (v23) is the clearest case: ContraDB
has no such figure at all (0 hits for "courtesy" repo-wide — it treats the
courtesy turn as an unparameterized sub-component of `chain` and `right left
through`), while The Caller's Box writes one as its own figure line 115 times in
the 24,107-dance corpus. `cast` (v40) is another: ContraDB defines no cast,
and The Caller's Box writes one on about 2,000 lines. Such a move is added only
with a corpus census behind each of its params; see the version history below. A move added at a user's
request instead (`circular_hey`, v36; `trade_the_wave`, `starburst` and
`hey_for_three`, v39; `shift`, v40) is defined by that request, which its version-history
entry records, and an importer reads it only where a census supports doing so.

## Implementation status (v0.1 engine, roadmap 2.4)

The figure engine (`packages/compendium_core/lib/src/{taxonomy,dialect,serialization}`)
is implemented and fully tested: `figures_json` codec, `MoveDef`/`Taxonomy`
with alias resolution + per-figure validation, the two-flavor renderer
(canonical + dialect, `%S` side injection, quarter-turn rotation words), and
the single `canonicalize()` chokepoint with round-trip property tests over all
shipped presets.

The **seed taxonomy** (`contra_taxonomy.dart`) began as a conservative slice
(~15 moves + the swing/do-si-do/box-the-gnat aliases + custom) chosen to
exercise every `ParamKind`. Full data entry for the remaining ContraDB moves is
tracked as roadmap 2.4a and is purely additive, landing in feature-grouped
slices. The complete extracted ContraDB reference (49 `defineFigure`s, all
choosers, defaults, `goodBeats`, aliases) is archived in the session files as
`contradb-taxonomy-extract.md`.

**2.4a progress:**
- **PR1 (simple moves, no new vocab):** added `butterfly_whirl`, `arch_and_dive`,
  `california_twirl`, `stand_still`, `slide_along_set`, `mad_robin`,
  `revolving_door`, `star_promenade` (whose `hand` was later removed — see v26;
  and originally the fused `allemande_orbit`, since retired — see v19). All fit
  the existing
  `ParamKind` set (no new vocabulary). ContraDB params with "no default" (which
  force a chooser selection there) take sensible community defaults here, since
  `ParamSpec.defaultValue` is required; rotations are stored in full turns.
  `stand_still` omits `goodBeats`, so any in-range beat count (0–64) is accepted
  without a warning; ContraDB's "beats ≥ 1" min-rule isn't expressible in the
  list-based `goodBeats` model and is not enforced.
- **PR2 (dancer-interaction, no new vocab):** added `gate`, `give_and_take`,
  `pull_by_dancers`, `pull_by_direction`, `cross_trails`, and extended
  `roll_away` with ContraDB's `whom` param. `who`/`whom` pairings are modeled as
  `dancerSet` (defaults required by `ParamSpec`); `give_and_take.who` is narrowed
  to `role1s`/`role2s`. `gate.face` (up/down/in/out) is a dedicated `choice`
  rather than spatial `direction` — it is the gate's **ending facing** (ContraDB
  `figure.js:841` renders it after the literal words "to face"), a point this
  entry originally got wrong and v22 corrects. Beat-shaping flags that ContraDB
  uses only to recompute beats (`give`, `balance`) are not render tokens.
- **PR3 (choice-enum + `centers`/single-dancer vocab):** added `down_the_hall`,
  `up_the_hall`, `zig_zag`, `slice`, `contra_corners`, `turn_alone`, `figure_8`,
  `poussette`, `rory_o_more`. Move-specific enums are `ParamKind.choice` with
  lowerCamelCase values (hall enders, zig-zag enders, march facing, slice
  `slice`/`by`/`return`, figure-8 dir, all/center/outsides); `half_or_full` maps
  onto `fraction` (`half`/`full`); left/right spins are `choice['left','right']`.
  (`slice`'s params are `slice` = left/right, `by` = couple/dancer, and `return`
  = straight/diagonal/none.) Added `centers` and the single-dancer tokens
  `onesRole1`/`onesRole2`/`twosRole1`/`twosRole2` to `ParamVocab.dancerSets`
  (1s/2s × role — ContraDB's chooser_dancer; used by `figure_8.lead`). Secondary
  modifiers — enders (incl. the halls'), figure-8 `dir`, embedded custom text
  (`contra_corners`/`turn_alone`), the who-coupled `moving`, and the single
  `lead` — are structured params but not render-template tokens (cf.
  swing.prefix), so canonical text carries only the identifying phrase and stays
  free of literal sentinel words like "none".
- **PR4 (places family + `ParamKind.places`):** added `circle`, `star`,
  `facing_star`, `square_through`, plus the one new engine type
  `ParamKind.places` (int 1–10, stored as places directly — not ContraDB's
  degrees — and rendered "N places"/"1 place"). Per-move place restrictions
  (square through's 2–4) and ContraDB's param-dependent places/beats ratios are
  typical-only, not enforced (`goodBeats` omitted where a rule isn't
  list-expressible, cf. poussette). `box_circulate` is intentionally excluded:
  it carries no places param. `star.grip` (`none`/`wristGrip`/`handsAcross`) is
  a **render token on all paths** (issue #749 v27): the display renders (`render` /
  `renderVerbose` / `renderSummary`) emit a " - wrist grip - " / " - hands
  across - " clause mirroring ContraDB `starWords`; `none` emits nothing.
  `renderCanonical` also emits the grip clause (added in taxonomy v27), so
  "wrist grip" and "hands across" are FTS-searchable.
- **PR5 (hey/wave family, no new vocab) — completes the 2.4a set:** added
  `pass_by`, `hey`, `dolphin_hey`, `form_long_waves`, `form_a_long_wave`,
  `form_an_ocean_wave` (split at v13, removed at v14; the short-wave half was
  renamed `form_short_waves` at v21). `hey` uses the approved structured model:
  `pass1`/`pass2` (pass2 defaults to a hey-scoped `unspecified` sentinel),
  `shoulder`, `length` (`full`/`half` as shipped in PR5; expanded to the full
  set of ContraDB named durations in v6 — see below), `dir`, four ricochet
  flags (`rico1`–`rico4`), and `beats`.
  `dolphin_hey.whom` uses the single-dancer tokens. Wave formations carry their
  in/out/balance/pass-through flags and ocean-wave hands as structured params;
  ContraDB's editor-only auto-beat recomputation is out of scope (explicit beats
  are stored). Canonical templates keep the identifying phrase (e.g.
  `role2s hey right`, `form an ocean wave`) with the descriptive modifiers held
  structured for the verbose renderer + structural search.
- **v6 (hey length expansion):** expanded `hey.length` from `full`/`half` to the
  full set of ContraDB named durations (`full`, `half`, `lessThanHalf`,
  `betweenHalfAndFull`). The dynamic `dancer%%N` meeting *target* was deferred at
  this point (later added as `meetTarget` in v17 — see below). `length` is
  structured-only (not in the render template), so this is a
  validation/storage change only; canonical text is unaffected.
- **v13 (ocean-wave split, issue #290):** split the overloaded
  `form_an_ocean_wave` — which conflated the default short-wave case with
  "pass the ocean" — into `form_a_short_wave` (renders "form a wave", parallels
  `form_a_long_wave`; **renamed `form_short_waves` at v21**) and
  `pass_the_ocean` (renders "pass the ocean"). Both
  inherit the legacy move's sourced params **minus `passThru`** (intrinsic to
  `pass_the_ocean`, absent from the short wave) and mirror its unencoded,
  param-dependent beats — no fabricated beat count. `form_an_ocean_wave` is
  **retained unchanged** (no alias, no data rewrite) so stored figures render
  byte-identically; hiding it from the authoring picker is an app-layer
  follow-up. Import adds conservative `pass_the_ocean` / short-wave
  recognizers; the ContraDB adapter's "form an ocean wave" mapping is unchanged.
  Purely additive: distinct from `schemaVersion` — no DB migration or derived
  rebuild.
- **v14 (revolving-door text parity, issue #347):** corrected `revolving_door`'s
  defaults toward the canonical figure + ContraDB #2443 / `libfigure`: `hand`
  `left` → **`right`** (it takes right hands), `who` `ones` → **`role2s`** (the
  ladles who take hands, ContraDB `subject_pair`), `whom` `neighbors` →
  **`partners`** (dropped off, ContraDB `object_pairs`). The canonical/search
  render keeps its terse `{who} {move} {hand} {whom}` template; a display-only
  **outcome clarifier** — "— drop off on the other side" — is added in
  `renderer.dart` `_summarySuffix` (same fixed, dialect-independent mechanism as
  the halls/hey/zig-zag/long-lines), mirroring ContraDB's `revolvingDoorWords`
  without repeating params. `hand` remains a real param (an explicit `left` is
  honored); atypical beats (e.g. TCB's 6 vs `goodBeats` [8]) stay a preserved
  warning. **Not byte-identical for existing data:** because these are default
  values, any previously-stored `revolving_door` figure that omitted `who`,
  `hand`, or `whom` now **renders** with the corrected canonical values
  (`role2s`/`right`/`partners`) instead of the old `ones`/`left`/`neighbors` —
  a render/display change, not a stored-data change (no DB migration, and any
  figure that persisted explicit params is unaffected).
- **v17 (hey `meetTarget`, issue #576):** added a `meetTarget` param
  (`ParamKind.dancerSet`, default `unspecified`) to `hey`, finally encoding
  ContraDB's deferred `dancer%%N` meeting *target* — WHICH pair you run a partial
  hey until you meet. The value domain is ContraDB `chooser_pairz`
  (extended at v24 with five mixer partner-series tokens, issue #732, and at
  v38 with `thirdCorners` and `opposites`, #1975)
  (`_heyMeetTargetChoices`: `role1s`/`role2s`/`ones`/`twos`/`partners`/
  `neighbors`/`sameRoles`/`shadows`/`secondShadows`/`prevNeighbors`/
  `nextNeighbors`/`thirdNeighbors`/`fourthNeighbors`/`firstCorners`/
  `secondCorners`/`thirdCorners`/`opposites`/`prevPartners`/`nextPartners`/
  `thirdPartners`/`fourthPartners`/`fifthPartners` + `unspecified`) — **pairs only** (single
  dancers, `everyone`, and `centers` are excluded, as ContraDB does). Our
  `length` already carries the meeting *count*
  (`lessThanHalf`=first meeting/%%1, `betweenHalfAndFull`=second/%%2), so
  `meetTarget` supplies only the WHO. The display renderer names the target only
  for the two partial lengths — "until {target} meet[ the second time]" (bare
  "meet", mirroring ContraDB `stringParamHeyLength`); `unspecified` keeps the
  generic "until someone meets[…]" clause, and half/full ignore it entirely.
  Allow-listed: an unknown/tolerantly-decoded token falls back to "someone"
  rather than injecting text. The editor surfaces the field ONLY when
  `length ∈ {lessThanHalf, betweenHalfAndFull}` (and clears a stale value when
  length returns to half/full). Purely additive: default `unspecified` renders
  and serializes exactly as before (canonical `renderTemplate` unchanged, no
  `paramBeats`, beats stay driven by `length`) — distinct from `schemaVersion`,
  the param rides the existing `figures_json` codec, so no DB migration.
- **v18 (single-file promenade/circle + take-only give_and_take, issue #634,
  deferred from #585):** three ContraDB free-text constructs left unhandled by
  the #585/#599 recognizer sweep, now modeled by reusing existing moves rather
  than introducing new ones:
  - **`promenade.singleFile`** (`ParamKind.flag`, default `false`) — ContraDB's
    "single file promenade …" travels the whole set nose-to-tail rather than
    couple-by-couple. The recognizer defaults `who` to `everyone` when no
    subject precedes "single file" (mirroring the existing `turn_alone`
    precedent) and treats everything after "promenade" as a verbatim note,
    since single-file promenades in the wild describe an arbitrary path
    ("along major set to new neighbors") rather than a fixed direction/distance.
  - **`circle.singleFile`** (`ParamKind.flag`, default `false`) — ContraDB's
    "promenade single file around the circle/ring [N places]" phrasing is a
    single-file circulation, i.e. the `circle` move with the dancers processing
    single file rather than in a joined-hands ring. The recognizer is anchored
    on the fixed phrase and short-circuits before the generic `promenade`
    recognizer runs (list order), so it can never be mis-attributed to
    `promenade`. `turn` defaults to `left` (no direction is stated in the
    source text); an optional trailing "N places" clause is still honored.
  - **Take-only `give_and_take`** (`give: false`) — ContraDB also renders this
    move as a bare "`<who> take <whom>`" with no "give &" clause at all. The
    recognizer requires `whom` to resolve to a known dancerSet subject (unlike
    the give-first branch, which is looser) so an unrelated "`<who> take
    <noun>`" sentence safely falls through to custom rather than being
    force-matched. `goodBeats` was widened from `[4, 8]` to `[2, 4, 8]` since
    real dances render the take-only form in as few as 2 beats.
  - No new `ParamKind` or move id was introduced; there is intentionally no
    `circle_left` move — "left" is the `circle.turn` default. Both flags are
    now **render tokens on all paths** (issue #749 v27): the display renders surface
    "single file promenade across" / "single file circle clockwise N places" for the
    `true` case, and `renderCanonical` includes them too (added in taxonomy v27 with
    a migration + derived rebuild). The precedent `star.grip` previously set
    for non-rendering was the bug that #749 fixed; all three params are now
    canonical-text-included.
- **v19 (`orbit` first-class + fused `allemande_orbit` retired, issue #295):**
  splits the fused `allemande_orbit` (which modeled "X allemande while Y
  orbits" as one combined move: `who`/`hand`/`inner`/`outer`/`beats`) into a
  first-class **`orbit`** move plus a `meanwhile[allemande, orbit]` container.
  - **`orbit`** params: `who` (dancerSet), `turn` (reuses the existing
    `ParamKind.spinDirection` — `clockwise`/`counterclockwise`, so no new
    vocab), `amount` (`ParamKind.rotation`, default `0.5`, matching the old
    fused `outer`), and `beats`. Canonical render: `{who} orbit {turn}
    {amount}` (e.g. "ones orbit clockwise ½"). Source-verified against The
    Caller's Box, which writes the orbit side standalone ("Men orbit clockwise
    1/2"); ContraDB has no standalone orbit figure (only the combined form), so
    TCB is the source. A conservative whole-line recognizer requires BOTH the
    direction and the amount to be stated (never fabricated); a bare "orbit"
    degrades to an unrecognized figure.
  - The combined figure is now `meanwhile[allemande, orbit]`: once `orbit` is
    recognized standalone, the TCB `||` fan-out and the ContraDB `while`
    fan-out both produce the container automatically. The ContraDB combined
    `allemandeOrbitWords` line (dance #1717) and the ContraDB structured-import
    shorthand are redirected to build the container directly, capturing the
    source's explicit orbit direction and orbiting pair.
  - The fused **`allemande_orbit` MoveDef is REMOVED** (removal is cleaner than
    a deprecated alias, and the migration is total and deterministic). Stored
    figures are rewritten by the **schema-v18** DB migration into
    `meanwhile[allemande{who, hand, turn=old inner}, orbit{who=invert(who),
    turn=direction derived from hand (left→clockwise, right→counterclockwise),
    amount=old outer}]`, carrying the fused figure's `beats` as the shared
    container total. This is the sanctioned canonical-changing migration (cf.
    the v14/schema-v12 ocean-wave removal): per-row/per-figure parse-never-throw
    — a figure with a wildcard hand or a non-invertible `who` is left
    byte-identical rather than fabricated.
- **v20 (`mad_robin` + `butterfly_whirl` param enrichment, issue #295):** gives
  two EXISTING moves the params The Caller's Box actually states, so its
  normalized wordings stop falling to `custom`. Additive only — no new move id,
  no new `ParamKind`, no DB migration.
  - **`mad_robin`** gains `direction` (a `ParamKind.choice` over
    `clockwise`/`counterclockwise`/`unspecified` — the existing
    `ParamVocab.spins` tokens, so no new vocabulary) and `whom` (a
    `ParamKind.dancerSet` over the pair relationships plus `unspecified`).
    Canonical render: `{who} mad robin {turn} {direction} {whom}`.
  - **`butterfly_whirl`** gains `who` (same pair-or-`unspecified` domain) and
    the same `direction`. Canonical render: `{who} butterfly whirl {direction}`.
    `goodBeats` stays `[4]`.
  - **Source verification.** TCB's glossary defines both figures in these
    terms — *"you travel in an oval around the person at your side… **who you
    go around is listed**… a clockwise mad robin begins with the left-hand
    person going in front"*, and *"two people … **rotate clockwise or
    counterclockwise** about a common center"* — and a 900-dance / 5,147-line
    TCB sample states the direction plus target on **24/24** mad robin lines and
    the pair plus direction on **18/18** butterfly whirl lines. ContraDB models
    neither: `libfigure` defines `butterfly whirl` as `[beats_4]` alone, and mad
    robin's `circling` param is `once_around` — a `chooser_revolutions` **angle
    in degrees**, which our existing `turn` already carries, *not* a direction.
    (ContraDB choreographers write the missing facts into free text instead,
    e.g. "mad robin, ladles in front, counterclockwise around neighbors".)
  - **`whom` is NOT `who`.** ContraDB's mad robin `who` names which pair steps
    IN FRONT (`madRobinWords` renders "`<who>` in front"); TCB's "around `<X>`"
    names the pair you travel AROUND. Folding the latter into `who` would invert
    the meaning of every ContraDB-imported mad robin, so it gets its own slot.
    TCB never states the in-front role. The v20 recognizer therefore left
    `who` at the taxonomy default and flagged it as an **assumed subject**;
    taxonomy v34 now stores the `unspecified` sentinel instead.
  - **Existing data is normalized by taxonomy v34.** New TCB imports explicitly
    store `who: unspecified`, while legacy assumed TCB mad robins are
    backfilled only when `who` was absent. The migration clears the assumed
    marker and rebuilds `dance_figures.canonicalText` / `dance_fts` / dedupe
    text once; explicit `who` values remain unchanged. A figure that states a
    direction is still distinguishable from its mirror image in search and
    dedupe.
  - **Deliberately not modeled:** a `butterfly_whirl` rotation amount. TCB
    states one on 4/18 lines ("… counterclockwise 1 & 1/2"), but no source
    models it, so per prefer-custom those lines stay `custom` rather than have
    the amount silently dropped from a structured figure.
  - Conservative whole-line recognizers require BOTH stated facts; a bare "mad
    robin" / "butterfly whirl" (ContraDB's own phrasing) or any leftover token
    still degrades to a faithful unrecognized figure.
- **No version change (`grand right and left` + `flutterwheel`, issue #295):**
  both are **compound shorthands**, not moves, so the taxonomy is deliberately
  left alone — no `grand_right_and_left` / `flutterwheel` `MoveDef`, no version
  bump, no migration. Each is lowered onto moves that already exist:
  - **`Grand right and left (<pass list>)` → one `pull_by_dancers` per pass.**
    ContraDB carries no such figure at all; it transcribes the identical
    choreography as consecutive pull-bys. The proof is one dance in both
    databases — *334* by Diane Silver, TCB #10042 A2
    `(4) Grand right and left (N3R;N2L)` == ContraDB #3403 A2
    `[2] 3rd neighbors pull by right` + `[2] 2nd neighbors pull by left`.
  - **`flutterwheel` → its own children.** TCB writes every one of its 143
    corpus lines as a compound whose children are `allemande ½` +
    `star promenade ½`; ContraDB models no flutterwheel either. The importer
    now emits those children rather than a custom parent.
  - **What is NOT modeled, and why.** Until taxonomy v38 the pass-list codes
    `C1`–`C3`, TCB's *square* corners ("the non-partner next to you… your
    opposite… the remaining person"), were left unmapped as a different
    relationship from the ECD *first/second corners*. v38 maps them to
    `firstCorners`, `opposites` and `thirdCorners` (#1975: the maintainer ruled
    that a square's corner is a contra first corner). Codes past `C3`, a
    mixer's partners beyond the modelled depth (`P6`+), out-of-range
    neighbors/shadows, phantoms and trail buddies are still left unmapped, and
    such lines stay `custom` rather than being approximated onto a token that
    means something else. See `docs/design/imports.md` for the recognizer rules and
    `docs/research/callersbox.md` for the glossary evidence and corpus counts.
- **v21 (wave-formation balance, issue #295 — subsumes #296):** models The
  Caller's Box's largest custom bucket, the "balance an existing wave" line
  (`Balance wave of four (NR,WL)`, `Balance long wave (NR, women face in)` —
  **4,613 lines** across the 24,107-dance corpus). There is **no
  `balance_the_wave` move and none was added**: a wave that is balanced IS the
  wave-FORMATION move carrying its `balance` flag, so such a line maps onto that
  move as ONE figure keeping its own beats — never an extra 0-beat form figure.
  - **RENAME (a DB migration, not an additive change):** `form_a_short_wave` →
    **`form_short_waves`**, display label **"form short waves"** (was "form a
    wave"). The figure is the whole set's short waves and every TCB wording is
    "wave of four" / "short waves". Because stored figures carry the old id this
    ships `CompendiumDatabase` **schema v19**, which rewrites `move` in every
    `dances.figures_json` blob — including sides nested inside a `meanwhile`
    container — per-row/per-figure parse-never-throw, leaving anything
    unmappable byte-identical (the #358 path). Precedent: the v14/schema-v12
    ocean-wave removal and the v19/schema-v18 `allemande_orbit` rewrite. The
    pre-rename label survives as a `searchKeyword`.
  - **`form_long_waves` gains `whom` + `hand` + `balance`.** TCB states all
    three on the line — `Balance long wave (NR, women face in)` is *neighbours
    by the right, women facing in* — on ~1,500 corpus lines; ContraDB's
    `formLongWavesWords` models only the facing. `whom`/`hand` therefore default
    to the `unspecified` sentinel (cf. `mad_robin.whom`, v20) and `balance` to
    `false`, so an existing figure is unchanged. **`who` keeps its ContraDB
    meaning — the pair that faces IN** — because TCB states exactly the same
    fact; nothing about stored data is reinterpreted. `goodBeats` widens to
    `[0, 4]`: 0 for the bare formation label, 4 for a balance-a-wave line.
  - **Display (this is issue #296).** `form_long_waves` renders
    `form long waves - {whom} by the {hand}, {who} facing in, {other} facing
    out{ - and balance}` (the hold clause appears only when BOTH `whom` and
    `hand` are stated), and `form_short_waves` appends the same ` - and balance`
    suffix. `form_a_long_wave` and `pass_the_ocean` already embedded their
    balance, so the wave moves are deliberately absent from the generic
    "balance &" prefix table — listing them would double it. All of this is
    `!forCanonical`-gated: **`renderTemplate` is unchanged for both moves**.
    Be precise about what that does and does not buy, because the two halves of
    v21 differ:
    - the **new `whom`/`hand`/`balance` params** are byte-stable — at their
      sentinel/`false` defaults a figure's canonical / FTS / dedupe text is
      unchanged from v20;
    - the **rename is not**, and deliberately so. `form_a_short_wave` →
      `form_short_waves` changes both the move **id** (so an unmigrated stored
      figure would stop resolving and fall through to the #358 raw-id fallback —
      this is what forces the schema-v19 migration) and the **`displayName`**
      ("form a wave" → "form short waves"), which `renderTemplate`'s `{move}`
      token expands — so those figures' canonical text moves too.

    The `derivedRebuildRequiredKey` marker is owed for a **broader** reason than
    canonical text, and it is worth stating precisely because it is easy to get
    backwards. `dance_figures` (see `tables.dart`) projects several columns out
    of each stored figure — `move` (the taxonomy id), `beats`, `progression`,
    `paramsJson`, `canonicalText`, and the derived `section` label — beyond the
    `danceId`/`idx` primary key. **A rebuild is owed whenever any of them would
    change.** Do not reduce that to the canonical text, and do not treat the
    list as closed: a migration that rewrote stored `beats` owes one just as
    much, and because `section` is derived from cumulative beats across the
    whole dance, such a change can shift the label of *later* figures too.

    A rename changes `move` by definition, so **a rename always owes both a
    migration and a rebuild** — even one that leaves `displayName` (and
    therefore canonical text) untouched. Without the rebuild,
    `dance_figures.move` keeps an id the taxonomy no longer defines and
    structural search goes silently stale: `DanceRepository.danceIdsWithFigure`
    (`dance_repository.dart`) filters on exactly `danceFigures.move` and
    reads `paramsJson`.

    (#296 also names `form_an_ocean_wave`; that reference is **stale** — the
    MoveDef was split at v13 and removed at v14.)
  - **`form_a_long_wave` is untouched** (it already carries a balance and means
    something different: ONE long wave in the centre formed by a subset), and
    **`form_rings` is explicitly out of scope** — only 38 TCB lines across 26
    wordings, and ContraDB has no ring-formation figure.
  - Import mapping, the annotation decoding, and what deliberately stays custom
    are documented in `docs/design/imports.md`; the corpus measurements are in
    `docs/research/callersbox.md`.
- **v22 (the two `gate` moves MERGED into one):** `gate` (ContraDB) and
  `rotation_gate` (TCB, v15) both rendered the display name "gate" and appeared
  as two identical rows in the move picker. They are now a **single `gate`**
  carrying a direction, a duration and an ending facing. `rotation_gate` is
  removed and stored figures of both are rewritten by **CompendiumDatabase
  schema v20** (v19 is the concurrent wave-move rename; neither step adds a
  column or table, so they chain cleanly and 18/19/20 are structurally
  identical).
  - **Two source misreadings corrected.** v15 kept the moves apart because "the
    two gate vocabularies are disjoint". They aren't, and the evidence is in
    `libfigure` (github.com/contradb/contra @ master):
    - `figure.js:841` renders a gate as
      `words(ssubject, smove, sobject, "to face", sgate_face)`, over
      `{up: "up the set", down: "down the set", in: "into the set",
      out: "out of the set"}` (`param.js:711`). ContraDB's `face` is the
      **ending facing**, not "which way `who` orbits `whom`". The sources are
      complementary, not conflicting: ContraDB states how a gate ends and no
      amount; TCB states the rotation sense and amount and no facing.
      **Where the misreading came from — avoid it in future:**
      `param.js:714` declares the param as
      `defineParam("gate_face", { name: "face", ui: "chooser_gate_direction" })`.
      The `ui:` value is a **widget hint, not the param's meaning**; reading it
      as "direction of travel" is what put that phrase into
      `contra_taxonomy.dart` and then into the v15/v16 history entries. Trust
      `name` + `words()` + the value strings.
    - `figure.js:844`: *"'ones gate twos' means: ones, extend a hand to twos -
      twos walk forward, ones back up, orbiting around the joined hands."*
      ContraDB's `who` **backs up** and `whom` **walks forward** (and neither
      orbits the other — both orbit the joined hands).
  - **Three dancer slots, one meaning each.** `who`/`whom` keep ContraDB's exact
    semantics. TCB's subject ("Neighbor gate…", "Partner gate…") is a THIRD
    axis — the pairing you gate WITH, not which side moves — so it gets its own
    `pair` slot. `chooser.js:114` shows ContraDB's subject domain
    (`chooser_pair`) admits only role-sides and can never hold
    `neighbors`/`partners`, so folding TCB's subject into `who` would silently
    reinterpret every TCB-imported gate. Same reasoning, same shape as
    `mad_robin.whom` at v20.
  - **The ending facing is now stored, not derived.** See the withdrawn
    "Derived (computed-at-render) taxonomy values" section below for the full
    post-mortem: `gateEndFacing` computed from a nominal `in` start orientation,
    so a 1/2 gate after a down-the-hall claimed "to face out of the set" when
    the answer is "up".
  - **Nothing is fabricated.** Every param defaults to the `unspecified`
    sentinel, so each source asserts only what it states and the user fills the
    rest. `turn` is the first `ParamKind.rotation` to opt into the sentinel
    (ContraDB's gate has no amount param at all). `goodBeats` widens to
    `[2, 3, 4, 6, 8]` — the counts attested across the 186 gate lines in the
    24,107-dance TCB corpus (8x122, 4x33, 6x15, 2x13, 3x3). The three 3-beat
    lines were checked rather than assumed (a spurious entry quietly weakens the
    atypical-beat warning for everyone): all three are the same real pattern, a
    6-beat `Modified right and left through` compound split evenly into
    `(3) Pass through across` + `(3) <X> gate counterclockwise 1/2`, which our
    own importer emits as children — so excluding `3` would warn on real data.
  - **TCB's "(ones forward)" annotations are no longer dropped.** 82 of those
    186 lines carry one, and until v22 a structured gate silently discarded it.
    A front-end pre-recognizer now reads them, and splits them by whether the
    stated verb actually matches a slot's meaning — prefer-custom at *param*
    granularity:
    - `"<dancers> forward"` where the dancers resolve to a set we model (60
      lines) → **`whom`**, which means exactly "the side that walks forward".
      Source-verified, not inferred.
    - **Stationary** phrasings — `(men stay put)`, `(women are posts)`,
      `(centers are posts)` — fit NEITHER slot: `whom` walks forward and `who`
      backs up, so both move. Structuring them would fabricate. Note-only.
    - `"… forward"` naming a set we do not model (`M1+W2 forward`,
      `ends forward`, `twos and fours forward`) → note-only, never approximated
      onto a token that means something else.
    An annotation consumed into `whom` does not *also* become a note (notes
    render as their own row, so that would visibly duplicate); every unconsumed
    annotation is preserved verbatim, so a multi-annotation line keeps the rest.
  - **Out of scope:** `pull_by_dancers` and `pull_by_direction` also both
    display "pull by". That is the same presentational collision, but they are
    genuinely distinct moves and merging them is not obviously correct.
- **v23 (`courtesy_turn` added):** a Caller's Box figure the taxonomy had no
  home for. Purely additive — new move, no rename, no removal — so
  **it owed no migration of its own** (cf. v20's `mad_robin`/`butterfly_whirl`
  params and v15's `rotation_gate`). Note the invariant is "an additive
  taxonomy change owes no migration", not a fixed value of
  `kCompendiumSchemaVersion`: that number also moves for reasons unrelated to
  the taxonomy — schema v21 dropped unused storage (#781/#782) while the
  taxonomy stood still. `courtesy_turn_test.dart` pins the current value, and
  says how to tell the two failure modes apart. The params
  ride the existing `figures_json` figure codec, and no stored figure can
  reference a move that did not exist, so every existing figure renders
  unchanged.
  - **ContraDB models this figure NOWHERE.** Verified against
    github.com/contradb/contra @ master: a repository-wide code search for
    "courtesy" returns **zero** hits in any file. `chain` carries exactly four
    params (`subject_role_ladles`, `by_right_hand`, `set_direction_across`,
    `beats_8`) and `right left through` exactly two; neither has a
    courtesy-turn slot, flag or ending facing. ContraDB treats the courtesy turn
    as an unparameterized sub-component of those figures. TCB instead writes it
    as its own figure line **115 times** in the 24,107-dance corpus, which is
    what this move exists to hold.
  - **Four slots, each source-verified** (census over the whole corpus):
    | param | kind | default | evidence |
    |---|---|---|---|
    | `who` | `dancerSet` | `partners` | stated on every line — partner x53, neighbor x39, N2 neighbor x13, shadow/N3 neighbor/twos x1 each |
    | `whom` | `dancerSet` | `unspecified` | **no source states it**; authoring-only |
    | `direction` | `spinDirection` | `clockwise` | 10 lines state one; all 10 say `clockwise` |
    | `endFacing` | `dancerSet` | `unspecified` | `, face N2` x8, `, face N3` x4, `, face N0` x1 |
  - **`endFacing` is a DANCER, not a facing — the easiest thing to get wrong
    here.** The name matches `swing.endFacing` (v16/#543) and `gate.face` (v22);
    the domain does not. Those hold the four set-relative cardinals
    (`in`/`out`/`up`/`down`, i.e. `gateFacings`). This one holds a dancer
    relationship, because that is what TCB states: every in-line ending facing
    is `, face N<n>`, which `tcbPassPeople` maps to
    `prevNeighbors`/`nextNeighbors`/`thirdNeighbors`.
    The corpus **does** also contain cardinal facings (`Ones courtesy turn; face
    down`, `Partner courtesy turn (power turn); face out`), but every one of
    them uses a **semicolon**, and the all-or-nothing `;`-compound rule keeps
    such a line whole-`custom` because its `; face down` clause structures to
    nothing. They therefore never reach the slot. This is worth stating
    explicitly rather than leaving implicit: anyone who later loosens that `;`
    handling would start feeding `down`/`out` into a dancer domain. A cardinal
    ending facing, if ever needed here, needs its **own** param.
  - **`direction` deliberately has NO `unspecified` sentinel** — but only because
    the move has no semantic need for one, *not* because a sentinel would be
    unsafe on a typed kind. It once was: `ParamKind.spinDirection` used to render
    from a *hardcoded* vocabulary that ignored `spec.choices`, and `_dropdown`'s
    reconciliation pushes a substitute value back into the draft via
    `addPostFrameCallback`, so merely *opening* the editor on a sentinel-bearing
    spinDirection would have rewritten "the source stated nothing" into
    "clockwise" — the class of bug #724 fixed at the UI layer. **That gap is
    closed.** All three consumers of the kind + `choices` contract now read
    `spec.choices ?? <fixed vocabulary>`: the figure param editor
    (`figure_param_editors.dart`) and `ParamSpec.validate` (#726), and the
    Advanced-search facet (`figure_param_domain.dart`'s `figureParamChoices`, PR
    #746). A sentinel on a typed kind is offered, stored and validated
    correctly.
    The corollary: declaring a param `ParamKind.choice` **purely** so it can
    admit the sentinel is an **obsolete workaround** — do not copy it into new
    params. #739 unwound the three declarations that used it:
    `form_long_waves.hand` is now a `ParamKind.handedness` and
    `mad_robin.direction` / `butterfly_whirl.direction` are
    `ParamKind.spinDirection`s, each still listing the sentinel in `choices`.
    (`gate.direction` stays a `choice` for an unrelated reason — its domain
    includes `mirror`, which no typed kind can express.) This param keeps the
    honest `ParamKind.spinDirection` and no sentinel because a courtesy turn
    wheels clockwise by construction — so `clockwise` is a real default, not a
    fabricated one.
  - **`goodBeats: [2, 3, 4, 6]`** — the counts attested across the 115 lines the
    recognizer claims (4 x97, 2 x8, 3 x6, 6 x4). `5` and `8` appear only on
    lines that *mention* a courtesy turn but can never structure as one, so they
    are correctly absent. The marginal values were checked rather than assumed
    (per the v22 precedent) and are all genuine: dance 2957 writes
    `(8) Modified ladies chain to partner:` → `(6) Women allemande right 1 & 1/2`
    + `(2) Partner courtesy turn` — the courtesy-turn tail of a decomposed
    chain, the exact shape our own compound fan-out emits.
  - **A chain never emits one.** 30 corpus lines write a chain (or a
    right-and-left-through / promenade, which end the same way) together with
    its courtesy turn. Those stay whole-`custom`: emitting a standalone
    `courtesy_turn` alongside the chain would double-count both the figure and
    its beats, and since neither our `chain` nor ContraDB's has a courtesy-turn
    parameter there is no slot in either model for the qualifier to ride in. The
    recognizer's whole-line contract enforces this by construction — no
    exclusion logic is written.
  - **Rendering is split canonical/display**, exactly as the merged `gate` is.
    A `renderTemplate` cannot express a conditional, so the canonical
    (dedupe/FTS) text is the flat
    `'{who} {move} {whom} {direction} {endFacing}'` and the maintainer's stated
    wording — `{who} courtesy turn {whom, when present} {direction, when not
    clockwise} {"to face" + endFacing, when set}` — lives on the display-only
    path. `direction` stays *in* the canonical text (rather than being
    display-only like `swing.endFacing`) because that omission was a
    byte-stability concession a brand-new move does not need, and without it a
    counterclockwise courtesy turn would dedupe as identical to a clockwise one.
  - Import mapping and what deliberately stays custom are documented in
    `docs/design/imports.md`; the corpus census is in
    `docs/research/callersbox.md`.

- **v24 (mixer partner series, issue #732):** five `pairDancerSets` tokens added
  for a mixer's previous and successive partners beyond P1 (`partners`, already
  the existing token): `prevPartners` (P0), `nextPartners` (P2), `thirdPartners`
  (P3), `fourthPartners` (P4), `fifthPartners` (P5). Named to parallel the
  neighbour series exactly; a reader who knows one series can read the other.
  Depth 5 is set by corpus coverage (95% of partner-series dances, 95% of
  occurrences) and structural motivation (a four-pass grand right and left lands
  on P5). P6+ and every negative P-n have no token, mirroring the existing
  refusal of N-1/N-2. The five tokens are also added to `_heyMeetTargetChoices`
  — a deliberate extension beyond ContraDB's `chooser_pairz` (which has no
  mixer-partner tokens), decided because without them a mixer's partial hey
  cannot name the partner it runs until you meet. The importer still declines
  the Caller's Box codes; wiring up the in-range codes is follow-up work
  under #732. Purely additive: no existing
  figure's derived output changes; the tokens ride the existing `figures_json`
  codec, so no DB migration is implied.

- **v25 (`balance.hand` + inverse-pair aliases, issue #870):** `balance` gains a
  `hand` (default `unspecified`), and two inverse pairs are declared
  (`box_the_gnat` ⇄ `swat_the_flea` on `hand`, `do_si_do` ⇄ `see_saw` on
  `shoulder`) so a figure whose effective param contradicts its alias pin is
  re-routed by the editor while authoring and re-checked at write time.
  Canonical keys change (`hand=unspecified` joins every
  balance key); the derived rebuild rides the one-time
  `inversePairNormalisationDoneKey` pass, NOT the version bump — nothing reads
  `Taxonomy.version` at runtime.

- **v26 (`star_promenade` loses `hand`, issue #843):** the first param REMOVAL
  in this taxonomy — v19 retired a whole move and v21 renamed one, but no
  version had previously deleted a param from a surviving move.

  `who` now means the dancer you PICK UP on the side, per the owner's
  2026-08-06 ruling, which adopts The Caller's Box's reading over ContraDB's.
  The removed `hand` described a *different* pair — the two dancers with hands
  in the centre — while rendering beside the subject, so "Neighbor star
  promenade right ½" asserted a right-hand connection with the neighbour that
  the dance never claimed. The two facts genuinely coexist, which is why they
  could not share one figure's slots: TCB's flutterwheel decomposes to
  `(4) Women allemande right 1/2` + `(4) Neighbor star promenade 1/2 (WR)`,
  where `who` is `neighbors` and `(WR)` names the women.

  The centre is preserved as a NOTE on TCB imports (`role2s by the right in the
  center`), storing canonical role tokens so it renders under the active
  dialect rather than freezing a gendered `W`. ContraDB star promenades import
  as unrecognized figures instead — an accepted structure regression, because ContraDB
  supplies the centre role rather than the pick-up relationship.

  Removing a declared param changes `figureCanonicalKey` for *every*
  `star_promenade` figure, not only those that stored a hand, because
  `effectiveParams` used to fill the default for the rest. A derived rebuild is
  therefore *owed* unconditionally — unlike the v18/v19 precedents, which
  schedule one only when a figure actually changed — and is discharged by the
  one-time `starPromenadeHandRemovalDoneKey` pass. Owed is not the same as
  always-called: that pass skips its own rebuild when an earlier sweep already
  rebuilt during the same `ensureMigrated`. No DB schema bump: nothing structural
  changes, and a stored `hand` is inert the moment the MoveDef stops declaring
  it.

- **v28 (`chain.hand`, issue #976):** `chain` gains a fourth param, `hand`
  (`ParamKind.handedness`, `defaultValue: ParamVocab.unspecified`), matching
  ContraDB's `by_right_hand` (`figure.js:288-293`). The role→side table is
  fixed by ContraDB's `chainChange` (`figure.js:256-263`): `role1s` (gents)
  implies `left`, `role2s` (ladies) implies `right` — one small named
  helper, `chainHandForWho`, shared by every write site so they cannot drift.

  `renderTemplate` is `'{who} {hand} {move} {dir}'` — hand **before** the move
  name, matching ContraDB's `chainWords` order and the live render ("ladles
  left-hand chain"); an earlier `'{who} {move} {hand} {dir}'` draft was wrong
  on both counts. A hand that equals the role-implied side is silenced on
  **both** the display and canonical paths (a deliberate exception to the
  repo's usual "canonical never silences" habit, since the value silenced is
  implied by the role word already in the text); one that contradicts it
  renders hyphenated (`left-hand`/`right-hand`), matching ContraDB's
  `shand + "-hand"`. This cannot go through `_silencedDefaultParams` — that
  map compares against the *spec* default, not a sibling param, and `chain`'s
  one slot there already holds `dir`.

  The hand is populated explicitly at every write site (both parsers, both
  editor `_selectMove` implementations, the editor's `who`-edit reaction, and
  the one-time backfill sweep below) — never left to the sentinel default
  alone — so a chain written by any path stores the same explicit hand a
  role word implies. It is populated ONLY when a role token (`role1s`/
  `role2s`) was actually read from the source; a chain with no named role
  keeps `hand` unset, so the taxonomy default fills it at read time instead
  of fabricating a hand from OUR default rather than the data.

  Every chain stored before this release is byte-identical: the sentinel
  default renders as the empty string on both paths (the existing mechanism
  already used by `mad_robin`/`butterfly_whirl`), so no DB migration is
  strictly needed for rendering. Structured search reads stored params,
  though, and an absent `hand` key never matches a `hand` facet — so a
  one-time `chainHandBackfillDoneKey` sweep (modeled on
  `_normaliseInversePairMoveIdsIfNeeded`) rewrites every stored `chain` figure
  that names `role1s`/`role2s` but stores no `hand` yet, leaving a role-less
  chain alone. Unlike the v25/v26 sweeps, this rebuild is gated on whether the
  pass actually rewrote a row (`rewroteAny`), not unconditional — a chain's
  canonical/FTS text is unaffected by the taxonomy change alone (the silencing
  rule hides the sentinel and the role-implied side identically), so only
  `params_json` goes stale, and only for rows the sweep rewrites.


**The full ContraDB v1 contra move set is now modeled** (all five 2.4a slices
landed). Exactly one new engine type was required across the whole build-out —
`ParamKind.places`; everything else fits the original kinds.

**Confirmed divergences from ContraDB (already applied in the seed):**
- Canonical roles are `role1`/`role2`; ContraDB `gentlespoons`→`role1(s)`,
  `ladles`→`role2(s)`. All role display names (incl. Larks/Robins) are dialect.
- `shoulder_round` replaces gyre/gypsy; legacy names retained as `searchKeywords`.
- Rotation is stored in **full turns** (0.25–2.5, quarter steps), not degrees
  (90–900). 90°→0.25 … 540°→1.5 … 900°→2.5.
- Places (circle/star/facing star/square through) are stored as **1–10 places**
  (`ParamKind.places`), not ContraDB's degrees — the same store-the-caller-unit
  choice as rotation. `box_circulate` carries no places param.

**Param-vocabulary status:**
Full coverage needed exactly **one** new engine type beyond the original set —
`ParamKind.places` (added in PR4). Everything else is modeled with the existing
kinds:
- **`places`** — DONE (PR4): `ParamKind.places`, int 1–10, used by circle, star,
  facing star, square through.
- **move-specific enums** — DONE (PR2/PR3): `ParamKind.choice` with confirmed
  lowerCamelCase spellings (march facing, star grip, slice `slice`/`by`/`return`,
  gate `face`, down-the-hall/zig-zag enders, hey length, all/center/outsides,
  figure-8 dir, left/right spins).
- **`half_or_full`** — DONE (PR3): maps onto `fraction` (`half`/`full`).
  ContraDB writes nothing else (`stringParamHalfOrFullNotN` throws on any
  other value); since v39 a foreign quarter-step amount up to 2½ is kept as
  `other` with `amount` (#2120).
- **`hey`** (pass pairs, shoulder, length, dir, four ricochet flags, beats,
  `meetTarget`) and the **ocean/long-wave family** — DONE (PR5 + v6 + v17):
  modeled with existing kinds (no new `ParamKind`). The full set of ContraDB
  named hey-length durations (`full`, `half`, `lessThanHalf`,
  `betweenHalfAndFull`) is supported (v6), and the dynamic `dancer%%N` meeting
  target is now captured by the `meetTarget` dancerSet param (v17, issue #576).

**`progressionCapable` removed (issue #551, 2026-07-31):** the `MoveDef.
progressionCapable` flag (previously set on `swing`/`allemande`) and its sole
consumer — an automatic info-icon/tooltip nudge in the figure editor's
Progression toggle — were removed. The nudge over-complicated the model; the
manual **Progression** toggle (unaffected) already lets a caller flag any
figure as the progression. This is non-serialized taxonomy metadata, so no
`contraTaxonomyVersion` bump or data migration was needed.

## Validation & rendering

- Each move may define `validBeats(params)` → ok / warning (never hard error).
  Implemented as `MoveDef.goodBeats` → `atypical_beats` warning.
- `renderTemplate` produces **canonical text**; dialect substitution then
  produces display text; both are pure functions in the core package →
  golden-tested. Screen readers get an expanded verbose rendering
  (`FigureRenderer.renderVerbose`, roadmap 5.4): a dialect-aware, spoken-friendly
  string that spells out notation glyphs (e.g. `1½` → "one and a half times")
  and is surfaced via `Semantics` labels on the dance detail card and the
  large-print Perform mode, while the visible text stays terse.
- FTS indexing uses canonical rendered text + searchKeywords (incl. legacy
  terms like "gypsy" so searches by older users still find shoulder round).
- Display may put a move's details in a different order from its canonical
  text where the template reads as search text rather than as a call:
  `pull by right across` (canonical `pull by across right`) and
  `slide left along set` (canonical `slide along set left`; a dialect that
  renames the move keeps its name whole, `sashay left`). A set direction
  reads the same way on every built-in move that shows one: a diagonal as
  `on right diagonal`, a facing direction as `facing in`, and
  `across`/`along` as themselves (`pull by right on left diagonal`, `robins
  chain facing in`); a hey or an ocean wave names it after the figure (`a
  half hey along`, `an ocean wave on right diagonal`). A figure of your own
  keeps the plain direction, since its template supplies the words around
  it. Cross trails says `passing` before each shoulder, so a direction never
  reads as the shoulder's side (`partner on right diagonal passing right
  shoulders`). Rory O'More's balance follows its subject (`larks balance &
  Rory O'More right`). A subject the verb after it agrees with stays plural
  (`neighbors take right hands`), while a subject that only prefixes the
  move reads singular (`neighbor swing`). All of this is display-only
  (`_displayDirection`, `_displayRenderTemplates` and `_displayBaseRenderers`
  in `renderer.dart`), so canonical text and the FTS index are unchanged.

### Derived (computed-at-render) taxonomy values — convention WITHDRAWN (v22)

**Status: this convention currently has NO instances.** Its sole exemplar — a
rotation-gate's ending facing, derived from `(startFacing, direction, turn)` in
`taxonomy/gate_facing.dart` (issue #294, taxonomy v15) — was **withdrawn at
taxonomy v22**, when the two gate moves merged and the ending facing became a
stored `ParamSpec` (`gate.face`). This section is kept as a record of why,
because the failure mode is instructive and will recur for anything that tries
to compute choreography from a figure in isolation.

Almost every taxonomy value is **stored data**: a named `ParamSpec` on a
`MoveDef`, authored by the user or supplied by an importer, and serialized with
the figure. A *derived* value would instead be computed at render time from
other params and never stored — attractive because such a value can't be
free-typed, fabricated, or drift from the geometry.

**Why the gate-facing derivation failed.** `gateEndFacing` was a pure function
of `(startFacing, direction, turn)`, defaulting `startFacing` to a nominal `in`
("dancers gate from an across-the-set facing"). Two problems, one of them fatal:

1. The renderer never passed a `startFacing`, so *every* gate derived from the
   nominal `in`. A 1/2 gate always rendered "to face out of the set" — including
   straight after a down-the-hall, where dancers face down and a half turn ends
   facing **up**.
2. Passing the real start facing would not have fixed it. The derivation's only
   sound rules are **relative** (a full turn leaves the facing unchanged; a half
   turn reverses it). Promoting a relative rule to an absolute cardinal requires
   knowing the orientation the dancers arrive in, which depends on every
   preceding figure — i.e. choreography simulation, not a context-free function
   over one figure's params. The module's own "CAVEAT" conceded a narrow version
   of this for gate *sequences*; the real scope is any preceding
   orientation-changing figure (down the hall, long lines forward and back, a
   Becket start, …).

**The rule that survives.** Before modeling a value as derived, check that it is
a function of the figure's OWN params alone. If it depends on where the dancers
already are, it is not derivable from a figure — it is authored data, and the
honest default is `unspecified` (so an importer can decline to state it and a
user can correct it) rather than a confident wrong answer.

If a genuinely context-free derived value ever appears, the original file
convention stands and is worth reusing: one pure module per derivation, named
`<figure>_<property>.dart`, exporting a defensively-total function that returns
`null` for any ambiguous case; any unratified assumption isolated at the top as
a single named constant; the derived clause appended by the *display* renderer
only, so the canonical byte-stable line stays template-driven; and no shared
`derived_values.dart` grab-bag — apply the rule of three and group separate
files under `taxonomy/derived/` once a second one exists.

Contrast — and now the norm for facings: an *author-set* facing (a swing's
`endFacing`, #543; the merged gate's `face`, v22) is stored data, a plain
`ParamSpec` in the taxonomy. Its display wording is appended by the renderer
only when it is actually set (swing's default `in`/gate's `unspecified` render
as before), so the canonical line stays byte-stable.

## Taxonomy version history

`contraTaxonomyVersion`, declared in
[`contra_taxonomy.dart`](../../packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart),
is a documentary marker: nothing reads it at runtime. It records that the
seeded move/param vocabulary changed, which users notice because dances are
categorised, rendered or matched differently. The log lives here rather than on
the declaration because it is a ledger of decisions already shipped — it does
not constrain the line it would sit on, and it grows on every bump, so every
reader of that file paid for the whole history to reach a one-line constant.

**Every bump appends an entry here, in the same PR.** The version is distinct
from `CompendiumDatabase.schemaVersion`: a taxonomy bump implies no database
migration unless its own entry says so. `tools/ci/check_version_history.py`
fails a PR that moves the constant without adding the matching entry.

**Bump only when the current version has shipped.** While the latest release
tag carries an older `contraTaxonomyVersion` than `main`, the head version is
unreleased: a further taxonomy change joins it and amends its entry here,
rather than adding a version no release will carry. CONTRIBUTING.md
("Versioned formats") gives the check. The gate cannot see an amendment,
because the constant does not move. A one-time rebuild pass that already ran
on a dev database at that version (a `…DoneKey` marker) does not run again.
If the amended change needs that pass to re-run, it needs a marker of its own.

- v2: roadmap 2.4a PR2 (dancer-interaction moves).
- v3: roadmap 2.4a PR3 (choice-enum moves + `centers`/single-dancer vocab).
- v4: roadmap 2.4a PR4 (places family + `ParamKind.places`).
- v5: roadmap 2.4a PR5 (hey/wave family) — completes the 2.4a move set.
- v6: full set of ContraDB named hey-length durations (lessThanHalf /
    betweenHalfAndFull added; dancer%%N meeting encodings remain out of scope).
- v7: swing renders its `prefix` modifier ("balance & swing" / "meltdown
    swing"); `none` still renders to nothing.
- v8: param-value-dependent beat counts — hey `length`, figure_8 `half`,
    rory_o_more `balance`, and slice `return` carry structured `paramBeats`
    (ContraDB-sourced) so untouched beats re-derive on a param change.
    Moves whose ContraDB beats are a range/ratio rather than a discrete
    per-value count (poussette, the places family, turn_alone) are left on
    their flat default — see the notes at those moves. See MoveDef.paramBeats.
- v9: extends `paramBeats` coverage — swing `prefix` (none 8, balance/meltdown
    16), petronella `balance` (8/4), and long_lines `goBack` (8/4), all
    ContraDB-sourced. The `meltdown_swing` alias now derives 16 beats.
    Moves with continuous angle/ratio beat rules (allemande, do_si_do,
    shoulder_round, circle/star family, box_the_gnat) remain deferred.
- v10: cross-line merge support — `box_the_gnat` gains a `balance` flag
    (default false; swat_the_flea inherits it via its box_the_gnat target)
    and the down/up-the-hall `ender` gains a `bendTheLine` value. Both are
    additive: no existing figure's derived output changes, and box_the_gnat
    stays on the continuous-beat-rule deferral (no `paramBeats`). Distinct
    from CompendiumDatabase.schemaVersion — no DB migration is implied.
- v11: adds `box_circulate` (ContraDB-sourced; modeled on `box_the_gnat`) and
    `star_through` (a balance+twirl figure modeled on `california_twirl` +
    a balance flag), plus the `weave the line` → `zig_zag` recognizer alias (the
    alias sets no `slide`; TCB's `(R;L …)`/`(L;R …)` bracket is read into it by
    `_weaveSlideAnnotation`, #1415).
    Both new moves carry a neutral `balance` flag (default false) that the
    CallersBox cross-line merge upgrades to true; like `box_the_gnat` their
    balanced beat count comes only from that merge sum, so neither takes a
    `paramBeats`. `box_circulate` carries no places param (ContraDB lists it
    under moveCaresAboutPlaces for angle display only). Additive: no existing
    figure's derived output changes; distinct from schemaVersion — no DB
    migration is implied.
- v12: `star_through` drops its `balance` flag to mirror `california_twirl`
    (who + beats only) per product decision, and is removed from the
    CallersBox cross-line balance-merge set (box_circulate stays). Removing
    an unused default-false flag changes no existing figure's derived output
    (a bare `star_through` already rendered without balance) and is distinct
    from schemaVersion — no DB migration is implied.
- v13: splits the overloaded `form_an_ocean_wave` (issue #290) into a default
    short-wave `form_a_short_wave` (renders "form a wave"; RENAMED to
    `form_short_waves` at v21) and a distinct
    `pass_the_ocean` (renders "pass the ocean"). Both inherit the legacy
    move's sourced params MINUS `passThru` (intrinsic to pass_the_ocean,
    absent from the short wave) and mirror its unencoded, param-dependent
    beats — no fabricated beat count. `form_an_ocean_wave` was RETAINED at
    v13 for stored-data fidelity; v14 removes it (migrated away — see below).
- v14: removes the now-superseded `form_an_ocean_wave` MoveDef (issue #290
    cleanup). Stored figures that reference it are rewritten by the schema
    migration (CompendiumDatabase schema v12) to `pass_the_ocean` (when
    `passThru` is true — its default) or `form_a_short_wave` (when false;
    itself renamed `form_short_waves` at v21, migrated by schema v19),
    carrying the remaining params. This is a DB migration (distinct from
    this taxonomy version), the sanctioned canonical-changing exception.
- v15: adds the TCB rotation-gate figure kind `rotation_gate` (issue #294,
    Option B). A NEW move — believed at the time to be distinct from the
    ContraDB `gate` on the grounds that the two vocabularies were disjoint —
    carrying `direction` (clockwise/counterclockwise/mirror) + a `turn`
    fraction over a VARIABLE beat count. Its resulting facing was derived
    deterministically at render time (gate_facing.dart), never stored.
    Purely additive taxonomy change: no existing figure's derived output
    changes, and distinct from CompendiumDatabase.schemaVersion — NO
    persisted-data migration is implied (new figures serialize under the
    existing figure codec; stored figures are untouched).
    SUPERSEDED at v22: the "disjoint vocabularies" premise rested on
    misreading ContraDB's `face` as a travel direction when libfigure
    renders it as the ENDING facing. `rotation_gate` is merged back into
    `gate` and removed.
- v16: adds an `endFacing` param to `swing` (issue #543) — the body facing a
    swing ends in, a first-class promotion of what previously lived only in
    a figure note. A `ParamKind.choice` over the four set-relative facing
    tokens (`in`/`out`/`up`/`down`, reused from the ContraDB `gate` `face`
    domain / `gateFacings`), defaulting to `in` (across — where most swings
    end). Named `endFacing` (NOT `face`) to avoid overloading gate's `face`
    (which this entry described as an orbit direction — a misreading
    corrected at v22, where it is confirmed to be the ending facing and the
    two params turn out to mean the same kind of thing). Purely additive: the
    default `in` renders exactly as today (the display renderer appends a
    `facing …` clause ONLY when non-default; swing's canonical
    `renderTemplate` is unchanged, so canonical/FTS/dedupe stay byte-stable),
    it carries no beat cost (absent from `paramBeats`; `goodBeats` unchanged)
    and does not feed the program-matrix swing column. Distinct from
    CompendiumDatabase.schemaVersion — the param rides the existing
    `figures_json` figure codec, so NO persisted-data migration is implied.
- v17: adds a `meetTarget` param to `hey` (issue #576) — names WHICH pair you
    run a partial hey until you meet, finally encoding the `dancer%%N`
    meeting target that had been deferred as out of scope. A
    `ParamKind.dancerSet` over ContraDB's `chooser_pairz` pair vocabulary
    (`_heyMeetTargetChoices`), defaulting to `unspecified`. Derived directly
    from libfigure: ContraDB folds length+target into one `hey_length`
    (`pair%%1`/`pair%%2`); we already split the meeting *count* into `length`
    (`lessThanHalf`=%%1, `betweenHalfAndFull`=%%2), so `meetTarget` supplies
    only the WHO. Purely additive: the default `unspecified` renders exactly
    as today (the display renderer only names the target when non-default;
    `renderTemplate` is unchanged, so canonical/FTS/dedupe stay byte-stable),
    it carries no beat cost (absent from `paramBeats`; `goodBeats` unchanged,
    beats stay driven by `length`). Like `endFacing`, distinct from
    CompendiumDatabase.schemaVersion — the param rides the existing
    `figures_json` figure codec, so NO persisted-data migration is implied.
- v18: adds `singleFile` flags to `promenade` and `circle` (issue #634,
    deferred from #585) for ContraDB's "single file promenade along major
    set" and "promenade single file around the circle N places" free-text
    phrasings — both additive, default-`false` flags. At this version they
    were structural-only (not display-rendered); #749 gap A adds display
    renders. Canonical text stays byte-stable.
    There is no separate `circle_left` move: the single existing `circle`
    move's `turn` param already covers left/right, so the single-file
    circle case reuses it with `turn` defaulted to `left` (the phrasing
    never states a direction). Also extends `give_and_take.goodBeats` to
    include `2` — real "take neighbors" renders (#570, #548) confirmed
    take-only beats at both ends of the already-documented 2-4 range.
    Purely additive: no existing figure's derived output changes, and
    distinct from CompendiumDatabase.schemaVersion — the new flags ride the
    existing `figures_json` figure codec, so NO persisted-data migration is
    implied.
- v19: splits the fused `allemande_orbit` (issue #295) into a first-class
    `orbit` move (`who`, `turn` reusing `ParamKind.spinDirection`, `amount`
    rotation default 0.5, `beats`). The combined "X allemande while Y orbits"
    figure is now modeled as `meanwhile[allemande, orbit]`: the TCB `||`
    fan-out and the ContraDB `while` fan-out both produce the container
    automatically once `orbit` is recognized standalone. The now-superseded
    `allemande_orbit` MoveDef is REMOVED; stored figures that reference it
    are rewritten by the schema migration (CompendiumDatabase schema v18) to
    `meanwhile[allemande{who,hand,turn=old inner}, orbit{who=invert(who),
    turn=direction derived from hand, amount=old outer}]`, carrying the
    shared beat count. This is a DB migration (distinct from this taxonomy
    version), the sanctioned canonical-changing exception (cf. v14).
- v20: gives `mad_robin` a `direction` + `whom`, and `butterfly_whirl` a `who`
    + `direction` (issue #295), so The Caller's Box's normalized wordings
    stop falling to `custom`. Sourced from TCB, which models detail ContraDB
    does not:
    - TCB `Glossary.htm` "Mad robin": "While facing one person, you travel in
      an oval AROUND THE PERSON AT YOUR SIDE… **Who you go around is
      listed**… A clockwise mad robin begins with the left-hand person going
      in front." A 5,147-line TCB sample has 24/24 mad robin lines stating
      BOTH a direction and an "around `<whom>`" target.
    - TCB `Glossary.htm` "Butterfly whirl": "Two people face the same
      direction… and **rotate clockwise or counterclockwise** about a common
      center." The same sample has 18/18 lines stating both a subject and a
      direction.
    ContraDB models neither: `libfigure` defines `butterfly whirl` with
    `beats_4` alone, and mad robin's `circling` param is `once_around` — a
    `chooser_revolutions` ANGLE in degrees (default 360), already carried by
    our existing `mad_robin.turn`, NOT a direction. ContraDB's mad robin
    `who` is a THIRD concept again (`madRobinWords` renders "`<who>` in
    front" — which role steps in front first), so TCB's "around `<X>`" needs
    its own slot: folding it into `who` would invert the meaning of every
    ContraDB-imported mad robin. Precedent for a TCB-sourced param:
    `rotation_gate` (issue #294) and `down_the_hall.ender: bendTheLine` (v10).
    Deliberately NOT added: a `butterfly_whirl` rotation amount. TCB states
    one on 4/18 lines ("1 & 1/2", "2"), but neither ContraDB nor the TCB
    glossary models it, so per prefer-custom those lines stay `custom` and
    `goodBeats` stays `[4]`.
    Every new param defaults to the `unspecified` sentinel (cf. `hey.pass2`
    / `hey.meetTarget`, v17), which the renderer emits as the empty string.
    At v20 this kept canonical/FTS/dedupe text unchanged for existing data.
    Taxonomy v34 later changes the `mad_robin.who` default and normalizes the
    legacy assumed TCB shape; see the v34 ledger entry below.
- v21: wave-formation balance (issue #295, subsuming #296). Three changes:
    - RENAMES `form_a_short_wave` to `form_short_waves` (display label
      "form short waves", not the old "form a wave"). The v13 split named it
      for a single wave, but the figure is the whole set's short waves —
      every TCB wording is "wave of four"/"short waves". A rename is a
      MIGRATION, not an additive change: stored figures carry the old id, so
      CompendiumDatabase schema v19 rewrites them (cf. the v14/v12 ocean-wave
      and v19/v18 `allemande_orbit` precedents). The old label survives as a
      `searchKeyword` so the picker still finds it.
    - gives `form_long_waves` a `whom` + `hand` (which pair you hold and by
      which hand) and a `balance` flag. TCB states all three on the line —
      `Balance long wave (NR, women face in)` — on ~1,350 corpus lines;
      ContraDB's `formLongWavesWords` models only the facing, so `whom`/
      `hand` take the `unspecified` sentinel default (cf. `mad_robin.whom`,
      v20) and `balance` defaults false. `who` KEEPS its ContraDB meaning
      (the role that faces IN) — TCB states the same fact, so no stored
      figure's meaning changes.
    - Byte-stability is NOT uniform across the two changes, and the
      distinction is the whole reason this taxonomy bump needs a schema bump
      alongside it:
      * The new `whom`/`hand`/`balance` params ARE byte-stable. They default
        to the `unspecified` sentinel / `false`, and `renderTemplate` is
        untouched, so a figure that omits them renders exactly as it did at
        v20 — canonical/FTS/dedupe text is unchanged for all existing data.
      * The RENAME is NOT byte-stable, for two independent reasons. (a) The
        move **id** changed, so an unmigrated stored figure would stop
        resolving and fall through to the #358 raw-id fallback — this is what
        forces the CompendiumDatabase schema-v19 migration. (b) The
        **`displayName`** changed ("form a wave" → "form short waves"), and
        `renderTemplate` is `'{move}'`, whose `{move}` token expands the
        DISPLAY NAME (`FigureRenderer._renderMoveName` uses the id only as a
        dialect-substitution lookup key) — so those figures' canonical text
        changes too.
      The `derivedRebuildRequiredKey` marker is owed for a BROADER reason
      than canonical text, and it is worth stating precisely because it is
      easy to get backwards. `dance_figures` (see `tables.dart`) projects
      several columns out of each stored figure — `move` (the taxonomy id),
      `beats`, `progression`, `paramsJson`, `canonicalText` and the derived
      `section` label — beyond the `danceId`/`idx` primary key. A rebuild is
      owed whenever ANY of them would change; do not reduce that to the
      canonical text, and do not treat the list as closed (a migration that
      rewrote stored `beats`, for instance, owes one just as much — and
      because `section` comes from cumulative beats across the whole dance,
      such a change can shift the label of LATER figures too).
      A rename changes `move` by definition, so **a rename always owes both
      a migration and a rebuild**, even one that leaves `displayName` (and
      therefore canonical text) untouched: without the rebuild,
      `dance_figures.move` keeps an id the taxonomy no longer defines, and
      structural search goes silently stale —
      `DanceRepository.danceIdsWithFigure` (`dance_repository.dart`)
      filters on exactly `danceFigures.move` and reads `paramsJson`.
    - The new params and the balance suffix are otherwise surfaced only on
      the `!forCanonical` display path (that display work IS issue #296,
      whose own reference to `form_an_ocean_wave` is stale — that MoveDef was
      removed at v14).
    The taxonomy version bump is distinct from the schema bump: the params
    ride the existing `figures_json` figure codec, and only the RENAME needs
    the persisted-data migration.
- v22: MERGES the two "gate" moves into one (maintainer ruling). `gate` and
    `rotation_gate` both rendered the display name "gate" and showed as two
    identical picker rows; they are now a single `gate` carrying a
    direction, a duration AND an ending facing. `rotation_gate` is REMOVED;
    stored figures of BOTH moves are rewritten by the schema migration
    (CompendiumDatabase schema v20 — v19 is v21's wave-move rename). This is
    a DB migration (distinct from
    this taxonomy version), the sanctioned canonical-changing exception
    (cf. v14, v19).

    CORRECTS TWO SOURCE MISREADINGS that v15/v16 recorded. Verified against
    libfigure at github.com/contradb/contra @ master:
    - `figure.js:841` renders a gate as
      `words(ssubject, smove, sobject, "to face", sgate_face)` and
      `param.js:711` maps its values `{up:"up the set", down:"down the set",
      in:"into the set", out:"out of the set"}`. ContraDB's `face` is
      therefore the ENDING FACING, not "which way `who` orbits `whom`" as
      v15/v16 claimed. The misreading came from `param.js:714`, which
      declares `name: "face"` but `ui: "chooser_gate_direction"` — the `ui:`
      value is a WIDGET HINT, not the param's meaning, and reading it as one
      is what put "direction" in our comment. The two sources were never in
      conflict: ContraDB states how a gate ends and no amount; TCB states
      the rotation sense and amount and no facing. The merge is close to
      their union, and the v15 "disjoint vocabularies" rationale for a
      separate move does not survive the correction.
    - `figure.js:844`: "'ones gate twos' means: ones, extend a hand to twos
      - twos walk forward, ones back up, orbiting around the joined hands".
      ContraDB's `who` BACKS UP and `whom` WALKS FORWARD (neither orbits the
      other; both orbit the joined hands).

    Slots. `who`/`whom` keep ContraDB's exact meaning. TCB's subject
    ("Neighbor gate…", "Partner gate…") is a THIRD axis — the pairing you
    gate WITH, not which side moves — and gets its own `pair` slot;
    `chooser.js:114` shows ContraDB's subject domain (`chooser_pair`) admits
    only role-sides and can never hold `neighbors`/`partners`, so folding
    TCB's subject into `who` would reinterpret every TCB-imported gate.
    Same reasoning, same shape as `mad_robin.whom` at v20. TCB's
    "(ones forward)" parentheticals — 82 of 186 corpus gate lines, until now
    silently dropped on a structured match — now fill `whom` when they say
    "<dancers> forward" AND name a set we model (60 lines), because `whom`
    means precisely "walks forward". A STATIONARY annotation
    ("(men stay put)", "(women are posts)") fits neither slot — `who` backs
    up, so it moves too — and is never structured; it, and any "forward"
    phrase naming a set we do not model, survives verbatim as the note.

    The ending facing is now STORED (`face`), not derived. `gateEndFacing`
    is WITHDRAWN: it computed from a nominal `in` start orientation, so a
    1/2 gate after a down-the-hall claimed "to face out of the set" when the
    answer is "up". A start-relative rule cannot produce an absolute
    cardinal without simulating the preceding choreography. See the
    ["Derived (computed-at-render) taxonomy values"](#derived-computed-at-render-taxonomy-values--convention-withdrawn-v22)
    section above, whose only exemplar this withdraws.

    Every param defaults to the `unspecified` sentinel (cf. v17/v20) so each
    source asserts only what it states; `turn` is the first
    ParamKind.rotation to opt into the sentinel (see ParamSpec.validate),
    because ContraDB's gate has no amount param at all. `goodBeats` widens
    from ContraDB's `[8]` / rotation_gate's `[4,6,8]` to `[2,3,4,6,8]`, the
    counts attested across the 186 corpus gate lines.
- v23: ADDS `courtesy_turn` (`who`, `whom`, `direction`, `endFacing`, `beats`).
    Purely additive — a new move, no rename and no removal — so, distinct
    from CompendiumDatabase.schemaVersion, NO persisted-data migration is
    implied (cf. v20's `mad_robin`/`butterfly_whirl` params and v15's
    `rotation_gate`, both additive with no migration). The params ride the
    existing `figures_json` figure codec, and no stored figure can reference
    a move that did not exist, so every existing figure renders unchanged.

    ENTIRELY TCB-SOURCED — ContraDB models this figure NOWHERE. Verified
    against libfigure at github.com/contradb/contra @ master: a repository-
    wide code search for "courtesy" returns ZERO hits, in any casing and any
    file. Its `chain` carries exactly four params (`subject_role_ladles`,
    `by_right_hand`, `set_direction_across`, `beats_8`) and its
    `right left through` exactly two (`set_direction_across`, `beats_8`);
    neither has a courtesy-turn slot, flag or ending facing. ContraDB treats
    the courtesy turn as an unparameterized sub-component of those figures.
    That is precisely why a TCB line writing one as its OWN figure line —
    which TCB does on 115 lines of the 24,107-dance corpus — had no home
    before this version and fell to `custom`.

    Slots, and the evidence for each (census over the whole corpus):
    - `who` — the pairing the turn is danced with, stated on every line:
      partner x53, neighbor x39, N2 neighbor x13, shadow x1, N3 neighbor x1,
      twos x1. Defaults to `partners` (the mode) for the authoring path; a
      recognizer that has to fall back to it marks the figure
      `assumedSubject` rather than asserting a subject the line never gave.
    - `whom` — **no source states it.** A search for the two-dancer form
      `<X> courtesy turn <Y>` finds nothing in the corpus: `who` always
      names the pairing, never a turner plus a turnee. The slot exists for
      manual authoring only, defaults to the `unspecified` sentinel, and the
      importer NEVER fills it. Per the maintainer's ruling: "you can make
      the end_facing and whom optional, left out by default unless it
      actually shows up in parsing data".
    - `direction` — TCB states one on 10 lines and every one of them is
      `clockwise`; `counterclockwise` is unattested. A courtesy turn IS
      clockwise by construction (the couple wheels as a unit), so those 10
      lines are redundant confirmations rather than a distinction, and
      `clockwise` is a REAL default, not a fabrication. Deliberately carries
      NO `unspecified` sentinel — not for any editor-safety reason (the
      editor and validator halves of that gap closed with #726, the
      Advanced-search facet with PR #746), but simply because the move has
      no semantic need for one; see the param comment.
    - `endFacing` — a **DANCER**, not a facing. Every attested value is a
      neighbor relationship: `, face N2` x8, `, face N3` x4, `, face N0` x1.
      See the param comment: this is the single easiest thing to get wrong
      about this move.
    `goodBeats: [2, 3, 4, 6]` — the counts attested across the 115 corpus
    lines this move's grammar claims (4 x97, 2 x8, 3 x6, 6 x4). `5` and `8`
    appear only on lines that MENTION a courtesy turn but can never
    structure as one (`(5) Neighbor promenade across; courtesy turn 3/4` is
    a `;` compound; the `8`s are `right and left through …
    ("courtesy fling")` lines), so they are correctly absent. The marginal
    values were checked rather than assumed, per the v22 precedent: dance
    2957 writes `(8) Modified ladies chain to partner:` -> `(6) Women
    allemande right 1 & 1/2` + `(2) Partner courtesy turn` — the
    courtesy-turn tail of a decomposed chain, the exact shape our own
    compound fan-out emits — dance 174 `(5) Women allemande right 1` +
    `(3) Neighbor courtesy turn`, and dance 14823 `(10) Star left 1 & 1/4` +
    `(6) Partner courtesy turn`. All genuine timing, none noise.
- v24: ADDS five mixer partner-series tokens to `pairDancerSets`:
    `prevPartners` (Caller's Box P0), `nextPartners` (P2), `thirdPartners`
    (P3), `fourthPartners` (P4), `fifthPartners` (P5) — the previous and
    successive partners in a mixer's direction of progression beyond P1
    (`partners`, already the existing token). Named to parallel the neighbour
    series exactly (`prevNeighbors`/`nextNeighbors`/`thirdNeighbors`/
    `fourthNeighbors`); a reader who knows one series can read the other.

    Depth is 5 (not 4, where the neighbour series stops). Measured over the
    whole 24,107-file Caller's Box mirror — counting bare `Pn` in prose AND
    pass codes `PnR`/`PnL`, which an earlier analysis missed — there are
    1,230 occurrences of P≥2 across 1,061 figure lines in 308 dances. Cutting
    at P5 covers 292 dances (95%) / 1,172 occurrences (95%); the next step
    (P6) adds only two dances and 17 occurrences. P5 is also structurally
    motivated: in an ascending-weave sequence, pass k people and you land on
    P(k+1); the conventional four-pass grand right and left therefore lands on
    P5. (This rule applies only to ascending-weave sequences — balance-wave
    orientation markers and descending sequences do not follow it.) P5 (83
    prose occurrences) accordingly outranks P4 (48). Example: TCB id 10467
    `Grand right and left mixer`: `(10) Grand right and left (P1R;P2L;P3R;P4L)`
    then `(4) P5 partner balance` / `(12) P5 partner swing` / `(16) P5 partner
    promenade counterclockwise`.

    P6+ and every negative `P-n` have no token, mirroring the existing
    refusal of `N-1`/`N-2`. The neighbour series likewise has only
    `prevNeighbors` and nothing beyond it.

    The five tokens are also added to `_heyMeetTargetChoices` (see comment
    there). Purely additive: no existing figure's derived output changes.
    Like v17 and v23, the tokens ride the existing `figures_json` codec —
    distinct from CompendiumDatabase.schemaVersion, NO persisted-data
    migration is implied.
- v25 (#870): `balance` gains a `hand` param (default `unspecified`), and
    inverse-pair aliases (`box_the_gnat` ⇄ `swat_the_flea` on `hand`,
    `do_si_do` ⇄ `see_saw` on `shoulder`) are declared so
    `Taxonomy.resolvedMoveId` can re-route a figure whose effective param
    contradicts the alias pin. **Canonical-key change:** every `balance`
    figure's `figureCanonicalKey` gains `hand=unspecified` — a derived
    rebuild is required. The `unspecified` sentinel is a non-null STRING
    that `figureCanonicalKey` includes (only `null` is skipped), so the
    key genuinely changes. Note the tension: `ParamVocab.unspecified`'s
    doc says the renderer emits it as the empty string, "which is what
    lets such a param sit in a renderTemplate without changing the
    canonical text of any figure that leaves it unset." That is true of
    **canonical text** (the renderer output) and false of
    **`figureCanonicalKey`** (the dedupe/FTS key), which includes every
    declared param regardless of rendering — two different notions of
    "canonical."

    Adding `balance.hand` is purely additive to the persisted codec —
    existing figures with no `hand` key produce the same effective value
    (`unspecified`) from `effectiveParams` — so NO DB schema migration is
    needed. The derived rebuild that re-indexes FTS and canonical keys comes
    from `CompendiumRepositories._normaliseInversePairMoveIdsIfNeeded`,
    which rebuilds if a rebuild has NOT already happened during this
    `ensureMigrated` call, or if its own scan rewrote any `figures_json`,
    and then writes its `settings` marker.

    It does NOT rebuild unconditionally, and the difference is reachable
    rather than theoretical: `alreadyRebuilt: rebuiltThisCall` is threaded
    in from the caller, so when an earlier sweep already rebuilt and this
    pass rewrites nothing, it correctly skips. Measured on a database with
    every one-time marker cleared and `derivedRebuildRequired` set: **1**
    rebuild across the four sweeps that could each have run one.

    (Corrected while writing v26, #843: this paragraph previously said "the
    taxonomy version bump triggers a derived rebuild". It does not, and
    nothing else does either — `Taxonomy.version` is stored on the object
    and never read by any runtime code. Believing otherwise is how a
    canonical-key change ships with a stale FTS index, so the mechanism is
    named explicitly here rather than assumed.)

    The inverse-pair re-routing changes only `figure.move` in the editor and at
    write time (import, editor save); canonical keys are unaffected because
    both halves of a pair already resolve to the same `MoveDef` id.
- v26 (#843): `star_promenade` LOSES its `hand` param, and `{hand}` leaves its
    `renderTemplate`. This is a param REMOVAL — the first in this taxonomy;
    v19's `allemande_orbit` retired a whole move, and v21 renamed one.

    **Why.** `star_promenade.who` meant two different things depending on
    which adapter wrote it. ContraDB's `who`+`hand` name the pair with a
    hand in the CENTER; TCB's prose subject names the dancer you PICK UP on
    the side. Owner ruling (2026-08-06): TCB's reading is what we store, so
    `who` is the pick-up relationship. The `hand` then describes a
    DIFFERENT pair from the subject it renders next to — "Neighbor star
    promenade right ½" implies a right-hand connection with the neighbor
    when the right-hand connection is between the two dancers in the
    center. A param that renders as though it qualifies the subject, while
    actually describing another pair, is misinformation dressed as
    precision, so it is removed rather than re-documented.

    The TCB flutterwheel decomposition shows both facts coexisting in one
    figure, which is why they cannot share a slot:
      `(8) Neighbor flutterwheel`
        -> `(4) Women allemande right 1/2`
         + `(4) Neighbor star promenade 1/2 (WR)`
    `who` is `neighbors` (whom you promenade); `(WR)` names the women (who
    form the star). Different sets. The center survives as a NOTE
    (`<role token> by the <hand> in the center`), written by the TCB
    import's `_starPromenadeAnnotation`; it stores canonical role tokens so
    it renders under the active dialect rather than freezing `W`/`M`.

    **Canonical-key change + one-time pass.** `figureCanonicalKey` is built
    from every DECLARED param (`figure_diff.dart`), so removing `hand`
    changes the key of EVERY `star_promenade` figure — not only those that
    stored one, because `effectiveParams` used to fill the `right` default
    for the rest. A derived rebuild is therefore OWED unconditionally —
    unlike the schema-v18/v19 precedents, which schedule one only when a
    figure actually changed — and it is NOT triggered by this version
    number: nothing reads `Taxonomy.version` at runtime.
    `CompendiumRepositories._stripStarPromenadeHandIfNeeded` does the work,
    mirroring #870 — strip the now-undeclared `hand` from stored
    `figures_json`, rebuild, then write the `settings` marker, in that
    order, so an interrupted pass retries on the next open.

    "Owed unconditionally" is about the DEBT, not the call: the pass still
    skips its own `runDerivedRebuild` when an earlier sweep already
    rebuilt during the same `ensureMigrated`, because that rebuild already
    paid the debt. Conflating the two is exactly how the v25 paragraph
    above came to claim a rebuild that does not happen.

    No DB SCHEMA bump: nothing structural changes, and a leftover `hand` is
    already inert for rendering and keying the moment the param leaves the
    MoveDef (`effectiveParams` iterates `def.params` only). The strip is
    hygiene — it stops dead data silently resurrecting if some later
    taxonomy re-declares `hand` here with a different meaning.

    **ContraDB star promenades now import as CUSTOM figures** — a
    deliberate structure regression, accepted by the owner. ContraDB
    supplies the center role, not the pick-up relationship, and we will not
    guess the relationship.
- v27 (#749): `star.grip`, `promenade.singleFile`, and `circle.singleFile`
    are promoted from display-only render tokens to **canonical render
    tokens** — they now appear in `renderCanonical` → `dance_fts`, making
    them free-text searchable ("hands across", "single file").

    **Gap A (display) was delivered in #805.** This bump closes Gap B.

    **Canonical forms** (owner-ruled, 2026-08-11):
      - `star right - hands across - 4 places` / `star left - wrist grip - 4 places`
      - `single file promenade along` (who DROPPED; dir always present — see below)
      - `single file promenade clockwise 4 places (circle)` — parenthetical
        retained so FTS finds it by "circle"

    **Why `who` is dropped from `promenade.singleFile` canonical.** The
    `who` field carries `everyone`, an importer artefact that conveys no
    choreographic information. Keeping it in canonical would create a false
    distinction in the FTS index between figures that are choreographically
    identical. Dropping it makes the canonical text stable across importers
    that handle the dancer set differently.

    **Why `dir` is always included for `promenade.singleFile` canonical.**
    The ContraDB importer now captures `dir: 'along'` from the source text
    (Part A of this issue). Including `dir` in canonical ensures the FTS
    index reflects the stated direction and makes the figure findable by the
    direction token.

    **Derived rebuild.** The rebuild is owed by the taxonomy change, not by
    rewrite count — a rewrite-count gate would leave FTS stale for
    databases with no grip or singleFile figures today, while any such
    figure added tomorrow would index correctly. So the rebuild is
    unconditional. The mechanism:
    `CompendiumRepositories._emitGripAndSingleFileIntoCanonicalIfNeeded`
    mirrors `_stripStarPromenadeHandIfNeeded` — one-shot settings key
    (`gripSingleFileCanonicalInclusionDoneKey`), rebuild regardless of
    rewrite count, marker written AFTER success. No `figures_json` rewrite
    needed — only the derived index changes.

    **No DB schema bump.** Only derived text (canonical / FTS) changes.

    **Display changes** (also in this bump):
      - `promenade.singleFile=true` display: drops `who`; includes `dir`
        even when it equals the taxonomy default (`across`) — matching the
        canonical form.
      - `circle.singleFile=true` display: rewording from suffix form
        (`circle left 4 places - single file`) to prefix form
        (`single file circle clockwise 4 places`).

    **ContraDB importer change** (also in this bump): `_promenade` now
    captures a plain `along` direction token after `promenade` in the
    single-file branch, setting `params['dir'] = 'along'`. This is
    consistent with the ordinary promenade path and ensures the canonical
    key includes the direction stated in source.

    **TCB recognizer** (also in this bump): `Single file promenade
    clockwise` and `Single file promenade counterclockwise` are now
    recognised as `circle` with `turn: 'left'` / `turn: 'right'` and
    `singleFile: true`.

    **#840 constraint.** The canonical form for `circle.singleFile=true`
    is now frozen as `single file promenade clockwise N places (circle)`.
    Any future rewording of that canonical form requires a **derived
    rebuild** — a new one-shot settings key + sweep (see
    `_emitGripAndSingleFileIntoCanonicalIfNeeded` for the pattern). The
    `contraTaxonomyVersion` bump is a documentary marker; it does NOT
    trigger the rebuild (nothing reads `Taxonomy.version` at runtime —
    see v26 note above).
- v28 (#976): `chain` gains a fourth param, `hand`
    (`ParamKind.handedness`, default `ParamVocab.unspecified`, via
    `_handOrUnspecified`), matching ContraDB's `by_right_hand`
    (`figure.js:281-291`). `renderTemplate` becomes
    `'{who} {hand} {move} {dir}'` — hand BEFORE move, matching ContraDB's
    `chainWords` order (`words(sdiag, swho, thand, smove)`) and the live
    render ("ladles left-hand chain"); an earlier `{who} {move} {hand}
    {dir}` draft was wrong and would have read "ladies chain left across".

    **Role→side table.** [chainHandForWho] (`param_types.dart`) is the
    single source of truth for `role2s`→`right`, `role1s`→`left`, mirroring
    ContraDB's `chainChange` (`figure.js:256-263`). Every site that writes or
    reads a role-implied side consults it, so none can drift: the ContraDB
    and shared-recognizer `_chain` parsers, core's `seedChainHand` (`param_change_rules.dart`) —
    which both `_selectMove` implementations, the meanwhile side editor and
    every `who` edit through `applyParamChange` call — and the one-time
    backfill sweep below. It is NOT baked into `chain.hand`'s
    taxonomy default — see the param's own doc comment for why.

    **Role-word scoping (#976 §6.1.3).** A hand is populated only at a
    site that actually read a role word from the source (or, in the
    editor, from a user-edited `who`). A bare, role-less `chain` — where
    `who` is left unset so the taxonomy default applies at read time
    (`figure_parser.dart`'s domain guard) — gets no hand. Populating one
    there would derive it from our default rather than the source, which
    is the fabrication the surrounding code already refuses elsewhere.

    **Silencing, on BOTH display and canonical.** A `hand` that agrees with
    the role-implied side renders nothing (`renderer.dart`'s
    template-expansion loop, keyed on `chain`/`hand` — NOT
    `_silencedDefaultParams`, whose single slot for `chain` already holds
    `dir` and which compares against the *spec* default rather than a
    sibling param). Applying this to canonical text too is a deliberate,
    narrow exception to the repo's usual "canonical never silences" habit:
    the value being silenced is implied by the role word ALREADY in the
    text, so omitting it removes nothing a search could want, and it is
    what keeps an imported `ladles chain`'s FTS/dedupe text byte-identical
    to the same dance imported before this release. A hand that
    CONTRADICTS the role reading (a deliberate `role2s`+`left` chain)
    still renders, hyphenated: `left-hand`/`right-hand` (matching
    ContraDB's `shand + "-hand"`, `figure.js:275`) — not a bare `left`,
    which would read as a different figure and tokenizes for FTS as one
    word instead of two.

    **Backfill IS owed, but the derived rebuild is gated on rewrite
    count, not unconditional.** Structured search reads only stored
    `params_json` (the `danceFigures` table in `database.dart`), so a chain imported before
    this release and an identical one imported after it must both carry
    an explicit `hand` or search results depend on import date. A
    one-time sweep, modelled on `_normaliseInversePairMoveIdsIfNeeded`,
    backfills `hand` on every stored `chain` whose `who` is
    `role1s`/`role2s` and whose `hand` is absent, using [chainHandForWho]
    — leaving a chain with no stored `who` alone, for the same
    role-word-scoping reason above. It rewrites `figures_json`, then runs
    `runDerivedRebuild` ONLY if a row was actually rewritten (unlike the
    taxonomy-version-owed sweeps above, whose rebuild is unconditional):
    the renderer's canonical/FTS text is byte-identical whether `hand` is
    the sentinel or the role-implied side, so a database with no
    un-backfilled chains has nothing stale to rebuild. It then writes its
    settings marker, in that order so an interrupted pass retries on the
    next open. This is a database-internal migration marker, not
    user-authored preference data — like its sibling sweep-marker keys
    above, it carries no entry in `privacy/settings_registry.dart`; the
    column-level `deviceLocal` classification on `settings.value_json`
    already keeps it from traveling.

    **No DB schema bump.** `hand` rides the existing `figures_json` codec.
- v29 (#921): `promenade.destination` — a new `ParamKind.dancerSet` param
    (default `ParamVocab.unspecified`) that captures the destination of a
    single-file promenade. ContraDB source texts like `single file promenade
    along major set to new neighbors` previously stored the trailing phrase
    verbatim as the figure note; this bump promotes it to a structured param.

    **Domain.** Reuses [ParamVocab.dancerSets] + the `unspecified` sentinel
    (`_dancerOrUnspecified`), per maintainer ruling (2026-08-14): no new
    ParamKind needed.

    **Rendering.** The param is appended as `to {destination}` in both the
    display and canonical renders for `promenade.singleFile=true`, suppressed
    when the value is `unspecified`. The canonical form is:
      `single file promenade {dir} to {next neighbors}` — destination
      humanized via [_humanize] (e.g. `nextNeighbors` → "next neighbors").

    **Import.** The ContraDB `_promenade` recognizer now consumes the
    destination tail — optional "major set", then "to [new/the same]
    {subject}" — and stores it as `destination`. "new neighbors" (ContraDB
    source phrasing) maps to `nextNeighbors`. An unrecognised tail is still
    stored as the note; a fully-consumed tail leaves no note.

    **No derived rebuild.** `destination` defaults to `unspecified`, which
    the renderer silences; existing figures' canonical text is byte-stable.
    Structured search gains the param immediately for newly-imported figures.
    Free-text search likewise gains it (the destination now appears in
    `renderCanonical` / `dance_fts` for newly-imported figures).

    **No DB schema bump.** `destination` rides the existing `figures_json`
    codec.
- v30 (#989): whole-set promenade rendering — three changes to the same
    `promenade`/`circle` corner of the taxonomy, shipped together because the
    third depends on the first two's plumbing. **Supersedes issue #771's
    sentinel ruling for `promenade.turn`** (see below) — #771's implementer
    must not treat that ruling as still binding.

    **1. `circle.singleFile` wording (both paths).** Previously, a
    single-file circle's stored `turn` (`left`/`right`) was substituted to
    `clockwise`/`counterclockwise` in both display and canonical text. Both
    paths now render the raw `turn` value instead, matching every other
    circle. Canonical's parenthetical — which exists purely to keep "circle"
    in the FTS index — widens from `(circle)` to carry the spin word too:
    `(circle, clockwise)` / `(circle, counterclockwise)`, so a search for the
    TCB source's own wording ("clockwise") still matches.

    **2. `promenade.destination` re-gate.** The render gate for the
    `to {destination}` clause widens from `singleFile==true` to
    `dir != 'across'` — a promenade doesn't need to be single-file to have a
    stated destination once `dir` is non-default. **Data-loss note, stated
    plainly and not as a migration:** an existing `singleFile==true,
    dir=='across'` figure that already carries a stored `destination` keeps
    the param in `figures_json` but stops rendering the clause — owner
    ruling (2026-08-18), accepted knowingly.

    **3. `promenade.turn`** — a new `ParamKind.spinDirection` param
    (`clockwise`/`counterclockwise`) capturing the promenade's rotation
    sense, the taxonomy slot issue #771's parser work is blocked on (that
    parser extension is #771's own scope, not this PR's — this PR adds 0 of
    #771's measured declines by itself).

    **⚠️ Owner-decided default is the CONCRETE `'counterclockwise'`**, not the
    `unspecified` sentinel `mad_robin.direction` / `butterfly_whirl.direction`
    use for the same `ParamKind.spinDirection` (v20 #295). #771's own
    "Decision requested" section had asked for the sentinel default so
    existing figures would render byte-identically with no migration; **that
    ruling is SUPERSEDED by this owner decision (2026-08-18)**, made with the
    rebuild cost known and explicitly accepted ("this is beta, our users will
    survive"). `choices` still lists the sentinel
    (`_spinOrUnspecified`) — reachable only via the automatic `dir`-driven
    editor reset (below), never a user-facing Clear control
    (`ParamSpec.allowManualClear: false`, the first param to set it) — so
    `promenade.turn` is the first param in the taxonomy to combine a
    CONCRETE default with sentinel-admitting `choices`; every other
    sentinel-admitting param still defaults TO the sentinel.

    **Rendering silencing (derived, not templated).** On the non-single-file
    display path, the concrete default `turn` is omitted when `dir` is
    `across`, `rightDiagonal`, or `leftDiagonal` and no destination is
    rendered. `along` is the exception: it un-silences the concrete default
    turn. A non-default `turn` or a rendered destination shows both `dir` and
    `turn` together. Rotationless directions (`in`/`out`/`up`/`down`) reset
    `turn` to the `unspecified` sentinel in the editor, so no turn token is
    rendered. The single-file display path takes the same `along` exception
    since the #2331 follow-up (maintainer ruling, 2026-11-23): before, a
    single-file promenade along the set at the default turn displayed as
    `single file promenade along`, with no rotation. Canonical never applies this default-silencing: `turn` is
    omitted from canonical text only at the `unspecified` sentinel, exactly
    like `dir`'s existing canonical behaviour of always rendering even at its
    default.

    **Editor.** `figure_list_editor.dart` hides `turn` whenever `dir` is
    `in`/`out`/`up`/`down`, where a rotation sense is meaningless, and the
    change that sets `dir` there resets `turn` to the `unspecified` sentinel
    via an explicit write, never `.remove()` — removal would fall back to the
    concrete default and render it. The reset is core's `applyParamChange`
    (`param_change_rules.dart`, #709), which the editor calls. It also
    hides `destination` whenever `dir == 'across'` (mirroring the render
    gate), leaving its stored value untouched rather than clearing it.
    `figure_param_editors.dart`'s Clear affordance is gated on the new
    `ParamSpec.allowManualClear` field (default `true`, so every existing
    sentinel-admitting param is unaffected); `promenade.turn` is the only spec
    that sets it `false`.

    **Derived rebuild — REQUIRED**, unlike v29's `destination` addition. All
    three changes above alter canonical/FTS text for figures whose
    `figures_json` never changes: existing single-file circles lose
    "clockwise"/"counterclockwise" from their canonical text (change 1);
    existing `singleFile+across+destination` promenades lose their clause
    (change 2); every stored promenade gains (or, at the pure-default
    combination, does not gain) a `turn` token (change 3). One settings marker
    (`promenadeTurnCircleWordingCanonicalRebuildDoneKey`, mirroring
    `gripSingleFileCanonicalInclusionDoneKey`'s v27 shape) covers all three —
    the debt is attributed to the taxonomy change as a whole, not to `turn`
    alone. No `figures_json` rewrite; the sweep calls `runDerivedRebuild` and
    is guarded so it runs at most once per database, retrying on an
    interrupted pass.

    **No DB schema bump.** `turn` rides the existing `figures_json` codec.

- v31 (#773): adds the two standalone turn figures reported by the CallersBox
    census. `turn_as_couples` mirrors `star_through`/`california_twirl` with
    `who` (default `partners`) and 4 beats. `two_hand_turn` mirrors
    `allemande` with `who` (default `partners`), `turn` (default `1.0`), and
    `beats` (default 8), intentionally omitting `hand` because both hands are
    used together. Both are additive taxonomy moves with no schema migration.
    The existing hall + `turnCouple` fold remains the representation for
    turn-as-couples lines attached to a down/up-the-hall sequence.
- v32 (#1056): changes the canonical display names of the do-si-do pair to
  `dosido` and `seesaw`, matching the compact vocabulary used by CallersBox.
  The permanent move IDs and alias pin are unchanged. Existing `do si do`,
  `do-si-do`, `see saw`, and `see-saw` spellings remain accepted on import and
  are normalized at the full-text query boundary. Because canonical figure
  text and FTS rows use the display names, existing derived rows are rebuilt
  once under `compactDosidoSeesawCanonicalRebuildDoneKey`; stored figure JSON
  and the SQLite schema are unchanged.
- v33 (#1160): corrects the `pass_the_ocean.centerHand` default to `left` and
  the `box_circulate.who` default to `role2s`, and changes the figure-eight
  canonical template to `{who} {half} {move}`. Existing derived canonical and
  FTS rows are rebuilt once under
  `taxonomyV33CanonicalRebuildDoneKey`; stored `figures_json` and the SQLite
  schema remain unchanged. Display-only wording fixes for swings, give-and-
  take, and figure-eight direction/target prose do not alter canonical text.
- v34 (#1193): changes the `mad_robin.who` default to `role2s` and allows the
  `unspecified` sentinel. Callers Box imports now explicitly store
  `who: unspecified` because the source names the pair being circled, not the
  pair stepping in front; the old assumed-subject marker is no longer set.
  Existing assumed mad robins with no explicit `who` are normalized, including
  nested `meanwhile` sides, and canonical/FTS rows are rebuilt once under
  `taxonomyV34CanonicalRebuildDoneKey`. Explicit subjects are preserved.
- v35 (#1104, #1198): aligns parameter names with their semantic roles (`travel`,
  `direction`, `where`, `axis`, `fraction`, `whomHand`, and `endFacing`),
  unifies the `pull_by` taxonomy, makes source-absence sentinels explicit,
  retains `circle` as a hall ender, updates canonical/display rendering, and
  makes canonical rendering of `meanwhile` and `modifier` containers searchable
  and stable using their structural move tokens between ordered children.
  Existing figures require a recursive persisted-data migration and a complete
  derived-index rebuild; legacy keys remain readable through deterministic
  normalization. The container projection is also guarded by the
  `modifierContainerCanonicalRebuildDoneKey` one-shot sweep; stored figure JSON
  and the SQLite schema remain unchanged.
- v36: adds `circular_hey`, the four-dancer hey passing by shoulders (alias
    "square hey"), defined for contra on its own terms using
    [ADR-006](../adr/006-english-country-dance-canonical-grammar.md) §7.4 as a
    starting point; ADR-006 §2 keeps the ECD definition separate. Params: `who`
    (default `neighbors`; the group that passes first, so there is no `whom`,
    mirroring `square_through.who`), `changes` (`ParamKind.places`, any whole
    number 1..10 like `circle.places`, default 4), `shoulder` (default
    `right`), `where` (default `across`) and `beats`. `changes` drives
    `paramBeats`: 1 -> 2, 2 -> 4, 3 -> 8, 4 -> 12 (default), 5 and above -> 16.
    Above six changes 16 is a placeholder the user is expected to override.
    Canonical text names the count ("3 changes"), not "places". The display
    line is "3/4 circular hey, neighbors pass right across", showing `N/4` for
    any count but four. The shared free-text recognizer reads that sentence for
    every count but four (`1/4`..`10/4`, `1/2`, `full`, and "square hey"); the
    full circuit's display omits the extent, so that line stays custom text
    unless written with `full`. The recognizer requires the extent,
    group, shoulder and direction rather than defaulting them. Purely
    additive: no schema migration, no derived-index rebuild (no existing
    figure changes). *Superseded in part by #2121 (not a taxonomy change): a
    line with no extent now reads as the full four changes, so the full
    circuit's display line reads back; the group, shoulder and direction are
    still required, and the direction may also be one of the display's
    diagonal or facing phrases (`on right diagonal`, `facing in`).*
- v37: adds `circular_hey.who2`, the group passed second, by the other
    shoulder — the counterpart of `hey.pass2`. It defaults to the
    `unspecified` sentinel and draws from the same pair vocabulary as
    `pass2`. When stated, the display line gains a second pass ("3/4 circular
    hey, neighbors pass right across, shadows pass left"); unstated, it
    renders exactly as v36 did. Like `pass2`, `who2` is not in the canonical
    template, so no stored canonical text changes. The free-text recognizer
    reads the second pass back and rejects a same-shoulder one. The Caller's
    Box `Square through <n> without hands (<pass list>)` now imports as a
    `circular_hey` with `who2` from the even cells. Purely additive: no schema
    migration, no derived-index rebuild, and already-imported dances keep
    their custom text (no backfill, maintainer decision).
  v37 also changes the `courtesy_turn.direction` default from `clockwise` to
    `counterclockwise`. The ordinary courtesy turn (after a role2s' chain, a
    right and left through or a promenade across) wheels counterclockwise with
    the left-hand dancer backing up (TCB glossary, "Courtesy turn"); clockwise
    is the mirrored turn, chiefly after a role1s' chain (maintainer, on the PR
    that made this change). v23's reading — "clockwise by construction", with
    the 10 corpus lines that state `clockwise` taken as confirmations — was
    wrong: a source names the rotation only when it is the unusual one, so
    those lines are the mirrored case. The display now silences
    `counterclockwise` and states `clockwise`. Source JSON is unchanged — a
    stored courtesy turn without a stated direction now means the ordinary
    turn, and one that states `clockwise` keeps it — but the canonical text of
    every courtesy turn without a stated direction changes, so v37 owes a
    one-time canonical/FTS rebuild, guarded by
    `taxonomyV37CanonicalRebuildDoneKey`.
- v38: changes ten seeded defaults, chosen as the values both ContraDB (all
    2,439 dances its listing API returned) and a random 2,000-dance sample of
    The Caller's Box use most (maintainer, decided on #1969). Stored-figure
    defaults, which change what a figure that omits the param means:
    `circle.places` 4 -> 3, `allemande.travel` 1 -> 1.5, `star.hand` right ->
    left, `poussette.who` `ones` -> `role1s`, `square_through`
    `places`/`beats` 4/16 -> 2/8, `roll_away.who` `neighbors` -> `role1s`,
    `orbit.who` `ones` -> `role1s`, `arch_and_dive.who` `ones` -> `twos`,
    `box_the_gnat.who` `partners` -> `neighbors` (so `swat_the_flea`, its
    alias, follows), and `figure_8.where` `none` -> `above`. `none` stays a
    valid stored `figure_8.where`. `square_through.goodBeats` becomes `[8, 16]`
    so existing four-place, 16-beat figures keep raising no `atypical_beats`
    warning. Source JSON is unchanged: a stored figure that never stated one of
    these now means the new default, and one that stated a value keeps it. The
    canonical text of every figure that leaves one of them unstated changes, so
    v38 owes a one-time canonical/FTS rebuild, guarded by
    `taxonomyV38CanonicalRebuildDoneKey`. No backfill pins the old values into
    stored figures (maintainer's call on #1969: the editor should offer the new
    defaults), so a device still on v37 renders such a figure with the old
    default until it updates.
  v38 also adds `ParamSpec.entryDefault`, a value the figure editor seeds on
    picking a move when it should differ from `defaultValue`
    (`Taxonomy.entryParams`). It is never read for a figure that omits the
    param, so it changes no stored meaning and owes no rebuild. It is used for
    the balance flag, which authors usually set but which a source that does not
    state it leaves unbalanced: `box_the_gnat`, `box_circulate` and
    `pass_the_ocean` seed `balance` true with 8 beats, and `form_long_waves`
    seeds `balance` true with 4 (its 0-beat formation label plus the balance's
    4). Each is the state the editor's own "+4 beats when balance turns on"
    rule reaches by ticking balance, so unticking returns the plain default.
    `box_the_gnat.goodBeats` and `box_circulate.goodBeats` become `[4, 8]` so
    the seeded 8 raises no `atypical_beats` warning. The Settings per-move
    defaults diff against `entryParams`, so a saved override is a diff from
    what the editor actually offers, and changing `balance` there records the
    matching `beats` too (the same +/-4 rule), because a saved default is
    applied to a new figure as plain values.
  v38 also adds two `pairDancerSets` tokens, `thirdCorners` and `opposites`
    (#1975, maintainer decisions), and moves the corners after the neighbour
    series, so the picker reads ... `fourthNeighbors`, `firstCorners`,
    `secondCorners`, `thirdCorners`, `opposites`, then the mixer partner
    series. A square's corner is a contra first corner, and The Caller's Box's
    square corners C1, C2 and C3 are the first corners, the opposites and the
    third corners. Both tokens are added to `_heyMeetTargetChoices` (and so to
    the mad robin and butterfly whirl pairs), beyond ContraDB's
    `chooser_pairz`, as v24 did for the partner series; that is the author's
    call. Neither has a pair inverse or a compound opposite, the author's
    call: `invertPairDancerSet` mirrors ContraDB, which has neither token.
    Purely additive for stored data: no figure's meaning or canonical text
    changes, and the order of `pairDancerSets` is display order only. A device
    still on v37 shows the new tokens humanized ("third corners",
    "opposites"), but its figure editor replaces a value it does not know with
    the param's default when the figure is opened, so editing such a figure
    there loses it, as with v24's partner series.
  v38 also makes `form_short_waves` a zero-count figure without its balance
    (#1975, maintainer decision): its `beats` default becomes 0, a
    `paramBeats` rule gives 4 with the balance and 0 without, and `goodBeats`
    becomes `[0, 4, 8]` (8 for The Caller's Box's folded form-and-balance
    lines, the author's call, so they raise no new `atypical_beats` warning).
    Its `balance` default stays false and it seeds nothing in the editor; the
    Settings per-move defaults record the matching `beats` when `balance`
    changes, as they do for a move that seeds one; this now covers every move
    whose `paramBeats` follows its balance, so Rory O'More and petronella too. A stored form short waves
    that omits `beats` now counts 0 rather than 4; one that states its beats
    keeps them. The derived `dance_figures.beats` and `deriveSections` read a
    figure's own stored `beats`, not the taxonomy default, and `beats` is not in
    its canonical text, so nothing is owed beyond v38's existing rebuild.
- v39: a figure 8 or poussette fraction of `other` states its amount (#2120,
    maintainer decisions relayed 2026-11-11). Before, `other` stored no amount:
    the ContraDB adapter turned any number but 0.25/0.5/0.75/1 into a bare
    `other`, the editor offered `other` with nowhere to put the amount, and the
    line read "ones other figure 8".
  - `figure_8` and `poussette` gain an `amount` param
    (`fractionAmountParam`): a `ParamKind.rotation` (quarter steps, 0.25–2.5)
    that opts into the `unspecified` sentinel and defaults to it. It is read
    only while `fraction` is `other`; an amount left under a named fraction
    means nothing and is dropped by the editor. An amount a named fraction
    states is stored as that fraction (`fractionParamsForAmount`), so in
    practice `other` carries 1¼–2½. **Why a sibling param and not a numeric
    `fraction`:** nothing on the sync, share or archive path validates param
    values, and an older build's editor rewrites a fraction it does not know
    to `half` when the figure is opened, then syncs that back. A sibling param
    is left alone by an older build, which keeps showing "other". Thirds and
    eighths are not representable; contra calls them essentially never, and a
    free-text amount (the rejected alternative) could not be filtered, checked
    or turned into beats.
  - `figure_8.paramBeats` gains `beatsPerAmount: 16` (ContraDB's
    `half_or_full * 16` carried past `full`, our extension: ContraDB has no
    amount beyond full), so a 1½ figure 8 is 24 beats; validation does not
    flag a count the move's own rule derives as atypical. Poussette still has
    no per-value beats.
  - Wording: an `other` with an amount renders as the amount (`ones 1½ figure
    8`, `1½ poussette - …`; `one and a half` verbose; a whole amount is spelled
    `two`, because a line that opens with a bare number is read as its beat
    count). One with no amount renders `an unstated amount of` on display and
    `unstated amount` in canonical text, never the bare token. The poussette
    line now uses the verbose fraction words too ("three quarters
    poussette"). The display read-back (#2121) reads the new wording, and the
    word `other` still reads back as an `other` with no amount.
  - Producers: the ContraDB adapter keeps a quarter-step number up to 2½ as
    `other` with `amount` (a number outside that domain is still a bare
    `other`, which reads as unstated); the figure parser reads a mixed amount
    (`1 1/2`, `1½`) for a figure 8 or poussette, where it used to fall back to
    a custom figure.
  - Migration: none of stored data. An `other` stored before v39 stays an
    `other` with no amount, because nothing it came from survives to say what
    the amount was (the provenance raw payload went in schema v21, #781, and
    ContraDB never produces such an amount anyway). Its canonical text changes
    ("other" -> "unstated amount"), so v39 owes a one-time canonical/FTS
    rebuild, guarded by `taxonomyV39CanonicalRebuildDoneKey` and listed in
    `oneTimeRepairMarkers`, so the pre-repair snapshot covers it.
  - Keys: `figureSnippetSignature` and the re-import diff key
    (`figureCanonicalKey`) include the amount only while it is stated, so every
    key a pre-v39 figure had is unchanged and no snippet-signature version
    bump is owed. The v1 signature migration's legacy `amount` -> `travel`
    rename is narrowed to `orbit`, the only move that had one, because conflict
    keys pass through it on every load.
  - Figures of your own no longer offer `other` for a fraction argument, nor
    does a per-move default in Settings ▸ Defaults (`offersFractionChoice`):
    an argument cannot carry an amount through to the move it fills, and a
    default seeds none. Settings does not offer `amount` either. One already
    chosen still validates and is still shown; a figure of your own expands
    it as an unstated amount (no amount is seeded), and a saved `other`
    default is no longer applied (`skipsMoveDefault`).
  - `figure_8` gains a `double` flag (default false), amending v39 because
    v39 has not shipped. Display wording only: it changes the figure's line
    ("ones lead a double half figure 8 up between twos, twos cast down the
    outside"), not canonical text or beats, so it owes no rebuild. The cast is
    the first pass mirrored (up -> down, down -> up) by the pair the line names
    between (`others` included); across casts "to follow"; with no direction
    stated there is nothing to mirror and no cast clause is written. The
    display read-back reads the double wording only with its mirrored cast.
    Because canonical text omits it, a double and a single figure 8 index
    identically for search; ContraDB has no such param, so none is imported.
    **Stored only while true** (`figure8DoubleParam`): `entryParams` and the
    free-text entry's draft both pass through `Taxonomy.dropUnstatedParams`
    (which also drops an unstated `amount`), and `applyParamChange` removes the
    key when turned off, so a figure 8 that is not double carries nothing a v38 peer's `validateFigure` would
    reject as `unknown_param`. Like `amount`, only a figure 8 marked double
    meets the "Older devices" limit above: a compound of the user's own whose
    template holds one is marked "needs repair" there. No maintainer decision
    covers widening that limit, so it is kept to figures that state `double`.
  - **Older devices (taxonomy v38, app 0.9.x).** A v38 build stores, syncs,
    shares and restores an `amount` it receives unchanged (the figure codec
    and the sync figure check never look inside params), renders such a figure
    as "other", and opening it in the editor keeps `other` (a valid value) and
    the amount. Its `validateFigure` rejects the unknown param
    (`unknown_param`), and the one place that bites is a compound of the
    user's own whose template holds such a figure: `decodeCompoundDefinition`
    returns null there, so the entry is marked "needs repair" and cannot be
    placed or used by a shorthand on that device, and a repair there means
    removing or changing the figure, which drops the amount and syncs back.
    Maintainer decision, 2026-11-12 (on #2120): accept and document it, with
    no refusal of such templates and no sync capability gate. The limit is
    general: an older build's validator rejects any param a later taxonomy
    adds, so every such bump has it. To keep it to figures that state an
    amount, the key is written only then: `Taxonomy.entryParams` does not seed
    the `unspecified` default, the editor drops it with a named fraction, and
    compound expansion does not seed one (an `other` argument expands as an
    unstated amount).
  - v39 also adds `forward_and_back`, forward and back in a named formation,
    and makes `long_lines`, a move until now, its alias. The formation list,
    the alias, its `longLines` default, routing between the two ids, and
    keeping dialect entries keyed on `long_lines` are the maintainer's choices
    in the session that wrote this, recorded in the description of the PR
    that adds it.
    - `forward_and_back` has `long_lines`' params, `goBack` and `beats` with its
      `paramBeats` (8 with `goBack`, 4 without), plus `formation`: a
      `ParamKind.choice` of `longLines`, `inSquares`, `linesOfThree`,
      `linesOfFour`, `linesOfFive`, `linesOfSix`, `asCouples`, `headCouples`,
      `sideCouples`, `inARing`, `inLinesAtHeads` and `inLinesAtSides`
      (`forwardAndBackFormations`), defaulting to `longLines`. ContraDB has
      long lines only, so its advanced filter refuses a `forward_and_back`
      leaf, and `long_lines` there carries no formation.
    - `long_lines` is an alias pinning `formation: longLines`, with
      `inversePairId: forward_and_back`, so `resolvedMoveId` routes a long lines
      whose formation changes to `forward_and_back`, and a forward and back left
      in long lines to `long_lines`. This is the first inverse pair on an axis of
      more than two values; the routing already handled one (the alias side
      routes away on any value but its pin, the target side back on the pin
      alone), so only its documentation changed. Stored `long_lines` figures
      keep their source JSON, canonical text (`long lines`) and display lines;
      their effective params gain `formation: longLines`, the alias's pin.
      Importers and the `while` modifier still produce and recognise
      `long_lines`. A figure starts under the id it is stored with: picking
      forward and back in the figure editor, or typing a bare `forward and
      back`, gives a long lines, since long lines is the default formation.
    - Wording: a forward and back displays as its formation then `forward &
      back` (verbose `forward and back`), or `forward` without `goBack` (`lines
      of three forward & back`, `in a ring forward`); its canonical text is
      `<formation> forward and back` either way, as `goBack` never was in long
      lines' canonical text. `long_lines` keeps its own lines: the display base
      renderer for `forward_and_back` is not used for it. Both camelCase
      humanizers (the renderer's and the app's `humanizeToken`) now break
      before a capital that starts a word after a one-letter capital word, so
      `inARing` reads `in a ring`; no earlier token has that shape, so no
      canonical text changes.
    - `MoveAlias.listedAsMove` (true for `long_lines` alone) keeps long lines
      standing as a move outside the taxonomy. The pickers that offer moves and
      not aliases (the dialect editor, Advanced search's "Has figure", Settings'
      per-move defaults) offer it, without its pinned `formation`: its figures
      are stored under `long_lines`, so a structured search must be able to
      name it. A dialect's name and wording for it apply to it and its
      target's never: dialects hold entries keyed on `long_lines` from when it
      was a move, and long lines' name is a formation where forward and back's
      is a direction, so a name for one would misread the other. A search never
      maps an alias's id through a dialect's names, as it never did a move's.
    - Free text reads a forward and back's displayed line back (a reader used
      by free-text entry only, so imports are unchanged), and a bare `forward
      and back` reads as long lines, the default formation. The note-tail rule
      now sees `forward and back` as a move's name, so `(8) Slice left, forward
      and back` typed as free text stays custom rather than a slice with that
      note.
    - A copy of long lines into a figure of your own is a long lines (its
      wording `{move}`, no formation parameter, copied from `long_lines`), and
      its wordings in a dialect offer no `formation` slot or condition: its
      name already says the formation. A note repeating long lines' own name is
      read as its name, as for every move (#1975). Picking forward and back in
      the figure editor applies the defaults saved for it, then long lines'
      when the pick is stored as long lines; a default formation other than
      long lines keeps it a forward and back.
    - The walkthrough-snippet signature (`figureSnippetSignature`) of an alias
      listed as a move is its own id without the params it pins, so every long
      lines keeps the key `long_lines` it had as a move (a forward and back in
      long lines shares it) and no signature version bump is owed; the other
      formations sign as `forward_and_back(formation=…)`. The re-import diff key
      (`figureCanonicalKey`) of a long lines changes, to `forward_and_back` with
      its formation, but it is computed on both sides of each diff and never
      stored, so nothing is migrated.
    - A matrix column saved on `long_lines` (parameterized or a compound step)
      matches its target with the alias's pin added, so it still counts long
      lines and no other formation. The column editor opens it as forward and
      back in long lines, and saves a column or step on forward and back that
      states long lines back on `long_lines` without the pin
      (`savedMatrixConstraint`), so a build before v39 still reads it; one that
      leaves the formation open stays on `forward_and_back`. Specificity counts the resolved constraint, so a
      column saved on long lines ranks as the same column saved on forward and
      back with the pin. The built-in long lines column follows forward and
      back's, where it stood as a move, and is labelled by a dialect's name for
      long lines, never for forward and back.
    - Migration: none, and no rebuild: no stored figure's canonical text
      changes, since nothing could store a `forward_and_back` before v39.
      **Older devices (v38).** A `forward_and_back` figure is an unknown move
      there and displays as its raw id, as every added move does. No long lines
      stores `formation`: `Taxonomy.withoutListedAliasPins` drops the alias's pin
      where a figure is built for storage (the editor's `FigureDraft.toFigure`,
      the dance repository's write-time routing, the free-text read-back, and
      switching a figure of your own to forward and back, which also routes a
      use switched to long lines to `long_lines`, since shorthands and default
      lists are not routed on write as dances are), although the editor seeds
      and shows it. A v38 build's `validateFigure`
      would reject the key as `unknown_param`, and its shorthand mappings drop a
      whole mapping holding such a figure, so a long lines entered on v39 must
      read on v38 exactly as one entered there.
  - v39 also adds `trade_the_wave`, the Modern Western Square Dance call: from
    short waves everyone steps forward, turns to face the other way and trades
    with the dancer facing the same way, passing right shoulders, reforming
    short waves facing the other direction with centers and ends swapped. It
    was added from a figure of the user's own of the same name, which
    `trade_the_wave_test.dart` reproduces, and the choices below that are not
    that figure's are the authoring session's, each with its reason.
    - Params are that figure's, key for key, so switching one's uses to the
      move (#1023) maps every parameter to the one of the same key: `sides`
      (`dancerSet`, default `neighbors`), `center` (`dancerSet`, `role1s`),
      `centerHand` (`handedness`, `right`), `axis` (`direction`, `across`) and
      `balance` (`flag`). As in `form_short_waves`, `center`, `centerHand` and
      `sides` name the wave the figure ends in, and the side hand is the other
      hand. The defaults are the figure's, and are also the wave trading
      `form_short_waves`' default wave gives and the one The Caller's Box
      glossary's sample notation ends in.
    - `balance` defaults to false with an entry default of true, and `beats`
      to 4 with an entry default of 8, as `pass_the_ocean`'s do; `paramBeats`
      is 8 with the balance and 4 without. The figure of the user's own
      defaulted its balance to true; a stored default of false is the
      authoring session's choice, so that a figure stating no balance (a
      typed bare name) never asserts one.
    - Wording: canonical text is the move name alone (`trade the wave`), as
      `form_short_waves`' is. The display is the figure's own line: "trade the
      wave - all step forward and face across, partners pass right shoulder
      and reform new short waves facing the other direction - role1s by the
      right in the center, neighbors by the left on the sides[ - and
      balance]". The dancers who trade are `sides`' opposite as a figure of
      your own computes it (`ParamOpposites`: partners and neighbors swap),
      and `others` when `sides` has none. The trade always passes right
      shoulders: the call has no left-shoulder form. The dancers are plural
      throughout, the verb agreeing with them: a figure of your own's live
      display writes them singular ("neighbor pass"), but its stored line, and
      so every use's text, is plural.
    - Reading: free-text entry reads the whole display line back
      (`readDisplayedTradeTheWave`, called from free-text entry only, as the
      courtesy turn's `whom` reader is), refusing a line whose traders are not
      `sides`' opposite or whose two hands are the same, and reads the bare
      name as the move, as it does every move's. No importer reads it, so
      imports are unchanged: The Caller's Box writes a bare "Trade the wave",
      which names none of the wave it ends in, so it stays custom text, and
      ContraDB has no such figure, so its advanced filter refuses a
      `trade_the_wave` leaf. The note-tail rule now sees `trade the wave` (and
      the search keyword `trade wave`) as a move's name, so a typed line whose
      note would start with it (`neighbors balance, trade the wave`) stays
      custom rather than a figure with that note.
    - Migration: none, and no rebuild: nothing could store a `trade_the_wave`
      before v39, and no stored figure is converted. Uses of a figure of your
      own with this name become the move only through the existing switch
      (#1023), which the user starts. **Older devices (v38).** A
      `trade_the_wave` figure is an unknown move there and displays as its raw
      id, as every added move does.
  - v39 also adds `starburst`: a zig zag's path danced without hands, the
    dancers arcing out of the set around `travel` couples and back in on the
    side they started. It is in neither ContraDB nor The Caller's Box. The
    maintainer asked for it in the session that wrote this, from a figure of
    their own of that name, keeping its parameters, defaults and wording
    template, except that `travel` is a `ParamKind.number` where theirs was
    `places`; the PR that adds it records the request.
    - Params: `direction` (`spinDirection`, default `counterclockwise`),
      `travel` (`number`, default 1: the couples passed, not places around a
      ring, so it renders as the digits alone), `who` (`dancerSet`, default
      `role1s`, the dancers who lead), `whom` (`dancerPair`, default
      `partners`, those they lead out), and `beats` (default 8, `goodBeats`
      `[8]`, the author's choice from that figure's 8 default beats). Search
      keyword `dolphin loop`. `starburst` is the first built-in
      slot of `ParamKind.number`, so the combination editor now offers that
      kind as well as the figure-of-your-own editor.
    - Wording: the template of the figure of the maintainer's own, with its
      literal `starburst` replaced by `{move}`, is the canonical
      `renderTemplate`: `{move} {direction} around {travel}, {who} lead {whom}
      out of the set`. The display takes the same template, and so, as their
      figure did, names a positional dancer in the singular, as the display
      does wherever one appears (`role2s lead partner out of the set`). As a
      modifier side it reads `doing a starburst`.
    - Free text reads the display line back
      (`readDisplayedStarburst`, called only by free-text entry, so no
      import's grammar changes), under its own name or a dialect's name for
      it. Every slot is required and only the whole line is read. Under a
      dialect whose roles are lead and follow, the verb `lead` is also a role
      word, and canonicalizing the whole line reads it as one before a dancer
      it does not take as an object (`leads lead third neighbor`), so the
      reader also tries each `lead` with the role words on either side
      canonicalized apart.
    - As for `forward_and_back`, the new name and keyword are now move words
      to the note-tail rule, so a typed line whose note names one stays custom
      (`(8) Slice left, starburst` or `…, dolphin loop`, where `…, sunburst`
      is still a slice with that note), and a glossary entry named `dolphin
      loop` now meets a shipped figure's keyword, as `starburst` meets its
      name.
    - ContraDB has no such figure, so its advanced filter refuses a
      `starburst` leaf.
    - Migration: none, and no rebuild: no stored figure can reference a move
      that did not exist. A v38 build displays a `starburst` by its raw id, as
      it does every added move. A figure of your own named starburst now
      shares a shipped figure's name, which the app reports as it does any
      such collision (#1023). A switch must map every parameter, onto one of
      the same kind or, for `places`, onto a plain `number`, which takes every
      count places can (`userFigureSwitchTargets`). So a figure of your own
      whose `travel` is `places`, as the maintainer's export declared it, can
      switch its uses to the move; each count is kept, and reads `around 2`
      where it read `around 2 places`. The maintainer asked for that widening
      as a follow-up to #2200, which added the move and whose description
      proposed it.
  - v39 also adds the third and fourth couples' dancers: `threesRole1`,
    `threesRole2`, `foursRole1` and `foursRole2`, appended to
    `ParamVocab.singleDancers` and so at the end of `ParamVocab.dancerSets`,
    after `twosRole2`. In the session that wrote this the maintainer asked
    for "third role1s/role2s and fourth role1s/role2s" at the end of the
    dancer list, confirmed the reading as one dancer of the third or fourth
    couple, and asked for `figure_8.lead` and `dolphin_hey.whom` to offer them
    and for The Caller's Box's `M3`/`W3`/`M4`/`W4` to read as them. The token
    names and the rest below are the author's calls.
    - Domain: every param that takes any dancer (no `choices`, or
      `_dancerOrUnspecified`: `gate`, `mad_robin.who`, `courtesy_turn`,
      `promenade` and `pull_by`) offers them, and so do the single-dancer
      params `figure_8.lead` and `dolphin_hey.whom`, which now take all of
      `ParamVocab.singleDancers` rather than ContraDB's `chooser_dancer` four.
      They are not hey meet targets (single dancers never are) and have no
      pair inverse or opposite.
    - Wording: the display reads them as `third`/`fourth` and the role's
      singular term, as it reads the ones and twos (`third lark`, `fourth
      follow`); a dialect's `dancers` substitution wins, and the dialect
      editor lists them.
    - Reading: free-text entry reads them back wherever it reads `first lark`
      (the figure parser, the dancer-and-name table, the display-line
      readers), and the role canonicalizer counts `fourth`/`4th` as a
      determiner and an ordinal, as it counted `third`, so `fourth follow`
      stays a role under Leads/Follows. That includes the figure 8's
      `LEAD leading` and the dolphin hey's `passing WHOM`. ContraDB has no
      such dancer and never names one, and its advanced filter skips them.
    - The Caller's Box: `M3`/`W3` and `M4`/`W4` are the third and fourth
      couples' role1 and role2 (`dancerWords`), as `M1`/`W1` and `M2`/`W2`
      are the ones' and twos', so `M3 figure eight up` reads with `who`
      `threesRole1`. A line an earlier import kept as custom text for one of
      them reads as the figure when the user re-checks unrecognized figures.
      The per-role annotation synthesis is unchanged: `(M1 past M3, W1 past
      W2)` still declines.
    - Migration: none, and no rebuild: nothing could store them before.
      **Older devices (v38).** A v38 build displays one humanized (`threes
      role1`), and its figure editor replaces a value it does not know with
      the param's default when the figure is opened (for a param whose
      default is `unspecified`, such as `gate.who`, "not stated"), so editing
      such a figure there loses it, as v37 did for v38's corners.
  - v39 also adds `hey_for_three`. The maintainer asked for it in the session
    that wrote this: "matching the parameters and display text for 'dolphin
    hey' except that the 'who' param matches the specific dancers list used
    for 'whom' rather than including all dancer options". The PR that adds it
    records the request.
    - Params: the dolphin hey's, in its order: `who`, `whom`, `shoulder`
      (default `right`) and `beats` (default 16, `goodBeats` `[16]`), with
      its canonical template `{who} {move} {shoulder}` and no search keyword.
      `who`, the dancer who starts, takes `ParamVocab.singleDancers`, as
      `whom` (default `onesRole1`) does, where `dolphin_hey.who` takes any
      dancers. Its default, `twosRole2`, is the author's call: the dolphin
      hey's `ones` is not one dancer, and `onesRole1` would start the hey
      passing themselves under `whom`'s default, so `whom` keeps the dolphin
      hey's default and `who` takes the other couple's role2.
    - Wording: the dolphin hey's display under the move's own name: `hey for
      three - start with second robin passing first lark by right
      shoulders`. Both dancers render as single dancers, in the dialect's
      words. As a modifier side it reads `doing a hey for three`. The
      glossary text is checked against The Caller's Box's "Hey for three"
      entry, which the maintainer supplied after #2205 merged. That entry
      says only that some variants make a couple one of the three; the
      glossary names the dolphin hey as one of them, which is the author's
      reading, and its beat count is the taxonomy's.
    - Reading: free-text entry reads the bare name and the whole display
      line back (`readDisplayedHeyForThree`, called only by free-text entry,
      as starburst's reader is), under its own name or a dialect's name for
      it, reading role words by the dialect. It also reads the name with the
      numeral, `hey for 3`, alone (a typed phrasing, as `hey for 4` is the
      hey's) or opening the display line. No importer reads it, so imports
      are unchanged: ContraDB has no such figure, and its advanced filter
      refuses a `hey_for_three` leaf. The figure-text corpus fixture has one
      line for it, from a beta tester's Caller's Companion library (`Hey for
      3 along set (N1 pass R, N2 L-sh, …)`), which states a direction and a
      four-pass list the move has no slots for; it stays custom text.
    - Migration: none, and no rebuild: no stored figure can reference a move
      that did not exist. A v38 build displays a `hey_for_three` by its raw
      id, as it does every added move. A figure of your own named hey for
      three now shares a shipped figure's name, which the app reports as it
      does any such collision (#1023), offering to switch its uses to the
      move.
  - v39 also lets a dance leave a circle's or star's distance unstated. The
    maintainer asked for it in the session that wrote this: "Remove the
    requirement that a circle or a star set a value for places in the dance
    editor." The PR that adds it records the request; the design below is
    the author's.
    - Params: `circle.places` and `star.places` list `ParamVocab.unspecified`
      in `choices`, and `ParamKind.places` now admits the sentinel when a spec
      lists it, as `ParamKind.rotation` does (`ParamSpec.validate`,
      `paramDomain`; a compound param bound to no slot admits it too, as an
      unbound rotation does). Their defaults stay 3
      and 4, so a figure that omits `places` still reads that many places, and
      a new figure in the editor starts with that many unless the user's own
      Settings default for the move leaves it unstated.
      Making `unspecified` the default instead was rejected: it would change
      how every stored figure that omits `places` renders (a figure the parser
      read from `circle left` with no count), which the request did not ask
      for. `facing_star.places`, `square_through.places` and
      `circular_hey.changes` still require a number; the request named only
      the circle and the star.
    - Editor: the places field of a param that admits the sentinel may be left
      empty. Empty stores `unspecified` and shows "not stated" instead of the
      range error; a field opened on the sentinel is empty. Any other text
      that is not a count from 1 to 10 is still an error. Every editor built
      on the param's spec gets this: the dance editor, the Settings per-move
      defaults, the program matrix's figure columns, and a compound's argument
      bound to such a slot (which shows the empty field rather than a made-up
      count; a compound's argument summary now reads "not stated" for the
      sentinel of any kind but text, where it read "unspecified").
    - Wording: the sentinel renders as nothing on every path, display and
      canonical, single file included: `circle left`, `star right - wrist
      grip` (the grip clause drops the dash that would lead into the count),
      `single file promenade right (circle, counterclockwise)`.
      Snippet signatures write it as `places=unspecified`, and
      `describeFigureSignature` now reads that token back for any numeric
      param that admits it (`gate.travel` too, which used to fall back to the
      raw signature).
    - Reading: no reader produces the sentinel. A line with no count, such as
      `circle left` or the display of an unstated circle, still reads as
      `places` omitted, so it comes back with the default. Free-text entry of
      an unstated circle's display line therefore gains a count.
    - Migration: none, and no rebuild: no stored figure could hold the
      sentinel before, and every canonical text is unchanged. **Older devices
      (v38).** A v38 build has no sentinel in these specs, so it renders such a
      figure as `circle left unspecified` (`star left unspecified`, `star left
      - wrist grip - unspecified`). Its places field shows the default without
      writing it back, so the sentinel survives until the user edits that
      field there. Its `validateFigure` rejects the sentinel, so there a
      synced compound whose template holds an unstated circle or star reports
      an invalid template, and a compound argument of `unspecified` does not
      expand.
- v40 (`cast` and the `hand_cast` alias, issue #770; also `shift`, below): the largest family
  of Caller's Box lines the taxonomy could not hold. Of the 2,066 lines
  mentioning a cast in the 1,563 public dances whose figures mention one
  (fetched 2026-11-19; `docs/research/callersbox.md`), 2,060 were `custom`;
  443 still are with all of v40 (469 with the cast move alone, before the
  `threes`/`fours` and role-number dancers below).
  - **`cast`** (`who`, `direction`, `places`, `whom`, `destination`, `beats`
    4). Every param but `beats` defaults to `unspecified`, because the source
    writes casts with every part optional. The maintainer's rulings
    (2026-11-19), each recorded where it applies:
    - `direction` is `left`/`right` (the shoulder turned over), `up`/`down`,
      or unstated. "Clockwise" is the right shoulder and "counterclockwise"
      the left.
    - The display reads an unstated direction as "cast back", a shoulder as
      "cast back left/right", and up/down bare. The canonical (search and
      dedupe) line keeps the stored token: `role2s cast right`.
    - "Cast off" is `down` with `places` 1 unless the line states a number:
      the glossary's "ones peel down the outside into second place" is a cast
      down one place. Whether the cast is assisted is not a param; the
      glossary says it "depends on your community".
    - A role's cast with no shoulder stated is over the right shoulder for
      role2s and the left for role1s ("as we do for chains"), and the
      maintainer limited that assumption to The Caller's Box adapter
      (`CallersBoxAdapter`, `_assumeCastShoulders`, which recurses into
      `||` sides). Typed text, a re-check of stored lines and other sources
      leave an unstated shoulder unstated, so a re-check of an older import
      differs from a fresh one on those lines (68 in the 1,563 dances, all
      "Women/Men cast back …"). The editor assumes nothing either.
    - The display always shows a shoulder, even the role's usual one
      ("role2s cast back right"): the maintainer's ruling, unlike a chain's
      role-implied hand, which goes unsaid.
    - `destination` holds ECD's destination tokens plus `top` and `bottom`.
      The maintainer decided this shape and ECD's `ecd_cast` be one, so
      ADR-006 F5 maps one to the other. ECD's taxonomy v1 took it before
      release (ADR-006 §9.4); `cast_test.dart` pins that the two agree on
      param names and on `direction` and `destination` choices, and that
      contra's destinations hold every ECD one.
  - **`hand_cast`**, an alias of `gate` pinning nothing: the maintainer's
    ruling, on The Caller's Box glossary calling each "very similar" to the
    other. It is listed as a move (`listedAsMove`), for the reasons
    `long_lines` is: it is stored under its own id, so search's "Has figure"
    must be able to name it, and a dialect's name or wording for `gate` must
    not rename it. It displays through `gate`'s renderer under its own name
    ("neighbor hand cast ½ to face up"). From The Caller's Box only a bare
    "Hand cast" reads as one; "Ones hand cast" stays custom, because the
    source does not say which of a gate's dancer slots "ones" fills. Typed
    or pasted, a hand cast's display line reads back wherever a gate's does
    (the display's own gate grammar, through `_handCastDisplay` in the
    ContraDB front end), which `cast_test.dart` checks value by value, since
    the round-trip sweep covers moves and not aliases. It keeps the gate's 8-beat
    default; imports carry the line's own beats (4 on 113 of 140).
  - The Caller's Box front end (`callersbox_figure_dialect.dart`,
    `_tcbCast`) reads a cast's `(cw)`/`(ccw)` annotation as its shoulder (1
    line, `Men cast back (cw) || Women go forward`, which the assumption above
    would otherwise have read as the left), and `(past twos; threes)`: the
    count fills `places` and the text is kept as a note. Only a list of dancers counts (`twos`, `N2`,
    `W1`, `N2 twos`, `shadow S1`); `(past ones and threes)`, `(past twos,
    threes)`, `(past S; to partner)`, `(past top couple)`, a second `(past …)`
    in the clause, or a count the line contradicts keep the line custom.
    `[with N1]` is a note, as on other moves.
  - **Not modelled, so still custom:** multi-step `;` lines whose other
    clauses do not parse (207 lines, mostly `lead through …; separate; cast
    …`, which keeps the maintainer's "lead through; separate; cast back to
    place" group custom), "others follow"/"inverting lines" riders (95),
    casts by dancers no move reads (`Ends`, `Inside ends`, two named
    dancers at once, which keeps "Ends cast back to P2" custom; 23), inside a
    double figure eight
    (26), `around the major set` (25), endpoints outside the destination
    list ("to ends of line of four"; 22), `behind <dancer>` (13), and the 6
    `(past …)` lists above.
  - `cast.direction` takes no opposite in `ParamOpposites`: like
    `circle.direction` it is a free-form choice slot, and its values are two
    pairs on different axes.
  - **`threes` and `fours`** join the dancer sets, after `twos`: the third and
    fourth couples as groups, for triplets, triple minors and four-couple sets
    (the maintainer's ruling, 2026-11-19). They are the tokens ECD's selectors
    already use. Like their single dancers (`threesRole1` …, v39) they are
    offered in every dance, not only one whose formation has a third couple,
    and they have no opposite (`pairInverse` names none). Like the ones they
    pass in the center of a hey they start, and a hey can run until they meet
    (both the author's calls, as v24's and v38's meet targets were); a hey's
    ricochet by the pair on the ends reads "others ricochet". The Caller's
    Box's `Threes`/`Fours` read as them, including before a wave balance.
  - **A role and a couple number name that couple's dancer**: The Caller's
    Box's "Woman one" and "Man three", which reach the reader as `role2 one`
    and `role1 three`, are `onesRole2` and `threesRole1`, shown as "first
    robin" and "third lark" (the maintainer's ruling). "One" after a group
    ("Women cast down one place") still counts places.
  - **Older devices (v39)** render `threes`/`fours` as the bare word, and
    keep it while the figure is only viewed or synced. Opening that figure's
    editor there corrects the out-of-domain value to the param's default (the
    dance editor's dropdown writes back any value it cannot offer), and the
    edit syncs. Every dancer token added before (v38's corners, v39's single
    dancers) has the same exposure. The maintainer accepted this for the beta
    (2026-11-19), so no guard is added.
  - **`form_long_waves` holds both hands and may leave the facing unstated**
    (issue #2331, the maintainer's rulings of 2026-11-23). The Caller's Box
    writes `Balance long wave (N2R,N1L, women face in)`: next neighbors by
    the right, neighbors by the left, women facing in. `whom2` (default
    `unspecified`) is the pair held by the hand opposite `whomHand`, so it has
    no hand of its own; the display reads "next neighbor by the right,
    neighbor by the left, …". `who` now admits `unspecified` (its default
    stays `role1s`, so ContraDB imports and new figures read as before), for
    the bare `form long wave` that states long waves but not who faces in;
    that facing then renders nothing, and the canonical text is the bare
    `form long waves`. `who` offers no manual Clear, as `promenade.direction`
    does not: a stated facing is not returned to "not stated" by hand. The
    same rulings read a bare TCB `form long wave` as `form_long_waves` —
    forming a long wave in the center (`form long wave in center`,
    `form_a_long_wave`) is a different figure — and fold its balance into it,
    across a phrase boundary too; the holds written on the forming line
    itself, `form long wave (P2L,P3R)`, read the same way (#2331 follow-up),
    with the facing `unspecified` when the line names none; see
    `docs/design/imports.md`.
    **Older devices (v39)** have neither change. A synced
    `form_long_waves{who: unspecified}` renders through v39's display line,
    which names a subject and its inverse unconditionally, so it reads
    "form long waves - unspecified facing in, others facing out"; v39's
    `who` domain does not admit the sentinel, so opening that figure's
    editor there writes back the default `role1s`, and that edit syncs as a
    facing the source never stated. v39's renderer reads no `whom2`, so a
    two-hand long wave shows only its first hold there; whether v39's editor
    keeps or drops a param it does not declare when it saves was not
    checked. Whether the beta acceptance recorded above for the new dancer
    tokens also covers these is the maintainer's call, not assumed here.
  - **`rory_o_more.twoPlaces`**: who slides two places, across the set,
    while the others slide one, as in The Caller's Box's "Leap of Faith"
    (#1797): `Slide left, women slide two places (M past N, W past (N;W))`.
    The maintainer chose the shape and its choices (2026-11-24): a dancer
    set of `role1s`, `role2s` or `ends` (the wave's ends; the token ECD and
    squares already use), not `centers` and not `everyone`, defaulting to
    `unspecified`, the ordinary one-place slide. The maintainer also chose the
    display wording, a trailing clause in the dialect's words: `balance & Rory
    O'More left, robins 2 places`. Display-only, like a hall's ender (the
    author's call, rejecting a template slot because that would have changed
    the canonical text and needed a rebuild): `renderTemplate` leaves it
    out, so the canonical line, and so search text and dedupe, do not
    change. Typing "2 places" into search does not find it. The Advanced
    search param filter does. The display line reads back through the
    ContraDB front end (`_roryTwoPlaces`). The Caller's Box adapter folds
    the line into the Rory O'More only straight after a balance-wave line
    (`_longSlide`, beside `_foldBalanceWaveIntoRory`), keeping the bracket as
    the note. Alone, or naming other dancers, the line stays custom.
    The clause is part of the summary, not the move's template, so a
    dialect's move wording for `rory_o_more`, and a figure's own wording
    override, show the line without it, as they do a hall's ender and the
    `balance &` prefix. The snippet signature keys on template params only,
    so a teaching snippet is shared by the long and the ordinary slide, as it
    is by a single and a double figure 8 (the author's call: `amount` joins
    the signature because it replaces the fraction on the line, while this
    only adds to it).
    **Stored only while it names dancers** (`roryTwoPlacesParam`), as
    `figure_8.double` is: `entryParams` seeds none, `applyParamChange` removes
    it when cleared, and `dropUnstatedParams` drops an unstated one. Settings ▸
    Defaults now records neither a cleared `twoPlaces` nor a `double` turned
    off as a move default, and picking a move or typing a figure drops one a
    saved default still holds; before this, a `double` toggled on and off in
    Settings was saved as `false` and seeded into every new figure 8.
    **Older devices (v39)** do not declare the param. They show the Rory
    O'More without the clause, and their dance editor copies every stored
    param into its draft (`FigureDraft.fromFigure`), so the value should
    survive an edit there; no v39 build was run to check that. Their
    `validateFigure` rejects it as `unknown_param`, which, as with v39's
    `amount` and `double`, bites a compound of the user's own whose template
    holds such a Rory O'More: it is marked "needs repair" there, and a repair
    that removes or changes the figure drops the value and syncs back. The
    maintainer accepted that exposure for `amount` (2026-11-12, #2120) and
    for `twoPlaces` (2026-11-24), with no refusal of such templates and no
    sync capability gate.
  - **`shift`** (`who`, `direction`, `beats` 4): one named group sidesteps
    while the others stay or dance something else, as in The Caller's Box's
    "Women allemande right 3/4 || Men shift left" (Mary Cay's Reel, dance
    10579). The maintainer asked for it (2026-11-24), and asked that The
    Caller's Box's bare "Shift left", which names no dancers, keep reading as
    `slide_along_set`, where every couple moves. The author proposed the
    shape below from a census of the 1,427 public dances whose figures mention
    a shift (fetched 2026-11-24), and the maintainer ratified the direction
    vocabulary, the exclusion of `everyone`, the `who` and `beats` defaults,
    and joining v40 rather than bumping (2026-11-24). The rest, including the
    `direction` default, is the author's:
    - Only a line whose dancers lead and whose verb is "shift" reads as one
      (`_shift` in `figure_parser.dart`). Bare "Shift/Slide left/right" stays
      `slide_along_set`: 780 `slide_along_set` figures before the change and
      780 after, over the same dances. (The census's bare "Shift left" and
      "Shift right" lines alone number 710; the other 70 come from lines that
      name no dancers, which this reading never takes.)
    - `direction` is `left`, `right`, `up` or `down` (default `left`), since
      the source writes "Twos shift up" (20 lines, 19 of them in Four Facing
      Four dances). The four values are the maintainer's ruling; the default
      `left` is the author's. Like `cast.direction` it takes no opposite.
    - `who` (default `role1s`, and `beats` 4, the commonest count in the
      census; both the maintainer's ruling) offers every dancer set but
      `everyone`, also the maintainer's ruling: a shift by everyone is the
      slide along the set under a second name, and a leading "Everyone" stays
      custom.
    - A count of places ("Men shift left one place", "two places") is kept as
      the note in the line's words, as the maintainer allowed; no param holds
      it. A count must agree with "place"/"places". A `(past …)` or other
      parenthetical is a note, as on other moves.
    - 117 figures read as a shift in those dances. Still custom: "Others shift
      …" (no dancer set holds "others"), a destination ("to next man's
      position", "to N2"), "one step", and the bare shifts with a target
      ("Shift left to N2", "Shift left with neighbor"), which were custom
      before.
  - Migration: none, and no rebuild: new moves, an alias and a param,
    nothing renamed or removed, so no stored figure changes and every
    canonical text stays as it was. **Older devices (v39)** show a synced
    `cast` as the bare word "cast", a `hand_cast` as "hand_cast" and a
    `shift` as "shift", flag them as unknown moves, and keep their params
    intact (the #358 raw-id fallback).
  - v40 also merges **pass by and pass through into one figure**,
    `pass_through`, keeping `pass_by` as an alias, amending v40 because v40
    has not shipped. The maintainer's design (2026-11-24, recorded in the
    description of the PR that adds it): one figure with `who`, `where`,
    `shoulder` and `beats`, plus a pass type (`by` or `through`) under the
    editor's "More options"; both names stay and no picker entry is added; a
    converted figure or an import that does not state the new param leaves it
    unspecified rather than falling to custom; a figure entered new must state
    every param. The maintainer chose, among options put to them: keeping both
    stored ids, with `pass_by` an alias (rather than a new `pass` id that
    older builds could not read); per-alias defaults (rather than a one-time
    backfill); and refusing the save of a newly entered figure (rather than
    every figure, or a warning).
    - `pass_through` has `who` (a dancer set or `unspecified`, default
      `unspecified`), `where` (a direction or `unspecified`, default `along`),
      `shoulder`, `beats` (2) and `passType` (`by`/`through`, default
      `through`), last so the editor shows it under "More options". Its
      template is `{who} {move} {where}`.
    - `pass_by` is an alias pinning `passType: by`, with `inversePairId:
      pass_through` and `listedAsMove`, for `long_lines`' reasons: its figures
      are stored under its own id, and dialects hold names and wordings keyed
      on it. Changing the pass type routes a figure between the two ids.
    - **`MoveAlias.defaultParams`** (new): what a figure stored under the alias
      means by leaving a param out. `pass_by` has `who: neighbors` and `where:
      unspecified`, so a stored pass by means what it always did, and a pass
      through means `who: unspecified` and `where: along`.
      `Taxonomy.effectiveParams` reads it after the alias's pins, and
      `Taxonomy.defaultParamValue` answers "what does this id mean by an
      omitted param" for callers that read a single default (the figure
      editor's fields). When a change re-routes a figure, `keepOmittedMeaning`
      writes each omitted param whose meaning differs between the two ids at
      its old value, so a pass by that left `who` out becomes a pass through
      with `who: neighbors`, and a pass through that left it out becomes a
      pass by with `who: unspecified` stated. The editor's field, the dance
      repository's write-time routing and switching a figure of your own all
      route this way. Copying pass by into a figure of your own starts from
      `{who} {move} {where}` with `who` at neighbors, and a dialect's wording
      for it offers the `who` and `where` slots; one for pass through now
      offers `who` too. So an existing wording for pass by without `{where}`,
      or for pass through without `{who}`, is listed as missing that slot
      when the dialect is next saved.
    - **`ParamSpec.requiredOnEntry`** (new; `who` and `where` here): the
      editor seeds them `unspecified` on picking either move
      (`Taxonomy.entryParams`), and a figure entered in that edit — picked, or
      typed in the free-text composer, a Move box or the Add figures from text
      sheet (all typed entry is new entry, none of it an import: the
      maintainer's ruling, 2026-11-24, recorded in the PR description; a
      typed line starts them unstated too unless it, or a saved per-move
      default, states them) — shows a message on its fields, on a group's
      side and on its row while closed, and holds the save while one is
      unstated
      (`Taxonomy.unstatedRequiredParams`; the draft's `enteredNew`, kept across
      undo and autosave but never stored on the figure). A figure that was
      loaded with the dance, an import, or one converted from before v40 saves
      as it is. `shoulder`, `beats` and the pass type always hold a value.
      Neither param can be cleared back to unstated by hand. Only the dance
      editor asks: the compound, shorthand and Settings default editors show
      no message, as nothing there would refuse the save, and a pass picked or
      typed there starts as it did before v40 (a pass by's neighbors, a pass
      through's along), not with blanks. A shorthand placed into a dance
      brings its figures as they were saved, without asking.
    - Stored params: `withoutListedAliasPins` now also drops a pass through's
      `passType: through` (its id says it) and a required param stated
      `unspecified` where omission already means that (a pass through's `who`,
      a pass by's `where`), so a figure carries a key a v39 build does not
      know only when it states one.
    - Wording: canonical text is unchanged for every stored figure (`neighbors
      pass by`, `pass through along`), since an unstated `who` or `where`
      renders nothing; a stated one joins it (`neighbors pass through
      across`). The display leads a pass through with a stated `who`
      ("neighbor pass through across"); a pass by keeps its own line ("neighbor
      pass by right shoulders"), now followed by a stated direction. No rebuild
      is owed.
    - Keys: the walkthrough-snippet signature leaves out the param each id
      gained in the merge (a pass through's `who`, a pass by's `where`)
      whatever its value, so every pass keeps its key
      (`pass_by(who=neighbors)`, `pass_through(where=along)`), no signature
      version bump is owed, and a snippet saved before v40 still applies to a
      pass entered since, which states both. Snippets therefore still cannot
      tell a neighbors pass through from a partners one, as before v40 (the
      session's call, over keying on the new param, which would leave every
      saved pass snippet unused by new figures). The re-import diff key (`figureCanonicalKey`) of
      both changes to `pass_through` with every effective param, but it is
      computed on both sides of each diff and never stored.
    - Imports: no producer changed. The Caller's Box side-run decoder fills
      `who` on every move that declares it, so `Pass through along (NR)` now
      imports as neighbors passing right shoulders (the maintainer's
      direction). A dance imported earlier keeps its unstated `who`, and
      re-importing it offers each such pass through as a variation. ContraDB
      has the two figures apart with their own params, so its advanced filter
      leaves out `passType` and the other figure's `who` or `where`. Walk
      forward lines with a subject (`Women walk forward to N2`) still decline
      to custom: nothing reads the subject onto `who` yet.
    - Search filters on the stored id and stored params, as before: a "pass
      through" leaf matches pass throughs and not passes by, and neither leaf
      offers the pass type, which is never stored. A matrix column saved on
      pass through counts pass throughs only, as before: the target of a
      listed alias's pair whose default is not the pin constrains that param
      to its default. The built-in matrix catalog now lists pass by right
      after pass through, where listed aliases follow their target.
    - Free text reads the new display lines back: a subject before `pass
      through` (`neighbor pass through across`) and a direction after a pass
      by's shoulders. ContraDB's generated text writes neither, so it reads as
      before; a line typed by hand that leads with a subject (`partners pass
      through the center`) now reads as a pass through with that `who`, the
      rest as its note, where it was custom text.
      The contra-to-English twin of a pass through carries its `who`.
    - Square and ECD calls are unchanged: `sq_pass_by`, `sq_pass_through` and
      `ecd_pass_through` remain separate moves (the session's call, as the
      request was about the contra figure picker).
    - Migration: none, and no rebuild. **Older devices (v39)** read a pass by
      or pass through that states only what v39 had exactly as before. That
      will not be the common case for new data: every pass entered in the
      dance editor from now on states both `who` and `where`, and every pass
      through imported from The Caller's Box with a dancer code (about 2,048,
      by the count in `imports.md`) states `who`. Checked
      against the v0.10.0-beta code: one that states a new param renders
      without it (`neighbors pass through across` shows "pass through
      across"; a pass by's direction is not shown), and one holding an
      `unspecified` v39 does not accept, reachable by changing the pass type,
      shows the bare word ("unspecified pass by right shoulders", "pass
      through unspecified"). Its `validateFigure` rejects either
      (`unknown_param`, `invalid_param_value`), with the general limit the
      maintainer accepted on #2120 (recorded under v39): a compound template
      holding one is marked "needs repair" there.

### ECD taxonomy versions

`ecdTaxonomyVersion` (`ecd_taxonomy.dart`) is the same kind of documentary
marker for the English Country Dance taxonomy, logged here.

**Every bump appends an entry here, in the same PR.**
`tools/ci/check_version_history.py` fails a PR that moves the constant without
a `- vN` entry under this heading; a contra entry above it does not count. A
change added to a version that has not shipped yet amends that version's entry
instead, which the gate cannot see.

- v1: ADR-006 §7's registry: 52 movements under `ecd_` IDs, the
    `ecd_swat_the_flea` and `ecd_hand_cast` aliases, `ParamKind.dancerList`
    for `who`, and the §6.3 template notation. Migration: no stored figure changes. A dance
    that already held `ecd_` IDs (from a newer peer or an archive) was
    indexed while they were unknown, so a one-time canonical/FTS rebuild runs,
    guarded by `ecdTaxonomyCanonicalRebuildDoneKey` and listed in
    `oneTimeRepairMarkers`. **Older devices.** A build without this taxonomy
    shows an `ecd_` figure as an unknown move and keeps it as it is
    (ADR-006 §5.1).
    **Snippet keys.** `figureSnippetSignature` keys an ECD template's
    `{?flag}` like a `{param}`, and a `dancerList` as its tokens sorted and
    joined by `+`. No contra key changes, so the signature version stays 2,
    and `migrateFigureSnippetSignature` leaves `ecd_` keys as they are.
    **Amended before release (2026-11-19): cast.** By the maintainer's
    decision, `ecd_cast` takes the parameter shape of contra's `cast` (v40,
    #770; ADR-006 §9.4): `where` (off/up/down/around) is gone; `direction` is
    `left`/`right`/`up`/`down`/`unspecified`, where `left` and `right` are
    the shoulder turned over, not a side of the set; `places` is new
    (`unspecified` by default, "cast off" is `down` with 1); `whom` holds
    "cast around"; `destination` adds `top` and `bottom` for cast alone. An
    unstated direction reads "cast back", and a stated shoulder is always
    shown; no shoulder is assumed from a role. `ecd_hand_cast` is a new alias
    of `ecd_gate` that pins nothing, with `listedAsMove`, as contra's
    `hand_cast` is. v1 had not shipped in a release tag, so it was amended in
    place rather than bumped (CONTRIBUTING.md "Versioned formats").

### Square taxonomy versions

`squareTaxonomyVersion` (`square_taxonomy.dart`) is the same kind of
documentary marker for the traditional square taxonomy (ADR-007), logged here.

**Every bump appends an entry here, in the same PR.**
`tools/ci/check_version_history.py` fails a PR that moves the constant without
a `- vN` entry under this heading; a contra or ECD entry does not count. A
change added to a version that has not shipped yet amends that version's entry
instead, which the gate cannot see.

- v1: ADR-007 §7.1's traditional core: 19 calls under `sq_` IDs, whose stems
    follow their contra namesakes (`sq_pass_through`, `sq_do_si_do`), and the
    aliases `sq_allemande_left`, `sq_allemande_right`, `sq_see_saw`,
    `sq_u_turn_back` and `sq_backtrack`. "Gypsy" reads as a shoulder round,
    as it does for contra, and no square keyword is another form's move name
    or a phrase another form's text says (such as "single file"), so a
    search over every form reads those as before. The selectors are
    ADR-007 §6.2's (`squareSelectors`); a selector or destination that names
    a role (`headRole1s`, `rightHandRole2`, `role1Place`) shows the dialect's
    role term. `ParamBeats.rules` lets a count follow more than one parameter
    (a circle's size and fraction). A chain states `where` (across, along
    the line), a `fraction` (8 across, 10 three quarters round the set, 16
    over and back) and a power turn; a separate whom it goes `around` (one
    or two); a circle or star a `size` from two to eight dancers, three
    included. A forward and back has contra's `goBack` (off: a forward
    only, 4 beats), and a promenade a `direction`, contra's spin tokens,
    defaulting to `counterclockwise`, which the display leaves unsaid; a
    wrong-way promenade is `clockwise`, not a `variant`
    (both added to v1 before it shipped, on Hudson's answers of 24
    November 2026). `squareCallPrograms`
    labels the calls
    CALLERLAB also lists. Migration: no stored figure changes. A dance that
    already held `sq_` IDs was indexed while they were unknown, so a one-time
    canonical/FTS rebuild runs, guarded by
    `squareTaxonomyCanonicalRebuildDoneKey`. **Older devices.** A build without
    this taxonomy shows an `sq_` figure as an unknown move and keeps it as it
    is (ADR-007 §5.1).

## Open questions (to resolve during implementation, with user input)

1. Exact positional definition of role1/role2 across formations (esp. Becket).
2. Whether TCB's richer hey notation (per-pass lists like `(WR;PL;MR;N2L~)`)
   maps losslessly onto ContraDB-style hey params — drives the import parser;
   worst case heys import as custom text.
3. Beat conventions: TCB uses 16-beat phrases with explicit per-line counts;
   ContraDB defaults 8. We store explicit beats per figure — imports keep
   source counts.
