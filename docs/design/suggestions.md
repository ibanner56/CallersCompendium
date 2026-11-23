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
  `isValidStoredSuggestionSettings`. The request is plain data so the app can
  send it to another isolate.
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
- **Off the UI thread**: the picker calls `Isolate.run` with the request. Until
  the ranking comes back the list shows in the plain order, with the header's
  spinner, and every row still adds on tap. A newer search, a context change
  or leaving Suggested drops a ranking still in flight. A failed ranking is
  logged and leaves the plain order.

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
  with the candidate appended. It therefore honours
  `matrix_exact_beat_collision` (exact beats or phrase) and the matrix's notion
  of neighbours: alternates of one slot are not neighbours of each other, and a
  break or note between two dances separates them.
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
  program has no venue".

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
dance. The median of 5 runs was about 0.5 s on
the development container; the benchmark fails above 5 s. Ranking runs in
another isolate, so this is time to a reordered list, not UI jank. A picker
search is normally far smaller than the whole collection.
