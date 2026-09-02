// Behaviour this compiler exhibits *because* the upstream taxonomy says so,
// not because it is right.
//
// `compendium_rubric` verifies choreography against `compendium_core`'s
// taxonomy, which makes that taxonomy a contract rather than a suggestion.
// When it is wrong, substituting a better answer would mean answering for a
// dance the record does not describe — so the defect is reproduced, and pinned
// here instead.
//
// **These tests are written to fail when the defect is fixed.** That is their
// job: an upstream release that corrects one of these lands as a red test
// pointing at the note that explains what to do about it, rather than as a
// silent change in what this compiler believes.
import 'package:compendium_core/compendium_core.dart' as core;
import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Compiles [move] with bare parameters from a duple-improper start.
///
/// A trailing flagged `pass_through` is appended only to satisfy the
/// pre-flight progression check, which runs *before* any figure does and would
/// otherwise mask the refusal under test. [move] refuses first, so the
/// `pass_through` never runs.
CompileResult compileBare(String move) => compile(
  parseDance(<String, Object?>{
    'title': 'upstream defect probe',
    'formation': <String, Object?>{'shape': 'dupleImproper'},
    'progression': 'single',
    'figures': <Object?>[
      <String, Object?>{'move': move, 'params': const <String, Object?>{}},
      <String, Object?>{'move': 'pass_through', 'progression': true},
    ],
  }).valueOrNull!,
);

void main() {
  group('form_short_waves: the baseline defaults contradict each other', () {
    // `centerHand: 'right'` and `center: 'role2s'` cannot both hold from a
    // duple-improper start -- the canonical wave there is `centerHand: left`.
    // A record omitting `centerHand` is therefore refused over a disagreement
    // between two values it never stated.
    //
    // Filed with the taxonomy's maintainer. WHEN IT IS FIXED: this test fails.
    // Restore the parser to `p.optionalEnum(['centerHand'], Hand.fromKey)` in
    // `dance_json.dart` so a stated `center` derives the hand again -- the
    // figure already implements that path -- and delete this group.
    test('the two defaults are still mutually inconsistent upstream', () {
      final params = core.contraTaxonomy.effectiveParams(
        core.Figure(move: 'form_short_waves'),
      );
      expect(
        params['centerHand'],
        'right',
        reason: 'upstream centerHand default changed -- see the note above',
      );
      expect(
        params['center'],
        'role2s',
        reason: 'upstream center default changed -- see the note above',
      );
    });

    test('so a record that omits centerHand refuses itself', () {
      final outcome = compileBare('form_short_waves');

      expect(
        outcome,
        isA<CompileError>(),
        reason:
            'a bare form_short_waves no longer refuses, which means the '
            'upstream defaults no longer contradict -- see the note above',
      );
      expect((outcome as CompileError).kind, ErrorKind.whoMismatch);
    });
  });
}
