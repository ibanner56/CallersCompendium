# ADR-006: English Country Dance canonical figure grammar

- **Status**: Proposed. Draft v0.2 (29 September 2026), circulated for review
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

This document proposes a small set of named movements, about 40 candidates,
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

The proposal is incomplete on purpose. Of 40 candidate movements, 32 have
draft parameters and 8 are deferred because we lack the evidence or the
community knowledge to define them well. Those are the questions where
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

**Six detailed dance transcriptions** from video. Four were completed: *The
Farmer's Joy*, *The American Husband*, *Alexander's Birth Day* and *The
Eliza*. Two were partial: *Barbarini's Tambourine* and *The Happy Pilgrim*.
Each describes one performance of one interpretation. None of them is proof
of a universal rule.

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
| 4 | `turn_single` | `who`, `shoulder`, `destination` | `{who} turn single [{shoulder}] {to \| back to} {destination}` | Renders "back to" when `destination = place`, otherwise "to". ⚠ Must `destination` always be given, even when the source is silent? |
| 5 | `hand_turn` | `who`, `hand`, `travel` | `{who} {hand}-hand turn {travel}` | Modelled on contra `allemande` in *parameters* only. "Allemande" is **not** an ECD alias. |
| 6 | `two_hand_turn` | `who`, `direction`, `travel` | *as contra, plus direction* | Contra `two_hand_turn` has no `direction`. ECD adds one ("two-hand turn anticlockwise"). ⚠ Needs a rendering and default. |
| 7 | `arm_turn` | `who`, `hand` | `{who} arm {hand}` | No `travel` yet: every arm turn we have documented goes once around. ⚠ Examples of a half or 1½ arm turn would change this. |
| 8 | `shoulder_round` | `who`, `shoulder`, `travel` | *as contra* | Aliases: "gypsy", "gyre", "siding"(?). ⚠ Is *siding* ever a shoulder round, or always its own figure? |
| 9 | `swing` | `who`, `endFacing` | *as contra* | Rare in ECD, included for coverage. "Balance and swing" is two figures. |
| 30 | `gate` | `who`, `whom`, `pair`, `direction`, `travel`, `endFacing` | *as contra* | |
| 33 | `orbit` | `who`, `whom`, `direction`, `travel` | `{who} orbit {direction} {travel} [around {whom}]` | |
| 40 | `mad_robin` | `who`, `whom`, `travel`, `direction` | *as contra* | Newly added candidate. |

### 7.3 Rings, stars and balances

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 2 | `balance` | `who`, `where`, `hand` | *as contra* | |
| 3 | `balance_ring` | none | `balance the ring` | |
| 10 | `circle` | `who`, `direction`, `places`, `singleFile`, `step` | *as contra*; with `step`, the step word replaces "circle": "slip left 3 places"; with `who`, prefixed "{who}, ..." | `who` is offered only outside duple minor ("2s and 3s circle left"). |
| 11 | `star` | `who`, `hand`, `places`, `grip` | *as contra*, with a "{who}, ..." prefix when `who` is set | ⚠ ECD's usual star is hands across, not contra's wrist grip. Should an unspecified grip display as hands across? |
| 36 | `form_short_wave` | `axis`, `balance`, `center`, `centerHand`, `sides` | *as contra* | `balance` is a yes/no flag ("wave and balance"). |
| 37 | `form_long_wave` | `who`, `whom`, `whomHand`, `balance` | *as contra* | ⚠ Tidal-wave topology is unresolved (§10). |

### 7.4 Heys, chains and rights-and-lefts

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 12 | `circular_hey` | `who`, `whom`, `slow`, `changes`, `where`, `shoulder` | `[{who} dance] {changes} [slow] changes of a circular hey, {whom} pass {shoulder} {where}` | Alias: "square hey". Often used interchangeably with rights and lefts, but passing by shoulders rather than hands. |
| 13 | `hey` | **deferred** | | Number of dancers (3, 4, ...), straight/diagonal/end/parallel paths, and how the reel relates. See Q4. |
| 14 | `figure_eight` | `who`, `whom`, `where`, `fraction`, `lead`, `double` | *as contra `figure_8`*; renders "double figure eight" when `double` is set | `double` = both couples move. `whom` added because in non-duple dances "the other couple" can be ambiguous. |
| 15 | `dolphin_hey` | `who`, `whom`, `shoulder`, `where`, `fraction`, `endFacing` | `{fraction} dolphin hey {where}: {who} pass {whom} {shoulder} shoulder to start, end facing {endFacing}` | |
| 16 | `rights_and_lefts` | `who`, `whom`, `slow`, `changes`, `where`, `hand` | `[{who} dance] {changes} [slow] changes of rights and lefts, {whom} pull by {hand} {where} to start` | ECD rights and lefts is **not** contra's "right and left through". It is closer to a contra square through without a balance. |
| 17 | `chain` | `who`, `hand`, `where`, `open` | `{who} {hand}-hand [open] chain [{where}]` | Always shows the hand. `open` is a yes/no flag. |
| 18 | `grand_chain` | **deferred** | | Its relationship to `chain` and `rights_and_lefts` is unresolved. See Q5. |

