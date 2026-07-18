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
progressionCapable: true
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

allemande · allemande orbit · arch & dive · balance · balance the ring ·
box circulate · box the gnat (alias: swat the flea) · butterfly whirl ·
California twirl · chain (role-parameterized, not "ladies chain") · circle ·
contra corners · cross trails · **custom** · do si do (alias: see saw) ·
dolphin hey · down the hall · up the hall · facing star · figure 8 ·
form long wave / ocean wave / long waves · gate · give & take ·
**shoulder round** (was gyre/gypsy; keyword-searchable under old names) ·
hey · long lines · mad robin · pass by · pass through · petronella ·
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
  `revolving_door`, `star_promenade`, `allemande_orbit`. All fit the existing
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
  `form_an_ocean_wave`. `hey` uses the approved structured model:
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
  `betweenHalfAndFull`). The dynamic `dancer%%N` meeting encodings remain out of
  scope. `length` is structured-only (not in the render template), so this is a
  validation/storage change only; canonical text is unaffected.
- **v13 (ocean-wave split, issue #290):** split the overloaded
  `form_an_ocean_wave` — which conflated the default short-wave case with
  "pass the ocean" — into `form_a_short_wave` (renders "form a wave", parallels
  `form_a_long_wave`) and `pass_the_ocean` (renders "pass the ocean"). Both
  inherit the legacy move's sourced params **minus `passThru`** (intrinsic to
  `pass_the_ocean`, absent from the short wave) and mirror its unencoded,
  param-dependent beats — no fabricated beat count. `form_an_ocean_wave` is
  **retained unchanged** (no alias, no data rewrite) so stored figures render
  byte-identically; hiding it from the authoring picker is an app-layer
  follow-up. Import adds conservative `pass_the_ocean` / `form_a_short_wave`
  recognizers; the ContraDB adapter's "form an ocean wave" mapping is unchanged.
  Purely additive: distinct from `schemaVersion` — no DB migration or derived
  rebuild.

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
- **`hey`** (pass pairs, shoulder, length, dir, four ricochet flags, beats) and
  the **ocean/long-wave family** — DONE (PR5 + v6): modeled with existing kinds
  (no new `ParamKind`). The full set of ContraDB named hey-length durations
  (`full`, `half`, `lessThanHalf`, `betweenHalfAndFull`) is now supported (v6).
  Only the dynamic `dancer%%N` meeting encodings remain out of scope.

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

## Open questions (to resolve during implementation, with user input)

1. Exact positional definition of role1/role2 across formations (esp. Becket).
2. Whether TCB's richer hey notation (per-pass lists like `(WR;PL;MR;N2L~)`)
   maps losslessly onto ContraDB-style hey params — drives the import parser;
   worst case heys import as custom text.
3. Beat conventions: TCB uses 16-beat phrases with explicit per-line counts;
   ContraDB defaults 8. We store explicit beats per figure — imports keep
   source counts.
