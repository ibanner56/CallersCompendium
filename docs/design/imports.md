# Design: Import pipeline

*Roadmap item 1.10 · v0.1 (2026-07-10). Covers the source-adapter framework
(6.1) and per-source plans (6.2–6.6).*

## Pipeline

Every import, regardless of source, flows through the same stages:

```
fetch → RawRecord → parse → StructuredDraft → canonicalize → dedupe → review → commit
```

| Stage | Contract |
|---|---|
| **fetch** | Adapter obtains bytes (file pick, URL, snapshot archive). Never blocks on network for local work. |
| **RawRecord** | Source-native payload preserved verbatim + source id/version → stored in `provenance.raw_payload`. Re-import/diff is always possible. |
| **parse** | Adapter maps fields and parses figures into structured `Figure[]`. **Parsing never fails a dance**: any unparseable figure line becomes a `custom` figure carrying its beats and text. A dance can arrive 100% custom and still be searchable. |
| **canonicalize** | Free text through the dialect `canonicalize()` chokepoint; terms/synonyms (incl. legacy "gypsy") mapped to canonical vocabulary; formation strings mapped to the enum (+detail). |
| **dedupe** | Match by (source, externalId) first — re-import updates provenance and offers diff. Otherwise fuzzy (normalized title + author) → user chooses link/duplicate/skip. Free-text imports feed their raw author names (see *Author resolution*) into this signal. An exact-normalized-title match with an overlapping tokenized author set is always a **confident match** (`DedupeCandidate.confident` / `DedupeVerdict.hasConfidentMatch`, issue #685) — it is guaranteed to surface as `ambiguous` regardless of how the score threshold is tuned, so inconsistent author-string formatting across sources can never silently resolve to `isNew`. Non-interactive callers (e.g. program import) treat a confident match as a hard **skip**, never a silent duplicate (see *Multi-author tokenization*). |
| **review** | Batch imports land in a review queue: per-dance parse quality score (% structured vs custom figures), side-by-side raw vs parsed. Accept-all is one tap; nothing silently mutates existing user data. |
| **commit** | Transactional; provenance row written; author names resolved to `Choreographer` associations (see *Author resolution*); import session log kept for undo. |

Adapters implement a small interface (`discover() / fetch() / parse()`) in the
pure-Dart core → each adapter unit-tested against fixture files.

## Author resolution (resolve-or-create seam)

Free-text sources (CallersBox, ContraDB — JSON and HTML — and Caller's Companion
text + `.USR`) supply author/choreographer **names**, not stable ids. Each adapter
carries those names verbatim on `StructuredDraft.authorNames` (in order, blanks
dropped) and **never fabricates ids** — names are data, not a parse failure. The
pipeline resolves them to real `Choreographer` associations (`Dance.authorIds`) at
**commit**:

### Multi-author tokenization (issue #685)

Every adapter that can carry more than one name in a single field (a
choreographer string, an `Authors[]` array element, a "by" line, `Author1`/
`Author2`) routes through **one** canonical splitter,
`splitAuthorNames()` (`packages/compendium_core/lib/src/imports/author_tokenizer.dart`),
instead of each adapter doing its own ad hoc split. Before this fix, mismatched
per-adapter tokenization (or no splitting at all) could make a re-imported
dance's author set score `0` similarity against the same dance already in the
collection — and combined with any title variance, that was enough to fall
below the dedupe threshold and silently create a duplicate.

`splitAuthorNames()` policy:

1. **Comma pass with suffix protection** — plain (non-regex) comma split,
   but a leading fragment that looks like a name suffix (`Jr`, `Sr`, `II`,
   `III`, `IV`, case-insensitive, optional trailing `.`) is re-attached to the
   previous name instead of starting a new author (`"Jane Doe, Jr."` stays one
   name; `"Jane Doe, Jr. and Bob Smith"` → `["Jane Doe, Jr.", "Bob Smith"]`).
   This is a deliberate trade-off: it protects the common suffix case at the
   cost of never treating an *actual* two-name comma-list entry as ambiguous
   with a suffix — accepted per the issue.
2. **Other-delimiter pass** — each comma-fragment is further split on `/`,
   `&`, `+`, `;`, or the whole words `and`/`with` (case-insensitive,
   word-boundary — so `Andy Davis` or `Ann Withers` are not over-split). The
   delimiter regex is a single fixed alternation with no repetition on
   attacker-controlled input, so it is **linear-time / ReDoS-safe** by
   construction (no nested or overlapping quantifiers).
3. Each resulting token is trimmed, re-sanitized (`sanitizeImportedText`,
   preserving the existing bidi/zero-width stripping from #444/#611 — a
   hostile field can't hide a spoofing character inside what used to be one
   opaque blob before splitting exposed the substring boundaries), and empty
   tokens are dropped.
4. Tokens are de-duplicated case/whitespace-insensitively within one call
   (first-seen casing wins), preserving order.
5. **Caps, never throws.** Each raw field is capped at `maxFieldLength`
   (default 500) chars before splitting, and the combined author list per
   record is capped at `maxAuthorsPerRecord` (default 20). Either cap firing
   truncates (rather than raising) and appends a non-fatal `ImportIssue`
   (`author_field_truncated` / `author_count_capped`) — untrusted remote
   input can never crash or hang an import (OWASP: fail closed, no raw
   parser detail surfaced to the UI).
6. The **raw, unsplit** field is always retained verbatim in
   `RawRecord.payload`/provenance — splitting only affects the derived
   `authorNames`, nothing is lost for re-import/diff.

Acceptance: the same multi-author dance imported from Caller's Box (an
`Authors[]` array) and from ContraDB (a single combined string) now normalizes
to the **same** author set, so dedupe's author-overlap signal is consistent
across sources regardless of which adapter produced it.