### 7.5 Crossing, passing and travelling

| # | Movement | Parameters | Draft display | Notes |
| ---: | --- | --- | --- | --- |
| 19 | `cross` | `who`, `shoulder`, `where` | `{who} cross [diagonally] passing {shoulder} shoulder [{where}]` | Roughly the union of contra *pass through* and *pass by*. |
| 20 | `change_places` | **deferred** | | Is it distinct from `cross`? See Q6. |
| 21 | `right_left_through` | `who`, `whom`, `where`, `withHands` | `[{who} dance a] right and left through [{where}], {with \| without} hands, {others} courtesy turning {whom}` | ⚠ In a three-couple selection, "the others" is not always a single pair. |
| 22 | `lead` | **deferred** | | Actor, route (between, outside, away) and destination. See Q7. |
| 23 | `cast` | **deferred** | | Direction and destination; how it differs from lead, cross and fall back. See Q7. |
| 24 | `fall_back` | `who`, `where` | `[{who}] fall back [{where}]` | `where` defaults to `across` and is then not shown. `who` defaults to everyone. |
| 25 | `back_to_back` | `who`, `shoulder`, `travel`, `where` | `{who} {shoulder}-shoulder back-to-back [{where}] {travel}` | Like contra dosido, but always named by shoulder, plus `where` (across/along). |
| 26 | `pass_through` | `who`, `where`, `shoulder` | `[{who}] pass through {shoulder} shoulders {where}` | |
| 27 | `promenade` | `who`, `where`, `direction`, `fraction`, `places`, `singleFile` | `{who} [single file] promenade {fraction \| N places} {direction} {where}` | `fraction` when in couples, `places` when single file. |
| 28 | `poussette` | `who`, `whom`, `fraction`, `direction` | *as contra* | ⚠ Contra defaults to half, clockwise. We have one ECD source that states *both* extent and rotation (*The Parson's Cap*: half, counter-clockwise). See Q8. |
| 29 | `galop` | **deferred** | | A movement, or a travelling style that modifies other movements? |
| 31 | `arch` | `who` | `{who} arch` | "Arch and dive through" is not yet defined. |
| 32 | `rollaway` | `who`, `whom`, `where`, `halfSashay` | `{who} roll away {whom} {where} [with a half sashay]` | Contra's ID is `roll_away`. `halfSashay` is a yes/no *style*, not "half a rollaway". |
| 34 | `line` | **deferred** | | A formation, an action ("lines forward and back"), or both? |
| 35 | `bend_line` | **deferred** | | A formation change or a movement? |

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
  deferred. The word "as" suggests a `meanwhile` container.

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
from "the software worked out where you end up".

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
over", or the same figure with a `hand` parameter?

**Q7. Lead and cast.**
What parameters do "lead up/down/out", "lead through", "cast off/up/down",
"cast around" and "long corners cast" need? What separates cast from lead,
cross and fall back?

**Q8. Poussette.**
In ECD practice, what extent and rotation should a bare "poussette" imply?
Should an unstated extent stay unspecified, as §5.3 suggests? We have very
few sources that state both extent and rotation.

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
Box the Gnat and Swat the Flea are related but use different hands and must
not collapse into one. Which other pairs look alike but must stay distinct?
Which of these are the same: Jersey/Nevada twirl, Gay Gordons/Varsouvienne
hold, box circulate, "matchboxes", and chassé/slide/sashay/slice? What does
Heywood's "Back to back for four" mean?

**Q12. What's missing?**
Which common ECD figures are absent from §7? Which entries are really two
figures, or should merge with another?

**Q13. Specific value questions.**
- Does ECD have arm turns other than once around?
- How is "siding" related to shoulder rounds?
- Should the usual ECD star grip be the default *display*, even when the
  source doesn't state it?
- How should `two_hand_turn.direction` be worded ("clockwise", "to the
  left", ...)?

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
