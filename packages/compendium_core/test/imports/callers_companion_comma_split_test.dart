import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: a Caller's Companion body line that names several figures
/// separated by commas is split into them, with the maintainer's rules for
/// sharing the line's beats, folding a balance, a roll away modifying the
/// figure before it, and where the dancers end up.
void main() {
  group('splitting', () {
    test('the last figure takes the beats the others leave', () async {
      // Maintainer decision 9 on #1975: every figure but the last keeps its
      // default beats.
      final figures = await _ccFigures('(8) Slide Left, Circle Left 3/4');
      expect(figures.map((f) => f.move), ['slide_along_set', 'circle']);
      expect(figures.map((f) => f.params['beats']), [2, 6]);
      expect(figures.last.params['places'], 3);
    });

    test('three figures share the line in order', () async {
      final figures = await _ccFigures(
        '(8) N1 pull by L, N2 pull by R, N3 pull by L',
      );
      expect(figures.map((f) => f.params['who']), [
        'neighbors',
        'nextNeighbors',
        'thirdNeighbors',
      ]);
      expect(figures.map((f) => f.params['beats']), [2, 2, 4]);
    });

    test('a compound prefix gives each figure its group', () async {
      final figures = await _ccFigures('(4,4) N3 pull by R, N2 pull by L');
      expect(figures.map((f) => f.params['beats']), [4, 4]);
    });

    test('a line with no beats leaves them unset', () async {
      final figures = await _ccFigures('Slide Left, Circle Left 3/4');
      expect(figures.map((f) => f.move), ['slide_along_set', 'circle']);
      expect(figures.every((f) => !f.params.containsKey('beats')), isTrue);
    });

    test('nothing left for the last figure keeps the line text', () async {
      // Not read as figures danced at the same time (decision 9).
      for (final line in [
        '(8) Larks allemande Left 1.5, Robins Orbit CW 0.5',
        '(8) Circle Right 3/4, turn alone to face Neighbor 2',
      ]) {
        final figures = await _ccFigures(line);
        expect(figures.single.isCustom, isTrue, reason: line);
      }
    });

    test('pieces that read as one figure stay together', () async {
      final f = (await _ccFigures(
        '(8) Ring balance, spin to the right, face new Neighbors',
      )).single;
      expect(f.move, 'petronella');
      expect(f.params['beats'], 8);
      expect(f.note, 'face new Neighbors');
    });

    test('a piece that is no figure keeps the line text', () async {
      for (final line in [
        '(8) Balance the Wave, dance to new Neighbor',
        '(8) Partner swing, face down, Neighbor swing',
        '(8) Partner swing, dance to new Neighbor',
      ]) {
        final figures = await _ccFigures(line);
        expect(figures.single.isCustom, isTrue, reason: line);
      }
    });

    test('a reading that notes the pieces after it is split', () async {
      // The whole line read as its first figure with the rest as its note.
      final three = await _ccFigures(
        '(8) Larks pull by Left, Partner pull by Right, '
        'Robins allemande Left 1.0',
      );
      expect(three.map((f) => f.move), ['pull_by', 'pull_by', 'allemande']);
      expect(three.map((f) => f.params['beats']), [2, 2, 4]);

      final two = await _ccFigures(
        '(8) Robins pull by Right, Neighbor allemande Left 3/4 (to long waves)',
      );
      expect(two.map((f) => f.move), ['pull_by', 'allemande']);
      expect(two.last.note, 'to long waves');
    });

    test('a note from the figure\'s own bracket is not split', () async {
      final f = (await _ccFigures(
        '(8) Partner right hand balance, square through two '
        '(to new Neighbor)',
      )).single;
      expect(f.move, 'square_through');
      expect(f.note, 'to new Neighbor');
    });

    test('a piece read with a leftover note is no figure', () async {
      // As free-text entry reads: `Balance and California Twirl` does not
      // split off as a balance noting a twirl, and `Right-hand star 7/8` is
      // not a four-place star noting 7/8. Neither line is split.
      final twirl = await _ccFigures(
        '(8) Balance and California Twirl, turn alone to face Ns',
      );
      expect(twirl, hasLength(1));
      expect(twirl.single.move, 'balance');
      expect(twirl.single.note, contains('turn alone'));

      final star = (await _ccFigures(
        '(8) Right-hand star 7/8, to momentary long wave of Robins',
      )).single;
      expect(star.isCustom, isTrue);
    });

    test('a figure\'s default beats count its params', () async {
      // A balanced swing is 16, which leaves nothing for the circle; a
      // balanced box the gnat is at least 4 + 4, which leaves nothing for the
      // pull by.
      for (final line in [
        '(16) Neighbor balance, swing, Circle Left 3/4',
        '(8) Partner Right hand balance, box the gnat, pull by R',
      ]) {
        expect((await _ccFigures(line)).single.isCustom, isTrue, reason: line);
      }
    });

    test('a line that reads whole is not split', () async {
      // Split, it would lose who2 to a bracketed note.
      final f = (await _ccFigures(
        '(8) Neighbor Right-hand balance, square through two '
        '(Neighbor R, Partner L)',
      )).single;
      expect(f.move, 'square_through');
      expect(f.params['who2'], 'partners');
      expect(f.note, isNull);
    });

    test('a line of more than six pieces is not tried', () async {
      final figures = await _ccFigures(
        '(14) N1 pull by L, N2 pull by R, N3 pull by L, N1 pull by R, '
        'N2 pull by L, N3 pull by R, N1 pull by L',
      );
      expect(figures.single.isCustom, isTrue);
    });
  });

  group('a balance before a move that carries one', () {
    test('folds in, with the pair and the hand', () async {
      // Maintainer decision on #1975, as The Caller's Box folds a balance line.
      for (final (line, move, who, hand) in [
        (
          '(8) Partner R-hand balance, box the gnat',
          'box_the_gnat',
          'partners',
          'right',
        ),
        (
          '(8) N2 Left hand balance, swat the flea',
          'swat_the_flea',
          'nextNeighbors',
          'left',
        ),
        (
          '(8) N3 RH-balance, box the gnat',
          'box_the_gnat',
          'thirdNeighbors',
          'right',
        ),
      ]) {
        final f = (await _ccFigures(line)).single;
        expect(f.move, move, reason: line);
        expect(f.params['balance'], isTrue, reason: line);
        expect(f.params['who'], who, reason: line);
        expect(f.params['hand'], hand, reason: line);
        expect(f.params['beats'], 8, reason: line);
      }
    });

    test('a balance naming no pair leaves the move its own', () async {
      // A bare `Balance` reads as everyone.
      final f = (await _ccFigures('(8) Balance, box the gnat')).single;
      expect(f.move, 'box_the_gnat');
      expect(f.params['balance'], isTrue);
      expect(f.params['who'], 'partners');
      expect(f.assumedSubject, isTrue);
    });

    test('a ring balance folds into a petronella', () async {
      final f = (await _ccFigures('(8) Balance the ring, petronella')).single;
      expect(f.move, 'petronella');
      expect(f.params['balance'], isTrue);
      expect(f.params['beats'], 8);
    });

    test('folds into a swing as its prefix', () async {
      final f = (await _ccFigures('(16) Neighbor balance, swing')).single;
      expect(f.move, 'swing');
      expect(f.params['prefix'], 'balance');
      expect(f.params['who'], 'neighbors');
    });

    test('stays its own figure before other dancers or another move', () async {
      final others = await _ccFigures(
        '(8) Partner R-hand balance, Neighbor box the gnat',
      );
      expect(others.map((f) => f.move), ['balance', 'box_the_gnat']);
      expect(others.last.params.containsKey('balance'), isFalse);

      // A move that cannot hold the pair: a petronella has no `who`, and a
      // Rory O'More's takes no relationship.
      for (final (line, move) in [
        ('(8) Neighbor balance, petronella', 'petronella'),
        ("(8) Neighbor balance, Rory O'More", 'rory_o_more'),
      ]) {
        final figures = await _ccFigures(line);
        expect(figures.map((f) => f.move), ['balance', move], reason: line);
        expect(figures.first.params['who'], 'neighbors', reason: line);
      }

      final pullBy = await _ccFigures('(8) Partner R-hand balance, pull by');
      expect(pullBy.map((f) => f.move), ['balance', 'pull_by']);
      expect(pullBy.map((f) => f.params['beats']), [4, 4]);
    });
  });

  group('a roll away or give and take', () {
    test('modifies the figure before it', () async {
      // Maintainer decision on #1975: the two share the line's beats in a
      // modifier container.
      for (final (line, modifier) in [
        (
          '(8) Circle Left 3/4, Partner Roll Away with half sashay',
          'roll_away',
        ),
        ('(8) Circle Left 3/4, Robins give and take neighbor', 'give_and_take'),
      ]) {
        final f = (await _ccFigures(line)).single;
        expect(f.move, modifierMove, reason: line);
        expect(f.params['beats'], 8, reason: line);
        final children = f.subFigures;
        expect(children.map((c) => c.move), ['circle', modifier], reason: line);
        expect(
          children.every((c) => !c.params.containsKey('beats')),
          isTrue,
          reason: line,
        );
      }
    });

    test('a place to end goes on the container', () async {
      final f = (await _ccFigures(
        '(8) Circle Left 3/4, Partner Roll Away with half sashay, face down',
      )).single;
      expect(f.move, modifierMove);
      expect(f.note, 'face down');
    });
  });

  group('where the dancers end up', () {
    test('fills the end facing a figure has', () async {
      // Maintainer decision on #1975.
      for (final line in [
        '(8) Partner swing, face down',
        '(14) Partner swing, end face down',
      ]) {
        final f = (await _ccFigures(line)).single;
        expect(f.move, 'swing', reason: line);
        expect(f.params['endFacing'], 'down', reason: line);
        expect(f.note, isNull, reason: line);
      }
      final turn = (await _ccFigures(
        '(4) Partner courtesy turn, face N2',
      )).single;
      expect(turn.params['endFacing'], 'nextNeighbors');
    });

    test('is otherwise the note', () async {
      for (final (line, note) in [
        ('(12) Partner swing, face N3', 'face N3'),
        ('(8) Circle Left 1.0, face New Neighbors', 'face New Neighbors'),
        ('(8) Larks allemande Left 1.5, to short wave', 'to short wave'),
      ]) {
        final f = (await _ccFigures(line)).single;
        expect(f.isCustom, isFalse, reason: line);
        expect(f.note, note, reason: line);
      }
    });

    test('is scrubbed like the rest of the line', () async {
      final f = (await _ccFigures(
        '(2) Larks allemande Left 1/2, to short wave (P R, Larks L in mid)',
      )).single;
      expect(f.note, 'to short wave (P R, role1s L in mid)');
    });
  });

  test('a hand balance reads on its own', () {
    for (final (line, who, hand) in [
      ('Partner R-hand balance', 'partners', 'right'),
      ('Neighbor Right hand balance', 'neighbors', 'right'),
      ('N1 RH-balance', 'neighbors', 'right'),
      ('Shadow left-hand balance', 'shadows', 'left'),
    ]) {
      final f = parseFigureLinesFanOut(line, beats: 4).single;
      expect(f.move, 'balance', reason: line);
      expect(f.params['who'], who, reason: line);
      expect(f.params['hand'], hand, reason: line);
    }
  });
}

/// The figures a Caller's Companion text export imports for one body line.
Future<List<Figure>> _ccFigures(String line) async {
  final adapter = CallersCompanionTextAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: 'Test Dance\nType: Contra\n\nA1   $line\n'),
  );
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return switch (draft.dance.figuresSource) {
    DecodedFigures(:final figures) => figures,
    UnreadableFigures() => throw StateError('figures did not decode'),
  };
}
