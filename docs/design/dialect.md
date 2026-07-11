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
  "discouragedTerms": ["gypsy", "gents", "ladies", "..."]
}
```

- `%S` placeholder injects direction/handedness into a move substitution
  (renders "right shoulder round" / "left shoulder round").
- `discouragedTerms` is **user-editable data with shipped defaults**, not
  hardcoded (ContraDB pitfall #3): the entry editor flags these terms, it
  never blocks.
- Shipped presets: **Larks/Robins (default)**, Gents/Ladies, Leads/Follows,
  Ladles/Gentlespoons, plus fully custom. Users may keep multiple named
  dialects and switch instantly (e.g. per-gig: a gendered-terms community vs a
  positional-terms community) — this generalizes CC's binary "on the fly
  gendered↔gender-free switch".

## Rendering pipeline (pure functions, golden-tested)

```
Figure ──renderTemplate──▶ canonical text ──dialect subst──▶ display text
free text (notes/custom) ──term regex (case-preserving)──▶ display text
```

- Substitution covers: role terms, move display names, and terms inside free
  text (notes, hooks, custom figures) via compiled word-boundary regex with
  case preservation.
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
