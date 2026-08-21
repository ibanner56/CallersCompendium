# Design: Search

*Roadmap item 3.2 · v0.1 (2026-07-11). Fills the "future search design in
Phase 3" placeholder in [storage.md](storage.md) "Search execution". Search
lives in the core package as a composable filter tree that compiles to a single
SQL query over the derived indexes; the UI (3.2c) is a thin builder over that
tree. Conforms to [ux.md](ux.md) §1 and [dialect.md](dialect.md)
"Canonicalization on input".*

## Principles

1. **One tree, one query.** A search is a `DanceFilter` value (a sealed tree).
   It compiles to exactly one parameterized `SELECT` — never an in-memory scan,
   never N per-leaf queries stitched in Dart (ContraDB pitfall #2).
2. **Search the derived indexes, not the JSON.** Structural predicates hit
   `dance_figures`; short text prefixes hit `dance_fts`; longer literal
   substrings hit `dance_substring_fts`; scalars hit `dances` columns. The
   authoritative `figures_json` is never parsed during search.
3. **Canonical in, canonical matched.** Move names and free-text terms pass
   through `canonicalize()` at the compiler boundary, mirroring how data was
   canonicalized on the way in — so a dialect user's "robins allemande"
   query matches stored `role2s`/`allemande` (see [dialect.md](dialect.md)).
   Collection text search may explicitly scope to raw title text or canonical
   figure text; Omni is the OR of the canonical cross-field query and a
   raw-title fallback. Long queries keep the complete input as one literal
   substring.
4. **Injection-safe by construction.** Every user value is a bind variable;
   only a fixed vocabulary of column names, operators, and JSON key paths is
   ever interpolated, and each is validated against an allow-list.
5. **Common case one-tap, advanced behind a disclosure.** The UX maps the
   frequent searches (a facet, or a few facets AND-ed) to trivial trees, and
   only exposes the full boolean/sequence grammar under "Advanced"
   (ContraDB ez-query lesson, [ux.md](ux.md) §1).

## The filter AST

A new sealed type in `compendium_core` (`lib/src/search/`). Sealed so the
compiler and UI both exhaustively switch over it.

```
sealed DanceFilter
  // combinators
  AndFilter(List<DanceFilter> children)      // ∅ ⇒ TRUE  (matches everything)
  OrFilter(List<DanceFilter> children)       // ∅ ⇒ FALSE (matches nothing)
  NotFilter(DanceFilter child)

  // metadata leaves
  FullTextFilter(String query, [FullTextScope scope = omni])
                                              // → scoped FTS5 MATCH
  AuthorFilter(String choreographerId)
  SourceFilter(String query)                 // substring match on cited source title/author
  SourceIdFilter(String sourceId)            // identity match on cited source id
  FormFilter(DanceForm form)                 // roadmap "Type": contra | ecd | square
  FormationFilter(FormationShape shape)      // shape only; free-text detail via FullTextFilter
  ProgressionFilter(Progression progression)
  StatusFilter(DanceStatus status)
  LevelFilter(DanceLevel level, [LevelOp op = eq])  // ordered scale; see LevelOp below
  MixedLevelFilter(bool mixed)               // → dances.mixed_level
  MixerFilter(bool mixer)                    // → dances.mixer (issue #732)
  RatingFilter(int minimum)                  // minimum-star floor, 1..5
  TagFilter(String tagId)
  CustomFieldFilter(CustomFieldDef def, CustomFieldOp op, Object? value)

  // structural leaf
  FigureFilter(FigureQuery query)            // sugar: FigureFilter.leaf(String move, {params, section})

  // sequence
  ThenFilter(FigureQuery before, FigureQuery after)
```

`CustomFieldOp` is typed by the field's `CustomFieldType` (validated when the
leaf is built against the field def, and again — defensively — at compile):

| Field type | Allowed operators | Column compared |
|---|---|---|
| `text`    | `contains`, `equals` | `value_text` |
| `number`  | `eq`, `lt`, `gt`, `between(lo, hi)` | `value_num` |
| `boolean` | `is` (true/false) | `value_num` (0/1) |
| `choice`  | `is`, `in(List<String>)` | `value_text` |

