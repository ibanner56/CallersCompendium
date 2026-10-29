# Design: The add-to-program sheet

*Design note for audit finding FIND-17, drafted 2026-10-29 against `main` at
`acacb05`. **Status: proposal.** Nothing here is built, and nothing here is a
maintainer decision except where a line says so. The maintainer asked for this
note ("design note now") in the 2026-10-29 decisions; the choices below are
recommendations, and §8 lists the ones that need an answer. Conforms to
[ux.md](ux.md) and the [accessibility baseline](../research/accessibility-baseline.md).*

## 0. Summary

The sheet that opens from a dance's row menu and from the dance detail screen
lists every program in one flat list. It has no search, no status, no sign that
a program already holds the dance, and no "new program" button once any program
exists. The editor's dance picker, which solves the mirror-image problem, does
better on all of these.

This note proposes four changes to the sheet and leaves its behaviour on tap
alone:

1. **Order and group.** Programs you can still plan open first, soonest event
   first. Performed programs follow, collapsed behind one row.
2. **Search.** A search field, shown once the list is long enough to need one.
   It matches title and venue, and folds case and accents.
3. **An "already contains" marker**, with the same icon and count the picker
   uses. Tapping a marked program still adds the dance.
4. **"New program with this dance" pinned above the list,** always.

It changes no stored data, adds no setting, and adds no record kind. It does
not touch the sheet's Undo (F11 owns it), the Save/New/header conventions
(D-11 is open), or the batch version of the sheet (N4).

## 1. What the sheet does today

`showAddToProgramSheet` (`app/lib/src/widgets/add_to_program_sheet.dart:22`) has
two callers: the Collection row's menu
(`app/lib/src/screens/dance_list_screen.dart:3123`) and the dance detail screen
(`app/lib/src/screens/dance_detail_screen.dart:627`). Both pass a dance id and
title.

| Behaviour | Where | Notes |
| --- | --- | --- |
| Loads every non-deleted program once, when the sheet opens. | `add_to_program_sheet.dart:28`; `ProgramRepository.listAll` (`program_repository.dart:724`) excludes soft-deleted programs by default | A snapshot. It does not update if a sync lands while the sheet is open. |
| Sorts by `updatedAt`, newest first. | `add_to_program_sheet.dart:30` | Edit time, not event time. A program edited yesterday for last month's gig ranks above next week's. |
| Shows no status and no filter. | `:94-143` | The Programs list shows a status chip with icon and text (`program_status_chip.dart:9-27`). The sheet does not. |
| Subtitle is the event date plus `collectionDanceCount(program.slots.length)`. | `:107-117` | Counts every slot, including breaks and alternates. The Programs list counts `plannedDanceCount` (`program_list_tile.dart:44`; `program.dart:370`). F10 (GIG-10) owns this. |
| Offers "Create a new program with this dance" only when there are no programs. | `:61-70`, `:147-191` | |
| Tapping a row appends one slot at the end, closes the sheet and shows an Undo snackbar. | `:196-245` | Re-reads the program, then calls `programs.update`. |
| The sheet is at most 70% of the screen height and has no text field. | `:44` | Nothing in it pads for the on-screen keyboard, because it has never needed to. |
| New program: creates a draft titled `programsNewProgram`, with this dance as slot 0, then a snackbar with no Undo. | `:250-276` | |

For comparison, the editor's picker shows an in-program icon and a count for
every dance already in the program being built
(`collection_picker.dart:1005-1047`). Its counts come from
`_danceSlotCounts` (`program_editor_screen.dart:2220`), which counts **every
slot that has a dance id, alternates included**, and skips break and free-text
slots.

The user guide describes the sheet in one line: "drop it into a program you are
building" (`docs/user/collection.md:306`).

## 2. Constraints

