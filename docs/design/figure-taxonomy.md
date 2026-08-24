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
- **Aliases** are entries that resolve to a canonical move with pinned params
  (see saw → do si do{shoulder: left}; swat the flea → box the gnat{hand:
  left}). Search de-aliases automatically.
- **`custom`** is a first-class move: `{text, beats}`; its text is
  dialect-processed and FTS-indexed. `contra corners` and `turn alone` embed an
  optional custom sub-text the same way.

## Parameter types

| Type | Values | Notes |
|---|---|---|
| dancerSet | everyone, larks*, robins*, ones, twos, firstCorners, secondCorners, partners, neighbors, sameRoles, shadows, nextNeighbors, prevNeighbors, nextPartners, prevPartners, … | *canonical role IDs are `role1`/`role2` — see below. Positional/relational tokens (all except `role1s`/`role2s`) are also **dialect-substitutable** via the dialect `dancers` map. The five mixer partner-series tokens (`prevPartners`/`nextPartners`/`thirdPartners`/`fourthPartners`/`fifthPartners`) are offered in the **figure editor dropdown only when the dance is marked a mixer** — unless the figure already stores one of them, in which case it remains visible and selectable on that figure (see `offerableDancerSets`). The tokens are unrestricted everywhere else (dialect editor, search, etc.). |
| dancerPair | subset of dancerSet valid for the move | |
| handedness / shoulder | right, left | |
| spinDirection | clockwise, counterclockwise | |
| rotation | 0.25 … 2.5 in quarter steps | replaces ContraDB degrees (90–900) |
| places | 1 … 10 int | ring/star travel; replaces ContraDB degrees; renders "N places" |
| fraction | 1/4, 1/2, 3/4, full, other | heys, poussettes |
| beats | 0–64 int | 0 allowed for formation labels |
| direction | along, across, rightDiagonal, leftDiagonal, in, out, up, down | |
| enum(...) | move-specific lists (grips, enders, prefixes…) | e.g. downTheHallEnder |
| text | free string | dialect-aware |
| flag | bool | e.g. withBalance |

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
California twirl · chain (role-parameterized, not "ladies chain") · circle ·
contra corners · cross trails · **custom** · do si do (alias: see saw) ·
dolphin hey · down the hall · up the hall · facing star · figure 8 ·
form long wave / ocean wave / long waves · gate · give & take ·
**shoulder round** (was gyre/gypsy; keyword-searchable under old names) ·
hey · long lines · mad robin · orbit · pass by · pass through · petronella ·
poussette · promenade · pull by (dancers/direction) · revolving door ·
right left through · roll away · Rory O'More · slice · slide along set ·
square through · stand still · star · star promenade · swing (alias:
meltdown swing) · turn alone · zig zag

Parameter-level details (per-move param sets, defaults, valid beats) follow
ContraDB's definitions as surveyed in research/contradb.md and are finalized
in the implementation with exhaustive tests; deviations get logged in this doc.

