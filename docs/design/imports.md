# Design: Import pipeline

*Roadmap item 1.10 · v0.1 (2026-07-10). Covers the source-adapter framework
(6.1) and per-source plans (6.2–6.6).*

<!-- section-index -->
> **Section index.** This document is ~73 KB — read the section you
> need rather than the whole file. Line counts indicate size, not position;
> follow the anchor. Keep this index current when you add or retitle a
> section.

- [Pipeline](#pipeline) — 21 lines
- [Author resolution (resolve-or-create seam)](#author-resolution-resolve-or-create-seam) — 139 lines
- [Sources](#sources) — 952 lines
  - [1. CallersBox snapshot (6.2, 6.3) — primary](#1-callersbox-snapshot-62-63--primary) — 113 lines
  - [2. Caller's Companion migration (6.5)](#2-callers-companion-migration-65) — 97 lines
  - [3. ContraDB (6.4)](#3-contradb-64) — 33 lines
  - [Compound-shorthand fan-out: grand right and left (#295)](#compound-shorthand-fan-out-grand-right-and-left-295) — 186 lines
  - [4. Generic JSON (6.6)](#4-generic-json-66) — 5 lines
  - [Signed published collections (#862)](#signed-published-collections-862) — 22 lines
  - [5. A list of titles (#823)](#5-a-list-of-titles-823) — 72 lines
  - [Simultaneous-action fan-out (`meanwhile`) (#591/#572)](#simultaneous-action-fan-out-meanwhile-591572) — 59 lines
  - [Shared free-text figure parser (cross-cutting)](#shared-free-text-figure-parser-cross-cutting) — 299 lines
  - [Balance-a-wave lines (CallersBox, #295 / taxonomy v21)](#balance-a-wave-lines-callersbox-295--taxonomy-v21) — 86 lines
- [Error handling & testing](#error-handling--testing) — 9 lines
<!-- /section-index -->

## Pipeline

Every import, regardless of source, flows through the same stages:

```
fetch → RawRecord → parse → StructuredDraft → canonicalize → dedupe → review → commit
```

| Stage | Contract |
|---|---|
| **fetch** | Adapter obtains bytes (file pick, URL, snapshot archive). Never blocks on network for local work. |
| **RawRecord** | Source-native payload preserved verbatim in memory + source id/version. The payload feeds `parse` and is **not persisted** — it was stored in `provenance.raw_payload` until schema v21 dropped that column (#781), because nothing read it back. Re-import dedupes on `(source, externalId)` and re-fetches from the source, so it needs no stored copy. |
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

Since #823 this resolver is no longer the only online-title→dance path. The
Collection-side title-list import shares its **search** step
(`lookupUniqueExactTitle`) but not its commit: it is interactive, so it plans
into `ImportReviewScreen` instead of importing unattended. See
[A list of titles](#5-a-list-of-titles-823) below for why that split is where it
is.

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
- **Mixer inference (issue #732).** `Dance.mixer` is set `true` when **either**
  the source `Mixer?` field reads `"Yes"` (trimmed, case-insensitive — the corpus
  contains only `""` and `"Yes"`, so the vocabulary is not widened to `"1"`/
  `"true"`) **or** the mapped `FormationShape` is `circleMixer` or `scatterMixer`.
  The formation-based inference exists because 21 Circle Mixer and 18 Scatter
  Mixer dances in the mirror have a blank `Mixer?` despite the formation name — a
  data-entry omission we correct on import. `sicilianCircle` is **deliberately
  not** inferred: 589 of the corpus's Sicilian Circles are correctly non-mixers,
  so inferring from that shape would mislabel them wholesale (the opposite error).
  A Sicilian Circle that genuinely is a mixer is still caught, but only via its
  explicit `Mixer? == "Yes"`.
  - **Scope: The Caller's Box only.** This inference is **not** applied by the
    ContraDB or Caller's Companion adapters, and that is deliberate. ContraDB has
    no first-class mixer category to read. Caller's Companion *may* — Chris builds
    his collection in CC and exports it to The Caller's Box, so his data probably
    aligns, but "mixer" may be a custom field of his rather than a native CC
    concept, and we have not confirmed which. Rather than guess a mapping for a
    source we have not verified, those adapters leave `mixer` at its `false`
    default. This was considered and declined, not overlooked; revisit if an
    explicit request for those sources arrives.

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
such a unit and reads it in one of three ways, in order:

- **Known parent** (the parent name structures to a single taxonomy move, e.g.
  `revolving_door`) → emit that **one** structured figure carrying the
  **parent's** beats; children are subsumed and their scrubbed decomposition is
  preserved in `Figure.note`.
- **Unknown parent whose children ALL structure (#295)** → emit the
  **children**, each carrying its own source-stated beats. The parent is a
  shorthand the taxonomy deliberately does not model but TCB decomposes itself
  into moves we already have. The exact-sum guard already proves the children
  total the parent, so section beats are byte-identical to the collapsed
  reading.

  This rule is **general, not figure-specific**: measured over the full corpus
  it fires on **877 compound blocks across 81 distinct parent names**. The
  largest families are `interrupted square through 2`/`… 4` (331 blocks),
  `modified right and left through with partner/neighbor` (141),
  `flutterwheel` (135 — `(8) Neighbor flutterwheel:` == `(4) Women allemande
  right ½` + `(4) Neighbor star promenade ½ (WR)`), `open ladies/gents chain`
  (66), `georgia rang tang` (47) and `hey along sides` (34), with a long tail
  covering `allemande x`, `catch all eight`, `do paso`, `dixie style to a wave`,
  `modified revolving door`, `vicious circle` and others.

  **The parent's shorthand name is preserved as a `note` on the FIRST child**,
  verbatim after scrubbing. That note is load-bearing at this breadth: it is
  what keeps a choreographically meaningful qualifier — the "interrupted" in
  `Interrupted square through 2`, the "modified" in `Modified right and left
  through with partner`, or a whole name like `Georgia Rang Tang` — from
  vanishing when the block is expressed as its parts. It is never truncated or
  normalized away (only `scrubFigureText`'s repo-wide gendered-term
  canonicalization applies, exactly as on any other stored text).
- **Anything else** → one `customFigure` with the parent text (colon stripped)
  and the parent's beats, the scrubbed decomposition in its `note`. This is the
  fallback whenever **any** child fails to structure, so a block is never
  emitted half-structured (e.g. `(12) Grand partner flutterwheel:`, whose
  `(4) Women star right ½` child does not structure, stays whole-custom).

**Confidence guard (tolerant / OWASP).** The collapse fires only when there is
≥1 indented child, the parent beats are numeric and > 0, and the children's
beats sum **exactly** to the parent's. If beats are missing/non-numeric,
indentation is malformed or absent, or the sum doesn't match, the pre-pass
**declines** and the lines flow through the ordinary per-line path unchanged.
Grouping is single-level and bounded (deeper nesting simply fails the exact-sum
guard → safe decline); the untrusted TCB payload can never crash the parse.

Both the parent line and its children accept a `(START-END)` beat span (the same
inclusive `END - START + 1` rule `_beatsPrefix` uses), because TCB writes
positioned/simultaneous compounds that way — e.g. `(7-12) [Top two couples]
Neighbor flutterwheel:`. `_beatsPrefix` gained span support in #555 but
`_compoundParent` did not, so until #295 such a block was **not recognised as a
compound at all**: the parent became its own figure *and* its children were
emitted alongside it, so the block contributed parent + children beats
(6 + 6 = 12 instead of 6) and every later section label drifted. Both patterns
now share the one rule; a backwards span (`(12-7)`) yields 0 beats and safely
declines the collapse.

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
    format spoofing characters can never enter the joined body, the in-memory
    JSON payload, or storage — defense in depth ahead
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
- **`star promenade` is DECLINED, not mapped (taxonomy v26, #843).** ContraDB's
  `who`+`hand` name, as a pair, the dancers with a hand in the CENTRE. Our `who`
  names the dancer you PICK UP on the side (owner ruling, 2026-08-06), and the
  pick-up relationship is not recoverable from the centre role, so structuring
  the line would assert the wrong dancers. These lines therefore reach the custom
  fallback, which keeps ContraDB's own wording (scrubbed, so role terms are
  canonicalized — see `figure_parser.dart`'s `declineToCustom`) — a deliberate,
  owner-accepted structure regression.

  **Deleting the recognizer was not sufficient, and this is the general lesson.**
  The shared recognizers in `figure_parser.dart` are source-neutral: a grammar a
  dialect file removes can still be claimed by the shared layer, silently. So
  `contraDbHtmlFigureFrontEnd` carries an explicit `declineToCustom` veto (a
  `FigureFrontEnd` hook added by the same change), which runs ahead of every
  recognizer. The deprecated JSON adapter's `_MoveMap` entry is removed too, so
  both producing paths are closed.

  The number of ContraDB dances that lose structure is **not measured**: no
  ContraDB corpus or dump exists locally, and none is documented in
  `docs/research/contradb.md`.

### Compound-shorthand fan-out: grand right and left (#295)

Some source shorthands are best represented as a **sequence of moves we already
have** rather than as a new taxonomy move. `Grand right and left` is the
reference case, and the evidence is a single dance transcribed in **both**
sources — *334* by Diane Silver:

| | A1 | A2 |
|---|---|---|
| TCB #10042 | `(4) N1 neighbor balance (RH)` · **`(4) Grand right and left (N1R;N2L)`** · `(4) N3 neighbor balance (RH)` · `(4) N3 neighbor box the gnat` | **`(4) Grand right and left (N3R;N2L)`** · `(12) N1 neighbor swing` |
| ContraDB #3403 | `[6] 1st neighbors balance & pull by right` · `[2] 2nd neighbors pull by left` · `[8] 3rd neighbors right hand balance & box the gnat` | `[2] 3rd neighbors pull by right` · `[2] 2nd neighbors pull by left` · `[12] 1st neighbors swing` |

ContraDB carries **no** grand-right-and-left figure at all (its ~61-figure
index), but it does carry `pull by dancers` / `pull by direction` — both already
in our taxonomy. A2 settles the beats too: TCB's 4 beats over 2 passes is
ContraDB's 2 + 2. So **no `grand_right_and_left` move is added**;
`grandRightAndLeftFromPassList` (`imports/callersbox_figure_dialect.dart`)
lowers the line onto one `pull_by_dancers` per stated pass, carrying that pass's
`who` and `hand`.

- **Where it runs.** `parseFigureLines`' no-top-level-separator fall-through,
  i.e. after the `||` (meanwhile) and `;` (clause-split) branches decline. A
  `FigureMatch` pre-recognizer can only return ONE move, so this cannot live in
  `tcbFigureFrontEnd.preRecognizers`. Running it only on that fall-through is
  deliberate: `Grand right and left (N1R;N2L); face across` keeps its
  whole-custom reading instead of silently dropping the trailing clause. The
  plural free-text fan-out (`parseFigureLinesFanOut`) inherits it; the
  **singular** reparse path (`parseFigureLineFanOut`) returns one figure and so
  cannot host an N-figure fan-out — the same limitation the `;`-splitter has.
- **Pass codes** are decoded with the SAME people-code map the hey pass-list
  decoder uses (one notation, one map). Glossary-backed:
  `N`/`N1`→`neighbors`, `N0`→`prevNeighbors`, `N2`→`nextNeighbors`,
  `N3`→`thirdNeighbors`, `N4`→`fourthNeighbors`, `P`/`P1`→`partners`,
  `P0`→`prevPartners`, `P2`→`nextPartners`, `P3`→`thirdPartners`,
  `P4`→`fourthPartners`, `P5`→`fifthPartners`,
  `S`/`S1`→`shadows`, `S2`→`secondShadows`, `M`/`W`→`role1s`/`role2s`.
  ContraDB reaches the same ordinal tokens by a different route (issue #945):
  its deployed `dialectForFigures` renders `3rd neighbors`/`4th neighbors`/
  `2nd shadows` unconditionally, and — only when a dance uses one of
  those — remaps plain `neighbors`/`next neighbors`/`shadows` to
  `1st neighbors`/`2nd neighbors`/`1st shadows` for every figure in that
  dance. `contradb_figure_dialect.dart`'s `_subjectPhrases` maps all six
  rendered forms back to these same taxonomy tokens, so the two dialects are
  visibly one convention despite the different surface notation.
- **Codes we deliberately do NOT map** (the run is declined rather than
  approximated — what that costs depends on the decoder: the line goes custom
  where the run IS its structure, as in a hey or a grand right and left, but
  merely keeps the taxonomy's defaults where the run only ADDS params, as in
  `square_through` since #799 and every side-slot move since #843): `C1`–`C3` — TCB's *"Corners (square)"* ("the non-partner next
  to you… the person across from you… the remaining person") are a **different
  concept** from its separate *"First/second corners"* entry, which is what
  `firstCorners`/`secondCorners` model; `P6`+/`P-n` (mixer partners beyond the
  modelled depth); `N5`+/`N-1`/`N-2`, `S3`+/`S-n`; `Ph*` (phantoms),
  `TB*` (trail buddy), `SR*`; and a bare `R`/`L` cell, which states a hand but
  no dancer.
- **Whole-line strictness.** The text outside the pass list must be exactly
  `grand right and left` (modulo filler), so `Progressive grand right and left`
  (its own glossary figure), `Same-role grand right and left`, `… to place`, a
  `[with N2]` qualifier and any second parenthetical all stay custom.
- **Beats: even split, or decline.** Each pass gets `beats ~/ passCount`, and a
  line whose beats do **not** divide evenly stays custom — an uneven split would
  invent a per-pass duration the source never states. The emitted figures
  therefore sum **exactly** to the source total, so `deriveSections` is
  unaffected. Exactly one corpus line hits the decline
  (`(8) Grand right and left (N0L;N1R;N2L)`).
- **Shorthand preserved.** The first emitted pass carries the note
  `grand right and left`, so the caller-meaningful name stays searchable.
- **Security (OWASP).** Imported text is untrusted: the fan-out is capped at
  `kMaxPassListCells` (12; the corpus maximum is 8), mirroring
  `kMaxMeanwhileSides`. Over the cap — or on any malformed input — the line
  degrades to the unchanged whole-custom figure, never an unbounded fan-out or a
  throw.
- **Corpus outcome:** 128 of the 353 `grand right and left` lines decompose; the
  rest decline honestly (163 on an unmappable code, 56 on leftover prose, 3 with
  no pass list, 2 degenerate, 1 on non-divisible beats). Whole-corpus structured
  share, with the compound-children change below: **75.09% → 76.24%**.

#### The unified `gate` (taxonomy v22)

`gate` and `rotation_gate` are ONE move now, and the two importers fill
**different, non-overlapping halves** of it — which is the whole reason the
merge is lossless:

| slot | ContraDB | The Caller's Box |
|---|---|---|
| `who` (extends a hand, **backs up**) | `subject_pair` | — |
| `whom` (**walks forward**) | `object_pairs_or_ones_or_twos` | the `(ones forward)` annotation |
| `pair` (the pairing you gate **with**) | — | `Neighbor`/`Partner`/`Shadow`/`N2 neighbor`… |
| `direction` (cw / ccw / **mirror**) | — | stated |
| `turn` (amount) | — | stated |
| `face` (the **ending facing**) | `gate_face` | — |

- **TCB's subject goes to `pair`, never `who`.** libfigure `figure.js:844` says
  ContraDB's subject backs up while its object walks forward, and
  `chooser.js:114` shows the subject domain (`chooser_pair`) cannot even hold
  `neighbors`/`partners`. TCB names the pairing, not a side, so reusing `who`
  would silently reinterpret every imported TCB gate. (Same class of bug as the
  `mad_robin` `who`/`whom` split.)
- **Nobody guesses the ending facing.** ContraDB states it literally
  (`figure.js:841` emits the words "to face"); TCB never states one for a gate,
  so `face` stays `unspecified` for the user to fill in. It is no longer derived
  from rotation geometry — that derivation assumed a nominal across-the-set
  start and was wrong after any orientation-changing figure (see
  `docs/design/figure-taxonomy.md`).
- **The TCB `(ones forward)` annotation is no longer lost.** 82 of the corpus's
  186 gate lines carry one, and a structured gate used to drop it (the `()`/`[]`
  strip is recognition-only, so only the *custom* fallback kept it). A
  `tcbFigureFrontEnd` pre-recognizer now runs ahead of the shared recognizers and
  delegates the grammar to `recognizeSharedFigureLine`, then splits the
  annotations by whether the stated verb matches a slot's meaning:
  - `"<dancers> forward"`, dancers resolvable via `resolveDancerSetPhrase`
    (60 lines) → **`whom`**. `whom` means exactly "walks forward", so this is
    source-verified rather than inferred.
  - **Stationary** phrasings (`(men stay put)`, `(women are posts)`,
    `(centers are posts)`) fit NEITHER slot — `whom` walks forward and `who`
    backs up, so both move — and are never structured.
  - `"… forward"` naming an unmodelled set (`M1+W2 forward`, `ends forward`,
    `twos and fours forward`, and `(twos split ones)`) → note-only.
  Consumed annotations do not also become a note (notes render as their own row
  beside the figure line, so duplicating the words would read as a bug);
  everything unconsumed is preserved verbatim, so
  `[Ones and twos] Neighbor mirror gate 3/4 (twos forward)` yields
  `whom: twos` plus the note `Ones and twos`. Display: `whom` has no readable
  ContraDB position without a subject, so a TCB gate states it as a trailing
  `", ones forward"` clause while the ContraDB shape keeps `"<who> gate <whom>"`.
- **Security (OWASP).** The annotation extractor bounds every axis: at most 8
  annotations per line, at most 120 characters captured per annotation (a longer
  one simply doesn't match), and the joined note is truncated at 200 characters.
  Unterminated or empty brackets and purely-numeric annotations are skipped. A
  line the pre-recognizer can't fully resolve falls through untouched — never a
  half-structured figure, never a throw.

#### Square through pass list (#799)

TCB writes a square through's dancer sets and hands as a compact pass list —
`Square through 2 (N2R;SL)` is "pass N2 by the right, then the shadow by the
left". The `()`/`[]` strip is recognition-only, so before #799 that payload was
dropped **before** recognition and the line structured as a bare
`square through 2` with only `places` set. The other params then fell to their
`square_through` MoveDef defaults — `who: partners`, `who2: neighbors`,
`hand: right`, `balance: true` — which do not merely lose the pass detail: they
assert the **wrong** dancers, and the `balance: true` default renders a balance
the line never states. Inside the `interrupted square through` compound that
motivated the issue that balance is **doubled**, because the balance is already
its own sub-figure on the line above.

The `_squareThroughPassList` pre-recognizer (a `FigureMatch` decoder, mirroring
the `hey` pass-list decoder — same `tcbPassPeople` map) reads the codes:

- **Odd 1-based passes → `who`, even passes → `who2`,** and the two must each
  name a single consistent dancer (a square through of `n` alternates between
  two sets).
- **Hands alternate by position parity;** the base (`hand`) is position 1's, and
  every cell must agree with the alternation or the line declines.
- **`balance: false` is emitted explicitly** for import fidelity — TCB writes the
  balance as a separate line, never inline on a square-through line, so a
  standalone `Square through n (…)` carries none. This mirrors `rory_o_more`,
  which forces `balance: false` for the same reason. (The decoder does not itself
  fold a preceding balance line in; a `<who> balance` line stays its own figure,
  matching TCB's two-line source.)

**Whole-line strictness / prefer-custom.** The text outside the pass list must be
exactly `square through <n>` (modulo filler), `n` in 2..10; the cell count must
equal `n`; every cell must be `<people-code><R|L>` with the code in
`tcbPassPeople`. A second parenthetical, an `interrupted`/`modified` qualifier, a
trailing clause, an unmappable code (`C1`–`C3`, out-of-range neighbors, a bare
`R`/`L`), an inconsistent dancer or a non-alternating hand all return `null`, so
the line falls through to the shared recognizer's bare, defaulted reading rather
than being half-structured. Untrusted import text is length-capped **before**
the pass list is split into cells (`_boundedPassListCells`), so a hostile line
with millions of `;` is rejected in O(1) rather than allocating the oversized
list first — a bound shared with the hey and grand-right-and-left decoders (the
`n <= 10` cap then keeps the accepted count small).

The defect is the whole class of `Square through <n> (<pass list>)` lines, not
only the reported "2". This decoder changes no line's structured/custom status
(the line already structured, just with defaults), so the corpus structured
share is unchanged.

**Not full ContraDB parity.** ContraDB and TCB encode this dance's first dancer
**differently** — ContraDB's `square through two - neighbors …` gives
`who: neighbors`, while TCB's `N2R` gives `who: nextNeighbors`. This is a
source-level discrepancy, not something the importer reconciles, so the two
imports of *Tangled Yarns* remain distinguishable on `who` even after the fix;
what the fix removes is the fabricated dancers and the doubled balance.

### 4. Generic JSON (6.6)
- Our own canonical export format (full fidelity: figures, programs, custom
  fields, provenance, dialect definitions). Serves backup/restore and
  user-to-user sharing. Versioned schema; forward-compatible reader.

### Signed published collections (#862)

Signed published collections are a separate trust boundary from generic JSON
sharing. The app fetches a static manifest and detached signature from the
pinned HTTPS origin, verifies the signature over the exact manifest bytes
before parsing, then streams each immutable archive to its signed byte count
and verifies its SHA-256 digest before decoding.

The manifest is app-owned and vendors must not silently expand its semantics.
Unknown metadata is tolerated, but unsupported schema majors, minimum-reader
versions, and required capabilities are refused. A capability that affects
membership, decoding, rights, provenance, or validation must be declared as a
reader requirement; an older client must not silently ignore it.

Version 1 is a dance collection boundary: dances and referenced choreographers
are accepted, while published-source records, source citations, programs,
venues, custom-field content, and unknown top-level entities are rejected
before planning. Published-source citation import is intentionally deferred
until the importer can namespace source identities and transactionally undo
source rows with their dances. Archive-embedded provenance is rejected. The
importer stamps every dance with `ProvenanceSource.publishedCollection`,
external id `<collection-id>/<dance-id>`, the manifest version, and the
manifest's permission and licence declaration. Collection-level consent is
required before commit, including when every dance is new; only potential
duplicate rows need individual decisions.

### 5. A list of titles (#823)

The only source whose input is **pasted text** rather than a file or a URL, and
the only one that does not plan through a `SourceAdapter`. A pasted blob of
titles is resolved by `resolveTitleList` (`app/lib/src/data/title_list_import.dart`),
which reuses the program importer's first two stages and skips its third:

| stage | reuse |
|---|---|
| `parsePlaintextProgram(...)` — local title match | verbatim |
| online title lookup | via the shared `lookupUniqueExactTitle` |
| `buildProgramSlots(...)` | **skipped** — the only program-coupled stage |

#### It plans; it does not commit

This is the load-bearing difference from the program path, and the reason
`resolveUnmatchedOnline` is **not** reused wholesale. That function commits as it
goes (`resolveConfidentOnlineDanceId` calls `OnlineSearchService.import` /
`ImportPipeline.commit`), which is correct for a program line — no user is
present to adjudicate it. A Collection import *does* have a user present, so
every resolved title becomes an `ImportRecordPlan` handed to `ImportReviewScreen`
and written only on confirmation, where `_defaultChoice` already maps an
`ambiguous` verdict to skip. Routing through the review is therefore what keeps
#685's silent-duplicate risk out of this path rather than widening it.

What the two paths share is exactly one non-committing step,
`lookupUniqueExactTitle` (`app/lib/src/data/online_title_lookup.dart`): search a
title, return the unique exact-title hit or a typed reason there isn't one.
Collapsing more than that into the shared function would drag an unattended
import into a flow that has a user watching; collapsing less would leave the two
paths as parallel implementations of the same search rule.

`OnlineSearchService.loadPreview` takes an optional `DedupeIndex` so the batch
plans against one snapshot. Without it each title rebuilds the index — two full
collection loads apiece — and this is the same one-index-per-batch discipline
`ImportPipeline.plan` already applies to every multi-record source.

#### Every pasted title is accounted for

The review lists all three groups, because "six imported" alone cannot tell a
caller which of the other six she already owned and which the app could not find,
and those need different follow-up:

- **to import** — an ordinary review row with its dedupe verdict and actions;
- **already in your collection** — named with the matched dance's
  choreographer(s), since the local match is by title alone and two dances can
  share a title;
- **not found** — carrying *which* way it missed (`noResults`, `noExactMatch`,
  `multipleExactMatches`, `fetchError`, `lineTooLong`).

A paste with nothing importable deliberately does **not** fall through to the
generic "no dances found" message: that answer is worth showing on its own.

#### Bounding untrusted input

The paste is untrusted text that turns into network requests, so
`preflightTitleList` — pure, synchronous, and enforced by the resolver rather
than only by the widget — applies: `kMaxTitleListChars` (65,536 UTF-16 code
units, not bytes) on the raw text;
`kMaxTitleListTitles` (100) **distinct** titles, refused before any request and
never silently truncated; `kMaxTitleLength` (200) per line, over which a line is
reported rather than searched; blank-line drop; and case-insensitive
de-duplication (first occurrence wins — unlike `parsePlaintextProgram`, which
must keep repeats because a program may legitimately call a dance twice).

An accepted paste therefore costs at most `2 × 100` requests, issued serially
with progress and a cancel, and a per-title `on Exception` boundary means one
unreachable dance becomes one `fetchError` row rather than an aborted batch. No
new fetch path is introduced: the existing `buildCallersBoxSearchUrl` /
`buildCallersBoxJsonUrl` host allowlist (#621, #766) still governs what is
reachable.

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
  `box_circulate` via the `box circulate` head phrase or the bare `<subject>
  cross while <subject> loop` form) is returned completely unmodified, with
  named-recognizer precedence fully preserved (both box-circulate forms are
  regression cases, not fan-outs). The ContraDB combined
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

#### Vocabulary: two overloaded words

Both terms below name more than one thing, with **different user-visible
outcomes**. Three of the four false claims corrected across #885 and #900 trace
to the first term alone, so they are defined here rather than left to context.

**"Decline" — say which kind.** "Declining" names three different things, and
which one applies is decided by where in the pipeline the decision is made, not
by the word.

| kind | who | what it costs |
|---|---|---|
| **front-end veto** | `FigureFrontEnd.declineToCustom` | the line goes **straight to `custom`**, skipping both layers below |
| **pre-recognizer decline** | anything in `FigureFrontEnd.preRecognizers` returning `null` | the line **falls through** to the shared recognizers and usually still **structures**, minus whatever that pre-recognizer would have added |
| **whole-line decline** | the shared recognizers in `figure_parser.dart` (`_recognizers`) returning `null`, reached after `_normalize` | the line becomes a **`custom` figure** — there is nothing else to try |

The rows are in **execution order**, which is the thing to hold on to: the veto
runs first and short-circuits everything, then the pre-recognizers, then the
shared core. `parseFigureLine` calls `frontEnd.declineToCustom` *before*
`_recognize`, so a vetoed line never reaches either recognizer layer.

`_recognize` (`figure_parser.dart`) implements the lower two rows: it walks
`frontEnd.preRecognizers` and returns the first non-null; only when all of them
decline does it normalize and walk the shared `_recognizers`. So a
pre-recognizer's `null` is "not mine", while a shared recognizer's `null` is
"not structurable". The veto is deliberately NOT part of it — `parseFigureLine`
applies that before calling in, so a vetoed line is never offered to either.

The practical consequence, and the reason this matters more than tidiness: a
comment saying an unmapped people code "declines the whole line to custom" is
**true** of the hey decoder — whose pass list *is* the figure's structure, so
without it there is nothing to build — and **false** of
`_squareThroughPassList` or `_sideRunAnnotation`, whose runs only *add* params.
`Square through 2 (C1R;C2L)` still imports as a `square_through`; only the
unmapped detail is dropped. Prefer naming the outcome ("falls through to the
shared reading", "becomes a custom figure") over the bare verb.

Which is which, derived from the code rather than from memory:

- `tcbFigureFrontEnd` registers **twelve** pre-recognizers: `_hey`,
  `_circulate`, `_squareThroughPassList`, `_balanceHandAnnotation`,
  `_gateAnnotation`, `_courtesyTurnAnnotation`, `_walkForwardAnnotation`,
  `_chainAnnotation`, `_starPromenadeAnnotation`, `_promenadeAnnotation`,
  `_rightLeftThroughAnnotation`, `_sideRunAnnotation`. Every one is the
  falls-through kind.
- `contraDbHtmlFigureFrontEnd` registers its **entire grammar** as
  pre-recognizers, **and** supplies a veto. Both halves matter, and they pull in
  opposite directions, which is why this front end is the one most likely to be
  described wrongly:
  - All **48** of its *recognizers* are the falls-through kind. None of them can send
    a line to `custom` on its own; that happens only when the shared core
    declines it too. So "this ContraDB recognizer declines the line to custom"
    is wrong about the mechanism even when it is right about the outcome.
  - Its *veto* (`_declineStarPromenade`) is the opposite: it does send a line
    straight to `custom`, ahead of both layers. Verified — `gentlespoons star
    promenade right 1` imports as `custom` under this front end while the
    canonical front end structures the identical line as `star_promenade`, so
    the veto alone is what changes the outcome.

  A claim about ContraDB declines must therefore say *which* of the two it
  means. An unqualified "ContraDB has no whole-line decline" is false; it has
  exactly one, and it is not a recognizer.
- `canonicalFigureFrontEnd` registers none, so for it every decline is a
  whole-line decline.
- `FigureFrontEnd.declineToCustom` is the veto row of the table above, and the
  only way a *source* can force `custom` by itself: it short-circuits ahead of
  both recognizer layers. It exists because deleting a source's own recognizer
  is not enough — the shared ones are source-neutral and will claim the line
  anyway. Only `contraDbHtmlFigureFrontEnd` supplies one today.

**"Verbatim" — say verbatim *against what*.** The word carries at least three
senses here, and only one of them is ever wrong. The custom fallback stores the
**scrubbed** text, never the raw source: `parseFigureLine` computes
`scrubFn(rawText)` and hands that to `customFigure`, and scrubbing canonicalizes
role terms. `Gentlespoons star promenade right 1` is stored as
`role1s star promenade right 1`.

So "verbatim" is true only relative to a stated baseline:

- **The normalization sense — correct.** Verbatim against whatever
  `recognitionNormalize` removed. `figure_parser.dart` scopes it this way twice
  (the `FigureFrontEnd.recognitionNormalize` doc and `_normalize`'s own): what a
  *structured* match drops — annotations and the like — survives on the custom
  reading. A real and useful guarantee.
- **The template sense — correct.** Verbatim against a recognizer's own
  template: text trailing the part a recognizer matched "survives verbatim as
  the note". Most of `contradb_figure_dialect.dart`'s many uses are this one.
  Also true, also baseline-relative, and *not* the same claim as the above.
- **The source sense — never true.** Nothing preserves the source's own wording
  through the parser, because role canonicalization happens before recognition
  for every line.

This ambiguity has already reached users: `app/CHANGELOG.md` promised a declined
ContraDB figure kept "its own wording exactly as written" when the role names
are in fact dialect-mapped. That instance is fixed, but the word is still doing
several jobs across the repo, so state the baseline whenever using it.

**Neither term has been swept.** Roughly 28 `verbatim` uses survive, most of them
correct, and a uniformity pass over them would be a mistake: a byte-identical
sentence can be true in one file and false in another. `figure_parser.dart`'s
"P6+ and P-n … decline the whole line to custom" is **true** — that map holds
prose dancer tokens, and an unmapped one really does force custom — while the
same sentence about annotation cells in `callersbox_figure_dialect.dart` was
false and had to be corrected. Grepping a claim finds its instances; each still
has to be judged in its own context.

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
  trailing balance wave (→ `pass_the_ocean` / `form_short_waves` /
  `form_a_long_wave` / `form_long_waves` with `balance: true`, beats summed;
  #577), diagonal chain /
  hey
  / right-&-left-through (→ `dir: left/rightDiagonal`), same-role right & left
  through (variant kept as a note), weave-the-line `with <dancer>`, relationship
  N-suffix (`with/to neighbor N2`, in either word order), explicit dancer codes
  (M1/W1/M2/W2 →
  ones/twos single-dancer identities), and `(A-B)` beat ranges. **Mad robin &
  butterfly whirl (#295, taxonomy v20):** both moves gained the params TCB
  states — `mad robin` a rotation `direction` plus the "around `<whom>`" target,
  `butterfly whirl` a `who` plus the same `direction` — so "Mad robin clockwise
  around neighbor N2" and "Partner butterfly whirl counterclockwise" now
  structure. Each recognizer requires BOTH stated facts, so a bare "mad robin" /
  "butterfly whirl" (ContraDB's own phrasing), or a butterfly whirl carrying an
  unmodeled rotation amount ("… counterclockwise 1 & 1/2"), still stays custom.
  **Directed promenade (#771):** TCB's `clockwise`/`counterclockwise`
  qualifiers now populate `promenade.turn` instead of causing the complete
  line to fall to `custom`. The shared parser accepts TCB's supported
  rotation-word forms; an unstated rotation keeps the taxonomy default.
  ContraDB HTML's source-rendered `on the left`/`on the right` promenade tail
  is likewise promoted from the existing figure note to `turn`, using the
  maintainer mapping `on the left` → `clockwise` and `on the right` →
  `counterclockwise`. Unrelated trailing text remains a note.
  **Grand right and left & flutterwheel (#295, NO taxonomy change):** both are
  compound shorthands, so neither becomes a move — `Grand right and left
  (<pass list>)` fans into one `pull_by_dancers` per stated pass (see
  "Compound-shorthand fan-out" above) and `flutterwheel` emits the
  `allemande` + `star promenade` children TCB itself writes (see "Compound
  figures" above). A pass code the taxonomy cannot faithfully represent, any
  leftover prose, or a child that fails to structure all keep the line custom.
  **Balance a wave (#295, taxonomy v21):** see *Balance-a-wave lines* below.
  **Courtesy turn (taxonomy v23):** TCB writes a standalone courtesy turn on
  **115** of the 24,107-dance corpus's figure lines, and until v23 every one of
  them fell to `custom` — the taxonomy had no such move, and ContraDB models
  none (0 hits for "courtesy" repo-wide; it treats the courtesy turn as an
  unparameterized sub-component of `chain` / `right left through`). The
  recognizer reads
  `[<dancer>] courtesy turn [<dancer>] [clockwise|counterclockwise] [face <dancer>]`
  and fills only what the line states: the pairing (`who`), a stated rotation
  sense (`direction` — 10 lines, all `clockwise`), and the `, face N0/N2/N3`
  ending facing (13 lines), which is a **DANCER**, not one of the cardinals
  `swing.endFacing` uses. `whom` is never filled on import: no corpus line
  writes the two-dancer form. A TCB annotation (`(in center)`, `(continued)`,
  `[Ones and threes]`) is preserved verbatim as the figure's **note** by a
  front-end pre-recognizer, so a structured match loses nothing the `custom`
  fallback kept — the same mechanism `gate` uses (7 lines).
  *Whole-line contract, so the following all stay `custom` with no exclusion
  logic written:* a **chain** (or right-and-left-through / promenade) that also
  names its courtesy turn (30 lines — emitting a standalone `courtesy_turn`
  would double-count both the figure and its beats, and neither model has a slot
  for the qualifier); **"arky"** (7 lines — reversed roles, unmodeled, and
  dropping the word would lose real choreography); a **rotation amount**
  (`courtesy turn 3/4`, `… 2` — 6 lines; the move has no `turn` param);
  `without hands`; and every unmappable dancer (`phantom partner`,
  `P1/P2/P4 partner`, `next corner`, `opposite neighbor`, `bottom couple`,
  `fives`). A `;` compound (`Ones courtesy turn; face down`) stays whole-custom
  under the existing all-or-nothing rule, which is also what keeps a **cardinal**
  ending facing out of the dancer-valued `endFacing` slot.
  *Secondary effect:* 13 dances' **compound parents** (`Modified ladies chain
  to partner:`, `Wheel chain to neighbor:`) now decompose, because their
  all-or-nothing child list was previously blocked by the unstructurable
  courtesy-turn tail.
  **Walk forward (#733, NO taxonomy change):** TCB writes `walk forward` on 879
  figure lines; it is three families, none of which needs a move. A bare
  `[<dancer>] walk forward` clause is read TOGETHER with the clause that follows
  it, since it states the inbound travel to a formation the next clause names:
  `[<dancer>] walk forward; form long wave in center` emits **only**
  `form_a_long_wave` with the walk clause's dancer transferred onto `who`
  (the move's `in` defaults to true and its rendered line already says "dance in
  to a long wave in the center", so a separate travel figure would state the
  travel twice), and `walk forward; form wave of four with <dancer>` emits
  `pass_through()` + the `form_short_waves` figure that already parsed. A
  directed `walk forward to <dancer>` is itself a `pass_through` — the `to
  <dancer>` names the DESTINATION you arrive at after passing your current
  neighbour, the standard contra progression — with the destination preserved
  verbatim as the figure's **note** (`to n2`), the same shape `chain` uses for
  its `to <dancer>` target, so `to n0` / `to n1` / `to shadow` stay
  distinguishable from the ordinary progression target. `dir` and `shoulder` are
  never written: both are `pass_through`'s own taxonomy defaults, and stating
  them would assert a direction and a shoulder the source did not.
  *Stays custom:* a genuinely bare `walk forward` (nothing anchors an
  interpretation); every travel qualifier the mapping cannot carry
  (`one step`, `slowly (step; step)`, `until right shoulders are adjacent`,
  `towards partner`, `(out of the set)`); non-dancer or qualified destinations
  (`to center`, `to next star`, `to second person`, `to shadow S1`); a stated
  subject on either pass-through reading (`Women walk forward to N2` —
  `pass_through` has no `who` slot, so structuring it would drop the role); and
  **every diagonal** (`walk forward on left/right diagonal [(optional spin)]`),
  because `form_a_long_wave` has no `dir` at all and on the short-wave side the
  source states the direction of TRAVEL rather than the wave's orientation —
  the recognizer already declines TCB's explicit `form diagonal wave of four`
  for the same reason, and `(optional spin)` has no slot either.
  *Secondary effect:* a newly-structured wave lets the existing trailing
  balance-wave fold (#577) claim the `Balance wave …` line after it, which it
  could not while the walk line was custom — 4 dances change which figure that
  balance attaches to (see "Balance-a-wave lines" below). Beat totals are
  unaffected.
  **The general `;`-run consume (#843 Parts B and C, NO taxonomy change):** TCB
  writes handedness and dancer identity in a `;`-separated run of
  `<people-code><R|L>` cells — `(NR)`, `(NR;PL)`, `(SR;NL)`. Four decoders
  already consumed it for the moves that LOWER it onto a bespoke structure (the
  hey's pass/ricochet slots, grand-right-and-left's one figure per pass, square
  through's pass list, the balance-a-wave annotation). Everywhere else
  `_stripAnnotations` dropped it and the taxonomy filled a default — which on
  **116** corpus figures was the OPPOSITE of what the source said.
  `_sideRunAnnotation` closes that, consuming **2,504** previously-dropped runs
  (`pass_through` 2,136, `square_through` 159, `cross_trails` 98,
  `pass_through + turn_alone` 88, plus a short tail across seven more keys).
  It runs LAST, so no existing decoder loses a line.
  *The slot is found by `ParamKind`, not by name.* Of the twenty moves with a
  side slot, seven name it `shoulder` and two `centerHand`, so the name check
  #870 used would miss nine of them.
  *Values are written even when they equal the default* (owner ruling): the
  decode either fires or it does not, and storing what the source SAID rather
  than what we assumed means the value survives a future change of default. This
  is byte-identical at both identity layers, so the 2,388 same-value cases raise
  no #686 "Variation?" prompt; the 116 inverse cases do, correctly.
  *Dancer identity* fills `who`/`who2` where declared — odd 1-based positions
  name `who`, even name `who2`. `pass_through` declares no `who`, so its dancer
  code is dropped; preserving it as a note would add one to ~2,048 figures
  across 1,773 dances. Dropping it is the IMPLEMENTING AGENT'S call, not an
  owner ruling: a note on that many figures is a visible change at corpus
  scale, so it is recorded here as an open question rather than a settled one.
  *Declines (→ the ordinary annotation-stripped reading):* any unmapped people
  code (`O`, `Ph`, `SRN`, `C1`–`C3`, out-of-range neighbours/shadows); a run
  whose sides do not alternate by position parity; a run stating more passes
  than the move models — a `square_through` cell count that disagrees with
  `places` (which is #799's ruling, and this decoder must not undo it by the
  side door), a `cross_trails` run past two cells, or any multi-cell run on a
  single-pass move; and a non-periodic `square_through` 4-list. A run
  CONTRADICTING a prose-stated side falls through with the PROSE value intact
  rather than declining to custom — forcing custom would regress a line that
  structures today.

  **Star promenade centre (#843, taxonomy v26, NO new slot):** TCB writes the
  centre in a trailing parenthetical — `Neighbor star promenade 1/2 (WR)` — on
  **all 626** of the corpus lines that import as `star_promenade` (measured
  against `c9a0185f`). It does **not** qualify `who`: `(WR)` says *the women
  have right hands in the centre*, while `who` names the dancer you PICK UP on
  the side. Both facts appear in one figure in TCB's own flutterwheel
  decomposition (`(4) Women allemande right 1/2` + `(4) Neighbor star promenade
  1/2 (WR)`), so they cannot share a slot — which is why taxonomy v26 removed
  the `hand` param rather than re-pointing it.
  The annotation becomes the figure's **note**, via the same
  annotation-preserving pre-recognizer mechanism `gate` and `courtesy_turn` use:
  `role2s by the right in the center`. It stores **canonical role tokens**, so
  the note renders under the active dialect ("robins…", "follows…") instead of
  freezing the source's gendered `W` forever. `who` is never written or
  overwritten from the annotation.
  *Stays verbatim (never approximated):* an unmapped people code (1 corpus line,
  a `c` square-corner prefix), a multi-cell `;` run (a star promenade has one
  centre, so a run states something this phrasing cannot express), and any
  annotation with no `R`/`L` tail. *Secondary effect:* other annotations on
  these lines — `(hand-in-hand with neighbor)`, `[with N1]` — were previously
  dropped outright and are now kept alongside the centre note.
  Prefix mix across the 626: `m` 358 → `role1s`, `w` 265 → `role2s`, `n`/`n1` 2
  → `neighbors`, 1 unmapped. **Zero** lines state a prose hand, so the visible
  change is the removal of a DEFAULTED "right" that used to render on every one
  of these figures.
  **Out (→ custom
  for now, tracked on #295):** cast off,
  two-hand turn & other ECD figures, promenade
  CW/CCW around the major set, non-duple formations, and
  anything with leftover prose. Coverage improves iteratively — measured against
  the full corpus (design target ≥80% of lines structured over time). (`||`
  simultaneity is no longer in this list — see "Simultaneous-action fan-out
  (`meanwhile`)" above; it fans into a `meanwhile` container one layer above
  this per-move recognizer, #591.)

### Balance-a-wave lines (CallersBox, #295 / taxonomy v21)

The Caller's Box writes "balance an existing wave" as its own figure line —
`(4) Balance wave of four (NR,WL)`, `(4) Balance long wave (NR, women face in)`
— **4,613 lines** across the 24,107-dance corpus, formerly the single largest
custom bucket. There is **no `balance_the_wave` move and none was added**: the
taxonomy expresses "a wave exists and is balanced" as the wave-FORMATION move
carrying its `balance` flag, so such a line maps onto that move. It is a
**1 line → 1 figure** mapping — the line keeps its own beats and no extra 0-beat
form figure is ever emitted.

**Where it happens, and why nothing is stolen.** The line still parses to
`custom`; the mapping is a FINAL pass of the CallersBox cross-line merge
(`_promoteBalanceWaveLines`), so by construction it only ever sees leftovers:

1. **Fold 1 (forward)** — a balance line immediately BEFORE a swing /
   petronella / rory o'more / box the gnat / swat the flea / box circulate folds
   into that move (`prefix: balance` / `balance: true`). ~44% of balance-wave
   lines have such a successor and are claimed here, exactly as before.
2. **Fold 4 (backward, #577)** — a balance-wave line immediately AFTER a
   structured `pass_the_ocean` / `form_short_waves` / `form_a_long_wave` /
   `form_long_waves` folds into that figure with the beats summed, so an
   explicitly-formed-then-balanced wave yields exactly ONE form figure. The
   balance line's annotation now also **enriches** the merged figure with any
   hand/pair it states that the forming line did not, instead of being
   discarded. A balance naming an **unmodeled formation** (`interlocking`,
   `intersecting`, `circular`) is refused here, exactly as the promotion refuses
   it: it is not a balance of the wave the previous line formed, and folding it
   would drop the qualifier from a structured figure that then asserts something
   the source never said. **86** corpus lines carry such a qualifier, but that
   is a census of the wording — **85** already fell to custom regardless, and
   exactly **1** was actually being folded and losing the word: dance 2463
   *Gypsy Star* B1, `form long waves in center` /
   `Balance interlocking long waves in center`. (That one was a regression this
   same change set introduced — recognizing `form long waves` is what made the
   pair foldable.)
3. **Promotion** — whatever is left becomes the form figure on its own. This is
   the implicit case (an allemande or shoulder round leaves the dancers in the
   wave the very next line balances): the forming is a fact the source implies,
   so representing it is inference from adjacent evidence, not fabrication.

A promotion is additionally **skipped** when the preceding figure is a still-
custom wave-FORMING line, so a form figure is never emitted beside an
unstructured "form …" line.

**Decoding TCB's annotation.** The parenthetical is the wave's payload, not a
droppable note, so it is decoded rather than discarded (structuring the line
without it would destroy detail the custom text preserved verbatim):

| line shape | maps to |
| --- | --- |
| `Balance wave of four (<pair><H>, <role><H'>)` | `form_short_waves{balance, sides: <pair>, center: <role>, centerHand: <H'>}` |
| `Balance wave of four` (no annotation) | `form_short_waves{balance}` (MoveDef defaults, as a bare "Form a wave" line already does) |
| `Balance long wave (<pair><H>, <role> face in)` | `form_long_waves{balance, whom: <pair>, hand: <H>, who: <role>}` |

The role pair is the wave's **centre** and the relationship pair its **sides**,
with the two hands OPPOSITE — verified on the corpus (2,560 of 2,764 wave-of-four
lines match that shape, and only one of the parsed pairs states the same hand
twice), and the same centre/sides model ContraDB already uses. `who` on
`form_long_waves` is the facing-IN role, matching ContraDB's own subject.
Roles reach the decoder already canonicalized ("women face in" is stored as
"role2s face in").

**Deliberately still custom** (prefer-custom — the whole line must be accounted
for): wave sizes we do not model (`wave of two/three/five/six/seven/eight`),
exotic formations (`intersecting`, `interlocking`, `circular wave`), annotations
naming two hand-holds at once (`(N2R,N1L, women face in)`), people codes with no
taxonomy slot (`C2`, `1CC`, `O`, `TB`, `SRN…`, `?` — the omissions documented
on `tcbPassPeople`, whose single map this decoder reuses), `someone face
in`, and `Balance long wave for all in center`. The singular
`form_a_long_wave` sense (ONE long wave in the centre formed by a subset) is
never guessed at either — a line meaning that reaches it through Fold 4 from the
preceding `form long wave in center` line.

**Supporting recognizer change.** `form (a) wave of four [with <dancer>]` — TCB's
dominant forming wording (~1,000 clauses) — now structures as `form_short_waves`
(the `with` tail sets `sides`), so the explicit-forming merge can actually fire.
`form new wave …`, `form diagonal/intersecting/interlocking …` and other wave
sizes still degrade to custom.

**Measured effect** (real adapter over the full mirror, 20,516 parseable dances):
custom figures 24,775 → 22,272 (−2,503), structured share 76.24% → **78.69%**;
every forward-merge move's count is unchanged or higher (none lost a balance);
and **per-dance beat totals are byte-identical for all 20,515 dances**, so
`deriveSections`' cumulative section placement cannot drift.

## Error handling & testing

- Every stage yields structured errors with source context (never stack-trace
  UX); partial batch failure imports the rest and reports.
- Adapter test fixtures: real TCB JSON samples (id 1, 100, 3418, 10284 cover
  chestnut/Becket/proper/notes cases), CC demo USR, synthetic edge cases
  (empty phrases, `(0)` beats, non-standard phraseStructure, windows-1252
  artifacts, duplicate titles).
- Round-trip property: export→import of our generic JSON is identity.
