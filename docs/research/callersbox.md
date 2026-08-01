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

### Compound figures — `(beats) Name:` with indented children

A figure line ending in a **colon** whose beats are followed by **indented**
child lines is TCB's way of writing one named figure as its component
sub-figures; the children's beats **sum to the parent's**. The children are the
*definition*, not extra choreography. Verbatim example from *Right Where We
Belong* (Isaac Banner, id 19001) A1:

```
(6) Revolving door:
     (4) Partner star promenade 1/2 (WR)
     (2) Women allemande right 1/2
(10) Neighbor swing
```

`Revolving door` (6) == `Partner star promenade 1/2` (4) + `Women allemande
right 1/2` (2); A1 total = 6 + 10 = 16. The import parser must **collapse** such
a unit to the single parent figure carrying the parent's beats (see
`docs/design/imports.md` → *Compound figures*) — counting the children
separately would inflate the section's beat total. When the parent is a
shorthand the taxonomy does NOT model but every child structures, the parser
emits the **children** instead (#295) and keeps the parent's name in a note —
see *The decomposition rule is general* below; the children's own beats already
total the parent's, so the section total is identical either way.


### Grand right and left & flutterwheel — compound shorthands (2026-07-31, issue #295)

Both are represented as **sequences of moves the taxonomy already has**, so
neither adds a `MoveDef` and `contraTaxonomyVersion` is unchanged.

#### Decisive evidence: *334* by Diane Silver, in both databases

The same dance is transcribed in TCB (**#10042**) and ContraDB (**#3403**). TCB
writes the shorthand; ContraDB writes the decomposition:

| | TCB #10042 | ContraDB #3403 |
|---|---|---|
| A1 | `(4) N1 neighbor balance (RH)` · **`(4) Grand right and left (N1R;N2L)`** · `(4) N3 neighbor balance (RH)` · `(4) N3 neighbor box the gnat` | `[6] 1st neighbors balance & pull by right` · `[2] 2nd neighbors pull by left` · `[8] 3rd neighbors right hand balance & box the gnat` |
| A2 | **`(4) Grand right and left (N3R;N2L)`** · `(12) N1 neighbor swing` | `[2] 3rd neighbors pull by right` · `[2] 2nd neighbors pull by left` · `[12] 1st neighbors swing` |

A2 is the clean comparison (no balance folded in): TCB's **4 beats over 2
passes** is ContraDB's **2 + 2**, dancer-for-dancer and hand-for-hand. ContraDB's
figure index (~61 figures, fetched 2026-07-31) contains **neither** a
grand-right-and-left **nor** a flutterwheel, but does contain `pull by dancers`
and `pull by direction`.

#### Pass-code vocabulary (`Glossary.htm`, verbatim)

- **Neighbors** — "Your current neighbor is N1. Your next neighbor in the
  direction of progression is N2. This is followed by N3, N4, and so forth. Your
  previous neighbor is N0. The neighbor before that is N-1."
- **Shadows** — "Shadow S1 is the first shadow you encounter one hands-four away
  from your partner. S2 is one hands-four beyond that, and so forth… There is no
  shadow S0. That'd be your partner."
- **Partners (mixers)** — "Your current partner is P1. The next partner in your
  direction of progression is P2, then P3, and so forth. Your previous partner
  is P0."
- **Corners (square)** — "The non-partner next to you is your corner C1… The
  person across from you ("opposite") is your corner C2. The remaining person is
  your corner C3. … A standard grand right and left is notated
  `(PR;C3L;C2R;C1L)`."
- **First/second corners** — a SEPARATE glossary entry: "A convention from proper
  English Country Dance. First corners are man one and woman two. Second corners
  are woman one and man two."

The last two entries are why `C1`–`C3` are **not** mapped: `ParamVocab`'s
`firstCorners`/`secondCorners` model the ECD *First/second corners*, a different
relationship from TCB's square corners. Mapping them would fabricate. Likewise
`P2`+ (a mixer's future partners) and `N5`+/`N-1`/`S3`+ have no taxonomy token,
and `Ph*` (phantoms) / `TB*` (trail buddy) / bare `R`/`L` name no representable
dancer — every one of those declines the whole line to `custom`.

#### Corpus measurements (full local TCB mirror, 24 107 dance files / 152 589 figure lines)

**`grand right and left`: 353 lines**, of which **128 decompose** to
`pull_by_dancers` sequences. Top decodable shapes: `(N1R;N2L)` 32 ·
`(N3R;N2L)` 26 · `(S2R;S1L)` 15 · `(N1R;N2L;N3R)` 14 · `(PR;S1L;S2R)` 9 ·
`(N2R;N3L)` / `(N1L;N2R)` / `(N4R;N3L)` 4 each. The 225 declines break down as:

| reason | lines | detail |
|---|---|---|
| unmappable pass code | 163 | mixer partner series `P2`+/`P0`/`P-n` 66 · square corners `C1`–`C7` 55 · out-of-range neighbors `N5`+/`N-n` 25 · bare `R`/`L` with no dancer 11 · out-of-range shadows `S3`+/`S-n` 5 · trail buddy `TB` 1 |
| leftover prose outside the pass list | 56 | a second parenthetical 17 · a `[…]` qualifier 16 · other prose/`;`-tail 9 · `Progressive grand right and left` 8 · `Same-role grand right and left` 6 |
| no pass list at all | 3 | |
| degenerate list (`(N1R)`, `(N1R;;N2L)`) | 2 | |
| beats do not divide by the pass count | 1 | `(8) Grand right and left (N0L;N1R;N2L)` |

Beats vs. pass count over the 129 lines that reach the beats check: 4/2 ×89,
6/3 ×29, 6/2 ×4, 8/4 ×3, 8/2 ×3 — **128 of 129 divide evenly**; the single
exception stays custom rather than inventing an uneven 3+3+2 split.

**`flutterwheel`: 143 lines, 143 of them compound parents TCB decomposes
itself.** The children are always an allemande plus a star promenade, summing
exactly to the parent:

```
(8) Neighbor flutterwheel:
     (4) Women allemande right 1/2
     (4) Neighbor star promenade 1/2 (WR) (hand-in-hand with neighbor)
```

Variants seen: `Partner` 53 · `Neighbor` 29 · `Partner reverse` (men allemande
LEFT) 23 · `Neighbor reverse` 8 · `(along the set)` · `[with N2]` ·
`N2`/`N3 neighbor` · `Shadow` · `[Top two couples]` bracket prefixes · 6-beat
parents splitting `(2)+(4)` · and a `(7-12)` beat SPAN. Two
`(12) Grand partner flutterwheel:` blocks have a `(4) Women star right 1/2`
child that does not structure, so they correctly stay whole-custom.

`Glossary.htm` on **Flutterwheel**: "When facing across, the right-hand people
(typically the women) right-hand turn 1/2 to the other side… They then continue
to the other side, centers letting go of right hands and bending the line to
face across." · *History*: "This is an MWSD square dance figure. It appears often
in MWSD contras but has never successfully made the leap to traditional
contras." · *Notation*: "While one of the pieces is listed as a star promenade,
that's only a loose approximation of the hand-hold. There is no butterfly
whirl." — i.e. TCB's own children are an approximation TCB chose, which is
exactly what we re-emit.

#### The decomposition rule is general: 877 blocks across 81 parent names

Flutterwheel motivated the rule, but "unknown parent + every child structures"
is a property of TCB's compound convention, not of one figure. Measured over the
full mirror, the compound blocks split as:

| block class | blocks | behaviour |
|---|---|---|
| parent structures to a taxonomy move | 110 | **unchanged** — collapse to the parent (`revolving_door`, …) |
| parent does not structure, ALL children do | **877** | emit the children (#295) |
| parent does not structure, some child fails | 788 | **unchanged** — one whole-custom parent |

The 877 span 81 distinct parent names. The largest families, with a verbatim
corpus block each:

| parent shorthand | blocks | example (dance) |
|---|---|---|
| `interrupted square through 2` / `… 4` (+ `[with …]`) | 331 | `(8) Interrupted square through 2:` → `(4) Partner balance (RH)` + `(4) Square through 2 (PR;N1L)` (#19238) |
| `modified right and left through with partner/neighbor` | 141 | `(8) Modified right and left through with partner:` → `(4) Pass through across (N3R)` + `(4) Partner California twirl` (#6523) |
| `flutterwheel` (all variants) | 135 | `(8) Neighbor flutterwheel:` → `(4) Women allemande right 1/2` + `(4) Neighbor star promenade 1/2 (WR)` (#6489) |
| `open ladies/gents chain to partner/neighbor` | 66 | `(8) Open ladies chain to neighbor:` → `(4) Women allemande right 1/2` + `(4) Neighbor allemande left 3/4` (#6165) |
| `georgia rang tang` | 47 | `(16) Georgia Rang Tang:` → 4 children: allemande, pass, allemande, pass (#300798) |
| `hey along sides` | 34 | `(16) Hey along sides:` → 4 children: pass through, shoulder round, pass through, shoulder round (#6000) |
| `allemande x`, `catch all eight`, `corner trade 2`, `do paso`, `dixie style to a wave`, `ones reel up the set`, `vicious circle`, `modified revolving door`, … | ~123 | `(10) Catch all eight:` → `(4) Neighbor allemande right 1/2` + `(6) Neighbor allemande left 1 & 1/4` (#11487) |

Because the rule is this broad, the parent name is **preserved verbatim
(post-scrub) as a note on the first emitted child**. The qualifiers carry real
choreographic meaning — "interrupted", "modified", "open" — and `Georgia Rang
Tang` / `Catch all eight` are names a caller searches for, so dropping them would
be a genuine fidelity loss even though the movement is fully expressed by the
children. `Modified revolving door` (#19305) is the sharpest illustration: the
bare `Revolving door` collapses to the taxonomy move, while the "Modified"
variant decomposes and keeps its name in the note.

Whole-corpus effect of #295 (grand right and left + the general compound rule),
measured with `tool/tcb_coverage.dart` on the same mirror before and after:
**75.09% → 76.24%** of figure lines structured.


### Residual variance to handle in the snapshot pipeline

Pre-1900 historical transcriptions (special conventions, own FAQ section); free-text
`CallingNotes`/`FormationDetail`/variant descriptions; ad-hoc `[bracket]`
clarifications; non-default phrase structures; encoding quirks.

### Figure-line sample: mad robin & butterfly whirl (2026-07-31, issue #295)

Method: 900 random dance ids fetched via `dance.php?id=N&format=JSON`
(517 returned data — the rest are the documented ~16.5% id gaps), yielding
**5,147 figure lines**. Used to source the taxonomy-v20 param enrichment.

| move | lines | share | states a direction | states the other fact |
|---|---|---|---|---|
| `mad robin` | 24 | 0.47% | 24/24 | 24/24 state an "around `<target>`" (neighbor 17, partner 7) |
| `butterfly whirl` | 18 | 0.35% | 18/18 | 18/18 name the pair (partner 13, neighbor 3, N2 neighbor 2) |

Attested wordings: `Mad robin clockwise around neighbor`, `Mad robin
counterclockwise around partner`, `Mad robin clockwise around neighbor N2`,
`Mad robin clockwise 1 & 1/2 around neighbor`, `Partner butterfly whirl
counterclockwise`, `N2 neighbor butterfly whirl clockwise`. A rotation amount
appears on 2/24 mad robin and 4/18 butterfly whirl lines. Note both N-tag word
orders occur — `around neighbor N2` and `N2 neighbor …` — for the same
relationship.

`Glossary.htm` is the controlled-vocabulary authority for what those words mean:

- **Mad robin** — "A sideways do-si-do / seesaw… While facing one person, you
  travel in an oval **around the person at your side**." · Notation: "**Who you
  go around is listed.** A clockwise mad robin begins with the left-hand person
  going in front, the right-hand person going behind." · Defaults: "The person
  you face is across the set. You are travelling around the person on the side
  of the set."
- **Butterfly whirl** — "Two people face the same direction, with nearest arms
  on each other's back, and **rotate clockwise or counterclockwise** about a
  common center. One person is going backwards. This typically follows a star
  promenade."

Both facts are therefore TCB *notation*, not caller flourish — which is what
justifies modeling them even though ContraDB's `libfigure` models neither (see
the v20 note in `docs/design/figure-taxonomy.md`). Critically, TCB's "around
`<X>`" is the pair you ORBIT, whereas ContraDB's mad robin `who` is the pair
that steps IN FRONT: different concepts, so they map to different params.

### Gate lines (surveyed 2026-07-31 over the full 24,107-dance mirror)

186 figure lines contain a gate. TCB and ContraDB describe the SAME figure from
opposite ends, which is why they merge cleanly into one taxonomy move (v22):
ContraDB states how a gate ends and never its amount; TCB states the rotation
sense and amount and never a facing.

- **Rotation sense** — `counterclockwise` 77, `mirror` 75, `clockwise` 34.
  `mirror` (the two-couple gate) has no ContraDB equivalent at all.
- **Turn amount** — `1` x96, `1 & 1/4` x34, `1/2` x27, `3/4` x16, `1/4` x6,
  absent x7.
- **Beats** — 8 x122, 4 x33, 6 x15, 2 x13, 3 x3. (Not the fixed 8 ContraDB
  pins.) The three 3-beat lines (#6819, #20257, #19476) are all the SAME real
  pattern rather than typos — a 6-beat compound split evenly into 3 + 3:
  `(6) Modified right and left through with partner:` →
  `(3) Pass through across (NR)` + `(3) Partner gate counterclockwise 1/2`.
- **Subject** — the *pairing*: `Neighbor`, `N0`/`N1`/`N2`/`N3 neighbor`,
  `Partner`, `P1 partner`, `Shadow`, `Same-role neighbor`. This is NOT
  ContraDB's subject, which names the side that backs up and whose chooser
  cannot even hold `neighbors`/`partners` — hence the separate `pair` slot.
- **Which side moves lives in a trailing parenthetical**, on 82 of the 186
  lines: `(ones forward)` x46, `(twos forward)` x13, `(men stay put)` x4,
  `(M1+W2 forward)` x4, `(ends forward)` x4, `(woman one and man two forward)`
  x2, `(threes forward)` x2, and singletons `(women are posts)`,
  `(centers are posts)`, `(twos and fours forward)`, `(ones and threes
  forward)`, `(women forward)`, `(twos split ones)`. This is the same fact
  ContraDB encodes in its subject/object split. A `"<dancers> forward"`
  annotation whose dancers resolve to a set we model (60 of the 82) maps onto
  the merged move's `whom`, which means precisely "walks forward". The rest are
  preserved verbatim as a note: the **stationary** phrasings
  (`(men stay put)`, `(women are posts)`, `(centers are posts)`) fit neither
  `whom` (walks forward) nor `who` (backs up — also moving), and the remaining
  "forward" phrases name sets we do not model.
- **TCB never states a cardinal ending facing for a gate.** The only "to face"
  wording found names a *dancer* (`to face N2`), not a direction.

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

### Wave-balance corpus census (2026-07-31, issue #295)

Method: full local mirror of the TCB JSON export — **24,107 files**, of which
20,516 carry redistributable figures. Counted every figure line whose text
begins with `Balance` and names a wave.

**4,613 such lines** across **296 distinct wordings** — the single largest
`custom` bucket before taxonomy v21.

| bucket | lines | disposition |
| --- | --- | --- |
| `Balance wave of four …` | 2,764 | → `form_short_waves{balance}` |
| `Balance long wave …` | 1,595 | → `form_long_waves{balance}` (or custom) |
| `Balance wave of two/three/five/six/seven/eight` | 181 | stays custom |
| `Balance in­tersecting / interlocking waves` | 59 | stays custom |
| other (`Balance circular wave`, `Balance wave across`) | 14 | stays custom |

Top wordings: `Balance wave of four (NR,WL)` ×776, `Balance long wave (NR, women
face in)` ×292, `Balance wave of four (PR,WL)` ×285, `Balance wave of four
(NR,ML)` ×249, `Balance wave of four (NL,MR)` ×195, `Balance long wave (PR, men
face in)` ×145.

**The `()` detail is structured, not prose.** For a wave of four, **2,560 of the
2,764 lines (92.6%)** match exactly `(<relationship-code><Hand>,
<role-code><OppositeHand>)` — `(NR,WL)`, `(PR,ML)`, `(N2R,WL)`, `(SR,WL)` — and
of every pair that parsed, only **one** states the same hand twice. The role
pair (`M`/`W`/`1`/`2`) is the **centre** of the wave and the relationship pair
(`N`/`N0`–`N4`, `P`/`P1`, `S`/`S1`/`S2` — the same `tcbPassPeople` map the hey
and grand-right-and-left decoders use) its **sides**, which is the same
centre/sides model ContraDB's ocean wave already uses. Long waves use
`(<relationship-code><Hand>, <role> face in)`: 858 `women face in`, 568 `men face
in`, 64 `twos face in`, 13 `ones face in`.

Adjacency (why the mapping is safe): ~44% of these lines are followed by a move
the existing forward balance-merge already claims (swing, petronella, rory,
box the gnat, box circulate, slide); 1,091 are preceded by a wave-forming clause
(`Pass the ocean` ×395, `form wave of four …` ×~480, `form long wave …` ×~130);
the remainder is the implicit case, dominated by allemandes.

Forming wordings in the same corpus: `form wave of four` ×632, `form long wave`
×385, `form wave of four with N2` ×232, `form long wave in center` ×210,
`form wave of four with shadow` ×58. The **plural** `form long waves` occurs
exactly **once** in all 24,107 files (dance 2463 *Gypsy Star* B1) — TCB's
singular "long wave" is the overwhelmingly dominant forming wording.

86 balance lines name a formation the taxonomy has no model for
(`interlocking` ×43, `circular` ×27, `intersecting` ×16). These stay `custom`
on BOTH the promotion and the trailing-balance-fold paths, so the qualifier is
never dropped from a structured figure. Note that 86 is a census of the
WORDING, not of anything that was previously mis-structured: 85 of those lines
already fell to custom, and only **one** (dance 2463 *Gypsy Star* B1, the sole
plural `form long waves` line) was ever folded into a wave figure.

Effect of taxonomy v21 measured by running the real adapter over the whole
mirror: custom figures 24,775 → 22,272, structured share 76.24% → **78.69%**,
with per-dance beat totals byte-identical for all 20,515 dances and no
forward-merge move losing a balance.

### Figure-line census: courtesy turn (2026-07-31, taxonomy v23)

Method: the real `CallersBoxAdapter` run over the whole 24,107-file mirror
before and after the change (20,516 dances with figures). Every line mentioning
"courtesy" was extracted from `phrases[].figures[]` — **228** lines.

Before v23, **all 228 fell to `custom`**: the taxonomy had no such move, so
there was no existing reading to regress.

**Line shape:** `({beats}) {who} courtesy turn[, face N{n}][ clockwise]`.

`who`, over the 115 lines the recognizer claims:

| token | lines | | token | lines |
|---|---|---|---|---|
| `partners` | 53 | | `shadows` | 1 |
| `neighbors` | 39 | | `thirdNeighbors` | 1 |
| `nextNeighbors` | 13 | | `twos` | 1 |

**Beats: 4 x97, 2 x8, 3 x6, 6 x4.** Note this is the census over the *claimable*
lines, which is the only population `goodBeats` should be drawn from. A naive
grep for "courtesy turn" also turns up a `5` and five `8`s, but they belong to
lines that can never structure as this move — `(5) Neighbor promenade across;
courtesy turn 3/4` is a `;` compound, and the `8`s are
`right and left through …("courtesy fling")` lines. The marginal 2/3/6 values
were each checked in context and are genuine timing: dance 2957 writes
`(8) Modified ladies chain to partner:` → `(6) Women allemande right 1 & 1/2` +
`(2) Partner courtesy turn`, dance 174 `(5) Women allemande right 1` +
`(3) Neighbor courtesy turn`, dance 14823 `(10) Star left 1 & 1/4` +
`(6) Partner courtesy turn`.

**`direction`:** stated on 10 lines; **all 10 say `clockwise`**.
`counterclockwise` is unattested — consistent with the figure's mechanics (the
couple wheels as a unit), so `clockwise` is a real default rather than a guess.

**⚠️ The ending facing is a DANCER, not a direction.** Every in-line ending
facing is a neighbor relationship — `, face N2` x8, `, face N3` x4, `, face N0`
x1 — which `tcbPassPeople` maps to `nextNeighbors` / `thirdNeighbors` /
`prevNeighbors`. Despite the shared name, this is **not** the `in`/`out`/`up`/
`down` domain `swing.endFacing` and `gate.face` use.

The corpus **does** contain cardinal facings on courtesy-turn lines — `Ones
courtesy turn; face down`, `Partner courtesy turn (power turn); face out`,
`Partner courtesy turn 2; face clockwise around the major set` — and it is worth
being precise about why they do not contradict the finding. Every one of them
uses a **semicolon**, and the CallersBox `;`-compound splitter is
all-or-nothing: the `; face down` clause structures to nothing, so the whole
line stays `custom` and the cardinal never reaches a slot. That is a property of
the compound rule, not of the facing grammar — if the `;` handling is ever
loosened, cardinals would start arriving at a dancer-valued param.

**⚠️ There is no two-dancer form.** Searching for `<X> courtesy turn <Y>` finds
nothing: `who` always names the pairing, never a turner plus a turnee. So the
`whom` slot, though modeled for manual authoring, is never filled on import.

**Wordings that stay `custom` (and why).** 30 lines write a **chain** — or a
right-and-left-through / promenade, which end the same way — together with its
courtesy turn (`[W1+W2] Ladies chain, with half courtesy turn in center`,
`Ladies chain to partner with double courtesy turn`, `Right and left through
with partner with double courtesy turn`, `Neighbor promenade across with double
courtesy turn`). Emitting a standalone courtesy turn for one of these would
double-count both the figure and its beats. 7 lines say **"arky"** (roles
reversed — unmodeled here, and ContraDB has no such concept either). 6 state a
**rotation amount** the four-slot model has no param for. The rest name dancers
the vocabulary deliberately does not map (`phantom partner`, `P1`/`P2`/`P4
partner`, `next corner`, `opposite neighbor`, `bottom couple`, `fives`). A
further 19 lines contain the word "courtesy" but no courtesy turn at all — the
`("courtesy fling")` variant of a right and left through.

**Annotations.** 7 claimable lines carry one (`(in center)` x4, `(continued)`
x3, plus bracketed subjects `[Ones and threes]` / `[Sides]`). The recognition
pass strips `()`/`[]`, so a structured match would have silently lost them; a
front-end pre-recognizer preserves them verbatim as the figure's note, the same
mechanism `gate` uses for `(ones forward)`.

**Whole-corpus effect of taxonomy v23**, measured with the same harness on the
same mirror: custom figures 22,272 → **22,180** (−92), structured share
78.69% → **78.78%**, per-dance beat totals byte-identical for all 20,516
dances. The figure count rises by 14 because **13 compound parents**
(`Modified ladies chain to partner:`, `Wheel chain to neighbor:`) now
decompose — their all-or-nothing child list was previously blocked by the one
child that could not structure.

### Figure-line census: walk forward (2026-08-01, issue #733)

Method: the real `CallersBoxAdapter` run over the whole 24,107-file mirror,
before (`22d5664b`, i.e. after #734) and after, restricted to the
**`Permission == "full"`** population (11,499 dances, 104,018 figure lines
before / 104,078 after). Line counts below are occurrences of a
`phrases[].figures[]` line over that same population.

**⚠️ Mixers (#732) are NOT excluded here, and that is why the structured share
below does not line up with the 80.96%/82.55% series #734 quotes.** That series
is measured over a non-mixer population (100,649 figures); this one includes
mixers (104,018). The two are not comparable as absolutes — the *deltas* are.
Whenever a figure here is set beside one from that series, check the population
before treating them as the same measurement.

**⚠️ Read the dance denominator carefully — it is narrower than the one the
v21/v23 sections above use, and that is not a shrinking corpus.** Of the
24,107 mirror files, 3,591 are `NOT_FOUND` placeholders, leaving **20,516**
parseable dance records — the denominator those sections quote. Only the
**11,499** `full` ones carry figures at all (`callersbox_adapter.dart`
returns `const []` for every other tier), so the remaining 9,017 are
metadata-only stubs with zero figures and are byte-identical under any figure
change, trivially. Only the *dance count* in the beat-total gate below is
stated over the narrower, figure-bearing 11,499.

**879** lines mention "walk forward". It is not one family, and none of the
three real families needs a taxonomy move:

| group | shape | lines | mapping |
|---|---|---:|---|
| 1a | `[<dancer>] walk forward; form long wave in center` | 142 | `form_a_long_wave` **only**, `who` transferred |
| 1b | `walk forward; form wave of four with <dancer>` | 127 | `pass_through()` + `form_short_waves(sides: …)` |
| 2 | `walk forward to <dancer>` | 181 | `pass_through()`, destination kept as the note |
| 3 | bare / qualified / diagonal | rest | left `custom` |

Group 1a's exact wordings: `Women walk forward; form long wave in center` x70,
`Men …` x66, `Ones …` x4, `Women walk forward; form long wave` x1,
`… form long wave [with phantoms]` x1 (`[…]` is stripped for recognition, so
this one line loses its bracket exactly as a standalone
`Form long wave [with phantoms]` line already does — noted for #729's audit).

Group 1b: `with N2` x92, `with shadow` x19, `with N3` x9, `with partner` x3,
`with N0` x2, `with N1` x2. Group 2: `to N2` x139 (+1 annotated), `to shadow`
x18, `to N1` x6 (+1 paired with a wave clause), `to partner` x6, `to N0` x4,
`to N3` x4 (+1 annotated, +1 paired).

**⚠️ `walk forward to N2` names the DESTINATION, not a dancer you pass.** You
walk forward past your CURRENT neighbour and arrive facing N2 — the standard
contra progression — so it is exactly a pass through. Corpus lines that dance
with the same dancer on the next line (`(4) Walk forward to N1` /
`(12) N1 neighbor swing`) confirm the mapping rather than contradict it: a pass
through is what puts you facing the dancer you then swing.

**⚠️ The subject cannot ride on a pass through.** `pass_through` has no `who`
param, so `Women walk forward to N2` / `Men walk forward; form wave of four
with shadow` stay `custom` rather than silently dropping the role. `who` DOES
transfer on group 1a, and it must: every subject-bearing line in that group
states the role on the WALK clause and none on the wave clause, while
`form_a_long_wave.who` defaults to `role2s` — absorbing without transferring
would render all 66 men's lines as women's figures. Measured after the change
over these lines specifically, `form_a_long_wave.who` is `role1s` x66,
`role2s` x72, `ones` x4 (the corpus-wide totals are 3 higher in each role,
from pre-existing lines this change does not touch).

**⚠️ The diagonals are declined, deliberately.** On **55** lines the
walk-forward clause itself carries a diagonal travel qualifier —
`walk forward on [slight|sharp] left/right diagonal [(optional spin)]`. (62
lines mention both "walk forward" and "diagonal"; on the other 7 the diagonal
is somewhere else, e.g. inside the `(…)` annotation of
`Walk forward to N2 (women going on slight right diagonal, …)`.)

**29 of the 55 are the actual cost of declining** — measured by flattening the
qualifier away and re-parsing: those 29 would structure end-to-end without it,
while the other 26 stay `custom` for independent reasons (`form wave of two`,
`form intersecting waves of four`, `form two-faced line`, a bare diagonal walk
with no formation clause). Of the 29, **28** are group-1b-shaped
(`…; form wave of four with <dancer>`) and **1** is group-2-shaped
(`Walk forward on left diagonal (optional spin) to N1`); **19** also carry
`(optional spin)`.

All 29 stay `custom` rather than being flattened into a plain `across` wave:
`form_a_long_wave` has no `dir` param at all, and `form_short_waves` does but
its domain (`set_direction_acrossish`) describes the WAVE's orientation while
the source states the direction of TRAVEL. The recognizer already refuses
TCB's *explicit* `form diagonal wave of four` on the same prefer-custom
grounds, so inferring that value from a travel qualifier would be strictly
more aggressive than what the parser already declines. `(optional spin)` has
no slot on any of the three moves either.

**Whole-corpus effect**, same harness, same mirror: **451** of the 879 lines
newly structure end-to-end (**0 → 451**; no line shape stops structuring).

> **A harness caveat worth recording, because it nearly went into this doc as
> fact.** A first pass reported "193 → 643". That check tested only whether
> each top-level figure was non-`custom`, and a `meanwhile` container is
> non-`custom` even when every one of its concurrent sides is `custom` — so it
> counted 193 `||` lines as already-structured at base when in truth **none**
> of them was. Recursing into the sides gives 0 → 450. The *delta* was
> identical either way (643 − 193 = 450 − 0), which is exactly why it survived
> and the absolutes did not: **deltas are portable across harnesses, absolute
> counts are not.** Quote the delta; re-derive an absolute against the harness
> you are comparing to.

Custom figures 20,452 → **19,996** (−456), structured share
80.34% → **80.79%** (+0.45pp), per-dance beat totals **byte-identical for all
11,499 dances**. The figure count rises by 60 (group 1b emits two figures where
one custom stood; group 1a emits one). 424 dances see a per-FIGURE beat
sequence change, all of them a `custom` line becoming structured except **4**
where the existing trailing balance-wave fold (#577) now claims the
`Balance wave …` line that follows the newly-structured wave: 3 dances move a
balance off a following `box_the_gnat` and 1 off a following `swing`, onto the
wave the source line actually names.

**One line structures only because #733 and #734 combine**, and it is worth
recording as the shape of the interaction: dance 8166 B1
`(13-16) [Heads (ones+fours)] Pass through across (NR); face partner; walk
forward to partner` now yields `pass_through{dir: across}` carrying #734's
note-ified `face partner`, plus #733's `pass_through` carrying `to partner`.
Neither change alone structures it — #734 could not, because the trailing walk
clause failed; #733 could not, because the middle facing clause failed. Beats
are unchanged (8 + 0 = the source's 8). Its `[Heads (ones+fours)]` / `(NR)`
annotations are dropped, which is the pre-existing bare-`pass_through`
annotation gap under #729's audit item, now reached by one more line. `atypical_beats` warnings rise by 340 (20,463 → 20,803), almost all a 4-beat
`pass_through` (`goodBeats: [2]`) — a leisurely pass through is a warning, not
an error, and no beats param is fabricated to suppress it.

## Open questions

- Fraction of dances at each permission tier (only a crawl or the maintainers can
  answer).
- Whether the maintainers would prefer to publish an official dump we mirror,
  versus us hosting a derived snapshot.
- How much of the figure corpus parses cleanly into our structured model —
  needs a prototype parser against a sample (Phase 1.8 input).
