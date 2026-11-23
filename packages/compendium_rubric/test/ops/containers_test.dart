import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

Map<String, Object?> _figure(
  String move, [
  Map<String, Object?> params = const {},
]) => {'move': move, 'params': params};

Map<String, Object?> _record(
  List<Map<String, Object?>> figures, {
  String shape = 'dupleImproper',
}) => {
  'title': 'containers',
  'formation': {'shape': shape},
  'progression': 'single',
  'figures': figures,
};

DanceParseError _parseError(Map<String, Object?> record) {
  final parsed = parseDance(record);
  expect(parsed, isA<Err<Dance, DanceParseError>>(), reason: '$parsed');
  return (parsed as Err<Dance, DanceParseError>).error;
}

Operation _onlyFigure(Map<String, Object?> figure) {
  final parsed = parseDance(_record([figure]));
  expect(parsed, isA<Ok<Dance, DanceParseError>>(), reason: '$parsed');
  return (parsed as Ok<Dance, DanceParseError>).value.figures.single.operation;
}

void main() {
  final improper = startingFormation(FormationType.dupleImproper, handsFour: 2);
  final becket = startingFormation(FormationType.becketCw, handsFour: 2);

  group('modifier: the main figure, then each modifier (user-ruled '
      '2026-11-23)', () {
    test('long lines while neighbours roll away ends as the roll away', () {
      const rollAway = RollAway(whom: WhoSet.neighbors);
      final modified = applyOk(
        const FiguresInOrder([LongLines(), rollAway], name: 'modifier'),
        improper,
      );
      final rolled = applyOk(rollAway, improper);
      expect(modified, rolled);
      // The roll away really swapped someone, so the match is not vacuous.
      expect(modified, isNot(improper));
    });

    test('slice left while partners roll away is its own progression', () {
      const modifier = FiguresInOrder([
        Slice(),
        RollAway(whom: WhoSet.partners),
      ], name: 'modifier');
      expect(modifier.isItsOwnProgression, isTrue);
      final sliced = applyOk(const Slice(), becket);
      expect(
        applyOk(modifier, becket),
        applyOk(const RollAway(whom: WhoSet.partners), sliced),
      );
    });

    test('a modifier whose main figure is not a progression is not one', () {
      // The modifiers do not lend the container their own reading: only the
      // main figure decides.
      const modifier = FiguresInOrder([LongLines(), Slice()], name: 'modifier');
      expect(modifier.isItsOwnProgression, isFalse);
    });

    test('is read from the record, children and all', () {
      final op = _onlyFigure(
        _figure('modifier', {
          'beats': 8,
          'figures': [
            _figure('long_lines'),
            _figure('roll_away', {'whom': 'neighbors', 'who': 'role1s'}),
          ],
        }),
      );
      expect(
        op,
        const FiguresInOrder([
          LongLines(),
          RollAway(who: WhoSet.role1s, whom: WhoSet.neighbors),
        ], name: 'modifier'),
      );
    });

    test('a refusal inside it is the refusal of the child', () {
      // A slice by a single dancer is deferred, so the modifier holding it
      // must refuse with the slice's own error.
      final result = const FiguresInOrder([
        LongLines(),
        Slice(by: SliceBy.dancer),
      ], name: 'modifier').apply(becket);
      expect(result, isA<Err<Formation, OpError>>());
      expect(
        (result as Err<Formation, OpError>).error,
        (const Slice(by: SliceBy.dancer).apply(becket)
                as Err<Formation, OpError>)
            .error,
      );
    });
  });

  group('meanwhile: parts danced by different dancers (user-ruled '
      '2026-11-23)', () {
    const allemande = Allemande(who: WhoSet.role2s, hand: Hand.left, turn: 1.5);
    const orbit = Orbit(who: WhoSet.role1s);

    test('women allemande 1½ while men orbit ½ ends as each part alone', () {
      final together = applyOk(const Meanwhile([allemande, orbit]), improper);
      final womenOnly = applyOk(allemande, improper);
      final menOnly = applyOk(orbit, improper);
      for (final id in improper.dancers.keys) {
        final expected = id.role == Role.robin ? womenOnly : menOnly;
        expect(
          together.stateOf(id).position,
          expected.stateOf(id).position,
          reason: '$id',
        );
      }
      // Both parts moved somebody, so neither half of the check is vacuous.
      expect(womenOnly, isNot(improper));
      expect(menOnly, isNot(improper));
    });

    test('the order the parts are written in does not matter', () {
      expect(
        applyOk(const Meanwhile([allemande, orbit]), improper),
        applyOk(const Meanwhile([orbit, allemande]), improper),
      );
    });

    test('refuses two parts that move the same dancers', () {
      const swap = RollAway(whom: WhoSet.partners);
      final result = const Meanwhile([swap, swap]).apply(improper);
      expect(result, isA<Err<Formation, OpError>>(), reason: '$result');
      final error = (result as Err<Formation, OpError>).error;
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('different dancers'));
    });

    test('a wave one part forms is not blamed on the next part', () {
      // An allemande ¾ leaves its pair in a wave. Every part starts from the
      // same state, so the other part does not settle that wave and then look
      // as though it moved the ones; written either way round it compiles to
      // the same set.
      final start = startingFormation(FormationType.becketCw, handsFour: 2);
      const ones = Allemande(who: WhoSet.ones, turn: 0.75);
      const twos = Allemande(who: WhoSet.twos, hand: Hand.left, turn: 0.5);
      final forward = applyOk(const Meanwhile([ones, twos]), start);
      final backward = applyOk(const Meanwhile([twos, ones]), start);
      expect(forward, backward);
      expect(
        forward.stateOf(const DancerId(0, Role.robin)),
        applyOk(ones, start).stateOf(const DancerId(0, Role.robin)),
        reason: 'the ones end in the wave their own part formed',
      );
    });

    test('a part that ends everyone where they began clashes with nothing', () {
      // Known limit (taxonomy.md, "Containers"): "moved" means a new cell, so
      // an allemande once around moves nobody to another cell.
      const once = Allemande(who: WhoSet.role2s, hand: Hand.left);
      expect(
        applyOk(once, improper).toRolesNotation(),
        improper.toRolesNotation(),
      );
      expect(
        applyOk(const Meanwhile([once, orbit]), improper),
        applyOk(orbit, improper),
      );
    });

    test('is its own progression when any part is', () {
      expect(const Meanwhile([allemande, orbit]).isItsOwnProgression, isFalse);
      expect(
        const Meanwhile([orbit, SlideAlongSet()]).isItsOwnProgression,
        isTrue,
      );
    });

    test('a nested sequence is danced in order, as one part', () {
      // Two allemandes 1½ take the women across and back again.
      const there = Allemande(who: WhoSet.role2s, hand: Hand.left, turn: 1.5);
      final result = applyOk(
        const Meanwhile([
          FiguresInOrder([there, there], name: 'sequence'),
          orbit,
        ]),
        improper,
      );
      final menOnly = applyOk(orbit, improper);
      for (final id in improper.dancers.keys) {
        expect(
          result.stateOf(id).position,
          id.role == Role.robin
              ? improper.stateOf(id).position
              : menOnly.stateOf(id).position,
          reason: '$id',
        );
      }
    });

    test('is read from the record', () {
      final op = _onlyFigure(
        _figure('meanwhile', {
          'figures': [
            _figure('allemande', {
              'who': 'role2s',
              'hand': 'left',
              'travel': 1.5,
            }),
            _figure('orbit', {'who': 'role1s', 'direction': 'clockwise'}),
          ],
        }),
      );
      expect(op, isA<Meanwhile>());
      expect((op as Meanwhile).figures, hasLength(2));
    });

    test('a sequence inside one stays together as one part', () {
      final op = _onlyFigure(
        _figure('meanwhile', {
          'figures': [
            _figure('sequence', {
              'figures': [
                _figure('allemande', {'who': 'role2s', 'travel': 1.5}),
                _figure('allemande', {'who': 'role2s', 'travel': 1.5}),
              ],
            }),
            _figure('orbit', {'who': 'role1s'}),
          ],
        }),
      );
      final parts = (op as Meanwhile).figures;
      expect(parts.first, isA<FiguresInOrder>());
      expect(parts.first.name, 'sequence');
    });
  });

  group('what the engine reads off a container', () {
    test('a flagged modifier on a slice is the slice\'s progression', () {
      // Its own progression, so the flag adds no change-over of its own: the
      // same set as the slice flagged on its own line, then the roll away.
      const modifier = FiguresInOrder([
        Slice(),
        RollAway(whom: WhoSet.partners),
      ], name: 'modifier');
      final flagged = OperationInvocation(modifier, progression: true);
      final result = flagged.apply(becket);
      expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
      final sliced =
          OperationInvocation(const Slice(), progression: true).apply(becket)
              as Ok<Formation, OpError>;
      expect(
        (result as Ok<Formation, OpError>).value,
        applyOk(const RollAway(whom: WhoSet.partners), sliced.value),
      );
    });

    test('a sequence is its own progression when any child is', () {
      const sequence = FiguresInOrder([
        LongLines(),
        SlideAlongSet(),
      ], name: 'sequence');
      expect(sequence.isItsOwnProgression, isTrue);
      expect(
        const FiguresInOrder([
          LongLines(),
          SlideAlongSet(),
        ], name: 'modifier').isItsOwnProgression,
        isFalse,
        reason: 'a modifier reads only its main figure',
      );
    });

    test('the extra hands four of every child', () {
      const meanwhile = Meanwhile([SlideAlongSet(), SlideAlongSet()]);
      expect(meanwhile.hands4Contribution, 2);
    });

    test('a child naming shadows sizes the set as the child would', () {
      const shadows = RollAway(whom: WhoSet.shadows);
      const modifier = FiguresInOrder([LongLines(), shadows], name: 'modifier');
      expect(modifier.dancerSets, contains(WhoSet.shadows));
    });

    test('the widest reach of any child', () {
      const modifier = FiguresInOrder([
        LongLines(),
        RollAway(whom: WhoSet.nextNeighbors),
      ], name: 'modifier');
      expect(modifier.reachAfter(0), 1);
      expect(modifier.reachAfter(1), 0);
    });
  });

  group('container records', () {
    test('a flagged child is refused: the flag goes on the container', () {
      final error = _parseError(
        _record([
          _figure('modifier', {
            'figures': [
              {..._figure('long_lines'), 'progression': true},
              _figure('roll_away'),
            ],
          }),
        ]),
      );
      expect(error.path, 'figures[0].params.figures[0].progression');
    });

    test('a container with fewer than two figures is refused', () {
      final error = _parseError(
        _record([
          _figure('meanwhile', {
            'figures': [
              _figure('swing', {'who': 'partners'}),
            ],
          }),
        ]),
      );
      expect(error.path, 'figures[0].params.figures');
    });

    test('an unsupported child is reported at its own path', () {
      final error = _parseError(
        _record([
          _figure('meanwhile', {
            'figures': [_figure('no_such_move'), _figure('orbit')],
          }),
        ]),
      );
      expect(error.path, 'figures[0].params.figures[0].move');
    });
  });
}
