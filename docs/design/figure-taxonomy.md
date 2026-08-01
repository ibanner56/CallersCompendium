# Design: Figure taxonomy v1 (contra)

*Roadmap item 1.8 · v0.1 (2026-07-10). Seeded from ContraDB's libfigure
(AGPL-3.0, attribution retained) with terminology modernized to current
community usage (aligned with The Caller's Box, e.g. "shoulder round" not
"gypsy"/"gyre"). Canonical IDs are permanent; display names go through dialect.*

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
| dancerSet | everyone, larks*, robins*, ones, twos, firstCorners, secondCorners, partners, neighbors, sameRoles, shadows, nextNeighbors, prevNeighbors, … | *canonical role IDs are `role1`/`role2` — see below. Positional/relational tokens (all except `role1s`/`role2s`) are also **dialect-substitutable** via the dialect `dancers` map. |
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
  `revolving_door`, `star_promenade` (and originally the fused `allemande_orbit`,
  since retired — see v19). All fit the existing
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
  rather than spatial `direction`. Beat-shaping flags that ContraDB uses only to
  recompute beats (`give`, `balance`) are not render tokens.
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
  structured, not a render token (cf. PR3 enders).
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
  (`_heyMeetTargetChoices`: `role1s`/`role2s`/`ones`/`twos`/`partners`/
  `neighbors`/`sameRoles`/`firstCorners`/`secondCorners`/`shadows`/
  `secondShadows`/`prevNeighbors`/`nextNeighbors`/`thirdNeighbors`/
  `fourthNeighbors` + `unspecified`) — **pairs only** (single dancers,
  `everyone`, and `centers` are excluded, as ContraDB does). Our `length` already carries the meeting *count*
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
    `circle_left` move — "left" is the `circle.turn` default. Neither flag is
    surfaced by the verbose renderer yet (structural-only for now), matching
    the existing precedent set by `star.grip`.
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
    backwards. `dance_figures` projects three things out of a stored figure —
    the **move id**, `params_json` and `canonicalText` (see `tables.dart`) — and
    a rebuild is owed if **any** of them moves. A rename changes the move id by
    definition, so **a rename always owes both a migration and a rebuild**, even
    one that leaves `displayName` (and therefore canonical text) untouched:
    without the rebuild, `dance_figures.move` would keep an id the taxonomy no
    longer defines, and structural search / filter-by-move would silently go
    stale.

    (#296 also names `form_an_ocean_wave`; that reference is **stale** — the
    MoveDef was split at v13 and removed at v14.)
  - **`form_a_long_wave` is untouched** (it already carries a balance and means
    something different: ONE long wave in the centre formed by a subset), and
    **`form_rings` is explicitly out of scope** — only 38 TCB lines across 26
    wordings, and ContraDB has no ring-formation figure.
  - Import mapping, the annotation decoding, and what deliberately stays custom
    are documented in `docs/design/imports.md`; the corpus measurements are in
    `docs/research/callersbox.md`.


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

### Derived (computed-at-render) taxonomy values — file convention

Almost every taxonomy value is **stored data**: a named `ParamSpec` on a
`MoveDef`, authored by the user or supplied by an importer, and serialized with
the figure. A small minority are instead **derived** — computed at render time
from other params, *never* stored, free-typed, or fabricated. The first (and
currently only) example is a rotation-gate's ending facing, derived from
`(startFacing, direction, turn)` in
[`taxonomy/gate_facing.dart`](../../packages/compendium_core/lib/src/taxonomy/gate_facing.dart)
(issue #294).

Because a derived value is *logic carrying a guarantee*, not taxonomy data, it
does **not** belong inside the `MoveDef` list in `contra_taxonomy.dart`. The
convention is:

- **Each derived value lives in its own pure module**, named
  `<figure>_<property>.dart` (e.g. `gate_facing.dart`), exporting a pure,
  defensively-total function (never throws; returns `null` for any
  convention-dependent / ambiguous case so the renderer emits nothing rather
  than guessing).
- **Isolate any unratified assumption at the top** of that module as a single
  named constant with a comment, so revisiting it is a one-line change (see
  `gateStartFacing = 'in'`).
- **Keep the canonical line template-driven.** The derived clause is appended by
  the *display* renderer (`FigureRenderer`), so it never enters the canonical,
  byte-stable serialization — preserving the canonical/display split above.
- **Do not create a shared `derived_values.dart` grab-bag.** One derivation =
  one module = one reviewable guarantee + one test surface. Apply the rule of
  three: when a *second* derived value appears, group the (still separate) files
  under a `taxonomy/derived/` subdirectory rather than merging them.

Contrast: an *author-set* facing — e.g. a swing's end-facing (`endFacing`,
#543) — is stored data: it stays a plain `ParamSpec` in the taxonomy and needs
no derivation module. Like the derived clauses, its display wording is appended
by the renderer only when non-default (the default `in`/across renders as
before), so the canonical line stays byte-stable.

## Open questions (to resolve during implementation, with user input)

1. Exact positional definition of role1/role2 across formations (esp. Becket).
2. Whether TCB's richer hey notation (per-pass lists like `(WR;PL;MR;N2L~)`)
   maps losslessly onto ContraDB-style hey params — drives the import parser;
   worst case heys import as custom text.
3. Beat conventions: TCB uses 16-beat phrases with explicit per-line counts;
   ContraDB defaults 8. We store explicit beats per figure — imports keep
   source counts.
