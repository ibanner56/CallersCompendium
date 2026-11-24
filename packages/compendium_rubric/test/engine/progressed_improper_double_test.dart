import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The Last Wednesday (Caller's Box 18654) as the Caller's Box bridge reads it
/// on its next-neighbours placement: a Double Progressed Improper dance whose
/// progressions are the cross trails (N2) and the star (N3).
const Map<String, Object?> _lastWednesday = {
  "title": "The Last Wednesday",
  "form": "contra",
  "formation": {"shape": "progressedImproper"},
  "progression": "double",
  "figures": [
    {
      "move": "allemande",
      "params": {"who": "role1s", "hand": "left", "travel": 1.5, "beats": 8},
    },
    {
      "move": "swing",
      "params": {"who": "partners", "beats": 8},
    },
    {
      "move": "chain",
      "params": {"who": "role2s", "hand": "right", "beats": 8},
    },
    {
      "move": "balance_the_ring",
      "params": {"beats": 4},
    },
    {
      "move": "cross_trails",
      "params": {
        "shoulder": "right",
        "who": "partners",
        "who2": "neighbors",
        "beats": 4,
      },
      "progression": true,
    },
    {
      "move": "box_the_gnat",
      "params": {
        "who": "nextNeighbors",
        "beats": 8,
        "balance": true,
        "hand": "right",
      },
    },
    {
      "move": "star",
      "params": {"hand": "right", "places": 4, "beats": 8},
      "progression": true,
    },
    {
      "move": "swing",
      "params": {"who": "thirdNeighbors", "beats": 16, "prefix": "balance"},
    },
  ],
};

void main() {
  test('a Double Progressed Improper dance lands on the ruled end', () {
    // Hudson, 2026-11-24: "Double progressed improper takes the normal end
    // state from a double progression and swaps the 1s and 2s within their
    // hands four". Before that rule the oracle expected the couple at each end
    // to be waiting out, changed over, and this dance mismatched.
    final dance =
        (parseDance(_lastWednesday) as Ok<Dance, DanceParseError>).value;
    final result = compile(dance);
    expect(result, isA<Compiled>(), reason: '$result');
  });
}