`LevelOp` is the ordered comparison for a `LevelFilter` leaf (`eq` / `lte` / `gte`
against the `DanceLevel` scale). An unspecified level (`dances.level IS NULL`)
never matches `lte` or `gte` — an unspecified difficulty is not a point on the
scale. `MixedLevelFilter` is a separate boolean axis orthogonal to `LevelFilter`.

`FigureQuery` (the operand grammar for `ThenFilter`, and the reusable shape of a
structural predicate) is deliberately **narrower** than `DanceFilter`:

```
sealed FigureQuery
  FigureLeaf(String move, {Map<String, Object?> params, String? section})
  FigureAnd(List<FigureQuery>)   // all match the SAME figure row
  FigureOr(List<FigureQuery>)    // any matches the same figure row
  FigureNot(FigureQuery)         // this figure row does NOT match
```

Rationale for the split (see *Open questions* for the flagged decision): a
`ThenFilter` asks "does a figure matching X occur *before* a figure matching Y",
which is only meaningful for predicates evaluated **per `dance_figures` row**.
Metadata leaves (`AuthorFilter`, `FullTextFilter`, `FormFilter`, …) are
per-*dance*, not per-figure, so they have no position in the sequence and are
excluded from `FigureQuery`. `FigureAnd`/`FigureOr`/`FigureNot` combine
constraints *on one figure* (e.g. "a `swing` in B1 that is a progression"),
distinct from the dance-level `AndFilter`/`OrFilter`/`NotFilter`.
`FigureFilter(query)` wraps any `FigureQuery` as a dance-level predicate ("some
figure in the dance matches"); `FigureFilter.leaf(move, {params, section})` is
convenience sugar for the single-leaf case.

## SQL compilation

The compiler (`FilterCompiler` in `compendium_core`) walks the tree and emits
one statement plus an ordered list of bind values:

```sql
SELECT id FROM dances
WHERE deleted_at IS NULL
  AND (<predicate>)
ORDER BY <sort>;
```

Each node compiles to a **boolean predicate over the current `dances` row**.
Binds are collected in **pre-order, left-to-right** as the predicate string is
built, so the bind list index always matches the emitted `?` order. `AndFilter([])`
compiles to the literal `1` (TRUE); `OrFilter([])` to `0` (FALSE); the outer
`deleted_at IS NULL` always stands regardless of the tree.

### Metadata leaves

| Node | Predicate |
|---|---|
| `FullTextFilter(q)` | `id IN (SELECT dance_id FROM dance_fts WHERE dance_fts MATCH ?)` |
| `AuthorFilter(cid)` | `id IN (SELECT dance_id FROM dance_authors WHERE choreographer_id = ?)` |
| `SourceFilter(q)` | `id IN (SELECT ds.dance_id FROM dance_sources ds JOIN published_sources ps ON ps.id = ds.source_id WHERE ps.title LIKE '%' \|\| ? \|\| '%' ESCAPE '\' OR ps.author LIKE '%' \|\| ? \|\| '%' ESCAPE '\')` (2 binds) |
| `SourceIdFilter(sid)` | `id IN (SELECT dance_id FROM dance_sources WHERE source_id = ?)` |
| `TagFilter(tid)` | `id IN (SELECT dance_id FROM dance_tags WHERE tag_id = ?)` |
| `FormFilter(f)` | `form = ?` (enum `.name`, e.g. `'contra'`) |
| `FormationFilter(s)` | `formation_shape = ?` (enum `.name`) |
| `ProgressionFilter(p)` | `progression = ?` (enum `.name`) |
| `StatusFilter(s)` | `status = ?` (enum `.name`) |
| `LevelFilter(l, eq)` | `level = ?` (enum `.name`) |
| `LevelFilter(l, lte/gte)` | `level IS NOT NULL AND (CASE level … END) ≤/≥ ?` (ordinal comparison over the `DanceLevel` scale; see `FilterCompiler._level`) |
| `MixedLevelFilter(b)` | `mixed_level = ?` (bind `1`/`0`) |
| `MixerFilter(b)` | `mixer = ?` (bind `1`/`0`) |
| `RatingFilter(n)` | `rating >= ?` (unrated dances excluded — NULL is not on the scale) |

Enum leaves compare against the stored `EnumNameConverter` string (`.name`), so
`FormFilter(DanceForm.contra)` binds `'contra'`. The `IN (SELECT …)` subqueries stay
cheap because `dance_authors`, `dance_tags`, `dance_sources`, and `dance_fts` are
all keyed/indexed on `dance_id`.

### Custom fields

`CustomFieldFilter(def, op, value)` compiles to an `EXISTS` over the field's row:

```sql
EXISTS (SELECT 1 FROM custom_field_values v
        WHERE v.dance_id = dances.id AND v.field_id = ?
          AND <op predicate>)
```

with `<op predicate>` selected by operator (all values bound):

| Op | Predicate |
|---|---|
| `contains` | `v.value_text LIKE '%' || ? || '%'` |
| `equals` / `is` (text/choice) | `v.value_text = ?` |
| `in` (choice) | `v.value_text IN (?, ?, …)` |
| `eq` (number) | `v.value_num = ?` |
| `lt` / `gt` | `v.value_num < ?` / `v.value_num > ?` |
| `between` | `v.value_num BETWEEN ? AND ?` |
| `is` (boolean) | `v.value_num = ?` (bind `1`/`0`) |

`field_id` is bound, not interpolated. The operator token is chosen from the
allow-list above by exhaustive `switch` on `(CustomFieldType, CustomFieldOp)`;
an illegal pairing is rejected when the leaf is constructed.

### Structural: `FigureFilter` / `FigureLeaf`

A figure leaf compiles to an `EXISTS` over the dance's `dance_figures` rows:

```sql
EXISTS (SELECT 1 FROM dance_figures f
        WHERE f.dance_id = dances.id
          AND f.move = ?
          [AND json_extract(f.params_json, '$.<key>') = ?]   -- per param
          [AND f.section = ?])                                -- if section set
```

- `move` is canonicalized (below) then bound.
- Each `params` entry adds one `json_extract(f.params_json, '$.<key>') = ?`
  clause. The `<key>` path segment is **not** a bind (SQLite JSON path syntax
  can't be parameterized); it is validated against `^[A-Za-z_][A-Za-z0-9_]*$`
  and rejected otherwise, so only well-formed identifiers reach the string.
  The value is always bound. Values are compared using `json_extract`'s natural
  typing (text/number/bool), so `{who: 'partners'}` binds the string
  `'partners'` and `{beats: 16}` binds the integer `16` — this differs from the
  existing `danceIdsWithFigure()` primitive, which compares pre-encoded JSON
  text; the compiler supersedes that primitive.
- `section`, when present, binds the derived phrase label (`'B1'`, …).

`FigureAnd` / `FigureOr` combine the *inner* clauses of a **single** `EXISTS`
(all constraints on the same `f` row), joined by `AND` / `OR`. Negation has two
distinct paths, because `FigureNot` lives in `FigureQuery`, not `DanceFilter`:

- **`FigureNot` nested inside a `FigureAnd`/`FigureOr`** negates that one
  figure-row clause, compiled as `NOT COALESCE((<clause>), 0)` — the
  `COALESCE` keeps SQL's three-valued logic (a NULL `json_extract` on a missing
  param) from swallowing the row.
- **A dance-level structural predicate wrapping a `FigureNot`** —
  `FigureFilter(FigureNot(FigureLeaf(...)))`, read as "the dance has no figure
  matching X" — compiles to
  `id NOT IN (SELECT dance_id FROM dance_figures f WHERE <clause>)`. This is
  NULL-safe because `dance_figures.dance_id` is `NOT NULL`, so the subquery can
  never yield a NULL that would break `NOT IN`.

Dance-level boolean negation of any *other* predicate stays `NotFilter(<child>)` →
`NOT (<child>)` (see Combinators below).

#### `meanwhile` containers are flattened per constituent (#590)

A `meanwhile` container figure holds ≥2 concurrent sub-figures. The indexer
(`_insertDerivedRows`) does **not** index the container as a `meanwhile` move;
instead it **flattens** it, emitting one `dance_figures` row per concurrent side
(each side's `move`, `params_json`, `canonicalText`) and appending each side's
canonical text to `dance_fts.figures_text`. So every constituent stays
individually matchable — a `FigureLeaf` matches either side, and FTS matches
either side's text. `idx` runs over the **flattened** constituent stream (the
`{dance_id, idx}` primary key requires distinct idx per row), so the container's
sides occupy consecutive slots in order; the container itself supplies their
shared section/beat placement. A second column, `group_idx`, is **shared** by
every row flattened from one top-level figure (all concurrent sides of a
container included) and is monotonic across top-level figures; it is what the
`ThenFilter` operator correlates on (see below), so simultaneous sides — which share a
group — are never read as sequential.

**Concurrency vs. sequence in `ThenFilter` (#748, was a #590 limitation).** Because a
container's concurrent sides get consecutive `idx` values, a positional
correlation on `a.idx < b.idx` could not tell them apart from a genuine
sequence: `ThenFilter(X, Y)` — and, symmetrically, `ThenFilter(Y, X)` — would both match an
`X while Y` container even though neither side happens before the other. The
signal needed to separate "two sides of one container" from "two sequential
figures" is not derivable from `idx`, `section` (sequential figures can share a
phrase) or `beats` (each side stores its own), so it is carried explicitly as
`group_idx`. `ThenFilter` correlates on `a.group_idx < b.group_idx`: two sides of one
container share a group and are excluded in **both** directions, while a real
sequence (distinct, increasing groups) still matches. This was originally
recorded as a limitation deferred to #594; #594 shipped without addressing it,
so #748 tracked and fixed it.

### Sequence: `ThenFilter(before, after)`

"A figure matching `before` occurs earlier in the dance than a figure matching
`after`" → a self-join on `dance_figures.group_idx`:

```sql
EXISTS (SELECT 1 FROM dance_figures a
        JOIN dance_figures b
          ON a.dance_id = b.dance_id
         AND a.dance_id = dances.id
         AND a.group_idx < b.group_idx
        WHERE (<before applied to a>)
          AND (<after applied to b>))
```

`<before applied to a>` / `<after applied to b>` are the `FigureQuery` clauses
compiled against aliases `a` and `b` respectively (same clause shapes as the
`EXISTS` above, minus the `dance_id` correlation which the join supplies).
`a.group_idx < b.group_idx` gives strict "before" while excluding the concurrent
sides of one `meanwhile` (which share a `group_idx`; see the flatten note
above); consecutive-only ("immediately then") is **not** in v1 (see *Open
questions*). Nested `ThenFilter` is not supported in v1 — `ThenFilter` operands are
`FigureQuery`, which excludes `ThenFilter` — keeping the compiled join to a single
pair of aliases.

### Combinators & sort

`AndFilter`/`OrFilter` wrap children in `( … AND … )` / `( … OR … )`; `NotFilter(child)` emits
`NOT (<child>)`.

**Execution model — one SELECT, plus a post-fetch sort for two cases.** The
single compiled `SELECT` performs *all filtering* and every **SQL-expressible**
sort: `title COLLATE NOCASE` (the default), `updated_at DESC` (recently added/
edited), and — only for a bare Omni `FullTextFilter` leaf with at most two
Unicode scalar values — `bm25(dance_fts)` relevance. Two sorts are **not**
expressible in that one statement and are
applied as a **post-fetch pass in Dart** over the returned id set:

- `author` — needs the author-name join/ordering; and
- `last-called` — needs the separate `ProgramRepository.lastCalledByDance()`
  query (as in 3.1).

So the compiler always emits exactly one `SELECT` (filter + SQL sort); when the
requested sort is `author` or `last-called`, the id set it returns is reordered
by an explicit Dart post-processing step — not by the SQL. `bm25` relevance is
available only for a bare short Omni `FullTextFilter`; scoped queries,
long-substring queries, and any other tree fall back to the `title` default
because their result sets do not share the legacy rank source.

### Worked example

UX: *form = contra, has a `petronella` in B1, then a `swing`*:

```
AndFilter([
  FormFilter(DanceForm.contra),
  ThenFilter(
    FigureLeaf('petronella', section: 'B1'),
    FigureLeaf('swing'),
  ),
])
```

compiles to:

```sql
SELECT id FROM dances
WHERE deleted_at IS NULL
  AND ( form = ?                                     -- 'contra'
    AND EXISTS (SELECT 1 FROM dance_figures a
                JOIN dance_figures b
                  ON a.dance_id = b.dance_id
                 AND a.dance_id = dances.id
                 AND a.group_idx < b.group_idx
                WHERE (a.move = ? AND a.section = ?)  -- 'petronella','B1'
                  AND (b.move = ?)) )                 -- 'swing'
ORDER BY title COLLATE NOCASE;
```

Binds, in emission order: `['contra', 'petronella', 'B1', 'swing']`.

## Schema v2 migration

3.2 adds indexed section-aware figure search, which needs the derived phrase
label persisted on each figure row. This is the project's **first real schema
migration** (v1 → v2).

**Change.** Add a nullable column to `dance_figures`:

```sql
ALTER TABLE dance_figures ADD COLUMN section TEXT;   -- e.g. 'A1','B2'; NULL if underivable
```

**How `section` is populated.** During `_rebuildDerived`, core already has the
`Dance`. The phrase label per figure is derived by the domain model — no new
derivation logic:

- `Dance.sectionedFigures` (dance.dart) returns
  `deriveSections(figures, phraseStructure)` (phrase_structure.dart), a
  `List<SectionedFigure>` where `SectionedFigure.label` is the phrase label of
  the phrase in which the figure **starts** (`labelAtBeat`, cumulative beats).
  Exception: a zero-beat figure at a phrase boundary (beat > 0) is attributed to
  the preceding phrase — it sits between two phrases and musically belongs with
  the one that just ended. A zero-beat figure at beat 0 stays in the first phrase.

`_rebuildDerived` iterates `dance.sectionedFigures` (instead of `figures`
alone) and writes `section: Value(sectioned.label)` into each
`DanceFiguresCompanion`. Labels come straight from `PhraseStructure.labels`
(`A1 A2 B1 B2 …`); a figure whose start beat can't be labelled (empty structure
never happens — it defaults to standard 4×16) yields a non-null label in all
current cases, but the column stays nullable to stay forward-compatible with
future structureless forms.

