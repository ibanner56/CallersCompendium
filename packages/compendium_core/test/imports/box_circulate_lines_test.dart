import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #2089: Caller's Companion's `Box circulate (Larks cross)` says who crosses,
/// and `Box circulate, balance the wave` puts the balance after the circulate,
/// which a box circulate's balance cannot say.
void main() {
  final readers = {
    'fan-out': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry('(8) $line'),
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure single(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        return figures.single;
      }

      test('a bracket says who crosses and which way they loop', () {
        // Maintainer decisions on #2089: with or without `box`, and the
        // bracket, read whole, is no note.
        for (final (line, who, hand) in [
          ('Box circulate (Larks cross)', 'role1s', null),
          ('Circulate (Robins cross)', 'role2s', null),
          ('Box circulate (Robins cross, Larks loop L)', 'role2s', 'left'),
          ('Circulate (Larks cross, Robins loop R)', 'role1s', 'right'),
        ]) {
          final f = single(line);
          expect(f.move, 'box_circulate', reason: line);
          expect(f.params['who'], who, reason: line);
          expect(f.params['hand'], hand, reason: line);
          expect(f.note, isNull, reason: line);
        }
      });

      test('any other bracket reads as it did before', () {
        // Maintainer decision on #2089: a box circulate noting it, and after a
        // bare `Circulate`, text.
        for (final line in [
          'Box circulate (Larks cross, Larks loop R)',
          'Box circulate (Neighbors cross)',
          'Box circulate to long wave (RH to N, Larks facing out)',
        ]) {
          final f = single(line);
          expect(f.move, 'box_circulate', reason: line);
          expect(f.params.containsKey('who'), isFalse, reason: line);
          expect(f.note, isNotNull, reason: line);
        }
        for (final line in [
          'Circulate (Larks cross, Larks loop R)',
          'Circulate (Neighbors cross)',
        ]) {
          expect(single(line).isCustom, isTrue, reason: line);
        }
      });

      test('a balance it says there is none of keeps the reading', () {
        for (final line in [
          'Box circulate, no balance',
          'Box circulate - without balance',
        ]) {
          final f = single(line);
          expect(f.move, 'box_circulate', reason: line);
          expect(f.note, contains('balance'), reason: line);
        }
      });

      test('a balance after the circulate keeps the line text', () {
        // Maintainer decision on #2089 for the wave balance; the ring and the
        // bracketed lines are the author's call.
        for (final line in [
          'Box circulate, balance the wave',
          'Box circulate, wave balance',
          'Box circulate and balance the wave',
          'Box circulate (Larks cross), balance the wave',
          'Box circulate, balance the ring',
          'Box circulate to a wave, balance the wave',
          'Box circulate to a wave and balance the wave',
        ]) {
          expect(single(line).isCustom, isTrue, reason: line);
        }
        // So does a square through, the other move whose balance its beats
        // give, without the box circulate's rule.
        expect(single('Square through 2, balance the wave').isCustom, isTrue);
      });
    });
  }

  group('on a Caller\'s Companion line', () {
    test('the beats give the bracketed box circulate its balance', () async {
      // The rule from #1975: 8 beats is a balance and circulate, 4 a
      // circulate.
      final balanced = (await _ccFigures(
        '(8) Box circulate (Larks cross)',
      )).single;
      expect(balanced.move, 'box_circulate');
      expect(balanced.params['who'], 'role1s');
      expect(balanced.params['balance'], isTrue);

      final bare = (await _ccFigures('(4) Circulate (Larks cross)')).single;
      expect(bare.params['who'], 'role1s');
      expect(bare.params['balance'], isFalse);
    });

    test('a balance after the circulate is not turned on first', () async {
      for (final line in [
        '(8) Box circulate, balance the wave',
        '(8) Box circulate to a wave, balance the wave',
      ]) {
        expect((await _ccFigures(line)).single.isCustom, isTrue, reason: line);
      }
    });

    test('a balance that reads alone splits off after it', () async {
      // The comma split's rule (#1975 decision 9), in the order written.
      for (final (line, balance, who) in [
        ('(8) Box circulate, balance the ring', 'balance_the_ring', null),
        ('(8) Box circulate, Neighbor balance', 'balance', null),
        ('(8) Box circulate (Larks cross), balance', 'balance', 'role1s'),
      ]) {
        final figures = await _ccFigures(line);
        expect(figures.map((f) => f.move), [
          'box_circulate',
          balance,
        ], reason: line);
        expect(figures.map((f) => f.params['beats']), [4, 4], reason: line);
        expect(figures.first.params['balance'], isNot(isTrue), reason: line);
        expect(figures.first.params['who'], who, reason: line);
      }
    });
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
