# Design: Dialect system

*Roadmap item 1.9 · v0.1 (2026-07-10). Architecture adopted from ContraDB
(research/contradb.md) with its pitfalls corrected.*

## Model

A **dialect** is a user-level presentation mapping applied at render time.
Storage is canonical for structured data (move IDs, role IDs) and for
figure-bearing free text; hand-typed prose is stored verbatim (see
"Canonicalization on input").

```json
{
  "name": "Custom",
  "roles":  {
    "role1": {"singular": "Lark", "plural": "Larks"},
    "role2": {"singular": "Robin", "plural": "Robins"}
  },
  "moves":  {"shoulder_round": "%S shoulder round", "do_si_do": "dosido"},
  "dancers": {"neighbors": "the others", "nextNeighbors": "the next couple"},
  "discouragedTerms": ["gypsy", "gents", "ladies", "..."]
}
```

- `%S` placeholder injects direction/handedness into a move substitution
  (renders "right shoulder round" / "left shoulder round").
- `dancers` substitutes the positional/relational dancer tokens (ContraDB's
  parallel `dancers` map) — e.g. `neighbors`, `ones`, `partners`,
  `nextNeighbors`, `centers`. The role-driven tokens `role1s`/`role2s` are
  **excluded**: they flow through role-term substitution (`roles`) instead, so
  they are never listed here. Like `moves`, presets ship an **empty** `dancers`
  map — no gendered or house-specific dancer terms are baked in.
- `discouragedTerms` is **user-editable data with shipped defaults**, not
  hardcoded (ContraDB pitfall #3): the entry editor flags these terms, it
  never blocks.
- Shipped presets are **role-neutral only**: **Larks/Robins (default)** and
  Leads/Follows (plus Canonical). Gendered role terms are **not** baked in as
  presets — a user who wants them enters them through the custom role-terms
  editor. Everything a dialect can set is editable in Settings → Dialect:
  role terms, per-move substitutions, dancer-term substitutions, and the
  discouraged-terms list. Users may
  keep a custom dialect and switch instantly (e.g. per-gig) — this generalizes
  CC's binary "on the fly gendered↔gender-free switch". The active dialect
  (including a full custom one) is persisted as JSON.

## Rendering pipeline (pure functions, golden-tested)

```
Figure ──renderTemplate──▶ canonical text ──dialect subst──▶ display text
free text (notes/custom) ──term regex (case-preserving)──▶ display text
```

- Substitution covers: role terms, move display names, positional/relational
  dancer terms, and terms inside free text (notes, hooks, custom figures) via
  compiled word-boundary regex with case preservation.
- Search always runs against canonical text/structures → dialect never affects
  results (dialect-agnostic search for free).
- Print/export lets the user choose canonical or active dialect; exports embed
  which dialect was applied.

## Canonicalization on input (single chokepoint)

ContraDB's `DialectReverser` ran only on some code paths (pitfall #7). Here,
**figure-bearing free text passes through one `canonicalize(text, dialect)`
function** before persistence: it inverse-maps the user's dialect terms and
known synonyms/legacy terms (gypsy → shoulder round) back to canonical
vocabulary, and flags ambiguities inline ("lingo line" underlining: recognized
terms underlined, discouraged terms struck through, unknown terms plain).

The chokepoint is deliberately **not** applied to long-form hand-typed prose.
`canonicalize` is a word-boundary substitution over an always-on synonym set
that includes ordinary English words and proper nouns — `man`, `men`, `woman`,
`women`, `lady`, `ladies`, `gent(s)`, `lark(s)`, `robin(s)`. Over a figure line
those are reliably roles; over a caller's prose they are not. Applied to prose
it rewrote dance titles, tune names and people's names: `Lady of the Lake`
became `role2 of the Lake` and re-rendered as "robin of the Lake"; `Robin
Hayden` became `role2 Hayden`; `The ladies room` became `The role2s room`. The
rewrite is in-place and the substitution also discards the caller's
capitalisation, so the original text is not recoverable. Prose is therefore
stored exactly as typed (issue #613).

Where the chokepoint IS wired:

- **Imports** canonicalize incoming **figure text** — the `custom` figure text
  and figure notes built by the free-text adapters — through `scrubFigureText`,
  which calls `canonicalizeText(…, Dialect.canonical)` so the always-on legacy
  synonyms resolve roles. Imported **dance-level prose** (`hook`,
  `callingNotes`, `walkthrough`) is only sanitized (`sanitizeImportedText`),
  never canonicalized, matching how hand-typed prose is stored.
- **Figure notes** (`Figure.note`) are canonicalized against the caller's
  **active** dialect in the dance editor's save path (`buildDance`), and
  rendered back via `renderFreeText` on load and at every display site
  (detail, perform, PDF/text export). A note carries modifiers and clarifiers
  for the figure beside it, so its language must stay consistent with the
  figure — and importers already store note text canonically through
  `scrubFigureText` (issue #715).
- **Hand-typed dance prose** — `hook`, `callingNotes`, `walkthrough` — is
  stored **verbatim, exactly as typed**, in whatever dialect the caller uses.
  It is not canonicalized on save and not rewritten on load. Display sites
  still route it through `renderFreeText`, which is a no-op for text holding no
  canonical role tokens.
- **Search** canonicalizes the query at the compiler boundary. Because prose is
  stored verbatim, a role term typed into prose is **not** full-text matchable
  (a Larks/Robins reader searching "Robins" has the query canonicalized to
  `role2s`, which the verbatim index does not contain). Ordinary prose is
  matched normally. This is a known gap, tracked separately; the fix is to
  match the query against both forms, not to rewrite the caller's prose.

> Intentionally not wired: **program-level prose** (`Program.notes`, free-text
> `ProgramSlot.text`) is stored and displayed verbatim — it is not
> canonicalized. This text is predominantly logistical (venue notes, set
> breaks, potluck/sound-check reminders) rather than role-bearing
> choreography, and since `canonicalizeText` is roles-only and leaves non-role
> text unchanged (byte-for-byte identical), wiring the chokepoint here would be
> a no-op for the overwhelming majority of program prose. Tracked as issue #665,
> closed as not planned.

Edge rules:
- Round-trip safety: `canonicalize(render(x)) == x` for all taxonomy terms in
  every shipped preset — property-tested.
- Collisions (user maps two canonical terms to one word) are rejected at
  dialect-edit time, since they'd make reversal ambiguous.
- Canonicalization is conservative: unknown phrases are stored as typed; only
  exact dialect/synonym matches are rewritten.
- Migration: a schema-v17 step once canonicalized existing prose in place. It
  was reverted before any release contained it (see above), so no database in
  the wild was rewritten. v17 remains a no-op step so v18+ keep their numbering.

## Scope of substitution

| Surface | Dialect applied? |
|---|---|
| Dance card, editor previews, performance mode | ✅ |
| Free text: custom figures, figure notes | ✅ (canonical on save, rendered on read) |
| Hand-typed prose: hooks, calling notes, walkthrough | ❌ verbatim (intentional; #613) |
| Program notes / free-text slots | ❌ verbatim (intentional; #665 not planned) |
| Search input | canonicalized before matching |
| Stored data, snapshots, JSON export (canonical mode) | ❌ canonical |
| Print/share | user choice, labeled |

## A11y note

Screen-reader strings use the same dialect output (the caller's own vocabulary
is their clearest language), with abbreviations expanded (per accessibility
baseline).
