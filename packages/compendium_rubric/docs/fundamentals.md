# ContraCompiler — Grounding Fundamentals

> Living reference for the core domain model. Captured to retain fidelity across the
> project. **The user defines all decisions**; this doc records only what has been
> explicitly decided, plus clearly-labeled open questions. Update it as decisions land.

---

## 1. Purpose

ContraCompiler is a "compiler" (written in Dart) that:

1. Takes an **ordered list of operations** ("figures") drawn from a predefined taxonomy.
2. Applies each operation, in order, to a **matrix** representing dancers on the floor.
3. Confirms whether the resulting matrix is a valid **output state** matching a named
   **success criterion** supplied alongside the operations.

Example request: operations `[A, B, A, C, B, D, A]` with success criterion `DI-SINGLE`.
(Operation names and success-criterion names are illustrative until defined.)

> The compiler's **execution model** (stateless functional core, fold over operations,
> independent success-state oracle, precondition error exits) lives in `architecture.md`.
> This doc covers the **domain state-model** (formations, encoding, progression mechanics).

### 1.1 Standing rule — this model is the source of truth

There is a **separate, older project** — `ContraDanceVerifier` (C#), a sibling of this repo —
that solves an adjacent problem. It is a legitimate source of *domain* learnings, and its figure
handlers and triage reports are worth mining. It is **not** an authority on this compiler.

The two differ at the foundations, not just in style:

| | ContraDanceVerifier | ContraCompiler |
|---|---|---|
| Grid | 2×2 local hands-four (`Nx2` extended) | 6×5 side-column matrix, centre cells c1–c3 |
| Dancer | `Role {Man, Woman}` + couple number | role1/role2 + couple identity |
| Facing | `{Up, Down, Left, Right, Center, Out}` | adds **`flexible`** (genuinely unresolved) |
| Input | **free text**, ~60 regex handlers, first match wins | **structured params** from the taxonomy |
| Oracle | **row only** — "column doesn't matter"; Becket passes on *total error ≤ 3* | **exact placement** |
| Progression | implicit in some figures (e.g. arch-and-dive bakes it in) | **explicit `progression` flag**, verified |

The oracle row is the one that matters most. A dance "passing" over there is a much weaker claim
than compiling here, so **their passing corpus cannot be used as an expected-output oracle.**

**The rule, therefore, with zero exceptions without the user's explicit confirmation:**

> When a learning, claim, or implementation in the legacy project **contradicts** this project's
> model — or cannot be reconciled with it — **assume this implementation is correct** and **ask
> the user** whether that assumption holds. Do not "fix" this project to match theirs, and do not
> silently adopt a behaviour that countermands these fundamentals.

The reasoning is that a contradiction is far more likely to be an artifact of their different
representation than a defect here: a transformation that is right on a 2×2 grid with a row-only
oracle can be wrong on an exact 6×5 one, and vice versa, without either being a bug. Read their
work for *what the dance figure does in the real world*; keep the geometry ours.

---

## 2. Scope

**In scope now:** **Duple** formations only.

- A "hands four" (a.k.a. **hands 4** / **h4**) is the duple grouping: **4 dancers**.
- A contra **line / set** is made of multiple such groups stacked down the hall.

**Deferred (stubbed, future work — will NOT reuse duple definitions):**

- **Triple** formations (6 dancers per group).
- **Three-facing-three** (6).
- **Four-facing-four** (8).
- Any other / unrecognized formation.

> Rationale: for nearly every operation, non-duple formations produce **different**
> results than duple, so each will need a complete, separate set of definitions. Until
> then, they are stubbed as pending tasks.

---

## 3. Terminology

| Term | Meaning |
|---|---|
| **Hands four / h4** | One duple group of 4 dancers (2 couples). |
| **Set / line** | The whole line of dancers = multiple h4 stacked down the hall. |
| **Lark / Robin** | The two **roles** (gender-free). Other dialects: Gent/Lady, Man/Woman, Lead/Follow. |
| **#1 couple / #2 couple** | The couple **number**. Historically "Actives"/"Inactives"; that distinction is weaker today. |
| **Couple A / B / C / D …** | Stable **identity** of a couple, tracked as it moves through the set. |
| **Top / bottom of the hall** | Top = above the first row; bottom = below the last row. |
| **Progression** | An explicitly-flagged operation that moves couples on to new neighbors (see §10). |

A couple is two dancers: e.g. couple 1-A = **L1-A** (Lark) + **R1-A** (Robin).

---

## 4. The Matrix

- **Empty rows are not represented** — the matrix holds only rows that contain dancers.
  (Empty **columns** c1–c3 **are** kept; see below.)
- Each **h4 occupies 2 rows × 5 columns**: the #1 couple on the upper row, the #2 couple
  on the lower row (no gap row between them, no buffer rows at the ends).
- **N** hands-four stacked vertically ⇒ full matrix is **(2·N) rows × 5 columns**.
- **Cell = decimal value** of a per-dancer bitmask (see §5). **`0` = empty space.**

Row layout within an h4 block (2 rows, block-relative, **at the standard start**):

```
 block row 0 (upper)   #1 couple      (faces DOWN the hall)
 block row 1 (lower)   #2 couple      (faces UP the hall)
```

> **Important:** h4 boundaries are **not** simply fixed row pairs — after a progression the
> first h4 can begin at row 1 instead of row 0. The boundary is determined by the couple
> **numbers**, per the governing rule in §10. Absolute row `2i`/`2i+1` pairing only holds
> while the first h4 begins at row 0.

The **middle columns (c1, c2, c3)** are retained to give figures room to resolve coherently
(only c0 and c4 hold dancers at the standard start; the precise reasons for the middle
columns emerge as operations are defined).

### Orientation (fixed / derived)

Derived from the user's start + normalization rules (see §8):

| Axis | Low index | High index |
|---|---|---|
| Rows | **r0 = top / North** | last row = **bottom / South** |
| Cols | **c0 = West** | **c4 = East** |

---

## 5. Dancer Encoding

Each dancer is a bitmask; the matrix stores its **decimal** value. Bit semantics are
computed on demand (avoids a dynamically-sized enum type as couple count grows).

Bit layout (read from the **right**; the couple-id field grows with the number of couples):

```
   … [ couple-id one-hot ] [ number ] [ role ]
        (N bits)             (1 bit)    (2 bits)

   role   (bits 1..0): 01 = Lark,  10 = Robin      (00 only for empty cell = 0)
   number (bit 2):      0 = #1 couple, 1 = #2 couple
   couple-id (bits 3+): one-hot, ascending powers of two:
                        A = …0001, B = …0010, C = …0100, D = …1000, …
```

**Decode helpers** (value `v`, `0` = empty):

| Property | Test |
|---|---|
| Empty | `v == 0` |
| Lark | `v & 1 == 1` |
| Robin | `(v >> 1) & 1 == 1` |
| #1 couple | `(v >> 2) & 1 == 0` |
| #2 couple | `(v >> 2) & 1 == 1` |
| Couple-id | `v >> 3` (one-hot: bit index 0→A, 1→B, 2→C, 3→D, …) |

Because couple-id is one-hot from the low end, a couple's id value is **stable regardless
of set size** (A always contributes 8, B 16, C 32, D 64, E 128, F 256, …). Bit width =
**N** (couple-id) + **1** (number) + **2** (role), where N = number of couples.
- Single h4 (2 couples) ⇒ 5-bit values (e.g. L1-A = `01001` = 9).
- Two h4 (4 couples) ⇒ 7-bit values (see §11).
- Three h4 (6 couples) ⇒ 9-bit values (see §10.3).

### Invariant vs. mutable

- **Invariant:** `role` (Lark/Robin) and `couple-id` (A/B/C/D). The one-hot couple-id is
  what lets us follow a specific couple as they move up/down the matrix.
- **Mutable:** `number` (#1 ⇄ #2). A couple's number changes at progression when it reaches
  an end of the set (§10).

> Note on the initial pairing: at the standard start, odd-lettered couples (A, C, …) are
> #1 and even-lettered (B, D, …) are #2. This is a **starting** condition, not a fixed
> rule — `number` is mutable.

---

## 6. Facing

Facing **is tracked** — it affects position normalization after some figures and the
handling of progression at the ends of the set.

**Facing values:**

| Facing | Toward | Compass |
|---|---|---|
| **Up** | top of hall / r0 | North |
| **Down** | bottom of hall / last row | South |
| **Across →** | higher columns / c4 | East |
| **Across ←** | lower columns / c0 | West |
| **Flexible** | context-dependent — resolved by the following figure | — |

**Initial facing:** all **#1 couples face DOWN**, all **#2 couples face UP**. Facing can
change as a result of operations.

**Flexible facing.** Some figures (e.g. `circle`) leave dancers in a **flexible** facing —
the direction is not yet fixed and is **resolved by the following figure**, which pins it to
whatever it requires (up / down / across). Flexible facing propagates until a figure consumes
it (by normalizing relative to facing) or a progression sets a concrete facing (§10.2).
Because facing is excluded from success-state equality (architecture §3.5, D4), a dancer left
flexible at the end of the sequence does not affect the match.

> **Open decision (§12):** the bitmask encoding does **not** carry facing. How facing is
> stored (parallel matrix, augmented cell/object, separate dancer record, …) is a data-
> structure decision still to be made — and it must be able to represent the **Flexible**
> value in addition to the four directions.

---

## 7. Left / Right relative to facing (geometric reference)

Objective geometry used by the normalization rule (§8). A dancer's left/right depends on
which way they face:

| Facing | Dancer's LEFT | Dancer's RIGHT |
|---|---|---|
| Up (N) | West / c0 | East / c4 |
| Down (S) | East / c4 | West / c0 |
| Across → (E) | North / top (toward r0) | South / bottom |
| Across ← (W) | South / bottom | North / top (toward r0) |

---

## 8. Position Normalization

When standing as a couple, dancers **normalize** their side **relative to their facing**:

- **Lark → to their LEFT.**
- **Robin → to their RIGHT.**

This is **not** a hard rule that every figure ends normalized, but several figures resolve
to normalized positions based on the direction the dancers face (up / down / across → /
across ←).

**Confirmed cases (up/down), consistent with the standard start and the example matrix:**

- **1s face DOWN** ⇒ Lark→left = **c4**, Robin→right = **c0**.
- **2s face UP** ⇒ Lark→left = **c0**, Robin→right = **c4**.

**Resolved case (across → / ←):** a couple facing **across** the set stands **stacked in a
single column** (both dancers in the same column, adjacent rows). Applying §7 directly:

- **Facing Across →** ⇒ LEFT = toward r0, so **Lark takes the upper row** (lower index),
  Robin the lower row.
- **Facing Across ←** ⇒ LEFT = toward the bottom, so **Lark takes the lower row** (higher
  index), Robin the upper row.

Instantiated in a hands four facing **in**: the **c0** pair faces Across → (Lark r0, Robin r1)
and the **c4** pair faces Across ← (Lark r1, Robin r0). Worked example: `swing` with
`where:sides, face:in` (taxonomy). See also `courtesy_turn`, `chain`, `right_left_through`.

> **Note:** it is the **up / down** case — not the across case — in which a couple falls along
> a **row** rather than a column: that is the line-of-four form produced by `swing`
> `face:down` / `face:up`.

> **Caveat — normalization is not universal.** Several figures *preserve* handedness rather
> than imposing it. The courtesy-turn family (`courtesy_turn`, `chain`, `right_left_through`)
> wheels the couple rigidly, so **the turned dancer ends on the RIGHT and the turner on the
> LEFT**; lark-left/robin-right is the common case there, not the rule. A couple arriving
> cleanly inverted ends inverted. See the `courtesy_turn` entry for the full invariant.

### 8.1 The line of four (transient formation)

The **line of four** is the first structure that uses the middle columns §4 reserved. It is a
*transient* formation — dancers pass through it mid-dance; no dance starts there (§9).

**Shape.** All four dancers of one h4 stand in a **single row**, spanning the hall:

```
 slots:   s0    s1   (—)   s2    s3
 cols:    c0    c1    c2    c3    c4
                      ^ empty: the set's centre line
```

**Side preservation.** The column pair standing on c0 occupies `{c0, c1}`; the c4 pair occupies
`{c3, c4}`. Dancers do not change sides of the set merely by forming a line.

**Which row (facing-derived).** A line facing **Down** occupies its h4's **upper** row; facing
**Up**, the **lower** row — i.e. the row it would travel *from*. When a figure reverses facing,
the line **migrates rows** accordingly. This holds without exception, including when facing and
travel disagree (`down_the_hall` with `facing: backward`).

> The row index of a line is a **normalization slot, not a hall position.** Travel up or down
> the hall is *not* a matrix transformation — it is a movement of the entire matrix, so it
> produces no displacement (see `down_the_hall`). The row therefore carries no information
> beyond orientation, and deriving it from facing keeps one exception-free rule.

**Normalization on formation.** When a line is *formed*, each pair normalizes lark-left /
robin-right relative to **facing** (§7) — never relative to travel. (`swing`'s `where:sides`
entry says "relative to travel" only because there the two always coincide.)

> **Normalization is a property of forming the line, not an invariant of it.** Figures that
> reverse facing while leaving slots in place — `turn_alone`, and the `slidingDoors` ender —
> necessarily leave the line **inverted**, which is physically correct: about-face without
> moving and the dancer on your left is now on your right. A line of four may therefore be
> non-normalized, and figures **must not** silently re-normalize one (see `down_the_hall`,
> conditional gather).

**Worked instances.** `swing` `where:sides` `face:down` / `face:up`; `down_the_hall` /
`up_the_hall` and their enders.

---

## 8.5 Waves (formation geometry)

> **Status:** the geometry below is **user-ruled and confirmed**, and
> `form_short_waves`, `form_long_waves` and `form_a_long_wave` now implement it. The
> remaining wave figures (`pass_the_ocean`, `rory_o_more`) and every quarter-turn amount
> are still deferred. See §12.

A wave is a line of dancers with **joined hands and alternating facing**. It was the single
largest gap in the model: it gated five held figures outright, and every quarter-turn refusal
in the taxonomy exists because a quarter turn lands in a wave. Three of those five are now
built (§8.5.1–§8.5.6 below are what they implement).

### 8.5.1 The offset rule (short waves)

Two dancers facing each other cannot join *matching* hands while squarely aligned — my right
hand is on my right side, yours is on yours, and facing each other puts those on opposite
sides of the space between us. Joining them requires a **sideways offset**:

> **To join RIGHT hands, each dancer steps toward their own LEFT.**
> **To join LEFT hands, each dancer steps toward their own RIGHT.**

In the matrix the offset is a **single column**, and because the outer lines sit on the grid
edge, only one of each facing pair can actually move:

> **The dancer whose step would leave the matrix HOLDS; their opposite absorbs the whole
> offset.**

Rows never change. **c2 is never occupied** — it stays the true centre line of the set,
which is precisely what §4 reserved the middle columns for.

**Worked example — a short wave from the standard duple-improper start** (2 h4, 4 couples).
Left/right are read off the §7 table.

*Right-hand wave* (everyone steps to their own left):

```
 .   R1-A  .    .   L1-A
L2-B  .    .   R2-B   .
 .   R1-C  .    .   L1-C
L2-D  .    .   R2-D   .
```

| Dancer | Faces | Own left | Result |
|---|---|---|---|
| R1-A (r0,c0) | Down | East | steps to **c1** |
| L2-B (r1,c0) | Up | West | off-grid — **holds c0** |
| L1-A (r0,c4) | Down | East | off-grid — **holds c4** |
| R2-B (r1,c4) | Up | West | steps to **c3** |

*Left-hand wave* (everyone steps to their own right) is the mirror:

```
R1-A  .    .   L1-A   .
 .   L2-B  .    .   R2-B
```

**At the standard start the effect reads role-uniformly** — right-hand ⇒ the Robins step in,
left-hand ⇒ the Larks step in — because facing is role-uniform there. That is a *consequence*,
not the rule. The rule is facing-relative, and away from the standard start (after a
progression, in Becket, or mid-figure) the two readings diverge. **Implement the facing rule,
never the role shorthand.**

### 8.5.2 The hand is not stored — it is geometry

Because the offset direction differs between the two hands, **which hand a wave uses is
recoverable from the positions alone.** There is therefore **no wave flag and no stored
handedness**: the offset positions are the whole truth.

> This is a deliberate divergence from `ContraDanceVerifier` (§1.1), which stores a wave as a
> `("wave", dancerOrder, "RH"|"LH")` overlay that **never modifies grid positions** and is
> flattened by `MapWaveToGrid()` the moment any non-wave figure runs. That is a bookkeeping
> dodge around a 2×2 grid with nowhere to put an offset dancer. Our matrix has the room, so
> we model the geometry instead. Per §1.1 this divergence is intentional and ours governs.

### 8.5.3 Facing

Forming a wave sets **concrete alternating facings**, not `flexible`. A wave's defining
property is that adjacent dancers face opposite ways; leaving that unresolved would discard
the very thing that makes it a wave.

### 8.5.4 Leaving a wave

When a **non-wave figure** runs against dancers standing in wave offsets, the offsets are
**automatically normalized back to c0/c4** before it executes. Exiting is not the departing
figure's responsibility.

Two consequences worth spelling out, because both are load-bearing:

**A line of four is not a wave.** Both shapes occupy `{c0, c1, c3, c4}`, so they have to be
told apart, and the discriminator is the row count: a line of four puts all four dancers of a
band in **one** row and leaves the other empty (§8.1), while a wave leaves **two per row**. A
band holding a line is skipped untouched. `c2` is never used by a line, so a centre dancer is
unambiguously a long wave — and they return to **the side column their rank has left free**,
which is well defined precisely because a centre wave is role-scoped (§8.5.5).

**The wave figures normalize too.** They are defined over settled side columns, so letting
the rule run before them is what makes them composable: forming short waves twice re-forms
the wave from c0/c4 rather than compounding two offsets, and `form_a_long_wave`'s `out` case
needs no code at all, because returning a centre dancer to the line they left *is* this rule.
The figures that opt out are the ones **danceable while standing in a wave** — `balance`, whose
canonical use is balancing the wave itself, `rory_o_more`, whose whole subject is the wave it
slides (normalizing first would delete it), and `stand_still`. The test is the figure's premise,
not its effect: moving nobody is not enough. `balance_the_ring` needs a ring of four with hands
joined all the way round and `long_lines` is danced in the two side lines; neither shape is a
wave, so the dancers must come out of one before either can begin, and both settle like any
other figure.

### 8.5.5 Long waves

Long waves run **along** the set rather than across it, and split into two cases. Neither
uses the §8.5.1 offset: that rule exists to let dancers who face *each other* join hands, and
in a long wave you join hands with the dancers **beside** you along the line, whom you do not
face. The line is already parallel to the wave, so no sideways step is needed.

**Side long waves** (`form_long_waves`, plural) — both lines become waves **in place** at
c0/c4. **No dancer moves at all**; only facing changes. The facing is **across the set,
alternating in and out**, which is what makes balancing a long wave a balance right and left
along the hall. Its `who` names the pair facing **in**, everyone else facing out — so `who`
here is a **facing selector, not a set of movers**, which it can afford to be precisely
because there is no movement to scope. The alternation follows from the role-scoped `who`:
roles alternate down a line, so naming one lands the facings in, out, in, out.

**Centre long wave** (`form_a_long_wave`, singular) — **role-scoped**. One role steps into
**c2** and waves down the middle of the set; the other role **holds its line**. c2 is exact —
no offset. A dancer walks in facing the way they walk, which alternates down the set for free
because consecutive ranks step in from opposite lines. Its `in` and `out` flags name the two
directions of traffic: who is going into the centre column and, if someone is already there,
who is returning to the sides.

The capacity arithmetic is what makes this work, and is worth stating because it is easy to
get wrong: a rank holds **two** dancers, but c2 holds **one**. A centre wave therefore
*cannot* be danced by everyone. Since every rank contains exactly one Lark and one Robin, a
**role-scoped** `who` puts exactly one dancer per rank into c2 — the counts match exactly.
This is why `form_long_waves` and `form_a_long_wave` carry role defaults (`role1s` and
`role2s` respectively) rather than `everyone`: the role scoping is structural, not stylistic.

```
centre long wave, who: role1s (Larks in, Robins hold their lines)

 R1-A  .   L1-A  .    .
  .    .   L2-B  .   R2-B
 R1-C  .   L1-C  .    .
  .    .   L2-D  .   R2-D
```

Some dances deliberately disobey the side/centre convention; those are **exceptions, not the
rule**, and the model should encode the rule.

### 8.5.6 Entering a wave by a quarter turn

`form_short_waves` is not the only way into a wave. A turning figure taken **a quarter past**
a whole or half turn leaves its pair a quarter of a rotation off square, and that quarter is
exactly the §8.5.1 offset — so the pair lands in a wave rather than anywhere the matrix
cannot express. This is ruled for **`do_si_do`, `allemande` and `shoulder_round`** — the three
turns that carry a usable direction token; every other member of the turn family still refuses
a quarter, each for its own reason (see `taxonomy.md`).

Four things define the landing:

**Along the set only.** The offset is a sideways step, so the turning pair must be
column-mates (facing each other along a line). An across-the-set quarter is refused
(`unsupportedParam`) — its dancers already sit on the two grid edges with nowhere to step.

**The direction token picks the wave.** `allemande`'s `hand` and the `shoulder` of `do_si_do`
and `shoulder_round` play the same part: `right` builds the canonical wave of §8.5.1, `left`
builds its mirror. Nothing new is stored — the landing is just the offset rule applied from
the pair's own facing.

**Rows never change.** A quarter slides each dancer one column toward the centre; it does not
collapse the pair into a single row. Two per row is what makes the shape a wave, and it is
the discriminator §8.5.4 relies on to tell a wave from a line of four.

**Three-quarters is a half and then a quarter — not the mirror.** The handedness is *not*
flipped. The half swaps the two couples between rows first, and the same handed quarter is
then applied from the cells they landed in, so the **other role** ends up in the centre.
`¼R ≠ ¾L`.

```
from the standard duple-improper start:

allemande/do si do RIGHT, 1¼          allemande/do si do RIGHT, 1¾
 .   R1-A  .    .   L1-A               .   L2-B  .    .   R2-B
L2-B  .    .   R2-B   .               R1-A  .    .   L1-A   .
```

**The wave owns the facing.** Whatever the figure would normally do to facing — `do_si_do`
preserves it, `allemande` rotates it, `shoulder_round` sets a determinate across-the-set
facing from the passing shoulder — is **overridden** on the quarter: every dancer takes
the wave's resting facing for the row they land in (§8.5.1 and §8.5.3, top row Down and
bottom row Up here). A wave whose dancers did not alternate would not be a wave, and that
property outranks the figure's own facing rule.

---

## 9. Starting Formations

| Formation | Description | Status |
|---|---|---|
| **Duple Improper** (our standard start) | 1s face down & normalize (Lark c4, Robin c0); 2s face up & normalize (Lark c0, Robin c4). Larks and Robins alternate down each line. | **Active** |
| **Duple Proper** | All Larks in c0, all Robins in c4. | Future |
| **Becket CW** / **Becket CCW** (two separate formations) | DI circled **left one place** — **partners share a column**, both lines facing **across (in)**. c4 = 1s line, c0 = 2s line. Direction sets progression sense (§10.6). Tracked as two formations for now (only two directions exist); easy to unify later. | **Active** |
| **Indecent** | Variant start. | Future |
| **Progressed Improper** | Variant start. | Future |

---

## 10. Progression

Over the course of an operation sequence, dancers move around within their hands four. At
one or more points the **1s end up below the 2s** within their h4. Progression is when
couples move on to new neighbors.

### 10.1 Progression is explicitly signaled — never assumed

Progression **does not** fire just because the state "looks progressed" (e.g. 1s below 2s).
The operation that performs the progression **carries a parameter that flags it as the
progression** (schema TBD with the taxonomy). There may be additional operations *after*
the 1s drop below the 2s and *before* the flagged progression actually happens. The
compiler must wait for the flag — **do not infer progression from matrix state.**

**A dance that claims a progression but flags none is refused.** The rule above cuts both ways:
if no figure carries the flag, the set never advances, and the dance cannot reach the state its
success criterion names. Left alone that surfaces as a *mismatch* after every figure has run,
which points at the choreography when the fault is the missing flag — so the compiler refuses
it up front instead, with `unperformedProgression`. This is the only **dance-level** error
kind: it is a fact about the figure list as a whole rather than about any one transition, so it
carries no figure index.

The flag is deliberately **not** inferred onto the last eligible figure. Which figure
progresses is choreography, and guessing it would turn a gap in a source record into a
silently different dance. Imported records do have that gap — the Caller's Box export of
*Sleepless at Pinewoods* declares a single-progression dance and flags nothing — and the
curated fixture differs from it by exactly that one flag, recorded as a divergence rather than
patched over.

### 10.2 What the progression operation does

When the flagged progression executes, the **couple** currently collected into the **top row
(row 0)** and the **couple** collected into the **bottom row (row N)** — and only those —
**normalize**:

1. **Turn to face along the set:** the row-0 couple turns to face **DOWN**; the row-N couple
   turns to face **UP**. (They have reached an end and turn back into the set.)
2. **Take the end's number:** both partners are set to the number belonging to the end they
   reached — see §10.2.2. (This *assigns*; it does not flip.)
3. **Normalize positions:** put the **Lark on the left relative to the new facing** (Robin
   right). Facing down ⇒ Lark→c4, Robin→c0. Facing up ⇒ Lark→c0, Robin→c4.

All **interior** rows are left **unchanged** by the progression step itself.

#### 10.2.1 Who normalizes — the couple with both partners in the end row

In **Duple Improper** the original wording was unambiguous: couples share a row, so row 0
holds exactly one couple. In **Becket**, row 0 can hold one dancer each from **two different
couples** (one per line), so "the row-0 couple" needed a referent.

**Rule: an end normalizes only when exactly one couple has _both_ partners in that row.**
§10.6 describes the mechanic in exactly these terms — *"a **couple** that reaches an end
**collects into that end row**"* — and in all five documented reference states (§10.5 plus
§10.6's four CW/CCW × single/double) an end row holds both partners of one couple.

**Applicability test at each end row, independently:**

- Exactly **one couple has both partners** in the end row ⇒ normalize it per §10.2.
- **Anything else** — an empty row, a lone dancer, a **non-partner pair**, or a **line of
  four** (§8.1: two whole couples in one row is an entire hands four, not an end couple) ⇒
  **no normalization at that end.** This is a *silent skip*, not an error: the figure's own
  transform stands and later figures are expected to resolve the shape.

The two ends are evaluated separately; one may normalize while the other skips.

**Why both partners are required.** A number is a property of the **couple**, not of a
dancer. Writing it for both partners at once is what makes it *structurally impossible* for
this step to leave a couple holding two different numbers. The rejected alternative — a
**positional** rule that normalizes any opposite-role pair in the end row — does exactly
that in Becket: it would flip one partner's number and not the other's, so couple B could
finish a progression as `L1-B` in row 0 and `R2-B` in row 1. Nothing reads a desynchronized
number *today* (the DI branch of §10.3 is the only consumer, and the desync would only arise
in Becket, whose branch reads orientation), but `couplesDownTheSet` takes one partner's
number as the couple's, so the latent break is real.

> **Resolved — non-partner pairs waiting out.** There are dances in which the dancers standing
> out at an end are legitimately **not partners** (e.g. having chained with an end dancer,
> reuniting with their partner only later). **The Judge exhibits exactly this on its first
> time through:** immediately before its op-6 progression fires, row 0 holds `R2-D` + `L2-B`
> and row 5 holds `L1-E` + `R1-C` — neither pair is a couple. Its `after_6` state has whole
> couples B and E at the ends, so under this rule **petronella's own transform must be what
> collects them**, with normalization only tidying the result (consistent with
> `architecture.md` §3.2's ordering: figure transform first, end-normalization after).
>
> **This is now verified.** With `petronella` implemented, The Judge compiles end-to-end and
> every intermediate state matches its hand-traced fixture — including op 5, which leaves the
> non-partner pairs at the ends, and op 6, whose own transform collects whole couples B and E
> there before end-normalization runs (`test/golden/golden_dances_test.dart`). The prediction
> above held: the transform delivers the whole couples, and this rule only tidies them. Had it
> not, the rule would have skipped and The Judge would have failed loudly at a named fixture,
> rather than silently producing the desynchronized state the rejected positional rule would.
>
> Storing waiting-out state **per dancer** (§10.3) also makes a non-partner pair at an end
> directly representable, so nothing here depends on the pair happening to be a couple. The
> *marking* pass still requires a whole couple, by design — a number is a property of the
> couple, and writing it for both partners at once is what keeps the two in step.

#### 10.2.2 The end number is assigned by destination line, not flipped

A number identifies which **side of the progression** a couple is on: in Duple Improper,
which row of its hands four; in Becket, which **line** (§10.6: *"c4 = the 1s line, c0 = the
2s line"*). A couple sitting in an end row is **in transit between lines**, and its number
must match the line it is about to re-enter.

So the end number is **derived from the end reached**, not obtained by inverting whatever the
arriving dancers happened to hold:

| Formation | Runs off the top | Re-enters | **Top-end number** | Bottom-end number |
|---|---|---|---|---|
| **Duple Improper** | the 2s (they travel up) | as 1s | **#1** | #2 |
| **Becket CW** | c0, the 2s line | c4, the 1s line | **#1** | #2 |
| **Becket CCW** | c4, the 1s line | c0, the 2s line | **#2** | #1 |

**Becket CCW is the mirror, and this is easy to get wrong.** It is tempting to state the rule
as "the couple waiting out at the top is a #1 couple" — true for Duple Improper and for
Becket CW, but **false for Becket CCW**, where §10.6's own oracle puts `R2-A . . . L2-A` (a
**#2** couple) in row 0. In CCW the c4 line shifts *up*, so it is a 1s couple that runs off
the top, and it re-enters c0 as a **2**. The invariant is not "top is #1" — it is *"your
number matches the line you are re-entering."*

On every well-formed state this produces the same result as the older *"flip the number"*
wording, because a couple always crosses to the opposite line. Assigning rather than flipping
buys two things:

- **It is self-repairing.** If the arriving dancers somehow hold inconsistent numbers, the
  end normalization writes both to the correct value instead of preserving the inconsistency
  in swapped form.
- **It makes the step idempotent** — a true *normalization* rather than a toggle. Re-applying
  it to an already-normalized state is a no-op. The movement in a progression comes from the
  figure's own transform (§3.2), never from this step, so idempotence here is correct.

A useful consequence, with one caveat: the canonical Duple Improper **starting** formation
(§11) is already end-normalized in the **matrix** — position, number and facing all stand. Its
*waiting-out* state is not, and should not be: in Duple Improper every row holds a whole
couple, so the end rows always qualify for marking (§10.3.2). Normalization only ever runs
behind an explicit progression flag (§10.1), so a start state is never passed through it.

### 10.3 Governing rule — where the hands four begin

**A dancer standing out at an end of the set carries that fact as state** — `waitingOut`, held
on the dancer beside their facing (§6) rather than encoded in the matrix cell (§5). Hands-four
boundaries are read from it:

- A **waiting row** is a non-empty row in which *every* dancer present is standing out.
- The remaining rows, top to bottom, pair off into **bands** — `(0,1),(2,3),…` when nobody is
  out, `(1,2),(3,4),…` when a couple is out at each end.

This is **formation-independent**: Duple Improper and Becket differ only in how a couple is
oriented *within* a band (§10.3.1), never in where the bands fall. It is also **total** — it can
be evaluated against any state, which the rule it replaced could not.

> **Superseded — why numbers and orientation could not be the signal.** This section previously
> read couple **numbers** in Duple Improper (top two alternate ⇒ bands begin at row 0; top two
> match ⇒ they begin at row 1) and couple **orientation** in Becket (a couple collected into the
> end row is waiting out). Both are only evaluable on a *settled* shape — and every state a
> figure actually sees is mid-dance. Measured against the golden fixtures, both returned
> "unresolvable" on **every** intermediate state. After The Baby Rose's circle, row 0 holds
> `R2-B` and `L1-A` — two different couples carrying two different numbers, so "the row's
> number" has no referent. In The Judge's `after_5_petronella`, couple D spans rows 0 and 2,
> which is not a column. Waiting-out state is carried on the dancer, so it survives whatever
> shape a figure leaves the set in.

> **A line of four is no longer a special case.** §8.1 puts a whole hands four in one row,
> leaving its partner row **empty**. An empty row is *not* a waiting row — nobody is standing
> out — so the band survives intact, and the "not defined over transient forms" caveat this
> section used to carry is gone.

#### 10.3.0 The two phases, and what moves between them

The two band arrangements above are the grid's only two **phases** — *aligned* (`(0,1),(2,3),…`,
nobody out) and *shifted* (`(1,2),(3,4),…`, the end rows stranded). Three things move the set
between them, and they are worth keeping distinct:

| What | Advances by | Why |
|---|---|---|
| The **progression** (§10.2's end-normalization) | one phase | the change-over: the couples who have served re-enter, and a fresh whole couple at each end takes its end number and stands out |
| `slide_along_set` | one phase | the slide carries everyone one row along, so the boundaries fall between different rows. It **is** the progression, so a progression flag on it adds nothing |
| A figure naming a **distance** set (`nextNeighbors` and friends) | *nothing*, unless it also carries the progression flag — in which case, one phase | reaching is **transient**: the figure is danced *d* phases from the one it was handed and always hands that phase back. A progression flag on top names movement the reach did not make, so a flagged reaching figure advances once |

**Reaching is decided by parity, not by history.** A distance-*d* set is danced *d* places from
the current phase, and since there are only two phases, only `d.isOdd` survives: odd distances
dance in the other phase, even ones in the phase they were given. What matters is that the
phase is always **handed back** — that is what lets a figure list reach out along the set and
then *retrace*. An earlier rule kept the toggle whenever the figure had moved somebody, which
works once and cannot walk back: *Sleepless at Pinewoods* reaches the fourth neighbors with a
whole-turn allemande that moves nobody, and a history-based rule undoes that step out and sends
the return leg onward instead of back. See `docs/taxonomy.md`, "The neighbor-distance sets",
for the worked trace, the resolution rule and the refusals.

#### 10.3.1 Couple orientation within a band

Still formation-dispatched, and still worth stating, because figures need it even though
grouping no longer does:

| Formation | Couples in an h4 |
|---|---|
| **Duple Improper** | share a **row** |
| **Becket** | share a **column** |

What is true in **both** is that **a couple waiting out always shares a row.** A waiting-out
couple has to fit into the empty space at the top or bottom of the set, and lying along the end
row is simply the best way to do it.

#### 10.3.2 The change-over — how a couple stops waiting out

A couple standing out is outside every active hands four, so **no figure's transform touches
it**: it is still sitting in the end row when the next progression fires. Something has to bring
it back in, and that something is the progression itself. §10.6 fixes the term: **wait-out lasts
one round.** So each progression, in order:

1. **Clear** — every dancer currently marked as waiting out has served their round and re-enters
   the set.
2. **Mark** — the sole whole couple at each end (§10.2.1) is normalized and marked as waiting
   out, **unless it is one of the couples just cleared.**

The exemption in step 2 is load-bearing: without it the same couple would be re-marked at every
progression and wait out forever. Worked through on a four-row Duple Improper set:

| | Marked before | After the figure's own transform | Result |
|---|---|---|---|
| **Progression 1** | nobody | B / A / D / C | mark B and C ⇒ one active band `(1,2)` = A, D |
| **Progression 2** | B, C | B / D / A / C | clear both, both exempt ⇒ nobody marked; bands `(0,1)` = **B, D** and `(2,3)` = A, C |

Note what the second row shows. The progression figure can only reach the active band, so it
swaps A and D and leaves B and C exactly where they stand; the change-over is what puts B back
into a hands four — with D.

> **The marking rule is deliberately positional**, not "is this couple already in a complete
> band?" In Duple Improper *every* row holds a whole couple, so an end row always qualifies. The
> tempting refinement — skip an end couple that already sits in a complete band — would break
> §10.5, where B is banded with A and nonetheless waits out. Normalization only ever runs behind
> an explicit progression flag (§10.1), so a start state is never passed through it.
### 10.4 End vs. middle — the mechanical difference

- **Ends (row 0 & row N):** take that end's number (§10.2.2 — assigned, not flipped), turn to
  face into the set, re-normalize, and (per §10.3) drop out of the active h4 for a round —
  waiting at the very top / bottom.
- **Middle:** interior couples keep their number and facing, but because the end couples
  drop out, the interior couples **re-pair with the couple from the adjacent original h4** —
  i.e. they meet new neighbors. This is the essence of progression.

### 10.5 Canonical example (2 h4)

Pre-progression
`[[L2-B,0,0,0,R2-B],[R1-A,0,0,0,L1-A],[L2-D,0,0,0,R2-D],[R1-C,0,0,0,L1-C]]`
(down the set: B#2, A#1, D#2, C#1 — top two alternate ⇒ h4s (B,A) and (D,C).)

Apply progression → row 0 (B) and row 3 (C) normalize; A, D unchanged:
`[[R1-B,0,0,0,L1-B],[R1-A,0,0,0,L1-A],[L2-D,0,0,0,R2-D],[L2-C,0,0,0,R2-C]]`
(down the set: B#1, A#1, D#2, C#2 — top two match ⇒ first h4 begins at row 1: active h4
**(A,D)**; **B** waits at the top, **C** waits at the bottom.)

### 10.6 Becket progression — oracle (net displacement)

> **What this section computes.** This is the **success-oracle / net displacement** for one
> Becket progression (used to compute `expected` for `Becket CW/CCW × count`, architecture
> §3.4). It is **not** the per-figure progression mechanic. **A progression-flagged figure is
> DI-style by default** (the general §10.2 operation, state-driven) even in a Becket dance;
> the figures then reposition dancers onto their destined Becket side (partners together). The
> **only** figure that progresses by an explicit column slide is **`slide_along_set`** (others
> like single-file promenades TBD). Either way, the **final** state after all figures must equal
> this net-displacement oracle.

Becket differs from DI in orientation: a **DI couple is horizontal** (partners in one row,
different columns), whereas a **Becket couple is vertical** (partners in one **column**,
different rows). The Becket start (§9) is DI circled left one place, both lines facing
**across (in)**: **c4 = the 1s line, c0 = the 2s line**.

**Net displacement of one Becket progression (derived + verified against all four CW/CCW ×
single/double reference states):**

- Each couple shifts **one row along its column**. Direction is set by the Becket sense:
  - **CW** (couples progress to their **left**): **c4 line shifts DOWN, c0 line shifts UP**.
  - **CCW** (progress to their **right**): the mirror — **c4 line shifts UP, c0 line shifts DOWN**.
- A couple whose partners both remain on the grid stays a normal **vertical side-couple**.
- A couple that reaches an **end** collects into that end row, **takes that end's number**
  (§10.2.2 — for **CW**, top ⇒ #1 and bottom ⇒ #2; for **CCW** the mirror, top ⇒ #2 and
  bottom ⇒ #1), and **normalizes across the row facing into the set** — exactly like the DI
  end-normalization (top → face down, Lark c4 / Robin c0; bottom → face up, Lark c0 /
  Robin c4). It then re-enters on the **opposite line**, where that number is the line's
  number (a 1 travels down c4; a 2 travels up c0 — reversed for CCW).

This makes the two lines **counter-shift** past each other; the couple leaving one line's end
crosses to the other line. h4 grouping after a Becket progression follows the same
number-derived rule as §10.3.

**Worked reference — Becket start**
`[[L2-B,0,0,0,R1-A],[R2-B,0,0,0,L1-A],[L2-D,0,0,0,R1-C],[R2-D,0,0,0,L1-C]]`
(c4/1s line: A r0-1, C r2-3 · c0/2s line: B r0-1, D r2-3)

- **CW + Single:** `[[R1-B,0,0,0,L1-B],[L2-D,0,0,0,R1-A],[R2-D,0,0,0,L1-A],[L2-C,0,0,0,R2-C]]`
  — A↓(r1-2), D↑(r1-2) form the active h4; B→top (2s→1s), C→bottom (1s→2s).
- **CW + Double:** `[[L2-D,0,0,0,R1-B],[R2-D,0,0,0,L1-B],[L2-C,0,0,0,R1-A],[R2-C,0,0,0,L1-A]]`
  — full formation restored (D+B r0-1, C+A r2-3); B re-entered c4, C re-entered c0.
- **CCW + Single:** `[[R2-A,0,0,0,L2-A],[L2-B,0,0,0,R1-C],[R2-B,0,0,0,L1-C],[L1-D,0,0,0,R1-D]]`
  — mirror: A→top (1s→2s), D→bottom (2s→1s); B↓, C↑ form the active h4.
- **CCW + Double:** `[[L2-A,0,0,0,R1-C],[R2-A,0,0,0,L1-C],[L2-B,0,0,0,R1-D],[R2-B,0,0,0,L1-D]]`.

> **Success-criterion note (architecture §3.4):** for Becket, the reference oracle applies
> `count` Becket-progressions in the formation's **direction** (CW/CCW). The direction is
> carried by the **formation** (`Becket CW` and `Becket CCW` are **two separate formations**);
> the criterion supplies only the **count** (single/double/…).

> **Confirmed:** Becket-start **facing** is **across/in**; **direction** = two separate
> formations (`Becket CW`/`Becket CCW`); **wait-out** = one round, DI end-mechanics (duple).

> **REFINEMENT — progression defaults to DI-style; column-slide is a specific figure
> (confirmed).** A progression-flagged figure runs the **general DI-style** end-normalization
> (§10.2, state-driven) **by default — for Becket too**; the remaining figures then reposition
> dancers onto their destined Becket side (partners together). The **column slide** happens
> **only** via the dedicated figure **`slide_along_set`** (`slide:[left/right]`, `beats`,
> progression-capable) — the sole known case; other single-file-promenade-like figures will be
> called out as encountered.
>
> Consequences: (1) normalization derives from **actual positions/facing**, not a fixed row
> rule; (2) the state immediately after a progression-flagged figure need not look "done" —
> only the **final** matrix (after all figures) is compared to the oracle (§10.6); (3) §10.6 is
> the **oracle/net-displacement**, not the per-figure mechanic.

> **Cross-check (verified).** A `Becket CW` dance whose only figures are progression-flagged
> `slide_along_set`s compiles clean against this oracle at both `count: 1` and `count: 2` — the
> CW+Single and CW+Double reference states above are reproduced exactly by the figure's own
> mechanic. So **`slide:left` ↔ the CW sense**, and `slide:right` ↔ CCW. The figure and this
> oracle were derived independently, which is what makes the agreement worth something.
>
> The `count: 2` case additionally exercises the figure's **re-banding**: the second slide has
> to bring the couples the first one stranded back into the set rather than trading them for a
> fresh pair. See `taxonomy.md` → `slide_along_set` → *re-banding*, and note the ⚠️ there — the
> phase rule is load-bearing and held at moderate confidence.

---

## 11. Worked Example — 8 dancers at the standard start (2 h4, 4 couples ⇒ 4×5)

Matrix (decimal), empty rows not represented:
`[[10,0,0,0,9],[21,0,0,0,22],[34,0,0,0,33],[69,0,0,0,70]]`

**① Decimal**

```
       c0    c1    c2    c3    c4
 r0    10     0     0     0     9
 r1    21     0     0     0    22
 r2    34     0     0     0    33
 r3    69     0     0     0    70
```

**② Bitmask** (7-bit = 4 couple-id + 1 number + 2 role; `0000000` = empty)

```
        c0        c1        c2        c3        c4
 r0  0001010   0000000   0000000   0000000   0001001
 r1  0010101   0000000   0000000   0000000   0010110
 r2  0100010   0000000   0000000   0000000   0100001
 r3  1000101   0000000   0000000   0000000   1000110
```

**③ Role / Number / Identity** (`·` = empty; facing overlay from initial state: 1s ↓, 2s ↑)

```
        c0        c1    c2    c3      c4
 r0   R1-A ↓      ·     ·     ·     L1-A ↓
 r1   L2-B ↑      ·     ·     ·     R2-B ↑
 r2   R1-C ↓      ·     ·     ·     L1-C ↓
 r3   L2-D ↑      ·     ·     ·     R2-D ↑
```

Decode check (r3c0 = 69): `69 = 1000101` → couple-id `1000` = **D**, number bit `1` = **#2**,
role `01` = **Lark** ⇒ **L2-D**. ✓

Couple-id / decimal reference (9-bit, 6-couple set for §10 demonstrations):
A→8, B→16, C→32, D→64, E→128, F→256; add +4 for #2, +1 Lark, +2 Robin.

---

## 12. Open / Deferred Decisions

Resolved since this list was written, kept here as a pointer to where each landed:

- **Facing storage** — **decided:** carried on `DancerState` beside the position, outside the
  encoded cell value, so it is excluded from success comparison for free. `waitingOut` is held
  the same way and for the same reason. *(§6; `lib/src/domain/dancer.dart`)*
- **Across-facing normalization** — **decided:** implemented by the starting formations and the
  shared transforms as the figures that use it were defined. *(§8;
  `lib/src/domain/starting_formations.dart`, `lib/src/ops/transforms.dart`)*
- **Guiding design principle** — **decided:** stateless functional core; see `architecture.md`.
- **Operation taxonomy** — **defined**, and now the largest document in the set: see
  `taxonomy.md` for the figures, their params and their effects, and §10.1 here for the
  `progression` flag that marks the progressing figure. Individual figures remain deferred
  within it; the taxonomy marks each one.
- **Success-criteria taxonomy** — **defined:** a sealed `SuccessCriterion` hierarchy, with
  `ProgressionCriterion(count:)` covering single and double. *(`lib/src/engine/success_criterion.dart`)*

Still open:

- **The wave formation** — **geometry settled (§8.5) and three of its five figures built.**
  `form_short_waves`, `form_long_waves` and `form_a_long_wave` now implement it. §8.5 fixes the
  representation — the facing-relative offset for short waves, c0/c4 in place for side long
  waves, c2 role-scoped for a centre long wave, concrete alternating facing, automatic
  normalization on exit, and no stored wave flag. What remains is **worked examples** for the
  two figures still held (`pass_the_ocean` — held on its across-facing entry state, not on the
  wave model — and `rory_o_more`), and a ruling on **quarter turns**: the representation now
  exists to land one in, but where exactly a ¾ allemande leaves each dancer is still unasked.
  *(§8.5)*
- **Non-duple formations** — triple, 3×3, 4×4, others: deferred. Their operations generally do
  **not** match duple results, so each needs its own set of definitions rather than a reuse of
  these. *(§2)*
- **Becket + reaching** — *the reach half is closed; a non-zero Becket reach is still untested.*
  Distance sets are absolute (taxonomy, "The distance sets are absolute"), so a figure naming one
  after a progression has less ground to cover. *March for Andrea* — the first worked example of a
  distance set from a Becket start — names `nextNeighbors` *after* its progression, so the gap
  closes to nothing, the figure is danced in place, and the dance sizes to the base two. It
  compiles.
  That example was also, for a while, read as a **placement** bug: the dance ran to completion but
  landed one line off, couple A finishing on the c0 line having started on c4. It was not an engine
  fault. The record's `roll_away` named `nextNeighbors` as **`who`** — actor context, which
  `RollAway` does not act on — leaving **`whom`** on its `partners` default, so the wrong pair
  traded and the two active couples came out mirrored. Corrected to `who: role1s, whom:
  nextNeighbors`, it lands on the oracle exactly. Worth recording because the failure was silent:
  a well-formed figure, a legal `who`, a dance that ran to the end.
  What is still genuinely untested is a Becket dance that names a distance set **before** its
  progression, where the effective distance is non-zero and the cross-hands-four reach actually
  runs. The standing suspicion is that `travelDirection` reads Becket travel from `position.col` —
  a *here* quantity — while the grouping arithmetic it is compared against is a *home* quantity.
  No corpus dance exercises it yet, so it is unresolved rather than disproved. *(§10.3.1)*