| Constraint | Source | What it means here |
| --- | --- | --- |
| Undo everywhere; confirm only where Undo is impossible. | `ux.md:192-193` | A duplicate add is not destructive and has an Undo, so it needs no confirmation (§4.3). |
| The sheet's Undo is fixed by F11 (GIG-19), which makes it compare-and-replace. | `batch-plan.md:256-263` (F11), `:263` (GIG-19) | This note must not redesign it. The sheet branch lands after F11, and takes F11's Undo as given. |
| Counts use `plannedDanceCount`. | `batch-plan.md:238-247` (F10, GIG-10); `program.dart:370` | The sheet's subtitle reads that getter. F10 edits `add_to_program_sheet.dart:107-116`, so the sheet branch lands after F10. |
| Phone layout follows U7. | `decided-work-plan.md:841-854` (N3) | U7 had not merged at `acacb05`. The sheet branch lands after it (§7). |
| Touch targets are at least 24 px, and 44 pt preferred on touch surfaces. | `accessibility-baseline.md:29`, `:51` | The new rows and the search field follow the same sizing as the existing `ListTile`s. |
| State is not colour-only. | `program_status_chip.dart:9-12`; `ux.md` cross-cutting rules | The marker uses an icon and text, as the picker's does. |
| Persisted state needs a registry entry on all three axes, in the same PR. | `AGENTS.md:86`; `.github/instructions/privacy-registry.instructions.md:29` | This design persists nothing (§4.6), so it adds no entry. |
| A new record kind or merge goes through sync-spec §6.6 and §6.15. | `sync-spec.md:3197`, `:4417` | This design adds neither, so both are out of play (§4.7). |
| D-11 (Save, New, header placement) is open. | `maintainer-decisions-2026-10-29.md:59` (D-11); the decision to write this note is `:352-355` | The pinned "New program" row is inside the sheet. It does not decide where New sits on any screen. |
| A new string needs keys in all six ARBs, beside related keys, and a `changelog.d` fragment. | `decided-work-plan.md:11-16` (conventions) | Listed in each branch (§7). |

The `batch-plan.md`, `decided-work-plan.md`, `maintainer-decisions-2026-10-29.md`
and `reports/FIND.md` citations are to the audit branch
(`claude/app-audit-categories-k2pdon`, under `docs/dev/audits/2026-10-behavior/`),
which is not on `main` yet. Their line numbers are for that branch. Every other
citation is against `main` at `acacb05`.

## 3. Questions in the audit's FIND-17, and short answers

| Question | Recommendation | Section |
| --- | --- | --- |
| Should the sheet have search? | Yes, once the list passes a threshold. | §4.1 |
| Should it hide past or Performed programs, and in what order? | Group, don't hide. Open programs first, Performed collapsed. | §4.2 |
| Should it mark programs that already contain the dance? | Yes: icon, text and count, same as the picker. Still add on tap. | §4.3 |
| Should it always offer "new program with this dance"? | Yes, as a pinned first row. | §4.4 |

## 4. The design

### 4.1 Search

**Today:** none, and the Programs list itself has no text filter either, only a
sort (`program_sort.dart:12-24`). A caller with 80 programs scrolls an
edit-time-ordered list.

**Options**

| | Option | Trade-off |
| --- | --- | --- |
| A | Never show search. | Cheapest. Leaves the 80-programs case as it is. |
| B | Always show a search field. | One rule, no layout jump. On a phone, it spends a row on the common 3-program case and pulls the keyboard up if it takes focus. |
| C | Show it only above a threshold (*recommended: 8 programs*). | The common case stays compact. The threshold is a number nobody can justify exactly; it is a UI tuning value, not a data rule. |

**Recommendation: C.** At roughly 56 px a row, about eight rows fit on a phone beside
the pinned New row and a title bar, so below that there is little to search
for. *(My estimate; the build should check it at 360×640.)*

**What it matches.** Title and the resolved venue label, folded with
`foldForTitleMatch` (`packages/compendium_core/lib/src/search/title_match.dart:21`).
That helper is the one the command palette already uses on program titles
(`command_palette.dart:162`), so the sheet adds no seventh matcher to the six
the audit counted (`FIND.md`, cross-cutting pattern 1). Order within results
follows §4.2; match rank (`rankTitleMatch`) is not used, because with a handful
of matches the grouped order is more useful than "exact first".