**Beyond ContraDB.** A few moves exist because a *source* states choreography
ContraDB does not model. `courtesy_turn` (v23) is the clearest case: ContraDB
has no such figure at all (0 hits for "courtesy" repo-wide — it treats the
courtesy turn as an unparameterized sub-component of `chain` and `right left
through`), while The Caller's Box writes one as its own figure line 115 times in
the 24,107-dance corpus. Such a move is added only with a corpus census behind
each of its params; see the version history below.

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
  (extended at v24 with five mixer partner-series tokens, issue #732)
  (`_heyMeetTargetChoices`: `role1s`/`role2s`/`ones`/`twos`/`partners`/
  `neighbors`/`sameRoles`/`firstCorners`/`secondCorners`/`shadows`/
  `secondShadows`/`prevNeighbors`/`nextNeighbors`/`thirdNeighbors`/
  `fourthNeighbors`/`prevPartners`/`nextPartners`/`thirdPartners`/
  `fourthPartners`/`fifthPartners` + `unspecified`) — **pairs only** (single
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
    degrades to a custom figure.
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
    TCB never states the in-front role, so an imported TCB mad robin leaves
    `who` at the taxonomy default and is flagged as an **assumed subject**.
  - **Nothing is fabricated for existing data.** Every added param defaults to
    the `unspecified` sentinel (cf. `hey.pass2`/`hey.meetTarget`), which the
    renderer emits as the empty string — in the canonical render too. A figure
    that omits them is therefore **byte-identical** to its v19 canonical text
    (test-enforced), so `dance_figures.canonicalText` / `dance_fts` / dedupe are
    untouched and NO DB migration is implied; a figure that *does* state a
    direction is distinguishable from its mirror image in search and dedupe.
  - **Deliberately not modeled:** a `butterfly_whirl` rotation amount. TCB
    states one on 4/18 lines ("… counterclockwise 1 & 1/2"), but no source
    models it, so per prefer-custom those lines stay `custom` rather than have
    the amount silently dropped from a structured figure.
  - Conservative whole-line recognizers require BOTH stated facts; a bare "mad
    robin" / "butterfly whirl" (ContraDB's own phrasing) or any leftover token
    still degrades to a faithful custom figure.
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
  - **What is NOT modeled, and why.** The pass-list codes `C1`–`C3` are TCB's
    *square* corners ("the non-partner next to you… your opposite… the
    remaining person"), a different relationship from the ECD *first/second
    corners* that `ParamVocab.firstCorners`/`secondCorners` model — so they are
    left unmapped and such lines stay `custom` rather than being approximated
    onto a token that means something else. The same holds for a mixer's
    future partners (`P2`+), out-of-range neighbors/shadows, phantoms and trail
    buddies. See `docs/design/imports.md` for the recognizer rules and
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
    (`dance_repository.dart:1454`) filters on exactly `danceFigures.move` and
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
    Advanced-search facet (`facet_labels.dart`'s `figureParamChoices`, PR
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
  as custom figures instead — an accepted structure regression, because ContraDB
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
  large-print performance view, while the visible text stays terse.
- FTS indexing uses canonical rendered text + searchKeywords (incl. legacy
  terms like "gypsy" so searches by older users still find shoulder round).

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
    a balance flag), plus the `weave the line` → `zig_zag` recognizer alias.
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
    A figure that omits them therefore renders BYTE-IDENTICALLY to v19 —
    canonical/FTS/dedupe text is unchanged for all existing data, and a
    ContraDB import keeps asserting nothing about direction or target. The
    params ride the existing `figures_json` figure codec, so — distinct from
    CompendiumDatabase.schemaVersion — NO persisted-data migration is implied.
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
      `DanceRepository.danceIdsWithFigure` (`dance_repository.dart:1454`)
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
    ContraDB's `chainChange` (`figure.js:256-263`). It is consulted at six
    write/read sites so none can drift: the ContraDB and shared-recognizer
    `_chain` parsers, both `_selectMove` implementations and the `who`
    branch of `_applyNonBeatsParamChange` in `figure_list_editor.dart`, and
    the one-time backfill sweep below. It is NOT baked into `chain.hand`'s
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
    `params_json` (`database.dart:783-784`), so a chain imported before
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
    rendered. Canonical never applies this default-silencing: `turn` is
    omitted from canonical text only at the `unspecified` sentinel, exactly
    like `dir`'s existing canonical behaviour of always rendering even at its
    default.

    **Editor.** `figure_list_editor.dart` hides `turn` (and resets it to the
    `unspecified` sentinel via an explicit write, never `.remove()` — removal
    would fall back to the concrete default and render it) whenever `dir` is
    `in`/`out`/`up`/`down`, where a rotation sense is meaningless. It also
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

## Open questions (to resolve during implementation, with user input)

1. Exact positional definition of role1/role2 across formations (esp. Becket).
2. Whether TCB's richer hey notation (per-pass lists like `(WR;PL;MR;N2L~)`)
   maps losslessly onto ContraDB-style hey params — drives the import parser;
   worst case heys import as custom text.
3. Beat conventions: TCB uses 16-beat phrases with explicit per-line counts;
   ContraDB defaults 8. We store explicit beats per figure — imports keep
   source counts.
