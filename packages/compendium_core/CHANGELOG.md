## Unreleased

### Fixed

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
