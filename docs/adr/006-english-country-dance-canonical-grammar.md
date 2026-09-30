# ADR-006: English Country Dance canonical figure grammar

- **Status**: Proposed. Draft v0.2 (29 September 2026; revised
  30 September 2026 for the expanded transcription set and four added
  figures), circulated for review
  by ECDDB contributors and other ECD callers, dancers and archivists before
  anything is implemented.
- **Roadmap item**: "ECD and Squares support" (Later milestones in
  [ROADMAP.md](../ROADMAP.md))
- **Deciders**: Maintainers, with community review

**What we're asking reviewers for:** corrections, missing vocabulary,
community practice, and answers to the
[open questions](#9-open-questions-for-reviewers).

This ADR is longer than most because it doubles as a review document for
readers outside this repository. In the template's terms: §2–§3 are the
*context*, §5–§7 the proposed *decision*, §3 and §5 the *rationale*, and
§9–§10 the open *consequences* and *revisit triggers*. Once accepted, the
resulting ECD taxonomy follows the versioning process in
[figure-taxonomy.md](../design/figure-taxonomy.md).

---

## Contents

1. [Summary](#1-summary)
2. [Background: why a canonical grammar?](#2-background-why-a-canonical-grammar)
3. [What we studied](#3-what-we-studied)
4. [Terms used in this proposal](#4-terms-used-in-this-proposal)
5. [Design principles](#5-design-principles)
6. [Shared parameter vocabulary](#6-shared-parameter-vocabulary)
7. [The candidate figure registry](#7-the-candidate-figure-registry)
8. [Worked examples](#8-worked-examples)
9. [Open questions for reviewers](#9-open-questions-for-reviewers)
10. [Out of scope for this pass](#10-out-of-scope-for-this-pass)
11. [How to respond](#11-how-to-respond)
12. [Appendix: how the contra grammar renders shared figures](#appendix-a-how-the-contra-grammar-renders-shared-figures)

---

## 1. Summary

Caller's Compendium is an app for callers to store, search, edit and print
dances. For contra dance it already stores each figure as structured data
("who does what, with which hand, how far") rather than free text. We would
like to do the same for English Country Dance, and we want the vocabulary to be
right before any of it is built.

This document proposes a small set of named movements, about 44 candidates,
each described by a fixed list of named parameters. For example, a right-hand
turn once around by partners is stored as the movement `hand_turn` with
`who = partners`, `hand = right`, `travel = 1`. It is not stored as a separate
"right-hand turn partners" entry. The goals are:

- **Minimal.** One entry per distinct movement. Variations of hand, side,
  direction, extent and who dances become parameters, not new entries.
- **Canonical.** Each movement has one stable ID. Regional and historical
  wording ("gypsy", "Honour", "square hey") is kept as searchable aliases and
  source text, and does not become extra entries.
- **Faithful to sources.** If a source doesn't say which hand, shoulder or
  direction, the stored value is *unspecified*. The grammar never fills in a
  "usual" value and presents it as something the source said.
- **Readable.** Every stored figure renders back to a plain English line a
  caller could read aloud.

The proposal is incomplete on purpose. Of 44 candidate movements, 36 have
draft parameters and 8 are deferred because we lack the evidence or the
community knowledge to define them well. A larger set of dance
transcriptions (§3) turned up figures the first list lacked. Four of them
are now added (siding, turn alone, box the gnat, swat the flea), but *up a
double and back* is still open (§7.6). Those open questions are where
ECDDB contributors can help most.

## 2. Background: why a canonical grammar?

Dance instructions appear in many forms: historical prose (Playford, Walsh),
modern publications, caller's cards, database entries, and spoken teaching in
videos. The same movement is written in many ways ("RH turn", "turn by the
right", "right hands round"), and one word can mean different movements in
different places. Free text is fine for reading a single dance but poor for:

- **Search:** "find dances with a half poussette" or "dances with a circular
  hey for two couples."
- **Consistency:** printing a program where every card uses the same words.
- **Dialect-aware display** (via the app's
  [dialect system](../design/dialect.md)): showing the same stored dance with
  Honour/Honor spelling, or with role terms (men/women, larks/robins, or
  positional terms) chosen by the caller.
- **Import and exchange:** bringing dances from sources such as ECDDB into a
  caller's personal collection without losing detail or inventing any.

The contra grammar in Caller's Compendium was built to import from ContraDB
and The Caller's Box. Where ECD and contra share a concept, this proposal
reuses the contra **parameter names** (`who`, `whom`, `hand`, `travel`, ...)
so that tools and editors behave consistently. ECD still **owns its own
movement definitions**. An ECD `poussette` is not assumed to mean exactly what
a contra `poussette` means just because the words match. Appendix A lists the
contra renderings that several entries below refer to.

## 3. What we studied

The grammar was drafted from these sources. The limits of each are stated
because they determine how much confidence each entry deserves.

**Antony Heywood's figure catalogue** at
[barndances.org.uk](https://barndances.org.uk/Antony/). Filtered to
English-style dances, it has **527 active figure labels**. **456** of those
appear in at least one English-style dance card and 71 do not. The catalogue
is an excellent inventory of *vocabulary*: which figure names exist and how
they are spelled. Its dance cards summarize which figures a dance contains.
They are not full transcriptions. They do not reliably give phrase or bar
order, repeats, who dances, or what happens at the same time.

**UpaDouble** ([upadouble.info](https://www.upadouble.info/)) figure
definitions and dance videos. We matched **23,944** Heywood dance cards
against **3,680** UpaDouble records by title: 1,781 exact matches, 273 after
normalizing spelling, and 16 ambiguous. A title match shows that two records
refer to the same *title*. It does not show that the choreography or style is
the same. Some titles are shared by an English dance and a contra dance (for
example *Chrysalis*: Heywood
[5943](https://barndances.org.uk/Antony/dancecard.php?ID=5943) is English,
[7513](https://barndances.org.uk/Antony/dancecard.php?ID=7513) is contra).

**Video captions and spoken teaching.** We treated a caption as evidence only
when it clearly paraphrased a specific occurrence and stated at least two
facts about the figure (for example actor and hand, or extent and direction).
Keyword hits, garbled speech recognition and catalogue co-listing did not
count.

**Detailed dance transcriptions from teaching videos.** These are the
strongest evidence we have for how figures are actually called, because each
records the exact on-screen caption for every figure, in order, with its
phrase label. The set now covers **16 dances**, all checked against
Heywood's catalogue as `Style: English`:

- A first batch of six. Four completed (*The Farmer's Joy*, *The American
  Husband*, *Alexander's Birth Day*, *The Eliza*). *The Happy Pilgrim*
  stopped partway, and *Barbarini's Tambourine* produced only a draft that
  needed repair.
- A second batch of twelve, which added ten new dances and gave clean
  transcriptions of two from the first batch. *Barbarini's Tambourine* is
  now complete: its wording matches the earlier draft. *The Farmer's Joy*
  is unchanged.

| Dance | Heywood ID | Formation (from the transcript) | Batch |
| --- | ---: | --- | --- |
| The Farmer's Joy | [14769](https://barndances.org.uk/Antony/dancecard.php?ID=14769) | Proper duple minor | 1, 2 |
| Barbarini's Tambourine | [198](https://barndances.org.uk/Antony/dancecard.php?ID=198) | Proper duple minor | 1 (draft), 2 |
| The American Husband | [184](https://barndances.org.uk/Antony/dancecard.php?ID=184) | Sicilian circle / triple minor | 1 |
| Alexander's Birth Day | [5286](https://barndances.org.uk/Antony/dancecard.php?ID=5286) | Facing couples | 1 |
| The Eliza | [1044](https://barndances.org.uk/Antony/dancecard.php?ID=1044) | Longways duple | 1 |
| The Happy Pilgrim | [22537](https://barndances.org.uk/Antony/dancecard.php?ID=22537) | 4-couple Becket | 1 (partial) |
| Beach Spring | [5613](https://barndances.org.uk/Antony/dancecard.php?ID=5613) | 4-couple longways | 2 |
| Christina | [4525](https://barndances.org.uk/Antony/dancecard.php?ID=4525) | Improper duple minor | 2 |
| Double Jubilee | [14575](https://barndances.org.uk/Antony/dancecard.php?ID=14575) | 3-couple longways, mixer | 2 |
| Hambleton's Round O | [1461](https://barndances.org.uk/Antony/dancecard.php?ID=1461) | Proper triple minor | 2 |
| Helena | [1540](https://barndances.org.uk/Antony/dancecard.php?ID=1540) | 4-couple longways | 2 |
| Honeysuckle Cottage | [5299](https://barndances.org.uk/Antony/dancecard.php?ID=5299) | Improper duple minor | 2 |
| King of Poland | [1910](https://barndances.org.uk/Antony/dancecard.php?ID=1910) | Improper duple minor | 2 |
| Midwinter Maggot | [5895](https://barndances.org.uk/Antony/dancecard.php?ID=5895) | Proper duple minor | 2 |
| News from Tripoly | [2548](https://barndances.org.uk/Antony/dancecard.php?ID=2548) | Proper duple minor (originally triple) | 2 |
| The Shrewsbury Lasses | [3275](https://barndances.org.uk/Antony/dancecard.php?ID=3275) | 3-couple longways (originally triple) | 2 |

The second batch alone has 100 figure captions. The dances range from a
1698 Playford publication to 2015, across duple, triple, three-couple,
four-couple and circle formations. §7.6 summarizes what the second batch changed.

Limits of this evidence:

- **One interpretation per dance.** Each transcription describes one
  performance of one interpretation. None of them is proof of a universal
  rule.
- **One source.** Every video comes from UpaDouble, so the wording reflects
  that site's captioning style. Four of the dances are by one deviser, Gary
  Roodman.
- **Uneven timing.** Bar ranges come from video timing and are approximate.
  They are good enough for this proposal, which does not use bar timing
  (§5.5).
- **Known gaps in three transcripts:**
  - *Double Jubilee*'s phrase labels were inferred, not shown on screen.
  - *Christina*'s bar ranges are unresolved.
  - Two of *The Shrewsbury Lasses*' captions are in uncertain order.

**A lesson learned about style filtering.** An early summary counted four
videos as support for "rollaway". Two of those dances (*California Twirlin'*,
*Marshmallows in Flight*) turn out to be Heywood-classified **contra**
dances. Only *The Happy Pilgrim* and *How Great is the Pleasure* are English.
We now check the dance's style, not just the figure's name, before counting
any source as ECD evidence. Reviewers who know of mis-styled or homonymous
records are especially welcome to say so.

## 4. Terms used in this proposal

| Term | Meaning here |
| --- | --- |
| **Movement** (or *move*) | A canonical entry in the grammar, such as `set`, `hand_turn` or `poussette`. Has a stable `snake_case` ID. |
| **Parameter** | A named property of a movement, such as `who`, `hand` or `travel`. Each movement declares which parameters it accepts. |
| **Figure** | One stored line of a dance: a movement plus parameter values, e.g. `hand_turn(who=["partners"], hand=right, travel=1)`. |
| **Dance** | An ordered list of figures, with phrase and bar information held separately. |
| **Alias** | Source wording that maps to a movement, sometimes fixing a parameter. "RH turn" maps to `hand_turn` with `hand=right`. |
| **Selector** | A token naming dancers: `partners`, `neighbors`, `ones`, `firstCorners`, `role1s`, ... |
| **Role-neutral** | Stored dances use `role1`/`role2`. Men/women, larks/robins, gents/ladies, or positional terms are applied only when the dance is displayed. |
| **Unspecified** | "The source did not say." A real stored value, different from any concrete default. |
| **Container** | A structural figure that groups other figures. There are only two (see §5.6). |

## 5. Design principles

These were decided by the Caller's Compendium maintainer after reviewing the
first draft. They are open to challenge but are no longer merely proposed.

### 5.1 ECD owns its movement IDs, but shares parameter names

Where ECD and contra describe the same *concept*, they use the same
parameter name. The allowed values and defaults may still differ. A
movement's ID, meaning and display belong to ECD. Where a source-specific
count has no contra equivalent (such as `changes` in rights and lefts), ECD
defines its own parameter.

### 5.2 `who` is a list

In ECD, `who` is always stored as a **list** of selector tokens, even when it
names one group: `["ones"]`, or `["twos", "threes"]` in a triple-minor or
longways-set figure such as "2s and 3s circle left". The order is kept as
entered. How to store a figure whose source never says *who* dances is still
open (§9, Q1).

### 5.3 Never invent a stated side

If a source omits a hand, shoulder, side or direction, the stored value is
`unspecified`. When someone is *writing* a dance by hand, the editor may
*suggest* the usual choice (right, for `set` and `turn single`). An imported
dance whose source was silent must not appear to have said "right".

### 5.4 Ordered pairs are two figures, not a named combination

"Set and turn single", "cross and cast", "right-hand turn, then left", "star
right and back by the left", "circle left and right", and "balance and
swing" are all stored as **two adjacent figures in order**. There is no
special combined movement and no "sequence" container. Values are not copied
from the first figure to the second unless the source states them. "Back by
the left" does not imply the same number of places as the first star unless
the source says so.

Exception, still to be defined: **set and link** should be a single
first-class movement, because the combined figure is a named unit of its own
(see §7.4).

### 5.5 Timing is not a movement parameter

Bars, beats, phrase labels (A1, B2), progression results and citations
belong to the dance's transcription and provenance, not to movement
parameters. `fraction`, `changes`, `places` and `travel` describe *how far*,
not *how long*.

### 5.6 Two structural containers, no more

The existing app has two containers, shared across dance forms:

- **`meanwhile`**: two or more figures that genuinely happen **at the same
  time**, e.g. "1s lead down, **as** 2s lead up". Displayed joined by
  "while".
- **`modifier`**: one core action plus modifiers that describe it, rendered
  as "*X*, *Y*-ing".

Both hold 2–6 child figures, share one authoritative beat count, and may be
nested only one level (a `meanwhile` inside a `modifier` or the reverse).
Neither means "and then": ordinary sequence is just the order of figures in
the list. The container contracts are specified in
[domain-model.md](../design/domain-model.md).

### 5.7 Shorthand is expanded only when it is unambiguous

`repeat`, `same`, `v.v.`, `similar`, "back again" and similar shorthand are
written out in full in a transcription **only** when the source makes clear
what is repeated and by whom. Otherwise the source text is kept as written.
Actor-number shorthand (`1C`, `2W`) and one-off named figures (*Tiroir*,
*Lichfield hey*, *Four Winds*, ...) are set aside when *discovering
movements* for this pass. They are not deleted from any source.

## 6. Shared parameter vocabulary

### 6.1 Parameter names

| Name | Meaning | Example values |
| --- | --- | --- |
| `who` | The dancers performing the figure (a list, §5.2) | `["partners"]`, `["ones"]`, `["twos","threes"]` |
| `whom` | The counterpart: the dancers acted on, set to, or turned around | `neighbors`, `partners` |
| `who2` | A second, independently named group | |
| `pair` | The relationship a figure is danced with, when distinct from `who`/`whom` | |
| `where` | The spatial path | `up`, `down`, `across`, `along`, `diagonally`, `in`, `out`, `forward`, `back`, `left`, `right` |
| `direction` | A side or rotation specific to the movement | `left`/`right` (set), `clockwise`/`counterclockwise` (poussette) |
| `hand` | The hand used | `right`, `left`, `both`, `unspecified` |
| `shoulder` | The shoulder passed | `right`, `left`, `unspecified` |
| `travel` | The amount of turn, in full turns | `0.5`, `1`, `1.5` |
| `fraction` | A fractional extent of a figure | `quarter`, `half`, `three-quarter`, `whole` |
| `places` | Places moved around a ring or star | a positive whole number |
| `changes` | Changes in a hey or rights-and-lefts | a positive whole number |
| `endFacing` | Which way dancers face at the end | `up`, `down`, `in`, `out` |
| `singleFile` | Single-file variant (yes/no) | |
| `destination` | An endpoint the **source states** | `place`, `second place`, `original places`, `progressed place`, `partner's place`, `corner's place` |
| `step` | Prescribed footwork | `slipping`, `skipping`, `unspecified` |

We avoid generic catch-all names (`target`, `extent`, `spin`, `turn`) where
one of the names above already fits.

### 6.2 Selectors (values for `who` / `whom`)

`everyone`, `role1s`, `role2s`, `ones`, `twos`, `threes`, `fours`, `fives`,
`partners`, `neighbors`, `sameRoles`, `shadows`, `secondShadows`,
`prevNeighbors`, `nextNeighbors`, `thirdNeighbors`, `fourthNeighbors`,
`prevPartners`, `nextPartners`, `thirdPartners`, `fourthPartners`,
`fifthPartners`, `firstCorners`, `secondCorners`, `corners`, `longCorners`,
`firstDiagonals`, `secondDiagonals`, `diagonal`, `actives`, `couples`,
`sideCouples`, `centers`, `top`, `bottom`, `unspecified`.

For a single named dancer: `onesRole1`, `onesRole2`, `twosRole1`, `twosRole2`.

`firstCorners`/`secondCorners` are treated as **lasting relationships**
established at the start of the dance. `firstDiagonals`/`secondDiagonals`
describe **whoever is currently** on that diagonal, which changes as dancers
move. We know some communities use "corner" and "diagonal" interchangeably
(§9, Q2).

### 6.3 Display notation

The draft display formulas in §7 use this notation:

- `{who}` inserts the parameter's rendered value.
- `[ ... ]` is omitted when its contents are unspecified or absent.
- `{a | b}` means one of the alternatives, chosen by a stated rule.

Formulas marked "*as contra*" reuse the contra renderer; Appendix A shows
what those produce today.

## 7. The candidate figure registry

"Reviewed" below means the maintainer has proposed parameters and display
text. It does **not** mean the entry has enough ECD evidence to be adopted.
Entries marked ⚠ contain a point we specifically want reviewers to check.

### 7.1 Setting, honouring and small gestures

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 1 | `set` | `who`, `whom`, `where`, `direction` | `{who} set [{direction}] [{where}] [to {whom}]` | `direction` is left/right, rendered only when not right. `whom` is used when dancers set to someone other than each other. `where` is the line the dancers face along. ⚠ Is "set forward" a `where`, or a different figure? |
| 1a | `set_and_link` | *not yet defined* | *not yet defined* | Requested as a single movement (§5.4). Including "tandem set and link". Needs roles, route and display. See Q9. |
| 38 | `clap` | none | `clap` | |
| 39 | `honor` | `who`, `whom` | `{who} step and honor {whom}` | "Honour"/"Honor" is a display dialect, not two entries. |

### 7.2 Turns

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 4 | `turn_single` | `who`, `shoulder`, `destination` | `{who} turn single [{shoulder}] {to \| back to} {destination}` | Renders "back to" when `destination = place`, otherwise "to". ⚠ Must `destination` always be given, even when the source is silent? Only 2 of 10 turn singles in the second transcription batch state a destination. Sources give the side as "turn single left/right", never as a shoulder. |
| 5 | `hand_turn` | `who`, `hand`, `travel` | `{who} {hand}-hand turn {travel}` | Modelled on contra `allemande` in *parameters* only. "Allemande" is **not** an ECD alias. |
| 6 | `two_hand_turn` | `who`, `direction`, `travel` | *as contra, plus direction* | Contra `two_hand_turn` has no `direction`. ECD adds one ("two-hand turn anticlockwise"). ⚠ Needs a rendering and default. None of the 19 two-hand turns in the second batch states a rotation, but 11 state an extent and 2 an ending facing (§7.6). |
| 7 | `arm_turn` | `who`, `hand` | `{who} arm {hand}` | No `travel` yet: every arm turn we have documented goes once around, and none of the transcribed ones states an extent. ⚠ Examples of a half or 1½ arm turn would change this. |
| 8 | `shoulder_round` | `who`, `shoulder`, `travel` | *as contra* | Aliases: "gypsy", "gyre". *Siding* is a separate figure (#41). |
| 9 | `swing` | `who`, `endFacing` | *as contra* | Rare in ECD, included for coverage. "Balance and swing" is two figures. |
| 30 | `gate` | `who`, `whom`, `pair`, `direction`, `travel`, `endFacing` | *as contra* | |
| 33 | `orbit` | `who`, `whom`, `direction`, `travel` | `{who} orbit {direction} {travel} [around {whom}]` | |
| 40 | `mad_robin` | `who`, `whom`, `travel`, `direction` | *as contra* | Newly added candidate. |
| 42 | `turn_alone` | `who`, `custom` | *as contra*: `{who} turn alone` | Added 30 September 2026. Behaves and displays as contra `turn_alone`. A separate figure from `turn_single`, not an alias of it. `custom` is contra's free-text note. |
| 43 | `box_the_gnat` | `who`, `hand`, `balance` | *as contra*: `{who} box the gnat` | Added 30 September 2026. Behaves and displays as contra `box_the_gnat`, including its `balance` flag for a preceding balance. That flag is an exception to §5.4, like the wave `balance` flags. |
| 44 | `swat_the_flea` | *as `box_the_gnat`*, with `hand` fixed to `left` | *as contra*: `{who} swat the flea` | Added 30 September 2026. As in contra, it is a separately named entry that stores as `box_the_gnat` with the hand fixed, so the two names never merge. |

### 7.3 Rings, stars and balances

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 2 | `balance` | `who`, `where`, `hand` | *as contra* | |
| 3 | `balance_ring` | none | `balance the ring` | |
| 10 | `circle` | `who`, `direction`, `places`, `singleFile`, `step` | *as contra*; with `step`, the step word replaces "circle": "slip left 3 places"; with `who`, prefixed "{who}, ..." | `who` is offered only outside duple minor ("2s and 3s circle left"). ⚠ Transcribed circles give their extent as "half" (6 of 9), not a number of places, and single-file circles use clockwise/counter-clockwise, not left/right (§7.6). |
| 11 | `star` | `who`, `hand`, `places`, `grip` | *as contra*, with a "{who}, ..." prefix when `who` is set | ⚠ ECD's usual star is hands across, not contra's wrist grip. Should an unspecified grip display as hands across? One transcription gives the extent as "once around", not places. |
| 36 | `form_short_wave` | `axis`, `balance`, `center`, `centerHand`, `sides` | *as contra* | `balance` is a yes/no flag ("wave and balance"). |
| 37 | `form_long_wave` | `who`, `whom`, `whomHand`, `balance` | *as contra* | ⚠ Tidal-wave topology is unresolved (§10). |

### 7.4 Heys, chains and rights-and-lefts

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 12 | `circular_hey` | `who`, `whom`, `slow`, `changes`, `where`, `shoulder` | `[{who} dance] {changes} [slow] changes of a circular hey, {whom} pass {shoulder} {where}` | Alias: "square hey". Often used interchangeably with rights and lefts, but passing by shoulders rather than hands. All 5 transcribed circular heys state `changes` and whom to start with. One caption adds "(no hands)". |
| 13 | `hey` | **deferred** | | Number of dancers (3, 4, ...), straight/diagonal/end/parallel paths, and how the reel relates. See Q4. |
| 14 | `figure_eight` | `who`, `whom`, `where`, `fraction`, `lead`, `double` | *as contra `figure_8`*; renders "double figure eight" when `double` is set | `double` = both couples move. `whom` added because in non-duple dances "the other couple" can be ambiguous. |
| 15 | `dolphin_hey` | `who`, `whom`, `shoulder`, `where`, `fraction`, `endFacing` | `{fraction} dolphin hey {where}: {who} pass {whom} {shoulder} shoulder to start, end facing {endFacing}` | |
| 16 | `rights_and_lefts` | `who`, `whom`, `slow`, `changes`, `where`, `hand` | `[{who} dance] {changes} [slow] changes of rights and lefts, {whom} pull by {hand} {where} to start` | ECD rights and lefts is **not** contra's "right and left through". It is closer to a contra square through without a balance. |
| 17 | `chain` | `who`, `hand`, `where`, `open` | `{who} {hand}-hand [open] chain [{where}]` | Always shows the hand. `open` is a yes/no flag. |
| 18 | `grand_chain` | **deferred** | | Its relationship to `chain` and `rights_and_lefts` is unresolved. See Q5. The two transcribed grand chains (*Helena*; *The American Husband* in the first batch) are both counted in changes ("three changes of a grand chain"), like rights and lefts. |

### 7.5 Crossing, passing and travelling

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 19 | `cross` | `who`, `shoulder`, `where` | `{who} cross [diagonally] passing {shoulder} shoulder [{where}]` | Roughly the union of contra *pass through* and *pass by*. |
| 20 | `change_places` | **deferred** | | Is it distinct from `cross`? See Q6. "Change" appears as a standalone figure in three transcribed dances: *Midwinter Maggot*, *Hambleton's Round O*, and *Alexander's Birth Day* from the first batch. |
| 21 | `right_left_through` | `who`, `whom`, `where`, `withHands` | `[{who} dance a] right and left through [{where}], {with \| without} hands, {others} courtesy turning {whom}` | ⚠ In a three-couple selection, "the others" is not always a single pair. |
| 22 | `lead` | **deferred** | | Actor, route (between, outside, away) and destination. See Q7. Now well attested: see §7.6. |
| 23 | `cast` | **deferred** | | Direction and destination; how it differs from lead, cross and fall back. See Q7. Now well attested: see §7.6. |
| 24 | `fall_back` | `who`, `where` | `[{who}] fall back [{where}]` | `where` defaults to `across` and is then not shown. `who` defaults to everyone. ⚠ All 4 transcribed fall-backs say "with neighbor", which suggests a `whom`. |
| 25 | `back_to_back` | `who`, `shoulder`, `travel`, `where` | `{who} {shoulder}-shoulder back-to-back [{where}] {travel}` | Like contra dosido, but always named by shoulder, plus `where` (across/along). |
| 41 | `siding` | `who`, `shoulder`, `travel`, `where`, `style` | `{who} {shoulder}-shoulder [{style}] siding [{where}] {travel}` (draft) | Added 30 September 2026. Same parameters as `back_to_back`, plus `style`: `straight` or `swirly`. An unstated style stays `unspecified` (§5.3). Captioned "Right shoulder siding", "Left Siding". |
| 26 | `pass_through` | `who`, `where`, `shoulder` | `[{who}] pass through {shoulder} shoulders {where}` | |
| 27 | `promenade` | `who`, `where`, `direction`, `fraction`, `places`, `singleFile` | `{who} [single file] promenade {fraction \| N places} {direction} {where}` | `fraction` when in couples, `places` when single file. |
| 28 | `poussette` | `who`, `whom`, `fraction`, `direction` | *as contra* | ⚠ Contra defaults to half, clockwise. We have one ECD source that states *both* extent and rotation (*The Parson's Cap*: half, counter-clockwise). Both transcribed poussettes are half with a named pushing role, and neither states a rotation. See Q8. |
| 29 | `galop` | **deferred** | | A movement, or a travelling style that modifies other movements? |
| 31 | `arch` | `who` | `{who} arch` | "Arch and dive through" is not yet defined. |
| 32 | `rollaway` | `who`, `whom`, `where`, `halfSashay` | `{who} roll away {whom} {where} [with a half sashay]` | Contra's ID is `roll_away`. `halfSashay` is a yes/no *style*, not "half a rollaway". |
| 34 | `line` | **deferred** | | A formation, an action ("lines forward and back"), or both? See *up a double* in §7.6. |
| 35 | `bend_line` | **deferred** | | A formation change or a movement? One transcription has "up a double and back, *bending the line*", which reads as a `modifier` (§5.6). |

### 7.6 What the expanded transcription set shows

The second transcription batch (§3) doesn't overturn any decision in §5.
It does do three things:

- It exposes figures that are missing from the registry.
- It gives enough examples of **lead** and **cast** to start defining them.
- It shows a few places where the draft parameters don't match how
  captions actually express extent.

Counts below are for the second batch only (12 dances, 100 captions) unless
stated. Each count is of captions, not of performances.

**Figures that appear in the transcriptions but not in §7:**

| Figure as captioned | Where | Observation |
| --- | --- | --- |
| "Up a double, and back", "Down a double, and back", "All up a double, and back", "Lines of three forward and back", "Line of four up a double and back"; also "Forward" on its own | *Helena*, *Midwinter Maggot*, *Double Jubilee*, *Honeysuckle Cottage* | The most common figure missing from §7. Has a direction (`up`, `down`, `forward`), an optional return ("and back"), and sometimes a formation ("lines of three"). "A double" is also used as an extent for *fall back*. Contra's nearest move is `long_lines` (forward, optionally back). It overlaps the deferred `line` entry. See Q12. |
| "Right shoulder siding", "Left shoulder siding"; "Left Siding" | *Double Jubilee* (later passes of the video); *Alexander's Birth Day* (first batch) | Siding is captioned with a stated shoulder. **Now added** as `siding` (#41). |
| "Box the gnat" | *Honeysuckle Cottage* | Appears as an ECD figure in its own right, not only as an alias. **Now added**, as contra, with `swat_the_flea` (#43, #44). |
| "turn alone" | *Double Jubilee* ("Lead partner down, turn alone, lead back") | **Now added** as `turn_alone` (#42), as contra. It is not an alias of `turn_single`. |
| "Serpentine" | *Beach Spring* | A named figure, described in the caption as a sequence of crosses ("followed by other members of their circle"). Treated as a one-off (§10). |

**Lead and cast (Q7).**
There are 15 captions involving cast or lead across 10 of the 12 dances.
They consistently state:

- **who** ("1s", "top couple", "middle two couples", single dancers "M1",
  "W2");
- **where** ("down", "up", "to middle", "back");
- a **destination** ("to progressed place", "home", "to 2nd place", "to the
  ends of a line of four");
- sometimes a **route** ("through 2s", "around neighbor") or a side ("cast
  left", "cast right").

The most frequent pattern is one couple casting while another leads the
opposite way. It occurs 8 times in 6 dances. The concurrency is written
explicitly with "as" in four captions ("1s cast down as 2s lead up"). In the
other four it is written only with a comma ("2s cast down, 1s lead up").
Under §5.6, "as" is recorded with a `meanwhile` container. A comma is
recorded as two figures in order, because the source doesn't state that they
happen together, even though dancers would read it that way. Reviewers may
want to weigh in on that choice.

**Extents that don't fit the draft parameters.**

| Movement | Observation |
| --- | --- |
| `circle` | 6 of 9 circles give their extent as "half" or "half way", not a number of places. Converting "half" to places depends on how many dancers are in the ring. None of the 9 states left or right. Single-file circles are called clockwise/counter-clockwise (*Midwinter Maggot*). This suggests `circle` needs a `fraction`, or a defined conversion from it. |
| `star` | "Right hands across star once around" (*Honeysuckle Cottage*) gives a turn amount, not places. |
| `two_hand_turn` | Of 19 two-hand turns, 8 are half, 3 are once and a half, and 8 give no extent. This strongly supports `travel`. Two give an ending facing ("and face down", "open to face new neighbors"). That suggests `endFacing`, which the draft entry lacks. No rotation direction is ever stated. |
| `turn_single` | 5 of 10 state a side, always as "left" or "right". This bears on whether the parameter should be called `shoulder` or `direction`. |
| `set` | "set right and honor, set left and honor to W2" (*The Shrewsbury Lasses*) is the only stated set direction, and it names a single dancer as `whom`. |

**Other patterns.**

- **Selectors** not in §6.2 appear repeatedly: "at the ends", "middles",
  "top couple", "couple below", "others", "opposite-sex neighbor", "new
  partner". Single-dancer actors (M1, W2) appear in three-couple dances as
  well as duple ones. See Q14.
- **Ending states** are often stated for figures that have no
  `destination` parameter:
  - "change with partner (all home)";
  - "orbit outside ... ending improper";
  - "(all progressed and proper)".

  This bears on Q3.
- **Resolvable shorthand** matches §5.7: "That again", "M2 & W1 the same",
  "others counter", "continue in the same direction". In each case the
  antecedent is the immediately preceding figure.
- **Chains and heys:**
  - Rights and lefts (4), circular heys (5) and a grand chain (1) are all
    counted in *changes*, with the starting partner or neighbor named.
  - A hand is never stated for rights and lefts.
  - One circular hey is captioned "(no hands)" (*Hambleton's Round O*), and
    a webpage for another adds the same note (*King of Poland*). This hints
    that hands, not path, are what separate the circular hey from rights
    and lefts.
- **Heys for three:** "1s left shoulder heys with end couples" (*Hambleton's
  Round O*) states a shoulder and runs two heys at once. That is new
  evidence for Q4.

## 8. Worked examples

These encodings illustrate the rules. They were written for this proposal
and have not been reviewed as transcriptions. Please correct them freely.

### 8.1 *The Farmer's Joy* (Joseph Pimentel, 2012), A1 and B2

Taken from the teaching in a video, one performance:

```text
A1  (1-4) 1st corners set forward and turn single back to place
    (5-8) 1st corners two hand turn
B2  (1-4) Right hands across...
    (5-8) ...and back by the left
```

Proposed storage:

```text
set           who=["firstCorners"]  where=forward       direction=unspecified
turn_single   who=["firstCorners"]  shoulder=unspecified destination=place
two_hand_turn who=["firstCorners"]  direction=unspecified travel=unspecified
star          hand=right  grip=handsAcross  places=unspecified
star          hand=left   grip=unspecified  places=unspecified
```

Points to notice:

- "Set forward and turn single" is **two figures** (§5.4).
- The source gives no side for the set, shoulder for the turn single, or
  amount for the two-hand turn, so all are `unspecified`.
- "Right hands across" states the grip. "Back by the left" does not, so the
  second star's grip and number of places are **not** copied from the first.
- B1 of this dance ("1s lead down, wheel around, cross up and cast down,
  **as** 2s lead up") cannot be encoded yet, because `lead` and `cast` are
  deferred. The word "as" suggests a `meanwhile` container. The same
  cast-while-leading pattern recurs in six of the transcribed dances
  (§7.6).

### 8.2 *The American Husband*, A2 (three couples)

```text
(1-4) 1s+2s face neighbors (diagonally) two changes of rights and lefts
(5-8) 2s+3s face neighbors (up and down) two changes of rights and lefts
```

```text
rights_and_lefts  who=["ones","twos"]   whom=neighbors  changes=2  where=diagonally  hand=unspecified
rights_and_lefts  who=["twos","threes"] whom=neighbors  changes=2  where=along       hand=unspecified
```

This shows why `who` must be a list. The same video names a grand chain,
a ladies' chain *and* rights and lefts in one dance. That tells us the terms
are distinct in this dance. It does not settle how they relate everywhere
(Q5).

### 8.3 *Alexander's Birth Day* (Gary Roodman, 2003), poussette

```text
With neighbor, half poussette, women push
```

```text
poussette  who=["role2s"]  whom=neighbors  fraction=half  direction=unspecified
```

"Women push" becomes `who = role2s` in role-neutral storage and displays as
"women", "robins", or a positional term according to the caller's chosen
dialect. The rotation is not stated, so it is `unspecified`.

### 8.4 *Midwinter Maggot* (Gary Roodman, 2012), B bars 1–8

```text
(1-2) Single file circle clockwise half
(3-4) Turn single left
(5-6) Single file circle counter-clockwise half (all home)
(7-8) Turn single right
```

```text
circle       singleFile=true  direction=clockwise         places=?
turn_single  shoulder=left    destination=unspecified
circle       singleFile=true  direction=counterclockwise  places=?   destination=home ⚠
turn_single  shoulder=right   destination=unspecified
```

Points to notice:

- **Extent.** The source says "half", but `circle` measures its extent in
  `places`. In a ring of four, half is two places. Writing `places=2`
  converts what the caller said into something they did not say, and the
  conversion depends on the ring size. This is the gap noted in §7.6.
- **Direction.** Single-file circles are called clockwise and
  counter-clockwise, but contra `circle` uses left and right.
- **Ending state.** "(all home)" is an ending state, but `circle` has no
  `destination` parameter (Q3).
- **Parameter name.** "Turn single left" is stored as `shoulder=left`. The
  source says "left", not "left shoulder", so the name of this parameter is
  itself a question.

## 9. Open questions for reviewers

These are ordered roughly by how much they block the design. Questions
Q1–Q3 are about data structure. Q4 onwards need ECD knowledge more than
software knowledge.

**Q1. Who dances, when the source doesn't say?**
When a line says only "circle left" or "set and turn single", should `who`
be stored as empty, as `["unspecified"]`, or as `["everyone"]`? Are
combinations such as `["everyone", "ones"]` ever meaningful, or always a
mistake?

**Q2. Positional versus role calling.**
Many ECD communities call positionally ("the dancer on the left", "wall
side", "first file") and some prefer that role terms never appear. We do not
want to impose a mapping from `role1`/`role2` to positions. How do ECDDB and
the callers you know handle this? Which terms, if any, describe a
relationship that stays fixed as dancers move (as "corner" usually does)? Do
"corner" and "diagonal" mean different things in your usage?

**Q3. Stated destinations.**
Should any moving figure be able to carry `destination` ("..., to
progressed place"), or only figures such as `turn single` where it is part
of the usual wording? We want to separate "the source says where you end up"
from "the software worked out where you end up". The transcriptions state
endpoints and ending states for many kinds of figure: casts ("to progressed
place"), changes ("all home"), orbits ("ending improper") and circles ("all
home"). Most turn singles, by contrast, don't state one.

**Q4. Heys and reels.**
How should heys for three and for four, straight/diagonal/end/parallel heys,
reels, Shetland/tandem reels and mirror (Grimstock) heys be organized? Is
the number of dancers a parameter of one `hey` movement? How should we
record where a hey starts, who meets whom first, and how far it goes?

**Q5. Grand chain, chain and rights and lefts.**
Are grand chain and rights and lefts the same figure under different names,
related figures, or distinct? Does it depend on period or region?

**Q6. Cross versus change places.**
Is "change places" (with or without hands) a separate figure from "cross
over", or the same figure with a `hand` parameter? The transcriptions use
both "cross" ("Women cross", "Partners cross") and "change" ("Change with
partner", "W1+M2 change"), but never both in the same dance.

**Q7. Lead and cast.**
What parameters do "lead up/down/out", "lead through", "cast off/up/down",
"cast around" and "long corners cast" need? What separates cast from lead,
cross and fall back? §7.6 summarizes 15 transcribed captions. A starting
point would be `who`, `where`, `destination`, and a route ("through
{whom}", "around {whom}"). When one couple casts while another leads and
the source joins them with only a comma, should we record them as
happening together?

**Q8. Poussette.**
In ECD practice, what extent and rotation should a bare "poussette" imply?
Should an unstated extent stay unspecified, as §5.3 suggests? We have very
few sources that state both extent and rotation. Both transcribed poussettes
say "half" and name who pushes ("women push", "men push first"), and neither
states a rotation. Does "push first" imply the pushing role changes halfway
through?

**Q9. Set and link.**
What is the canonical definition of set and link, and its tandem variant?
Who sets, who links, and where does each dancer end? Please point to
English-style sources that describe it precisely.

**Q10. Movements still undecided.**
- `galop`: is it a movement or a travelling style?
- `line` and `bend_line`: are they formations or actions?
- Tidal wave versus long and short waves.
- Single-file promenade versus single-file circle within a minor set.
- Chevron/Pothooks and mirror heys need their own definitions.

**Q11. Aliases that should not merge.**
Box the Gnat and Swat the Flea are now separate entries, as in contra
(#43, #44). Which other pairs look alike but must stay distinct?
Which of these are the same: Jersey/Nevada twirl, Gay Gordons/Varsouvienne
hold, box circulate, "matchboxes", and chassé/slide/sashay/slice? What does
Heywood's "Back to back for four" mean?

**Q12. What's missing?**
Which common ECD figures are absent from §7? Which entries are really two
figures, or should merge with another? The transcriptions already point to
**up a double / forward and back** (with or without "and back", in lines
or as all). Siding, turn alone, box the gnat and swat the flea have since
been added. How should "up a double and back" relate to the deferred
`line` entry and to `fall_back`?

**Q13. Specific value questions.**
- Does ECD have arm turns other than once around?
- Siding's `style` values are `straight` and `swirly`. Are those the
  words callers would recognize? Is there any other style of siding?
- Should `circle` (and perhaps `star`) accept a `fraction` or turn amount
  ("circle half", "star once around"), as well as or instead of `places`?
- Should the turn single's side be called `shoulder` or `direction`,
  given that sources say "turn single left/right"?
- Should `two_hand_turn` and `cross` take `endFacing` ("two hand turn once
  and a half and face down", "cross with partner and face right")?
- Should the usual ECD star grip be the default *display*, even when the
  source doesn't state it?
- How should `two_hand_turn.direction` be worded ("clockwise", "to the
  left", ...)?

**Q14. Selectors.**
The transcriptions use actor phrases that §6.2 cannot express:

- "at the ends", "middles", "middle two couples", "top couple", "couple
  below";
- "others", "all";
- "opposite-sex neighbor", "new partner", "this neighbor".

Which of these deserve selector tokens, and which are relative to the
previous figure and should stay as source text?

## 10. Out of scope for this pass

- **Implementation.** No code, database fields or file formats have been
  built. Spellings such as `threeQuarter` versus `three_quarter`, or
  `full` versus `whole`, are not yet fixed.
- **Specialized chain families.** Dixie, teacup, spin chain.
- **Specialized hey and reel families.** Interlocking, Morris-derived.
- **Wave topology.** Tidal wave and the ocean-wave/across-the-set
  distinction.
- **Footwork and gesture labels.** Jump/stamp, rigadoon, rant.
- **One-off named figures.** Tiroir, Yearn, Weathervane, Celtic knot,
  Lichfield hey, Four Winds. These stay as source text for now.
- **Mapping to positional calling** (Q2): we want community input first.

## 11. How to respond

Any form of feedback helps, and partial answers are very welcome:

- Answer any of the questions in §9 by number.
- Mark up a registry row: "keep", "rename to ...", "merge with ...",
  "split into ...", "needs parameter ...".
- Send counter-examples: dances whose instructions can't be expressed with
  these parameters, ideally with a link to an **English-style** source
  (ECDDB record, published book, or a video with clear teaching).
- Correct the worked examples in §8.

Where you know of style or homonym problems (the same title used by an
English dance and a contra or other dance), please mention them. That is the
error we are most likely to make without help.

---

## Appendix A: how the contra grammar renders shared figures

Several ECD entries above say "*as contra*". These are the current contra
display patterns in Caller's Compendium, for reference, taken from
[`contra_taxonomy.dart`](../../packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart).
Parameters in square
brackets are shown only when set. ECD would diverge where its notes say so.

| Contra move | Contra parameters (default) | Contra display pattern |
| --- | --- | --- |
| `balance` | `who` (neighbors), `hand` (unspecified) | `{who} balance` |
| `balance_the_ring` | none | `balance the ring` |
| `allemande` (model for ECD `hand_turn`) | `who` (neighbors), `hand` (right), `travel` (1) | `{who} allemande {hand} {travel}` |
| `two_hand_turn` | `who` (partners), `travel` (1) | `{who} two hand turn {travel}` |
| `shoulder_round` | `who` (neighbors), `shoulder` (right), `travel` (1) | `{who} shoulder round {travel}` |
| `swing` | `who` (partners), `endFacing` (in) | `{who} swing` |
| `turn_alone` | `who` (everyone), `custom` (free text) | `{who} turn alone` |
| `box_the_gnat` | `who` (partners), `hand` (right), `balance` (no) | `{who} box the gnat` |
| `swat_the_flea` | stored as `box_the_gnat` with `hand` fixed to left | `{who} swat the flea` |
| `circle` | `direction` (left), `places` (4), `singleFile` (no) | `circle {direction} {places}` |
| `star` | `hand` (right), `places` (4), `grip` (none) | `star {hand} {places}` plus a "hands across" / "wrist grip" clause when grip is set |
| `figure_8` | `who` (ones), `where` (none / above / below / across), `lead` (a single dancer, ones' role2), `fraction` (half) | `{who} {fraction} figure 8` |
| `poussette` | `who` (ones), `whom` (neighbors), `fraction` (half), `direction` (clockwise) | `{who} poussette {whom} {fraction} {direction}` |
| `gate` | `who`, `pair`, `whom`, `direction`, `travel`, `endFacing` (all unspecified) | `{who} {pair} gate {whom} {direction} {travel} {endFacing}` |
| `roll_away` | `who` (neighbors), `whom` (partners), `halfSashay` (no) | `{who} roll away {whom}` |
| `mad_robin` | `who` (role2s), `travel` (1), `direction`, `whom` | `{who} mad robin {travel} {direction} {whom}` |
| `form_short_waves` | `axis` (across), `balance` (no), `center` (role2s), `centerHand` (left), `sides` (neighbors) | `form short waves` |
| `form_long_waves` | `who` (role1s), `whom`, `whomHand` (both unspecified), `balance` (no) | `{who} form long waves` |

Contra concrete defaults, such as poussette's "half, clockwise", are
**not** automatically ECD defaults. §5.3 applies: an ECD source that doesn't
state a value is stored as `unspecified`.

## Appendix B: sources

- Antony Heywood, figure catalogue and dance cards:
  <https://barndances.org.uk/Antony/>
- UpaDouble figure definitions and dance records:
  <https://www.upadouble.info/>
- Transcribed dances and their Heywood IDs: see the table in §3.
- Dance records cited for style checks (Heywood IDs):
  California Twirlin' [12344](https://barndances.org.uk/Antony/dancecard.php?ID=12344) (contra);
  Marshmallows in Flight [24257](https://barndances.org.uk/Antony/dancecard.php?ID=24257) (contra);
  The Happy Pilgrim [22537](https://barndances.org.uk/Antony/dancecard.php?ID=22537) (English);
  How Great is the Pleasure [17744](https://barndances.org.uk/Antony/dancecard.php?ID=17744) (English);
  The Parson's Cap [2736](https://barndances.org.uk/Antony/dancecard.php?ID=2736) (English);
  Lichfield's Ruby Surprise [14581](https://barndances.org.uk/Antony/dancecard.php?ID=14581) (English);
  Along the Dee [21981](https://barndances.org.uk/Antony/dancecard.php?ID=21981) (English);
  Alexander's Birth Day [5286](https://barndances.org.uk/Antony/dancecard.php?ID=5286) (English);
  The American Husband [184](https://barndances.org.uk/Antony/dancecard.php?ID=184) (English);
  Chrysalis [5943](https://barndances.org.uk/Antony/dancecard.php?ID=5943) (English) /
  [7513](https://barndances.org.uk/Antony/dancecard.php?ID=7513) (contra).