- **Matching policy — exact, normalized, conservative.** A name matches an existing
  `Choreographer` iff its normalized form (trim → collapse internal whitespace →
  lowercase) equals an existing row's normalized name. **Punctuation is significant**
  (never stripped) and there is **no fuzzy matching** (v1): a wrong merge
  (miscrediting a dance) is worse than an occasional near-duplicate row. The seeded
  `Traditional`/`Unknown` rows are ordinary rows — a name normalizing to them
  matches and is reused, with no special-casing.
- **Create path.** A name with no match mints a new id and inserts a name-only
  `Choreographer` (no website/email). Blank/whitespace-only names are skipped
  entirely; a name repeated within one record collapses to a single authorship
  entry.
- **Batch de-dup.** A single normalized-name → id map is seeded from the collection
  at the start of a commit and newly-created ids are added to it live, so two dances
  crediting the same new author in one batch resolve to **one** created row.
- **Re-import/link replaces authors.** Because re-import overwrites the dance's
  content wholesale, it also **replaces** the resolved author list — a manually-added
  co-author on the target dance is dropped on re-import.
- **Undo.** The import session tracks the ids of choreographers it created. Undo
  hard-deletes inserted dances (cascading away their `dance_authors` rows) and
  restores updated dances, then removes each created choreographer — but only those
  no surviving dance still references (the repository's referenced-guard is
  respected). Pre-existing choreographers are never touched.
- **`callingNotes` behavior change.** Author names are **no longer folded** into
  `Dance.callingNotes`, and the old per-name `*_unresolved` info issues are removed;
  authorship now lives in `Dance.authorIds`. The per-record resolution outcome
  (matched vs created, per name) is surfaced structurally on
  `CommittedRecord.authorResolutions` for the review step.

### Dedupe confident-match guarantee (issue #685)

`DedupeIndex.fuzzyMatches` always includes a candidate whose normalized title
is exactly equal to the incoming record's **and** whose tokenized author set
intersects it (`DedupeCandidate.confident = true`), even when its combined
score would otherwise fall under the active threshold. `DedupeVerdict.
hasConfidentMatch` exposes this at the verdict level. This is a deliberate,
future-proofed guarantee, not a threshold-tuning accident: an exact-title +
shared-author pair can never resolve to `isNew` (and therefore never silently
duplicate), regardless of how differently the two sides' author strings were
formatted or tokenized upstream.

