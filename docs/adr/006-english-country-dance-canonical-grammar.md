# ADR-006: English Country Dance canonical figure grammar

- **Status**: Proposed (30 September 2026). Revised 18 November 2026 after
  the first round of review. Circulated for review by ECDDB contributors and
  other ECD callers, dancers and archivists before anything is implemented.
- **Roadmap item**: "ECD and Squares support" (Later milestones in
  [ROADMAP.md](../ROADMAP.md))
- **Deciders**: Maintainers, with community review

**What we're asking reviewers for:** corrections, missing vocabulary,
community practice, and answers to the
[open questions](#9-open-questions-for-reviewers).

This ADR is longer than most because it doubles as a review document for
readers outside this repository. In the template's terms: §1.1 and §2–§3
are the *context* (§1.1 states the requirements), §5–§7 the proposed
*decision*, §3 and §5 the *rationale*, and §9–§10 the open *consequences*
and *revisit triggers*. Once accepted, the resulting ECD taxonomy follows the versioning
process in [figure-taxonomy.md](../design/figure-taxonomy.md).

### What changed in this revision

The first round of review asked for stated requirements, a definition of
"movement" and of "figure", and pointed out that *The Farmer's Joy* lost the
meaning of "and back". This revision answers those points. Section numbers
are unchanged, so earlier references still find the same topic, but §5.3,
§5.4 and §5.6 now say something different from the draft. The maintainer's
decisions behind this revision are recorded in the description of the pull
request that made it.

- **Requirements are stated** (§1.1). Complete coverage of every dance is not
  one. Losing or changing anything the source states is ruled out.
- **"Movement" is defined** (§4) as a pattern of travel. Hand, arm and
  two-hand turns are now one movement, `hand_turn`, and their familiar names
  are aliases (§7.2). Gate, swing and shoulder round stay separate, and §4
  says why.
- **"Figure", "step" and "line" are defined** (§4). "Set and turn single" is
  one line: a `sequence` of two steps (§5.4, §5.6). The draft stored it as
  two lines.
- **"And back" is kept.** Every movement in which dancers travel can carry a
  stated `destination` (§6.4). *The Farmer's Joy* is re-encoded (§8.1). This
  answers Q3.
- **Not stating a value is separated from what words carry** (§5.3). Wording
  such as "and back" or "to place" is stored. Only what the source leaves out
  is `unspecified`.
- **Timing is entered and shown in bars** (§5.5). A sequence can give one
  span of bars for several actions.
- **Stored movement IDs carry an `ecd_` prefix** (§5.1).
- **"Up a double" is defined**, as `forward_and_back` (§7.5).
- **"Gypsy" is no longer an alias.** It is a discouraged term (§7.2).
- **Import is aimed at ECDDB** (§2). Heywood's catalogue and the UpaDouble
  videos remain evidence, not import sources.
- **Evidence from contra book transcriptions** is added (§3).
- **Two new questions**: extents defined by a goal (Q15) and half bars in
  triple time (Q16).

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
partners" entry. A two-hand turn (both hands) and an arm turn (an arm hold)
are the same movement with different values, and can still be entered,
searched and shown by their own names.

The registry (§7) has **44 movements**:

- **35 are defined**, each with parameters and a draft display. Some still
  have specific review points.
- **9 are open**, because we lack the evidence or the community knowledge
  to define them well: `hey`, `grand_chain`, `change_places`, `lead`,
  `cast`, `galop`, `line`, `bend_line` and `set_and_link`.

The open movements and the questions in §9 are where ECDDB contributors can
help most.

### 1.1 Requirements

The maintainer set these requirements in November 2026, after the first
round of review, as recorded in the description of the pull request that
made this revision. They are inputs to the design, not proposals. The
wording of the table and of the definitions it relies on (§4) is this
ADR's.

| | Requirement |
| --- | --- |
| **R1. Structure as much as possible, never fail to store.** | A line the grammar can't express is stored as free text (a *custom* figure, as in the contra grammar), and a dance can mix structured and free-text lines. Representing every dance completely is **not** a requirement: several well-known ECD dances are made of movements no shared taxonomy will cover. Failing to structure a line is not failing to store it, but every line should be structured where it can be. |
| **R2. Never lose or change what the source states.** | A stored figure may drop wording that carries no information and restore it when displayed ("back to place" is stored as `destination = place`). It may never say something different from the source. If structuring a line would lose a stated detail, the detail goes in a note on the structured figure, or the line stays free text. What the source leaves out is stored as `unspecified` (§5.3). |
| **R3. Search.** | Dances can be found by a movement with any of its parameter values, by an alias ("arm right" finds turns stored with an arm hold), and by ordered runs of figures ("X then Y"). |
| **R4. Render as calling language, in any dialect.** | Every stored line reads back as a line a caller could say aloud, keeping its stated meaning ("Right hands across and back by the left"). The app's full [dialect system](../design/dialect.md) applies, as it does for contra: spelling, role and dancer terms, and per-movement display formulas, including the conditional `[if … then … else …]` groups. |
| **R5. Import without inventing, aimed at ECDDB.** | The main import target is ECDDB, integrated as the app integrates The Caller's Box: not every dance will have published figures. Aligning on a shared taxonomy should keep the adapter small. Heywood's catalogue and the UpaDouble videos inform the vocabulary (§3), but are not import sources (§2). A line an importer can't resolve keeps its source text. |
| **R6. Minimal and canonical.** | One movement per pattern of travel (§4). Hand, hold, extent, direction, who dances and where they end are parameters. Familiar names are aliases that can be entered, searched and displayed, while the stored form stays compact. The `sequence` container (§5.6) groups runs without adding combined movements. |
| **R7. Timing in bars.** | Users enter timing in bars, imports bring bars where the source gives them, and the app shows bars. The app stores beats, converted through the dance's phrase structure (§5.5). In ECD, a sequence can give one span of bars for several actions without timing each step. |
| **R8. Independent of contra.** | ECD owns its movements. Stored IDs carry an `ecd_` prefix. Parameter names are shared with contra where the concept is the same, but definitions are not (§5.1). |
| **R9. No tracking of dancer positions.** | The app does not work out where dancers are or check that a dance works. A `destination` is stored because the source, or the person entering the dance, states it. It is never computed. |

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

**Import sources.** ECDDB is the import the app is designed for, in the way
it already imports from The Caller's Box: dances whose figures are published
come in structured, and others come in with their metadata. The sources in
§3 serve a different purpose:

- Heywood's catalogue lists which figures a dance contains, but not their
  order or the choreography, so it informs vocabulary only.
- The UpaDouble teaching videos do contain the choreography. Extracting it
  takes OCR and caption analysis by AI agents, which doesn't fit inside the
  app. They are evidence for this proposal, not an import path.

**Alignment with ECDDB.** The more closely this grammar matches ECDDB's own
model, the smaller the adapter. In the long term the maintainer will
probably treat the ECDDB taxonomy as the authoritative model, and propose
changes there before adopting them in the app, to help prevent the two
drifting apart. That is the maintainer's expectation, not yet an agreement
with ECDDB.

## 3. Research basis

Five kinds of source inform the grammar. Each has limits, and those limits
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

**Contra book transcriptions.** The companion
[Compendium Analect](https://github.com/ibanner56/Compendium-Analect)
project transcribes dance books into this app's contra grammar. It reports
about 5,200 book phrases translated in 776 dances from three contra books.
Two further volumes, entered by hand, are not in that count. None of this
is ECD,
so it says nothing about what an ECD word means. It does show how book
shorthand and the containers ECD shares with contra (§5.6) behave in
practice, and it shaped §5.3–§5.6:

- **"Return" and "and back"** were the most costly shorthand (about 380
  phrases). Where they were resolved, the returning figure was written out
  again, and nothing recorded that it ended where the first began.
- **One span of music for several actions.** When a book gave a single span,
  the transcribers had to split it between the figures. About 60 of those
  splits were guesses.
- **Groups of couples** that `who` couldn't name were put in notes. In one
  review, six figures passed validation while claiming that all six dancers
  did what the source gave to two.
- **Casting** was one of the largest families of untranslated lines (about
  200), because the contra grammar has no cast. It was most often a cast
  danced while another couple moves up.
- **"While" and commas.** Two transcribers of the same author's books
  disagreed on when a comma means "at the same time".

These counts are reported by that project from work it has not yet
released. They have not been re-derived for this document.

## 4. Terms used in this proposal

| Term | Meaning here |
| --- | --- |
| **Movement** (or *move*) | A canonical entry in the grammar, such as `set`, `hand_turn` or `poussette`, with a stable `snake_case` ID (stored with an `ecd_` prefix, §5.1). A movement is **a pattern of action**: for a movement that travels, who moves around or past whom, and along what path; for one danced in place (`set`, `honor`, `clap`), the action itself. Two descriptions are the same movement if a dancer could be taught the difference as "the same thing, but with X", where X is one variation: who dances, the hand, the hold, how far, which way, or where they end. Each such variation is a **parameter**. |
| **Parameter** | A named property of a movement, such as `who`, `hand` or `travel`. Each movement declares which parameters it accepts. |
| **Figure** | One stored item: either a movement with its parameter values, e.g. `hand_turn(who=["partners"], hand=right, travel=1)`, or a container holding other figures. A figure the grammar can't express is a *custom* figure holding its source text. |
| **Step** | A figure inside a `sequence`. |
| **Line** | A figure at the top level of a dance: one row of the dance as displayed. "Set and turn single" is one line made of two steps. |
| **Dance** | An ordered list of lines, with phrase and bar information held separately. |
| **Container** | A structural figure that groups other figures: `meanwhile`, `modifier` or `sequence` (§5.6). |
| **Alias** | Source wording that maps to a movement, sometimes fixing a parameter. "RH turn" maps to `hand_turn` with `hand=right`. "Two-hand turn" maps to `hand_turn` with `hand=both`. An alias whose fixed parameters set it apart is shown and searchable under its own name, as "two-hand turn" is. Aliases that fix the same values, such as "RH turn" and "turn by the right", can't be told apart once stored, so how such a figure reads is a dialect choice. |
| **Discouraged term** | A word the app recognizes in imported or typed text but never offers, such as "gypsy". The [dialect system](../design/dialect.md) stores it as its canonical meaning and flags it in the editor. |
| **Selector** | A token naming dancers: `partners`, `neighbors`, `ones`, `firstCorners`, `role1s`, ... |
| **Role-neutral** | Stored dances use `role1`/`role2`. Men/women, larks/robins, gents/ladies, or positional terms are applied only when the dance is displayed. |
| **Unspecified** | "The source did not say." A real stored value, different from any concrete default. |
| **Destination** | Where dancers end, when the source or the person entering the dance states it (§6.4). |
| **Defined** / **Open** | A defined movement has parameters and a draft display. An open movement doesn't yet, and is listed in §7.6. |

**How the definition of movement plays out.** Its test is whether dancers
travel in the same pattern, differing in one variation at a time, not
whether two names exist. Merging the turns and keeping shoulder round
separate are the maintainer's decisions; the reasoning below is this ADR's.

- **Merged.** A right-hand turn, a two-hand turn and an arm turn all have
  two dancers turning around a shared center while connected. They differ
  only in hand and hold, so they are one movement, `hand_turn`.
- **Separate: gate.** One dancer pivots in place while the other travels
  around them, moving the pair to a new facing. The path is different, not
  just the hold.
- **Separate: swing.** Its hold, footwork and rotation all differ from a
  hand turn's at once, so it isn't "a hand turn, but with X" for any one X.
- **Separate: shoulder round.** Dancers circle each other facing, without a
  hold, and keep a named shoulder towards each other. It is not a turn.
  Siding and back-to-back are likewise named by
  shoulder and stay separate movements.

## 5. Design principles

These principles are settled by the Caller's Compendium maintainer.
Reviewers are still welcome to challenge them. Where a detail inside a
principle is this ADR's own proposal rather than the maintainer's, it says
so.

### 5.1 ECD owns its movement IDs, but shares parameter names

Where ECD and contra describe the same *concept*, they use the same
parameter name. The allowed values and defaults may still differ. A
movement's ID, meaning and display belong to ECD. Where a source-specific
count has no contra equivalent (such as `changes` in rights and lefts), ECD
defines its own parameter.

**Stored IDs carry an `ecd_` prefix**: `ecd_set`, `ecd_hand_turn`,
`ecd_poussette`. The maintainer decided this in November 2026 (recorded
with the other decisions behind this revision). ECD dances imported or
entered today hold contra moves, because no ECD taxonomy exists yet, so a
plain `poussette` or `star` in an ECD dance would be ambiguous. The reasons
for the prefix, as this ADR sees them:

- an older build that receives an ECD dance shows an unknown move instead of
  silently reading it with contra's meaning and defaults;
- anything keyed by move ID, such as dialect wordings and shorthand, can't
  collide with contra;
- a plain ID in an ECD dance is known to be a contra move stored before the
  ECD taxonomy existed.

The prefix applies to movements only. The containers (§5.6) are structural
IDs shared by every dance form, and stay unprefixed. A square dance grammar
proposed in parallel makes the same choice with an `sq_` prefix. This
document writes IDs without the prefix to keep the tables readable.

A parameter name can mean different things in different dance forms. ECD's
`destination` names a *position* (§6.4), while contra's `promenade` has a
`destination` that names *people* ("to new neighbors"). Each form has its
own dialect, so the shared name doesn't cause confusion.

### 5.2 `who` is a list

In ECD, `who` is always stored as a **list** of selector tokens, even when it
names one group: `["ones"]`, or `["twos", "threes"]` in a triple-minor or
longways-set figure such as "2s and 3s circle left". The transcriptions use
such combinations often: "1s+2s", "2s+3s", "1s+3s", "middle two couples".
The order is kept as entered. How to store a figure whose source never says
*who* dances is an open question (Q1).

The contra transcriptions (§3) show what happens without a list: groups such
as "ones and threes" end up in notes, and the figure claims more dancers
than the source named.

### 5.3 Store what the words say; never fill in what they leave out

Two different things can look alike in a source:

- **Meaning carried by the words.** "And back" means return to where the
  line began. "To place" names an endpoint. These are stated, and are stored:
  "and back by the left" becomes a step whose `destination` is `place`
  (§5.4, §6.4).
- **Details the source leaves out.** If a source omits a hand, shoulder, side
  or direction, the stored value is `unspecified`. The grammar never fills in
  a "usual" value and presents it as something the source said.

When someone is *writing* a dance by hand, the editor may *suggest* the usual
choice (right, for `set` and `turn single`). An imported dance whose source
was silent must not appear to have said "right".

Storage may drop wording that adds nothing, and the display restores it
(R2): "turn single back to place" is stored as `destination = place`, and
"back to" is added again when it is shown. If structuring a line would lose a
stated detail, the detail goes in a note on the figure, or the line stays
free text.

### 5.4 Ordered runs: adjacent lines or a sequence

An ordered run of figures, such as "set and turn single", "cross and cast",
"right-hand turn, then left", "right hands across and back by the left",
"circle left and right", or "balance and swing", can be stored in two ways:

- **as adjacent lines**, each with its own timing; or
- **as one line**: a `sequence` (§5.6) of two to four steps, with one span
  of bars.

The maintainer decided that ECD uses the sequence container. When to use it
is this ADR's proposal. Use a sequence when any of these applies:

- the source writes the run as one line or clause;
- the source gives one span of music for the whole run ("bars 1–4");
- the run is one side of a `meanwhile`;
- a later step returns to where an earlier one began ("and back"). It
  **must** be a sequence then, because `destination = place` means where
  dancers were when the *line* began (§6.4). On a line of its own, it would
  mean where that step began.

Otherwise, use adjacent lines. Either way, search finds each step of a
top-level sequence, alone or in an ordered run. Ordered-run search ("X then
Y") does not yet look inside a sequence that is one side of a `meanwhile`
([search.md](../design/search.md)); R3 would need that extended.

Neither form is a combined movement. Values are not copied from one step to
the next unless the source states them. "Back by the left" does not imply
the same grip or number of places as the first star. But "back" itself is
stated, so the returning step carries `destination = place` (§8.1).

There are two kinds of exception:

- **`set_and_link`** is one movement, distinct from a bare `set`, because
  the combined figure is a named unit of its own. Its definition is open
  (§7.6). A link danced on its own is recorded as "trade places, turning
  single", with the note "as in set and link" (the maintainer's wording).
  Storing that as a `modifier` of a change of places and a turn single is
  this ADR's proposal, and depends on `change_places` being defined (Q6).
- **A preceding balance** is recorded as a `balance` flag on
  `box_the_gnat` and on the two wave formations, matching the contra
  taxonomy. Contra also folds a preceding balance into `swing` (its `prefix`
  parameter). ECD's `swing`, as proposed here, does not: in ECD, "balance
  and swing" is a sequence or two lines (§7.2).

### 5.5 Timing is recorded in bars, and is not part of a movement

ECD dances are set to tunes of many meters, and callers time them in bars:
one line takes bars 1–2 and the next bars 3–6. Entering and showing bars,
storing beats, and the ECD-only span are the maintainer's decisions. The
other points below are this ADR's proposal.

- **Bars in, bars out.** Users enter timing in bars, imports bring bars where
  the source gives them, and the app shows bars.
- **Beats underneath.** The app stores beats, as it does for contra, so its
  existing timing and section arithmetic applies to lines as it does today.
  It converts between bars and beats through the dance's phrase structure,
  which records
  the number of phrases, bars per phrase and beats per bar for each part of
  the tune: for example `4*8*3` for four 8-bar phrases in triple time. A
  tune whose meter changes is several components joined with `+`. Whether a
  figure can last half a bar in triple time is Q16.
- **Bar ranges are derived.** "Bars 1–4" and phrase labels (A1, B2) come from
  the order and length of the lines, as section labels do for contra. They
  are not stored.
- **One span for a sequence** (ECD only for now). A sequence can carry a single span ("A, B and C in bars 1–4") while its
  steps carry no timing of their own. Contra sequences keep their current
  contract, where the total is always the sum of the steps.
- **Rules for the span.** If every step carries
  timing, the steps must add up to the span. Two parts of the app read each
  step's own timing today and would have to allow for untimed steps: the
  editor, which keeps a sequence's total equal to its steps' sum, and search,
  which places each step of a top-level sequence in the section where it
  starts ([search.md](../design/search.md)).

Timing is still not a movement parameter. `fraction`, `changes`, `places`
and `travel` describe *how far*, not *how long*. Progression results and
citations belong to the dance's transcription and provenance.

### 5.6 Three structural containers

The ECD grammar uses the app's three containers, which are shared across
dance forms:

- **`meanwhile`**: two or more figures that genuinely happen **at the same
  time**, e.g. "1s cast down **as** 2s lead up". Displayed joined by
  "while".
- **`modifier`**: one core action plus modifiers that describe it, rendered
  as "*X*, *Y*-ing", e.g. "up a double and back, *bending the line*".
- **`sequence`**: two to four steps danced in order and shown as one line,
  joined as an English list ("set and turn single"). Its uses are in §5.4,
  and its ECD timing in §5.5.

`meanwhile` and `modifier` hold 2–6 child figures, and `sequence` holds 2–4.
Each has one authoritative timing, and a sequence must fit in one phrase. A
container may
nest one level inside a container of another kind, such as a `sequence` as
one side of a `meanwhile`. Ordinary sequence is still the order of lines in
the dance. Any container may carry a **title**, a searchable name for the
group shown before its line. Named one-off figures (§10) can therefore be
stored as a titled container with structured steps where that is possible,
rather than as plain text. The container contracts are specified in
[domain-model.md](../design/domain-model.md).

A `meanwhile` is used only when the source states concurrency, for example
with "as" or "while". Two actions joined by a comma ("2s cast down, 1s lead
up") are recorded as two figures in order, even where dancers would read
them as simultaneous (Q7). The contra transcriptions (§3) show that
transcribers diverge on this unless the rule is spelled out with examples,
so any ECD transcription guide should include them.

### 5.7 Shorthand is expanded only when it is unambiguous

`repeat`, `same`, `v.v.`, `similar`, "back again" and similar shorthand are
written out in full in a transcription **only** when the source makes clear
what is repeated and by whom. Otherwise the source text is kept as written.
In the transcriptions, the shorthand that does occur is resolvable: "That
again", "M2 & W1 the same", "others counter" and "continue in the same
direction" each refer to the immediately preceding figure. In the contra
books (§3), "same" meant three different things: the same dancer, the same
group, or the same formation. An expansion has to know which one it is.

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
| `grip` | How dancers hold on, where a movement allows more than one hold | `hand`/`arm` (hand turn), `handsAcross` (star), `unspecified` |
| `shoulder` | The shoulder passed | `right`, `left`, `unspecified` |
| `travel` | The amount of turn, in full turns | `0.5`, `1`, `1.5` |
| `fraction` | A fractional extent of a figure | `quarter`, `half`, `three-quarter`, `whole` |
| `places` | Places moved around a ring or star | a positive whole number, or `unspecified` |
| `changes` | Changes in a hey, chain or rights-and-lefts | a positive whole number |
| `endFacing` | Which way dancers face at the end | `up`, `down`, `in`, `out` |
| `singleFile` | Single-file variant (yes/no) | |
| `destination` | Where dancers end, when **stated** (§6.4) | `place`, `second place`, `original places`, `progressed place`, `all improper` |
| `goBack` | The movement returns the way it came ("and back") (yes/no) | |
| `distance` | A named distance travelled | `double`, `unspecified` |
| `formation` | The grouping a movement is danced in, where it varies | `linesOfThree`, `linesOfFour` |
| `step` | Prescribed footwork | `slipping`, `skipping`, `unspecified` |
| `style` | A named manner of performing a movement (siding only) | `straight`, `swirly`, `unspecified` |

We avoid generic catch-all names (`target`, `extent`, `spin`, `turn`) where
one of the names above already fits. The name `grip` is this ADR's choice:
the star already had a `grip`, and using the same name for a hand turn's
hold keeps one concept under one name.

### 6.2 Selectors (values for `who` / `whom`)

`everyone`, `role1s`, `role2s`, `ones`, `twos`, `threes`, `fours`, `fives`,
`partners`, `neighbors`, `sameRoles`, `shadows`, `secondShadows`,
`prevNeighbors`, `nextNeighbors`, `thirdNeighbors`, `fourthNeighbors`,
`prevPartners`, `nextPartners`, `thirdPartners`, `fourthPartners`,
`fifthPartners`, `firstCorners`, `secondCorners`, `corners`, `longCorners`,
`firstDiagonals`, `secondDiagonals`, `diagonal`, `actives`, `couples`,
`sideCouples`, `centers`, `top`, `bottom`, `unspecified`.

For a single named dancer: `onesRole1`, `onesRole2`, `twosRole1`,
`twosRole2`, `threesRole1`, `threesRole2`, `foursRole1`, `foursRole2`. The
contra taxonomy added the third and fourth couples' dancers in v39.

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
what those produce. Every formula can be reworded per dialect, as contra's
can (R4).

`circular_hey` is the exception to "ECD owns its definitions" in one respect:
contra gained its own `circular_hey` (taxonomy v36) with a different parameter
set (`who`, `changes`, `shoulder`, `where`, and since v37 `who2`). It is defined independently, so
the ECD entry in §7.4 is **not** "as contra", and Appendix A lists the contra
version for comparison only.

### 6.4 Destinations

Every movement in which dancers travel accepts an optional `destination`,
stated by the source or by the person entering the dance (R9). That is the
maintainer's decision; the §7 tables don't repeat it. Movements with no
movement implied don't take one. This ADR reads that as `honor`, `clap`,
`turn_alone`, `balance`, `balance_ring`, `arch`, `form_short_wave` and
`form_long_wave`; reviewers may disagree with individual entries. `set` does
take one, because a set can travel ("set forward").

When no destination is stated, none is stored, and that means the same as
`unspecified`.

**Display.** A stated destination is always shown (R2, R4). Unless a
movement's own display formula places it, it is added at the end of the
line: ", to {destination}". `place` reads "back to place". A movement may
word it differently, as `turn_single` does, and as `star` does when it ends a
sequence ("and back by the left"). Which movements reword it is part of
their draft display in §7.

`forward_and_back` records "and back" with its `goBack` flag (§7.5), which
already means the dancers end where the line began. It doesn't take
`destination = place` as well.

| Value | Meaning | Typical wording |
| --- | --- | --- |
| `place` | Where each dancer was when **the line began**. In a sequence, the line is the whole sequence. | "to place", "back to place", "and back" |
| `first place`, `second place`, ... `sixth place` | A numbered position in the set | "to second place" |
| `original places` | Where each dancer was at the start of **this time through** the dance, not the start of the whole dance | "to original places", "all home" |
| `progressed place` | Where each dancer ends after progressing, which also covers "all progressed and proper" | "to progressed place" |
| `partner's place` | Where the dancer's partner was when the line began | "to partner's place" |
| `neighbor's place` | Where the dancer's neighbor was when the line began | "to neighbor's place" |
| `diagonal's place` | Where the dancer on that dancer's diagonal was when the line began | "to diagonal's place" |
| `all improper` | Everyone ends improper: on the opposite side of the set from their proper side | "ending improper" |

- **Numbered places depend on the formation.** The editor offers only the
  places a formation has: two in a duple minor, three in a triple minor or
  three-couple set, four in a four-couple set, and up to six where the set
  size is not fixed. Sixth is the limit for now. Longer sets may extend it.
- **"Back to" is display.** `place` is one value, whichever words the
  source used for it.
- **The list may grow.** Reviewers are welcome to name endpoints it is
  missing.

## 7. The figure registry

Each defined movement below has parameters and a draft display. "Defined"
means the design is specific enough to review. It does **not** mean the
entry has been accepted. Entries marked ⚠ contain a point we specifically
want reviewers to check. Movements in which dancers travel also accept
`destination` (§6.4).

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
| `turn_single` | `who`, `shoulder`, `destination` | `{who} turn single [{shoulder}] [{to \| back to} {destination}]` | Renders "back to" when `destination = place`, otherwise "to". Evidence: 13 captions in 7 dances. 5 state a side, always as "turn single left/right", never as a shoulder. 2 state a destination. ⚠ Is `shoulder` the right name for the side (Q13)? |
| `turn_alone` | `who`, `custom` | *as contra*: `{who} turn alone` | Identical to contra `turn_alone`. A separate movement from `turn_single`, not an alias of it. `custom` is contra's free-text note. |
| `hand_turn` | `who`, `hand`, `grip`, `travel`, `direction` | `{who} {hand}-hand turn {travel}`; aliases display as `{who} two-hand turn [{direction}] {travel}` and `{who} arm {hand} [{travel}]` | One movement for every turn of two dancers connected by hand or arm (§4). `hand` is `right`, `left` or `both`. `grip` is `hand` or `arm`, and `arm` can't be combined with `both`. `direction` is the rotation, used only with both hands, where the hand doesn't imply it (for sources such as Heywood's "two-hand turn anticlockwise"). Aliases, which can all be entered and searched: "right-hand turn", "turn by the right" (`hand=right`); "two-hand turn" (`hand=both`); "arm right", "arm left" (`grip=arm`). "Two-hand turn" and "arm right/left" are shown under their own names. The one-hand aliases fix the same values, so which of them a line shows is a dialect choice (§4). The parameters are modelled on contra `allemande` and `two_hand_turn`, but "allemande" is **not** an ECD alias. Evidence: one-hand turns, 6 captions in 3 dances, 2 with an extent ("right turn half"). Two-hand turns, 21 captions in 12 dances: 12 state an extent (9 half, 3 once and a half), 2 an ending facing ("and face down", "open to face new neighbors"), and none a rotation. No arm-turn caption states an extent other than once around. ⚠ How should `direction` be worded, and should the movement take `endFacing` (Q13)? |
| `shoulder_round` | `who`, `shoulder`, `travel` | *as contra* | Not a turn (§4). Alias: "gyre". "Gypsy" is **not** an alias. It is a discouraged term: the app recognizes it in imported or typed text, stores it as shoulder round, and flags it in the editor, but never offers it. Siding is a separate movement (§7.5). |
| `swing` | `who`, `endFacing` | *as contra* | Rare in ECD, included for coverage. Unlike contra's `swing`, it has no `prefix`: "balance and swing" is a sequence or two lines (§5.4). |
| `box_the_gnat` | `who`, `hand`, `balance` | *as contra*: `{who} box the gnat` | Identical to contra `box_the_gnat`, including its `balance` flag (§5.4), apart from the optional `destination` (§6.4). Occurs as a figure in its own right (*Honeysuckle Cottage*). |
| `swat_the_flea` | as `box_the_gnat`, with `hand` fixed to `left` | *as contra*: `{who} swat the flea` | Identical to contra apart from the optional `destination`. A separately named entry stored as `box_the_gnat` with the hand fixed, so the two names never merge. |
| `gate` | `who`, `whom`, `pair`, `direction`, `travel`, `endFacing` | *as contra* | Not a turn: one dancer pivots while the other travels around (§4). |
| `orbit` | `who`, `whom`, `direction`, `travel` | `{who} orbit {direction} {travel} [around {whom}]` | Evidence: 3 captions in *The Shrewsbury Lasses* ("orbit outside, same direction, ending improper"). "Ending improper" is `destination = all improper` (§6.4). |
| `mad_robin` | `who`, `whom`, `travel`, `direction` | *as contra* | |

### 7.3 Rings, stars and balances

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `balance` | `who`, `where`, `hand` | *as contra* | Captions include "partner right hand balance" and "balance forward and back". |
| `balance_ring` | none | `balance the ring` | |
| `circle` | `who`, `direction`, `places`, `singleFile`, `step` | *as contra*; with `step`, the step word replaces "circle" ("slip left 3 places"); with `who`, prefixed "{who}, ..." | `who` is offered only outside duple minor ("2s and 3s circle left"). Evidence: 10 captions in 7 dances. 6 give the extent as "half" or "half way", not a number of places. One states a side ("circle six left"). Single-file circles are called clockwise/counter-clockwise. "Half" and "half way" are stored as `places`, derived from the size of the ring: half the number of dancers in it. The ring is normally set by the formation: two places in a duple minor (four dancers), three in a triple minor (six dancers). When `who` names only some of the couples, the ring is those couples: "1s+2s circle half" in a triple minor is two places. An unstated extent is `places = unspecified`. |
| `star` | `who`, `hand`, `places`, `grip` | *as contra*, with a "{who}, ..." prefix when `who` is set; "and back by the {hand}" when it is the last step of a sequence and has `destination = place` | ECD's usual star is hands across, not contra's wrist grip. Evidence: all 3 transcribed stars say "hands across". One gives the extent as "once around", not places. An unstated extent is `places = unspecified`. ⚠ Should an unspecified grip *display* as hands across? Should `star` take a turn amount? |
| `form_short_wave` | `axis`, `balance`, `center`, `centerHand`, `sides` | *as contra* | `balance` is a yes/no flag ("wave and balance"). |
| `form_long_wave` | `who`, `whom`, `whomHand`, `balance` | *as contra* | ⚠ Tidal-wave topology is unresolved (§10). |

### 7.4 Heys, chains and rights-and-lefts

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `circular_hey` | `who`, `whom`, `slow`, `changes`, `where`, `shoulder` | `[{who} dance] {changes} [slow] changes of a circular hey, {whom} pass {shoulder} {where}` | Alias: "square hey". Passes by shoulders rather than hands. Evidence: 5 captions in 4 dances, all stating `changes` and whom to start with. One is captioned "(no hands)", which suggests hands are what separate it from rights and lefts. |
| `rights_and_lefts` | `who`, `whom`, `slow`, `changes`, `where`, `hand` | `[{who} dance] {changes} [slow] changes of rights and lefts, {whom} pull by {hand} {where} to start` | Not contra's "right and left through". Closer to a contra square through without a balance. Evidence: 9 captions in 6 dances. 8 state `changes`, several name the starting partner or neighbor, and none states a hand. |
| `chain` | `who`, `hand`, `where`, `open` | `{who} {hand}-hand [open] chain [{where}]` | Always shows the hand. `open` is a yes/no flag. |
| `figure_eight` | `who`, `whom`, `where`, `fraction`, `lead`, `double` | *as contra `figure_8`*; renders "double figure eight" when `double` is set | `double` means both couples move. Contra's `figure_8` gained the same flag in v39. `whom` names the couple danced around, which is ambiguous in non-duple dances. Evidence: "1s half figure 8 up through 2s", "Middles half figure 8 through nearest end". |
| `dolphin_hey` | `who`, `whom`, `shoulder`, `where`, `fraction`, `endFacing` | `{fraction} dolphin hey {where}: {who} pass {whom} {shoulder} shoulder to start, end facing {endFacing}` | |

### 7.5 Crossing, passing and travelling

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `cross` | `who`, `shoulder`, `where` | `{who} cross [diagonally] passing {shoulder} shoulder [{where}]` | Roughly the union of contra *pass through* and *pass by*. Evidence: 10 captions in 7 dances ("Women cross", "Partners cross", "cross in middle left shoulder"). One gives an ending facing ("cross with partner and face right"). |
| `right_left_through` | `who`, `whom`, `where`, `withHands` | `[{who} dance a] right and left through [{where}], {with \| without} hands, {others} courtesy turning {whom}` | ⚠ In a three-couple selection, "the others" is not always a single pair. |
| `fall_back` | `who`, `where` | `[{who}] fall back [{where}]` | `where` defaults to `across` and is then not shown. `who` defaults to everyone. Evidence: 4 captions in 4 dances, all "fall back with neighbor", one "a double". ⚠ This suggests a `whom`. |
| `forward_and_back` | `who`, `where`, `formation`, `distance`, `goBack` | `[{who}] [{formation}] {where} [a {distance}] [and back]` | Aliases: "up a double", "down a double" (`distance = double`), "forward and back", "lines forward and back". `where` is `up`, `down` or `forward`. `distance` is shown only when stated, so "Lines of three forward and back" doesn't gain "a double". `goBack` records "and back": the return is the same movement reversed, with nothing of its own to state, so it is a flag rather than a second step (§5.4), and it replaces `destination = place` (§6.4). A bare "Forward" is `goBack = no`. `formation` names the grouping ("lines of three"). Contra's nearest move, also `forward_and_back` since contra taxonomy v39, has `formation` and `goBack` (Appendix A). Evidence: 6 captions in 4 dances ("Up a double, and back", "Down a double, and back", "All up a double, and back", "Lines of three forward and back", "Line of four up a double and back, bending the line", "Forward"). The last-but-one is a `modifier` with a bend of the line (§7.6). ⚠ Promoted from open in this revision; its shape is this ADR's proposal. Does `distance` need values other than `double`, such as a single? How does it relate to `line` and `fall_back` (Q10)? |
| `back_to_back` | `who`, `shoulder`, `travel`, `where` | `{who} {shoulder}-shoulder back-to-back [{where}] {travel}` | Like contra dosido, but always named by shoulder, plus `where` (across/along). Evidence: 3 captions, none stating a shoulder. |
| `siding` | `who`, `shoulder`, `where`, `style` | `{who} {shoulder}-shoulder [{style}] siding [{where}]` (draft) | The parameters of `back_to_back` except `travel`, plus `style` (`straight` or `swirly`). An unstated style is `unspecified`. Captioned "Left Siding" (*Alexander's Birth Day*), and "Right/Left shoulder siding" in later passes of the *Double Jubilee* video. |
| `pass_through` | `who`, `where`, `shoulder` | `[{who}] pass through {shoulder} shoulders {where}` | |
| `promenade` | `who`, `where`, `direction`, `fraction`, `places`, `singleFile` | `{who} [single file] promenade {fraction \| N places} {direction} {where}` | `fraction` when in couples, `places` when single file. Evidence: "promenade half round the minor set", "promenade across the set back to original places". The second is `destination = original places` (§6.4). |
| `poussette` | `who`, `whom`, `fraction`, `direction` | *as contra* | ⚠ Contra defaults to half, clockwise. Evidence: 3 captions in 2 dances, all half, all naming who pushes ("women push", "men push first"), none stating a rotation. Heywood's *The Parson's Cap* is the one source we know that states both extent and rotation (half, counter-clockwise). See Q8. |
| `arch` | `who` | `{who} arch` | "Arch and dive through" is not defined. |
| `rollaway` | `who`, `whom`, `where`, `halfSashay` | `{who} roll away {whom} {where} [with a half sashay]` | Contra's ID is `roll_away`. `halfSashay` is a yes/no *style*, not "half a rollaway". |

### 7.6 Open movements

These movements are recognized, but their definitions depend on evidence or
community knowledge we don't yet have. Each is tied to a question in §9.

| Movement | What is known | Question |
| --- | --- | --- |
| `lead` | A distinct movement from `cast`. Evidence (counted together with cast, because the two often share a caption): 16 captions in 11 dances. They consistently state who, where ("up", "down", "to middle", "back") and a destination ("to progressed place", "home", "to 2nd place", "to the ends of a line of four"). Some state a route ("through 2s"). A likely starting set of parameters is `who`, `where`, `destination` (§6.4) and a route ("through {whom}"). | Q7 |
| `cast` | A distinct movement from `lead`. The captions state the same kinds of information, plus a side ("cast left around neighbor"). One couple casting (or crossing and going below) while another leads the other way occurs in 9 captions in 7 dances. Five join the two with "as", which gives a `meanwhile`. Four use only a comma (§5.6). In the contra books (§3) the same pattern was common and, with no `cast` movement, always ended up as free text. Of the open movements, this one would structure the most lines. | Q7 |
| `set_and_link` | A single named movement, distinct from a bare `set` (§5.4), including "tandem set and link". Roles, route and display are undefined. | Q9 |
| `hey` | Covers the number of dancers (3, 4, ...), straight/diagonal/end/parallel paths, and reels. Evidence: "1s left shoulder heys with end couples" (two heys for three danced at once, with a stated shoulder) and "a Shetland (tandem) reel for three couples". Contra's `hey_for_three` (v39: `who`, `whom`, `shoulder`) is a possible starting point. | Q4 |
| `grand_chain` | Evidence: 2 captions in 2 dances. Both are counted in changes ("six changes of a grand chain", "three changes of a grand chain"), like rights and lefts, and one states a hand. *The American Husband* names grand chain, ladies' chain and rights and lefts as distinct figures within one dance. | Q5 |
| `change_places` | Evidence: "change" is a standalone figure in 4 captions in 3 dances ("Change with partner (all home)", "W1+M2 change", "Men change"). None of those dances also uses "cross". A link danced on its own ("trade places, turning single") would build on it (§5.4). | Q6 |
| `galop` | Unclear whether it is a movement or a travelling style that modifies other movements. | Q10 |
| `line` | A formation, an action, or both. Overlaps `forward_and_back`. | Q10 |
| `bend_line` | Captioned as a modifier ("up a double and back, *bending the line*"), which fits the `modifier` container (§5.6). It may not need to be a movement at all. | Q10 |

## 8. Worked examples

These encodings illustrate the rules. They were written for this proposal
and have not been reviewed as transcriptions. Please correct them freely.
Bar ranges are shown in brackets; they are derived from the order and
length of the lines, not stored (§5.5).

### 8.1 *The Farmer's Joy* (Joseph Pimentel, 2012), A1 and B2

```text
A1  (1-4) 1st corners set forward and turn single back to place
    (5-8) 1st corners two hand turn
B2  (1-4) Right hands across...
    (5-8) ...and back by the left
```

Proposed storage:

```text
A1 [1-4]  sequence
            set          who=["firstCorners"]  where=forward  direction=unspecified
            turn_single  who=["firstCorners"]  shoulder=unspecified  destination=place
   [5-8]  hand_turn      who=["firstCorners"]  hand=both  direction=unspecified  travel=unspecified
B2 [1-8]  sequence
     [1-4]  star  hand=right  grip=handsAcross  places=unspecified
     [5-8]  star  hand=left   grip=unspecified  places=unspecified  destination=place
```

Displayed (default dialect):

```text
A1  1st corners set forward and turn single back to place
    1st corners two-hand turn
B2  Right hands across and back by the left
```

Points to notice:

- **A1 is one sequence** because the source writes it as one clause, "set
  forward and turn single back to place" (§5.4).
- **B2 is one sequence** because its second star returns to where the first
  began ("and back"), which §5.4 requires. The source splits that sentence
  across two phrases with an ellipsis, and gives each half its bars, so each
  star keeps its 4 bars. A sequence can hold a single span instead (§5.5),
  but here that would lose bars the source states (R2).
- **"And back" is kept.** The second star carries `destination = place`:
  dancers end where the line began, which is where the first star started
  (§6.4). The display turns it back into "and back by the left". Stating the
  return doesn't copy the first star's places or grip, which stay
  `unspecified`. Search still finds both stars, alone or as "star right then
  star left".
- **Unspecified values.** The source gives no side for the set, shoulder for
  the turn single, or rotation or amount for the two-hand turn, so all are
  `unspecified`.
- **Two-hand turn.** It is a `hand_turn` with `hand = both`, shown under its
  own name (§7.2).
- **Lead and cast.** B1 of this dance ("1s lead down, wheel around, cross up
  and cast down, **as** 2s lead up") depends on `lead` and `cast` (§7.6).
  Its "as" makes it a `meanwhile`. One side is a run of four actions, so it
  would be a `sequence` inside the `meanwhile`.

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
[1-2]  circle       singleFile=true  direction=clockwise         places=2
[3-4]  turn_single  shoulder=left
[5-6]  circle       singleFile=true  direction=counterclockwise  places=2  destination=original places
[7-8]  turn_single  shoulder=right
```

Points to notice:

- **`circle` extent.** "Half" becomes `places=2`. *Midwinter Maggot* is a
  duple minor, so the ring has four dancers, and half of it is two places
  (§7.3).
- **"All home"** is `destination = original places`: where the dancers stood
  at the start of this time through (§6.4). It is shown at the end of the
  line (", to original places"), so the circle's display doesn't drop it.
- **Four lines.** The source gives each action its own bars, so they stay
  adjacent lines rather than a sequence (§5.4).
- **`turn_single` side.** "Turn single left" is stored as `shoulder=left`,
  though the source says "left", not "left shoulder" (Q13).

## 9. Open questions for reviewers

These are ordered roughly by how much they block the design. Questions
Q1–Q3 are about data structure. Q4 onwards need ECD knowledge more than
software knowledge. Q3 is answered in this revision and kept so that
earlier references still work.

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

**Q3. Stated destinations and ending states.** *Answered in this revision.*
Every movement in which dancers travel can carry a stated `destination`
(§6.4), from the source or from the person entering the dance. Casts ("to
progressed place"), changes and circles ("all home"), orbits ("ending
improper") and lines ("all progressed and proper") all map to its values.
The app never works out a destination itself (R9). Still open: which
endpoints are missing from §6.4?

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
Lead and cast are two distinct movements. What parameters does each need to
cover "lead up/down/out", "lead through", "cast off/up/down", "cast around"
and "long corners cast"? What separates cast from cross and fall back?
Is `who`, `where`, `destination` and a route a
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
- *Up a double / forward and back* is now defined as `forward_and_back`
  (§7.5), with "and back" as a `goBack` flag and "a double" as a stated
  `distance`. Does that shape match how you write it? Are there distances
  other than a double? How does it relate to `line` and `fall_back`?
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
figures, or should merge with another? In particular: is merging hand,
two-hand and arm turns into one `hand_turn` (§7.2) right in your practice?

**Q13. Specific value questions.**
- Siding's `style` values are `straight` and `swirly`. Are those the words
  callers would recognize? Is there any other style of siding?
- Should `star` accept a turn amount ("star once around"), as well as or
  instead of `places`?
- Should the turn single's side be called `shoulder` or `direction`, given
  that sources say "turn single left/right"?
- Should `hand_turn`, `cross` and `fall_back` gain `endFacing` or `whom`,
  as their captions suggest?
- Should the usual ECD star grip be the default *display*, even when the
  source doesn't state it?
- How should a two-hand turn's `direction` be worded ("clockwise", "to the
  left", ...)?

**Q14. Selectors.**
Which of the actor phrases listed in §6.2 ("at the ends", "middles", "top
couple", "couple below", "others", "opposite-sex neighbor", "new partner")
deserve selector tokens? Which are relative to the previous figure and
should stay as source text? Single-dancer tokens now reach the fourth
couple. Do longer sets need more?

**Q15. Extents defined by a goal.**
Some sources give an extent by its result rather than its size: "almost
twice", "until the men face out", "a bit more than three quarters". A
stated endpoint can be a `destination`, but most of these can't. Should a
movement be able to mark its extent as approximate, or carry an
end-condition as text, or should these stay as notes?

**Q16. Half bars.**
Do ECD sources time figures in half bars? In duple time half a bar is a whole
number of beats, but in triple time it is not, and the app stores whole
beats (§5.5).

## 10. Out of scope

- **Implementation.** No code, database fields or file formats have been
  built. Spellings such as `threeQuarter` versus `three_quarter`, or `full`
  versus `whole`, are not yet fixed.
- **Tracking dancer positions** (R9). The app won't work out where dancers
  are, compute a destination, or check that a dance works.
- **Specialized chain families.** Dixie, teacup, spin chain.
- **Specialized hey and reel families.** Interlocking, Morris-derived.
- **Wave topology.** Tidal wave and the ocean-wave/across-the-set
  distinction.
- **Footwork and gesture labels.** Jump/stamp, rigadoon, rant.
- **One-off named figures.** Tiroir, Yearn, Weathervane, Celtic knot,
  Lichfield hey, Four Winds, Serpentine (*Beach Spring*). These stay as
  source text, or as a titled container where their steps can be structured
  (§5.6). They are not movements.
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
- Where ECDDB's own model already decides something this document leaves
  open, or decides it differently, please say so. The aim is to align with
  it (§2).

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
| `allemande` (a model for ECD `hand_turn`) | `who` (neighbors), `hand` (right), `travel` (1.5) | `{who} allemande {hand} {travel}` |
| `two_hand_turn` (a model for ECD `hand_turn` with both hands) | `who` (partners), `travel` (1) | `{who} two hand turn {travel}` |
| `shoulder_round` | `who` (neighbors), `shoulder` (right), `travel` (1) | `{who} shoulder round {travel}` |
| `swing` | `who` (partners), `prefix` (none; or balance, meltdown), `endFacing` (in) | `{who} swing` |
| `turn_alone` | `who` (everyone), `custom` (free text) | `{who} turn alone` |
| `box_the_gnat` | `who` (neighbors), `hand` (right), `balance` (no; the editor seeds yes) | `{who} box the gnat` |
| `swat_the_flea` | stored as `box_the_gnat` with `hand` fixed to left | `{who} swat the flea` |
| `circle` | `direction` (left), `places` (3; may be unspecified since v39), `singleFile` (no) | `circle {direction} {places}` |
| `star` | `hand` (left), `places` (4; may be unspecified since v39), `grip` (none) | `star {hand} {places}` plus a "hands across" / "wrist grip" clause when grip is set |
| `circular_hey` (**not** the ECD §7.4 entry) | `who` (neighbors, passes first), `changes` (4; any whole number 1-10), `shoulder` (right), `who2` (unspecified; v37, passed second by the other shoulder), `where` (across) | `{fraction} circular hey, {who} pass {shoulder} {where}[, {who2} pass {other shoulder}]`; fraction (`changes`/4) shown unless `changes` is 4 |
| `figure_8` | `who` (ones), `where` (above / below / across / none), `lead` (a single dancer, ones' role2), `fraction` (half), `double` (no; v39) | `{who} {fraction} figure 8` |
| `forward_and_back` (**not** the ECD §7.5 entry; v39, with `long_lines` its alias) | `formation` (longLines), `goBack` (yes) | `{formation} forward and back`; the `long_lines` alias reads `long lines` |
| `poussette` | `who` (role1s), `whom` (neighbors), `fraction` (half), `direction` (clockwise) | `{who} poussette {whom} {fraction} {direction}` |
| `gate` | `who`, `pair`, `whom`, `direction`, `travel`, `endFacing` (all unspecified) | `{who} {pair} gate {whom} {direction} {travel} {endFacing}` |
| `roll_away` | `who` (role1s), `whom` (partners), `halfSashay` (no) | `{who} roll away {whom}` |
| `mad_robin` | `who` (role2s), `travel` (1), `direction`, `whom` | `{who} mad robin {travel} {direction} {whom}` |
| `form_short_waves` | `axis` (across), `balance` (no), `center` (role2s), `centerHand` (left), `sides` (neighbors) | `form short waves` |
| `form_long_waves` | `who` (role1s), `whom`, `whomHand` (both unspecified), `balance` (no; the editor seeds yes) | `{who} form long waves` |

Contra concrete defaults, such as poussette's "half, clockwise", are **not**
automatically ECD defaults. §5.3 applies: an ECD source that doesn't state a
value is stored as `unspecified`.

## Appendix B: sources

- Antony Heywood, figure catalogue and dance cards:
  <https://barndances.org.uk/Antony/>
- UpaDouble figure definitions, dance records and teaching videos:
  <https://www.upadouble.info/>
- Transcribed dances and their Heywood IDs: see the table in §3.
- Compendium Analect, contra book transcriptions:
  <https://github.com/ibanner56/Compendium-Analect>
- Other dance records cited for style checks (Heywood IDs):
  - California Twirlin' [12344](https://barndances.org.uk/Antony/dancecard.php?ID=12344) (contra)
  - Marshmallows in Flight [24257](https://barndances.org.uk/Antony/dancecard.php?ID=24257) (contra)
  - How Great is the Pleasure [17744](https://barndances.org.uk/Antony/dancecard.php?ID=17744) (English)
  - The Parson's Cap [2736](https://barndances.org.uk/Antony/dancecard.php?ID=2736) (English)
  - Lichfield's Ruby Surprise [14581](https://barndances.org.uk/Antony/dancecard.php?ID=14581) (English)
  - Along the Dee [21981](https://barndances.org.uk/Antony/dancecard.php?ID=21981) (English)
  - Chrysalis [5943](https://barndances.org.uk/Antony/dancecard.php?ID=5943) (English) /
    [7513](https://barndances.org.uk/Antony/dancecard.php?ID=7513) (contra)
