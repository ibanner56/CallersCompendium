# Research: The Caller's Box data survey

*Roadmap item 1.3 · surveyed 2026-07-10 from `ibiblio.org/contradance/thecallersbox/`*

The Caller's Box (TCB) is the largest contra dance collection: **16,874 dances**
(DB update 2026-06-25). Volunteer project — **Chris Page** (data curation, since
2010) and **Michael Dyck** (code, search, hosting at ibiblio/UNC). Live since 2018.
The web DB is extracted from Chris's personal desktop database, which is not public.

## Key findings

1. **There is a per-dance JSON export**: `dance.php?id=NNNN&format=JSON` (since
   2020). No bulk export/API. Full collection requires iterating ids 1–~19,600
   (sparse; ~16.5% missing, "no dance with id=N" response for gaps).
2. **Notation is highly normalized by design** — far better than we assumed. The
   project's explicit goal is a shared searchable language; changes are applied
   globally (e.g. the Oct 2025 global gypsy → "shoulder round" rename). Figures are
   likely **machine-parseable into our structured model** with a rules-based parser
   plus a manual-review queue, rather than requiring heavy freetext sanitization.
3. **Permissions are per-dance and author-controlled** — this is the central
   constraint on rehosting (see below).

## Record format (JSON)

Fields: `ID, Name, Authors[], InterpretedBy[], Permission, Status, BasedOn[],
FormationBase, FormationDetail, Progression, Direction, Mixer?, Virtual?,
PhraseStructure, Music[], Tunes[], phrases[{name, figures[]}], CallingNotes[],
Appearances[{source,p,lo,vol,no,altnames}], OtherNames[], Videos[],
VirtualVideos[], VariantVideos[], VariantVirtualVideos[]`.

- `Status` may be `Deprecated`/`Broken` (author disavows / dance doesn't work).
- `PhraseStructure` empty = default `4*8*2`; else e.g. `6*8*2` for 48-bar.
- **`License` (e.g. CC-BY-NC on some dances) appears only in HTML, not JSON** — a
  snapshot pipeline that cares about licenses must scrape HTML too.
- HTML pages are `windows-1252` encoded; JSON is the cleaner source (no gloss-link
  markup in figure text).

### Example (id=1, "The Nice Combination", Gene Hubert, CC-BY-NC)

```
A1: (4) Neighbor balance / (12) Neighbor swing
A2: (6) In a line of four, go down the hall (M1-W2-M2-W1) / (2) Neighbor turn as
    couples / (6) ...go up the hall (W2-M1-W1-M2) / (2) Bend the line
B1: (6) Circle left 3/4 / (10) Partner swing
B2: (8) Ladies chain to neighbor / (8) Star left 1
```

## Notation conventions (documented in Brief-glossary.htm / Glossary.htm)

- Every figure line: `(beats) text`. `(0)` = formation label, no beats.
- People: `N` neighbor (`N2`/`N3` future, `N0`/`N-1` past), `P` partner, `M`/`W`
  role, `S` shadow, `C1..C3` corners, `O` opposite, `TB` trail buddy, `1`/`2`
  ones/twos, `1CC/2CC` contra corners, `SRN` same-role neighbor.
- Operators: `;` then · `,`/`||` while · `[]` who does it · `()` detail ·
  `~` partial hey pass · `//` either-or · `&` in fractions (`1 & 1/2`) ·
  `" "` spoken vs `' '` literal-from-source.
- Rotation amounts: allemandes in quarters (`allemande left 1 & 1/2`), circles/
  stars in full turns (`Circle left 3/4`), heys in fractions with pass lists
  (`Hey 1/2 (WR;PL;MR;N2L~)`).
- Formation vocabulary (controlled, complete list on the search form): Duple Minor
  {Improper, Becket, Proper, Indecent, Reverse-progression improper, Progressed
  improper, Cross, Other}, Triple Minor, Three/Four Facing, Solo/Singlet/Doublet/
  Triplet/Quadruplet, Longways 5+, Circle Mixer, Circle of Threesomes, Sicilian
  Circle, Scatter Mixer, Grid Contra/Square, Zia, other.
- Progression: None/Single/Double/Triple/Quadruple/More/Virtual/Other-Weird.
- No difficulty/level field exists.

### Residual variance to handle in the snapshot pipeline

Pre-1900 historical transcriptions (special conventions, own FAQ section); free-text
`CallingNotes`/`FormationDetail`/variant descriptions; ad-hoc `[bracket]`
clarifications; non-default phrase structures; encoding quirks.

## Search capabilities (hints at internal schema)

Substring search on title/author; controlled formation + progression filters;
positive/negative figure-line matching with any/all modes; **per-phrase (A1..B2)
figure search** (2023). Matches our roadmap search requirements almost 1:1.

## Permissions & rehosting (critical)

Four author-controlled tiers: **full** (figures visible), **search** (figures
searchable but hidden; JSON `phrases` comes back empty), **not searchable**
(index-only), **omit** (absent entirely). No site-wide license or ToU; a subset of
dances carry explicit CC-BY-NC (HTML only). Authors can downgrade permission at any
time, so a snapshot can go stale legally as well as factually.

**Conclusions for roadmap 6.2 / 1.13:**

- Do not scrape-and-rehost unilaterally. **Contact Chris Page
  (chriscpage+thecallersbox@gmail.com) and Michael Dyck (jmdyck@ibiblio.org)**
  before building the public snapshot — discuss bulk access (possibly a direct dump
  from Chris's database, avoiding a 20k-request crawl), permission-tier handling,
  and license metadata. They are described as responsive volunteers.
- Snapshot must carry per-dance provenance: TCB id, permission tier at snapshot
  time, license if any, and appearances/attribution.
- Only `full`-permission figures can be redistributed; `search`-tier dances could
  be included as metadata-only stubs with a link back to TCB.
- Community extensions exist (Caller's Box Configurator does Larks/Robins term
  swapping in-browser) — evidence of user demand for our dialect feature.

## Open questions

- Fraction of dances at each permission tier (only a crawl or the maintainers can
  answer).
- Whether the maintainers would prefer to publish an official dump we mirror,
  versus us hosting a derived snapshot.
- How much of the figure corpus parses cleanly into our structured model —
  needs a prototype parser against a sample (Phase 1.8 input).
