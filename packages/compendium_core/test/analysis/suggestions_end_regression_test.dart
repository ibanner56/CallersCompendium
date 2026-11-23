import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'suggestions_end_fixture.dart';

/// Adding at the end ranks exactly as it did before the scorer learned to
/// rank for a point inside the program (#2344).
///
/// [_pinned] was printed by the #2343 scorer (main at 6826cf5), before any
/// #2344 change, from the fixture in suggestions_end_fixture.dart: every
/// candidate's place, score and reasons (kind, side, weighted effect), for
/// five variants. A change that alters any of them for the end of the
/// program fails here.
void main() {
  String line(RankedSuggestion s) {
    final reasons = s.reasons
        .map(
          (x) =>
              '${x.kind.name}'
              '${x.neighbor == null ? '' : '/${x.neighbor!.name}'}'
              ':${x.effect.toStringAsFixed(4)}',
        )
        .join(', ');
    return '${s.danceId} ${s.score.toStringAsFixed(4)} | $reasons';
  }

  for (final entry in endFixtureVariants.entries) {
    test('adding at the end ranks as before (${entry.key})', () {
      final ranking = rankSuggestions(entry.value());
      expect([for (final s in ranking.order) line(s)], _pinned[entry.key]);
    });
  }
}

// dart format off
const _pinned = <String, List<String>>{
  'defaults': [
    'c-new-moves 2.2000 | newMoves:1.2000, neverCalledHere:0.9000, fitsCurve:0.5000, formationCommonTonight:-0.4000',
    'c-becket 0.8000 | neverCalledHere:0.9000, sameFormationAsNeighbor/previous:-0.6000, fitsCurve:0.5000',
    'c-proper 0.3000 | easierThanCurve:-1.0000, neverCalledHere:0.9000, firstFormationTonight:0.4000',
    'c-overlap -0.2013 | neverCalledHere:0.9000, harderThanCurve:-0.7013, formationCommonTonight:-0.4000',
    'c-no-level -0.4000 | formationCommonTonight:-0.4000',
    'c-fresh -0.5000 | easierThanCurve:-1.0000, neverCalledHere:0.9000, formationCommonTonight:-0.4000',
    'c-triplet -1.2000 | beatOverlap/previous:-3.0000, neverCalledHere:0.9000, fitsCurve:0.5000, firstFormationTonight:0.4000',
    'c-square -1.3000 | beatOverlap/previous:-1.8000, neverCalledHere:0.9000, formationCommonTonight:-0.4000',
    'c-long-ago -2.0013 | beatOverlap/previous:-1.8000, notCalledHereSince:0.9000, harderThanCurve:-0.7013, formationCommonTonight:-0.4000',
    'c-recent -4.1013 | calledHereRecently:-3.0000, harderThanCurve:-0.7013, formationCommonTonight:-0.4000',
    'c-english 0.0000 | englishNotCovered:0.0000',
    'p-b -20.0000 | alreadyInProgram:-20.0000',
  ],
  'phrase rule': [
    'c-new-moves 2.2000 | newMoves:1.2000, neverCalledHere:0.9000, fitsCurve:0.5000, formationCommonTonight:-0.4000',
    'c-becket 0.8000 | neverCalledHere:0.9000, sameFormationAsNeighbor/previous:-0.6000, fitsCurve:0.5000',
    'c-proper 0.3000 | easierThanCurve:-1.0000, neverCalledHere:0.9000, firstFormationTonight:0.4000',
    'c-triplet 0.0000 | phraseOverlap/previous:-1.8000, neverCalledHere:0.9000, fitsCurve:0.5000, firstFormationTonight:0.4000',
    'c-overlap -0.2013 | neverCalledHere:0.9000, harderThanCurve:-0.7013, formationCommonTonight:-0.4000',
    'c-no-level -0.4000 | formationCommonTonight:-0.4000',
    'c-fresh -0.5000 | easierThanCurve:-1.0000, neverCalledHere:0.9000, formationCommonTonight:-0.4000',
    'c-square -1.3000 | phraseOverlap/previous:-1.8000, neverCalledHere:0.9000, formationCommonTonight:-0.4000',
    'c-long-ago -2.0013 | phraseOverlap/previous:-1.8000, notCalledHereSince:0.9000, harderThanCurve:-0.7013, formationCommonTonight:-0.4000',
    'c-recent -4.1013 | calledHereRecently:-3.0000, harderThanCurve:-0.7013, formationCommonTonight:-0.4000',
    'c-english 0.0000 | englishNotCovered:0.0000',
    'p-b -20.0000 | alreadyInProgram:-20.0000',
  ],
  'even curve, no venue': [
    'c-new-moves 1.3000 | newMoves:1.2000, fitsCurve:0.5000, formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-becket -0.1000 | sameFormationAsNeighbor/previous:-0.6000, fitsCurve:0.5000, venueSkippedNoVenue:0.0000',
    'c-no-level -0.4000 | formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-proper -0.6000 | easierThanCurve:-1.0000, firstFormationTonight:0.4000, venueSkippedNoVenue:0.0000',
    'c-overlap -1.4000 | harderThanCurve:-1.0000, formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-fresh -1.4000 | easierThanCurve:-1.0000, formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-recent -1.4000 | harderThanCurve:-1.0000, formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-triplet -2.1000 | beatOverlap/previous:-3.0000, fitsCurve:0.5000, firstFormationTonight:0.4000, venueSkippedNoVenue:0.0000',
    'c-square -2.2000 | beatOverlap/previous:-1.8000, formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-long-ago -3.2000 | beatOverlap/previous:-1.8000, harderThanCurve:-1.0000, formationCommonTonight:-0.4000, venueSkippedNoVenue:0.0000',
    'c-english 0.0000 | englishNotCovered:0.0000',
    'p-b -20.0000 | alreadyInProgram:-20.0000',
  ],
  'a long evening': [
    'c-triplet 1.8000 | neverCalledHere:0.9000, fitsCurve:0.5000, firstFormationTonight:0.4000',
    'c-becket 1.4000 | neverCalledHere:0.9000, fitsCurve:0.5000',
    'c-proper 0.3000 | easierThanCurve:-1.0000, neverCalledHere:0.9000, firstFormationTonight:0.4000',
    'c-square -0.1000 | neverCalledHere:0.9000, sameFormationAsNeighbor/previous:-0.6000, formationCommonTonight:-0.4000',
    'c-no-level -1.0000 | sameFormationAsNeighbor/previous:-0.6000, formationCommonTonight:-0.4000',
    'c-fresh -1.1000 | easierThanCurve:-1.0000, neverCalledHere:0.9000, sameFormationAsNeighbor/previous:-0.6000, formationCommonTonight:-0.4000',
    'c-overlap -1.1000 | harderThanCurve:-1.0000, neverCalledHere:0.9000, sameFormationAsNeighbor/previous:-0.6000, formationCommonTonight:-0.4000',
    'c-long-ago -1.1000 | harderThanCurve:-1.0000, notCalledHereSince:0.9000, sameFormationAsNeighbor/previous:-0.6000, formationCommonTonight:-0.4000',
    'c-new-moves -1.4000 | beatOverlap/previous:-1.8000, neverCalledHere:0.9000, sameFormationAsNeighbor/previous:-0.6000, fitsCurve:0.5000, formationCommonTonight:-0.4000',
    'c-recent -5.0000 | calledHereRecently:-3.0000, harderThanCurve:-1.0000, sameFormationAsNeighbor/previous:-0.6000, formationCommonTonight:-0.4000',
    'c-english 0.0000 | englishNotCovered:0.0000',
    'p-b -20.0000 | alreadyInProgram:-20.0000',
  ],
  'every factor a lot': [
    'c-new-moves 2.4000 | fitsCurve:1.5000, newMoves:1.2000, formationCommonTonight:-1.2000, neverCalledHere:0.9000',
    'c-becket 0.6000 | sameFormationAsNeighbor/previous:-1.8000, fitsCurve:1.5000, neverCalledHere:0.9000',
    'c-triplet 0.6000 | beatOverlap/previous:-3.0000, fitsCurve:1.5000, firstFormationTonight:1.2000, neverCalledHere:0.9000',
    'c-proper -0.9000 | easierThanCurve:-3.0000, firstFormationTonight:1.2000, neverCalledHere:0.9000',
    'c-no-level -1.2000 | formationCommonTonight:-1.2000',
    'c-square -2.1000 | beatOverlap/previous:-1.8000, formationCommonTonight:-1.2000, neverCalledHere:0.9000',
    'c-overlap -2.4039 | harderThanCurve:-2.1039, formationCommonTonight:-1.2000, neverCalledHere:0.9000',
    'c-fresh -3.3000 | easierThanCurve:-3.0000, formationCommonTonight:-1.2000, neverCalledHere:0.9000',
    'c-long-ago -4.2039 | harderThanCurve:-2.1039, beatOverlap/previous:-1.8000, formationCommonTonight:-1.2000, notCalledHereSince:0.9000',
    'c-recent -6.3039 | calledHereRecently:-3.0000, harderThanCurve:-2.1039, formationCommonTonight:-1.2000',
    'c-english 0.0000 | englishNotCovered:0.0000',
    'p-b -20.0000 | alreadyInProgram:-20.0000',
  ],
};
// dart format on
