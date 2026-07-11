# Research: ContraDB figure & dialect model

*Roadmap item 1.2 · surveyed 2026-07-10 from github.com/contradb/contra @ `13f38a5`.*

ContraDB (Rails, by David Morse, 2015–2022, now unmaintained) is the strongest
prior art for structured figures + dialect. **License: AGPL-3.0 — identical to
ours**, so we may reuse code and design with attribution; the figure taxonomy
itself is factual domain vocabulary and freely adoptable.

## Figure model

- A dance's figures live in one `figures_json` text column: an array of
  `{move, parameter_values[], note?, progression?}` objects.
- `move` is a canonical name; `parameter_values` is **positional**, matching the
  ordered formal parameters in the move definition. `progression: 1` marks the
  progression point. `"*"` is a wildcard sentinel in search filters.
- Canonical moves (~45) are defined in `app/javascript/libfigure/figure.js` via
  `defineFigure(name, params[], props)`; params come from a library of ~30 param
  types over ~20 "chooser" UI/value types (booleans, beats 0–64, degrees
  90–900, hand/shoulder/spin sides, set directions, enders, free text, and rich
  dancer-selector types).
- Full move list includes: allemande (+orbit), arch & dive, balance (+the ring),
  box circulate, box the gnat, butterfly whirl, California twirl, chain, circle,
  contra corners, cross trails, **custom**, do si do, dolphin hey, down/up the
  hall, facing star, figure 8, form (a long wave / an ocean wave / long waves),
  gate, give & take, gyre, hey (10 params!), long lines, mad robin, pass by,
  pass through, petronella, poussette, promenade, pull by (dancers/direction),
  revolving door, right left through, roll away, Rory O'More, slice, slide along
  set, square through, stand still, star, star promenade, swing, turn alone,
  zig zag.
- **Aliases** share a canonical move with pinned params: see saw → do si do
  (left shoulder), swat the flea → box the gnat (left hand), meltdown swing →
  swing. Search de-aliases automatically.
- **`custom` move** = free-text `custom_figure` + beats; beat validation always
  passes; text still gets dialect highlighting. `contra corners` and `turn alone`
  also embed a `custom_figure` sub-field.
- Dancer selector vocabulary: everyone, gentlespoons/ladles (+first/second),
  partners, neighbors, ones, twos, same roles, first/second corners, plus
  out-of-set dancers (shadows, 2nd shadows, prev/next/3rd/4th neighbors).

## Dialect system

- **Canonical terms in storage; dialect applied only at display.** Search is
  therefore dialect-agnostic for free.
- Per-user `idioms` table (STI: `Idiom::Dancer` | `Idiom::Move`) rows of
  `(term, substitution)` → assembled into `{moves: {...}, dancers: {...}}`.
- Applied via `moveSubstitution`, `dancerSubstitution`, and `stringInDialect`
  (regex over free text — notes/hooks — with case preservation).
- `%S` placeholder embeds direction into a move substitution (e.g. gyre →
  `"%S shoulder round"` renders "right shoulder round").
- `DialectReverser` maps user-dialect input back to canonical before storage.
- "Lingo lines": entered text gets canonical/dialect terms underlined and a
  hardcoded `bogusTerms` list (men/women/ladies/gents/larks/ravens/gypsy/...)
  struck through, nudging users toward canonical entry.

## Formations, schema, programs, tags

- Formation is a free-text `start_type` filtered by regex into improper /
  Becket (cw/ccw) / proper / "everything else" — one of ContraDB's weak spots.
- Schema: `dances` (title, choreographer_id, start_type, hook, preamble, notes,
  figures_json, publish enum), `choreographers`, `users`, `idioms`,
  `programs` + `activities` (ordered slots; dance_id nullable so a slot can be
  free text — e.g. a break or announcement), system-wide `tags` + per-user
  `duts` (dance-user-tag) applications.

## Search

- Lisp-in-JSON filter trees, same language client and server:
  structural ops `and/or/no/not/all/&(figurewise)/then(sequence)`; leaves
  `figure` (move + optional param filters with `*`), `formation`, `progression`,
  `progress-with`, `title`, `choreographer`, `hook`, plus numeric compares
  (`count-matches`, tag counts).
- `then` (X followed by Y) is especially valuable for choreography search.
- **Execution is a full in-memory scan in Ruby** — no SQL/index support; the
  known scalability ceiling. The expression model is worth keeping; the
  evaluator should run against an indexed store.

## Pitfalls to avoid (their design debt)

1. Positional `parameter_values` — any change to a move's param order corrupts
   stored data. **Use named params** (`{who: "ladles", beats: 8}`) + schema
   versioning.
2. Plain-text JSON column, no indexing → full scans. We should normalize or
   index (SQLite JSON1/FTS5) from day one.
3. Hardcoded `bogusTerms` conflates community language policy with code — make
   discouraged-term lists data, locally editable.
4. Role system hardwired to exactly two roles named ladles/gentlespoons.
   Keep two-role contra semantics but make role *names* pure presentation.
5. Parallel manually-maintained hashes (`moveCaresAboutRotations…`) drifting
   from move definitions — keep all move metadata in one definition.
6. JS-in-Ruby (MiniRacer) dual-runtime figure engine froze their JS "in an
   archaic dialect of es5" — we need the figure engine in one language, shared
   properly across platforms.
7. Dialect reversal on input only happens in some code paths — make
   canonicalize-on-input a single enforced chokepoint.

## What to adopt

- Canonical-storage + display-dialect architecture, wholesale.
- The move taxonomy and parameter/chooser vocabulary as the seed of our figure
  taxonomy (roadmap 1.8), updated post-2022 (e.g. "gyre" → shoulder round per
  current community/TCB usage).
- Alias mechanism; `custom` figure with dialect-aware free text.
- Lisp-style composable filter expressions incl. `then` sequencing.
- Programs as ordered slots with free-text-only slots allowed.
- `%S` direction placeholder and dialect reversal concepts.
