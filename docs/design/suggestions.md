# Design: Suggest the next dance (Experimental)

*Issues #2343, #2344 and #2348 · built. The program builder's pickers can
order their results by how well each dance would fit where it will go (the
end of the program, a place an add before or after a slot lands, or the slot
Replace… fills), and say why; so can Perform's swap sheet, for the slot being
swapped (#2348). It sits behind Settings ▸ Experimental ▸ Suggestions,
off by default. The user-facing description is in
[programs.md](../user/programs.md#let-the-app-suggest-the-next-dance),
[perform.md](../user/perform.md#swap-a-dance) and
[settings.md](../user/settings.md#suggestions).*

## Shape

- **Core** (`packages/compendium_core/lib/src/analysis/`): a pure-Dart scorer,
  `rankSuggestions(SuggestionRequest) → SuggestionRanking`, and the stored
  settings, `SuggestionSettings` with `readSuggestionSettings` and
  `isValidStoredSuggestionSettings`. The request carries each dance as a
  `SuggestionCandidate`, only what the scorer reads (id, form, formation,
  level, phrase structure, figures and a revision), not the whole `Dance`
  with its notes, tunes and custom fields. `SuggestionCandidate.fromDance`
  makes one. The request takes the slots
  before and after the position, and whether the candidate takes an
  alternate's place (`candidateIsAlternate`); `SuggestionPosition` works those
  out for the end (`atEnd`), an add before or after a slot (`inserting`) and
  Replace… (`replacing`), which Perform's swap sheet (#2348) reuses for the
  slot being swapped. See "Positions" below.
- **App**: the picker takes an optional `PickerProgramContext` (the
  history-filters Q3 shape: program id, linked venue id, typed venue, plus the
  venue's display name and a `SuggestionPosition`). The builder's three
  mounts pass it: the inline pane and the bottom sheet with the end of the
  program, or, while an add before or after a slot (#2339) is pending, the
  place that add lands; and Replace… with the place of the slot being
  replaced (`ProgramSlotListEditor.onPickReplacementDance` passes the slot).
  Suggested is the last entry of the picker's Sort menu only while the toggle
  is on and a position is present. It is
  never in the Collection's sorts (`availableCollectionSorts` is unchanged),
  the builder's pickers never open in it, and it lasts until another sort is
  chosen or the picker closes.
- **Perform's swap sheet (#2348)** passes the place of the slot being swapped
  (`SuggestionPosition.replacing`, as Replace… does, so the dance being
  swapped out is neither a neighbour nor in the program compared with). With
  Suggestions and `suggestions_in_perform_swap` both on it offers Suggested
  and opens in it (`CollectionPicker.openSuggested`): from the start, after
  each Keep change (a new panel request) and when the setting is turned on
  while the sheet is open, until the caller picks a plain sort there. The
  pinned **Your alternates** are not ranked and stay first. With either off
  the picker gets `offerSuggested: false`, the sheet as #2346 built it. Off
  by default even with Suggestions on, so turning Suggestions on for the
  builder does not change Perform unasked (a drafting call in the issue,
  approved with it). *Rejected:* separate weights for Perform (one set is
  easier to understand), and the switch under Settings ▸ Program ▸ Perform
  mode (Experimental switches live in the feature's own section).
- **Off the UI thread**: the picker ranks on a `SuggestionWorker`, a
  long-lived isolate of its own, started the first time Suggested is chosen
  and stopped when the picker closes. Sending a message copies it on the
  calling isolate, and copying 20,000 dances' figures in one message held the
  UI thread for about 0.5 s (measured with `Isolate.run`, the first
  implementation). So the worker keeps every candidate it has been sent, by
  id and revision; it is sent only candidates it does not hold at that
  revision, 250 to a message with a turn of the event loop between messages,
  and then the request with the candidates as ids. A re-rank after a dance is
  added sends only the program and the ids.
  - **Revision.** `SuggestionCandidate.fromDance` hashes `updatedAt`, the
    form, formation, level and phrase structure, and the identity of the
    dance's figure list. Some bulk paths stamp `updatedAt` at whole seconds,
    so a stamp alone can stay the same across an edit; a `Dance` is immutable,
    so changed figures are always a new list. Hashing every figure's content
    instead cost about 40 ms per rank of 20,000 dances on the calling isolate;
    the identity costs nothing, and its price is that the same figures loaded
    again (a reload of the collection) are sent again.
  - **Only the newest call counts.** Each `rank` call supersedes every
    earlier one. An earlier call still sending chunks checks before each
    chunk, with no wait between the check and the send, and stops once a newer
    call has started, so it cannot send a candidate over the revision the newer
    call sent. The worker does not rank as each request arrives: it ranks the
    newest request waiting once the messages already queued are in, and
    answers the older ones as superseded. A superseded call fails with
    `SuggestionRankSuperseded`, which the picker ignores (the newer call
    reports). A request already being ranked when a newer one arrives still
    finishes, and the picker drops its result.
  - **Failure.** If the worker isolate fails or exits, every waiting call fails
    and the next call starts a new worker; a failed spawn closes its port. A
    worker disposed while still starting is stopped as soon as it exists.
  - **Known limit.** The worker keeps every candidate it has been sent for the
    life of the picker; nothing is evicted. A picker that is open for a long
    time over many different searches holds every dance it has ranked.

  Until the ranking comes back the list shows in the plain order, with the
  header's spinner, and every row still adds on tap. A newer search, a
  context change or leaving Suggested drops a ranking still in flight. A
  ranking is shown only for the results and the position it was made for, so
  when the position moves (an insertion started, retargeted or cancelled; a
  dance added) the plain order shows until the new position is ranked, and a
  ranking for the old position that comes back late is never shown. A
  failed ranking is logged and puts the list back in the plain order,
  dropping any earlier Suggested order of the same results, with a short
  notice above the list ("Couldn't rank these dances, so they're in their
  usual order.") until the next ranking succeeds or another sort is chosen.

## Factors

Each factor contributes signed effects; a dance's score is their sum. Each raw
effect is multiplied by the factor's weight: **Off** = 0 (the factor is not
evaluated), **A little** = 1, **A lot** = 3. Ties keep the plain order of the
results. The UI shows no numbers.

| Factor | Raises | Lowers |
| --- | --- | --- |
| Variety on the matrix | each move new to the program, +0.2 (at most +0.6) | each move colliding with a neighbour on the matrix, −0.6 (at most −1) |
| Formation balance | the first dance of its formation in the program, +0.4 | same formation as a neighbour, −0.6; a formation that is already at least 3 and half of the program's dances, −0.4 |
| Difficulty curve | within a quarter of the level range of the curve's target, +0.5 | further off, −2 × the distance as a share of the range (at most −1) |
| Recent calls at this venue | never called there, +0.3; last called there before the window, +0.3 | called there within the window, −1 |

- **Variety** builds the candidate's matrix row with `buildMatrixRow` (the same
  routing as `buildProgramMatrix`, including the matrix column config and the
  user's own figures) and asks `ProgramMatrix.isCollisionOnMove` of the program
  with the candidate in its place. It therefore honors
  `matrix_exact_beat_collision` (exact beats or phrase) and the matrix's notion
  of neighbours (`ProgramMatrix.neighborRowIndices`): every row of the
  alternate group on either side, never an alternative in the candidate's own
  group, and never across a break; a note or waltz between two dances does not
  separate them. The reason names the first neighbour the move really
  collides with (`ProgramMatrix.collidingNeighborRowIndices`: the side
  before, then after, nearest row first) and its side, and follows the
  setting: "Same partner swing beats as *Chorus Jig*, after it" under exact
  beats, "Partner swing in the same phrase as *Chorus Jig*, after it" under
  the phrase rule; "before it" when the neighbour comes after. A neighbour the
  picker cannot name falls back to "the previous dance" / "the next dance".
- **Formation** treats Becket clockwise and counter-clockwise as one family,
  compares the same neighbours as Variety, and names the first that matches.
- **Difficulty curve** uses the shipped levels' positions. *Build up, then ease
  off* rises from the easiest level to the hardest at 70% of an evening of 12
  dances (or the program's planned length when longer), then eases to the
  middle of the range by the last dance. *Even* targets the mean level of the
  program's dances. A dance with no level, or a level set with one level only,
  is not moved. The curve is read at the position: the planned dances before
  it (before its primary, for an alternate's place), in an evening of the
  planned dances before and after it plus the candidate (not counted when it
  takes an alternate's place).
- **Venue** reads `ProgramRepository.latestCallByDance(CalledFilter)`: the
  newest recency date per dance of exactly the slots the **Called** filter
  counts, with the same caller filter, history settings (performed-only,
  dated-only, tracking) and venue key, and `currentProgramId` set so the
  program being built is never its own history (N1-6). The window counts whole
  calendar months back from today (`calendarMonthsBefore`). A dance called there
  only in undated programs is in no window and is not moved. A program with no
  venue skips the factor and every dance carries the note "skipped, because the
  program has no venue". The reasons name the venue as the builder shows it;
  a linked venue with no name to show (not loaded yet, or deleted, with
  nothing typed) reads "a saved venue", the builder's own fallback.

**Already in this program.** A candidate the program already holds (in any
slot, before or after the position) is kept, never removed, but not scored.
For Replace…, the slot being replaced is in neither list, and the picker
leaves the dance it holds out of the candidates altogether
(`CollectionPicker.excludedDanceIds`), so that dance is never ranked.
The order is: the ranked dances, best first; then the English dances not in
the program; then every dance already in the program, of any form, in the
plain order. Each of those carries the one reason "Already in this program"
(effect −20, `alreadyInProgramEffect`, so it reads as lowering the dance;
the order does not depend on the number). Not scoring them also means none
reads "Never called at …": the venue history leaves the program being built
out (N1-6), so it would. *Rejected:* leaving them unmarked, which ranked a
dance already called tonight near the top as never called at the venue; and
scoring them with a large penalty, which still placed them above English
dances not in the program.

The shipped defaults are: Variety on the matrix **A lot**, Formation balance
**A little**, Difficulty curve **A little** with *Build up, then ease off*, and
Recent calls at this venue **A lot** within **3 months**.

**Reasons.** Each ranked dance carries its reasons sorted by the size of their
effect. The row shows the top two that moved it (or, when none did, the first
note: "Nothing it looks for moved this dance"); **Why?** lists every reason,
each marked as raising or lowering it, then the notes.

**English dances** are not covered: the matrix comparison assumes contra
phrases, and English figures have no bar-to-phrase mapping that the collision
test can use yet. They are listed after every ranked dance, in their plain
order, each with the note "Suggestions don't cover English dances yet".
Squares are ranked like contras. *Rejected:* ranking English dances with the
matrix factor forced off, which would mix them into the list with scores that
mean something different.

## Positions (#2344)

`SuggestionPosition` is the one place the builder's three ways of asking are
turned into slots before and after:

- **The end**: every slot before, none after. The order there is pinned
  against the #2343 scorer (`suggestions_end_regression_test.dart`, printed
  before #2344 changed anything).
- **An add before or after a slot**: split where the add lands,
  `Program.insertSlotAtGroupBoundary` with a placeholder, so the ranking and
  the add can never disagree: before a group's primary or after its last
  alternate, always as a primary, with a leading run of orphaned alternates
  given as the add will leave it (its first promoted).
- **Replace…**: the slot is left out and the candidate stands in its place,
  as an alternate when the slot is one (`candidateIsAlternate`), so its
  primary and the group's other alternates are alternatives to it, not
  neighbours. It is ranked for the slot as it stands in the program, not as
  the edit dialog's unsaved changes would leave it (an Alternate switch
  flipped in the dialog does not move the position).

Maintainer ruling (2026-11-23):

- *The dance being replaced is not a candidate.* A replacement list should
  not contain the dance being replaced, since picking it changes nothing and
  the caller can close the sheet instead. Replace… passes the dance the slot
  edit dialog shows as `excludedDanceIds`, so a second Replace… in the same
  dialog leaves out the earlier pick and offers the saved dance again.
  Online rows are not filtered (their local id is unknown until import); one
  that resolves to that dance hands it back, which changes nothing.
  *Rejected (#2344's original call):* listing it and not marking it
  *Already in this program*.

Calls made in #2344 (not maintainer rulings):

- *The reason names one neighbour.* When a move collides on both sides, or
  with several alternates, the reason names the first (the side before, then
  after, nearest row first) and keeps the count of colliding moves; **Why?**
  does not list every neighbour. *Rejected:* one reason per neighbour, which
  would count the same move twice in the score.
- *A ranking for one position is never shown for another.* After the position
  moves the plain order shows until the new ranking arrives, as after a new
  search. *Rejected:* keeping the old order on screen meanwhile, whose reasons
  would name the wrong neighbours.
- *Replace… passes the program context too*, so its Called and Not called
  filters and its Last called sort now leave the program being built out of
  calling history (N1-6), as the add-dance pickers already did.

## Event rules (#2345)

With Event rules (#2340) on too, Suggested marks each candidate that would
break one of the program's applied rules at the position it ranks for, and
lists it after every unmarked candidate; each group keeps the ranking's order
(`markRuleBreakingSuggestions`, `RankedSuggestion.wouldBreak`). Nothing is
hidden, no score changes, and there is no setting: it applies whenever both
features are on, Suggested shows and the program applies a rule.

- **What "would break" means.** `CandidateRuleCheck` puts the candidate in the
  `SuggestionPosition`'s place and runs `evaluateEventRules` on that program;
  the candidate would break a rule when its slot is among the slots the
  breach names (`slotIds`, or `alternateSlotIds` for a candidate taking an
  alternate's place): the slot the builder's own marker would flag once the
  dance is added. It also would break a rule when the program as it stands
  (with `SuggestionPosition.replaced` back in its place) meets the rule as
  planned and the program with the candidate does not: for **Replace…**, a
  dance that takes away the only match of an *At least* rule. So *At least*
  over the whole program or a half never marks a dance being added, and a
  pair that already breaks a neighbouring rule elsewhere marks no candidate.
  *Rejected:* marking whenever the program with the candidate breaks the
  rule, which would mark every candidate once the program already breaks it.
- **No search per candidate.** The app resolves each applied rule's saved
  search once and runs it once, over the program's dances and every
  candidate together (`checkCandidateEventRules`, `DanceRepository.matchingAmong`).
  What a candidate would break depends only on which of those match sets
  hold it, so the evaluator runs once per combination met (at most 2^n for n
  rules), not once per candidate.
- **Shown in two steps.** The check starts with the ranking and runs beside
  it; the ranking shows as soon as it is ready, unmarked, and the marks and
  the new order follow once the check is done. A failed check leaves the
  ranking unmarked.
- **English dances** that the ranking lists unranked keep that place and
  are never marked: the issue's decision is that English candidates are
  handled as #2343 handles them. One already in the program is in that group
  with every other form, and is checked with it. *Rejected:* checking English
  dances like any other (a rule is a saved search, so nothing technical
  stops it), which would move an English dance out of #2343's group. This
  holds in the program builder; Perform's swap sheet marks English dances
  too (#2347, below).
- **One position for every host.** The check takes any `SuggestionPosition`.
  The builder passes the one Suggested ranks for. Perform's swap sheet
  passes its own (#2347, below).

## Event rules in Perform's swap sheet (#2347)

With Event rules on, its **Check Perform's Swap this dance** on (the
default) and rules applied to the program, Perform's swap sheet checks every
dance it lists, in any order, through `CollectionPicker.eventRules` with
`PickerEventRules.inEveryOrder`. A dance that would break a rule in the
swapped slot is marked with the rule's sentence and listed after every
unmarked one. Nothing is hidden, and with either switch off or no rules
applied the sheet is unchanged.

- **Where the candidate goes.** `swapCandidatePosition` builds the program as
  `Program.swapSlotDanceKeepingAlternate` stores it: the candidate in the
  swapped slot and the swapped-out dance kept as an alternate right after it,
  so it does not count as planned; an alternate being swapped is promoted to
  lead its group, as the swap does. `SuggestionPosition.replaced` is the
  dance planned there now, so `CandidateRuleCheck` compares with the program
  as it stands. Every scope applies, neighbouring dances included, against
  the dances on either side of the slot. The ranking (#2348) still ranks for
  `SuggestionPosition.replacing`; the picker hands the check that position
  and the sheet checks at its own instead, both fixed while the sheet is
  open. *Rejected:* checking at `SuggestionPosition.replacing`, which leaves
  the swapped-out dance out of the program entirely; it gives the same
  answers today, because a rule counts planned dances only, but would drift
  from what the swap stores if alternates ever counted.
- **Your alternates** (an implementation call, not a maintainer ruling):
  the pinned rows are checked with the results and marked the same way, and
  a marked alternate is listed after the unmarked ones, still under **Your
  alternates**. *Rejected:* leaving them unchecked, when an alternate is the
  likeliest dance to be swapped in; and moving a marked alternate below the
  results, which would break the sheet's two headings.
- **English dances** are marked too, under **Suggested** as in the plain
  order (`markRuleBreakingSuggestions`'s `includeEnglish`): the issue asks
  for every swap result that would break a rule to be marked. An
  implementation call; *rejected:* keeping #2345's builder behaviour, which
  would leave an English replacement for an English dance unmarked.
- **Shown in two steps**, as in the builder: the results show at once,
  unmarked, and the marks and the new order follow once the check is done.
  The rules' search context is read once per sheet.

## Stored settings

Three `settings` keys, all `appUser`, non-personal and shareable in the privacy
registry, all in the backup schema, and all gated on the `suggestions.v1`
sync capability ([sync-spec.md §6.15](sync-spec.md#615-capability-gate)):

- `suggestions_enabled`: a bool, off by default.
- `suggestions_in_perform_swap` (#2348): a bool, off by default; whether
  Perform's swap sheet orders by suggestions. It does nothing while
  `suggestions_enabled` is off.
- `suggestion_settings`: a JSON object.

```json
{
  "version": 1,
  "factors": {
    "matrixVariety": {"weight": "aLot"},
    "formationBalance": {"weight": "aLittle"},
    "difficultyCurve": {"weight": "aLittle", "shape": "buildThenEase"},
    "venueRecency": {"weight": "aLot", "window": "3mo"}
  },
  "preferences": []
}
```

- `weight` is `off`, `aLittle` or `aLot`; `shape` is `buildThenEase`, `even` or
  `off`; `window` is `1mo`, `3mo` or `6mo`.
- A missing key, factor or field reads as its default. An unknown token reads
  as that field's default.
- An unknown factor, and every entry of `preferences`, is kept verbatim and
  written back unchanged. `preferences` is reserved for saved-search Prefer /
  Avoid entries (#2325), which this build neither shows nor scores.
- A malformed value, or a `version` other than 1, reads as the defaults. A
  `version` above 1 (saved by a newer build) is reported as newer: the editor
  shows the defaults read-only with a notice, and writes nothing, so a newer
  build's choices are never overwritten by one that cannot read them.
  Suggestions rank with the defaults meanwhile.
- **Reset to defaults** writes the default choices for the four factors and
  keeps the preserved unknown factors and `preferences`. It is disabled while
  the choices already are the defaults.

The backup validator accepts a value with an integer `version` of at least 1,
an object `factors` and a list `preferences` (each when present); for version
1 every known field must hold a known token.

## Performance

`benchmark/search_benchmark.dart` ranks all 20,000 seeded dances (the same
synthetic collection the search queries use) after a 10-dance program, with
the shipped defaults (every factor on) and a venue history for every tenth
dance, through a `SuggestionWorker` as the picker does: building the request
(the per-candidate projection), sending it, ranking and returning. It reports
the longest stretch the calling isolate went without a turn of its event loop
meanwhile, which is what a dropped frame would be. Medians of 5 runs on the
development container, taken when the feature landed; the block time
varies by several milliseconds from run to run, and only the 5 s total is
enforced:

| | Build the request | Longest block | Total |
| --- | --- | --- | --- |
| First rank (a new worker, every candidate sent) | 5.27 ms | 26.95 ms | 0.67 s |
| Re-rank after an add (candidates already held) | 5.13 ms | 8.19 ms | 0.41 s |

"Build the request" includes each candidate's revision (see "Revision"
above).

The longest block is mostly receiving the ranking back (20,000 results with
their reasons), not sending. Sending the same request in one `Isolate.run`
message blocked the calling isolate for about 0.57 s. The benchmark fails
when the first rank's total passes 5 s. A picker search is normally far
smaller than the whole collection.
