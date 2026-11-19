# ADR-006: English Country Dance canonical figure grammar

- **Status**: Accepted (19 November 2026). Proposed 30 September 2026, and
  revised 18 November 2026 after the first round of review. The maintainer
  answered the open questions on 19 November 2026 (§9) and made the
  implementation decisions in §12. The points left open on acceptance were
  answered the same day (§9.1).
- **Roadmap item**: "ECD and Squares support" (Later milestones in
  [ROADMAP.md](../ROADMAP.md))
- **Deciders**: Maintainers, with community review

**Feedback is still welcome.** Outside reviewers will mostly respond after
trying the implementation hands-on. Corrections, missing vocabulary and
community practice can change the taxonomy later through the versioning
process in [figure-taxonomy.md](../design/figure-taxonomy.md).

This ADR is longer than most because it began as a review document for
readers outside this repository. In the template's terms: §1.1 and §2–§3
are the *context* (§1.1 states the requirements), §5–§7 and §12 the
*decision*, §3 and §5 the *rationale*, and §9–§10 the *consequences* and
*revisit triggers*.

### What changed when cast was aligned with contra (19 November 2026)

Contra is gaining a `cast` movement of its own (issue
[#770](https://github.com/ibanner56/CallersCompendium/issues/770), still
being built). The maintainer decided that ECD's `cast` takes the same
parameters from the start, so that a
contra-imported English dance re-reads one to one (§12, F5). The answers are
in §9.4, and the sections they changed are:

- **`cast` has no `where`** (§7.5). Its `direction` is `left`, `right`, `up`
  or `down`, where `left` and `right` are the shoulder turned over, not a
  side of the set. It gains `places` ("cast down one place"), and its
  `destination` can be the top or bottom of the set. "Cast around 2s" is
  `whom`, and "cast off" is down one place.
- **A hand cast is a `gate`**, and can be found by that name (§7.2).

### What changed when one caller's notes were checked (19 November 2026)

While the registry was being built, it was checked against one caller's
own notation for her dances, as a data point for which figures callers use
in practice (not as a template). Figures it uses that this ADR didn't cover
were put to the maintainer, whose answers are in §9.3. The registry gained:

- **`pull_by`**, **`hey_for_six`**, **`petronella`** and **`contra_corners`**
  as movements (§7.3, §7.4, §7.5).
- **Cloverleaf** as a value of `turn_single`'s side (§7.2).
- **Push or draw** on `poussette`, as its `style` (§7.5).
- **"Chase"** as a name for a single-file `circle` (§7.3).
- Wheel around, loop, side step, serpentine change, hole-in-the-wall cross
  and "meet" stay source text for now (§10).

### What changed when the last open points were answered (19 November 2026)

Acceptance left eleven points open. The maintainer answered them all the
same day. Each answer is recorded in §9.1 in the maintainer's own words,
and the sections it changed are:

- **An unstated `who` is `["unspecified"]` again** (§5.2, §5.3, §8). This
  reverses the answer to Q1, so that R2 has no exception for `who`. The
  editor suggests `everyone` when someone enters a dance by hand.
- **"A double" is stored when the source gives no distance**, and the
  editor suggests it (§7.5). It is the one exception to R2, which the
  maintainer confirmed (§9.1, point 3).
- **Each dance form has its own dialect**, with everything a contra dialect
  has today (§12, S1 and S3).
- **The proper/improper checkbox and the new formation shapes are for ECD
  only.** Contra's shapes don't change. ECD has no Becket circle. It had no
  Sicilian circle either, until a later answer added one (§9.2, point 5).
- **Gendered role terms are never shown**, not even as a choice (§2, §4,
  §8.3). Where a quoted source uses one, this document gives the default
  dialect's term in square brackets instead (§3).
- **`set_and_link` takes no parameters**: no `who`, because everyone
  dances it at once, and no `tandem` flag, because everyone does the thing
  all the time (§7.1, §9.1 point 4).
- **`leftFile` and `rightFile`** are the left-hand and right-hand lines as
  the caller sees them, facing down the hall (§6.2).
- **"Pothooks"** is an alias of `chevron` (§7.5).
- **"Set forward"** is a `set` with `where = forward` (§7.1).
- **In `right_left_through`**, `who` names the four dancers who take part
  (§7.5).
- **Heywood's "Back to back for four"** is not supported (§10).
- **The new-dance form setting syncs** (§12, S2).

### What changed on acceptance (19 November 2026)

The maintainer answered every open question and made the implementation
decisions in §12. Each answer is recorded in §9, with the maintainer's own
notes quoted. The sections those answers changed are:

- **Turns are three movements again** (Q12): `hand_turn` (one hand),
  `two_hand_turn` and `arm_turn` (§4, §7.2). This reverses the merge made in
  the 18 November revision.
- **An unstated `who` is `everyone`** (Q1, §5.2, §5.3). The maintainer
  reversed this after acceptance (§9.1).
- **Defined, where the draft left them open** (§7): `lead`, `cast`,
  `change_places`, `grand_chain`, `galop`, `bend_line`, `chevron`,
  `mirror_hey`, and the hey family as separate movements (Q4). `set_and_link`
  is defined in part (Q9). `line` is not a movement (Q10).
- **The star takes no grip** (Q13e), and **the turns, `cross` and
  `fall_back` gain parameters** (Q13d).
- **New selectors**: `ends`, `middles`, `leftFile` and `rightFile` (Q2, Q14).
- **Stored values are camelCase**, as contra's are (§6.1, §12).
- **The dance record, settings and screens** are decided in §12.

### What changed in the 18 November revision

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
  two-hand turns became one movement, `hand_turn`, with their familiar names
  as aliases. Acceptance reversed that merge (Q12). Gate, swing and shoulder
  round stay separate, and §4 says why.
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
9. [Answers to the open questions](#9-answers-to-the-open-questions)
10. [Out of scope](#10-out-of-scope)
11. [How to respond](#11-how-to-respond)
12. [Implementation decisions](#12-implementation-decisions)
13. [Appendix A: how the contra grammar renders shared figures](#appendix-a-how-the-contra-grammar-renders-shared-figures)
14. [Appendix B: sources](#appendix-b-sources)

---

## 1. Summary

Caller's Compendium is an app for callers to store, search, edit and print
dances. For contra dance it already stores each figure as structured data
("who does what, with which hand, how far") rather than free text. We would
like to do the same for English Country Dance, and this document set out
the vocabulary before any of it was built.

It defines a small set of named movements, each described by a fixed list
of named parameters. For example, a right-hand turn once around by partners
is stored as the movement `hand_turn` with `who = partners`, `hand = right`,
`travel = 1`. It is not stored as a separate "right-hand turn partners"
entry. Two-hand turns and arm turns are movements of their own (Q12).

The registry (§7) has **49 movements**, each with parameters and a draft
display. The points left open on acceptance have been answered (§9.1).
Movements left out on purpose are listed in §10.

### 1.1 Requirements

The maintainer set these requirements in November 2026, after the first
round of review, as recorded in the description of the pull request that
made this revision. They are inputs to the design, not proposals. The
wording of the table and of the definitions it relies on (§4) is this
ADR's.

| | Requirement |
| --- | --- |
| **R1. Structure as much as possible, never fail to store.** | A line the grammar can't express is stored as free text (a *custom* figure, as in the contra grammar), and a dance can mix structured and free-text lines. Representing every dance completely is **not** a requirement: several well-known ECD dances are made of movements no shared taxonomy will cover. Failing to structure a line is not failing to store it, but every line should be structured where it can be. |
| **R2. Never lose or change what the source states.** | A stored figure may drop wording that carries no information and restore it when displayed ("back to place" is stored as `destination = place`). It may never say something different from the source. If structuring a line would lose a stated detail, the detail goes in a note on the structured figure, or the line stays free text. What the source leaves out is stored as `unspecified` (§5.3), including who dances. The maintainer made one exception: `forward_and_back` with no stated distance is stored as a double (§7.5, §9.1). |
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
  Honour/Honor spelling, or with role terms (larks/robins, leads/follows,
  or positional terms) chosen by the caller.
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
triple, three-couple, four-couple and circle formations. The table gives each
formation as its transcription names it. The app's ECD shapes have no Becket
circle (§12, F2), but do have a Sicilian circle (§9.2, point 5). Which ECD
shape *The American Husband* and *The Happy Pilgrim* would take is left to
whoever transcribes them; testers may want to revisit these two dances as
evidence. That is this ADR's call.

**Quotations.** Some sources name dancers with gendered role terms, which
this document never shows (§9.1). Where a quotation would, the default
dialect's role word takes its place in square brackets: "[Lark]" for the
first role and "[Robin]" for the second, as in "[Robins] cross" or "[Robin
2]".
That convention is this document's.

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
| **Alias** | Source wording that maps to a movement, sometimes fixing a parameter. "RH turn" maps to `hand_turn` with `hand=right`. "Arm left" maps to `arm_turn` with `hand=left`. An alias whose fixed parameters set it apart is shown and searchable under its own name, as "swat the flea" is (§7.2). Aliases that fix the same values, such as "RH turn" and "turn by the right", can't be told apart once stored, so how such a figure reads is a dialect choice. |
| **Discouraged term** | A word the app recognizes in imported or typed text but never offers, such as "gypsy". The [dialect system](../design/dialect.md) stores it as its canonical meaning and flags it in the editor. |
| **Selector** | A token naming dancers: `partners`, `neighbors`, `ones`, `firstCorners`, `role1s`, ... |
| **Role-neutral** | Stored dances use `role1`/`role2`. Role terms such as larks/robins or leads/follows, or positional terms, are applied only when the dance is displayed. Gendered role terms are never shown, not even as a choice (§9.1). |
| **Unspecified** | "The source did not say." A real stored value, different from any concrete default. |
| **Destination** | Where dancers end, when the source or the person entering the dance states it (§6.4). |
| **Defined** / **Open** | A defined movement has parameters and a draft display. Before acceptance, an open movement had neither and was listed in §7.6. Acceptance settled all of them: each was defined or split, except `line`, which was found not to be a movement (§7.6). |

**How the definition of movement plays out.** Its test is whether dancers
travel in the same pattern, differing in one variation at a time, not
whether two names exist. Keeping shoulder round separate is the
maintainer's decision; the reasoning below is this ADR's.

- **Turns: the maintainer's exception.** A right-hand turn, a two-hand turn
  and an arm turn all have two dancers turning around a shared center while
  connected, and differ only in hand and hold. By the test above they would
  be one movement, and the 18 November revision merged them as `hand_turn`.
  On acceptance the maintainer split them back into three movements:
  `hand_turn` (one hand), `two_hand_turn` and `arm_turn` (Q12, §7.2). The
  answer gives no reason, so this document doesn't supply one.
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
The order is kept as entered.

When the source never says *who* dances, `who` is stored as
`["unspecified"]`. When someone enters a dance by hand, the editor suggests
`everyone`. That is the maintainer's decision, which reversed the answer to
Q1 so that R2 holds for `who` (§9.1, point 5). `everyone` can't be combined
with another selector: the editor refuses `["everyone", "ones"]`, and an
importer keeps such a line as source text (Q1b). A line whose `who` is
`["unspecified"]` is displayed without a subject. A line whose `who` is
`["everyone"]` shows the dialect's word for everyone, such as "all", so "set
and turn single" and "all set and turn single" are stored and shown
differently. Both display rules are this ADR's proposal, as is the rule that
`unspecified`, like `everyone`, can't be combined with another selector.

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
  a "usual" value and presents it as something the source said. That
  includes `who` (§5.2). The one exception is the distance of
  `forward_and_back`, which the maintainer decided is stored as a double
  when the source gives none (§7.5, §9.1).

When someone is *writing* a dance by hand, the editor may *suggest* the usual
choice (right, for `set` and `turn single`; everyone, for `who`). An
imported dance whose source was silent must not appear to have said
"right". The one place where it can is the exception above: a silent
source's forward and back is shown as "a double" (§7.5).

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
the same number of places as the first star. But "back" itself is
stated, so the returning step carries `destination = place` (§8.1).

There are two kinds of exception:

- **`set_and_link`** is one movement, distinct from a bare `set`, because
  the combined figure is a named unit of its own (§7.1). A link danced on
  its own is recorded as "trade places, turning single", with the note "as
  in set and link" (the maintainer's wording). It is stored as a `modifier`
  whose core is `change_places` (§7.5) and whose modifier is `turn_single`.
  The modifier form is this ADR's proposal.
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
  tune whose meter changes is several components joined with `+`, and so
  is a dance in several parts (§12, F4). A figure can last half a bar only
  where half a bar is a whole number of beats, so not in triple time (Q16).
  The written meter and key are kept in their own fields (§12, F3).
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
again", "[Lark 2] & [Robin 1] the same", "others counter" and "continue
in the same direction" each refer to the immediately preceding figure. In the contra
books (§3), "same" meant three different things: the same dancer, the same
group, or the same formation. An expansion has to know which one it is.

Actor-number shorthand (such as `1C`) and one-off named figures (*Tiroir*,
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
| `direction` | A side, rotation or way specific to the movement | `left`/`right` (set), `clockwise`/`counterclockwise` (poussette, two-hand turn); for `cast`, `left`/`right` (the shoulder turned over), `up`, `down` (§7.5) |
| `hand` | The hand used | `right`, `left`, `none` (change places only), `unspecified` |
| `shoulder` | The shoulder passed | `right`, `left`, `unspecified` |
| `travel` | The amount of turn, in full turns | `0.5`, `1`, `1.5` |
| `fraction` | A fractional extent of a figure | `quarter`, `half`, `threeQuarter`, `full` |
| `places` | Places moved around a ring or star, or up or down the set in a `cast` | a positive whole number, or `unspecified` |
| `changes` | Changes in a hey, chain or rights-and-lefts | a positive whole number |
| `endFacing` | Which way dancers face at the end | `up`, `down`, `in`, `out` |
| `singleFile` | Single-file variant (yes/no) | |
| `destination` | Where dancers end, when **stated** (§6.4) | `place`, `secondPlace`, `originalPlaces`, `progressedPlace`, `allImproper` |
| `goBack` | The movement returns the way it came ("and back") (yes/no) | |
| `distance` | A named distance travelled | `double`, `single`, `unspecified` (not for `forward_and_back`, which stores `double` when none is stated, §7.5) |
| `formation` | The grouping a movement is danced in, where it varies | `linesOfThree`, `linesOfFour` |
| `step` | Prescribed footwork | `slipping`, `skipping`, `unspecified` |
| `style` | A named manner of performing a movement (siding only) | `straight`, `swirly`, `unspecified` |
| `switchPush` | The pushers change partway through (yes/no; poussette) | |
| `castShoulder` | The shoulder a casting pair turns over (chevron) | `left`, `right`, `unspecified` |

We avoid generic catch-all names (`target`, `extent`, `spin`, `turn`) where
one of the names above already fits. The draft had a `grip` parameter for
the star and the hand turn. Acceptance removed it: turns by the arm are now
`arm_turn` (Q12), and ECD stars are always hands across (Q13e).

**Stored spelling.** Stored values are camelCase, matching contra's
(`threeQuarter`, `full`, `secondPlace`, `originalPlaces`, `allImproper`).
The maintainer decided this on acceptance (§12, F1). Some tables in this
document write values as words, such as "second place", for readability.

### 6.2 Selectors (values for `who` / `whom`)

`everyone`, `role1s`, `role2s`, `ones`, `twos`, `threes`, `fours`, `fives`,
`partners`, `neighbors`, `sameRoles`, `shadows`, `secondShadows`,
`prevNeighbors`, `nextNeighbors`, `thirdNeighbors`, `fourthNeighbors`,
`prevPartners`, `nextPartners`, `thirdPartners`, `fourthPartners`,
`fifthPartners`, `firstCorners`, `secondCorners`, `corners`, `longCorners`,
`firstDiagonals`, `secondDiagonals`, `diagonal`, `actives`, `couples`,
`sideCouples`, `centers`, `top`, `bottom`, `ends`, `middles`, `leftFile`,
`rightFile`, `unspecified`.

`ends` and `middles` name positions in the set ("at the ends", "middles")
(Q14). `leftFile` and `rightFile` were added by the maintainer's note on Q2:
"Also include leftFile and rightFile (similar to your wall/music sides but
more explicit)". They are the left-hand line and the right-hand line of the
set as the caller sees it, facing down the hall (the maintainer's answer,
§9.1). They name positions, not roles, so storage stays role-neutral.

`unspecified` is a valid value of both `who` and `whom` (§5.2).

For a single named dancer: `onesRole1`, `onesRole2`, `twosRole1`,
`twosRole2`, `threesRole1`, `threesRole2`, `foursRole1`, `foursRole2`. The
contra taxonomy added the third and fourth couples' dancers in v39.

`firstCorners`/`secondCorners` are treated as **lasting relationships**
established at the start of the dance. `firstDiagonals`/`secondDiagonals`
describe **whoever is currently** on that diagonal, which changes as dancers
move. Some communities use "corner" and "diagonal" interchangeably, but the
two stay distinct here (Q2).

Phrases that depend on the previous figure stay as source text (Q14):
"couple below", "others", "opposite-role neighbor" and "new partner". "Top
couple" is the existing `top`.

Single dancers are named in three-couple dances as well as duple ones
("[Lark 1]", "[Robin 2]"). Tokens stop at the fourth couple for now (Q14).

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
movement implied don't take one: `set`, `honor`, `clap`, `balance`,
`balance_ring`, `arch`, `form_short_wave` and `form_long_wave`. A set
happens in place, or, in this ADR's reading, with a step forward in "set
forward" (§7.1). When
dancers set while falling back ("fall back setting"),
the set is a modifier on the travelling figure (§5.6), and that figure
carries the destination. `set` and `turn_alone` are the maintainer's
calls; the rest of the list is this ADR's reading, and reviewers may
disagree with individual entries.

When no destination is stated, none is stored, and that means the same as
`unspecified`.

`cast` also takes `top` and `bottom` of the set ("cast down to bottom"),
as contra's planned `cast` will. No other ECD movement takes them (§9.4).

**Display.** A stated destination is always shown (R2, R4), next to the
figure that carries it. Unless a movement's own display formula places it,
it is added at the end of that figure's own text: ", to {destination}". In
a sequence, that is the end of the step, not of the whole line, so "partners
cross to partner's place and fall back" reads "partners cross, to partner's
place, and fall back", never "... fall back, to partner's place".
`place` reads "back to place". A movement may
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
| `all proper` | Everyone ends on their proper side | "ending proper" |
| `top`, `bottom` | The top or bottom of the set; `cast` only (§9.4) | "to the bottom" |

- **Numbered places depend on the formation.** The editor offers only the
  places a formation has: two in a duple minor, three in a triple minor or
  three-couple longways set, four to six in four- to six-couple longways
  sets (§12, F2). Circle
  and square sets offer none for now, until testers show which numbering
  callers use. That is this ADR's call (§9.1, point 2). Sixth is
  the limit for now. Longer sets may extend it.
- **"Back to" is display.** `place` is one value, whichever words the
  source used for it.
- **The list may grow.** It ships as it is, and values are added as
  testers find gaps (Q3). Adding a value doesn't break stored dances.

## 7. The figure registry

Each movement below has parameters and a draft display, and was accepted on
19 November 2026 with the changes that the answers in §9 made, and updated
when the points left open were answered (§9.1). Notes say which answer
settled a point the draft had put to reviewers.
Display wording can still change through the dialect system (R4) without a
change to the stored form. Movements in which dancers travel also accept
`destination` (§6.4).

"Evidence" figures in the notes count captions in the 15 complete
transcriptions (§3). Each count is of captions, not of performances.

### 7.1 Setting, honouring and small gestures

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `set` | `who`, `whom`, `where`, `direction` | `{who} set [{direction}] [{where}] [to {whom}]` | `direction` is left/right, rendered only when not right. `whom` is used when dancers set to someone other than each other ("set to partner"). `where` is the line the dancers face along, or `forward`. Evidence: 13 captions in 7 dances. Only *The Shrewsbury Lasses* states a direction ("set right and honor, set left and honor to [Robin 2]"), and it names a single dancer as `whom`. A set takes no `destination` (§6.4). Setting while falling back ("fall back setting") is a `modifier` whose core is the travelling figure (§5.6). "Set forward" is `where = forward`: in the maintainer's words, "kind of the opposite of "fall back setting", but forward instead of backward" (§9.1). Making it a value of `set` is this ADR's call, and departs from the analogy, which points to a `modifier` like "fall back setting" with a forward movement as its core. The reason: `fall_back` has values of its own to record (`whom`, `distance`), while the step forward in "set forward" has none, so a modifier would add a figure that states nothing. |
| `honor` | `who`, `whom` | `{who} step and honor {whom}` | "Honour"/"Honor" is a display dialect, not two entries. |
| `clap` | none | `clap` | |
| `set_and_link` | none | `set and link` | One named movement, distinct from a bare `set` (§5.4). Everyone sets and everyone links: in the maintainer's words, "it's not a matter of who sets and who links though - everyone does both" (Q9), and "Everyone does it at once" (§9.1). So it takes no `who`, and no `tandem` flag either: in the maintainer's words, "You don't need an in-tandem flag, everyone does the thing all the time. If that changes, we'll make the update." Recording no facing is this ADR's proposal. |

### 7.2 Turns

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `turn_single` | `who`, `shoulder`, `destination` | `{who} turn single [{shoulder}] [{to \| back to} {destination}]`; "cloverleaf turn single" when `shoulder = cloverleaf` | Renders "back to" when `destination = place`, otherwise "to". Evidence: 13 captions in 7 dances. 5 state a side, always as "turn single left/right", never as a shoulder. 2 state a destination. The side stays a `shoulder` parameter (Q13c, the maintainer's answer), so "turn single left" is stored as `shoulder = left`. Its values are `right`, `left`, `cloverleaf` and `unspecified`: the maintainer added cloverleaf to that list rather than as a yes/no flag (§9.3). |
| `turn_alone` | `who`, `custom` | *as contra*: `{who} turn alone` | Identical to contra `turn_alone` apart from the optional `destination` ("turn alone back to place", §6.4). A separate movement from `turn_single`, not an alias of it. `custom` is contra's free-text note. |
| `hand_turn` | `who`, `hand`, `travel`, `endFacing` | `{who} {hand}-hand turn {travel}` | A turn of two dancers joined by one hand. `hand` is `right`, `left` or `unspecified`. Aliases, which can all be entered and searched: "right-hand turn", "turn by the right", "RH turn" (`hand=right`), and the same for the left. They fix the same values, so which of them a line shows is a dialect choice (§4). Two-hand and arm turns are separate movements (Q12). The parameters are modelled on contra `allemande`, but "allemande" is **not** an ECD alias. `endFacing` was added on acceptance (Q13d). Evidence: 6 captions in 3 dances, 2 with an extent ("right turn half"). |
| `two_hand_turn` | `who`, `travel`, `direction`, `endFacing` | `{who} two-hand turn [{direction}] {travel}` | Split from `hand_turn` on acceptance (Q12). `direction` is the rotation, worded clockwise or counter-clockwise; "anticlockwise" is a spelling the dialect can choose (Q13f). It is for sources such as Heywood's "two-hand turn anticlockwise". `endFacing` was added on acceptance (Q13d). Contra's `two_hand_turn` is a model, but the ECD movement is defined independently (§5.1). Evidence: 21 captions in 12 dances. 12 state an extent (9 half, 3 once and a half), 2 an ending facing ("and face down", "open to face new neighbors"), and none a rotation. |
| `arm_turn` | `who`, `hand`, `travel`, `endFacing` | `{who} arm {hand} [{travel}]` | Split from `hand_turn` on acceptance (Q12). `hand` is `right`, `left` or `unspecified`. Aliases: "arm right", "arm left". Q13d added `endFacing` to `hand_turn` while it still covered arm turns, so this ADR gives it to all three turns. Evidence: no arm-turn caption states an extent other than once around. |
| `shoulder_round` | `who`, `shoulder`, `travel` | *as contra* | Not a turn (§4). Alias: "gyre". "Gypsy" is **not** an alias. It is a discouraged term: the app recognizes it in imported or typed text, stores it as shoulder round, and flags it in the editor, but never offers it. Siding is a separate movement (§7.5). |
| `swing` | `who`, `endFacing` | *as contra* | Rare in ECD, included for coverage. Unlike contra's `swing`, it has no `prefix`: "balance and swing" is a sequence or two lines (§5.4). |
| `box_the_gnat` | `who`, `hand`, `balance` | *as contra*: `{who} box the gnat` | Identical to contra `box_the_gnat`, including its `balance` flag (§5.4), apart from the optional `destination` (§6.4). Occurs as a figure in its own right (*Honeysuckle Cottage*). |
| `swat_the_flea` | as `box_the_gnat`, with `hand` fixed to `left` | *as contra*: `{who} swat the flea` | Identical to contra apart from the optional `destination`. A separately named entry stored as `box_the_gnat` with the hand fixed, so the two names never merge. |
| `gate` | `who`, `whom`, `pair`, `direction`, `travel`, `endFacing` | *as contra* | Not a turn: one dancer pivots while the other travels around (§4). A "hand cast" is a gate, and can be found by that name (the maintainer's decision, §9.4). |
| `orbit` | `who`, `whom`, `direction`, `travel` | `{who} orbit {direction} {travel} [around {whom}]` | Evidence: 3 captions in *The Shrewsbury Lasses* ("orbit outside, same direction, ending improper"). "Ending improper" is `destination = allImproper` (§6.4). |
| `mad_robin` | `who`, `whom`, `travel`, `direction` | *as contra* | |

### 7.3 Rings, stars and balances

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `balance` | `who`, `where`, `hand` | *as contra* | Captions include "partner right hand balance" and "balance forward and back". |
| `balance_ring` | none | `balance the ring` | |
| `petronella` | `who`, `places`, `direction` | `{who} petronella [{places}] [to the {direction}]` | Added from a caller's notes (§9.3): "Balance the ring, petronella", "petronella one place to the right". `direction` is `left` or `right`. The parameters are this ADR's. |
| `circle` | `who`, `direction`, `places`, `singleFile`, `step` | *as contra*; with `step`, the step word replaces "circle" ("slip left 3 places"); with `who`, prefixed "{who}, ..." | `who` is offered only outside duple minor ("2s and 3s circle left"). Evidence: 10 captions in 7 dances. 6 give the extent as "half" or "half way", not a number of places. One states a side ("circle six left"). Single-file circles are called clockwise/counter-clockwise. "Half" and "half way" are stored as `places`, derived from the size of the ring: half the number of dancers in it. The ring is normally set by the formation: two places in a duple minor (four dancers), three in a triple minor (six dancers). When `who` names only some of the couples, the ring is those couples: "1s+2s circle half" in a triple minor is two places. An unstated extent is `places = unspecified`. "Chase" ("chase single file CCW ¾") is a single-file circle, and a name it can be found by (§9.3). |
| `star` | `who`, `hand`, `places` | `[{who}, ] {hand} hands across [{places}]`; "and back by the {hand}" when it is the last step of a sequence and has `destination = place` | ECD stars are hands across, so the star takes no grip (Q13e). In the maintainer's words: "Pretty sure ECD only uses hands-across, so don't specify a grip for now and we'll add one if we need to later." The display always says "hands across"; that wording is this ADR's. The extent is `places` only (Q13b): "once around" is stored as the number of places in the ring, worked out as for `circle`. An unstated extent is `places = unspecified`. Evidence: all 3 transcribed stars say "hands across", and one gives the extent as "once around". |
| `form_short_wave` | `axis`, `balance`, `center`, `centerHand`, `sides` | *as contra* | `balance` is a yes/no flag ("wave and balance"). |
| `form_long_wave` | `who`, `whom`, `whomHand`, `balance` | *as contra* | Long and short waves follow contra (Q10d). Tidal waves stay out of scope (§10). |

### 7.4 Heys, chains and rights-and-lefts

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `circular_hey` | `who`, `whom`, `slow`, `changes`, `where`, `shoulder` | `[{who} dance] {changes} [slow] changes of a circular hey, {whom} pass {shoulder} {where}` | Alias: "square hey". Passes by shoulders rather than hands. Evidence: 5 captions in 4 dances, all stating `changes` and whom to start with. One is captioned "(no hands)", which suggests hands are what separate it from rights and lefts. |
| `rights_and_lefts` | `who`, `whom`, `slow`, `changes`, `where`, `hand` | `[{who} dance] {changes} [slow] changes of rights and lefts, {whom} pull by {hand} {where} to start` | Not contra's "right and left through". Closer to a contra square through without a balance. Evidence: 9 captions in 6 dances. 8 state `changes`, several name the starting partner or neighbor, and none states a hand. |
| `chain` | `who`, `hand`, `where`, `open` | `{who} {hand}-hand [open] chain [{where}]` | Always shows the hand. `open` is a yes/no flag. |
| `figure_eight` | `who`, `whom`, `where`, `fraction`, `lead`, `double` | *as contra `figure_8`*; renders "double figure eight" when `double` is set | `double` means both couples move. Contra's `figure_8` gained the same flag in v39. `whom` names the couple danced around, which is ambiguous in non-duple dances. Evidence: "1s half figure 8 up through 2s", "Middles half figure 8 through nearest end". |
| `dolphin_hey` | `who`, `whom`, `shoulder`, `where`, `fraction`, `endFacing` | `{fraction} dolphin hey {where}: {who} pass {whom} {shoulder} shoulder to start, end facing {endFacing}` | |
| `hey_for_three` | `who`, `whom`, `shoulder`, `where`, `fraction` | `[{fraction}] hey for three [{where}], {who} pass {whom} {shoulder} shoulder to start` | Heys are separate movements by the number of dancers (Q4, the maintainer's answer). `who` starts the hey by passing `whom` first. `where` is the path (`along`, `across`, `diagonally`). Heys danced at the same time by different groups are a `meanwhile`, and parallel or end heys are stored that way, or as source text where that would lose a stated detail. Those storage rules are this ADR's. Contra's `hey_for_three` (v39) is a starting point, but the ECD movement is defined independently. Evidence: "1s left shoulder heys with end couples". |
| `hey_for_four` | as `hey_for_three` | `[{fraction}] hey for four [{where}], {who} pass {whom} {shoulder} shoulder to start` | As `hey_for_three`, for four dancers (Q4). |
| `hey_for_six` | as `hey_for_three` | `[{fraction}] hey for six [{where}], {who} pass {whom} {shoulder} shoulder to start` | As `hey_for_three`, for six dancers. Added from a caller's notes ("Hey for 6 halfway", §9.3). |
| `tandem_reel` | `who`, `whom`, `shoulder`, `where` | `{who} [{where}] tandem reel` | Alias: "Shetland reel". A reel is its own movement (Q4). The name and parameters are this ADR's. Evidence: "a Shetland (tandem) reel for three couples". |
| `mirror_hey` | `who`, `whom`, `fraction` | `[{fraction}] mirror hey, {who} splitting {whom} to start` | The maintainer's definition (Q10d): "Mirror heys have one couple splitting another to start, almost always along the set. We could probably go with always along the set for now and adjust later if we need to." So it has no `where`, and is always along the set. `who` is the couple that splits and `whom` the couple split. The parameters, and the alias "Grimstock hey", are this ADR's. |
| `grand_chain` | `who`, `whom`, `changes`, `hand` | `[{who} dance] {changes} changes of a grand chain[, {whom} pull by {hand} to start]` | A movement of its own, distinct from rights and lefts (Q5). *The American Husband* names grand chain, "[robins'] chain" and rights and lefts as distinct figures within one dance. Evidence: 2 captions in 2 dances, both counted in changes ("six changes of a grand chain", "three changes of a grand chain"), and one states a hand. |

### 7.5 Crossing, passing and travelling

| Movement | Parameters | Draft display | Notes |
| --- | --- | --- | --- |
| `cross` | `who`, `shoulder`, `where`, `endFacing` | `{who} cross [diagonally] passing {shoulder} shoulder [{where}] [and face {endFacing}]` | Roughly the union of contra *pass through* and *pass by*. `endFacing` was added on acceptance (Q13d). "Change places" is a separate movement (Q6). Evidence: 10 captions in 7 dances ("[Robins] cross", "Partners cross", "cross in middle left shoulder"). One gives an ending facing ("cross with partner and face right"). |
| `right_left_through` | `who`, `whom`, `where`, `withHands` | `[{who} dance a] right and left through [{where}], {with \| without} hands, {others} courtesy turning {whom}` | In a three-couple set, the choreography says which four dancers take part, usually as two couples, and `who` names them, such as `["ones","twos"]` (the maintainer's answer, §9.1). That `{others}` and `{whom}` come from those four dancers, never from the third couple, is this ADR's reading. |
| `fall_back` | `who`, `whom`, `where`, `distance` | `[{who}] fall back [with {whom}] [{where}] [a {distance}]` | An unstated `where` is `unspecified`, and is read as across, which is not shown. That wording is this ADR's: it keeps the reading of across from storing a value the source didn't state (§5.3). An unstated `who` is `unspecified` (§5.2). `whom` and `distance` were added on acceptance (Q13d). Evidence: 4 captions in 4 dances, all "fall back with neighbor", one "a double". "Fall back setting" is a `modifier`: `fall_back` as the core, `set` as the modifier (§6.4). |
| `forward_and_back` | `who`, `where`, `formation`, `distance`, `goBack` | `[{who}] [{formation}] {where} [a {distance}] [and back]` | Aliases: "up a double", "down a double" (`distance = double`), "forward and back", "lines forward and back". `where` is `up`, `down` or `forward`. `distance` is `double` or `single` (Q10a). When the source gives no distance, `double` is stored, and the editor suggests it when someone enters the line by hand. That is the maintainer's decision (§9.1), and the one exception to R2, so `distance` never stores `unspecified`. The stored distance is always shown, so "Lines of three forward and back" reads "Lines of three forward a double and back". That display rule is this ADR's. `goBack` records "and back": the return is the same movement reversed, with nothing of its own to state, so it is a flag rather than a second step (§5.4), and it replaces `destination = place` (§6.4). A bare "Forward" is `goBack = no`. `formation` names the grouping ("lines of three"). "Line" is not a movement: it is this `formation` (Q10c). A bend of the line is a `modifier` with `bend_line` (§7.5). Contra's nearest move, also `forward_and_back` since contra taxonomy v39, has `formation` and `goBack` (Appendix A). Evidence: 6 captions in 4 dances ("Up a double, and back", "Down a double, and back", "All up a double, and back", "Lines of three forward and back", "Line of four up a double and back, bending the line", "Forward"). |
| `back_to_back` | `who`, `shoulder`, `travel`, `where` | `{who} {shoulder}-shoulder back-to-back [{where}] {travel}` | Like contra dosido, but always named by shoulder, plus `where` (across/along). Evidence: 3 captions, none stating a shoulder. |
| `siding` | `who`, `shoulder`, `where`, `style` | `{who} {shoulder}-shoulder [{style}] siding [{where}]` | The parameters of `back_to_back` except `travel`, plus `style` (`straight` or `swirly`, Q13a). "Sharp siding" is an alias for `style = straight` and "Playford siding" for `style = swirly` (Q13a). That pairing was this ADR's understanding when it was put to the maintainer. An unstated style is `unspecified`. Captioned "Left Siding" (*Alexander's Birth Day*), and "Right/Left shoulder siding" in later passes of the *Double Jubilee* video. |
| `pass_through` | `who`, `where`, `shoulder` | `[{who}] pass through {shoulder} shoulders {where}` | |
| `promenade` | `who`, `where`, `direction`, `fraction`, `places`, `singleFile` | `{who} [single file] promenade {fraction \| N places} {direction} {where}` | `fraction` when in couples, `places` when single file. Evidence: "promenade half round the minor set", "promenade across the set back to original places". The second is `destination = originalPlaces` (§6.4). |
| `poussette` | `who`, `whom`, `fraction`, `direction`, `style`, `switchPush` | *as contra*, adding "first" after the pushers when `switchPush` is set | An unstated extent or rotation stays `unspecified`. Contra's half, clockwise is not assumed (§5.3, Q8). `who` names the dancers who push, or push first. `switchPush` is a yes/no flag: the pushers change partway through, as in a source's "... push first" (Q8). The flag's name is this ADR's. Storage is role-neutral, and gendered role terms are never shown (§4, §9.1). Evidence: 3 captions in 2 dances, all half, all naming who pushes, none stating a rotation. Heywood's *The Parson's Cap* is the one source we know that states both extent and rotation (half, counter-clockwise). `style` is `push` or `draw` ("[robins] draw partners halfway"), added from a caller's notes (§9.3). `who` names the dancers who push or draw, and an unstated style reads as push, which is what Q8 has `who` name. |
| `arch` | `who` | `{who} arch` | "Arch and dive through" is not defined. |
| `rollaway` | `who`, `whom`, `where`, `halfSashay` | `{who} roll away {whom} {where} [with a half sashay]` | Contra's ID is `roll_away`. `halfSashay` is a yes/no *style*, not "half a rollaway". |
| `change_places` | `who`, `whom`, `hand`, `where` | `{who} change places [with {whom}] [{hand}]` | A movement of its own, distinct from `cross` (Q6). `hand` is `right`, `left`, `none` ("without hands") or `unspecified`. A link danced on its own is a `modifier` with `change_places` as the core and `turn_single` as the modifier (§5.4). Evidence: "change" is a standalone figure in 4 captions in 3 dances ("Change with partner (all home)", "[Robin 1]+[Lark 2] change", "[Larks] change"). None of those dances also uses "cross". |
| `pull_by` | `who`, `whom`, `hand`, `where` | `{who} [{hand} hand] pull by [{whom}] [{where}]` | Added from a caller's notes (§9.3): "Partner R hand pull by" occurs 10 times. Contra's `pull_by` is a model, but the ECD movement is defined independently (§5.1). The parameters are this ADR's. |
| `contra_corners` | `who` | `{who} contra corners` | Its own movement, by the maintainer's answer (§9.3), rather than a titled container of the turns it is made of. `who` names the dancers who turn their corners, usually the 1s. The parameters are this ADR's. Evidence: 3 uses in a caller's notes ("Contra corners: 1s R hand, turn first corners L hand"). |
| `lead` | `who`, `where`, `whom`, `destination` | `{who} lead {where} [through {whom}] [to {destination}]` | Defined on acceptance (Q7). `where` covers "up", "down", "out", "to the middle" and "back". `whom` is the route ("lead through 2s"). Evidence (counted together with cast, because the two often share a caption): 16 captions in 11 dances. They consistently state who, where and a destination ("to progressed place", "home", "to 2nd place", "to the ends of a line of four"). |
| `cast` | `who`, `direction`, `places`, `whom`, `destination` | `{who} cast {back \| back {direction} \| {direction}} [{places}] [around {whom}] [to {destination}]` | Defined on acceptance (Q7), and given the parameters of contra's planned `cast` (#770) by the maintainer's decision of 19 November 2026 (§9.4). `direction` is `left`, `right`, `up`, `down` or `unspecified`. `left` and `right` are the shoulder the dancer turns over, not a side of the set: a cast clockwise is over the right shoulder, counterclockwise over the left. An unstated direction reads "cast back"; `left` and `right` read "cast back left" and "cast back right"; `up` and `down` read "cast up" and "cast down". `places` counts places moved ("cast down one place" is `down` with `places = 1`). "Cast off" is `down` with `places = 1` unless a number is stated, and "cast off" stays a name it can be found by. "Cast around 2s" is `whom`. `destination` also takes `top` and `bottom` ("cast down to bottom"), which no other ECD movement takes. "Long corners cast" is `who = longCorners`. A cast while another group leads is a `meanwhile` only when the source says so with "as" or "while". Actions joined only by a comma are separate figures in order (§5.6, Q7). Evidence: the same captions as `lead`. One couple casting while another leads occurs in 9 captions in 7 dances: five join the two with "as", four with a comma. |
| `galop` | `who`, `where`, `goBack` | `{who} galop {where} [and back]` | A movement, not a travelling style (Q10b, the maintainer's answer). The parameters are this ADR's. |
| `chevron` | `who`, `shoulder`, `whom`, `castShoulder` | `chevron: {who} cross passing {shoulder} shoulder and back into {whom}'s places, as {whom} cast over the {castShoulder} shoulder into {who}'s places` | The maintainer's definition (Q10d), from FODA2 in the Compendium Analect archive: "One pair of dancers crosses passing by a specified shoulder, then backs up into the other pair's place while that pair casts over their left or right shoulder into the crossing pair's place." `who` is the crossing pair, `whom` the casting pair, and `castShoulder` the casting pair's shoulder. The parameter names are this ADR's. "Pothooks" is an alias. The draft wrote "Chevron/Pothooks", and the maintainer's answer was that it is "probably" another name for chevron (§9.1), so it can be split out if testers show otherwise. |
| `bend_line` | `who` | `bending the line` | The modifier in a `modifier` container, as in "up a double and back, *bending the line*" (Q10c). It is not used as a line on its own. |

### 7.6 Movements that were open

The draft left nine movements open. Acceptance settled them all (§9):

- `lead`, `cast`, `change_places`, `galop` and `bend_line` are in §7.5;
- `grand_chain` is in §7.4, and `hey` became `hey_for_three`,
  `hey_for_four` and `tandem_reel` there, beside the new `mirror_hey` (Q4,
  Q10d);
- `set_and_link` is in §7.1;
- `line` is not a movement. It is the `formation` of `forward_and_back`
  (Q10c).

`chevron` (§7.5) was added on acceptance (Q10d).

## 8. Worked examples

These encodings illustrate the rules, updated for the accepted grammar.
They were written for this proposal and have not been reviewed as
transcriptions. Please correct them freely.
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
   [5-8]  two_hand_turn  who=["firstCorners"]  direction=unspecified  travel=unspecified
B2 [1-8]  sequence
     [1-4]  star  who=["unspecified"]  hand=right  places=unspecified
     [5-8]  star  who=["unspecified"]  hand=left   places=unspecified  destination=place
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
  began ("and back"), which §5.4 requires. B2 is one 8-bar phrase. The
  source splits the sentence across its two 4-bar halves with an ellipsis,
  and gives each half its bars, so each star keeps its 4 bars. A sequence can hold a single span instead (§5.5),
  but here that would lose bars the source states (R2).
- **"And back" is kept.** The second star carries `destination = place`:
  dancers end where the line began, which is where the first star started
  (§6.4). The display turns it back into "and back by the left". Stating the
  return doesn't copy the first star's places, which stay `unspecified`. Search still finds both stars, alone or as "star right then
  star left".
- **Unspecified values.** The source gives no side for the set, shoulder for
  the turn single, or rotation or amount for the two-hand turn, so all are
  `unspecified`.
- **Two-hand turn.** It is a `two_hand_turn` (§7.2, Q12).
- **No subject on the stars.** The source names no dancers, so `who` is
  `["unspecified"]`, and the display shows no subject (§5.2).
- **Set forward** is a `set` with `where = forward` (§7.1).
- **Lead and cast.** B1 of this dance ("1s lead down, wheel around, cross up
  and cast down, **as** 2s lead up") uses `lead` and `cast` (§7.5).
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
With neighbor, half poussette, [robins] push
```

```text
poussette  who=["role2s"]  whom=neighbors  fraction=half  direction=unspecified
```

"[Robins] push" names the second role, so it becomes `who = role2s` in
role-neutral storage. It displays as "robins", "follows", or a positional
term according to the caller's chosen dialect. The rotation is not stated,
so it is `unspecified`.

### 8.4 *Midwinter Maggot* (Gary Roodman, 2012), B bars 1–8

```text
(1-2) Single file circle clockwise half
(3-4) Turn single left
(5-6) Single file circle counter-clockwise half (all home)
(7-8) Turn single right
```

```text
[1-2]  circle       who=["unspecified"]  singleFile=true  direction=clockwise         places=2
[3-4]  turn_single  who=["unspecified"]  shoulder=left
[5-6]  circle       who=["unspecified"]  singleFile=true  direction=counterclockwise  places=2  destination=originalPlaces
[7-8]  turn_single  who=["unspecified"]  shoulder=right
```

Points to notice:

- **`circle` extent.** "Half" becomes `places=2`. *Midwinter Maggot* is a
  duple minor, so the ring has four dancers, and half of it is two places
  (§7.3).
- **"All home"** is `destination = originalPlaces`: where the dancers stood
  at the start of this time through (§6.4). It is shown at the end of the
  line (", to original places"), so the circle's display doesn't drop it.
- **Four lines.** The source gives each action its own bars, so they stay
  adjacent lines rather than a sequence (§5.4).
- **`turn_single` side.** "Turn single left" is stored as `shoulder=left`,
  though the source says "left", not "left shoulder" (Q13c).
- **`who`.** No line names its dancers, so each stores `["unspecified"]`
  (§5.2).

## 9. Answers to the open questions

The draft put sixteen questions to reviewers. On 19 November 2026 the
maintainer answered all of them on a decision sheet, choosing among options
that this ADR's author had drafted, each with a recommendation. The answer
to each question is recorded below. Where the maintainer chose something
other than the recommendation, it says so. The maintainer's notes are quoted
as written, except where a paraphrase is marked. Outside reviewers can still challenge any answer after testing
the implementation (§11).

**Q1. Who dances, when the source doesn't say?** On acceptance the
maintainer chose `["everyone"]`, not `["unspecified"]`, which was the
recommendation. Afterwards the maintainer reversed that answer, to keep R2
without an exception for `who` (§9.1, point 5): an unstated `who` is stored
as `["unspecified"]`, and the editor only suggests `everyone` (§5.2).
A follow-up (Q1b) settled that `everyone` can't be combined with another
selector: the editor refuses it, and an importer keeps such a line as
source text.

**Q2. Positional versus role calling.** Storage stays role-neutral, with
`role1` and `role2`. Positional wording comes later through the dialect
(§10). Corners (a lasting relationship) and diagonals (whoever is there now)
stay distinct. The maintainer's note added two selectors: "Also include
leftFile and rightFile (similar to your wall/music sides but more
explicit)". What they name was answered later (§6.2, §9.1).

**Q3. Stated destinations and ending states.** This was answered in the 18
November revision. The §6.4 list ships as it is, and values are added as
testers find gaps.

**Q4. Heys and reels.** Heys are separate movements, not one `hey` with a
dancer count: `hey_for_three`, `hey_for_four` and `tandem_reel` (§7.4). The
recommendation was one movement. The parameters of each, and how heys at the
same time are stored, are this ADR's.

**Q5. Grand chain, chain and rights and lefts.** `grand_chain` is a movement
of its own, distinct from `rights_and_lefts` (§7.4).

**Q6. Cross versus change places.** `change_places` is a movement of its
own, distinct from `cross` (§7.5).

**Q7. Lead and cast.** Both are defined now, with the parameters the
recommendation listed (§7.5). Two actions joined only by a comma are two
figures in order (§5.6).

**Q8. Poussette.** An unstated extent and rotation stay `unspecified`. `who`
names the dancers who push, and a flag records that the pushers change
partway through. This ADR names it `switchPush` (§7.5). The maintainer's
note, in paraphrase: gendered role words are not used. A later answer
extended that to every display choice (§9.1, point 7).

**Q9. Set and link.** "Other", with the note: "Set and link is an everyone
figure, maybe it cares about which way you're facing? It's not a matter of
who sets and who links though - everyone does both." Later answers removed
its `who` and the `tandem` flag this ADR had given it (§9.1, point 4).
Recording no facing is this ADR's proposal.

**Q10. Other open movements.**

- *Forward and back:* `distance` was `double`, `single` or `unspecified`.
  The note: "But double is the default, idk if I've ever seen "up a single"
  but that doesn't mean it's not something that exists." A later answer
  settled that a double is stored when the source gives no distance, and
  suggested in the editor (§9.1, point 3).
- *Galop* is a movement, not a travelling style (§7.5). The recommendation
  was a style.
- *Line* is the `formation` parameter only. *Bend the line* is a movement
  used as a modifier (§7.5).
- *Waves, chevrons and mirror heys* are defined now, not deferred, which was
  the recommendation. The note:

  > chevron was defined in FODA2, the archive just merged to Analect. One
  > pair of dancers crosses passing by a specified shoulder, then backs up
  > into the other pair's place while that pair casts over their left or
  > right shoulder into the crossing pair's place.
  >
  > Mirror heys have one couple splitting another to start, almost always
  > along the set. We could probably go with always along the set for now
  > and adjust later if we need to.
  >
  > I really have no idea what a tidal wave is, but long and short waves you
  > can infer from contra.

  So `chevron` and `mirror_hey` are defined (§7.4, §7.5), and long and short
  waves follow contra (§7.3). Keeping tidal waves out of scope (§10) is this
  ADR's reading of the note. The draft wrote "Chevron/Pothooks". Pothooks
  is recorded as an alias of chevron (§9.1, point 8).
- *Single-file promenade and single-file circle* stay distinct.

**Q11. Aliases that must not merge.** These stay distinct until testers
show that two are the same: Jersey and Nevada twirl, Gay Gordons and
Varsouvienne hold, box circulate, "matchboxes", and chassé, slide, sashay and
slice. Box the gnat and swat the flea were already separate (§7.2). The
draft also asked what Heywood's "Back to back for four" means. That was not
on the decision sheet. Asked later, the maintainer didn't know either, so it
is not supported (§9.1, point 9; §10).

**Q12. What's missing?** Hand, two-hand and arm turns are split back into
three movements: `hand_turn`, `two_hand_turn` and `arm_turn` (§4, §7.2). The
recommendation was to keep the merge. No missing figures were named.

**Q13. Specific value questions.**

- *Siding:* `straight` and `swirly`, with "Sharp siding" and "Playford
  siding" as aliases (§7.5).
- *Star extent:* `places` only, with no turn amount (§7.3). The
  recommendation was to add one.
- *Turn single side:* `shoulder`, not `direction` (§7.2). The
  recommendation was `direction`.
- *New parameters:* `endFacing` on `hand_turn` and `cross`, and `whom` and
  `distance` on `fall_back` (§7.2, §7.5). When the question was asked,
  `hand_turn` still covered all three turns, so this ADR gives `endFacing`
  to `two_hand_turn` and `arm_turn` too.
- *Star grip:* "Other", with the note: "Pretty sure ECD only uses
  hands-across, so don't specify a grip for now and we'll add one if we
  need to later." The star has no grip parameter (§7.3).
- *Two-hand turn direction:* clockwise and counter-clockwise, with
  "anticlockwise" as a dialect spelling (§7.2).

**Q14. Selectors.** `ends` and `middles` are added. Phrases that depend on
the previous figure stay as source text (§6.2). The maintainer's note, in
paraphrase: such relationships are called same-role or opposite-role, and
this document should use only those terms. Single-dancer tokens stop at the
fourth couple for now.

**Q15. Extents defined by a goal.** The movement is structured, and the
wording is kept as a note on it (R2).

**Q16. Half bars.** Half bars are allowed only where half a bar is a whole
number of beats. The editor refuses them in triple time, and a note can
carry finer timing (§5.5).

### 9.1 Points answered after acceptance

Acceptance left these points open. They came out of the answers, or were
never put as questions. The maintainer answered them all on 19 November
2026, and each answer below quotes the maintainer's words. Where this
document still had to make a call to apply an answer, it says so.

1. **Dialects across forms.** The answer to S1 (§12) asked for "separate
   dialects per-form", while the answer to S3 chose one dialect with role
   terms overridden per form. Answer: "Each dance form gets the full
   dialect experience that contra has today." Each form has its own
   dialect, with the spelling, role and dancer terms, per-movement
   wordings, discouraged terms and presets that
   [dialect.md](../design/dialect.md) describes for contra. This
   document reads that as replacing the design chosen in S3.
2. **Formations.** Do the proper/improper checkbox and the new shapes from
   F2 (§12) change contra's shapes too, or only how ECD dances are stored?
   Answer: "ECD only, ECD does not have becket or Sicilian circles."
   Contra's shapes, such as `dupleImproper` and `becketCw`, don't change,
   and the ECD shapes have no Becket or Sicilian circle. A later answer
   added a Sicilian circle to ECD (§9.2, point 5). The point also
   noted that the numbered places the editor offers (§6.4) were not defined
   for circle and square sets. The answer doesn't address that, so this
   document offers none for those sets until testers show a need.
3. **"Double is the default"** (Q10a). Is "a double" stored when the source
   doesn't say, or only suggested when someone enters a dance by hand?
   Answer: "Double should be used when unspecified and suggested when
   entering one." Asked to confirm that "used" means stored, as R2's one
   exception, the maintainer chose "Yes, store a double". So
   `forward_and_back` stores `distance = double` when the source gives
   none, and the editor suggests it (§7.5). It is the one exception to R2
   and §5.3.
4. **Set and link** (Q9). Does it take `who`, a `tandem` flag, or which way
   dancers face? Answer: "Everyone does it at once." It takes no `who`
   (§7.1). A follow-up answer removed the `tandem` flag: "You don't need
   an in-tandem flag, everyone does the thing all the time. If that
   changes, we'll make the update." The answers don't address facing, and
   this document records none.
5. **R2 and Q1.** R2 says that what the source leaves out is stored as
   `unspecified`, while the answer to Q1 stored an unstated `who` as
   `everyone`. Four options were put: reword R2 to name the exception;
   leave R2 with the exception as a separate sentence; keep R2 strict and
   reverse Q1; or reword R2 and also record when a source literally said
   "all". Answer: "C", the option worded "Keep R2 strict and reverse your
   earlier answer: store "unspecified" and only suggest "everyone."" An
   unstated `who` is stored as `["unspecified"]`, and the editor only
   suggests `everyone` (§5.2, §5.3). "All set and turn single" and "set and
   turn single" are now stored differently.
6. **`leftFile` and `rightFile`** (Q2). What does each name, and left and
   right as seen facing which way? Answer: "the left-hand line and the
   right-hand line from the perspective of the caller facing down the
   hall" (§6.2).
7. **Gendered role terms** (Q8). Does the Q8 note also rule out gendered
   role terms as a choice for display? Answer: "Don't. show. gendered.
   role. terms. They're discouraged, explicitly." They are never shown: not
   in stored data, not as a dialect's role terms or as a choice offered,
   and not in this document (§3, §4). A custom dialect no longer takes
   gendered role terms, for contra or ECD, and one saved earlier is
   repaired on read ([dialect.md](../design/dialect.md)). Still open: with
   **Auto-convert all discouraged terms** turned off, a discouraged term in
   free text is shown as typed.
8. **Pothooks** (Q10d). Is it another name for chevron, or a separate
   figure? Answer: "yeah probably". It is an alias of `chevron` (§7.5),
   and can be split out if testers show it is a different figure.
9. **Heywood's "Back to back for four"** (the draft's Q11). What does it
   mean? Answer: "no clue". It is not supported, and a line that uses it
   stays source text (§10).
10. **The new-dance form setting** (S2). Is it kept per device or synced?
    Answer: "sync". It syncs across the caller's devices (§12). The
    glossary still opens on the form it gives (S6).
11. **Two review points the draft marked but never asked as questions.**
    - Is "set forward" a `where` of `set`, or a different figure (§7.1)?
      Answer: "kind of the opposite of "fall back setting", but forward
      instead of backward". This document records it as `set` with
      `where = forward`. The answer's analogy points to a `modifier` like
      "fall back setting", with a forward movement as its core; §7.1 gives
      this document's reason for departing from it.
    - In `right_left_through`, "the others" in a three-couple selection is
      not always a single pair (§7.5). Answer: "The choreography should
      specify which four dancers participate, usually in terms of which two
      couples participte [sic]". `who` names those four dancers, usually as two
      couples.

### 9.2 Points answered during implementation

The maintainer answered these on 19 November 2026, while the dance record
was being built (workstream W3). Each was put with options and a
recommendation; the answer is quoted.

1. **How ECD shapes are stored.** (a) As new values of the formation shape
   the app already stores, with a list per form, `tripleMinor` shared with
   contra; or (b) a separate ECD shape field beside a shape older versions
   understand. Answer: "1a". The cost accepted with (a): a device on an
   older version skips a synced dance with a new shape until it is updated.
2. **The proper/improper checkbox.** Stored as a yes/no "improper" on the
   formation, with "Other, with a description" kept in the ECD list.
   Answer: "agreed, yes/no flag where proper is the default".
3. **ECD dances already stored with contra shapes.** Not rewritten when the
   app updates; the opt-in migration of F5 also maps their shapes. Answer:
   "yeah use the tag-driven migration".
4. **Meter and key.** Free text, empty when not given (F3). The maintainer
   added: "Meter and key need to be searchable."
5. **Sicilian circle in ECD.** One caller's dances include "Sicilian circle
   (Hands 4 in a circle) or LDM". Options: (a) offer Sicilian circle in the
   ECD list; (b) keep it out. Answer: "a". This reverses the "no Sicilian
   circle" part of §9.1, point 2; ECD still has no Becket.
6. **Sets not called longways.** The same caller writes "2 couple set",
   "3 couple set" and "4 couple set". Options: (a) add a two-couple set
   shape, and treat three- and four-couple sets as three- and four-couple
   longways, with the description for anything unusual; (b) no new shape;
   (c) separate three- and four-couple set shapes. Answer: "a".
7. **Original and interpreted credits.** Many ECD dances credit an original
   source and year and a later interpreter, for example "Walsh, 1731, Pat
   Shaw version". Answer: "Many ECD dances have a primary author and
   publication year AND a secondary author who interpreted the dance from
   the original publication in a later year. We'll want to make it easy to
   enter all four values for ECD." The follow-up put this proposal: keep
   the author list and the Composed date for the original author and
   publication year; add "Interpreted by", an ordered list from the same
   people list as authors, and "Interpreted in", a year or a fuller date
   like Composed; store both for every form and show them up front for ECD;
   ship them as a second change inside the same unreleased database
   version. Answer: "Go with your recommendation." They are stored as
   `Dance.interpreterIds` and `Dance.interpretedOn` (storage.md, v42). The
   dance editor shows them, with the Composed date, beside the authors for
   an English dance, and in More details for other forms.

### 9.3 Figures from a caller's notes

On 19 November 2026 the registry was checked against one caller's own
notation for her dances, as a data point rather than a template. Eight
points about figures it uses that this ADR didn't cover were put to the
maintainer, each with options and a recommendation. The answers, in the
maintainer's words where they say more than the option chosen:

1. **Pull by** (10 uses). "Add it": `pull_by` is a movement (§7.5).
2. **Cloverleaf turn single** (about 8 uses). "Add cloverleaf as an option
   in the list for turn single, not a yes/no flag": `cloverleaf` is a value
   of `turn_single`'s side, beside `right` and `left` (§7.2). Reading "the
   list" as the side's list is this ADR's, since it is the only list the
   movement has.
3. **Draw poussette** (about 6 uses). Chosen as recommended: push or draw is
   the poussette's `style`, and `who` names the dancers who push or draw
   (§7.5).
4. **Hey for six** (2 uses). As recommended: `hey_for_six` beside the heys
   for three and four (§7.4).
5. **Petronella** (4 uses). As recommended: `petronella` is a movement
   (§7.3).
6. **Contra corners** (3 uses). The maintainer chose its own movement over
   the recommendation, a titled container of the turns it is made of:
   `contra_corners` (§7.5).
7. **Chase** (4 uses). As recommended: a single-file `circle`, which can be
   found by the name "chase" (§7.3).
8. **Rarer figures**: wheel around, loop, side step, serpentine change,
   hole-in-the-wall cross and "meet". "a for now, but some may gain
   definitions in time": they stay source text (§10).

### 9.4 Cast, aligned with contra's

Contra is gaining its own `cast` (issue
[#770](https://github.com/ibanner56/CallersCompendium/issues/770), still
being built when this was written, 19 November 2026). The
maintainer decided that ECD's `cast` and contra's must share one parameter
shape from the start, so that re-reading a contra-imported English dance
(§12, F5) maps one to one. The decisions, with the maintainer's reasons:

1. **Parameters.** `cast` keeps `who`, `whom` and its 4 beats, drops
   `where` (off, up, down, around), and takes `direction` (`left`, `right`,
   `up`, `down`, `unspecified`), `places`, and `destination` (§7.5).
   `left` and `right` mean "the shoulder the dancer turns over, not a side
   of the set": "a cast clockwise is over the right shoulder and
   counterclockwise over the left". This replaces the earlier "`direction`
   is the side". "Cast around {whom}" is `whom`, which replaces `where =
   around`.
2. **Display.** The maintainer gave a rough template rather than an exact
   rule: `{who} cast {back | back {direction} | {direction}} [{places}
   place(s)] [around {whom}] [to {destination}]`. An unstated direction
   reads "cast back". A return to place then reads "to place" rather than
   §6.4's "back to place", so the line never says "back back"; that wording
   is this document's.
3. **Cast off** is `down` with `places = 1` unless a number is stated. The
   maintainer's reason: The Caller's Box glossary's "Cast off" entry
   describes "ones peel down the outside into second place", which is no
   different from "ones cast down 1 place". "Cast off" stays a name the
   movement can be found by. When a line says where the cast off ends ("cast
   off to the bottom"), no count is stored, since the count would then be
   more than the line says (R2); that reading is this document's.
4. **Top and bottom.** `destination` takes `top` and `bottom` as well as the
   §6.4 list, as contra's planned `cast` will: The Caller's Box writes "cast down to
   bottom" 104 times and "to top" 16 times. Giving them to `cast` alone,
   rather than to every movement's `destination`, is this document's call.
5. **Hand cast** is a `gate`. The maintainer's reason: The Caller's Box
   glossary calls a hand cast "a cast off figure done with hands… very
   similar to a gate", and its Gate entry says the reverse. It is a name
   `gate` can be found by, not a movement or alias of its own; that choice
   is this document's.

The taxonomy had not been released, so its version 1 was amended in place
([figure-taxonomy.md](../design/figure-taxonomy.md#ecd-taxonomy-versions)).

## 10. Out of scope

- **ECDDB import.** It stays the import target (R5), but is not part of the
  first implementation round (§12, D1).
- **Tracking dancer positions** (R9). The app won't work out where dancers
  are, compute a destination, or check that a dance works.
- **Specialized chain families.** Dixie, teacup, spin chain.
- **Specialized hey and reel families.** Interlocking, Morris-derived.
- **Wave topology.** Tidal wave and the ocean-wave/across-the-set
  distinction. Long and short waves follow contra (Q10d).
- **Footwork and gesture labels.** Jump/stamp, rigadoon, rant.
- **One-off named figures.** Tiroir, Yearn, Weathervane, Celtic knot,
  Lichfield hey, Four Winds, Serpentine (*Beach Spring*). These stay as
  source text, or as a titled container where their steps can be structured
  (§5.6). They are not movements.
- **Heywood's "Back to back for four".** Its meaning is unknown (§9.1,
  point 9), so a line that uses it stays source text.
- **Wheel around, loop, side step, serpentine change, hole-in-the-wall
  cross and "meet"**, for now (§9.3, point 8). Some may gain definitions
  later.
- **Mapping to positional calling** (Q2). `leftFile` and `rightFile` are
  stored, but how role terms map to positions waits for community input.

## 11. How to respond

Feedback is welcome at any time, and most will come from hands-on testing.
Partial answers help:

- Mark up a registry row: "keep", "rename to ...", "merge with ...", "split
  into ...", "needs parameter ...".
- Send counter-examples: dances whose instructions can't be expressed with
  these parameters, ideally with a link to an **English-style** source
  (ECDDB record, published book, or a video with clear teaching).
- Correct the worked examples in §8.
- Where ECDDB's own model decides something differently, please say so.
  The aim is to align with it (§2).

Where you know of style or homonym problems (the same title used by an
English dance and a contra or other dance), please mention them. That is the
error we are most likely to make without help.

## 12. Implementation decisions

The maintainer made these decisions on 19 November 2026, on the same
decision sheet as §9, about how the app stores and shows ECD dances. Some
draw on the requirements for squares in ADR-007, which is still a proposal,
so that both forms behave the same way. The goal they serve is the
maintainer's: the app supports ECD choreography and programming as fully as
it supports contra, and a caller can program a night that mixes the two, or
an all-English evening.

### 12.1 Stored data

- **F1. Value spelling.** Stored values are camelCase, as contra's are,
  with `full` rather than `whole` (§6.1).
- **F2. Formations.** New shape values are added. The maintainer's note:
  "Separate proper/improper as a new checkbox, shapes are duple minor,
  triple minor, three couple longways, four couple longways, five couple
  longways, six couple longways, circle, and square. Mixer toggle stays."
  The shape drives the numbered places the editor offers (§6.4). The
  checkbox and the new shapes are for ECD only, and contra's shapes don't
  change. ECD has no Becket circle (§9.1, point 2). Answers given while the
  record was built (§9.2) added a Sicilian circle and a two-couple set to
  the ECD list, stored the shapes as new values of the existing formation
  shape, and stored the checkbox as a yes/no "improper", proper by default.
- **F3. Meter and key.** A dance gains optional meter and key text fields,
  shown on the dance and the program sheet, and searchable. Phrase
  structure still records beats per bar (§5.5).
- **F4. Dances in several parts** use one phrase structure joined with `+`,
  with section labels derived as they are today. No part grouping is added.
- **F5. ECD dances already imported** with contra moves are left as they
  are, and still display through the contra taxonomy (§5.1). A migration
  that the caller runs for one dance or for all maps contra moves with a
  clear ECD meaning, re-reads custom lines with the ECD parser, and leaves
  anything else as it is.
- **F6. Shared parts.** The ECD work builds the two pieces squares also
  need: choosing the taxonomy from the dance's form instead of always using
  contra, and a dance-form selector in the glossary. Both are designed for
  any number of forms, and ADR-007 builds on them.

### 12.2 Screens and settings

- **S1. Showing figures by form.** "Other", with the note: "As specified in
  ADR-007, I want users to toggle forms in the glossary to only show the
  figures in that form, have separate dialects per-form, and only show
  figures in the new dance form based on what the form of the dance is.
  There's no reason you can't contextually determine which figures to show
  or not show in the app." So the glossary has a form selector that shows
  that form's figures, and the figure editor offers only the figures of the
  dance's own form. This ADR reads the note as meaning there is no "dance
  forms I call" setting. Each form has its own dialect, with everything a
  contra dialect has today (§9.1, point 1).
- **S2. A new dance's form** comes from a setting: "Make this a user
  setting with each dance form as an option along with "last used"". The
  recommendation was the last form used on the device, with no setting.
  The setting syncs across the caller's devices (§9.1, point 10).
- **S3. Role terms across forms.** The answer chose one dialect with role
  terms overridden per form. That conflicted with the S1 note, and a later
  answer gave each form its own dialect instead (§9.1, point 1). This
  ADR reads that as meaning a
  program that mixes forms shows each dance in its own form's dialect, with
  that form's role terms. How a program's own choice of dialect
  ([dialect.md](../design/dialect.md)) extends to several forms is left to
  the implementation.
- **S4. Difficulty levels** share one vocabulary across forms (ADR-005).
- **S5. Programs** have no form of their own. When a program mixes forms,
  each dance shows its form, and the dance picker can filter by form.
- **S6. The glossary's selected form.** Per device, as ADR-007 proposes,
  with the note: "The Glossary should contain all forms on all devices - if
  you just mean which one is selected by default, go with the form the user
  chooses for their new dance default." So every form is available on every
  device, and the glossary opens on the form the S2 setting gives.

### 12.3 Scope

- **D1. ECDDB import** is a later round, not part of the first
  implementation (§10). The recommendation was to survey ECDDB first and
  then build the importer in this round.

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
| `two_hand_turn` (a model for ECD `two_hand_turn`) | `who` (partners), `travel` (1) | `{who} two hand turn {travel}` |
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
automatically ECD defaults. §5.3 applies, except for the distance of
`forward_and_back` (§7.5): an ECD source that doesn't state a
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
