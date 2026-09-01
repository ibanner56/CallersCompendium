# Changelog

All notable changes to the Compendium Core are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings are the `packages/compendium_core/pubspec.yaml` version at the
time of the release, written as a bare `major.minor.patch` with no `v` and no
prerelease suffix — the same convention `app/CHANGELOG.md` uses.

**This version is not pinned to the release tag, and drifts from the app's.**
The core is bumped only when it has unreleased changes, so a release that
touches only the app leaves it untouched, and one core version can span several
tags. See [Cutting a release](../../docs/dev/releasing.md#cutting-a-release).

Headings from `## [0.1.0-beta.9]` down are historical: they predate this
convention and are keyed to the release *tag* the change shipped with, not to a
core version. They are left that way deliberately — do not renumber them.

## [Unreleased]

### Changed

- Correct the seven backup-eligible settings classifications to `deviceLocal`
  rather than `deviceScoped`, matching their permitted local-backup route.
- **Schema 29 → 30** — remove redundant normalization collision snapshots;
  existing skip identities are retained while `recordNormalisationSkip` now
  accepts only the identifying table, column, and record triple.
- Add optional transitive related-dance markers, including schema 30 → 31
  persistence and archive compatibility.

## [0.2.0] - 2026-08-31

### Added

- Add Draft and Variation values to the persisted `DanceStatus` enum.

### Changed

- Normalize shareable text to Unicode NFC and remove unsafe controls at all
  repository write boundaries, with collision-safe existing-data backfill.

## [0.1.3] - 2026-08-26

### Added

- Add called/not-called filtering to Collection and Program dance pickers using
  the active caller and performed-history scope.

### Fixed

- Use Caller's Box bracket annotations as an otherwise unstated supported dancer
  subject, preserve them as notes when a subject is explicit, and fall back to
  custom for unmodelled leading subjects.
- Parse selected Caller's Box fall-back, facing, formation, and complementary
  long-wave clauses into existing figures or retained notes rather than making
  the complete source line custom.

## [0.1.2] - 2026-08-25

### Changed

- Integrate signed Published Collections into dance import and align collection,
  program, and settings data with their updated app workflows.

### Fixed

- Limit parameter-specific wording controls to supported moves, consolidate
  legacy circle wording, and retain the automatic single-file circle prefix.

## [0.1.1] - 2026-08-24

### Fixed

- Accept optional `{move}` and either `{shoulder}` or `{shoulder_clause}` in
  custom move-wording validation for hey templates.
- Preserve non-shareable custom-field definitions, values, and sharing flags in
  backups while continuing to omit them from shared exports.
- Preserve dance walkthrough text when importing and re-importing generic JSON
  and published collections.
- Omit unspecified gate subjects and attach comma-prefixed forward clauses to
  the final rendered gate slot.
- Restore tombstoned dances and programs before re-import/archive writes and
  apply later soft-delete timestamps during compensation or undo.
- Add parameter-specific wording branches for long-wave in/out combinations and
  ordinary versus single-file promenades and circles.
- Rename canonical taxonomy terms to `dosido` and `seesaw` while retaining
  spaced and hyphenated parsing and full-text search spellings.
- Reroute inverse-pair figures immediately after hand or shoulder edits so
  autocomplete text reflects the updated values.
- Remove unpaired UTF-16 surrogates from imported text while preserving valid
  surrogate pairs.

## [0.1.0-beta.9] - 2026-08-21

### Added

- Add `promenade.destination`.
- Add configurable program-matrix columns.
- Add the matrix-column settings editor.
- Add parameterized matrix columns.
- Parse directed promenade rotations.
- Add compound matrix columns.
- Add standalone turn moves.
- Support composite phrase structures.
- Add optional program-editor auto-commit.
- Import signed published collections.
- Add scoped Collection search.
- Add `along` to gate and swing facing vocabularies.
- Add per-dance figure wording.
- Add configurable move wording templates.

### Changed

- Make the dance editor reactive.
- Move core design comments into agent/documentation tooling.
- Upgrade Flutter and Dart package metadata.
- Revise promenade turns, circle wording, and destination gating.
- Refactor display rendering around slots.

### Fixed

- Deduplicate shared-bundle venues by provenance.
- Correct published-collection review findings.
- Preserve venue liveness during archive re-import.
- Deduplicate Unicode-equivalent imports.
- Reject non-finite custom-field numbers.

## [0.1.0-beta.8] - 2026-08-14

### Added

- Persist Collection and Program sorting, including “Last used”.
- Create dances from program-note slots.
- Log caught user-facing errors.
- Recognize additional ContraDB figures.
- Add the `chain.hand` parameter.

### Changed

- Make Collection data reactive.
- Notify watchers after migration raw writes.
- Correct fixture-validation and local-gate documentation.
- Make Program lists reactive.
- Make reference-data surfaces reactive.
- Watch venues per consumer.
- Default the matrix to exact beat-overlap detection.
- Repair renamed collision tests.
- Classify prefix-declared settings.
- Make dance details reactive.

### Fixed

- Disambiguate matrix allemande/chain roles and swing prefixes.

### Removed

- Remove `ProgramsRefreshScope`.
- Remove support for schemas v11–v19.

## [0.1.0-beta.7] - 2026-08-12

### Added

- Add custom-field sharing disclosure and shareability flags.
- Add configurable Collection tile fields.
- Add tag colours.
- Add `Dance.mixer`.
- Add mixer partner-series vocabulary.
- Gate mixer partner tokens in the figure editor.
- Add mixer display, search, export, and set-list support.
- Import mixer partner-series tokens.
- Add quadruplet formations.
- Add timestamps and soft deletion to all syncable entities.
- Add “Include figures?” export controls.

### Fixed

- Exempt TCB parsing from the fan-out note-swallow guard.
- Recurse into `meanwhile` for parse quality and reparse.
- Render single-dancer identities through the active dialect.
- Assign zero-beat figures to the ending phrase.
- Include blank-caller programs in calling history.
- Exclude hidden dances from Caller's Box search.
- Render pass-through shoulders.
- Re-tombstone resurrected choreographers on undo.
- Remap archive IDs correctly in merge mode.
- Preserve dropped TCB prose annotations.
- Notify Drift watchers after remaining raw writes.

- **Bare ContraDB box-circulate form now recognized (#752).** ContraDB
  sometimes writes the figure as the component cross/loop path — `larks cross
  while robins loop` — without the `box circulate` head phrase. Previously this
  fell through to custom and, with #591's `while` fan-out active, became a
  `meanwhile[custom, custom]` container carrying no structured information. A
  new pre-recognizer `_boxCirculateBare` detects the `<subject> cross while
  <subject> loop [left|right]` form and maps it to `box_circulate`, recovering
  `who` from the crossing subject and `hand` from a trailing `left`/`right`
  when present. Both dancer-set subjects must resolve to known sets — unrelated
  `while` lines still reach the fan-out unchanged.

- **Dancer-qualified balance-wave lines now fold into the preceding wave figure
  (#872).** TCB writes `Men balance long wave in center`; the scrubber
  canonicalises that to `role1s balance long wave in center`. The previous
  `_isBalanceWaveLine` predicate required the text to lead with `balance`, so
  dancer-prefixed lines were not recognised and the balance appeared twice —
  once in `form_a_long_wave` (taxonomy default) and once as a surviving
  `custom` figure. Dance 18878 A1 now imports as a single
  `form_a_long_wave{beats: 8}` with no trailing custom.
  - The dancer-prefix mismatch guard in `_foldTrailingBalanceIntoWave` now
    resolves the wave's **effective** `who` — explicit param first, then the
    taxonomy default — so a bare `form_a_long_wave` (no explicit `who`,
    taxonomy default `role2s`) correctly refuses a `role1s balance long wave`
    line rather than silently folding it.

- **`Then(before, after)` no longer matches the two concurrent sides of a
  `meanwhile` container as if one preceded the other (#748).** The self-join
  correlated on `a.idx < b.idx`, but the #590 flattener gives an `X while Y`
  container's sides consecutive `idx` values under the `{danceId, idx}` primary
  key, so `Then(X, Y)` — and symmetrically `Then(Y, X)` — matched a container in
  which neither side happens before the other. The concurrency signal was absent
  from the index: no `dance_figures` column told two consecutive top-level
  figures apart from two sides of one container. A derived `group_idx` column,
  shared by every row flattened from one top-level figure and monotonic across
  them (`idx` stays unique for the key), now backs the correlation:
  `_then` keys on `a.group_idx < b.group_idx`, so two sides of a container share
  one `group_idx` and neither direction matches, while a genuine sequence still
  does. Multi-side and nested containers follow — all sides of a container share
  one `group_idx`. Schema **v21 -> v22**: `addColumn(group_idx)` plus a deferred,
  crash-safe derived rebuild repopulates it from `figures_json` (mirroring the v2
  `section` precedent). This resolves the limitation `docs/design/search.md` had
  recorded and deferred to #594, which shipped and closed without addressing it.

- **Caller's Box `Square through <n> (<pass list>)` no longer drops its pass
  list (#799).** The `()`/`[]` strip is recognition-only, so a structured
  `square_through` never saw the parenthetical `(N2R;SL)` and fell to the
  taxonomy defaults for `who`/`who2`/`hand`/`balance` — fabricating dancers the
  source never named and, because `square_through` defaults `balance:true`,
  doubling the balance the Caller's Box writes as a *separate* preceding line.
  A `tcbFigureFrontEnd` pre-recognizer now decodes the pass list the way the
  `hey` and `grand right and left` decoders already do: odd 1-based passes fill
  `who`, even passes fill `who2` (each parity must be internally consistent),
  hands alternate by parity from the first pass, `places` comes from the pass
  count, and `balance:false` is emitted explicitly for import fidelity (the
  `_roryOMore` precedent). This is the whole class of pass-list square-throughs,
  not only *Square Through 2*. OWASP bounds on `n` (2..10) and the cell count.
  The pass-list codes this consumes are the line's structured payload and are
  distinct from the prose parenthetical qualifiers tracked in #744, which this
  does not touch. Caller's Box and ContraDB still disagree on the *first*
  dancer for this dance (`N2` = `nextNeighbors` vs. `neighbors`), so the two
  imports are not byte-identical even after this fix — only the fabrication and
  the doubled balance are removed.

### Changed

- Catalogue and classify persisted fields.
- Add fixture-validity tooling and repair drifted fixtures.
- Normalize test import ordering.
- Report orphaned fixture-invalid markers.
- Resolve fixture paths independently of the working directory.
- Adopt Drift schema verification and raise the support floor.
- Export programs as JSON while suppressing venue addresses.
- Fold balances into `square_through`.
- Add archive-import choreographer-preservation coverage.
- Mark repository `upsert` results as required.
- Establish reactive repository watch APIs.

- **Star grip and single-file flags are now canonical render tokens (taxonomy
  v27, #749 Gap B + #840).** `star.grip`, `promenade.singleFile`, and
  `circle.singleFile` are now emitted by `renderCanonical`, so they appear in
  `dance_fts` and are FTS-searchable. A one-shot derived rebuild fires on first
  open to backfill existing databases.

  `contraTaxonomyVersion` bumped 26 → 27. No SQL schema change.

  Render form changes:
  - `star.grip`: `"star right - hands across - 4 places"` /
    `"star left - wrist grip - 4 places"` (grip clause added to all render
    paths; `none` still emits no clause).
  - `promenade.singleFile`: `"single file promenade along"` / `"…across"` — `who`
    always dropped; `dir` always shown even at the `across` default (v27
    ruling).
  - `circle.singleFile`: `"single file circle clockwise N places"` (prefix form
    replaces the v26 suffix; `turn:'left'` = clockwise per contra convention).
  - Canonical form for circle: `"single file promenade clockwise N places
    (circle)"` — parenthetical keeps "circle" in the FTS index.

- **ContraDB importer captures `dir:'along'` for single-file promenade (#749
  Part A).** The bare direction token immediately after `promenade` in a
  single-file line is now consumed as `params['dir']`. Previously it was left
  in the note.

- **TCB "Single file promenade clockwise/counterclockwise" now imports as
  circle (#749 Part E / #840).** Added `_singleFileCircleRecognizer` to
  `tcbFigureFrontEnd.preRecognizers`. Clockwise → `turn:'left'`;
  counterclockwise → `turn:'right'`. Recognizer is placed before
  `_sideRunAnnotation` so the `;`-run decoder does not claim it first.

- **General `;`-run consume (#843, Parts B and C, NO taxonomy change).** New
  pre-recognizer `_sideRunAnnotation` in `callersbox_figure_dialect.dart`,
  placed LAST in `tcbFigureFrontEnd.preRecognizers` so the four existing
  bespoke decoders (`_hey`, `grandRightAndLeftFromPassList`,
  `_squareThroughPassList`, the balance-a-wave decoder) keep every line they
  already claim.

  Unlike those four it lowers nothing onto a bespoke structure: it reads the
  same `<people-code><R|L>` notation and fills whatever slots the move it landed
  on declares. **The slot lookup is keyed on `ParamKind`, not on the param
  name.** #870 established the query-the-taxonomy pattern but keyed on the
  literal name `hand`; of the twenty moves with a side slot, seven call it
  `shoulder` and two call it `centerHand`, so a name check silently misses nine.

  **Values are written even when they equal the taxonomy default** (owner
  ruling). Byte-identical at both identity layers — `renderCanonical` and
  `figureCanonicalKey` both build from `effectiveParams`, which fills defaults —
  so the 2,388 same-value cases raise no #686 "Variation?" prompt. The 116
  inverse-value cases DO change the key, and should: the stored choreography
  contradicted its source.

  Dancer identity (Part C) fills `who`/`who2` where the move declares them, odd
  1-based positions naming `who` and even `who2`. `pass_through` declares no
  `who`, so its dancer code is dropped rather than forced into a slot the move
  does not have — writing it unconditionally makes `validateFigure` reject the
  figure and sends 2,136 corpus lines to the custom fallback.

  **A cell is a PASS**, so a move modelling fewer passes than the run states
  declines. In particular `square_through`'s cell count must equal `places`:
  #799 deliberately refused to guess the unstated third pass of `Square through
  3 (N2R;SL)`, and this decoder must not undo that ruling by the side door. A
  run contradicting a prose-stated side falls THROUGH to today's reading (prose
  wins, annotation dropped) rather than declining to custom — forcing custom
  would regress a line that structures today.

  Corpus (pristine `f3030cbc`): 2,504 dropped runs consumed — `pass_through`
  2,136, `square_through` 159, `cross_trails` 98, `pass_through + turn_alone`
  88, plus a short tail. Zero move-id deltas, zero beat deltas, zero
  custom/structured flips.

- **`O` documented in `tcbPassPeople`'s deliberate omissions (#843).** The most
  common unmapped prefix in the corpus (72 cells, ahead of `Ph` 21 and `SRN`
  17) was absent from both the map and its documented omissions list, which read
  as an oversight rather than a decision. No `opposites` token is added —
  `O` is primarily meaningful for non-duple formations (squares), which are
  not a current priority; behaviour was already correct (an unmapped code
  declines the run). Ruling by @ibanner56, confirmed 2026-08-11: non-duple
  formations are not immediately pressing.

- **`contraTaxonomyVersion` 26 (#843, Part A).** `star_promenade` LOSES its
  `hand` param and `{hand}` leaves its `renderTemplate` — the first param
  removal in this taxonomy (v19 retired a whole move; v21 renamed one).

  Owner ruling (2026-08-06): `who` names the dancer you PICK UP on the side,
  which is TCB's reading. The `hand` described a DIFFERENT pair — the two
  dancers in the centre — while rendering beside the subject, so "Neighbor star
  promenade right ½" implied a right-hand connection with the neighbour. TCB's
  flutterwheel decomposition shows both facts coexisting in one figure
  (`(4) Women allemande right 1/2` + `(4) Neighbor star promenade 1/2 (WR)`:
  `who` is `neighbors`, `(WR)` names the women), which is why they cannot share
  a slot.

  **Canonical-key change:** removing a declared param changes
  `figureCanonicalKey` for EVERY `star_promenade` figure, not only those that
  stored a `hand` — `effectiveParams` used to fill the `right` default for the
  rest. The derived rebuild is therefore OWED unconditionally — unlike the
  schema-v18/v19 precedents, which schedule one only when a figure actually
  changed — and is discharged by `_stripStarPromenadeHandIfNeeded` (marker
  `starPromenadeHandRemovalDoneKey`, written after success), mirroring #870.
  Owed is not the same as always-called: the pass skips its own rebuild when an
  earlier sweep already rebuilt during the same `ensureMigrated`, since that
  rebuild already paid the debt.
  **No DB schema bump:** nothing structural changes, and a leftover stored
  `hand` is already inert because `effectiveParams` iterates the MoveDef's
  declared params only. The strip is hygiene — it stops dead data resurrecting
  if a later taxonomy re-declares `hand` here with another meaning.

  Stored explicit `hand` values are DROPPED rather than converted into the new
  centre note: `figures_json` does not record which adapter wrote a figure, and
  the value means the real centre hand on a ContraDB-imported figure but a
  default on a TCB one. (Decided by the implementing agent, not the owner.)

- **Doc correction in the v25 block.** It claimed "the taxonomy version bump
  triggers a derived rebuild". It does not — `Taxonomy.version` is stored on the
  object and is never read by any runtime code, and #870's rebuild in fact came
  from its own settings-marker pass. Believing the claim is how a canonical-key
  change ships with a stale FTS index, so the mechanism is now named explicitly.

- **`FigureFrontEnd` gains an optional `declineToCustom` veto.** A front-end
  cannot decline a move by deleting its own recognizer: the shared recognizers
  in `figure_parser.dart` are source-neutral and will claim the line anyway.
  ContraDB's `star promenade` needed a real veto, since its subject means the
  centre role there and the pick-up relationship everywhere else. Runs before
  every recognizer, inside the existing try, so a throwing predicate degrades to
  custom like anything else.

- **TCB star-promenade centre annotation (#843).** New pre-recognizer
  `_starPromenadeAnnotation` in `callersbox_figure_dialect.dart`, on the
  existing `_annotatedMatch` seam (so it inherits the OWASP annotation caps and
  adds no new bound). `(WR)` becomes the note `role2s by the right in the
  center` — canonical role tokens, so it renders under the active dialect
  instead of freezing `W`. `who` is never written or overwritten. Anything that
  is not exactly one mapped `<people-code><R|L>` cell (multi-cell run, unmapped
  prefix, no `R`/`L` tail) is preserved verbatim rather than approximated,
  mirroring `_gateAnnotation`'s treatment of `(men stay put)`.

  Corpus (pristine `c9a0185f`, 24,107 files / 20,516 parseable / 11,499
  `Permission: full`): 626 raw lines import as `star_promenade`, all 626 carry
  an annotation, 625 are exactly one mapped cell (`m` 358, `w` 265, `n`/`n1` 2)
  and 1 is an unmapped `c` prefix. ZERO carry a prose hand, so the visible
  change is the removal of a DEFAULTED "right" that rendered on every one.

- **ContraDB star promenades decline to custom (#843).** Both producing paths
  are closed: the `'star promenade'` `_MoveMap` entry in
  `contradb_adapter.dart` is removed, and `contraDbHtmlFigureFrontEnd` carries
  the `declineToCustom` veto (its own recognizer is deleted, which alone was not
  enough). A deliberate, owner-accepted structure regression; the custom
  fallback keeps ContraDB's wording (scrubbed — role terms are canonicalized on
  every custom figure, so it is not byte-verbatim). **The count of affected ContraDB
  dances is NOT measured** — no ContraDB corpus or dump exists locally or is
  documented in `docs/research/contradb.md`.

- **`contraTaxonomyVersion` 25 (#870).** Three changes:
  - `balance` gains a `hand` param (default `unspecified`, choices
    `_handOrUnspecified`). Precedent: `form_long_waves.hand` (v21).
    **Canonical-key change:** every `balance` figure's `figureCanonicalKey`
    gains `hand=unspecified` — two different notions of "canonical" are in play
    (the renderer's canonical text vs. `figureCanonicalKey`'s dedupe/FTS key;
    `ParamVocab.unspecified` renders as empty but is a non-null STRING that the
    key includes). A derived rebuild is triggered by
    `inversePairNormalisationDoneKey`.
  - `MoveAlias` gains an optional `inversePairId` field. Two pairs declared:
    `swat_the_flea` ⇄ `box_the_gnat` (hand), `see_saw` ⇄ `do_si_do`
    (shoulder). `meltdown_swing` is not part of a pair (`prefix` is not a
    two-valued axis).
  - `Taxonomy.resolvedMoveId(figure)` re-routes a figure whose effective param
    contradicts its alias pin to the correct half of the pair. Called at write
    time (the single convergence point: `DanceRepository._upsert`) rather than
    on every read — `effectiveParams` (hot path) is untouched.
  - One-time normalisation of existing incoherent `figures_json` entries via
    `_normaliseInversePairMoveIdsIfNeeded` (rides the same startup path as
    `_recomputeSectionLabelsIfNeeded`). **Fresh install:** no incoherent figures
    exist; the scan finds nothing and writes the marker immediately.

- **TCB balance hand annotation extraction (#870).** New pre-recognizer
  `_balanceHandAnnotation` in `callersbox_figure_dialect.dart` extracts
  `(RH)` → `right`, `(LH)` → `left` from balance lines before
  `_stripAnnotations` drops them. The parenthetical is consumed into the
  `hand` param, not preserved as a note.

- **Balance fold hand threading (#870).** `_foldBalanceIntoMove` threads
  `balance.params['hand']` into the merged figure when the balance states a
  hand and the move accepts one. The convergence-point normalisation then
  re-routes the move id if the hand contradicts the alias pin.

### Removed

- Remove unused raw payload and snapshot storage.

## [0.1.0-beta.6] - 2026-08-01

### Changed

- Scope calling history to the default caller.
- Index `program_slots.dance_id`.
- Canonicalize hand-typed prose through the dialect chokepoint.
- Correct the v21 byte-stability documentation.
- Correct the rename/rebuild documentation.
- Bound courtesy-turn facing lookup at the search operation.
- Update `meanwhile` test fixtures.
- Restore verbatim storage of hand-typed prose, reverting the earlier
  canonicalization.

- **The sentinel workaround params now carry their natural `ParamKind`s
  (#739). Type information only — no behaviour change, no
  `contraTaxonomyVersion` bump.** `form_long_waves.hand` was declared
  `ParamKind.choice` and is now `ParamKind.handedness`;
  `mad_robin.direction` and `butterfly_whirl.direction` were `choice` and are
  now `ParamKind.spinDirection`. Each keeps its existing `choices` list, which
  already held the fixed vocabulary plus the `unspecified` sentinel. The
  `choice` declarations existed for one reason only: the typed dropdown kinds
  (`handedness`, `shoulder`, `spinDirection`, `fraction`, `direction`) used to
  render and validate from a *hardcoded* vocabulary that ignored
  `spec.choices`, so a sentinel declared on one of them was offered nowhere and
  rejected by the validator. All three consumers of the kind + `choices`
  contract now read `spec.choices ?? <fixed vocabulary>` — the figure param
  editor and `ParamSpec.validate` (#726), and the Advanced-search facet's
  `figureParamChoices` (#746) — so the workaround buys nothing and cost the
  taxonomy its type information.
  - **Nothing a user can see changes.** Verified by dumping every observable
    output for the whole taxonomy before and after — canonical text, display
    and verbose renders under every preset dialect, `renderSummary`,
    `validateFigure`, `effectiveParams`, snippet signatures and their
    descriptions, `ParamSpec.validate` over a fixed probe set, and
    `figureParamChoices` for every param of every move — and diffing:
    byte-identical (93,479 lines, matching SHA-256). Canonical text is the
    dedupe/FTS key, so this is the invariant that mattered.
  - **No `contraTaxonomyVersion` bump.** The constant is not serialized
    anywhere (it feeds only `Taxonomy.version`), no `MoveDef`, param, default
    or vocabulary changed, and no stored figure is rewritten — the same
    reasoning that applied to the `progressionCapable` removal (#551).
  - **`gate.direction` deliberately stays a `ParamKind.choice`**, and its
    comment now says so explicitly. Its domain includes `mirror` — the
    two-couple gate — which `ParamKind.spinDirection` (`clockwise`/
    `counterclockwise` only) cannot express, so it is not an instance of this
    workaround and converting it would silently drop `mirror`.
  - **`ParamVocab.unspecified`'s doc comment now states the rule instead of
    listing the params.** It enumerated which params opt into the sentinel and
    had already drifted (it omitted `form_long_waves.hand`/`whom` and most of
    the `gate.*` family). It now says what is actually true — a param admits
    the sentinel iff it names it in `ParamSpec.choices` and its kind's
    validator consults `choices`, which explicitly includes the typed kinds —
    and points at `sentinel_choices_test.dart` as the mechanically-enforced
    source of truth, so it cannot drift again.
  - **New guards.** `sentinel_choices_test.dart` now fails any
    `ParamKind.choice` whose domain, minus the sentinel, is exactly one of the
    fixed vocabularies (the workaround's precise signature, and one that does
    not flag `gate.direction`'s superset domain). `facet_param_choices_test.dart`
    gains the missing direction: the search facet must offer a param's declared
    domain *verbatim*, since the pre-existing sweep only caught the facet
    offering too much and would have stayed green while `unspecified` silently
    vanished from the search dropdown.

- **BREAKING (data): `form_a_short_wave` is renamed `form_short_waves` (#295).**
  The move is the whole set's short waves, and every Caller's Box wording is
  "wave of four" / "short waves", so its display label is now **"form short
  waves"** (was "form a wave"). Because stored figures carry the old move id
  this ships **`CompendiumDatabase` schema v19**, which rewrites `move` in every
  `dances.figures_json` blob — including sides nested inside a `meanwhile`
  container — and schedules a derived rebuild, but only when a figure actually
  changed. Per-row and per-figure parse-never-throw: an unmappable or malformed
  entry is left byte-identical and rides the non-destructive unknown-move path
  (#358). The pre-rename label stays searchable as a `searchKeyword`. Callers
  referencing the id in code must update it; there is no alias.

- **The fused `allemande_orbit` move is retired in favour of
  `meanwhile[allemande, orbit]` (#295).** With `orbit` now recognized
  standalone, the combined "X allemande while Y orbits" figure is modeled as a
  `meanwhile` container: the CallersBox `||` fan-out and the ContraDB `while`
  fan-out both produce it automatically, and the ContraDB combined-line
  recognizer plus the ContraDB structured-import shorthand build it directly
  (capturing the source's explicit orbit direction and orbiting pair). The
  `allemande_orbit` MoveDef and its dialect renderer are removed. **Schema
  migration v17 → v18:** stored `allemande_orbit` figures in `figures_json` are
  rewritten into `meanwhile[allemande{who, hand, turn=old inner},
  orbit{who=invert(who), turn=direction derived from hand, amount=old outer}]`,
  carrying the fused figure's beats as the shared container total. The rewrite
  is per-row/per-figure parse-never-throw — a figure with a wildcard hand or a
  non-invertible `who` is left byte-identical (falling through to the
  unknown-move path) rather than fabricated — and schedules a derived-index
  rebuild only when a figure actually changed.

- **A CallersBox annotation note no longer displaces a recognizer's own note
  (#729's collision, as it applies to the new `walk forward` anchor).**
  `_withAnnotationNote` combined the two with `??`, which was correct while only
  `gate` and `courtesy_turn` (neither of which emits a note) used it. It now
  JOINS them — recognizer note first, `'; '` separator, the joined string
  truncated on a rune boundary to the existing `_maxAnnotationNote` cap — so
  `Walk forward to N2 (women going on slight right diagonal, …)` keeps both its
  `to n2` destination and the parenthetical. No existing figure changes.

- **The two `gate` moves are now ONE figure (`contraTaxonomyVersion` 22,
  `CompendiumDatabase` schema 20).** `gate` (ContraDB) and `rotation_gate`
  (The Caller's Box, taxonomy v15) both rendered the display name "gate" and
  appeared as two identical rows in the move picker. The merged `gate` carries a
  direction, a duration **and** an ending facing; `rotation_gate` is removed and
  stored figures of both are rewritten by the schema-v20 migration (per-row and
  per-figure parse-never-throw, recursing into `meanwhile` containers, beat
  totals preserved exactly). Chains after the schema-v19 wave-move rename;
  neither step adds a column or table.
  - **Two source misreadings corrected**, verified against `libfigure`
    (github.com/contradb/contra @ master). `figure.js:841` renders a gate as
    `words(ssubject, smove, sobject, "to face", sgate_face)` over
    `{up: "up the set", …}` (`param.js:711`) — ContraDB's `face` is the
    **ending facing**, not "which way `who` orbits `whom`" as v15/v16 recorded,
    so the two sources were never in conflict. And `figure.js:844`
    ("*'ones gate twos' means: ones, extend a hand to twos - twos walk forward,
    ones back up*") shows `who` **backs up** and `whom` **walks forward**.
  - **TCB's subject maps to a new `pair` slot, never to `who`.** It names the
    pairing you gate *with*, a third axis from ContraDB's "which side backs up"
    (whose domain, `chooser.js:114`, cannot even hold `neighbors`/`partners`).
    Reusing `who` would have silently reinterpreted every TCB-imported gate.
    Same shape as the `mad_robin.whom` split at v20.
  - **`goodBeats` widens to `[2, 3, 4, 6, 8]`** — the counts attested across the
    186 gate lines in the 24,107-dance TCB corpus. The three 3-beat lines were
    verified rather than assumed: all are a 6-beat `Modified right and left
    through` compound split evenly into 3 + 3, which our own importer emits as
    children, so excluding `3` would warn on real imported data.
  - Every param defaults to the `unspecified` sentinel, so each source asserts
    only what it states. `turn` is the first `ParamKind.rotation` to opt into
    that sentinel (`ParamSpec.validate` now accepts it when a rotation spec
    lists it in `choices`), because ContraDB's gate has no amount param at all.

### Removed

- Remove the progression-capable editor hint.

- **`gateEndFacing` (the "derived taxonomy value" exemplar) is WITHDRAWN.** It
  derived a gate's ending facing from a nominal `in` start orientation, so every
  half-turn gate rendered "to face out of the set" — including straight after a
  down-the-hall, where the answer is "up". Passing the real start facing would
  not have fixed it: the rule is only ever *relative*, and promoting it to an
  absolute cardinal needs the orientation the dancers arrive in, i.e.
  choreography simulation. The facing is stored data now (`gate.face`).
  `taxonomy/gate_facing.dart` keeps only the shared `gateFacings` /
  `gateDirections` vocabulary, and the "Derived (computed-at-render) taxonomy
  values" section of `docs/design/figure-taxonomy.md` records the withdrawal.

### Fixed

- Recognize ContraDB `balance & <move>` prefixes.
- Parse Caller's Companion beat prefixes robustly.
- Extend ContraDB star, box-the-gnat, pass-through, and chain recognition.
- Fold trailing wave balances into pass-the-ocean.
- Bound and sanitize Phrase-table ingestion.
- Preserve program provenance in archives.
- Sanitize imported program text.
- Escape SQL `LIKE` metacharacters.
- Make guarded deletes atomic.
- Read archives transactionally.
- Chunk large repository `isIn` queries.
- Decode custom-field choices tolerantly and avoid duplicate choreographer
  loads.
- Correct low-severity equality, plurality, cryptography-comment, and CI
  issues.
- Preserve unstructured semicolon clauses as notes.

- **The rotation param editor represents the `unspecified` sentinel instead of
  coercing it to `1.0`.** `FigureParamEditor`'s `ParamKind.rotation` branch fell
  back to `1.0` for any non-numeric value, so `gate.turn`'s sentinel displayed as
  "1 turn" — a value no source stated — and the first stepper nudge would have
  promoted that fabrication into stored data. A rotation spec that lists
  `ParamVocab.unspecified` in `choices` now renders an explicit unset state,
  disables decrement while unset, adopts the domain minimum on the first
  increment (an unambiguous user action rather than a seeded "typical" value),
  and offers a clear affordance back to unspecified. Rotation specs WITHOUT the
  sentinel keep the numeric fallback unchanged.

- **Caller's Box gate annotations are no longer silently dropped.** 82 of the
  corpus's 186 gate lines state which side moves — `(ones forward)`,
  `(men stay put)`, `(women are posts)` — and a *structured* gate discarded it
  (the `()`/`[]` strip is recognition-only, so only the custom fallback kept
  it). A `tcbFigureFrontEnd` pre-recognizer now reads them and splits by whether
  the stated verb matches a slot's meaning: `"<dancers> forward"` naming a set
  we model (60 lines) maps onto `whom`, which means precisely "walks forward";
  **stationary** phrasings (`(men stay put)`, `(women are posts)`) fit neither
  `whom` nor `who` (which backs up — also moving) and are never structured; and
  anything else is preserved verbatim as the note. OWASP bounds on the
  annotation count, per-annotation capture length and joined note length.
  New `resolveDancerSetPhrase` in `figure_parser.dart` resolves a dancer phrase
  only when it consumes the whole phrase, so a partly-understood fragment
  resolves to `null` rather than to its first dancer word.

- **Caller's Box `chain`/`promenade`/`right_left_through` no longer silently
  drop a parenthetical qualifier — including one that NEGATES the
  choreography (#729).** `"Ladies chain to partner (optional double courtesy
  turn)"` and `"Partner promenade across (without courtesy turn)"` used to
  structure while losing the annotation entirely (`_stripAnnotations` is
  recognition-only), so the negating form left the imported figure asserting
  the opposite of what the source said. Three new `tcbFigureFrontEnd`
  pre-recognizers (mirroring `gate`/`courtesy_turn`/`walk forward`) now
  preserve every qualifier verbatim as the figure's note, for BOTH additive
  and negating wordings — a deliberate, owner-ruled choice: no new taxonomy
  flag models "a courtesy turn did or did not happen" on these moves, so the
  structured figure still asserts the un-negated choreography while the
  contradicting words live in the (human-readable, not machine-checked) note.
  `chain` and `right_left_through` already emit their own recognizer note
  (`to <dancer>` / `same-role`); the note-combine fix that keeps that note
  from being displaced (see "Changed", above) is what makes these two safe.
  Measured over the `Permission: full` corpus (117,981 figure lines / 12,001
  dances): **0 move IDs, 0 beat totals and 0 custom/structured flips
  change**; 1,061 figures gain or extend a note (`right_left_through` 594,
  `chain` 416, `promenade` 51).

- **A figure `note` leaked canonical role tokens (`role1s`/`role2s`) into
  plain-text export instead of the reader's dialect terms (#715).**
  `danceToPlainText` now routes the note through `FigureRenderer.renderFreeText`,
  mirroring how `callingNotes`/`walkthrough` are already rendered. Audited
  every other display/export path (dance detail, PDF export, perform mode) —
  each already called `renderFreeText`, so this was the only raw emission.
  `walkthroughOverride` (the per-figure walkthrough snippet override) was also
  checked and is editor-only; it is never emitted by any export/display path,
  so it stays out of scope.

- **A TCB compound parent with a `(START-END)` beat span was not recognised as a
  compound, corrupting section beats (#295).** `_beatsPrefix` gained span
  support in #555, but `_compoundParent` did not, so a block like
  `(7-12) [Top two couples] Neighbor flutterwheel:` fell through to the ordinary
  per-line path: the parent became its own figure **and** its indented children
  were emitted alongside it, so the block contributed parent + children beats
  (6 + 6 = 12 instead of 6) and every later section label drifted. The parent
  and child patterns now accept a span with the same inclusive
  `END - START + 1` rule the per-line beats prefix uses; a backwards span
  (`(12-7)`) yields 0 beats and safely declines the collapse. Covered by its own
  regression group.

- **Silent duplicate dances on program import (#685).** Every author-name
  field (a choreographer string, a Caller's Box `Authors[]` element, a
  Caller's Companion "by" line, `Author1`/`Author2`) now routes through one
  shared, ReDoS-safe `splitAuthorNames()` tokenizer instead of each adapter
  splitting (or not splitting) multi-author strings differently. This makes
  dedupe's author-overlap signal consistent across sources, and
  `DedupeIndex.fuzzyMatches` now *guarantees* an exact-normalized-title match
  with an overlapping tokenized author set is surfaced as a confident
  candidate (`DedupeCandidate.confident` / `DedupeVerdict.hasConfidentMatch`)
  regardless of score-threshold tuning — such a pair can no longer silently
  resolve to `isNew`.

### Added

- Import Caller's Companion Phrase-table choreography.
- Flag repeated figure/phrase combinations in adjacent dances.
- Mark already-imported ContraDB programs.
- Add partial-hey meeting targets.
- Seed shorthands from Caller's Companion call buttons.
- Recognize ContraDB single-file promenade/circle and take-only give-and-take.
- Show formations in the program matrix.
- Create venues from `.USR` set locations.
- Import `.USR` related-dance links.
- Add figure-level variation diffs to import deduplication.

- **The Caller's Box `walk forward` lines now map onto existing moves (#733) —
  NO new `MoveDef`, no `contraTaxonomyVersion` bump, no schema migration.**
  `walk forward` appears on **879** figure lines of the `Permission: full`
  corpus (11,499 dances); it is three families, none of which needs a move:
  - **Absorbed into `form_a_long_wave` (142 lines).** `[<dancer>] walk forward;
    form long wave in center` emits ONLY the wave figure — the move's `in`
    defaults to `true` and its rendered line already reads "*&lt;who&gt; dance in
    to a long wave in the center*", so a separate travel figure would state the
    inbound travel twice. The walk clause's dancer is **transferred** onto the
    wave's `who` and `assumedSubject` is cleared: the role is stated on the WALK
    clause and never on the wave clause, while `form_a_long_wave.who` defaults
    to `role2s`, so absorbing without the transfer would have rendered all 66
    `Men walk forward …` lines as women's figures.
  - **`pass_through()` + `form_short_waves` (127 lines).** `walk forward; form
    wave of four with <dancer>` walks into a wave with the dancer you are not
    currently facing, which is a pass through; the wave clause already parsed on
    its own.
  - **`pass_through()` with the destination as a note (181 lines).**
    `walk forward to <dancer>` — the `to <dancer>` names the DESTINATION you
    arrive at after passing your current neighbour (the standard contra
    progression), not a dancer you pass. `pass_through` has no destination
    param, so the destination rides as the figure's note (`to n2`), the shape
    `chain` already uses for its `to <dancer>` target; that keeps `to n0` /
    `to n1` / `to shadow` distinguishable from the ordinary progression target.
  - **`dir` and `shoulder` are never written.** Both are `pass_through`'s own
    taxonomy defaults; writing them would assert a direction and a shoulder the
    source did not state. Verified corpus-wide: the count of pass-throughs
    carrying a `dir` is unchanged (2,201) and none carries a `shoulder`.
  - **Prefer-custom everywhere else.** A bare `walk forward`, any travel
    qualifier the mapping cannot carry (`one step`, `slowly (step; step)`,
    `until right shoulders are adjacent`, `(out of the set)`), a non-dancer or
    qualified destination (`to center`, `to next star`, `to shadow S1`), a
    stated subject on either pass-through reading (`pass_through` has no `who`),
    and **every diagonal walk-forward line** (`form_a_long_wave` has no `dir` at
    all; `form_short_waves`'s `dir` describes the wave's orientation, not the
    direction of travel; `(optional spin)` has no slot) stay `custom`. 55 lines
    carry a diagonal on the walk clause; 29 of them would structure if it were
    flattened away, which is the measured cost of declining.
  - **Measured over the whole mirror**, `Permission: full`, mixers INCLUDED
    (11,499 figure-bearing dances — the other 9,017 parseable records are
    metadata-only stubs with no figures): custom figures 20,452 → **19,996**
    (−456), structured share 80.34% → **80.79%** (+0.45pp), **451**
    `walk forward` lines newly structuring end-to-end (0 → 451), and
    **per-dance beat totals byte-identical for all 11,499 dances**. Measured
    against `22d5664b` (i.e. on top of #734); that share is not comparable as
    an absolute to #734's own non-mixer 80.96%/82.57% series, though the
    deltas are. `atypical_beats` warnings rise by 340, almost all a 4-beat
    `pass_through` (`goodBeats: [2]`) — a leisurely pass through is a warning,
    never an error, and no beats param is fabricated to suppress it.
  - **Composes with #734.** One line structures only because both changes are
    present (dance 8166 B1, `… Pass through across (NR); face partner; walk
    forward to partner`): #734 note-ifies the middle facing clause, #733
    structures the trailing walk clause, and neither alone gets the line.
    #734's "a LEADING clause never note-ifies" rule is untouched — this change
    removes `Walk forward; form long wave in center` from the set where the
    leading clause FAILS (it is absorbed instead), rather than weakening the
    rule; the two tests pinning it now use `Women walk forward; form wave of
    four with N2`, which still fails at the leading clause because
    `pass_through` has no `who` slot.

- **New `courtesy_turn` move (`contraTaxonomyVersion` 23; `CompendiumDatabase`
  schema stays **20** — purely additive, no migration).** The Caller's Box
  writes a standalone courtesy turn on **115** of its 24,107-dance corpus's
  figure lines and, until now, every one of them — 228 lines mentioning one in
  total — fell to `custom`.
  - **Entirely TCB-sourced.** ContraDB models this figure **nowhere**: a
    repository-wide code search of `contradb/contra @ master` for "courtesy"
    returns zero hits. Its `chain` carries exactly four params
    (`subject_role_ladles`, `by_right_hand`, `set_direction_across`, `beats_8`)
    and its `right left through` exactly two; neither has a courtesy-turn slot,
    flag or ending facing. ContraDB treats the courtesy turn as an
    unparameterized sub-component of those figures — which is precisely why a
    TCB line writing one as its OWN figure line had no home.
  - **Four slots, each backed by a corpus census.** `who` (stated on every
    line — partner x53, neighbor x39, N2 neighbor x13); `whom` (**no source
    states it** — there is no two-dancer `X courtesy turn Y` form anywhere in
    the corpus, so it is authoring-only and never filled on import); `direction`
    (10 lines state one, all `clockwise`); `endFacing` (13 lines).
  - **`endFacing` is a DANCER, not a facing.** Despite sharing a name with
    `swing.endFacing`, it does **not** hold the four set-relative cardinals.
    Every attested value is a neighbor relationship — `, face N2` x8,
    `, face N3` x4, `, face N0` x1 — mapped through `tcbPassPeople`. The corpus
    does write cardinal facings on courtesy-turn lines, but always after a `;`,
    where the existing all-or-nothing compound rule keeps the line whole-custom
    before any recognizer sees it.
  - **`direction` deliberately carries no `unspecified` sentinel.**
    `ParamKind.spinDirection` is rendered by the app's param editor from a
    hardcoded vocabulary that ignores `spec.choices` (issue #726), and the
    editor's dropdown reconciliation would push a substitute value back into the
    draft — so a sentinel there would silently rewrite "unstated" into
    "clockwise" on open. A courtesy turn wheels clockwise by construction, so
    the real default is honest and no sentinel is needed.
  - **`goodBeats: [2, 3, 4, 6]`** — the counts attested across the 115 claimable
    lines (4 x97, 2 x8, 3 x6, 6 x4). The `5` and `8` a naive grep finds belong
    to lines that can never structure as this move. The marginal values were
    verified in context rather than assumed, per the v22 precedent.
  - **Rendering is split canonical/display.** Canonical (dedupe/FTS) keeps the
    flat `'{who} {move} {whom} {direction} {endFacing}'`; the conditional
    wording — `{who} courtesy turn {whom, when present} {direction, when not
    clockwise} {"to face" + endFacing, when set}` — lives on the display path,
    as the merged `gate`'s "to face …" clause does.
- **The Caller's Box recognizer for courtesy turns**, reading
  `[<dancer>] courtesy turn [<dancer>] [clockwise|counterclockwise]
  [face <dancer>]` under the whole-line contract, plus a front-end
  pre-recognizer that preserves a TCB annotation (`(in center)`, `(continued)`,
  `[Ones and threes]`) verbatim as the figure's **note** — so a structured match
  loses nothing the `custom` fallback kept. That single contract is also what
  keeps every unmodelable wording honest, with no exclusion logic written: a
  **chain** (or right-and-left-through / promenade) that also names its courtesy
  turn stays whole-custom (30 lines — structuring it would double-count both the
  figure and its beats, and neither model has a slot for the qualifier);
  **"arky"** stays custom (7 lines — reversed roles, unmodeled, and ContraDB has
  no such concept either); a stated **rotation amount** stays custom (6 lines —
  the move has no `turn` param); and every unmappable dancer (`phantom
  partner`, `P1`/`P2`/`P4 partner`, `next corner`, `opposite neighbor`,
  `bottom couple`, `fives`) declines rather than being approximated.
  - Measured over the whole mirror with the real adapter: custom figures
    22,272 → **22,180**, structured share 78.69% → **78.78%**, per-dance beat
    totals **byte-identical** for all 20,516 dances. A secondary win: **13
    compound parents** (`Modified ladies chain to partner:`, `Wheel chain to
    neighbor:`) now decompose into their children, because their all-or-nothing
    child list was previously blocked by the one child that could not structure.

- **Balance-a-wave lines from The Caller's Box now import as real figures
  (#295, subsuming #296).** TCB writes "balance an existing wave" as its own
  line (`Balance wave of four (NR,WL)`, `Balance long wave (NR, women face
  in)`) — 4,613 lines across the 24,107-dance corpus, formerly the single
  largest custom bucket. No `balance_the_wave` move was added: the taxonomy
  expresses "a wave exists and is balanced" as the wave-FORMATION move carrying
  its `balance` flag, so such a line maps onto that move as ONE figure keeping
  its own beats.
  - `form_long_waves` gains `whom`, `hand` and `balance`. `whom`/`hand` default
    to the `unspecified` sentinel and `balance` to `false`, and
    `renderTemplate` is unchanged, so `renderCanonical` — the search/dedupe key
    — is byte-identical for every previously stored `form_long_waves` figure.
    (The short-wave RENAME below is a separate, deliberate canonical change.) `who` keeps its
    ContraDB meaning (the pair that faces IN); TCB states the same fact.
  - The display path now surfaces a wave's balance as a trailing
    ` - and balance` clause on both `form_long_waves` and `form_short_waves`,
    and `form_long_waves` renders the pair + hand when the source stated them
    (`form long waves - neighbor by the right, role2s facing in, role1s facing
    out - and balance`). This is issue **#296** — whose own reference to
    `form_an_ocean_wave` is stale, that MoveDef having been removed at taxonomy
    v14. `form_a_long_wave` and `pass_the_ocean` already embedded their balance
    and are unchanged.
  - The mapping runs as a FINAL pass of the CallersBox cross-line merge, so it
    only ever sees lines no existing fold claimed: a balance destined for a
    following swing / petronella / rory o'more / box the gnat / box circulate
    still folds forward, and a balance following an explicitly-formed wave still
    folds backward into exactly ONE form figure — now also carrying any hand or
    pair the balance line stated that the forming line did not.
  - TCB's `(NR,WL)` / `(NR, women face in)` annotation is decoded into params
    (the role pair is the wave's centre, the relationship pair its sides, hands
    opposite — verified on 2,560 of 2,764 corpus lines). Conservative: wave
    sizes we do not model, exotic formations (`intersecting`/`interlocking`/
    `circular` — refused on the trailing-balance FOLD path too, so a
    formed-then-balanced wave never loses the qualifier either; 86 corpus lines
    carry such a qualifier, of which 85 already fell to custom and exactly 1 was
    being folded and losing it), two-hand-hold annotations, people codes the
    shared
    `tcbPassPeople` map deliberately omits (square corners, mixer partner
    series, phantoms, trail buddies) and `Balance long wave for all in center`
    all stay custom.
  - `form (a) wave of four [with <dancer>]` — TCB's dominant forming wording —
    now structures too, so the explicit-forming merge can fire.
  - Measured over the full mirror: custom figures 24,775 → 22,272, structured
    share 76.24% → 78.69%, **per-dance beat totals byte-identical for all
    20,515 dances**, and no forward-merge move losing a balance. Taxonomy
    version → 21.

- **`Grand right and left` and `flutterwheel` now structure, with NO new
  taxonomy moves (#295).** Both are compound shorthands, so instead of crowding
  the taxonomy they are lowered onto moves that already exist —
  `contraTaxonomyVersion` stays at 20 and no DB migration is implied.
  - **`Grand right and left (<pass list>)` → one `pull_by_dancers` per stated
    pass**, each carrying that pass's dancer (`who`) and hand.
    `grandRightAndLeftFromPassList` runs on `parseFigureLines`'
    no-top-level-separator fall-through and reuses the hey decoder's people-code
    map (TCB writes one notation for both). Evidence: *334* by Diane Silver in
    both databases — TCB #10042 A2 `(4) Grand right and left (N3R;N2L)` is
    ContraDB #3403 A2 `[2] 3rd neighbors pull by right` + `[2] 2nd neighbors
    pull by left`; ContraDB has no grand-right-and-left figure at all.
  - **An unknown compound parent whose children ALL structure now emits the
    CHILDREN**, each with its own source-stated beats, instead of one custom
    parent. This is a **general** rule over TCB's `(beats) Name:` +
    indented-children convention, not a single-figure special case: it covers
    **877 compound blocks across 81 distinct parent names** in the full corpus —
    `interrupted square through 2`/`… 4` (331), `modified right and left through
    with partner/neighbor` (141), `flutterwheel` (135, e.g.
    `(8) Neighbor flutterwheel:` == `(4) Women allemande right 1/2` +
    `(4) Neighbor star promenade 1/2`), `open ladies/gents chain` (66),
    `georgia rang tang` (47), `hey along sides` (34) and a long tail.
    Known parents (`revolving_door`, …) still collapse to the single parent move
    exactly as before, and a block with ANY unstructurable child still stays one
    whole-custom figure — never a half-structured mix. **The parent's shorthand
    name is preserved verbatim (post-scrub) as a note on the first child**, so a
    meaningful qualifier — the "interrupted" in `Interrupted square through 2`,
    the "modified" in `Modified right and left through with partner`, or a name
    like `Georgia Rang Tang` — is never lost when the block is expressed as its
    parts.
  - **Beats are exact.** Grand right and left splits the source total evenly
    across the passes and **declines to custom when it does not divide evenly**
    (an uneven split would invent a per-pass duration the source never states);
    compound children already sum to the parent by the existing exact-sum guard.
    `deriveSections`' cumulative section placement is therefore unchanged.
  - **Prefer-custom is preserved.** A pass code the taxonomy cannot faithfully
    represent keeps the whole line custom rather than approximating it —
    notably TCB's *square* corners `C1`-`C3`, which are a different relationship
    from the ECD first/second corners `ParamVocab` models — as does any leftover
    prose (`Progressive …`, `Same-role …`, `[with N2]`, a second parenthetical,
    a trailing `;` clause). 128 of the corpus's 353 grand-right-and-left lines
    decompose; whole-corpus structured share rises 75.09% → 76.24%.
  - **Security (OWASP).** Imported text is untrusted: the pass-list fan-out is
    bounded by the new `kMaxPassListCells` (12), mirroring `kMaxMeanwhileSides`;
    over the cap, or on any malformed input, the line degrades to the unchanged
    custom figure rather than fanning out unboundedly or throwing.
  - The shared TCB people-code map gains glossary-backed `P1` (→ `partners`),
    `S1` (→ `shadows`) and `S2` (→ `secondShadows`), so hey pass lists using
    those codes now decode too.

- **`mad_robin` and `butterfly_whirl` now carry the detail The Caller's Box
  states (#295).** `mad_robin` gains a rotation `direction`
  (`clockwise`/`counterclockwise`) and `whom` — the pair you travel AROUND,
  which is a different concept from the existing `who` (ContraDB's pair that
  steps *in front*). `butterfly_whirl` gains `who` and the same `direction`.
  New conservative TCB recognizers structure "Mad robin clockwise around
  neighbor N2" and "Partner butterfly whirl counterclockwise"; each requires
  BOTH stated facts, so a bare "mad robin" / "butterfly whirl" — or a butterfly
  whirl with a rotation amount, which no source models — still degrades to a
  faithful custom figure. Sourced from TCB's glossary and a 5,147-line TCB
  sample (24/24 and 18/18 lines respectively state both facts); ContraDB models
  neither, so ContraDB imports keep asserting nothing. Taxonomy version → 20.
  Purely additive: every new param defaults to an `unspecified` sentinel that
  renders as nothing, so `renderCanonical` — the search/dedupe key — is
  byte-identical for every figure stored before v20 and no database migration
  is needed.

- **`orbit` is now a first-class move (#295).** A standalone `orbit` move —
  `who` (dancerSet), `turn` (`clockwise`/`counterclockwise`, reusing the
  existing spin-direction vocabulary), `amount` (rotation, default ½), and
  `beats` — recognized from The Caller's Box's standalone phrasing ("Men orbit
  clockwise 1/2"). The recognizer is conservative: both the direction and the
  amount must be stated, so a bare "orbit" stays a custom figure. Taxonomy
  version → 19.
- **`meanwhile` display rendering (#594).** Human-facing renders
  (`FigureRenderer.render`/`renderVerbose`/`renderSummary`) now join a
  `meanwhile` container's concurrent sides with the caller-facing word
  "while" (e.g. "Larks allemande left 1 while Robins orbit clockwise ½"; 3+
  sides chain the same separator). `renderCanonical` is unaffected — it keeps
  joining sides with the structural `meanwhile` move id, so the dedupe/FTS key
  stays byte-stable.
- **`meanwhile` container figure (#590).** A first-class figure for simultaneous
  action: a single `meanwhile` container groups ≥2 concurrent sub-figures
  (nested in `params['figures']`, encoded recursively via the same figure codec)
  that share one beat count (`params['beats']`). `Figure.isMeanwhile`,
  `Figure.subFigures`, and the `Figure.meanwhile(...)` factory expose it;
  `kMaxMeanwhileSides` (6) bounds the side count and nesting is **flat only**.
  It rides `figures_json` **additively** — no `figureSchemaVersion` bump.
  `deriveSections` counts the shared beats exactly once, the search indexer
  flattens the container so each concurrent side stays individually matchable
  (`filterByMove` + FTS), and the archive/.ccshare sanitizer recurses into every
  nested side (scrubbing free text) while enforcing the depth + side-count caps
  defensively (clamp/flatten, never throw). Non-fabricating: it records only
  "these happen at once," never a synthesized combined move.

## [0.1.0-beta.5] - 2026-07-29

### Added

- Add full ContraDB rendered-figure recognition.
- Accept localized Caller's Companion dates.
- Add per-dance walkthroughs.
- Expand Caller's Box figure recognition.
- Add custom-field category grouping and inline choices.
- Add per-figure walkthrough snippets.
- Add swing ending-facing parameters.

### Changed

- Document the derived-taxonomy-value convention.
- Add per-adapter figure front ends.
- Route free-text parsing through source front ends.
- Localize exported documents.
- Localize core diagnostics.

## [0.1.0-beta.4] - 2026-07-23

### Added

- Batch-edit dance levels.
- Distinguish parser-gap custom figures.
- Reparse import-gap figures.
- Add Venue storage and schema v14.
- Add diagnostics and rotating crash logs.
- Add venue editor and settings support.
- Resolve venues in exports.
- Add import-review consent for shared files.
- Batch-edit ratings, tunes, and custom fields.
- Add free-text figure entry.
- Add user-defined figure shorthands.

### Changed

- Batch dance child hydration.
- Add purge/export regression coverage.
- Add seeded parser and binary-reader fuzz tests.

### Fixed

- Resolve ambiguous shared-program slots to existing dances.
- Include referenced choreographers in shared programs.
- Preserve figure modifiers in export.
- Fix purge-related corruption.
- Garbage-collect orphaned choreographers and sources.
- Make replace-mode restore atomic.
- Bound import and `.USR` input sizes.
- Mark defaulted figure subjects as assumptions.
- Exclude soft-deleted dances from FTS.
- Sanitize imported control, bidi, and formatting characters.
- Batch and report derived-index rebuilding.
- Scope author and last-called sorts correctly.
- Deduplicate re-imported venues.

## [0.1.0-beta.3] - 2026-07-20

### Added

- Add first/second-half derivation and matrix badges.
- Add TCB rotation-gate figures.
- Import ContraDB callers and event dates.
- Add first/second-half calling statistics.
- Add sort-direction controls.
- Add called-count metadata.
- Add opt-in decimal turn rendering.
- Add inline emphasis for user-authored figure text.

### Fixed

- Auto-stamp performed dance slots.

## [0.1.0-beta.2] - 2026-07-19

### Added

- Snap beats to the new parameter default.
- Add a hide-alternates export option.
- Add colour-name theme seeding.
- Import programs directly from ContraDB.
- Seed “The Baby Rose”.
- Search ContraDB programs during import.
- Collapse TCB compound figures correctly.
- Receive shared archive bundles.

### Changed

- Batch program-slot loading.
- Split the overloaded `form_an_ocean_wave` move.

### Fixed

- Import Becket direction from TCB.
- Decode TCB `N1` hey passes.
- Add the program-debut marker and dance-first flag.
- Correct display-default and subject rendering.
- Preserve unknown moves non-destructively.
- Match ContraDB zig-zag, slice, mad-robin, revolving-door, and box-circulate
  wording.
- Match ContraDB terse-clause wording.
- Match ContraDB ocean-wave wording and migrate the old move.

## [0.1.0-beta.1] - 2026-07-17

### Added

- Scaffold Flutter workspace, pure-Dart core package, and CI.
- Implement the core domain model.
- Add figure serialization and the dialect-rendering engine.
- Add the Drift/SQLite storage layer.
- Add dance browsing, sorting, and filtering.
- Add the search AST, SQL compiler, and schema v2.
- Add Collection search and query building.
- Add custom-figure lingo and accessible figure reordering.
- Add custom-field management and text/number search facets.
- Add the simple figure-move taxonomy.
- Add dancer-interaction figure moves.
- Add choice-enum figures and single-dancer vocabulary.
- Add the places figure family and `ParamKind.places`.
- Add the hey/wave family and complete the ContraDB move set.
- Add active-dialect settings.
- Add taxonomy-keyword underlining for custom figures.
- Add Program CRUD and navigation.
- Add program event metadata and schema v3.
- Add dance levels and schema v4.
- Add dance-level search.
- Add program printing and export.
- Add the programming matrix.
- Add composed and revised dates.
- Add ratings, sorting, and filtering.
- Add choreographer contact data.
- Add choreographer contact editing.
- Add published-source citations and schema v8.
- Add published-source full-text search and schema v9.
- Add published-source search UI support.
- Make dialect settings fully editable.
- Add dialect substitutions for dancer terms.
- Auto-link dance cross-references.
- Add custom dialect name resolution and storage.
- Add by-phrase figure search.
- Add per-dance calling history.
- Add dialect-aware dance text/PDF export.
- Add verbose and screen-reader figure rendering.
- Add live program adjustments.
- Add source adapters and provenance tracking.
- Add ContraDB named hey durations.
- Add parameter-dependent beat counts.
- Add the generic JSON archive codec.
- Add generic-JSON import.
- Add Caller's Companion clipboard/text import.
- Add ContraDB import.
- Add Caller's Box JSON import.
- Add ContraDB HTML-link import.
- Add Caller's Companion `.USR` import.
- Add Caller's Box online search and direct import.
- Derive beats from figure parameters.
- Add shared free-text figure parsing.
- Resolve imported authors to choreographers.
- Add downgrade protection and backup-before-migrate guards.
- Add additional TCB figure recognizers.
- Search using all saved dialects.
- Recognize Rory O'More and hall figures.
- Merge cross-line balance/bend-the-line figures.
- Recognize heys as structured figures.
- Add `box_circulate`, `star_through`, and the weave-the-line alias.
- Persist and undo imported `.USR` programs.
- Recognize Slide, contra corners, and give-and-take.
- Add ContraDB online title search.
- Recognize line-of-four hall prefixes.
- Recognize facing-star rotations.
- Split TCB semicolon compounds.
- Decode compound circle/star turn amounts.
- Add value equality to `SearchEnrichment`.

### Changed

- Add regression coverage for the auto-size load/toggle race.
- Apply the active dialect to editor vocabulary.
- Update dependencies and the `share_plus` API.
- Lowercase shipped dialect role defaults.
- Ignore leading articles when sorting titles.
- Split matrix swing by role and hey by length.
- Harden CI and analyzer consistency.
- Reduce collection/program full hydration.
- Harden purge, FTS, export, bootstrap, and Perform tests.
- Consolidate free-text scrubbing.
- Move hey length earlier in editor ordering.
- Add version, Flutter, and schema single-source guards.
- Canonicalize imported role and do-si-do spellings.
- Normalize TCB dialect text before recognition.
- Document why TCB gates were not recognized.

### Fixed

- Correct phrase labeling, `DanceLink` invariants, and Formation documentation.
- Address search-core review defects.
- Regenerate `DanceLink` IDs when duplicating dances.
- Render swing prefixes without unwanted editor scrolling.
- Sanitize FTS5 query text.
- Harden startup, purge, and database-open handling.
- Match ContraDB figure-summary modifiers.
- Enforce hey ricochet limits.
- Render balance and long-lines summary modifiers.
- Align `star_through` with `california_twirl`.
- Deduplicate re-imported Caller's Companion programs.

## [0.1.0-beta.0] - 2026-07-10

- Initial package scaffold.
