# Design: Suggest the next dance (Experimental)

*Issue #2343 · built. The program builder's add-dance picker can order its
results by how well each dance would fit as the next one at the end of the
program, and say why. It sits behind Settings ▸ Experimental ▸ Suggestions,
off by default. The user-facing description is in
[programs.md](../user/programs.md#let-the-app-suggest-the-next-dance) and
[settings.md](../user/settings.md#suggestions).*

## Shape

- **Core** (`packages/compendium_core/lib/src/analysis/`): a pure-Dart scorer,
  `rankSuggestions(SuggestionRequest) → SuggestionRanking`, and the stored
  settings, `SuggestionSettings` with `readSuggestionSettings` and
  `isValidStoredSuggestionSettings`. The request carries each dance as a
  `SuggestionCandidate`, only what the scorer reads (id, form, formation,
  level, phrase structure, figures and a revision), not the whole `Dance`
  with its notes, tunes and custom fields. `SuggestionCandidate.fromDance`
  makes one. The request takes slots before and after the position, so a
  later caller can rank for a point inside the program (#2344) or another
  host (#2348) with the same shape.
- **App**: the picker takes an optional `PickerProgramContext` (the
  history-filters Q3 shape: program id, linked venue id, typed venue, plus the
  venue's display name and the program's slots). Only the builder's add-dance
  mounts (the inline pane and the bottom sheet) pass it. Replace… passes
  nothing, and an add before or after a slot (#2339) passes no slots, so the
  picker does not offer Suggested there. Suggested is the last entry of the
  picker's Sort menu only while the toggle is on and slots are present. It is
  never in the Collection's sorts (`availableCollectionSorts` is unchanged),
  the picker never opens in it, and it lasts until another sort is chosen or
  the picker closes.
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
  with the candidate appended. It therefore honors
  `matrix_exact_beat_collision` (exact beats or phrase) and the matrix's notion
  of neighbours: alternates of one slot are not neighbours of each other, and a
  break or note between two dances separates them. The reason follows the
  setting: "Same swing beats as the previous dance" under exact beats,
  "Swing in the same phrase as the previous dance" under the phrase rule.
- **Formation** treats Becket clockwise and counter-clockwise as one family.
- **Difficulty curve** uses the shipped levels' positions. *Build up, then ease
  off* rises from the easiest level to the hardest at 70% of an evening of 12
  dances (or the program's planned length when longer), then eases to the
  middle of the range by the last dance. *Even* targets the mean level of the
  program's dances. A dance with no level, or a level set with one level only,
  is not moved.
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

## Stored settings

Two `settings` keys, both `appUser`, non-personal and shareable in the privacy
registry, both in the backup schema, and both gated on the `suggestions.v1`
sync capability ([sync-spec.md §6.15](sync-spec.md#615-capability-gate)):

- `suggestions_enabled`: a bool, off by default.
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
