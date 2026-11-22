# ADR-008: Rubric, from checking contra choreography to helping write it

- **Status**: Accepted on merge. Written 22 November 2026. The repository's
  usual path is to open an ADR as `Proposed` (CONTRIBUTING.md); for this one
  the maintainer chose to treat his merge of the pull request that adds it as
  the acceptance vote. Decisions he changes in review are changed here before
  the merge.
- **Roadmap item**: "Choreography validation integration" (Later milestones
  in [ROADMAP.md](../ROADMAP.md)); issue
  [#1031](https://github.com/ibanner56/CallersCompendium/issues/1031), the
  dance verification status chip
- **Deciders**: Maintainers

## How to read this record

This record is mostly about **product direction**: what Rubric should do for
a caller who is writing, importing or checking a contra dance, and in what
order. The decisions about the compiler itself (§5) are here because the
product depends on them. Many of them restate rulings the maintainer has
already made one figure at a time.

Each decision is labelled with who made it:

- **The maintainer decided** marks a choice Hudson (@ibanner56) made on
  22 November 2026, in the discussion that commissioned this record.
- **The maintainer's view** marks something he said in that discussion that
  this record builds on, without his having been asked to rule on it.
- **Author's call** marks a choice the author of this record made, with the
  alternative it rejected. The maintainer reviews these in the pull request.

Rubric's own design documents (its domain model, execution model, figure
catalogue, implementation guide and corpus status) live inside the
`compendium_rubric` package and reach `main` with it. Until then this record
names them without linking them.

## 1. Context

### 1.1 What Rubric is

Rubric is a pure-Dart package, `compendium_rubric`, that answers one
question about a contra dance: **do the dancers end up where the dance says
they will?** It reads a dance in `compendium_core`'s figure taxonomy, places
every dancer in an exact cell of a small set (two hands four or more, sized
from the figures), applies each figure as a pure function from one formation
to the next, and compares the final formation with an independently computed
reference: one or two progressions of the starting formation. The result is
one of three values: **Compiled**, **Mismatch** (it ran, but the dancers
ended up somewhere else) or **CompileError** (a figure refused, with a
reason).

Its foundations were ruled by the maintainer one figure at a time, and they
are what make it a checker rather than an animator:

- **Exact placement.** Every dancer has one cell and one facing after every
  figure. The success check compares position, role, couple number and
  couple identity cell by cell. It ignores facing and the bookkeeping for
  couples waiting out at the ends, and it settles a final wave onto the side
  lines before comparing, as the next figure would.
- **Progression is stated, never inferred.** The figure that progresses
  carries a flag, and the compiler never decides from the floor that a
  progression happened.
- **Refuse rather than guess.** A figure that cannot be danced from the state
  it is handed refuses with a typed reason. A dance with a free-text figure in
  it is never compiled around the unknown part.
- **`compendium_core` is consumed, never modified.** Core owns the dance
  representation and the taxonomy. Rubric verifies choreography expressed in
  them, and where core is wrong, Rubric pins the defect in a test instead of
  substituting a better answer.

### 1.2 Where it stands

Two measurements, over the maintainer's local mirror of The Caller's Box
(24,107 files, not in this repository):

