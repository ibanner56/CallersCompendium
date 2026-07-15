# Design: Dialect system

*Roadmap item 1.9 · v0.1 (2026-07-10). Architecture adopted from ContraDB
(research/contradb.md) with its pitfalls corrected.*

## Model

A **dialect** is a user-level presentation mapping applied at render time.
Storage is always canonical (move IDs, role IDs, canonicalized free text).

```json
{
  "roles":  {"role1": "Larks", "role2": "Robins"},
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
**all free-text entry passes through one `canonicalize(text, dialect)`
function** before persistence: it inverse-maps the user's dialect terms and
known synonyms/legacy terms (gypsy → shoulder round) back to canonical
vocabulary, and flags ambiguities inline ("lingo line" underlining: recognized
terms underlined, discouraged terms struck through, unknown terms plain).

Edge rules:
- Round-trip safety: `canonicalize(render(x)) == x` for all taxonomy terms in
  every shipped preset — property-tested.
- Collisions (user maps two canonical terms to one word) are rejected at
  dialect-edit time, since they'd make reversal ambiguous.
- Canonicalization is conservative: unknown phrases are stored as typed; only
  exact dialect/synonym matches are rewritten.

## Scope of substitution

| Surface | Dialect applied? |
|---|---|
| Dance card, editor previews, performance mode | ✅ |
| Free text: calling notes, hooks, custom figures, program notes | ✅ (regex) |
| Search input | canonicalized before matching |
| Stored data, snapshots, JSON export (canonical mode) | ❌ canonical |
| Print/share | user choice, labeled |

## A11y note

Screen-reader strings use the same dialect output (the caller's own vocabulary
is their clearest language), with abbreviations expanded (per accessibility
baseline).