**Migration wiring** (`database.dart`):

- Bump `schemaVersion` `1 → 2`; extend the version-history doc comment.
- `MigrationStrategy.onUpgrade`:

  ```dart
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      await m.addColumn(danceFigures, danceFigures.section);
      // Backfill section for every existing figure row.
      await repositories.dances.rebuildAllDerived();
    }
  }
  ```

  `rebuildAllDerived()` already recomputes every `dance_figures` +
  `dance_fts` row from `figures_json` for all dances including soft-deleted
  ones — exactly the "derived tables rebuilt after any migration touching
  figures" contract in [storage.md](storage.md) "Migrations". (Wiring note: the
  rebuild needs the repository/taxonomy; if that isn't reachable from inside
  `MigrationStrategy`, the equivalent rebuild SQL runs inline in `onUpgrade`
  and the repository rebuild is a post-open integrity pass — an implementation
  detail for 3.2b, flagged in *Open questions*.)

**Indexes.** Add, alongside the existing `dance_figures_move`:

```sql
CREATE INDEX dance_figures_move_section ON dance_figures(move, section);
CREATE INDEX dance_figures_dance_idx    ON dance_figures(dance_id, idx);
```

- `(move, section)` serves the common `FigureFilter` leaf (`move = ? AND section = ?`).
- `(dance_id, idx)` serves the `ThenFilter` self-join's ordering and correlation.