The venue label means resolving a linked venue the way the Programs list does
(`resolveVenueLabel`, used at `program_list_tile.dart:55`). The sheet does not
load venues today (`add_to_program_sheet.dart:28` reads only programs). Loading
them adds one read when the sheet opens. If the maintainer prefers a
title-only match, that drops the read and the venue-name cases ("the Tuesday
night at X") at once.

**Focus.** Do not autofocus on a phone: the keyboard would cover the list the
user came to see. On desktop and tablet-with-keyboard, autofocus is fine.
*(My call: autofocus by platform class is a detail for the build session to
confirm against U7's layout rules, so it is not on the §8 list.)*

**State.** The query lives in the sheet's `State` and is gone when the sheet
closes. It is never persisted (§4.6).

### 4.2 Hiding past or Performed programs, and the order

**Why this matters beyond tidiness.** Adding a dance to a Performed program
leaves the new slot unperformed: the performed stamp is applied only on the
*transition* to Performed (`program_repository.dart:548-565`). Yet by default
any program that contains a dance counts as calling it
(`docs/user/programs.md:452-455`). So a mis-tap on last month's gig quietly
adds a "called" entry to that dance's history. Nobody sees it until the history
looks wrong.

**What "past" can mean.** Only status is an explicit, user-set signal
(`enums.dart:22`: `draft`, `finalized`, `performed`). `eventDate` is optional
(`program.dart:280`) and a date-only value, so "before today" depends on the
device's local day. A Draft with a past date is as likely to be a set list
someone is writing up after the fact as a stale one.

**Options**

| | Option | Trade-off |
| --- | --- | --- |
| A | Keep one flat list. | No change, no risk. The mis-tap hazard and the long list stay. |
| B | Hide Performed programs behind a "Show performed" toggle in the sheet. | Hides the hazard. A caller who wants to add a forgotten dance to last night's program must find the toggle. Needs a per-open default. |
| C | Group: open programs first, then one collapsed "Performed (N)" row that expands in place. **(Recommended)** | Everything stays reachable in two taps. The expanded-or-not state is session-only. Costs one extra row and a little layout code. |
| D | Hide any program whose event date is before today. | Relies on the optional date and the device's day. Hides undated stale drafts not at all and some live ones wrongly. Rejected. |

**Recommendation: C.** It treats status, which the user set, as the signal. It
answers the hazard by demotion rather than removal, because adding a dance to a
Performed program is legitimate (the dance you forgot to log).

**Rules for C**

- **Open group:** every program whose status is not Performed (Draft,
  Finalized).
- **Performed group:** a single row, "Performed (N)", with a chevron, below the
  open group. Tapping it expands the programs in place. They keep §4.3's marker.
- **Auto-expand** the Performed group when (a) there is no open program, or (b)
  a search query is non-empty and matches only Performed programs. A caller
  searching for a program by name must not be told "no results" while a match
  sits in a collapsed group.
- **Order inside the open group** *(recommended; alternatives in §8)*: programs
  with an event date today or later, soonest first; then everything else
  (undated, or dated earlier and not Performed), by `updatedAt` descending, as
  today. The soonest gig is the likeliest target; the fallback keeps today's
  behaviour.
- **Order inside the Performed group:** event date descending, undated last
  by `updatedAt`. The most recent gig is the likeliest forgotten-dance target.
- **Status is shown** on every row, using `programStatusPresentation`
  (`program_status_chip.dart:9-27`) so the sheet and the Programs list name
  statuses identically. In the open group a status chip separates Draft from
  Finalized. In the Performed group it is redundant but harmless; the build may
  omit it there.

### 4.3 The "already contains" marker

**Behaviour.** A program that holds the dance in any slot shows the picker's
in-program icon and, when the dance appears more than once, its count
(`collection_picker.dart:1005-1047`), plus the text "In this program" or "In
this program ×N" in the subtitle. The row's semantic label gains the same
information (`programsAddDanceToProgramSemantic` takes its details as a single
string, `add_to_program_sheet.dart:121-125`, so the build can add it there; the
visible text is a new ARB key).

**What counts.** Every slot with this dance id, alternates included. That is
`_danceSlotCounts`' rule (`program_editor_screen.dart:2220-2226`), and it
matches the question the marker answers: "will I duplicate this dance?" It is
deliberately not the calling-history rule, under which an alternate counts only
once performed (`docs/user/programs.md:459-463`). A dance that is already the
fallback in a program is still one the caller may not want to add again.
Free-text slots that name the dance but carry no dance id are not detected,
exactly as in the picker.

**One rule, one implementation.** The count belongs in core, as one getter on
`Program` (for example `danceSlotCount(String danceId)`), so the picker, this
sheet and N4's batch version read the same definition. The picker's local
`_danceSlotCounts` then becomes a loop over that getter. The two surfaces
today agree only because nobody has changed either.

**Options for tapping a marked program**

| | Option | Trade-off |
| --- | --- | --- |
| A | Add anyway, with the marker as the only warning. **(Recommended)** | Matches the picker, which adds on every tap and shows the count. A repeated dance (a reprise, a second-half repeat) is legitimate. Undo is one tap. |
| B | Add anyway but ask first ("Already in Friday dance. Add again?"). | Safer for a mis-tap. Violates "confirm only where Undo is impossible" (`ux.md:192-193`) and adds a step to a legitimate repeat. |
| C | Block the tap. | Removes a legitimate action. Rejected. |

**Order is not affected.** A marked program does not sort to the top or bottom.
Moving rows by a property the user is not looking at makes the list unstable
while they scan it.

### 4.4 "New program with this dance", always offered

**Options**

| | Option | Trade-off |
| --- | --- | --- |
| A | Pinned first row above the list, outside the scrolling region. **(Recommended)** | Always visible, including with the keyboard up and a long list. One row of height. |
| B | A footer button. | Scrolls out of sight, or reserves height at the bottom where the keyboard sits. |
| C | A "+" in the sheet's title row. | Compact, but an icon-only action on a sheet whose job is choosing a program is easy to miss, and needs a tooltip and semantic label of its own. |

**Recommendation: A.** The row is a `ListTile` with a leading `add` icon and
the existing label, `programsCreateWithDance`
(`add_to_program_sheet.dart:186`). The empty-state version keeps its teaching
text and button; the pinned row simply shows in both states, so the empty state
can drop its own button and reuse the pinned one. Behaviour is unchanged:
creates a Draft titled `programsNewProgram` with this dance as slot 0, closes
the sheet, shows the existing snackbar (`:250-276`).

**Not in scope:** the create path has no Undo today
(`add_to_program_sheet.dart:247-249` says the new program "can be deleted from
the programs list"; deletion is soft and restorable for 30 days,
`ux.md:192-193`). This note leaves that alone. It can be revisited with F11.

### 4.5 Layout on a phone

At 360×640 with the keyboard open, roughly 260 px of the screen remains. The
sheet's cap is 70% of the full height (`add_to_program_sheet.dart:44`), so the
sheet would be sized for a screen that is no longer there, and the pinned New
row, the search field and two or three rows would not fit.

**Recommendation:** size the sheet from the *available* height, that is, the
screen height minus `viewInsets.bottom`, and add the bottom inset as padding.
`isScrollControlled: true` is already set (`:41`), which is what lets the sheet
use more than half the screen. Pin New above the list and the search field
below it; the list is the only part that scrolls. The build must have a widget
test at 360×640 with a simulated keyboard inset, and one at 200% text scale.

U7 owns the phone-layout rules for shared widgets. This note states what the
sheet needs; U7's result decides the exact margins and any shared sheet
helper, so the build reads U7's merged code first (§7).

On desktop and wide layouts the sheet stays a bottom sheet. Changing it to a
dialog or a popover is a separate question and no finding asks for it.

### 4.6 State and the privacy registry

Everything this design adds is session-only: the search query, whether the
Performed group is expanded, and the transient grouping. None of it is written
to the database or to settings, so the registry (`packages/compendium_core/lib/src/privacy/`)
needs no entry, and the ratchets stay quiet.

*Rejected alternative:* remember "Performed expanded" across opens. It needs a
settings key, which needs a registry entry on all three axes in the same PR
(`AGENTS.md:86`), and, if shareable, a
capability-gate decision (§4.7). The gain is one tap for a habit nobody has
asked for.

The snapshot rule stays: the sheet reads programs once on open
(`add_to_program_sheet.dart:28`). It is short-lived, and `_selectProgram`
re-reads the program it is about to change (`:207`). Making the list live
(`watchAll`, `program_repository.dart:836`) would reorder rows under a finger
and is not recommended.

### 4.7 Sync

The only write is the one the sheet already makes: an ordinary program update,
or a new program. No new record kind, no new merge, no new shareable setting.
Sync-spec §6.6 (collision reconciliation, `sync-spec.md:3197`) and §6.15 (the
capability gate, `sync-spec.md:4417`) therefore do not apply.

One adjacent point for F11 rather than this note: the append is read, modify,
write (`add_to_program_sheet.dart:207-221`), not a compare-and-replace
(`replaceIfUnchanged`, `program_repository.dart:358`). A concurrent edit to the
same program between the read and the write could be lost. F11 fixes the
*Undo* (GIG-19); whether it also moves the *append* to `replaceIfUnchanged` is
its call. This note's design works either way.

### 4.8 The batch case (N4) and the sheet's API

N4 lists "add to program" among the batch actions. This note does not design
it. It asks only that the build keep the sheet's parts reusable: the program
list (grouping, search, marker, pinned New row) lives in its own widget that
takes a list of programs and the dance id(s) to test for "contains". Whether
the marker for a multi-dance selection means "all", "some" or "none" is N4's
question. `showAddToProgramSheet`'s signature stays as it is, so its two
callers are unchanged.

## 5. Docs the change touches

- `docs/design/ux.md` §1 and §2 (`:59-60`, `:71`): one line each saying the sheet
  groups, searches and marks. No other section changes.
- `docs/user/collection.md:306`: describe the grouping, the marker and the
  always-available "new program" row. `docs/user/` is the single source of the
  in-app bundle, so the `user-docs` gate covers it.
- `docs/user/programs.md`: a sentence under the calling-history section that
  adding a dance to a Performed program does not mark it performed.
  *(That is already true; the sheet change just makes it reachable by design
  rather than by accident, so it deserves a line.)*

## 6. Tests the build must include

A guard test must be shown to fail (`AGENTS.md:104`).
For each, the mutation it must catch:

| Test | Mutation it catches |
| --- | --- |
| A Performed program does not appear above an open one, whatever its `updatedAt`. | Grouping removed, or sorted by `updatedAt` only. |
| The Performed group auto-expands when a query matches only Performed programs. | Auto-expand removed. |
| A program holding the dance only as an alternate shows the marker. | Marker counting primaries only. |
| Tapping a marked program still adds a slot and shows the Undo snackbar. | Tap blocked or gated. |
| "New program" is present with 0, 1 and 100 programs. | Row shown only when empty. |
| Search folds case and accents ("ecole" finds "École"), and matches a venue name. | Plain `contains`; title-only match. |
| At 360×640 with a keyboard inset, the New row, the search field and one program row are all visible. | Sheet sized from full height. |
| The marker count equals the picker's count for the same program. | Two implementations drifting. |

## 7. Proposed branch breakdown

Format follows `decided-work-plan.md`. Size counts changed lines, tests
included: S < 150, M 150–400, L 400+. The branch names are proposals.

| # | Branch | Items | Main files | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- | --- |
| N3-1 | `feat/add-to-program-contains-and-new` | Marker (§4.3), shared `Program` count getter, picker switched to it, pinned New row (§4.4), subtitle on `plannedDanceCount` if F10 has not already moved it | `widgets/add_to_program_sheet.dart`, `widgets/collection_picker.dart` (the count source only), `program_editor_screen.dart` (`_danceSlotCounts` → the getter), `packages/compendium_core/lib/src/model/program.dart`, six ARBs, `docs/user/collection.md`, `docs/design/ux.md`, `changelog.d/` | M (~280) | Sonnet | F10, F11 (both edit the sheet), U7 |
| N3-2 | `feat/add-to-program-order-and-search` | Grouping and order (§4.2), status on rows, search (§4.1), available-height sizing (§4.5), extract the list widget (§4.8) | `widgets/add_to_program_sheet.dart`, a new list widget beside it, `program_status_chip.dart` (reuse only), six ARBs, `docs/user/collection.md`, `docs/user/programs.md`, `changelog.d/` | M (~350) | Sonnet | N3-1 (same file); U7 for the phone sizing |

**Why two.** The first is a self-contained correctness improvement (a marker
that answers "will I duplicate this?", and a button that is always there). The
second changes the list's shape and adds the layout work. Splitting keeps each
diff reviewable and lets the first ship if the maintainer wants a different
answer on grouping.

**Hot files.** `add_to_program_sheet.dart` is edited by F10 (`:107-116`) and F11
(`:233-241`) first. Both N3 branches must merge after them, and N3-2 after N3-1.
`program_editor_screen.dart` is a hot file (F10, U7, F11): N3-1's edit there is
a few lines at `:2220`, and should rebase last.

**No registry, sync or schema work in either branch.**

## 8. Decisions needed

These are the maintainer's. The recommendation is mine, not a decision.

1. **Performed programs (§4.2).** Group and collapse (C, *recommended*), hide
   behind a toggle (B), keep one flat list (A), or hide by event date (D,
   *not recommended*)?
2. **Order within the open group (§4.2).** Soonest event date first, then the
   rest by edit time (*recommended*), or edit time only, as today?
3. **Search (§4.1).** Show it above a threshold of about 8 programs
   (*recommended*), always, or never? And does it match venue names
   (*recommended*, costs one extra read) or titles only?
4. **A repeated add (§4.3).** Add anyway with the marker as the warning
   (*recommended*), or ask first?
5. **Where "New program with this dance" sits (§4.4).** A pinned first row
   (*recommended*), or a footer?
6. **Should alternates count toward the marker (§4.3)?** Yes
   (*recommended*: the marker asks "will I duplicate this?"), or only primary
   slots, to match calling history?

Not on this list because they are not open: Save, New and header placement
(D-11 is open and this note does not touch it) and the sheet's Undo (F11).
