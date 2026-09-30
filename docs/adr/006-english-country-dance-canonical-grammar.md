# ADR-006: English Country Dance canonical figure grammar

- **Status**: Proposed (30 September 2026). Circulated for review by ECDDB
  contributors and other ECD callers, dancers and archivists before anything
  is implemented.
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
3. [Research basis](#3-research-basis)
4. [Terms used in this proposal](#4-terms-used-in-this-proposal)
5. [Design principles](#5-design-principles)
6. [Shared parameter vocabulary](#6-shared-parameter-vocabulary)
7. [The figure registry](#7-the-figure-registry)
8. [Worked examples](#8-worked-examples)
9. [Open questions for reviewers](#9-open-questions-for-reviewers)
10. [Out of scope](#10-out-of-scope)
11. [How to respond](#11-how-to-respond)
12. [Appendix A: how the contra grammar renders shared figures](#appendix-a-how-the-contra-grammar-renders-shared-figures)
13. [Appendix B: sources](#appendix-b-sources)

---

## 1. Summary

Caller's Compendium is an app for callers to store, search, edit and print
dances. For contra dance it already stores each figure as structured data
("who does what, with which hand, how far") rather than free text. We would
like to do the same for English Country Dance, and we want the vocabulary to
be right before any of it is built.

This document proposes a small set of named movements, each described by a
fixed list of named parameters. For example, a right-hand turn once around
by partners is stored as the movement `hand_turn` with `who = partners`,
`hand = right`, `travel = 1`. It is not stored as a separate "right-hand turn
partners" entry. The goals are:

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

The registry (§7) has **46 movements**:

- **36 are defined**, each with parameters and a draft display. Some still
  have specific review points.
- **10 are open**, because we lack the evidence or the community knowledge
  to define them well: `hey`, `grand_chain`, `change_places`, `lead`,
  `cast`, `galop`, `line`, `bend_line`, `set_and_link`, and *up a double /
  forward and back*.

The open movements and the questions in §9 are where ECDDB contributors can
help most.

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
movement definitions**. An ECD `poussette` is not assumed to mean exactly
what a contra `poussette` means just because the words match. Where an ECD
movement is deliberately identical to its contra counterpart, §7 says so,
and Appendix A shows how the contra version displays.

## 3. Research basis

Four kinds of source inform the grammar. Each has limits, and those limits
determine how much confidence each registry entry deserves.

**Antony Heywood's figure catalogue** at
[barndances.org.uk](https://barndances.org.uk/Antony/). Filtered to
English-style dances, it has **527 active figure labels**. **456** of those
appear in at least one English-style dance card and 71 do not. The catalogue
is an excellent inventory of *vocabulary*: which figure names exist and how
they are spelled. Its dance cards summarize which figures a dance contains.
They are not full transcriptions. They do not reliably give phrase or bar
order, repeats, who dances, or what happens at the same time.

**UpaDouble** ([upadouble.info](https://www.upadouble.info/)) figure
definitions and dance records. We matched **23,944** Heywood dance cards
against **3,680** UpaDouble records by title: 1,781 exact matches, 273 after
normalizing spelling, and 16 ambiguous. A title match shows that two records
refer to the same *title*. It does not show that the choreography or style is
the same. Some titles are shared by an English dance and a contra dance (for
example *Chrysalis*: Heywood
[5943](https://barndances.org.uk/Antony/dancecard.php?ID=5943) is English,
[7513](https://barndances.org.uk/Antony/dancecard.php?ID=7513) is contra).

**Video captions and spoken teaching.** A caption counts as evidence only
when it clearly paraphrases a specific occurrence and states at least two
facts about the figure (for example actor and hand, or extent and
direction). Keyword hits, garbled speech recognition and catalogue
co-listing don't count.

**Full transcriptions of teaching videos.** These are the strongest
evidence, because each records the exact on-screen caption for every figure,
in order, with its phrase label. The set has 16 dances. Fifteen are complete
and together give **131 figure captions**. *The Happy Pilgrim* is partial,
has no usable captions, and is excluded from the counts in §7.

| Dance | Heywood ID | Formation (as transcribed) |
| --- | ---: | --- |
| Alexander's Birth Day | [5286](https://barndances.org.uk/Antony/dancecard.php?ID=5286) | Facing couples |
| The American Husband | [184](https://barndances.org.uk/Antony/dancecard.php?ID=184) | Sicilian circle / triple minor |
| Barbarini's Tambourine | [198](https://barndances.org.uk/Antony/dancecard.php?ID=198) | Proper duple minor |
| Beach Spring | [5613](https://barndances.org.uk/Antony/dancecard.php?ID=5613) | 4-couple longways |
| Christina | [4525](https://barndances.org.uk/Antony/dancecard.php?ID=4525) | Improper duple minor |
| Double Jubilee | [14575](https://barndances.org.uk/Antony/dancecard.php?ID=14575) | 3-couple longways, mixer |
| The Eliza | [1044](https://barndances.org.uk/Antony/dancecard.php?ID=1044) | Proper duple minor |
| The Farmer's Joy | [14769](https://barndances.org.uk/Antony/dancecard.php?ID=14769) | Proper duple minor |
| Hambleton's Round O | [1461](https://barndances.org.uk/Antony/dancecard.php?ID=1461) | Proper triple minor |
| The Happy Pilgrim | [22537](https://barndances.org.uk/Antony/dancecard.php?ID=22537) | 4-couple Becket (partial transcription) |
| Helena | [1540](https://barndances.org.uk/Antony/dancecard.php?ID=1540) | 4-couple longways |
| Honeysuckle Cottage | [5299](https://barndances.org.uk/Antony/dancecard.php?ID=5299) | Improper duple minor |
| King of Poland | [1910](https://barndances.org.uk/Antony/dancecard.php?ID=1910) | Improper duple minor |
| Midwinter Maggot | [5895](https://barndances.org.uk/Antony/dancecard.php?ID=5895) | Proper duple minor |
| News from Tripoly | [2548](https://barndances.org.uk/Antony/dancecard.php?ID=2548) | Proper duple minor (originally triple) |
| The Shrewsbury Lasses | [3275](https://barndances.org.uk/Antony/dancecard.php?ID=3275) | 3-couple longways (originally triple) |

The dances range from a 1698 Playford publication to 2015. They cover duple,
triple, three-couple, four-couple and circle formations.

Limits of this evidence:

- **One interpretation per dance.** Each transcription describes one
  performance of one interpretation. None of them is proof of a universal
  rule.
- **One source.** Every video comes from UpaDouble, so the wording reflects
  that site's captioning style. Four of the fifteen complete dances are by
  one deviser, Gary Roodman.
- **Uneven timing.** Bar ranges come from video timing and are approximate.
  This proposal does not depend on them (§5.5).
- **Known gaps in three transcripts:**
  - *Double Jubilee*'s phrase labels were inferred, not shown on screen.
  - *Christina*'s bar ranges are unresolved.
  - Two of *The Shrewsbury Lasses*' captions are in uncertain order.

**Style filtering.** Every dance counted as evidence is confirmed as
`Style: English` on its Heywood card, not just matched by title or figure
name. The check matters. Of four videos that once looked like support for
"rollaway", two (*California Twirlin'*, *Marshmallows in Flight*) are
Heywood-classified **contra** dances. Only *The Happy Pilgrim* and *How
Great is the Pleasure* are English. Reviewers who know of mis-styled or
homonymous records are especially welcome to say so.

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
| **Defined** / **Open** | A defined movement has parameters and a draft display. An open movement doesn't yet, and is listed in §7.6. |

## 5. Design principles

These principles are settled by the Caller's Compendium maintainer.
Reviewers are still welcome to challenge them.

### 5.1 ECD owns its movement IDs, but shares parameter names

Where ECD and contra describe the same *concept*, they use the same
parameter name. The allowed values and defaults may still differ. A
movement's ID, meaning and display belong to ECD. Where a source-specific
count has no contra equivalent (such as `changes` in rights and lefts), ECD
defines its own parameter.

### 5.2 `who` is a list

In ECD, `who` is always stored as a **list** of selector tokens, even when it
names one group: `["ones"]`, or `["twos", "threes"]` in a triple-minor or
longways-set figure such as "2s and 3s circle left". The transcriptions use
such combinations often: "1s+2s", "2s+3s", "1s+3s", "middle two couples".
The order is kept as entered. How to store a figure whose source never says
*who* dances is an open question (Q1).

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

There are two kinds of exception:

- **`set_and_link`** is one movement, because the combined figure is a
  named unit of its own. Its definition is open (§7.6).
- **A preceding balance** is recorded as a `balance` flag on
  `box_the_gnat` and on the two wave formations, matching the contra
  taxonomy.

### 5.5 Timing is not a movement parameter

Bars, beats, phrase labels (A1, B2), progression results and citations
belong to the dance's transcription and provenance, not to movement
parameters. `fraction`, `changes`, `places` and `travel` describe *how far*,
not *how long*.

### 5.6 Two structural containers, no more

The app has two containers, shared across dance forms:

- **`meanwhile`**: two or more figures that genuinely happen **at the same
  time**, e.g. "1s cast down **as** 2s lead up". Displayed joined by
  "while".
- **`modifier`**: one core action plus modifiers that describe it, rendered
  as "*X*, *Y*-ing", e.g. "up a double and back, *bending the line*".

Both hold 2–6 child figures, share one authoritative beat count, and may be
nested only one level (a `meanwhile` inside a `modifier` or the reverse).
Neither means "and then": ordinary sequence is just the order of figures in
the list. The container contracts are specified in
[domain-model.md](../design/domain-model.md).

A `meanwhile` is used only when the source states concurrency, for example
with "as" or "while". Two actions joined by a comma ("2s cast down, 1s lead
up") are recorded as two figures in order, even where dancers would read
them as simultaneous (Q7).

### 5.7 Shorthand is expanded only when it is unambiguous

`repeat`, `same`, `v.v.`, `similar`, "back again" and similar shorthand are
written out in full in a transcription **only** when the source makes clear
what is repeated and by whom. Otherwise the source text is kept as written.
In the transcriptions, the shorthand that does occur is resolvable: "That
again", "M2 & W1 the same", "others counter" and "continue in the same
direction" each refer to the immediately preceding figure.

Actor-number shorthand (`1C`, `2W`) and one-off named figures (*Tiroir*,
*Lichfield hey*, *Four Winds*, ...) are set aside when *discovering
movements*. They are not deleted from any source.

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
| `changes` | Changes in a hey, chain or rights-and-lefts | a positive whole number |
| `endFacing` | Which way dancers face at the end | `up`, `down`, `in`, `out` |
| `singleFile` | Single-file variant (yes/no) | |
| `destination` | An endpoint the **source states** | `place`, `second place`, `original places`, `progressed place`, `partner's place`, `corner's place` |
| `step` | Prescribed footwork | `slipping`, `skipping`, `unspecified` |
| `style` | A named manner of performing a movement (siding only) | `straight`, `swirly`, `unspecified` |

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
(Q2).

The transcriptions also use actor phrases this list cannot express yet:

- positions in the set: "at the ends", "middles", "top couple", "couple
  below";
- relative references: "others";
- descriptive references: "opposite-sex neighbor", "new partner".

Single dancers are named in three-couple dances as well as duple ones
("M1", "W2"). See Q14.

### 6.3 Display notation

The draft display formulas in §7 use this notation:

- `{who}` inserts the parameter's rendered value.
- `[ ... ]` is omitted when its contents are unspecified or absent.
- `{a | b}` means one of the alternatives, chosen by a stated rule.

Formulas marked "*as contra*" reuse the contra renderer; Appendix A shows
what those produce.

## 7. The figure registry

Each defined movement below has parameters and a draft display. "Defined"
means the design is specific enough to review. It does **not** mean the
entry has been accepted. Entries marked ⚠ contain a point we specifically
want reviewers to check.

"Evidence" figures in the notes count captions in the 15 complete
transcriptions (§3). Each count is of captions, not of performances.

### 7.1 Setting, honouring and small gestures

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `set` | `who`, `whom`, `where`, `direction` | `{who} set [{direction}] [{where}] [to {whom}]` | `direction` is left/right, rendered only when not right. `whom` is used when dancers set to someone other than each other ("set to partner"). `where` is the line the dancers face along. Evidence: 13 captions in 7 dances. Only *The Shrewsbury Lasses* states a direction ("set right and honor, set left and honor to W2"), and it names a single dancer as `whom`. ⚠ Is "set forward" a `where`, or a different figure? |
| `honor` | `who`, `whom` | `{who} step and honor {whom}` | "Honour"/"Honor" is a display dialect, not two entries. |
| `clap` | none | `clap` | |

### 7.2 Turns

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `turn_single` | `who`, `shoulder`, `destination` | `{who} turn single [{shoulder}] {to \| back to} {destination}` | Renders "back to" when `destination = place`, otherwise "to". Evidence: 13 captions in 7 dances. 5 state a side, always as "turn single left/right", never as a shoulder. 2 state a destination. ⚠ Should `destination` be required even when the source is silent? Is `shoulder` the right name for the side? |
| `turn_alone` | `who`, `custom` | *as contra*: `{who} turn alone` | Identical to contra `turn_alone`. A separate movement from `turn_single`, not an alias of it. `custom` is contra's free-text note. |
| `hand_turn` | `who`, `hand`, `travel` | `{who} {hand}-hand turn {travel}` | Parameters modelled on contra `allemande`; "allemande" is **not** an ECD alias. Evidence: 6 captions in 3 dances, 2 with an extent ("right turn half"). |
| `two_hand_turn` | `who`, `direction`, `travel` | *as contra, plus direction* | Contra `two_hand_turn` has no `direction`; ECD adds one for sources such as Heywood's "two-hand turn anticlockwise". Evidence: 21 captions in 12 dances. 12 state an extent (9 half, 3 once and a half), 2 an ending facing ("and face down", "open to face new neighbors"), and none a rotation. ⚠ Needs a rendering and default for `direction`. Should it also take `endFacing`? |
| `arm_turn` | `who`, `hand` | `{who} arm {hand}` | No `travel`: every documented arm turn goes once around, and no caption states another extent. ⚠ A half or 1½ arm turn would require one. |
| `shoulder_round` | `who`, `shoulder`, `travel` | *as contra* | Aliases: "gypsy", "gyre". Siding is a separate movement (§7.5). |
| `swing` | `who`, `endFacing` | *as contra* | Rare in ECD, included for coverage. "Balance and swing" is two figures (§5.4). |
| `box_the_gnat` | `who`, `hand`, `balance` | *as contra*: `{who} box the gnat` | Identical to contra `box_the_gnat`, including its `balance` flag (§5.4). Occurs as a figure in its own right (*Honeysuckle Cottage*). |
| `swat_the_flea` | as `box_the_gnat`, with `hand` fixed to `left` | *as contra*: `{who} swat the flea` | Identical to contra. A separately named entry stored as `box_the_gnat` with the hand fixed, so the two names never merge. |
| `gate` | `who`, `whom`, `pair`, `direction`, `travel`, `endFacing` | *as contra* | |
| `orbit` | `who`, `whom`, `direction`, `travel` | `{who} orbit {direction} {travel} [around {whom}]` | Evidence: 3 captions in *The Shrewsbury Lasses* ("orbit outside, same direction, ending improper"). The ending state has no parameter (Q3). |
| `mad_robin` | `who`, `whom`, `travel`, `direction` | *as contra* | |

### 7.3 Rings, stars and balances

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `balance` | `who`, `where`, `hand` | *as contra* | Captions include "partner right hand balance" and "balance forward and back". |
| `balance_ring` | none | `balance the ring` | |
| `circle` | `who`, `direction`, `places`, `singleFile`, `step` | *as contra*; with `step`, the step word replaces "circle" ("slip left 3 places"); with `who`, prefixed "{who}, ..." | `who` is offered only outside duple minor ("2s and 3s circle left"). Evidence: 10 captions in 7 dances. 6 give the extent as "half" or "half way", not a number of places. One states a side ("circle six left"). Single-file circles are called clockwise/counter-clockwise. ⚠ Should `circle` take a `fraction`, given that converting "half" to places depends on the size of the ring? (§8.4) |
| `star` | `who`, `hand`, `places`, `grip` | *as contra*, with a "{who}, ..." prefix when `who` is set | ECD's usual star is hands across, not contra's wrist grip. Evidence: all 3 transcribed stars say "hands across". One gives the extent as "once around", not places. ⚠ Should an unspecified grip *display* as hands across? Should `star` take a turn amount? |
| `form_short_wave` | `axis`, `balance`, `center`, `centerHand`, `sides` | *as contra* | `balance` is a yes/no flag ("wave and balance"). |
| `form_long_wave` | `who`, `whom`, `whomHand`, `balance` | *as contra* | ⚠ Tidal-wave topology is unresolved (§10). |

### 7.4 Heys, chains and rights-and-lefts

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `circular_hey` | `who`, `whom`, `slow`, `changes`, `where`, `shoulder` | `[{who} dance] {changes} [slow] changes of a circular hey, {whom} pass {shoulder} {where}` | Alias: "square hey". Passes by shoulders rather than hands. Evidence: 5 captions in 4 dances, all stating `changes` and whom to start with. One is captioned "(no hands)", which suggests hands are what separate it from rights and lefts. |
| `rights_and_lefts` | `who`, `whom`, `slow`, `changes`, `where`, `hand` | `[{who} dance] {changes} [slow] changes of rights and lefts, {whom} pull by {hand} {where} to start` | Not contra's "right and left through". Closer to a contra square through without a balance. Evidence: 9 captions in 6 dances. 8 state `changes`, several name the starting partner or neighbor, and none states a hand. |
| `chain` | `who`, `hand`, `where`, `open` | `{who} {hand}-hand [open] chain [{where}]` | Always shows the hand. `open` is a yes/no flag. |
| `figure_eight` | `who`, `whom`, `where`, `fraction`, `lead`, `double` | *as contra `figure_8`*; renders "double figure eight" when `double` is set | `double` means both couples move. `whom` names the couple danced around, which is ambiguous in non-duple dances. Evidence: "1s half figure 8 up through 2s", "Middles half figure 8 through nearest end". |
| `dolphin_hey` | `who`, `whom`, `shoulder`, `where`, `fraction`, `endFacing` | `{fraction} dolphin hey {where}: {who} pass {whom} {shoulder} shoulder to start, end facing {endFacing}` | |

### 7.5 Crossing, passing and travelling

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `cross` | `who`, `shoulder`, `where` | `{who} cross [diagonally] passing {shoulder} shoulder [{where}]` | Roughly the union of contra *pass through* and *pass by*. Evidence: 10 captions in 7 dances ("Women cross", "Partners cross", "cross in middle left shoulder"). One gives an ending facing ("cross with partner and face right"). |
| `right_left_through` | `who`, `whom`, `where`, `withHands` | `[{who} dance a] right and left through [{where}], {with \| without} hands, {others} courtesy turning {whom}` | ⚠ In a three-couple selection, "the others" is not always a single pair. |
| `fall_back` | `who`, `where` | `[{who}] fall back [{where}]` | `where` defaults to `across` and is then not shown. `who` defaults to everyone. Evidence: 4 captions in 4 dances, all "fall back with neighbor", one "a double". ⚠ This suggests a `whom`. |
| `back_to_back` | `who`, `shoulder`, `travel`, `where` | `{who} {shoulder}-shoulder back-to-back [{where}] {travel}` | Like contra dosido, but always named by shoulder, plus `where` (across/along). Evidence: 3 captions, none stating a shoulder. |
| `siding` | `who`, `shoulder`, `where`, `style` | `{who} {shoulder}-shoulder [{style}] siding [{where}]` (draft) | The parameters of `back_to_back` except `travel`, plus `style` (`straight` or `swirly`). An unstated style is `unspecified`. Captioned "Left Siding" (*Alexander's Birth Day*), and "Right/Left shoulder siding" in later passes of the *Double Jubilee* video. |
| `pass_through` | `who`, `where`, `shoulder` | `[{who}] pass through {shoulder} shoulders {where}` | |
| `promenade` | `who`, `where`, `direction`, `fraction`, `places`, `singleFile` | `{who} [single file] promenade {fraction \| N places} {direction} {where}` | `fraction` when in couples, `places` when single file. Evidence: "promenade half round the minor set", "promenade across the set back to original places". |
| `poussette` | `who`, `whom`, `fraction`, `direction` | *as contra* | ⚠ Contra defaults to half, clockwise. Evidence: 3 captions in 2 dances, all half, all naming who pushes ("women push", "men push first"), none stating a rotation. Heywood's *The Parson's Cap* is the one source we know that states both extent and rotation (half, counter-clockwise). See Q8. |
| `arch` | `who` | `{who} arch` | "Arch and dive through" is not defined. |
| `rollaway` | `who`, `whom`, `where`, `halfSashay` | `{who} roll away {whom} {where} [with a half sashay]` | Contra's ID is `roll_away`. `halfSashay` is a yes/no *style*, not "half a rollaway". |

### 7.6 Open movements

These movements are recognized, but their definitions depend on evidence or
community knowledge we don't yet have. Each is tied to a question in §9.

| Movement | What is known | Question |
| --- | --- | --- |
| *up a double / forward and back* (ID not chosen) | Evidence: 6 captions in 4 dances ("Up a double, and back", "Down a double, and back", "All up a double, and back", "Lines of three forward and back", "Line of four up a double and back, bending the line", "Forward"). It has a direction (up, down, forward), an optional return ("and back"), and sometimes a formation ("lines of three"). "A double" is also used as an extent for *fall back*. Contra's nearest move is `long_lines` (forward, optionally back). | Q10 |
| `lead` | Evidence (lead and cast together): 16 captions in 11 dances. They consistently state who, where ("up", "down", "to middle", "back") and a destination ("to progressed place", "home", "to 2nd place", "to the ends of a line of four"). Some state a route ("through 2s"). A likely starting set of parameters is `who`, `where`, `destination` and a route ("through {whom}"). | Q7 |
| `cast` | As for `lead`, plus a side ("cast left around neighbor"). One couple casting (or crossing and going below) while another leads the other way occurs in 9 captions in 7 dances. Five join the two with "as", which gives a `meanwhile`. Four use only a comma (§5.6). | Q7 |
| `set_and_link` | A single named movement (§5.4), including "tandem set and link". Roles, route and display are undefined. | Q9 |
| `hey` | Covers the number of dancers (3, 4, ...), straight/diagonal/end/parallel paths, and reels. Evidence: "1s left shoulder heys with end couples" (two heys for three danced at once, with a stated shoulder) and "a Shetland (tandem) reel for three couples". | Q4 |
| `grand_chain` | Evidence: 2 captions in 2 dances. Both are counted in changes ("six changes of a grand chain", "three changes of a grand chain"), like rights and lefts, and one states a hand. *The American Husband* names grand chain, ladies' chain and rights and lefts as distinct figures within one dance. | Q5 |
| `change_places` | Evidence: "change" is a standalone figure in 4 captions in 3 dances ("Change with partner (all home)", "W1+M2 change", "Men change"). None of those dances also uses "cross". | Q6 |
| `galop` | Unclear whether it is a movement or a travelling style that modifies other movements. | Q10 |
| `line` | A formation, an action, or both. Overlaps *up a double*. | Q10 |
| `bend_line` | Captioned as a modifier ("up a double and back, *bending the line*"), which fits the `modifier` container (§5.6). It may not need to be a movement at all. | Q10 |

## 8. Worked examples

These encodings illustrate the rules. They were written for this proposal
and have not been reviewed as transcriptions. Please correct them freely.

### 8.1 *The Farmer's Joy* (Joseph Pimentel, 2012), A1 and B2

```text
A1  (1-4) 1st corners set forward and turn single back to place
    (5-8) 1st corners two hand turn
B2  (1-4) Right hands across...
    (5-8) ...and back by the left
```

Proposed storage:

```text
set           who=["firstCorners"]  where=forward        direction=unspecified
turn_single   who=["firstCorners"]  shoulder=unspecified destination=place
two_hand_turn who=["firstCorners"]  direction=unspecified travel=unspecified
star          hand=right  grip=handsAcross  places=unspecified
star          hand=left   grip=unspecified  places=unspecified
```

Points to notice:

- **Two figures.** "Set forward and turn single" is stored as two figures
  (§5.4).
- **Unspecified values.** The source gives no side for the set, shoulder for
  the turn single, or amount for the two-hand turn, so all are
  `unspecified`.
- **No copying.** "Right hands across" states the grip. "Back by the left"
  does not, so the second star's grip and number of places are not copied
  from the first.
- **Lead and cast.** B1 of this dance ("1s lead down, wheel around, cross up
  and cast down, **as** 2s lead up") depends on `lead` and `cast` (§7.6).
  Its "as" makes it a `meanwhile`.

### 8.2 *The American Husband*, A2 (three couples)

```text
(1-4) 1s+2s face neighbors (diagonally) two changes of rights and lefts
(5-8) 2s+3s face neighbors (up and down) two changes of rights and lefts
```

```text
rights_and_lefts  who=["ones","twos"]   whom=neighbors  changes=2  where=diagonally  hand=unspecified
rights_and_lefts  who=["twos","threes"] whom=neighbors  changes=2  where=along       hand=unspecified
```

This shows why `who` must be a list.

### 8.3 *Alexander's Birth Day* (Gary Roodman, 2003), poussette

```text
With neighbor, half poussette, women push
```

```text
poussette  who=["role2s"]  whom=neighbors  fraction=half  direction=unspecified
```

"Women push" becomes `who = role2s` in role-neutral storage. It displays as
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
circle       singleFile=true  direction=counterclockwise  places=?
turn_single  shoulder=right   destination=unspecified
```

This passage shows three gaps in the current definitions:

- **`circle` extent.** The source says "half", but `circle` measures its
  extent in `places`. In a ring of four, half is two places. Writing
  `places=2` turns what the caller said into something they didn't say,
  and the conversion depends on the ring size.
- **`circle` ending state.** "(all home)" is an ending state, but `circle`
  has no `destination` parameter (Q3).
- **`turn_single` side.** "Turn single left" is stored as `shoulder=left`,
  though the source says "left", not "left shoulder" (Q13).

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

**Q3. Stated destinations and ending states.**
Should any moving figure be able to carry `destination` ("..., to
progressed place"), or only figures such as `turn single` where it is part
of the usual wording? The transcriptions state endpoints and ending states
for many kinds of figure:

- casts ("to progressed place");
- changes ("all home");
- orbits ("ending improper");
- circles ("all home");
- lines ("all progressed and proper").

We want to separate "the source says where you end up" from "the software
worked out where you end up".

**Q4. Heys and reels.**
How should heys for three and for four, straight/diagonal/end/parallel heys,
reels, Shetland/tandem reels and mirror (Grimstock) heys be organized? Is
the number of dancers a parameter of one `hey` movement? How should we
record where a hey starts, who meets whom first, how far it goes, and heys
danced at the same time by different groups?

**Q5. Grand chain, chain and rights and lefts.**
Are grand chain and rights and lefts the same figure under different names,
related figures, or distinct? Does it depend on period or region?

**Q6. Cross versus change places.**
Is "change" or "change places" (with or without hands) a separate figure
from "cross", or the same figure with a `hand` parameter? The transcriptions
use one word or the other in any given dance, never both.

**Q7. Lead and cast.**
What parameters do "lead up/down/out", "lead through", "cast off/up/down",
"cast around" and "long corners cast" need? What separates cast from lead,
cross and fall back? Is `who`, `where`, `destination` and a route a
sufficient starting set (§7.6)? When one couple casts while another leads
and the source joins them with only a comma, should we record them as
happening together?

**Q8. Poussette.**
In ECD practice, what extent and rotation should a bare "poussette" imply?
Should an unstated extent stay unspecified, as §5.3 suggests? Does "men push
first" mean the pushing role changes partway through?

**Q9. Set and link.**
What is the canonical definition of set and link, and its tandem variant?
Who sets, who links, and where does each dancer end? Please point to
English-style sources that describe it precisely.

**Q10. Other open movements.**
- *Up a double / forward and back*: one movement with a direction and an
  optional return, or more than one? How does it relate to `line` and
  `fall_back`, and what should its ID be?
- `galop`: is it a movement or a travelling style?
- `line` and `bend_line`: are they formations, actions, or (for
  `bend_line`) a modifier?
- Tidal wave versus long and short waves.
- Single-file promenade versus single-file circle within a minor set.
- Chevron/Pothooks and mirror heys need their own definitions.

**Q11. Aliases that must not merge.**
Box the gnat and swat the flea are kept as separate named entries. Which
other pairs look alike but must stay distinct? Which of these are the same:
Jersey/Nevada twirl, Gay Gordons/Varsouvienne hold, box circulate,
"matchboxes", and chassé/slide/sashay/slice? What does Heywood's "Back to
back for four" mean?

**Q12. What's missing?**
Which common ECD figures are absent from §7? Which entries are really two
figures, or should merge with another?

**Q13. Specific value questions.**
- Does ECD have arm turns other than once around?
- Siding's `style` values are `straight` and `swirly`. Are those the words
  callers would recognize? Is there any other style of siding?
- Should `circle` (and perhaps `star`) accept a `fraction` or turn amount
  ("circle half", "star once around"), as well as or instead of `places`?
- Should the turn single's side be called `shoulder` or `direction`, given
  that sources say "turn single left/right"?
- Should `two_hand_turn`, `cross` and `fall_back` gain `endFacing` or
  `whom`, as their captions suggest?
- Should the usual ECD star grip be the default *display*, even when the
  source doesn't state it?
- How should `two_hand_turn.direction` be worded ("clockwise", "to the
  left", ...)?

**Q14. Selectors.**
Which of the actor phrases listed in §6.2 ("at the ends", "middles", "top
couple", "couple below", "others", "opposite-sex neighbor", "new partner")
deserve selector tokens? Which are relative to the previous figure and
should stay as source text? Should single-dancer tokens extend to threes
(and beyond) for three-couple and longer sets?

## 10. Out of scope

- **Implementation.** No code, database fields or file formats have been
  built. Spellings such as `threeQuarter` versus `three_quarter`, or `full`
  versus `whole`, are not yet fixed.
- **Specialized chain families.** Dixie, teacup, spin chain.
- **Specialized hey and reel families.** Interlocking, Morris-derived.
- **Wave topology.** Tidal wave and the ocean-wave/across-the-set
  distinction.
- **Footwork and gesture labels.** Jump/stamp, rigadoon, rant.
- **One-off named figures.** Tiroir, Yearn, Weathervane, Celtic knot,
  Lichfield hey, Four Winds, Serpentine (*Beach Spring*). These stay as
  source text.
- **Mapping to positional calling** (Q2): we want community input first.

## 11. How to respond

Any form of feedback helps, and partial answers are very welcome:

- Answer any of the questions in §9 by number.
- Mark up a registry row: "keep", "rename to ...", "merge with ...", "split
  into ...", "needs parameter ...".
- Send counter-examples: dances whose instructions can't be expressed with
  these parameters, ideally with a link to an **English-style** source
  (ECDDB record, published book, or a video with clear teaching).
- Correct the worked examples in §8.

Where you know of style or homonym problems (the same title used by an
English dance and a contra or other dance), please mention them. That is the
error we are most likely to make without help.

---

## Appendix A: how the contra grammar renders shared figures

Several ECD entries in §7 say "*as contra*". These are the contra display
patterns in Caller's Compendium, taken from
[`contra_taxonomy.dart`](../../packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart).
Parameters in square brackets are shown only when set. ECD diverges where
its notes in §7 say so.

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

Contra concrete defaults, such as poussette's "half, clockwise", are **not**
automatically ECD defaults. §5.3 applies: an ECD source that doesn't state a
value is stored as `unspecified`.

## Appendix B: sources

- Antony Heywood, figure catalogue and dance cards:
  <https://barndances.org.uk/Antony/>
- UpaDouble figure definitions, dance records and teaching videos:
  <https://www.upadouble.info/>
- Transcribed dances and their Heywood IDs: see the table in §3.
- Other dance records cited for style checks (Heywood IDs):
  - California Twirlin' [12344](https://barndances.org.uk/Antony/dancecard.php?ID=12344) (contra)
  - Marshmallows in Flight [24257](https://barndances.org.uk/Antony/dancecard.php?ID=24257) (contra)
  - How Great is the Pleasure [17744](https://barndances.org.uk/Antony/dancecard.php?ID=17744) (English)
  - The Parson's Cap [2736](https://barndances.org.uk/Antony/dancecard.php?ID=2736) (English)
  - Lichfield's Ruby Surprise [14581](https://barndances.org.uk/Antony/dancecard.php?ID=14581) (English)
  - Along the Dee [21981](https://barndances.org.uk/Antony/dancecard.php?ID=21981) (English)
  - Chrysalis [5943](https://barndances.org.uk/Antony/dancecard.php?ID=5943) (English) /
    [7513](https://barndances.org.uk/Antony/dancecard.php?ID=7513) (contra)
