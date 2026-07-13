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
| dancerSet | everyone, larks*, robins*, ones, twos, firstCorners, secondCorners, partners, neighbors, sameRoles, shadows, nextNeighbors, prevNeighbors, … | *canonical role IDs are `role1`/`role2` — see below |
| dancerPair | subset of dancerSet valid for the move | |
| handedness / shoulder | right, left | |
| spinDirection | clockwise, counterclockwise | |
| rotation | 0.25 … 2.5 in quarter steps | replaces ContraDB degrees (90–900) |
| fraction | 1/4, 1/2, 3/4, full, other | heys, poussettes |
| beats | 0–64 int | 0 allowed for formation labels |
| direction | along, across, rightDiagonal, leftDiagonal, in, out, up, down | |
| enum(...) | move-specific lists (grips, enders, prefixes…) | e.g. downTheHallEnder |
| text | free string | dialect-aware |
| flag | bool | e.g. withBalance |

### Roles
Canonical role IDs are **`role1` / `role2`** (position semantics: role1 =
left-of-partner facing down… defined precisely in implementation docs). All
display names — Larks/Robins, Gents/Ladies, Leads/Follows, Ladles/Gentlespoons
— are dialect, including the default. This is the lesson from both ContraDB
(hardcoded ladles/gentlespoons) and Caller's Companion (couldn't retrofit
gender-free Elements). Default dialect ships as Larks/Robins.

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
- **PR1 (simple moves)** — added `butterfly_whirl`, `arch_and_dive`,
  `california_twirl`, `stand_still`, `slide_along_set`, `mad_robin`,
  `revolving_door`, `star_promenade`, `allemande_orbit`. All fit the existing
  `ParamKind` set (no new vocabulary). ContraDB "no default" choosers get
  sensible community defaults (our `ParamSpec` requires one); rotations stored
  in full turns; `stand_still` omits `goodBeats` (ContraDB's "beats ≥ 1").
- PR2 dancer-interaction, PR3 choice-enum (+`centers`), PR4 places-family
  (+`ParamKind.places`), PR5 hey/wave family — remaining.

**2.4a data-entry progress:**
- _PR1 (simple moves, no new vocab):_ added `butterfly_whirl`, `arch_and_dive`,
  `california_twirl`, `stand_still`, `slide_along_set`, `mad_robin`,
  `revolving_door`, `star_promenade`, `allemande_orbit`. ContraDB params with
  "no default" (which force a chooser selection there) take sensible community
  defaults here, since `ParamSpec.defaultValue` is required. `stand_still` omits
  `goodBeats` because ContraDB's "beats ≥ 1" min-rule isn't expressible in the
  list-based `goodBeats` model.

**Confirmed divergences from ContraDB (already applied in the seed):**
- Canonical roles are `role1`/`role2`; ContraDB `gentlespoons`→`role1(s)`,
  `ladles`→`role2(s)`. All role display names (incl. Larks/Robins) are dialect.
- `shoulder_round` replaces gyre/gypsy; legacy names retained as `searchKeywords`.
- Rotation is stored in **full turns** (0.25–2.5, quarter steps), not degrees
  (90–900). 90°→0.25 … 540°→1.5 … 900°→2.5.

**Param-vocabulary extensions still needed for full coverage (need a decision):**
Several moves don't fit the current `ParamKind` set and are deferred until we
agree how to model them:
- **`places`** (distance travelled around a ring/star, ContraDB 1–10 "places"):
  used by circle, star, facing star, square through, box circulate. Distinct
  from in-place `rotation` — needs its own kind or an int param.
- **move-specific enums** already fit `ParamKind.choice`, but we should confirm
  the canonical value spellings: march facing, star grip, slice return/increment,
  gate direction, down-the-hall enders, zig-zag enders, hey length.
- **`half_or_full`** → maps onto our `fraction` type (0.5/1.0) — confirm.
- **`hey`** (10 params incl. four ricochet flags + hey-length/meeting encodings):
  the single biggest modeling decision; see open question 2 below.
- **ocean/long-wave family** (`form an ocean wave` has 7 params) and the
  auto-beat "change" behaviors ContraDB attaches to param edits (editor UX,
  likely out of scope for the pure model).

## Validation & rendering

- Each move may define `validBeats(params)` → ok / warning (never hard error).
  Implemented as `MoveDef.goodBeats` → `atypical_beats` warning.
- `renderTemplate` produces **canonical text**; dialect substitution then
  produces display text; both are pure functions in the core package →
  golden-tested. Screen readers get an expanded verbose rendering (a11y
  baseline requirement) — verbose rendering still TODO.
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