**Migration test** (`test/storage/migration_test.dart`, replacing the scaffold's
placeholder note). Following the scaffold's own instructions for "when schema
v2 lands":

1. Check in a small `test/storage/fixtures/v1.sqlite` captured at schema v1
   (built by the current `onCreate`, seeded with a couple of dances whose
   figures span sections). Generation is scripted and documented so it can be
   regenerated.
2. Test: copy the fixture to a temp path, open it through
   `CompendiumDatabase` (triggering the real `onUpgrade` path), then assert:
   - `PRAGMA table_info(dance_figures)` now includes a `section` column;
   - `schema_version` (drift's stored version) is 2;
   - the seeded dances' figure rows have the expected `section` labels
     (e.g. the figure at beat 0 is `A1`, a figure starting at beat 32 is `B1`);
   - pre-existing non-derived data (titles, authors, custom values) survives
     unchanged.
3. Keep the existing "beforeOpen recreates `dance_fts`" test.

## Dialect canonicalization of input

Search input is canonicalized at the **compiler boundary**, once, before any
bind is produced — so storage/search stay dialect-agnostic exactly as writes
are ([dialect.md](dialect.md) "Canonicalization on input"):

- **`FullTextFilter(query)`**: the query string is run through
  `canonicalizeText(query, activeDialect)` before it becomes the `MATCH` bind,
  so a dialect term ("robins", "gents") maps to the canonical role token stored
  in `dance_fts.figures_text`. FTS operators the user typed (`AND`, `"…"`,
  `*`) are preserved by the term-only, word-boundary substitutor.
- **`FigureLeaf.move` / `FigureQuery` moves**: the move name is canonicalized
  to its taxonomy id before binding to `f.move = ?`. A caller who typed a
  dialect/synonym move name resolves to the same canonical `move` stored in
  `dance_figures`.
- **`params` string values** that name roles (e.g. `who: 'robins'`) are
  canonicalized the same way before binding, matching the canonical params
  written by the codec.

The active `Dialect` is passed into the compiler (the UI supplies the user's
current dialect). Non-role prose and unknown terms are left verbatim
(canonicalization is conservative — exact word-boundary matches only).

## Query-builder UX (spec for 3.2c — not built in this PR)

Every UX affordance maps to an AST node; the panel is a thin editor over the
tree. This section specifies the mapping; the widget work is 3.2c.

| Affordance | AST |
|---|---|
| Unified FTS search bar | `FullTextFilter(query)` |
| One-tap facet: Form/Type | `FormFilter(form)` |
| One-tap facet: Formation | `FormationFilter(shape)` |
| One-tap facet: Progression | `ProgressionFilter(progression)` |
| One-tap facet: Author | `AuthorFilter(choreographerId)` |
| One-tap facet: Tag(s) | `TagFilter(tagId)` (multiple tags AND-ed, or OR within the facet — see open Q) |
| One-tap facet: Status | `StatusFilter(status)` |
| One-tap facet: Level | `LevelFilter(level)` — multiple levels OR-ed |
| One-tap facet: Mixed level | `MixedLevelFilter(true)` |
| One-tap facet: Mixer | `MixerFilter(true)` — tri-state (null / show-mixers-only); shown only when the collection contains at least one mixer dance (issue #732) |
| One-tap facet: Rating | `RatingFilter(minimum)` — minimum-star floor |
| One-tap facet: Custom field | `CustomFieldFilter(def, op, value)` — `def` is a `CustomFieldDef`; `op` is a `CustomFieldOp` |
| **Multiple facets selected** | `AndFilter([...leaves])` — the common case |
| Advanced ▸ boolean group | `AndFilter` / `OrFilter` / `NotFilter` group nodes |
| Advanced ▸ figure row | `FigureFilter(query)` with move + param + section pickers |
| Advanced ▸ sequence row ("X then Y") | `ThenFilter(before, after)` — both operands are `FigureQuery` |

- **Common case**: the facet chips compose into a flat `AndFilter` of leaves. No tree
  UI is shown until the user opens **Advanced**, which reveals the nested
  group/figure/sequence editor (ez-query lesson).
- **Figure row pickers**: `move` = taxonomy type-ahead (dialect-aware, same as
  the editor); `params` = named-param pickers from the move's schema; `section`
  = dropdown of the dance form's phrase labels (`A1 A2 B1 B2 …`).
- **Sequence row**: two figure-row editors joined by "then"; each side is a
  `FigureQuery` (a figure leaf, or a `FigureAnd`/`FigureOr` group of figure leaves).
- **Accessibility**: result counts are announced politely to AT via a live
  region ("42 dances"), per [ux.md](ux.md) §1 and the accessibility baseline;
  the builder is fully keyboard-operable and every control is labelled.

## Performance

Target (from [storage.md](storage.md)): **< 50 ms** for a representative query
over **20k dances** (TCB scale) on tablet-class hardware, with no full-table
in-memory scans.

- The design meets this by construction: every predicate is either a `dances`
  column compare, an indexed `dance_id` subquery, or an `EXISTS`/self-join over
  `dance_figures` served by the `(move, section)` and `(dance_id, idx)`
  indexes. `figures_json` is never parsed at query time.
- `json_extract` on `params_json` is evaluated only for figure rows already
  narrowed by the indexed `(move, section)` predicate, keeping it off the hot
  path.

**CI benchmark harness** (`packages/compendium_core/test/` or a dedicated
`benchmark/`, run in CI):

1. **Fixture generator**: build ~20k synthetic dances with realistic figure
   counts (≈8–12 figures each) and varied moves/sections/authors/tags/custom
   fields, into an on-disk SQLite DB (not in-memory, to reflect real I/O).
   Deterministic seed so runs are comparable.
2. **Query set**: a handful of representative trees — a bare `FullTextFilter`, a
   single facet, a multi-facet `AndFilter`, a `FigureFilter` leaf with a param+section, and
   a `ThenFilter` sequence — each executed after a warm-up.
3. **Assertion**: measure median wall-clock per query; assert median **< 50 ms**
   with headroom (fail threshold set with margin, e.g. alert well before 50 ms
   to catch regressions early). Report timings in CI output.
4. **Location & gating**: lives beside the storage tests; runs on the same CI
   matrix as [ci.yml](../../.github/workflows/ci.yml). Marked so a slow CI
   runner's variance doesn't flake the build (generous absolute threshold,
   with the real regression signal being the reported median).

## Open questions

Flagged for coordinator/user input before 3.2b:

1. **`ThenFilter` operand grammar** *(want input)*. This doc recommends `ThenFilter`
   operands are `FigureQuery` (figure leaves + `FigureAnd`/`FigureOr`/
   `FigureNot`), **not** arbitrary `DanceFilter` and **not** nested `ThenFilter`.
   Metadata/`FullTextFilter` under `ThenFilter` has no per-position meaning and would force
   a much heavier compile. Confirm this restriction is acceptable, or specify
   the intended semantics if metadata-in-sequence is wanted.
2. **`NotFilter` semantics** *(want input)*. Recommended: dance-level `NotFilter(child)` =
   boolean `NOT (<child>)`; `FigureNot(leaf)` at dance level = `NOT EXISTS`
   ("no figure matches"). Note the subtlety that `NotFilter(FigureFilter(x))` (dance has no
   x) and `FigureFilter` under a De Morgan expansion behave differently around
   `EXISTS`/`NOT EXISTS`; confirm the "no figure matches" reading is what users
   expect.
3. **Custom-field operator set** *(confirm)*. Proposed per-type operators are in
   the AST table. Open: should `text` support `startsWith`/regex? Should
   `number` `between` be inclusive (proposed: yes, `BETWEEN`)? Should `choice`
   `in` be offered in v1 UI or deferred?
4. **Section-label format** *(low risk)*. Reuse `PhraseStructure.labels`
   (`A1 A2 B1 B2 …`) verbatim as the `section` string. Non-standard structures
   (`6*8*2`) yield `A1 A2 B1 …` per the existing `labels` rule. Confirm no
   separate canonical section vocabulary is wanted.
5. **Mixing `FullTextFilter` with structural leaves** *(confirm)*. Freely allowed
   under `AndFilter`/`OrFilter` at dance level (each compiles independently); disallowed
   **inside `ThenFilter`** per Q1. Confirm.
6. **`bm25` relevance vs. metadata sort** *(settled for v1)*. Relevance ordering
   is offered only for a bare short Omni `FullTextFilter`; scoped,
   long-substring, and other trees use the fixed sort allow-list. A blended
   ranking can be revisited later.
7. **Multi-tag facet semantics** *(minor)*. When the user picks several tags in
   the Tag facet: AND (has all) or OR (has any)? Proposed: OR within a single
   facet, AND across facets (standard faceted-search behaviour).
8. **Migration rebuild wiring** *(implementation, 3.2b)*. Whether the v2
   backfill runs `rebuildAllDerived()` from within `onUpgrade` (needs
   repository/taxonomy access) or via inline SQL + a post-open integrity pass.
   No user-facing behaviour difference; noted so 3.2b picks the cleaner wiring.

## Deferred to later PRs

- **3.2b** — core: the `DanceFilter`/`FigureQuery` types, `FilterCompiler`,
  the v2 migration + column + indexes, the migration test, the benchmark
  harness, and repository entry point (`search(DanceFilter) → List<String>`
  ids, reusing the 3.1 ordering plumbing).
- **3.2c** — app: the unified FTS bar + facet chips + Advanced tree builder,
  wired to the compiler, with AT-announced result counts.

## Future leaves (CC parity backfill, ROADMAP 4b)

*Not part of 3.2; recorded so the AST/compiler grow consistently when the
dance-model backfill lands (design/domain-model.md "CC parity backfill").*

- Optional `composedOn`/`revisedOn` become scalar leaves + sort keys if those
  land as core columns rather than custom fields.