- **Interactive path unchanged.** `verdictFor`'s `isNew`/`ambiguous` branching
  and `ImportPipeline.commit`'s "no resolution supplied → skip" default are
  untouched — a confident candidate is, by construction, always present in
  the fuzzy list, so it can never fall through to `isNew` in the first place.
  The interactive review screen still lets the user resolve it (link /
  duplicate / skip) like any other `ambiguous` candidate.
- **Non-interactive path defaults to skip (Option 2, locked).** Callers with
  no user present to disambiguate (the program-import resolver, see below)
  treat `hasConfidentMatch` as a hard skip rather than importing a fresh
  dance or forcing a `duplicate()` resolution.
- **Seam for #686.** `confident`/`hasConfidentMatch` is deliberately exposed
  as plain data with no UI/behavior branching baked into `dedupe.dart` — issue
  #686 will layer a richer resolution (a figure-diff "variation?" prompt) on
  top of this same trigger without needing to touch this file's scoring
  logic again.

### Program-import path (issue #685)

The non-interactive program-import resolver
(`app/lib/src/data/program_import_online_resolver.dart`,
`resolveConfidentOnlineDanceId`) already runs the previewed online dance
through the full local `DedupeIndex` via `OnlineSearchService.loadPreview`
(no second index build needed). Before calling `OnlineSearchService.import`,
it now checks `preview.plan.verdict.hasConfidentMatch` and returns `null`
(leaving the program line on the existing note-slot fallback) instead of
importing. This is intentionally **not** the same as the interactive
`CallersBoxOnline`/`ContraDbOnline.import` behavior, which forces a
`duplicate()` resolution on any `ambiguous` verdict — that override is correct
only for the genuinely interactive single-dance "search → tap Import" flow
(an explicit user pick), and would otherwise force-import a confident local
duplicate when reused from a batch/non-interactive path.

## Sources

### 1. CallersBox snapshot (6.2, 6.3) — primary
- Input: hosted NDJSON snapshot (see design/callersbox-snapshot.md) or a
  single dance JSON pasted/downloaded from `dance.php?id=N&format=JSON`.
