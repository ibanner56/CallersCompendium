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
| **dedupe** | Match by (source, externalId) first — re-import updates provenance and offers diff. Otherwise fuzzy (normalized title + author) → user chooses link/duplicate/skip. Free-text imports feed their raw author names (see *Author resolution*) into this signal. |
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

## Sources

### 1. CallersBox snapshot (6.2, 6.3) — primary
- Input: hosted NDJSON snapshot (see design/callersbox-snapshot.md) or a
  single dance JSON pasted/downloaded from `dance.php?id=N&format=JSON`.
- Field mapping is direct (research/callersbox.md documents the schema);
  figures parsed by a **TCB grammar parser**: `(beats) text` per line, keyword
  matching against taxonomy `searchKeywords`, parameter extraction for the
  high-frequency moves (swing, balance, allemande, circle, star, chain,
  long lines, right left through, promenade, petronella, do si do, hey…).
  Long-tail/complex notation (per-pass hey lists, `||` simultaneity) falls to
  custom figures — refined iteratively; parser coverage is measured against
  the full corpus and reported (target: ≥80% of figure lines structured in
  first release, improving over time).
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
- Approach: FM12 parser (fmptools-style) extracting the dances/sets tables;
  figures are the user's personal free text → import as custom figures
  (optionally run through the TCB grammar parser for opportunistic
  structuring, clearly marked for review). Sets → Programs; user fields →
  custom fields.
- Fixture: the publicly downloadable demo `.USR` (kept out of the repo until
  redistribution permission is clarified; local test asset otherwise).
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
  (→ pass by), lead down/up & go down/up outside (→ down/up the hall `moving`),
  circulate (→ box circulate, balance folded), weave-the-line `with <dancer>`,
  relationship N-suffix (`with/to neighbor N2`), and `(A-B)` beat ranges. **Out
  (→ custom for now, tracked on #295):** balance-in-a-wave, cast off, turn as
  couples, mad robin & butterfly whirl (need direction/who params), same-role
  right & left through, diagonal figures, `||` simultaneity, and anything with
  `or`/leftover prose. Coverage improves iteratively — measured against the full
  corpus (design target ≥80% of lines structured over time).

## Error handling & testing

- Every stage yields structured errors with source context (never stack-trace
  UX); partial batch failure imports the rest and reports.
- Adapter test fixtures: real TCB JSON samples (id 1, 100, 3418, 10284 cover
  chestnut/Becket/proper/notes cases), CC demo USR, synthetic edge cases
  (empty phrases, `(0)` beats, non-standard phraseStructure, windows-1252
  artifacts, duplicate titles).
- Round-trip property: export→import of our generic JSON is identity.
