import 'param_types.dart';

/// The vocabulary of contra's `cast` move (taxonomy v40, issue #770): the
/// values of its `direction` and `destination` params, the words each is shown
/// with, and the one role convention the readers apply.
///
/// The maintainer decided (2026-11-19) that contra's `cast` and ECD's
/// `ecd_cast` share one parameter shape, so that ADR-006 F5 can re-read a
/// contra-imported ECD dance one to one. This file is the contra side of that
/// shape. ECD's side is owned by the ECD taxonomy and had not yet taken it when
/// this was written; `cast_test.dart` records where it stands.

/// Which way a cast turns or travels. `left` and `right` are the SHOULDER the
/// dancer turns over, not a side of the set: The Caller's Box's "cast
/// clockwise" is over the right shoulder and "cast counterclockwise" over the
/// left (the maintainer's mapping). `up` and `down` travel along the set. An
/// unstated direction is [ParamVocab.unspecified], which the display reads as
/// "cast back".
const List<String> castDirections = ['left', 'right', 'up', 'down'];

/// The stated endpoint of a cast. The same tokens as ECD's destinations
/// (ADR-006 §6.4, `ecdDestinations`) plus `top` and `bottom`, which The
/// Caller's Box writes ("cast down to bottom", "cast up to top"). Kept as its
/// own list rather than read from ECD's, so that neither taxonomy changes when
/// the other does; a test pins that every ECD destination is here.
const List<String> castDestinations = [
  'place',
  'firstPlace',
  'secondPlace',
  'thirdPlace',
  'fourthPlace',
  'fifthPlace',
  'sixthPlace',
  'originalPlaces',
  'progressedPlace',
  'partnersPlace',
  'neighborsPlace',
  'diagonalsPlace',
  'allImproper',
  'allProper',
  'top',
  'bottom',
];

/// The words shown for a stated cast [destination], or '' for none.
///
/// Read back by the parsers through [castDestinationFromWords], so a change
/// here must keep the two in step (the round-trip ratchet in
/// `figure_round_trip_test.dart` fails otherwise).
String castDestinationPhrase(Object? destination) => switch (destination) {
  'allImproper' => 'ending improper',
  'allProper' => 'ending proper',
  'top' => 'to the top',
  'bottom' => 'to the bottom',
  final String token when castDestinations.contains(token) =>
    'to ${_castDestinationWords[token]}',
  _ => '',
};

const Map<String, String> _castDestinationWords = {
  'place': 'place',
  'firstPlace': 'first place',
  'secondPlace': 'second place',
  'thirdPlace': 'third place',
  'fourthPlace': 'fourth place',
  'fifthPlace': 'fifth place',
  'sixthPlace': 'sixth place',
  'originalPlaces': 'original places',
  'progressedPlace': 'progressed place',
  'partnersPlace': "partner's place",
  'neighborsPlace': "neighbor's place",
  'diagonalsPlace': "diagonal's place",
};

/// The destination token a lowercased word list names, or null. [words] is
/// what follows "to" (or the whole "ending …" phrase), already split on
/// whitespace. Accepts the display's own wording and The Caller's Box's
/// shorter one ("to bottom", "to top"); an apostrophe-free "partners place"
/// reads the same as "partner's place".
String? castDestinationFromWords(List<String> words) {
  final key = words.map((w) => w.replaceAll("'", '')).join(' ');
  return switch (key) {
    'ending improper' => 'allImproper',
    'ending proper' => 'allProper',
    'the top' || 'top' => 'top',
    'the bottom' || 'bottom' => 'bottom',
    _ => _castDestinationByWords[key],
  };
}

final Map<String, String> _castDestinationByWords = {
  for (final MapEntry(:key, :value) in _castDestinationWords.entries) ...{
    value.replaceAll("'", ''): key,
    // "partner's place" loses its apostrophe above; "partners place" and
    // "partner place" are the same endpoint written loosely.
    if (value.contains("'")) value.replaceAll("'s", ''): key,
  },
};

/// The shoulder a "cast back" turns over when the line names a role and no
/// shoulder: role2s (women) cast back over the right shoulder, role1s (men)
/// over the left. The maintainer's ruling (2026-11-19), likened to the
/// role-implied hand of a chain (`chainHandForWho`): in The Caller's Box these
/// lines follow a counterclockwise promenade, where the outside dancer turns
/// out to the right and the inside dancer to the left.
///
/// Written explicitly, never as a taxonomy default, for the same reason as a
/// chain's hand: a role-conditional default would go stale the moment `who` is
/// edited. Every reader writes it for a role's "cast back" with no shoulder
/// (`figure_parser.dart`, `_cast`), the editor writes it when a role is picked
/// (`seedCastShoulder`). Unlike a chain's hand, the display always shows it
/// ("role2s cast back right"), by the maintainer's ruling.
/// Null for any other `who`, so the shoulder stays unstated.
String? castBackShoulderForWho(Object? who) => switch (who) {
  'role2s' => 'right',
  'role1s' => 'left',
  _ => null,
};
