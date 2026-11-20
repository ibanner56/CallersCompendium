# ADR-007: Square dance canonical call grammar

- **Status**: Proposed (12 November 2026; reworked 20 November 2026 for
  traditional squares). For maintainer review before anything is
  implemented.
- **Roadmap item**: "ECD and Squares support" (Later milestones in
  [ROADMAP.md](../ROADMAP.md))
- **Deciders**: Maintainers

**What we're asking the reviewer for:** a decision on each principle in §5,
corrections to the registry in §7, and answers to the
[open questions](#10-open-questions).

In the template's terms: §2–§4 are the *context*, §5–§8 the proposed
*decision*, §5 the *rationale*, and §9–§11 the *consequences* and *revisit
triggers*. Once accepted, the square taxonomy follows the versioning process in
[figure-taxonomy.md](../design/figure-taxonomy.md) with a version of its own,
as the ECD one does (§9).

CALLERLAB timing figures in §2, §7 and Appendix A are reprinted with
permission of CALLERLAB (§4.2).

---

## Contents

1. [Summary](#1-summary)
2. [Background: traditional squares](#2-background-traditional-squares)
3. [Where the app stands today](#3-where-the-app-stands-today)
4. [Evidence and sources](#4-evidence-and-sources)
5. [Design principles](#5-design-principles)
6. [Shared vocabulary](#6-shared-vocabulary)
7. [The call registry](#7-the-call-registry)
8. [Dance structure, entry, glossary and import](#8-dance-structure-entry-glossary-and-import)
9. [Delivery phases](#9-delivery-phases)
10. [Open questions](#10-open-questions)
11. [Consequences and revisit triggers](#11-consequences-and-revisit-triggers)
12. [Learnings from the ECD implementation](#12-learnings-from-the-ecd-implementation)
13. [Appendix A: worked examples](#appendix-a-worked-examples)
14. [Appendix B: sources](#appendix-b-sources)

---

## 1. Summary

Caller's Compendium stores contra figures as structured data: a canonical
move plus named parameters. This ADR proposes the same for **traditional
square dances**, the phrased squares of the New England and contra
community, with a **separate taxonomy** that owns every call ID. A call such
as Allemande Left or Do-si-do is defined in the square taxonomy on its own
terms, even where contra has a figure with the same name. This follows the
approach ADR-006 takes for English Country Dance (accepted 19 November 2026).

### 1.1 Maintainer requirements

The maintainer set these requirements. They are inputs to the design, not
proposals. Each is quoted in the pull request that adds this ADR.

From the planning conversation, 12 November 2026:

- The square taxonomy is **fully independent** of the contra taxonomy, as
  ADR-006 proposed (and has since adopted) for ECD, even where figures share
  a name.
- Calls carry **beat counts**.
- Dance entry has a **toggle for free-form patter** that does not follow
  fixed phrasing.
- The glossary offers a **switcher between contra and squares** that can
  take ECD later, so it is not a two-way toggle.
- [Taminations](https://github.com/bradchristie/taminations-flutter) is a
  **reference only**. No code is ported or copied from it, so the project
  takes on no licensing or attribution obligation.

From the maintainer's review comments on the pull request, 16 November 2026:

- "Dialect settings will also need a switcher." Dialect settings now have
  a dance-form switcher that includes squares (§3).
- "[T]he glossary should be sorted/filterable by program, similar in
  intention to the browsing structure Taminations offers" (§8.3).
- "We should expect that some figures from Advanced and Challenge may be
  requested even if we don't pull in the full programs, to accommodate
  figures which appear in otherwise-simpler, choreographed country square
  dances" (§5.2, §7.3).

From 20 November 2026: **"We expect the people using Compendium to be
storing + calling traditional squares, not MWSD."** This replaces the first
draft's success criteria, which were the CALLERLAB Mainstream and Plus
programs with Advanced and Challenge as stretch goals. The first draft of
this ADR was built around CALLERLAB club calling (Modern Western Square
Dance, MWSD); this version is built around traditional squares (§2).

Also on 20 November 2026 the maintainer chose **"Option A"**: traditional
squares first, club calls as borrowed vocabulary, and a CALLERLAB program
kept only as a glossary label (§5.2). The maintainer added: "I imagine if
you look around online for sources of traditional squares choreography
you'll find that some of the Plus/Advanced/Challenge calls still show up in
trad squares or contra." §7.3 records that search.

### 1.2 The proposal in brief

Everything below is proposed by this ADR's author for the maintainer to
accept or change, except where §1.1 or §10 records the maintainer's
decision.

- **One taxonomy per dance form**, with square call IDs carrying an `sq_`
  prefix so they can never be mistaken for contra moves, including by older
  builds (§5.1; the maintainer accepted the prefix, Q5).
- **Traditional squares are the design center** (§5.2; the maintainer chose
  this as Option A, §1.1). The registry starts
  from the calls traditional squares actually use, and adds the club calls
  they borrow, including the few Plus and Advanced calls that traditional
  squares and contras were found to use (§7.3). CALLERLAB programs are kept
  only as a label in the glossary.
- **Beats are stored on every call.** Defaults follow traditional
  phrase-filling practice, and the check that matters is that each phrase
  adds up, which needs a new per-phrase check (§5.3).
- **Squares use the existing containers**, `meanwhile` above all, because
  traditional figures often have two groups dancing at once (§5.6).
- **A dance is a phrased figure, a break or free-form patter** (§8.1), with
  contra-style phrase labels, a repeat order, and who becomes the new
  partner.
- **Squares join the glossary's dance-form selector** that ADR-006 built
  (§8.3).

## 2. Background: traditional squares

The squares callers will store in the app are traditional ones: figures
written by contra and New England choreographers, danced to reels and jigs,
and printed beside contras. They differ from club (MWSD) square dancing in
ways that drive this design:

1. **A square is a fixed, phrased figure, repeated.** The figure is danced
   several times through, usually twice with the heads leading and twice
   with the sides, or four times with everyone active. Club calling is mostly
   improvised patter, with phrasing only in singing calls.
2. **Figures are labelled and timed like contras.** Sources print phrase
   labels (A1, A2, B1, B2, and C1, C2 for longer figures) and a beat count
   for each line. Most figures are 64 beats; some are 96.
3. **Timing fills the phrase.** A forward and back is "always a full eight
   beats in New England" (Parkes); CALLERLAB also gives 8, but 4 for lines
   close together. Where the two differ, the traditional count is usually
   longer: a ¾ circle of four is 8 (CALLERLAB 6), and a do-si-do or right
   and left through between facing couples is 8 (CALLERLAB 6). It can be
   shorter too: Lavender Moon dances a square through 2 in 4 (CALLERLAB 5).
4. **Most figures change partners**, and the source says who the new
   partner is: usually the corner.
5. **The vocabulary overlaps contra.** Heys, gypsies (shoulder rounds), pull
   bys, balances and single-file moves appear beside square terms. Club calls
   (zoom, box the gnat, square through, even allemande thar) are borrowed
   knowingly, sometimes with a note that they are club figures.
6. **Sources describe; callers call.** Books print descriptions of the
   figure with beat counts, not the words a caller says.

## 3. Where the app stands today

These facts were checked against the code on 12 November 2026 and rechecked
on 20 November 2026, after the ADR-006 (ECD) implementation, through #2302,
had landed. §12 lists what this ADR takes from that work and what it does
not.

- `DanceForm` already has a `square` value
  ([enums.dart](../../packages/compendium_core/lib/src/model/enums.dart)), and
  search can filter on it.
- The Caller's Companion importer maps a dance whose `Type` contains "square"
  to `DanceForm.square`. From a `.USR` file it also maps the "Square"
  formation family to `FormationShape.other` with detail "Square", and sets
  `mixer` from a square's `SubType` ("Mixer, H H S S"); the text export
  gives `other` with the raw text as detail and sets no `mixer`
  ([callers_companion_mapping.dart](../../packages/compendium_core/lib/src/imports/callers_companion_mapping.dart)).
  It parses the figure lines of these dances with the **contra** vocabulary
  (`parseFigureLinesFanOut`). So square dances imported so far hold contra
  moves (`swing`, `circle`, `promenade`, ...) or custom text. §8.4 deals
  with them.
- **ADR-006 built both shared parts squares need** (ADR-006 §12.1, F6).
  The first is the taxonomy registry.
  `TaxonomyRegistry`
  ([taxonomy_registry.dart](../../packages/compendium_core/lib/src/taxonomy/taxonomy_registry.dart))
  chooses the taxonomy from the dance's form: `forForm` lays a form's own
  taxonomy over contra's, `anyForm` resolves a stored ID of any form, and a
  stored ID's prefix (`danceFormMovePrefixes`, today only `ecd_`) names the
  form that defines it. The registry refuses a form whose move or alias IDs
  lack its prefix. Its comment says squares register the same way once this
  ADR is accepted. Until then a square dance uses contra's taxonomy.
  The dance editor offers only the dance form's own figures, and warns when
  a dance holds another form's figures.
- The second is the glossary's dance-form selector (#2278). It is a
  segmented control over every form that has a taxonomy of its own, shown
  when there is more than one, and it opens on the new-dance form (ADR-006
  S2, S6). Squares appear in it as soon as they register a taxonomy.
- `FormationShape.square` exists, added for ECD square sets (ADR-006 F2).
  But a square dance cannot choose it yet: `offeredFormationShapes` gives
  square dances contra's shapes
  ([formation.dart](../../packages/compendium_core/lib/src/model/formation.dart)).
  Caller's Companion squares still map to `other` with detail "Square".
- Each dance form has its own dialect library, square included, and the
  dialect settings switch between forms (storage keys
  `custom_dialects_square` and `active_dialect_ref_square`;
  [dialect.md](../design/dialect.md)). Gendered role terms are never shown:
  the maintainer's answer to ADR-006 §9.1 point 7 (recorded on 19 November
  2026) rules them out of stored data and dialects, and ADR-006 applies it
  to its own text. dialect.md records the same rule, dated 18 November.
- ECD dances imported before ECD had a taxonomy keep their contra moves, and
  a caller-run conversion maps their moves and formation to ECD ones
  (ADR-006 F5; #2273). §8.4 follows the same pattern for squares.
- ECD has its own taxonomy version (`ecdTaxonomyVersion`), with its own
  heading in [figure-taxonomy.md](../design/figure-taxonomy.md), rows in the
  version-history and version-bump gates under `tools/ci/`, and a one-time
  rebuild marker for dances that held `ecd_` IDs before they were known.
- 38 Dart files outside test directories under `packages/` and `app/` still
  refer to `contraTaxonomy` by name, 34 of them under a `lib/` directory.
  Some are contra-only by nature (the ContraDB and Caller's Box importers,
  the registry's base). Others serve any form and still name contra's
  taxonomy directly, among them the glossary's list of figures of your own,
  the custom-figure list and detail screens, the user-figure switch screen
  and draft, the compound-figure editor and its argument editors, the
  shorthand screens and the per-move defaults in Settings. So an `sq_`
  compound figure could not be written yet.
- `MoveDef` supports a beat default per move and a `ParamBeats` table that
  picks beats from **one** parameter's value.
- Figures of your own record a dance form (`UserFigureDefinition.form`,
  defaulting to `contra`), as do compound definitions. The glossary lists
  each under its own form, and the dance editor offers only those of the
  dance's form.
- Several editor choices are hard-wired to ECD (`DanceForm.ecd` comparisons in
  many places across app and core), among them the improper checkbox, meter,
  key and interpreter fields up front, named phrases, sequence spans, and the
  dialect editor's sample figures.
- The new-dance figure template (ContraDB's eight `stand_still` lines) and the
  fallback sides of a new `meanwhile` are contra's `stand_still`, which counts
  as another form's figure in an ECD dance, and will in a square dance once
  squares have a taxonomy
  ([display_defaults.dart](../../app/lib/src/data/display_defaults.dart)).
- Dialect move wordings are keyed by move ID (`kMoveWordingBranchKeys` in
  [dialect.dart](../../packages/compendium_core/lib/src/dialect/dialect.dart)
  has a `promenade` entry).
- Structural containers (`meanwhile`, `modifier`, `sequence`) are a fixed
  set (`containerMoves` in
  [figure.dart](../../packages/compendium_core/lib/src/model/figure.dart)),
  with a maximum depth of two (`kMaxContainerDepth`).
- Phrase labels are derived from `phraseStructure`: the empty default is
  four 16-beat phrases labelled A1, A2, B1, B2, and `6*8*2` gives six
  phrases labelled A1 to C2
  ([phrase_structure.dart](../../packages/compendium_core/lib/src/model/phrase_structure.dart)).
  Three ECD-only additions sit beside it: counting in bars, named phrases
  (`A:2*4*2 + B:1*8*2`, #2298), and a `sequence` that carries one count with
  untimed steps (#2269, #2296).
- Validation checks the whole dance against its phrase structure
  (`phrase_overflow`, `phrase_underflow`), and warns when a `sequence` is
  longer than the longest phrase (`sequence_exceeds_phrase`). There is no
  per-phrase check, for ECD either. The editor adds `other_form_figures`
  for a dance that holds another form's figures, and, for ECD only,
  `sequence_span_mismatch`.

## 4. Evidence and sources

### 4.1 Held squares (primary evidence)

The design rests on 19 traditional squares with figure text that the
maintainer's archive work has held back until square support exists. They
were collected on 19 November 2026 into a brief with each source text
verbatim, a line-by-line reading, and a call inventory. The brief is the
maintainer's working material, not a published source; this ADR cites the
dances, and every count below was checked against the verbatim text.

| Source | Squares with figures | Notes |
| --- | ---: | --- |
| Tony Parkes, *Son of Shadrack and Other Dances* (1993) | 11 | Book. Phrase labels and beats on every line. |
| Michael Fuerst (comp.), *Midwest Folklore and other dances* (1995) | 3 | Book. Phrase labels; beats mostly unstated. |
| Gene Hubert (ed.), *Dizzy Dances* vols 1–3 | 5 | Not from the books: callers' versions in workshop syllabi and American Country Dances On-Line. Weaker evidence. |

Thirteen more held squares from *Dizzy Dances* have titles but no figures
anywhere reachable, so they are not counted.

What the 19 show:

- **Kinds.** Every one is a phrased figure repeated to reels or jigs. None
  is a club patter sequence or a singing call.
- **Length.** 14 of the 18 with a known length are 64 beats. Four are 96:
  Masters' Quadrille, Southern Nights, Parallel Dried Alfalfa and Lavender
  Moon.
- **Repeat order.** Heads twice then sides twice (HHSS) in 8, heads and
  sides alternating (HSHS) in 4, four times through with everyone active in
  5. Southern Nights says only "Similar action for sides". Happy Hobo says
  "Repeat for the sides. Repeat entire dance."; the brief tentatively records
  HHSS, though the text reads more naturally as HSHS.
- **Partners.** 13 change partners every time through, and the source names
  the new partner (mostly the corner). 5 keep partners; 1 is unclear.
- **Simultaneous actions.** 8 have two groups dancing different things at
  once ("Four [Larks] (acting as two facing couples) pass through", then
  "[Larks] turn right in single file and go four steps while [Robins] pass
  through"). One (Interface Jig) also gives start offsets ("After 4 beats:
  Side [Robins] chain").
- **Labels.** Both books print contra-style phrase labels on every square.
  The syllabus versions omit them.
- **No book prints an intro, break or ending.** The syllabi describe the
  routine around the figure ("Intro; figure as above; figure with the sides
  leading; break; ..."), and one prints a break.

### 4.2 CALLERLAB documents (secondary)

The club calls that traditional squares borrow are defined by CALLERLAB. The
CALLERLAB documents in the project's shared files (Appendix B) supply their
names, their usual formations and their club timing. CALLERLAB restructured
its programs on 1 September 2026: a new 50-call Mainstream replaced Basic,
Mainstream and SSD.

The definition documents allow reprints and derivative works if their
copyright notice appears, but say the information "shall not be changed nor
revised in any derivation". The timing lists allow reproduction with the
notice "Reprinted with permission of CALLERLAB."

**Proposed by this ADR's author:** the app ships call names, formation names
and timing numbers as data, and writes **every glossary definition in its
own words**. No definition text, styling text or diagram is copied from
CALLERLAB or from any dance book. Whether the app's `THIRD_PARTY_NOTICES.md`
carries the CALLERLAB reprint line for the timing data is Q1.

### 4.3 Taminations

Per the maintainer's requirement (§1.1), **no code, data files, animations,
formation geometry or definition text from Taminations may be copied, ported
or translated into this repository.** It may be consulted to cross-check how
a call is danced. It was not consulted for this draft, and the
implementation PRs should each say whether it was consulted and confirm
nothing was taken.

## 5. Design principles

Each principle is a proposal by this ADR's author, except where noted: the
maintainer accepted the `sq_` prefix in §5.1 (Q5) and chose the direction of
§5.2 (Option A, §1.1).

### 5.1 Squares own their call IDs, and the IDs carry a prefix

The square taxonomy is a separate `Taxonomy(form: DanceForm.square)`. Every
call in it has its own definition, defaults, display template and glossary
text. Where a square call and a contra move share a concept, they share
**parameter names** (`who`, `hand`, `shoulder`, `beats`), as ADR-006 §5.1
does for ECD. They never share a definition. Implementation may share
rendering helpers; the data stays separate.

Every square move ID starts with `sq_`: `sq_swing`, `sq_hey`,
`sq_forward_and_back`. As in ADR-006 §5.1, the prefix applies to calls only:
the containers (`meanwhile`, `modifier`, `sequence`) are structural IDs that
every form shares, and stay unprefixed. Traditional squares share even more
names with contra than club squares do (swing, balance, circle, star,
promenade, chain, hey, gypsy/shoulder round, pull by, box the gnat, california
twirl). With unprefixed IDs:

- **Older builds would misread square dances without any error.** A build
  from before this work that receives a square dance by sync, archive or
  share resolves every figure through `contraTaxonomy`, so `swing` and
  `circle` would render with their contra meaning and defaults. With a
  prefix the old build shows the raw ID instead. That is visible, not wrong.
- **Anything keyed by move ID would collide**: dialect move wordings,
  shorthand tables, and editor display defaults.
- **The legacy square imports (§3) become detectable.** An unprefixed ID in
  a square dance is known to be a contra move from an earlier import.

The archive's existing contra data shows the risk is real: "square through"
already appears there as a contra move, mostly as a balance-interrupted
square through 2 in 8 beats, which is not the club call.

**Stems follow contra's namesakes** (this ADR author's call, after ECD). Where
a square call and a contra move share a name, the part of the ID after `sq_`
is contra's: `sq_pass_through`, `sq_right_left_through`, `sq_do_si_do`,
`sq_square_through`, `sq_cross_trails`, and `sq_swing` with contra's `prefix`
parameter for a balance before it. ECD kept contra's stem for some namesakes
(`ecd_pass_through`, `ecd_box_the_gnat`) but not all (`ecd_figure_eight`,
`ecd_balance_ring`, `ecd_rollaway`); squares make it a rule. It lets the
namesake report (`tools/ci/report_figure_namesakes.py`, #2299), which matches
on display name and on the ID after the prefix, find most pairs. It still
misses pairs whose stems differ, such as `sq_hand_turn` and contra's
`allemande`, or a balance in the ring and contra's `balance_the_ring`. The
report has no list of extra pairs today, so phase 1 adds one for these (this
ADR author's proposal). Shared stems also make the twin table in §8.4 easy to
read and check. Other square IDs spell "through" too; "thru" is a dialect
spelling.

*Alternative rejected:* plain IDs with the dance's form as the only
discriminator. It lost on the points above. ADR-006 made the same choice
with `ecd_`, which the maintainer decided in November 2026.

**Resolving a taxonomy.** Squares register in the existing
`TaxonomyRegistry` (§3): `sq_` joins `danceFormMovePrefixes`, and the square
taxonomy is added to `shippedTaxonomies`. Then `forForm(square)` is the
square taxonomy over contra's, and an unprefixed ID in a square dance is a
legacy contra move from an earlier import until it is converted (§8.4).
As for ECD, the figure picker offers only the form's own (`sq_`) calls, and
the square parser (§8.4) reads only square calls, so contra's layer under
the square taxonomy serves only to show legacy moves. Nothing else in
resolution changes.

### 5.2 Traditional squares first; club calls as borrowed vocabulary

*Decided by the maintainer on 20 November 2026 (Option A, §1.1). The details
below are the author's.*

The registry (§7) has two parts:

- **The traditional core** (§7.1): the calls the held squares use, with
  traditional defaults. Some have no CALLERLAB equivalent (hey for four,
  gypsy, pull by, balance outside a wave).
- **Borrowed club calls** (§7.2): CALLERLAB Mainstream calls, plus the Plus
  and Advanced calls that traditional squares or contras are found to use
  (§7.3): Circle to a Line (traditional "break to a line"), the Thar family,
  Shoot the Star, Do Paso, See Saw, Pass the Sea, Trade the Wave, Dixie Style
  to a Wave and Cross Trail Thru. Their meaning is CALLERLAB's, written in our
  own words, except where a traditional meaning differs and is kept as a
  variant.

Each borrowed call, and each core call that CALLERLAB also lists, carries
its **CALLERLAB program as a glossary label** ("Mainstream", "Plus",
"Advanced"), so a caller can see which calls are also club calls, and the
glossary can sort and filter by it (§8.3). Nothing else is derived from it:

- There is **no derived "required program"** for a dance. On traditional
  squares it would mislead: Parkes rates Circle Three Quarters
  "Intermediate", yet "break to a line" would label it Plus, and the program
  would say nothing about the heys and single-file moves that make other
  figures hard.
- Difficulty stays the caller's own level (ADR-005). Book ratings such as
  "Fairly easy", "Intermediate" and "Difficult" map onto it.
- Program membership is not versioned by CALLERLAB edition. The label is
  the 2026 program.

Everything the first draft built for club calling beyond Mainstream is out of
scope: Plus, Advanced and Challenge calls that no traditional or contra
source was found to use (§7.3), edition-versioned programs, and calls that
take another call as an argument ("Clover and (anything)"). §11 lists them
under revisit triggers. As the maintainer expects (§1.1), single Advanced or
Challenge calls will be requested for choreographed traditional squares. The
registry takes them one call at a time, with no need to complete a program:
a request adds one §7.2 row with its program label. Challenge calls have no
CALLERLAB timing, so their default beats come from the source that uses
them.

### 5.3 Beats are stored, with traditional defaults

Every call has a `beats` parameter, as in contra.

- **Defaults follow traditional practice** where the held squares show it
  (§7.1). For borrowed club calls with no traditional evidence, the default is
  the CALLERLAB count (§7.2).
- **The phrase totals are the main check.** Today the editor compares only the
  dance's whole beat total with its phrase structure (`phrase_overflow`,
  `phrase_underflow`) and warns when a `sequence` is longer than the longest
  phrase (`sequence_exceeds_phrase`). Phase 1 adds a warning when the calls in
  one phrase do not fill it. It would be the app's first per-phrase check: ECD
  has none (§3). This ADR proposes it for squares; whether contra uses it too
  is left to that phase's PR.
- **Squares count in beats.** Bars are ECD's (§3) and stay off for squares
  (this ADR author's call), and named phrases are for English dances only
  by the maintainer's decision (ADR-006 §9.2 point 8). Neither is missed,
  since the sources count beats and
  print A1 to C2, which unnamed phrase structures give (§12).
- **`goodBeats` lists every plausible count**, traditional and club, so that a
  traditional count is never flagged just for differing from a club count. A
  count outside the list is a warning, never an error.
- **Defaults can depend on parameters**, for example a circle's fraction and
  size, a hand turn's turns, or whether a swing starts with a balance.
  `ParamBeats` must be extended to read more than one parameter.
- **Imported dances keep their stated beats.** Sources such as Parkes state a
  count on every line, so defaults matter mostly for hand entry and for
  sources that state none (Fuerst, mostly).

The first draft's static-square adjustment (`fromStaticSquare`) is dropped.
It encoded a CALLERLAB convention that traditional sources do not follow;
they state the count they mean.

### 5.4 Formations describe calls, not dances

Every square dance starts and ends in a squared set. At dance level the
formation is the existing `FormationShape.square` (§3), and the Caller's
Companion importer stops using `other` + "Square".

For borrowed club calls, the registry records CALLERLAB's usual starting
formations as glossary information. These are shipped data, not stored on
figures. **The app does not track or simulate dancer positions.** It does
not check that a figure resolves, and it does not warn that a call is
improper from the previous call's formation. A position simulator is out of
scope (§11).

Whether a stored call should be able to record a formation or position the
source *states* ("lines of four at the sides", "end facing the nearest side
couple") is Q4.

### 5.5 Selectors name dancers the way traditional sources do

`who` is a single selector token, as in contra. ADR-006 §5.2 makes ECD's
`who` a list because ECD figures often name two groups ("2s and 3s"). The
held squares name one group at a time, so a single token is enough. Two
rules carry over from the existing taxonomy:

- **Role-neutral storage and display.** The books name the two roles with
  gendered words. The parser reads them as `role1s` and `role2s`, and the
  app shows the square dialect's role terms. Gendered role terms are never
  stored or shown, for squares as for every form (§3). Stored values that
  name a role use `role1` and `role2` (`role1Place`, not a gendered word).
  Following ADR-006 §3, where a quotation in this ADR would show a gendered
  role term, the default dialect's term takes its place in square brackets:
  "[Lark]" for the first role and "[Robin]" for the second.
- **Heads and sides mean the original heads and sides.** "At the head", for
  whoever is in the head position now, is a separate selector.

Traditional sources also name dancers by history: "original corner", "the
one you meet", "the one you face", "the one you swung", "person who started
as partner". The fixed relationships set when the square forms get tokens
(`originalCorners`, `originalPartners`, `originalOpposites`). So does the
very common "the one you face / meet" (`facing`). Relations that depend on
an earlier call ("the one you swung", "the one you just allemanded") stay as
text in the line's note. §6.2 lists the selectors.

### 5.6 Simultaneous and grouped actions use the existing containers

The contra model's containers apply, with one proposed change to `sequence`
(Q10):

- **`meanwhile`** for two or more groups dancing at the same time. The held
  squares need it in 8 of 19 dances: the first role stars while the second
  promenades, the second stands back to back while the first promenades
  single file, the first goes single file while the second passes through.
- **`sequence`** for a short run that must stand as one side of a
  `meanwhile`, or, if the sequence span is opened to squares, for steps that
  share one stated count (Q10).
- **`modifier`** where a source describes one action by another.

Their limits (2–6 children for `meanwhile` and `modifier`, at most 4 in a
`sequence`, two levels of nesting, and no container directly inside one of its
own kind) are enough for every held square except one. Interface Jig overlaps
three actions with stated start offsets ("After 4 beats", "12, of which 4 fall
in A.1 and 8 fall in A.2"). Offsets are not modelled; such a figure is stored
as `meanwhile` lines with the offsets in their notes (Q12).

Optional lines ("the sides can swing as well", "everybody can swing") are
stored as ordinary lines with a note, not as a new structure.

### 5.7 Parts of a call are not stored

"Right and left through" or "zoom" is one line. The app does not break a call
into parts. As in ADR-006 §5.3, a parameter the source does not state is
stored as `unspecified`, never filled with a usual value: Fuerst's bare
"Circle left" keeps an unspecified fraction.

## 6. Shared vocabulary

### 6.1 Parameter names

| Name | Meaning | Example values |
| --- | --- | --- |
| `who` | Who dances the call | `everyone`, `heads`, `role2s`, `facing` |
| `whom` | The other dancer, where the call names one | `corners`, `partners`, `originalCorners` |
| `hand` | The hand used | `right`, `left` |
| `shoulder` | The shoulder passed | `right`, `left` |
| `turns` | How far a turn goes, in full turns | `0.5`, `0.75`, `1`, `1.5`, `2` |
| `fraction` | How far around a circle, star or promenade | `quarter`, `half`, `threeQuarters`, `full` |
| `direction` | A turning or travel direction | `left`, `right`, `in`, `out` |
| `destination` | Where a promenade ends, as the source states it | `home`, `role1Place`, `role2Place` |
| `where` | Where a call is danced | `across`, `alongTheLine`, `inTheCenter`, `withTheSides` |
| `size` | Dancers in a circle or star | `2`, `4`, `8` |
| `count` | A number of hands | Square Through 1–5 |
| `prefix` | What the call starts with, as contra's swing names it | `none`, `balance` (swing) |
| `variant` | A named family member | Promenade: `couples`, `singleFile`, `outside` |
| `beats` | Beats, as in contra (§5.3) | `0`–`64` |

Parameters that only one call uses (`four`, `courtesy`, `around`, `into`,
`fullTurn`, `reverse`, `fullAround`) and per-call values such as `balance`'s
`where` (`inPlace`, `wave`, `ring`) are defined with the call in §7.

An amount the source gives loosely ("once around and a little bit more",
"just about 3/4") is stored as the nearest value with the source's words in
the line's note.

### 6.2 Selectors

- Everyone: `everyone`.
- Identity in the square: `heads`, `sides`, `headPosition` ("at the head"),
  `sidePosition`, `couple1` to `couple4`, `role1s`, `role2s`, `headRole1s`,
  `headRole2s`, `sideRole1s`, `sideRole2s`.
- Relationships: `partners`, `corners`, `opposites`, `rightHandRole2`
  ("right-hand [Robin]"), `leftHandRole2`, and the original ones,
  `originalPartners`, `originalCorners`, `originalOpposites`.
- Position: `facing` ("the one you face" or "meet"), `centers`, `ends`,
  `centerFour`, `outsideFour`, `leaders`, `trailers`.
- `unspecified`.

## 7. The call registry

IDs are shown without the `sq_` prefix (§5.1) to keep the tables readable.
Each entry's ID, parameters and defaults are proposals. Entries marked ⚠
have a point for the reviewer.

### 7.1 Traditional core

Built from the call inventory of the 19 held squares (§4.1). "Seen" is the
number of dances that use the call, then the beat counts seen on lines where
it stands alone (number of lines in brackets).

| ID | Parameters | Default beats | Seen | Notes |
| --- | --- | --- | --- | --- |
| `swing` | `who`, `whom`, `prefix` (`none`, `balance`) | 8; 16 with a balance | 19 dances; 8 (14), 12 (3), 14 (1), 16 (3) | "Balance and swing" is one line, as the sources print it. |
| `promenade` | `who`, `variant` (`couples`, `singleFile`, `outside`, `wrongWay`, `star`), `destination`, `fraction`, `direction` | 16 to a destination; ½: 8; ¾: 12 | 15; 16 (14), 8 (1) | Sources name a destination ("to the [Lark]'s place"), not a fraction. Single-file moves ("turn right in single file and go four steps") are `singleFile` with the source's words in the note. |
| `hand_turn` | `who`, `whom`, `hand`, `turns` | once: 4–8 (default 8); 1½: 8; twice: 8 | 11; 4 (4), 6 (1), 8 (8) | "Allemande left/right" and "turn ... by the hand" are aliases (Q8). Every source line names the person. |
| `circle` | `who`, `direction`, `fraction`, `size` | 8 dancers: full 16, ½ 8; 4 dancers: ½ 4, ¾ 8, full 8 | 10; 4 (2), 8 (6) | Parkes's ¾ circle of four is 8 (CALLERLAB 6). |
| `forward_and_back` | `who` | 8 | 10; 8 (11) | "Always a full eight beats in New England" (Parkes). "Forward again and ..." is Q10. |
| `pass_through` | `who` | 4 | 9; 4 (4) | Spelled "through" in the books, "thru" in some syllabi; dialect handles spelling. |
| `chain` | `who`, `where`, `fraction` (`half` across, `full` over and back), `four`, `courtesy` (`normal`, `powerTurn`) | 8; over and back 16 | 8; 8 (8), 16 (1) | "[Robins] chain", "four [Robins] chain", "the same two [Robins] chain", "chain along the line". `powerTurn` is Fuerst's "power turn", a courtesy turn with an extra half. |
| `star` | `who`, `hand`, `fraction`, `size` | 4 dancers: once 8, ¾ 6 | 8; 8 (9), 6 (1), 4 (1) | |
| `balance` | `who`, `whom`, `where` (`inPlace`, `wave`, `ring`) | 4 | 7; 4 (6) | Standalone balances, including in waves and rings. Before a swing it is the swing's `prefix: balance`. |
| `do_si_do` | `who`, `whom`, `turns`, `shoulder` | 8 | 7; 8 (5) | Includes 1½ and "once around and a little bit more" into a wave. "See saw" is an alias for `shoulder: left` (§7.2). |
| `separate` | `who`, `around`, `into` (`line`, `middle`, `home`) | 8 | 5 | Variants in the sources: "squeeze in between the sides", "stop behind this one", "go between the sides back into the middle". |
| `right_left_through` | `who`, `where`, `fullTurn` | 8; with a full courtesy turn 12 | 4; 8 (3), 12 (1) | "With the sides", "the other way (across the other corner)". |
| `lead` | `who`, `direction` | 4 | 3 | "Lead to the right" before a circle or split. |
| `face` | `who`, `direction` | 0 | 3 | "Face the sides", "face to the right"; a facing change with no travel. |
| `pass_by` | `who`, `whom`, `shoulder` | 2 | 2; 2 (3) | "Pass corner by right shoulder". |
| `pull_by` | `who`, `whom`, `hand` | 2 | 2; 2 (1) | |
| `hey` | `who`, `where` (`alongTheLine`, `inTheCenter`), `shoulder` (first pass) | 16 | 2; 16 (2) | Hey for four. |
| `turn_alone` | `who` | 4 | 2; 4 (1) | An about-face on the spot (after Parkes's glossary). CALLERLAB's U-Turn Back and Backtrack are aliases. |
| `shoulder_round` | `who`, `whom`, `shoulder`, `turns` | 8 | 1; none stated | "Gypsy" is an alias. ⚠ Default 8 is phrase-filling; the brief's reading of Hey 'Round the Corner gives 6 (Q11). |

Single uses in the held squares that stay `custom` lines unless more
evidence appears: "stand back to back", "cross the set", "move to the
right-hand [Robin]", "split the sides", and Shadrack's Square's "move up". "Pass
partner, swing the next" is two lines, `pass_by` and `swing`.

### 7.2 Borrowed club calls

CALLERLAB Mainstream (2026) calls not already covered by §7.1, plus the Plus
and Advanced calls that §7.3 found in traditional or contra sources. Default
beats are CALLERLAB's (reprinted with permission of CALLERLAB; "SS" means from
a static square). Where a held square gives a different traditional count,
the notes show it and `goodBeats` includes it. The program column is the
glossary label (§5.2).

| ID | Parameters | Default beats | Program | Notes |
| --- | --- | --- | --- | --- |
| `bend_the_line` | `who` | line of 4: 4, of 8: 6 | Mainstream | |
| `box_the_gnat` | `who` | 4 | Mainstream | Held squares: 4 (2 lines). |
| `california_twirl` | `who` | 4 | Mainstream | |
| `cast_off_three_quarters` | `who` | 6 | Mainstream | |
| `centers_in` | none | 2 | Mainstream | |
| `circulate` | `who`, `variant` | 4 | Mainstream | |
| `courtesy_turn` | `who` | 4 | Mainstream | |
| `dive_through` | `who` | 6 | Mainstream | Diving couple 2, arching couple 6. |
| `double_pass_through` | `who` | 4 | Mainstream | |
| `extend` | `who` | 2 | Mainstream | |
| `ferris_wheel` | `who` | 6 | Mainstream | |
| `first_couple_go` | `direction` | 6 | Mainstream | |
| `flutterwheel` | `who`, `reverse` | 8; SS heads or sides 10, SS all 12 | Mainstream | |
| `fold` | `who`, `variant` | fold 2, cross fold 4 | Mainstream | |
| `grand_square` | none | 32 | Mainstream | |
| `half_sashay` | `who`, `variant` (`halfSashay`, `rollaway`, `role2InRole1Sashay`) | 4 | Mainstream | |
| `hinge` | `who`, `variant`, `hand` | single 2, couples 3 | Mainstream | |
| `alamo_style` | none | 4 | Mainstream | |
| `step_to_a_wave` | `who`, `hand` | 2 | Mainstream | Held squares form waves with no separate beats. |
| `do_si_do_to_a_wave` | `who` | 6 | Mainstream | |
| `pass_the_ocean` | `who` | 4 | Mainstream | |
| `recycle` | `who` | 4 | Mainstream | |
| `right_and_left_grand` | `variant` (`grand`, `weaveTheRing`, `wrongWayGrand`) | 10 | Mainstream | |
| `run` | `who`, `variant`, `direction` | run 4, cross run 6 | Mainstream | |
| `scoot_back` | `who` | 6 | Mainstream | |
| `single_circle_to_a_wave` | `who` | 4 | Mainstream | |
| `slide_through` | `who` | 4 | Mainstream | |
| `spin_the_top` | `who`, `hand` | 8 | Mainstream | |
| `split_two` | `who` | 2 | Mainstream | |
| `square_through` | `who`, `hand`, `count` | 1: 2, 2: 5, 3: 7–8, 4: 10 | Mainstream | Held squares: square through 2 in 4 (Lavender Moon). `goodBeats` includes the traditional count. |
| `star_through` | `who` | 4 | Mainstream | |
| `sweep_a_quarter` | `who` | two couples 2, four couples 4 | Mainstream | |
| `swing_through` | `who`, `hand` | 6 | Mainstream | |
| `tag_the_line` | `who`, `fraction`, `direction` | full 6, ¾ 5, ½ 4, ¼ 3 | Mainstream | |
| `touch_a_quarter` | `who`, `hand` | 2 | Mainstream | |
| `trade` | `who`, `variant` | couples 6–8; named 3–4; partner 4 | Mainstream | |
| `trade_by` | none | 4 | Mainstream | |
| `veer` | `who`, `direction` | 2 | Mainstream | |
| `wheel_and_deal` | `who` | 4 | Mainstream | |
| `wheel_around` | `who`, `reverse` | 4 | Mainstream | |
| `zoom` | `who` | 4 | Mainstream | Southern Nights dances three zooms in 16 beats and says so. |
| `circle_to_a_line` | `who` | 8 | Plus | "Break to a line" is an alias; it is a basic move in traditional sources. |
| `thar` | `variant` | ½ arm turn to thar: 2 | Plus | Seen only in a caller's break. |
| `shoot_the_star` | `fullAround` | 4; full around 6 | Plus | Seen only in the same break. |
| `do_paso` | none | 12 | Plus | The Caller's Box glossary places it in early western square breaks, and Caller's Box dances use it ([callersbox.md](../research/callersbox.md)). |
| `pass_the_sea` | `who` | 6 | Plus | ⚠ Evidence is thin: an entry in the Caller's Box glossary index (§7.3). |
| `trade_the_wave` | `who` | 6 | Plus | The contra taxonomy has it (v39), and The Caller's Box writes it. |
| `dixie_style_to_a_wave` | `who` | 6; SS all 8 | Plus | Caller's Box dances use it ([callersbox.md](../research/callersbox.md)). |
| `cross_trails` | `who`, `variant` (`traditional`, `callerlab`) | 6 | Advanced | ⚠ The Caller's Box glossary says the traditional form (pass, then cross over toward the corner) came from 1950s squares and that CALLERLAB later redefined it. Contras by John Coffman use it, and contra's `cross_trails` is its namesake (§5.1). Default `traditional`; `goodBeats` lists a wide spread because no source gives a traditional count. |

CALLERLAB Mainstream calls that §7.1 already covers (Swing, Promenade,
Allemande and Arm Turns, Circle, Forward and Back, Pass Thru, "[Robins] Chain",
Star, Balance, Dosado, Separate, Right and Left Thru, Lead Right, U-Turn Back,
Backtrack) take their traditional entries, with the CALLERLAB name as an alias
where it differs. These entries also carry the "Mainstream" label, on the
entry or on its CALLERLAB-name alias, so a program filter finds them (§8.3).
The Plus call See Saw is the `do_si_do` alias noted in §7.1, with the label
"Plus" on that alias in the same way.

### 7.3 Plus, Advanced and Challenge calls in traditional sources

On 20 November 2026 the maintainer expected that some Plus, Advanced and
Challenge calls "still show up in trad squares or contra". We checked the held
squares, this repository's contra taxonomy and Caller's Box research notes,
and these online sources (Appendix B): the Caller's Box glossary and two of
its dances, Mary McNab Dart's *Contra Dance Choreography* (its own Appendix
B), Colin Hume's notes on modern western squares, Wikipedia's contra
choreography and traditional square articles, the dances of Cary Ravitz,
Robert Luecking and John Coffman, Paul Balliet's glossary, and the "Honeycomb
Contra Figures" page. Parts of some long pages could not be read in full, so a
call missing below may still be used somewhere.

| Call | Program | Where it was found | In the registry |
| --- | --- | --- | --- |
| Circle to a Line | Plus | Held squares ("break to a line") | `circle_to_a_line` |
| Allemande Thar, Shoot the Star | Plus | One held square's break | `thar`, `shoot_the_star` |
| Do Paso | Plus | Caller's Box glossary, as an early western square break; Caller's Box dances ([callersbox.md](../research/callersbox.md)) | `do_paso` |
| See Saw | Plus | Coffman contras (e.g. "Aback", a see saw ¾ into a wave in 8) | `do_si_do` alias |
| Pass the Sea | Plus | Caller's Box glossary index only | `pass_the_sea` ⚠ |
| Trade the Wave | Plus | Contra taxonomy (v39); The Caller's Box writes it | `trade_the_wave` |
| Dixie Style to a Wave | Plus | Caller's Box dances | `dixie_style_to_a_wave` |
| Cross Trail Thru | Advanced | Caller's Box glossary (1950s squares); about five Coffman contras | `cross_trails` ⚠ |

No Challenge call was found. These Plus and Advanced calls were looked for
and not found in any source read: Teacup Chain, Relay the Deucey, Spin Chain
Thru, Load the Boat, Dixie Grand, Fan the Top, Track Two, Peel Off, Ping
Pong Circulate, Linear Cycle, Chase Right, Coordinate, Explode the Wave,
Grand Swing Thru, Partner Tag, Partner Hinge, Quarter Thru, Turn Thru,
Acey Deucey and the diamond calls. They stay out of scope (§5.2). Walk
Around the Corner and Eight Chain Thru (both Plus) were not looked for and
are worth checking. The contra taxonomy's `zig_zag` shares only its name
with the Advanced call.

The same sources show Mainstream calls in contras (Box the Gnat, Star Thru,
Square Thru, Flutterwheel, Circulate, Spin the Top, Swing Thru), which §7.2
already covers. They also show traditional square calls outside CALLERLAB that
no held square uses: Allemande X, Catch All Eight, Mountain-style Do-si-do,
grand chains for either role, Birdie in the Cage and other Southern figures.
Those wait for a held square that uses them (§11).

## 8. Dance structure, entry, glossary and import

### 8.1 What a square dance record is

A square dance has one of three kinds, held in a new `squareKind` field
(only meaningful when `form == square`):

| Kind | What it holds | Phrasing |
| --- | --- | --- |
| `figure` | A phrased figure that is danced several times through | Phrased |
| `break` | An intro, middle break or ending | Phrased by default |
| `patter` | A free-form sequence or module | Free form by default |

A singing call is a `figure` with a new `singing` flag; its song goes in
the existing `tunes` field.

**Phrasing.** A phrased square uses the existing `phraseStructure` and its
labels, exactly as contra does. The empty default gives four 16-beat
phrases labelled A1 to B2, which fits 14 of the held squares; `6*8*2` gives
the 96-beat A1 to C2 that Parkes and Fuerst print. The editor shows the
labels and, with the new per-phrase check (§5.3), warns when a phrase does
not add up.

**The free-form toggle** (maintainer requirement, §1.1). Every square dance
has a `freeForm` flag that the editor shows as a toggle. It defaults on for
`patter` and off for the other kinds, and the caller can change it. When it
is on, the editor does not derive section labels or check phrase lengths,
shows only a total beat count, and keeps but ignores `phraseStructure`.

**Repeat order.** A new optional field, `order`, records how the figure is
repeated:

- `HHSS`: twice with the heads leading, twice with the sides;
- `HSHS`: alternating;
- `allFour`: four times through with everyone active;
- `other`, with text;
- `unstated`, the default.

Caller's Companion's `SubType` (for example "Keeper, H S H S") already
carries the order, and the importer can read it.

**New partner.** Most traditional figures change partners, and the source
says who the new partner is. A new optional field, `newPartner`, records it:
`none`, `corner`, `rightHandRole2`, `opposite`, `other` (with text), or
`unstated`. The existing `mixer` flag stays as the yes/no class that
Caller's Companion's `SubType` already sets. The contra `progression` field
is not used for squares, but the editor still shows it, as it does for ECD.

**Storing the new fields** follows ECD's pattern (this ADR author's call).
`squareKind`, `order`, `newPartner`, `freeForm` and `singing` are new
`dances` columns, each with a privacy-registry entry. Like ECD's meter, key
and interpreters, they are kept for every form, shown up front for squares
and under More details for other forms, so a dance whose form is changed and
changed back loses nothing. ECD's `improper`, which is cleared in other
forms, was the rejected precedent. An
archive is stamped with a newer version only when a dance carries a
non-default value, and sync omits default values, so existing wire hashes
do not change (ECD's `omittedDanceDefaults`). If the ECD schema and archive
versions are still unreleased when these fields land, they are amended
rather than bumped, as the version-bump gate (#2276) requires.

**Formation.** Square dances are offered `FormationShape.square` through a
square shape list, as ECD has `ecdFormationShapes` (this ADR author's
proposal). The value already exists and the archive already stamps
non-contra shapes, so no new enum value or wire gate is needed. But
ADR-006 added the value for ECD (F2), and the maintainer's answer that the
new shapes are "ECD only" (ADR-006 §9.1 point 2) was about contra, not
squares, so using it for square dances needs the maintainer's acceptance
(Q13).

**Breaks.** Breaks are their own records (`squareKind=break`), as the
maintainer decided (Q6). A figure and its usual break are linked with the
existing `DanceLink`. The editor can copy a break's calls into another dance
at the cursor, as ordinary lines, so no new structure is needed; later edits
to the break do not change the copy. A live reference that follows the
break's edits is left for later. The order of intro, figures, break and
ending around a figure (which the syllabi describe and the books do not) goes
in the dance's notes.

### 8.2 Entering calls

The figure editor offers the square registry when the dance's form is
`square`. Each line is one call, with its parameters and beats, as in
contra. Lines the registry cannot express are `custom`, with free text and
beats. A square shorthand table, kept separate from contra's, is a typing
aid only.

### 8.3 Glossary dance-form selector

The glossary's **dance-form selector** (maintainer requirement, §1.1) was
built for ECD for any number of forms (#2278; ADR-006 F6, S1, S6). Squares
appear in it once their taxonomy is registered, as a third segment after
Contra and ECD. The selector itself needs no change; the program sort and
filter below are new (phase 2).

- Every form is available on every device. The glossary opens on the form
  the new-dance form setting gives (ADR-006 S2, S6).
- The square glossary can be sorted and filtered by program (maintainer
  requirement, §1.1), as a browsing structure like Taminations' by level.
  The groups are the traditional core, then Mainstream, Plus, Advanced and
  Challenge. A core call that CALLERLAB also lists (Swing, Dosado, Right
  and Left Thru, ...) carries that program's label too (§7.2), so filtering
  to Mainstream shows it alongside the borrowed calls. Each entry shows its
  own-words definition, parameters, default beats and program label.
- Dialect settings already switch by dance form, and squares have their own
  dialect library (§3). The dialect editor's sample figures are ECD's or
  contra's today; squares need their own (phase 1).
- ECD ships its taxonomy with no glossary definition text yet. Squares plan
  own-words definitions, but they can follow the taxonomy as a separate
  step (§9).
- Figures of your own already carry a `form`, and the glossary already lists
  them by form (§3). The compound and custom-figure editors must resolve
  through the registry before an `sq_` figure of your own can be written.

### 8.4 Import and existing square dances

Traditional sources describe figures in prose with beat counts in
parentheses, as Parkes does ("Head couples forward and back (8 beats)") or
with the count first, as American Country Dances On-Line does ("(4) H/S
[Robins] cross the set"). The square line parser reads that prose, as the
contra importers already read Caller's Box and ContraDB lines. It does not
expect callers' shorthand.

The square parser is its own parser with the ECD parser's contract (this
ADR author's call): it never fails, falling back to an import-gap `custom`
line; it stores only what the words say; it checks its result against the
square taxonomy alone; it bounds line length and replaces gendered role
words before reading. Where import code now routes English dances with a
yes/no `ecd` switch (the Caller's Companion line cache, free-text entry, the
custom-line re-read), phase 3 replaces the switch with a choice by form
rather than adding a second one.

- **The held squares** (§4.1) are the first import target and the acceptance
  set for phase 3: each should import with every line structured except the
  single-use calls listed in §7.1. As with ECD's corpus, the texts are the
  maintainer's and are not committed: the PR records the counts, and the
  tests use lines written for them.
- **Caller's Compendium archives and shares** carry the new fields, with the
  same additive rules the figure codec already follows.
- **Caller's Companion** is the only current source that marks dances as
  square. From phase 3, its square dances are parsed with the square parser.
  Its `.USR` question about English dances already leaves squares out
  (#2284), and the importer takes the square form from `Type`, so no question
  or tag prompt for squares is needed.
- **The Caller's Box** may have some square dances: the maintainer believes it
  does (Q7), and its notation supports that. Its glossary defines square
  corners `C1`–`C3`, and a corpus count over a local mirror found 55 declined
  grand right and left lines using `C1`–`C7` codes
  ([callersbox.md](../research/callersbox.md)). A title search found none of
  the held *Dizzy Dances* squares there, though it did find a *Dizzy Dances*
  contra. So phase 3 starts with a search that confirms whether Caller's Box
  has squares at all, how it marks them and how their figure lines read. Its
  formation list includes "Grid Contra/Square"
  ([callersbox.md](../research/callersbox.md)), but that may mean
  grid-formation contras, so the search must not assume it is the marker.
- **Dances already imported as square** hold contra moves or custom text (§3).
  Most of their structured lines kept no source text, so the existing
  "re-parse custom figures" flow cannot help: it only touches import-gap
  custom lines. The plan:
  - **Phase 1** leaves them alone. Their unprefixed IDs resolve through the
    contra taxonomy (§5.1), so they display exactly as they do today.
  - **Phase 3** adds a migration that the caller runs per dance or for all of
    them, in ECD's steps (#2273): a table of contra moves with a square twin
    (`swing`, `circle`, `promenade`, `star`, `allemande`, `chain`, `hey`,
    `shoulder_round`, ...), carrying over only stored values; then a re-read
    of the contra display words with the square parser, refusing any reading
    that drops a stored value; then a re-read of import-gap custom lines.
    Anything else is left as it is. Some twins name or split parameters
    differently from their contra namesakes (§7.1 and §7.2: `circle`, `star`,
    `do_si_do`, `chain`, `square_through`, `cross_trails`, and `hand_turn`
    for contra's `allemande`), so the twin table maps each contra value to
    the twin's, and a test pins the mapping (this ADR author's call; ECD's
    twins carry values unchanged). The maintainer avoided such a table
    for cast by giving ECD's `cast` contra's parameters (ADR-006 §9.4,
    #770); squares keep their own parameters where the sources need them.
    Until a dance is converted, the editor's `other_form_figures` warning
    could point the caller to the conversion; that link is new (this ADR
    author's proposal). Like ECD's conversion, it also changes the
    formation, from `other` + "Square" to `FormationShape.square`. It maps the
    contra selectors that square imports may hold: since taxonomy v38 the
    maintainer's ruling (#1975) maps Caller's Box `C1`, `C2` and `C3` to
    `firstCorners`, `opposites` and `thirdCorners`, which become `corners`,
    `opposites`, and `rightHandRole2` where the third corner is the
    second-role dancer on a first-role dancer's right. §6.2 has no selector
    for a second-role dancer's third corner (the first-role dancer on their
    left), so those lines keep it in a note. The caller can also re-import
    from the original file, through the existing re-import flow.

## 9. Delivery phases

1. **Framework and traditional core.** Registering squares in
   `TaxonomyRegistry` with the `sq_` prefix (§5.1), a square taxonomy version
   with its history heading, gate rows and rebuild marker as ECD has (§3),
   moving the screens that name contra's taxonomy (§3, including the
   glossary's list of figures of your own, the custom-figure, user-figure,
   compound and shorthand screens) to the registry, the square taxonomy with
   the §7.1 registry, multi-parameter beats, a program label on calls and
   aliases, offering `FormationShape.square` to square dances (§8.1), the new
   dance fields (§8.1), the per-phrase beat check (§5.3), turning the ECD-only
   editor checks that squares need into checks by form (§3), opening the
   sequence span to squares (Q10), a placeholder figure per form, square
   sample figures in the dialect editor, extra pairs for the namesake report
   (§5.1), and tests.
2. **Borrowed club calls.** The §7.2 registry with CALLERLAB program labels,
   including the Plus and Advanced calls found in §7.3, and the glossary's
   sort and filter by program (§8.3).
3. **Entry and import.** Square editor behavior, shorthand, copying a break
   into another dance, the square prose parser, import of the held squares,
   Caller's Companion squares, the Caller's Box search, and the conversion of
   earlier square imports.
4. **Glossary text.** Own-words definitions for the §7.1 and §7.2 calls. ECD
   shipped its taxonomy before its definitions, and squares can too (this
   ADR author's call).

Out of scope, from the first draft: Plus, Advanced and Challenge calls that
no traditional or contra source was found to use (§7.3), edition-versioned
programs, a derived required program, and calls that take another call as an
argument.

## 10. Open questions

**Q1. CALLERLAB notice in the app.** Should `THIRD_PARTY_NOTICES.md` carry
"Reprinted with permission of CALLERLAB" for the borrowed calls' timing
data? It costs one line. *Recommendation: yes.*

**Q2.** *Withdrawn (20 November 2026).* It asked which CALLERLAB edition the
app should default to. Program labels now use only the 2026 edition (§5.2).

**Q3.** *Withdrawn (20 November 2026).* It asked where a dance's derived
required program should appear. There is no derived program for traditional
squares (§5.2).

**Q4. Stated positions.** Should a call line be able to record a formation
or position the source states ("end in lines of four at the sides", "end
facing the nearest side couple"), as an optional, never-computed parameter?
The held squares state these often. *Recommendation: defer; keep them in the
line's note for now.*

**Q5. ID prefix.** *Answered by the maintainer (15 November 2026): the
`sq_` prefix is accepted.* ADR-006 has since adopted `ecd_`, so nothing is
left open.

**Q6. Breaks.** *Answered by the maintainer (15 November 2026): breaks are
saved as separate records, and ideally the editor can put a break into
another dance; it is acceptable if that is not doable.* §8.1 proposes a
copy-in.

**Q7. Import sources.** *The maintainer believes The Caller's Box has some
squares (15 November 2026).* Its square-corner notation supports that
(§8.4). §8.4 adds it to phase 3, which first searches Caller's Box to
confirm it.

**Q8. Allemande.** §7.1 proposes one `hand_turn` call, with "Allemande Left"
and "Allemande Right" as aliases that pin the hand, in place of the first
draft's separate `allemande` and `arm_turn`. Parkes writes "allemande left
corner" and "turn partner by the left hand, once and a half" for the same
kind of action, and every allemande line in the held squares names the
person. Should a bare "allemande left" be read as the corner?
*Recommendation (changed on 20 November 2026, this ADR author's call): an
omitted `whom` still means `unspecified`, as §5.7 requires, but the editor
starts a new line on the corner through `ParamSpec.entryDefault`, which
seeds the editor without changing what an omitted value means (a caller who
keeps the seeded value stores it). "Allemande Left" and "Allemande Right"
are `MoveAlias` entries that pin the hand (`pinnedParams`). `entryDefault`
(taxonomy v38) and alias `pinnedParams` are existing contra mechanisms,
which ECD reuses.*

**Q9.** *Withdrawn by the author (20 November 2026).* It asked whether
Heads Square Thru 4 from a static square takes 10 or 12 beats. §5.3 proposes
dropping the static-square adjustment, so a source states the count it
means. Q9 reopens if that proposal is rejected.

**Q10. "Forward again and ...".** Several held squares write a half forward
and back that flows into the next action ("Forward again and swing the
opposite (8)", "Forward again and pass through"). Is that one line, the
next call with a note, or a `sequence` of a forward and the next call?
*Recommendation (changed on 20 November 2026, this ADR author's call): a
`sequence` with the source's one count and untimed steps, the span ECD
built (#2269). Today that span is ECD-only, so squares need it opened to
their form. The earlier recommendation, the next call with a note, is the
fallback if the span stays ECD-only.*

**Q11. Gypsy timing.** Should a gypsy (shoulder round) default to 8 beats,
like the other phrase-filling calls, or to 6? No held square states it.

**Q12. Start offsets.** Should a `meanwhile` side be able to start part-way
through, as in Interface Jig? One held square needs it. *Recommendation: no,
until more dances do; keep offsets in notes.*

**Q13. Square formation.** ADR-006 added `FormationShape.square` "for ECD
only" (F2). May square dances use it too (§8.1)? *Recommendation: yes; it
is the same four-couple set, and the value needs no new wire gate.*

## 11. Consequences and revisit triggers

**Becomes easier:** callers can store, search and print traditional squares
with the same structure contra has: phrase labels, beat counts, simultaneous
actions and the contra-like vocabulary these squares share. The glossary
becomes a reference for squares. Squares reuse what ADR-006 built or
decided: the taxonomy registry, the per-form dialects and the glossary
selector.

**Becomes harder, or costs:**

- **Per-phrase check.** The phrase check in §5.3 is new editor and
  validation work, not something contra or ECD has today.
- **Taxonomy registration.** ADR-006's registry and glossary selector take
  squares with no change, but screens including the glossary's list of figures
  of your own and the custom-figure, user-figure, compound and shorthand
  screens still name
  contra's taxonomy directly, and many editor checks are ECD-only (§3). Phase
  1 moves the first to the registry and turns the checks squares need into
  checks by form. Its tests follow ECD's in `taxonomy_registry_test.dart` ("a
  contra dance does not resolve `ecd_` IDs").
- **Taxonomy versioning.** A square taxonomy version adds a ledger heading,
  gate rows and a one-time rebuild marker, as ECD's did. Adding it to the
  version-bump policy is the maintainer's call, as it was for ECD (#2254).
- **Schema and privacy.** `squareKind`, `singing`, `freeForm`, the repeat
  order and the new partner are new persisted fields (§8.1). Each needs a
  privacy-registry classification in the PR that adds it.
- **Glossary text.** Own-words definitions for about 70 calls (19 in §7.1,
  49 in §7.2, and aliases) are real writing work, and need review by someone
  who calls traditional squares.
- **Overlap with contra.** Many traditional square calls look like contra
  moves. Keeping them separate (§1.1) means two definitions of a hey or a
  gypsy that must not drift into contradicting each other where the dances
  really are the same. The namesake report (#2299) lists each pair when one
  side changes. Shared stems (§5.1) let it find most pairs; the few whose
  stems differ go in a short list of extra pairs (§5.1).

**Explicitly out of scope:** club (MWSD) calling beyond the borrowed calls in
§7.2, simulating dancer positions, checking that a figure resolves,
animations, and any code, data or text from Taminations.

**Revisit when:**

- Callers ask to store club patter or singing calls beyond the borrowed
  calls, which would bring back edition-versioned programs, the rest of Plus
  and above, and calls that take a call.
- A caller or a traditional or contra source turns up another Plus,
  Advanced or Challenge call (§5.2, §7.3).
- Callers ask for stated positions or offsets (Q4, Q12).
- More held squares surface with calls §7.1 does not cover.

## 12. Learnings from the ECD implementation

The maintainer asked on 20 November 2026 for this ADR to take what applies
from the ECD work, which was mostly complete by then. Each choice below is
this ADR author's call unless it says otherwise.

**Taken from ECD:**

- The registry, prefix rules and form-scoped picker, unchanged (§5.1).
- Stems shared with contra's namesakes, as many of ECD's are
  (`ecd_pass_through`), made a rule for squares so the namesake report and
  the twin table work (§5.1, §8.4).
- Contra's `ParamSpec.entryDefault` to seed the editor, and `MoveAlias`
  with `pinnedParams` for named variants, both of which ECD reuses (Q8).
- Storage: columns kept for every form and shown up front for the owning
  form,
  privacy entries, an archive stamp only for non-default values, sync that
  omits defaults, and amending unreleased versions rather than bumping
  (§8.1).
- A taxonomy version with its ledger, gate rows and rebuild marker (§3,
  §9).
- A separate parser with ECD's contract, and dispatch by form instead of a
  yes/no switch (§8.4).
- The conversion's steps (though the square twin table also maps values, where
  ECD's carries them unchanged): a twin table, then a re-read of display
  words, then import-gap lines, then the formation (§8.4).
- An uncommitted acceptance corpus with recorded counts (§8.4).
- A sequence with one count and untimed steps, if opened to squares (Q10).
- The taxonomy before its glossary text (§9).
- The glossary's built segmented selector, in place of the dropdown this ADR
  first proposed beyond three forms (§8.3).

**Not taken, with reasons:**

- **Bars.** Square sources count beats, so squares stay in beats.
- **Named phrases** (`A:` …). They are for English dances only by the
  maintainer's decision (ADR-006 §9.2 point 8), and the square sources
  print A1 to C2, which unnamed phrase structures already give.
- **The improper flag.** It is ECD-only by the maintainer's answer (ADR-006
  §9.1 point 2), and squares have no proper or improper start.
- **ECD's empty `goodBeats`.** ECD lists no typical counts. Squares keep them,
  because traditional counts are stable enough that a count outside the list
  is worth a warning (§5.3).
- **A list-valued `who`** (`dancerList`). The held squares name one group at
  a time (§5.5).
- **ECD's own template notation.** Square calls render with contra-style
  templates, since their wording is close to contra's.

---

## Appendix A: worked examples

The source lines below are short quotations of the cited dances. The
encodings are this ADR's.

### A.1 Circle Three Quarters (Tony Parkes)

```text
A.1. Head couples forward and circle left in the center, three quarters around (8 beats)
     Heads swing opposite, moving out to [Lark]'s place (8)
A.2. Head couples lead to the right and circle four; head [Larks] break to a line of four (8)
     Forward and back (8)
B.1. With the couple across, circle four to the left, three quarters around (8)
     Swing the corner (8)
B.2. Promenade to the [Lark]'s place (16)
Sequence: Twice for heads, twice for sides.
```

```text
squareKind=figure  freeForm=false  phraseStructure=""  order=HHSS  newPartner=corner

A1  sq_circle            who=heads  direction=left  fraction=threeQuarters  size=4  beats=8
    sq_swing             who=heads  whom=opposites  beats=8
A2  sq_circle_to_a_line  who=heads  beats=8
    sq_forward_and_back  who=everyone  beats=8
B1  sq_circle            who=everyone  direction=left  fraction=threeQuarters  size=4  beats=8
    sq_swing             who=everyone  whom=corners  beats=8
B2  sq_promenade         who=everyone  variant=couples  destination=role1Place  beats=16
```

- The A1 circle's "forward" and the A2 "lead to the right and circle four"
  are kept in the lines' notes. "Break to a line" is the alias that reads as
  `circle_to_a_line`.
- The phrases total 16 each, so the per-phrase check (§5.3) gives no
  warning.
- Parkes gives a ¾ circle of four 8 beats. Under CALLERLAB's 6 this would
  have warned; under §5.3 it is the default.

### A.2 Synchromesh Square (Tony Parkes), B1

```text
B.1. Four [Larks] (acting as two facing couples) pass through (4)
     [Larks] turn right in single file and go four steps while [Robins] pass through (4)
     Swing the one you meet (original corner) (8)
```

```text
B1  sq_pass_through  who=role1s  beats=4
    meanwhile  beats=4
      sq_promenade  who=role1s  variant=singleFile  direction=right  note="go four steps"
      sq_pass_through  who=role2s
    sq_swing         who=everyone  whom=facing  note="original corner"  beats=8
```

The `meanwhile` holds the one shared beat count. "The one you meet" is the
`facing` selector, and the source's "(original corner)" stays in the note,
because it describes who that dancer is rather than how the dancers find
them.

### A.3 A 96-beat figure

Masters' Quadrille (Parkes) runs A.1 to C.2: `phraseStructure=6*8*2` gives
the same six labels, and the per-phrase check (§5.3) checks each 16-beat
phrase. Parkes notes
that the figure suits 48-measure tunes and otherwise runs against the music
on purpose; that goes in the dance's notes.

## Appendix B: sources

Traditional squares (primary evidence, §4.1):

- Tony Parkes, *Son of Shadrack and Other Dances*, Hands Four Books, 1993.
- Michael Fuerst (comp.), *Midwest Folklore and other dances*, 1995.
- Gene Hubert (ed.), *Dizzy Dances* vols 1–3, 1983, 1992 and 1990, through
  Ralph Page Legacy Weekend syllabi and American Country Dances On-Line.

CALLERLAB documents, held in the project's shared files (secondary, §4.2):

- Mainstream Dance Program Definitions, revised 29 March 2026.
- Mainstream Timing, revised 5 July 2026, effective 1 September 2026.
- Standard Mainstream Applications, revised May 2020.
- Standard Basic Applications, revised August 2022.
- Definition Guide for Basic/Mainstream, 7 February 2011.
- Plus Definitions, revised 25 August 2026; Plus Timing, revised 5 July
  2026; (New) Plus Program Suggested Teaching Order, effective 1 September
  2026.
- Advanced Definitions, revised 27 August 2026; Advanced Timing, revised 12
  June 2025.

Online sources for the §7.3 search (read 20 November 2026):

- The Caller's Box glossary,
  <https://www.ibiblio.org/contradance/thecallersbox/Glossary.htm>, and
  Seth Tepfer's "Spin the Top Contra" and its variant (dances 2110 and 2111).
- Mary McNab Dart, *Contra Dance Choreography*, Appendix B,
  <https://store.cdss.org/elibrary/dart/appendix_b.htm>.
- Colin Hume, "Modern Western Square Dance", <https://colinhume.com/dtmwsd.htm>.
- Wikipedia, "Contra dance choreography",
  <https://en.wikipedia.org/wiki/Contra_dance_choreography>, and
  "Traditional square dance",
  <https://en.wikipedia.org/wiki/Traditional_square_dance>.
- Paul Balliet, contra glossary (from *Twirling Dervish Returns*),
  <https://sites.google.com/site/contradancesbypaulballiet/contra-dances-by-paul-balliet/glossary>.
- Cary Ravitz, contra choreography notes, <https://www.dance.ravitz.us/>.
- Robert Luecking, collected dances,
  <https://luecking.hosted.uark.edu/LueckingDances.pdf>.
- John Coffman, contra dances,
  <https://sites.google.com/site/capecontradance/cape-girardeau-mo-contra-dance/contra-dances-by-john-coffman>.
- "Honeycomb Contra Figures", <https://upadouble.info/honeycombContra/>.

Reference named by the maintainer, under §4.3's rules: Taminations,
<https://github.com/bradchristie/taminations-flutter>. It was not consulted
for this draft, and nothing in it is taken from Taminations.
