import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:compendium_rubric/src/engine/end_effects.dart';
import 'package:test/test.dart';

Map<String, Object?> _fig(
  String move,
  Map<String, Object?> params, {
  bool progression = false,
}) => {
  'schemaVersion': 1,
  'move': move,
  'params': params,
  if (progression) 'progression': true,
};

/// Jam Doodle (The Caller's Box 10513), as the importer reads it.
List<Map<String, Object?>> _jamDoodle() => [
  _fig('allemande', {'who': 'neighbors', 'hand': 'right', 'travel': 1.5}),
  _fig('allemande', {'who': 'nextNeighbors', 'hand': 'left', 'travel': 1.5}),
  _fig('hey', {
    'length': 'half',
    'pass1': 'role2s',
    'shoulder': 'right',
    'pass2': 'partners',
  }),
  _fig('swing', {'who': 'neighbors'}),
  _fig('allemande', {'who': 'role1s', 'hand': 'left', 'travel': 1.5}),
  _fig('swing', {'who': 'partners'}),
  _fig('chain', {'who': 'role2s', 'hand': 'right'}),
  _fig('star', {'hand': 'left', 'places': 4}, progression: true),
];

Dance _dance(List<Map<String, Object?>> figures) {
  final parsed = parseDance({
    'title': 'end effects',
    'formation': {'shape': 'dupleImproper'},
    'progression': 'single',
    'figures': figures,
  });
  return (parsed as Ok<Dance, DanceParseError>).value;
}

const _la = DancerId(0, Role.lark);
const _ra = DancerId(0, Role.robin);
const _rb = DancerId(1, Role.robin);
const _lc = DancerId(2, Role.lark);
const _rc = DancerId(2, Role.robin);

List<WarningKind> _kinds(CompileResult result) => [
  for (final warning in result.warnings) warning.kind,
];

void main() {
  group('an end couple waiting out trades places when the dance needs it', () {
    test('Jam Doodle compiles once both waiting couples cross over', () {
      // After the N2 allemande and the half hey, everyone in the set has
      // crossed but couples B and E, who waited out at the ends. Uncrossed,
      // the N1 swing finds two larks in column 0 at the top and refuses.
      final result = compile(_dance(_jamDoodle()));
      expect(result, isA<Compiled>(), reason: '$result');
      expect(
        [
          for (final warning in result.warnings)
            if (warning.kind == WarningKind.endEffectSwap) warning.opIndex,
        ],
        [3, 3],
      );
    });

    test('a retry that fails later reports the original refusal', () {
      // The partner swing replaced by one the set cannot dance: the trade
      // gets past the N1 swing, but the dance still fails, so the result is
      // the refusal the dance met first, without the trade.
      final figures = _jamDoodle()..[5] = _fig('swing', {'who': 'role1s'});
      final result = compile(_dance(figures));
      expect(result, isA<CompileError>());
      final error = result as CompileError;
      expect(error.opIndex, 3);
      expect(error.error.message, contains('L-B and L-A'));
      expect(_kinds(result), isNot(contains(WarningKind.endEffectSwap)));
    });
  });

  group('endEffectCandidates', () {
    final start = _dance(_jamDoodle()).instantiate();
    const namingA = OpError(ErrorKind.whoMismatch, 'L-A is in the way');

    /// [state] as it stood before a figure that moved every dancer outside
    /// the end rows: each middle row's pair traded places.
    Formation everyMiddleRowMoved(Formation state) {
      var before = state;
      for (var row = 1; row < state.lastRow; row++) {
        final ids = state.dancersInRow(row);
        before = tradeInPlace(before, (ids[0], ids[1]));
      }
      return before;
    }

    final previous = everyMiddleRowMoved(start);

    test('offers a pair alone at an end that stood still', () {
      expect(endEffectCandidates(start, previous: previous, error: namingA), [
        (0, (_ra, _la)),
      ]);
    });

    test('offers a pair that is not a couple', () {
      final mixed = tradeInPlace(start, (_ra, _rb));
      expect(
        endEffectCandidates(
          mixed,
          previous: everyMiddleRowMoved(mixed),
          error: namingA,
        ),
        [(0, (_rb, _la))],
      );
    });

    test('offers a pair the figure before left waiting out', () {
      // Only couple C moved, but the top row was stranded out of every
      // hands four in the figure before.
      final waiting = markWaitingOut(start, rows: [0, start.lastRow]);
      expect(
        endEffectCandidates(
          start,
          previous: tradeInPlace(waiting, (_lc, _rc)),
          error: namingA,
        ),
        [(0, (_ra, _la))],
      );
    });

    test('offers nobody in a live hands four when some of the set stood', () {
      // A figure for part of the set (only couple C moved) says nothing
      // about the top couple, who were in a hands four.
      expect(
        endEffectCandidates(
          start,
          previous: tradeInPlace(start, (_lc, _rc)),
          error: namingA,
        ),
        isEmpty,
      );
    });

    test('offers nobody when nobody else moved', () {
      expect(
        endEffectCandidates(start, previous: start, error: namingA),
        isEmpty,
      );
    });

    test('offers nobody when the error does not name them', () {
      expect(
        endEffectCandidates(
          start,
          previous: previous,
          error: const OpError(ErrorKind.whoMismatch, 'L-C is in the way'),
        ),
        isEmpty,
      );
    });

    test('offers nobody at an end that already traded', () {
      expect(
        endEffectCandidates(
          start,
          previous: previous,
          error: namingA,
          spentRows: {0},
        ),
        isEmpty,
      );
    });

    test('offers nobody before the first figure', () {
      expect(
        endEffectCandidates(start, previous: null, error: namingA),
        isEmpty,
      );
    });
  });
}