- **22 November 2026**, after Rubric was brought up to taxonomy v40
  (pull request #2318): **1,962 of 3,163 in-scope dances compile (62.0%).**
  The September build, re-run on the same mirror the same day, reproduced its
  earlier result exactly: 2,035 of 3,254 (62.5%) at taxonomy v35. Of the 108
  dances that compiled in September and do not now, **96 now arrive with
  core's `sequence` container**, which Rubric does not read yet (§5.2). The
  other 12 are uninvestigated.
- **September 2026**, the last full breakdown. "In scope" excluded the 6,531
  files with a free-text figure (57% of the 11,499 files that hold a dance at
  all) and the dances blocked by a figure or parameter Rubric has
  deliberately deferred. The deferred figures blocking the most dances were
  `promenade` (546), `butterfly_whirl` (175) and `slice` (146), and the
  `meanwhile` container blocked 131. Three dances crashed with two dancers
  landing in one cell, two of them containing `give_and_take`.

The November run has not yet been broken down the same way, so the September
figures above are the latest per-figure numbers.

### 1.3 What callers are asking for

Issue #1031 asks for a dance to be checked so a caller knows an imported
dance works. The roadmap already plans a dance "compiler" in the dance view,
next to the beat counter, and lists choreography validation as a non-goal for
v1 that is developed separately.

A compiler that knows where every dancer is after every figure can do more
than say yes or no. The same fold that checks a dance can **show** the floor
after each figure, can try small edits to a broken dance and report which
ones compile, and can assemble new dances from the taxonomy and keep only
the ones that compile. Each of these is the checker run in a different way,
not a new engine. That is the progression this record lays out.

### 1.4 The wider field

Square dance callers have had checker-mover software for a long time. For
contra there are animators, dance databases and a few generators, but little
that checks a dance against an exact model of the floor, and nothing of that
kind inside a caller's own collection. This record does not set out to match
any other tool. It notes the field only because callers already understand
the idea of a tool that "moves the checkers", so Rubric does not need to
teach it.

### 1.5 Constraints

- **ADR-001**: the domain core is Flutter-free. Rubric is pure Dart, and its
  only project dependency is `compendium_core`.
- **Offline first.** The app works without a network. Rubric needs none.
- **The privacy registry.** Any new persisted field is classified in the same
  change that adds it (`AGENTS.md`, "Every persisted field must be
  classified").
- **Every user-visible string is localized.** A result shown to a caller goes
  through the app's localization, as core's validation issues already do.
- **AGPL-3.0-only.** Rubric's code and data are this project's own work.
- **Accuracy outranks coverage.** A wrong "this dance works" does more harm
  to a caller than "can't check this yet", so every surface below prefers the
  second.

## 2. Decision in brief

1. **Rubric is one engine with four uses, built in this order**: verify a
   dance (§3.1), show the floor after each figure (§3.2), suggest a repair
   for a dance that does not compile (§3.3), and generate dances (§3.4).
   *The maintainer decided the scope*: everything except animation. *The
   order is the author's call* (§4.2).
2. **Animation is out of scope.** So are square dances as a form Rubric
   compiles (§3.5). *The maintainer decided.*
3. **The engine keeps its exact-cell model** and extends it: containers
   (§5.2), a collision guard (§5.3), and phrasing warnings later (§5.4).
   *The maintainer decided* the container model, the collision approach and
   the phrasing timing; the mechanisms are the author's calls, marked where
   they appear.
4. **Verification reaches the app first, behind an experimental switch**
   (issue #1031), once the bar in §6.2 is met. *The switch was the
   maintainer's plan for this work; the bar is the author's call.*

## 3. Decision: what Rubric does for a caller

### 3.1 Verify: does this dance work?

The first use is the one #1031 asks for. On a dance's details and in dance
entry, Rubric reports one of these states:

| State | When | What the caller sees |
| --- | --- | --- |
| **Works** | Compiled, with the progression taken from the record | The dance progresses as written |
| **Works if the progression is where we assumed** | Compiled, but the record does not mark the progressing figure and the importer assumed one | Says which figure was assumed |
| **Doesn't progress** | Mismatch | Where the dancers end up and where they should have |
| **A figure didn't fit** | A figure refused (`whoMismatch`, `notAdjacent`, `unresolvableDancerSet`, `unperformedProgression`) | The figure, who Rubric expected and who was there |
| **Can't check yet** | A free-text figure, a deferred figure or parameter, a form Rubric does not model, or a collision (§5.3) | What Rubric does not understand yet |

- *The maintainer decided* that a dance must be checkable for the product to
  be useful: every figure in the taxonomy should work for its standard usage.
- *Author's call*: **"Can't check yet" is never shown as a failure.** It
  separates what Rubric has not learned from what it found, as the corpus
  report already keeps separate outcome buckets. The rejected alternative was
  a single pass/fail, which would blame a dance for a figure Rubric has not
  learned.
- *Author's call*: **a refusal or a mismatch is reported as what Rubric
  found, not as a verdict on the dance.** Today many refusals are Rubric's own
  gaps (swing's `whoMismatch` refusals were the largest single group in
  September), so the wording says what did not fit and where, and §6.2 keeps
  verification behind the experimental switch until those gaps are small.
  The rejected alternative was "this dance is wrong", which the current
  numbers do not support.
- *Author's call*: **an assumed progression is always shown as assumed.** The
  Caller's Box does not mark the progressing figure, and Rubric's importer
  assumes one by a fixed rule and always warns. A green result that rests on
  a guess must not read like one that rests on the record.
- *Author's call*: **results are computed when shown, not stored.** Compiling
  one dance is a short pure fold, and storing a result would add a persisted
  field, a privacy classification, a sync question and a staleness problem
  whenever the dance or Rubric changes. The rejected alternative was a cached
  status column. Revisit if a collection-wide view (for example, a filter for
  dances that do not progress) makes on-demand compiling too slow.

### 3.2 Show the floor: where is everyone after each figure?

The second use shows the formation **after each figure**: every dancer's
cell and facing, drawn as a small static diagram beside the figure list. A
caller can step through a dance and see where it went wrong, which is what a
checker-mover gives a square dance caller.

- The fold already computes each intermediate formation and discards it;
  only Rubric's developer probe prints them today. *Author's call*: Rubric's
  public result gains the per-figure formations, including the last good one
  before a refusal. Nothing new is modelled, but the result type changes.
- **Positions are known at figure boundaries, not between them.** The
  record's beats say *when* each boundary falls, so "where is everyone after
  beat 24" has an answer whenever beat 24 ends a figure. *The maintainer's
  view*: drawing the motion between those points is animation, which
  compiling does not need (§3.5, §5.1).
- *Author's call*: when a dance refuses or mismatches, the diagram shows the
  last good formation and marks the figure that failed.
- *Author's call*: diagrams are static and drawn by the app from Rubric's
  formation values. Rubric itself draws nothing, so a future visualization
  plugin can read the same values.

### 3.3 Repair: what would make this dance work?

The third use answers a Mismatch or a refusal with **suggestions**: small
edits that make the dance compile. Everything in this section is the
*author's call*.

- A suggestion is a single bounded edit: change one parameter of one figure
  (for example the hand, the shoulder, the amount of a turn or who does it),
  replace one figure with a figure of the same beats, or move the
  progression flag to another figure.
- Every suggestion is **compiled in full** before it is shown. Rubric never
  suggests an edit it has not verified.
- Suggestions are **shown, never applied**. The caller chooses one, and the
  change is an ordinary edit to their dance.
- Suggestions are ranked by how little they change: one parameter before one
  figure, a figure in the failing phrase before one elsewhere. Ties keep the
  dance's own order, so the same dance gives the same suggestions every time.
- The decision the maintainer should look at most closely: **this is a
  search, and Rubric's rules forbid searching to decide what a record
  means.** The importer's progression rule tries two placements and no more,
  because a search would have no principled way to choose among several that
  work. A suggestion search does not decide what the record means. It
  proposes edits to a person, who chooses. The compiler's own rule stays
  untouched: it never infers a progression, and a record with no flag still
  refuses. The rejected alternative was to offer no repair at all, which
  leaves the caller with a diagram and no next step.

### 3.4 Generate: write me a dance

The fourth use builds new dances from the taxonomy: a caller gives a
formation, a progression and constraints (figures to include or avoid, a
difficulty, a figure to feature), and Rubric proposes dances that compile.
Everything in this section is the *author's call*.

- **Generate, then verify.** Candidates are assembled figure by figure and
  each partial dance is compiled as it grows, so a branch that cannot be
  danced is dropped early. Every dance offered has compiled in full.
- **Phrasing comes first.** A generated dance has to fit the music, so
  generation waits for the phrasing warnings in §5.4. Verification can
  tolerate a dance that bends its phrases. A generator must not produce one.
- **Flow is a ruling, not a statistic.** What may follow what is
  choreographic judgement, so flow rules are written down as maintainer
  rulings, as figure semantics are, and are not learned from the corpus. The
  rejected alternative was a model trained on the corpus, which would copy
  its habits and its errors with no ruling to answer for them.
- **A generated dance is the caller's.** It is saved as an ordinary dance in
  the caller's collection, and the app records that it was generated. That
  record is a persisted field and is classified in the privacy registry in
  the change that adds it.
- Before offering a dance, the app checks the caller's own collection for a
  dance with the same figure sequence and says so, so a caller does not
  unknowingly present an existing dance as new.

### 3.5 Out of scope

- **Animation.** *The maintainer decided.* Rubric does not model dancers
  between figure boundaries. The roadmap's visualization plugin is the place
  for it, and §3.2's formation values are what it would read.
- **Square dances.** *The maintainer decided* that Rubric will not compile
  square dances: mature square dance tools already exist, and the maintainer
  does not have the square dance expertise to rule on figures. This holds
  even if the app gains square dance records, as the square dance grammar
  proposed in pull request #2204 would allow.
- **English country dance and other longways forms.** Not decided by this
  record. Rubric models duple improper and Becket contra today, and each new
  formation needs its own figure definitions (triple minor, three facing
  three and four facing four among them). English country dances have their
  own grammar ([ADR-006](006-english-country-dance-canonical-grammar.md)),
  and compiling them would be a decision of its own.

## 4. Rationale

### 4.1 One engine, not four tools

Each use in §3 is the fold run differently: once (verify), once with its
intermediate states kept (show), many times over small edits (repair), and
many times over growing candidates (generate). Building them on one engine
means a figure taught to Rubric improves all four at once, and a ruling made
for one is honoured by the others. Separate tools would drift, and a
generator that did not share the checker's model could produce dances the
checker refuses.

### 4.2 The order

*Author's call.* Each use depends on the one before it:

- Verification is what callers asked for, and its accuracy bounds every
  other use.
- Showing the floor needs only what verification computes, and it makes
  verification's answers explainable.
- Repair needs the floor view, so a caller can see why a suggestion works.
- Generation needs phrasing, flow rulings and a high pass rate, because a
  generator that only works with the figures Rubric knows will lean on them.

The rejected alternative was to lead with generation, which is the most
visible feature but would rest on the least verified ground.

### 4.3 Why the exact model, and not a continuous one

*Author's call*, consistent with the maintainer's rulings so far. Animators
place dancers at continuous coordinates and check closeness. Rubric places
them in cells and checks equality. The exact model is weaker at showing a
dance and stronger at checking one: a dance either reaches the reference
formation or it does not, and a tolerance cannot hide an error. Rubric keeps
it. Where an outside description of a figure places dancers continuously,
Rubric reads it for the order of the dancers and their facing, and decides
the cells itself.

## 5. Decision: the engine underneath

### 5.1 The state model

- **Every dancer has an exact cell and facing after every figure.** This
  record restates that and changes nothing. A figure Rubric cannot place
  exactly is deferred, not approximated.
- *The maintainer decided* that Rubric must be able to say where every
  dancer is and when. It can, at every figure boundary of every dance it
  compiles; §3.2 is that answer made visible.
- *The maintainer's view*: continuous motion between cells is an animation
  concern, and parsing and compiling choreography do not need it.
- **Quarter turns are an approximation, by design.** A turn taken a quarter
  past a whole or half turn, along the set, lands its pair in a wave. Rubric
  keeps the pair on its own two rows and slides each dancer one column
  toward the centre, rather than adding an artificial middle row. *The
  maintainer's view* is that the landings are known for most turns, but that
  a quarter turn on two rows is not a full 90 degrees. The order of the
  dancers across the set and their facing come out right; the geometry is a
  projection onto Rubric's grid. Quarter turns across the set are still
  deferred. Which turns' quarter landings are ruled is recorded in Rubric's
  own domain model.

### 5.2 Containers: `sequence`, `meanwhile` and `modifier`

Core's taxonomy has three structural containers, and Rubric reads none of
them today. `sequence` cost the 96 dances lost in the taxonomy-v40 sync
(§1.2), and `meanwhile` blocked 131 more in September.

**`sequence`** is an ordered run of figures on one line ("balance and
swing"). *Author's call*: Rubric folds its children in order, exactly as if
they were written as separate figures, and a progression flag on the
container applies after the last child. Nothing else in the model changes,
and it is expected to recover most of the 96.

**`meanwhile`** is two or more groups dancing at once ("larks allemande
while robins orbit"). *The maintainer decided* the model, steps 1, 3 and 4:

1. Every side reads **the same starting formation**.
2. Each side is folded on its own, over only its own dancers. A side may be a
   `sequence`, which folds in order within that side. *(Author's call.)*
3. The results are **merged**: each dancer takes the cell and facing its own
   side gave it. A dancer named by no side stays where it was. *(The
   maintainer decided the merge; the dancers named by no side are the
   author's call.)*
4. The figure **refuses** if two sides name the same dancer, or if two
   dancers end in the same cell.

The maintainer asked whether a `meanwhile` could be "compiled" into a single
transformation. It can, and it is the same model seen from the other side.
Each side moves its own dancers to new cells and facings. When the sides
share no dancer and no destination cell, the union of those moves, plus the
dancers who stand still, is **one move of the whole set**, and the
`meanwhile` is one figure that applies it. The refusal in step 4 is exactly
the case where the union is not a valid move. So the fold and the reference
formation treat a `meanwhile` as one figure. If the container carries the
progression flag, the end-of-set normalization runs once, after the merge,
as it does after any progressing figure. *Author's call* on sizing: a
`meanwhile` contributes the sum of its sides' extra hands four and the
widest of their reaches, the same rule the dance applies across its figures.

What the model cannot express is one side **depending on where the other
side's dancers end**. Rubric refuses that case rather than guess an order.
The couple-`who` `orbit`, whose true half turn carries a couple onto the
cells the centre figure vacates, fits the merge model provided the centre
figure does vacate them, and is checked against it when it is next worked.

**`modifier`** is a whole-set figure changed by another ("long lines, while
the robins roll away"). Core builds one for two cores (`long_lines` and
`slice`) and two modifiers (`roll_away` and `give_and_take`). *Author's
call*: each pairing is a figure of its own, defined by a maintainer ruling
like any other figure, because a modifier changes how its core is danced
and is not two independent groups. Pairings without a ruling are deferred.

### 5.3 Collisions

Two dancers landing in one cell is caught today when the figure that causes
it builds its output formation, but it is caught as an exception, which the
corpus harness records as a crash so a sweep can continue.

- *The maintainer leaned toward*: **refuse now as a guard, then fix each
  figure.** His answer was "Probably C?", and he added that every taxonomy
  figure has to work for its standard usage. This record takes that as the
  decision; he confirms or changes it in review.
- *Author's call* on the mechanism: the collision becomes a refusal naming
  the figure and **both dancers**, instead of an exception. The corpus report
  counts collisions in their own bucket, owned by Rubric, so they read as
  Rubric's defects and never as a fault in the dance, and the app reports
  them as "can't check yet" (§3.1). The rejected alternative was folding them
  into an existing refusal kind, which would hide a defect among genuine
  refusals.
- Each collision is then traced to its figure and the figure fixed, starting
  with `give_and_take`. A collision is a bug to fix, not a permanent refusal.
- *Author's call*: Rubric does not let two dancers share a spot as a special
  formation. Its grid has one dancer per cell, and a contra figure that would
  need two is a figure Rubric has defined wrongly.

### 5.4 Phrasing

*The maintainer decided*: **no phrasing check now; warnings later.** When it
comes, it is warnings and never a refusal. Real dances bend phrasing, so
verification must not refuse them for it. *Author's call* on the shape:

- The dance's length against its phrase structure. Core already derives
  phrase sections from a dance's configurable phrase structure and warns on
  overflow and underflow, and Rubric reads that rather than counting again.
- A figure that crosses a phrase boundary. Core does not warn about that
  today, so this warning is new work, and it belongs in core if the dance
  editor should show it too.

Generation (§3.4) is the one use that treats these warnings as constraints.

### 5.5 Corpora and evidence

- **The Caller's Box** stays the main test corpus. It stays out of the
  repository, and is measured on the maintainer's local mirror.
- **ContraDB** is the second. The site's dance pages are rendered HTML.
  Core's ContraDB HTML adapter turns a page back into taxonomy figures, and
  because ContraDB renders its figures deterministically from its own
  structured records, that back-conversion is the route in (*the maintainer
  decided*). Figures the adapter does not recognise still arrive as free
  text, and how many do has not been measured. ContraDB pages can mark the
  progressing figure, which the Caller's Box does not, so a dance whose page
  carries the mark can be checked without an assumed progression.
- *Author's call*: **any crawl of either site is slow, bounded and agreed
  with the maintainer first.** Both are volunteer-run.
- **Figure semantics come from the maintainer.** Each figure Rubric
  implements has been ruled in a direct conversation about what it does and
  where it leaves the dancers, and that stays the method. *The maintainer
  decided* that a taxonomy entry may cite the CALLERLAB definitions as
  outside evidence where a contra figure shares a square dance call, while
  noting that they add little beyond those conversations.

### 5.6 Integration into the app

- *Author's call*: Rubric joins `main` as the `compendium_rubric` workspace
  package. The app depends on it, it depends on `compendium_core`, and core
  never depends on it. The rejected alternative, folding Rubric into core,
  would put a research-grade engine on every import path.
- The verification state (§3.1) is shown only when the experimental switch
  for issue #1031 is on. *Author's call*: the switch lives in Settings,
  Experimental, beside the other experimental features, and is off by
  default.

## 6. Consequences

### 6.1 What becomes easier and harder

- **Easier:** one engine serves four features, and each figure ruling
  improves all of them. A caller can see why a dance fails, not only that it
  fails.
- **Harder:** every user-facing state in §3.1 must be localized and must
  stay honest as Rubric changes. A figure fix can turn a "works" into a
  "doesn't progress" for a dance a caller already trusts. That is correct,
  and the app shows the current answer without implying it was always so.
- **The repair search costs time.** Compiling every bounded edit can mean
  thousands of folds per dance. *Author's call*: it runs only when the
  caller asks, stops at a fixed budget, and says so if it stopped early.
- **Generation needs a body of flow rulings** that does not exist yet, and
  writing it is maintainer time.
- **Rubric's docs and this record must agree.** When a decision here changes,
  this record gains an erratum or a superseding record, and Rubric's own docs
  change in the same pull request.

### 6.2 The bar for turning verification on

*Author's call* on the criteria. The experimental switch for #1031 ships
when, on the latest corpus measurement:

1. no dance crashes, and every collision the guard reports is explained;
2. the `sequence` container is supported, so the taxonomy-v40 losses are
   recovered;
3. every dance a spot check of compiled results turns up as wrongly
   "working" has been fixed, because a false "works" is the failure callers
   cannot see; and
4. the in-scope compile rate reaches a level the maintainer sets.

The number in point 4 is the maintainer's to set. This record does not
choose it.

### 6.3 Debts accepted knowingly

- Most dances in the Caller's Box that have figures arrive with at least one
  free-text figure and cannot be checked. Raising that ceiling is
  import-dialect work in core, not Rubric work.
- The importer's assumed progression stays a guess. ContraDB dances that mark
  the progression, and dances entered in the app where the caller marks it,
  do not need it.
- Square dance and non-contra forms stay unsupported.

## 7. Revisit triggers

- A caller asks to see dancers between figure boundaries, or the
  visualization plugin needs positions Rubric cannot give.
- Compiling on demand is too slow for a view across the whole collection
  (§3.1).
- The repair search's budget routinely stops before finding a suggestion.
- A second form (English country dance, triple minor) is to be compiled.
- A figure turns up whose standard usage cannot be expressed as one move of
  the whole set, inside or outside a `meanwhile`.
- `compendium_core` changes its containers or the meaning of the
  progression flag.
