## Unreleased

### Changed

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

### Added

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

## 0.1.0

- Initial package scaffold.
