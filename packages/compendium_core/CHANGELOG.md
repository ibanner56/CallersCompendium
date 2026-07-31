## Unreleased

### Added

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

### Fixed

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

### Changed

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

## 0.1.0

- Initial package scaffold.