- Field mapping is direct (research/callersbox.md documents the schema);
  figures parsed by a **TCB grammar parser**: `(beats) text` per line, keyword
  matching against taxonomy `searchKeywords`, parameter extraction for the
  high-frequency moves (swing, balance, allemande, circle, star, chain,
  long lines, right left through, promenade, petronella, do si do, hey…).
  Long-tail/complex notation (per-pass hey lists) falls to custom figures —
  refined iteratively; parser coverage is measured against the full corpus and
  reported (target: ≥80% of figure lines structured in first release,
  improving over time). A top-level `||` (simultaneity — "Women allemande
  left 1 || Men orbit clockwise ½") is no longer opaque custom text: it fans
  out into a `meanwhile` container carrying the shared beat count, with each
  side independently run back through the same per-side parser (#591; see
  "Simultaneous-action fan-out (`meanwhile`)" below).
- `Permission: search` stubs import as metadata-only with a link to TCB.
- Attribution: TCB id + appearances retained; UI shows "via The Caller's Box".

#### Compound figures (the `(beats) Name:` + indented-children convention)

TCB sometimes expresses one named figure as its **decomposition**: a parent
line `(beats) Name:` (trailing colon) followed by **indented** child lines
`(beats) …` whose beats **sum to the parent's**. The children are the
*definition* of the parent move, **not** additional choreography. For example
*Right Where We Belong* (#19001) A1 is:

```
(6) Revolving door:
     (4) Partner star promenade 1/2 (WR)
     (2) Women allemande right 1/2
(10) Neighbor swing
```

Parsing each line independently double-counts A1 (6 + 4 + 2 + 10 = 22 instead
of the true 16). A **compound pre-pass** in `callersbox_adapter.dart` (which
sees the raw, still-indented lines before `parseFigureLine` trims them) groups
such a unit and collapses it to **exactly one** `Figure`:

- **Known parent** (the parent name structures to a single taxonomy move, e.g.
  `revolving_door`) → emit that structured figure carrying the **parent's**
  beats; children are subsumed.
- **Unknown parent** → one `customFigure` with the parent text (colon stripped)
  and the parent's beats.
- Children are **never** re-emitted as separate figures; their scrubbed source
  decomposition is preserved in `Figure.note` so nothing is lost.

**Confidence guard (tolerant / OWASP).** The collapse fires only when there is
≥1 indented child, the parent beats are numeric and > 0, and the children's
beats sum **exactly** to the parent's. If beats are missing/non-numeric,
indentation is malformed or absent, or the sum doesn't match, the pre-pass
**declines** and the lines flow through the ordinary per-line path unchanged.
Grouping is single-level and bounded (deeper nesting simply fails the exact-sum
guard → safe decline); the untrusted TCB payload can never crash the parse.

### 2. Caller's Companion migration (6.5)
- Input: user's `CallersCompanion2.USR` (FileMaker 12 container).
- Approach: FM12 parser (fmptools-style) extracting the `Dance`/`Set`/`SetItem`
  **and `Phrase`** tables. The figure transcription lives in the separate
  **`Phrase` table** (`PhraseText`, keyed by `zk_Dance_ID` + `PhraseNumber`
  A1..C2), not the `Dance`-row `A1..C2` columns (empty in real files), so
  `extractCcUsrArchive` joins `Phrase` per dance (grouped by `zk_Dance_ID`,
  ordered A1→A2→B1→B2→C1→C2 then others; primary `PhraseText` only — the
  gender-swapped `PhraseText_GenderSwap_*` variants are ignored) and populates
  each dance's body from it. The `Dance`-row `A1..C2` path is kept as a
  **fallback** for exports that carry it and for the CC text adapter. Each body
  line is routed through the **shared free-text fan-out**
  (`parseFigureLinesFanOut`: ContraDB > TCB > CC) — every line with content
  after scrubbing is retained: recognised moves structure into taxonomy
  figures, the rest as `importGap` customs (parse-never-fails); a line that is
  empty after scrubbing yields nothing (nothing to store). Sets → Programs; user
  fields → notes.
- Adapter wiring note: the `.USR` adapter round-trips each dance through a JSON
  `columns` payload. The `Phrase` body is **not** in that per-dance column map,
  so the joined body is threaded through the `discover → fetch → parse` payload
  explicitly (legacy payloads without it fall back to the `A1..C2` columns).
- Beat-prefix parsing (#560): each body line's leading beats prefix is peeled by
  `splitCcBeatPrefix` before the fan-out. It accepts a lone `(16)`, a **compound**
  `(4,12)` / `(4, 12)` (whitespace-tolerant, each group ≤ 4 digits, mirroring the
  free-text inline-beat cap), and a bare/absent prefix (beats `0`); a **malformed**
  prefix (`()`, `(x)`, `(4,)`, `(,12)`) does not match and is left as ordinary text
  (`parse-never-fails`). **Compound-beat semantics:** a compound's parts **sum** to
  the line total; a line that structures as a **single** figure (e.g. balance-and-
  swing is one swing) carries that **total**, whereas a line the fan-out cleanly
  **splits** into exactly as many non-custom figures as parts has each part
  **distributed** in order. Any other case (part-count ≠ figure-count, or a custom
  fallback) keeps the splitter's Option-A allocation (total on the first figure),
  which is always lossless w.r.t. the cumulative total and never invents an
  allocation the source did not state.
- Security hardening (#561, OWASP — do not trust because it's local/community):
  the `Phrase` table is newly-surfaced untrusted free text + rows, so it is
  guarded consistently with the `.USR` reader's existing bounds.
  - **Sanitized at the ingestion boundary.** Every body line is scrubbed via
    `sanitizeImportedText` (single-line, issue #444) during the incremental line
    walk (`_appendCappedBodyLines`) *before* it reaches a `CcBodySection`, so
    control/bidi-override/invisible
    format spoofing characters can never enter the joined body, the persisted
    JSON payload (`provenance.raw_payload`), or storage — defense in depth ahead
    of the parser's own `scrubFigureText` chokepoint (idempotent, no double-mangle).
  - **Bounded fail-closed.** `FmpReadLimits` gains CC-layer caps enforced in
    `extractCcUsrArchive`: `maxPhraseRows` (default 20 000; sample is 162) and
    `maxFiguresPerDance` (512) throw `FmpResourceLimitException`, which the
    adapter's `discover` maps to the friendly "That file is too large to
    import." — never OOM/throw-through. `maxBodyLineLength` (2 000 chars, matching
    the local `maxFreeTextEntryLength`) is the exception: a single over-long line
    is **dropped with a warning**, not fatal — mirroring the free-text-entry path
    so one over-long line can't abort a 40-dance import (the O(1) check does no
    unbounded work; the aggregate caps are the real DoS guard).
  - **Untrusted joins degrade, never throw.** A `Phrase` row with a
    missing/empty `zk_Dance_ID`, or an orphan id matching no `Dance`, is dropped
    with a warning; duplicate keys are grouped. (`Elements` is not ingested yet —
    #563 — so nothing to harden there today.)
- **Program-import parity (#611).** The #444/#561 `sanitizeImportedText`
  defense originally only covered dance imports; program imports (this CC
  `.USR` `Set`/`SetItem` → `Program` builder in `callers_companion_programs.dart`,
  and the ContraDB program HTML parser in `contradb_program.dart`) now route
  every imported free-text field through the same sanitizer at parse/build
  time — single-line fields (title, venue, band, caller, dancer level, guest
  caller, contributor) with `allowLineBreaks: false`, multi-line prose (notes,
  break text, program notes) with the default — so a program title or note
  can no longer carry bidi-override/zero-width spoofing characters into
  storage, matching the dance path exactly.
- **Shorthand seeding from `InsertCall` (#562).** After the dance/program commit,
  the review flow offers an **opt-in, previewed** step that turns CC's shipped
  default "call buttons" (`InsertCall`: label → call text + beats, with an ALT
  form) into figure shorthands (#420). Per maintainer direction we target the
  shipped defaults **as-is** — there is no user-vs-default discriminator. Core
  (`extractCcUsrArchive` → `insert_call_shorthands.dart`) reads `InsertCall` via
  the same tolerant table/column resolver, sanitizes each label/text through
  `sanitizeImportedText`, bounds the scan (`FmpReadLimits.maxInsertCallRows`,
  default 20 000), and — for each button whose text structures through
  `parseFigureLinesFanOut` to **non-custom** taxonomy figure(s) — builds a
  `ShorthandSeedCandidate{token = label, figures}`. Buttons that only parse to
  `custom` seed nothing (no raw-text shorthands). Where the ALT slot is a
  *distinct* call that also structures, it is offered as a **selectable alternate
  expansion for the same token** (CC toggles the two under one button; a shorthand
  token is unique, so exactly one mapping persists per token). Candidate figures,
  token length, and total count honour the shorthand-store bounds
  (`maxShorthandTargetFigures`/`maxShorthandTokenLength`/`maxShorthandMappings`),
  and candidates dedupe on the normalized token. The app step (`ImportShorthandSeedScreen`)
  previews each candidate's rendered figures; the user picks which to seed (and
  primary vs. alt). Tokens that collide with an **existing** shorthand are
  surfaced in a read-only "already defined — skipped" section — never overwritten
  — which also makes **re-import idempotent** (a second import of the same file
  finds those tokens present and adds nothing). Declining seeds nothing.
- Follow-ups: approximating dialect from `Elements`/button phrasing (#563).
- Fixture: the publicly downloadable demo `.USR` (kept out of the repo until
  redistribution permission is clarified; local test asset otherwise). CI runs
  against hand-built `.fmp12`/`FmpDatabase` fixtures shaped like the real schema.
- Fallback: parse CC's "copy formatted dance" clipboard/text format for
  one-at-a-time migration.

### 3. ContraDB (6.4)
- Input: the **server-rendered HTML** at `contradb.com/dances/N` (the page a
  normal visitor sees), parsed by `ContraDbHtmlAdapter`. ContraDB serves **no
  JSON** (`dances/N.json` → HTTP 406, no public API), so the rendered page is the
  only path a user can actually reach; they import a dance by pasting its URL.
  The adapter walks the dance table rows into `(section-label, beats, figure-text)`
  and routes each figure line through the shared free-text parser.
- A second, **deprecated** adapter (`ContraDbAdapter`) maps ContraDB's internal
  `figures_json` positional move/parameter model move-for-move onto our taxonomy
  (positional→named table per move, gyre → shoulder_round term migration). It is
  **`@Deprecated` and wired into no live path** — that JSON input is unobtainable
  from the site — and is retained only as reference prior art plus its unit tests.

### 4. Generic JSON (6.6)
- Our own canonical export format (full fidelity: figures, programs, custom
  fields, provenance, dialect definitions). Serves backup/restore and
  user-to-user sharing. Versioned schema; forward-compatible reader.

### Simultaneous-action fan-out (`meanwhile`) (#591/#572)
- Two source dialects write simultaneous action on one line instead of
  splitting it into two: CallersBox's `||` operator (e.g. `(6) Women
  allemande left 1 || Men orbit clockwise ½`) and ContraDB free-text prose
  joined by `while`/`whiles` (e.g. dances #1717, #1603, #326: `"ladles
  allemande left 1½ around while the gentlespoons orbit clockwise ½
  around"`). Both fan into the core model's `Figure.meanwhile` container
  (#590) instead of one opaque whole-custom figure.
- **CallersBox `||`:** `meanwhileFromDoublePipe`
  (`imports/callersbox_figure_dialect.dart`) splits the line on a top-level
  `||` (bracket-depth aware, mirroring the existing `;`-compound splitter),
  parses each side independently through the normal per-side `parseFigureLine`
  front-end, and builds the container with the line's single combined beat
  count. `parseFigureLines` calls it before falling back to the pre-#591
  whole-custom behaviour.
- **ContraDB `while`/`whiles`:** `parseContraDbFigureLine`
  (`imports/contradb_figure_dialect.dart`) runs the FULL existing recognizer
  pipeline first — so a line matching a dedicated named combined move (e.g.
  `box_circulate`) is returned completely unmodified, with named-recognizer
  precedence fully preserved (the box-circulate dual-clause form is a
  regression case, not a fan-out). The ContraDB combined
  `allemandeOrbitWords` line (dance #1717) is the one exception: since the
  fused `allemande_orbit` move was retired (issue #295), it is resolved by
  `_allemandeOrbitMeanwhile` into a `meanwhile[allemande, orbit]` container —
  handled right after the generic parse and preferred over it, so it keeps the
  same first-crack precedence while emitting a container. Only when the
  whole-line attempt degrades to custom — or its captured note
  swallowed a top-level `while`/`whiles` connective (mirrors the pre-existing
  `_noteSwallowedCompound` guard for `||`/`;`) — does it attempt a
  word-boundary split (`\bwhiles?\b`, so "whiles" is never cut mid-word) and
  build a `meanwhile` container from the two sides.
- **Prefer-custom, never fabricate:** each side is independently parsed by the
  same per-side front-end used for the whole line; a side that doesn't
  recognize becomes its own custom sub-figure — nothing is dropped or
  invented. The container itself is built with a direct `Figure.meanwhile(…)`
  call in the import-layer wrapper, bypassing `parseFigureLine`'s taxonomy
  `validateFigure` step entirely: `meanwhileMove` is a structural id (like
  `customMove`) that is deliberately unregistered in the taxonomy, so routing
  it through `validateFigure` would always reject it.
- **Defensive bounds on untrusted input (OWASP):** side counts are clamped to
  `2..kMaxMeanwhileSides` at the import layer — a hostile/malformed line with
  more separators than the model allows safely degrades to the pre-#591
  whole-custom fallback rather than throwing or silently truncating sides.
  Sides are never themselves `meanwhile` (flat only), so the model's
  recursive-nesting defenses stay reserved for the untrusted deserialization
  path. Each side is scrubbed via the same `scrubFigureText` pass as any other
  figure line, so bidi/zero-width sanitization parity (#444/#611) holds
  per-side by construction.
- **Shared beats, counted once:** the source states one combined beat total
  for the whole line, never per-side — it lands on the container's `beats`
  only (sides carry none), so `deriveSections` cumulative totals stay
  byte-identical to the pre-#591 whole-custom line.
- **Reparse upgrade:** the singular fan-out (`parseFigureLineFanOut`,
  `imports/reparse_custom_figures.dart`) gets the same `||`/`while` fan-out,
  so an old import-gap custom that predates #591 upgrades to a `meanwhile`
  container the next time reparse runs — the same low-risk mechanism already
  used to upgrade old customs when recognizer coverage improves.

### Shared free-text figure parser (cross-cutting)
- All four free-text adapters (CallersBox, ContraDB-HTML, CC-text, CC-`.USR`)
  route their `(beats) text` figure lines through one pure-Dart core parser,
  `parseFigureLine` (`imports/figure_parser.dart`), instead of each emitting
  `custom` directly. It runs **after** dialect scrubbing (`scrubFigureText` →
  `canonicalizeText(…, Dialect.canonical)` + the `gypsy`→`shoulder round`
  safety net), so recognition sees canonical `role1`/`role2` tokens.
- **Conservative, whole-line, single-move matching.** A line structures only
  when exactly one covered move plus its recognized modifiers (dancer set,
  direction, hand/shoulder, rotation/fraction, places) account for the *entire*
  line; any leftover prose forces the `custom` fallback. Every structured
  candidate is validated against the taxonomy — an error-severity issue also
  forces custom. A wrong structured match misrepresents choreography, so when
  in doubt it stays custom. **Parse-never-fails** is preserved (unrecognized →
  `custom`, never throws, never drops text); source beats and the progression
  flag are preserved exactly. Section labels (`A1`…) are **not** embedded in the
  figure text — they derive from cumulative beats via the domain model
  (`deriveSections`), and the beat count is already a structured field, so a
  `'$label: $scrubbed'` prefix would duplicate structured data that can drift
  out of sync. Both the structured and custom paths therefore store clean text
  only. (This intentionally drops the previous CallersBox/ContraDB phrase-label
  prefix on custom figures.)
- **First-cut coverage (in):** swing (+balance/meltdown prefix), balance,
  balance the ring, do si do / see saw, shoulder round (+gypsy), box the gnat /
  swat the flea, allemande, circle, star, chain, long lines, right left
  through, pass through, promenade, petronella. **Enriched for CallersBox
  (#553):** roll away, cross trails, figure eight, form (a) long wave(s), trade
  (→ pass by), pass/cross-by left/right (→ pass by), lead down/up & go down/up
  outside (→ down/up the hall `moving`), circulate (→ box circulate, balance
  folded), hall + turn as couples (→ `ender: turnCouple`), pass the ocean +
  trailing balance wave (→ `pass_the_ocean` / `form_a_short_wave` /
  `form_a_long_wave` with `balance: true`, beats summed; #577), diagonal chain /
  hey
  / right-&-left-through (→ `dir: left/rightDiagonal`), same-role right & left
  through (variant kept as a note), weave-the-line `with <dancer>`, relationship
  N-suffix (`with/to neighbor N2`), explicit dancer codes (M1/W1/M2/W2 →
  ones/twos single-dancer identities), and `(A-B)` beat ranges. **Out (→ custom
  for now, tracked on #295):** balance-in-a-wave, cast off, mad robin & butterfly
  whirl (need direction/who params), two-hand turn & other ECD figures, promenade
  CW/CCW around the major set, non-duple formations, and
  anything with leftover prose. Coverage improves iteratively — measured against
  the full corpus (design target ≥80% of lines structured over time). (`||`
  simultaneity is no longer in this list — see "Simultaneous-action fan-out
  (`meanwhile`)" above; it fans into a `meanwhile` container one layer above
  this per-move recognizer, #591.)

## Error handling & testing

- Every stage yields structured errors with source context (never stack-trace
  UX); partial batch failure imports the rest and reports.
- Adapter test fixtures: real TCB JSON samples (id 1, 100, 3418, 10284 cover
  chestnut/Becket/proper/notes cases), CC demo USR, synthetic edge cases
  (empty phrases, `(0)` beats, non-standard phraseStructure, windows-1252
  artifacts, duplicate titles).
- Round-trip property: export→import of our generic JSON is identity.
