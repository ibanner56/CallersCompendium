import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import '../figures_support.dart';

/// The Caller's Box writes a circular hey as a square through without hands —
/// `Square through 3 without hands (NR;PL;NR)` (TCB dances 20273 and 527). Now
/// that the taxonomy has `circular_hey` (v36), that line imports as one
/// instead of staying custom text.
///
/// The pass list supplies the move's facts: the odd cells' dancers are `who`,
/// the even cells' dancers are `who2` (taxonomy v37), the first cell's side is
/// `shoulder`, and the count is `changes`. The pass list does not say whether
/// the first pass runs across or along, so `where` is left to the taxonomy
/// default, as for TCB heys. A line with no pass list is a square through
/// noting "without hands" (#1971); one whose list does not decode stays custom.
List<Figure> _parse(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Future<List<Figure>> _importedFigures(List<String> lines) async {
  final payload = jsonEncode({
    'ID': '20273',
    'Name': 'Circular hey fixture',
    'Permission': 'full',
    'phrases': [
      {'name': 'B2', 'figures': lines},
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return figuresOf(adapter.parse(raw).dance);
}

void main() {
  void expectCustomLine(String line) {
    final f = _parse(line, beats: 8).single;
    expect(f.isCustom, isTrue, reason: line);
  }

  group('square through without hands -> circular_hey', () {
    test('(NR;PL;NR): three changes, neighbors first by the right', () {
      final f = _parse(
        'Square through 3 without hands (NR;PL;NR)',
        beats: 8,
      ).single;
      expect(f.isCustom, isFalse);
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'neighbors');
      expect(f.params['changes'], 3);
      expect(f.params['shoulder'], 'right');
      expect(f.params['who2'], 'partners');
      expect(f.params['beats'], 8);
      expect(
        f.params.containsKey('where'),
        isFalse,
        reason: 'TCB states no direction; none is asserted',
      );
      expect(f.note, isNull);
    });

    test('partners first by the left, full circuit', () {
      final f = _parse(
        'Square through 4 without hands (PL;NR;PL;NR)',
        beats: 12,
      ).single;
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'partners');
      expect(f.params['changes'], 4);
      expect(f.params['shoulder'], 'left');
      expect(f.params['who2'], 'neighbors');
    });

    test('any second group the pass list names is kept in who2', () {
      final shadows = _parse('Square through 2 without hands (NR;SL)').single;
      expect(shadows.move, 'circular_hey');
      expect(shadows.params['who'], 'neighbors');
      expect(shadows.params['who2'], 'shadows');
      expect(shadows.params['shoulder'], 'right');

      final next = _parse('Square through 2 without hands (PR;N2L)').single;
      expect(next.move, 'circular_hey');
      expect(next.params['who'], 'partners');
      expect(next.params['who2'], 'nextNeighbors');
    });

    test('no pass list: a square through noting "without hands" (#1971)', () {
      // The first passer is unknown, so there is no circular hey to build.
      final f = _parse('Square through 3 without hands', beats: 8).single;
      expect(f.move, 'square_through');
      expect(f.params['places'], 3);
      // No balance-and-pull, and an import never gains an unstated balance.
      expect(f.params['balance'], isFalse);
      expect(f.note, 'without hands');
    });

    test('a bracket that is not a pass list does not block the reading', () {
      final f = _parse('Square through 4 without hands (optional)').single;
      expect(f.move, 'square_through');
      expect(f.note, 'without hands; optional');
    });

    test('"thru" with an undecodable list stays custom too', () {
      expectCustomLine('Square thru 3 without hands (NR;PR;NR)');
      expectCustomLine('Square thru 3 without hands (NR;PL;NR)');
    });

    test('a comma list followed by another clause stays custom', () {
      expectCustomLine(
        'Square through 4 without hands (NR, PL, NR, PL), then balance',
      );
    });

    test('a comma list on a square through with hands is not read', () {
      final f = _parse('Square through 3 (NL, PR, NL)', beats: 8).single;
      expect(f.move, 'square_through');
      expect(f.params.containsKey('who2'), isFalse);
    });

    test("Caller's Companion's comma pass list is read too (#1971)", () {
      final f = _parse(
        'Square through 3 without hands (NR, PL, NR) to new Neighbor',
        beats: 8,
      ).single;
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'neighbors');
      expect(f.params['who2'], 'partners');
      expect(f.params['changes'], 3);
      expect(f.params['shoulder'], 'right');
      expect(f.note, 'to new Neighbor');
    });

    test('a square through WITH hands is still a square through', () {
      final f = _parse('Square through 3 (NR;PL;NR)', beats: 8).single;
      expect(f.move, 'square_through');
      expect(f.params['places'], 3);
      expect(f.params['who'], 'neighbors');
      expect(f.params['who2'], 'partners');
    });
  });

  group('conservative declines stay custom', () {
    void expectCustom(String line) {
      final f = _parse(line, beats: 8).single;
      expect(f.isCustom, isTrue, reason: line);
      expect(f.params['text'], line);
    }

    test('the same group passed twice running', () {
      expectCustom('Square through 2 without hands (NR;NL)');
    });

    test('shoulders that do not alternate', () {
      expectCustom('Square through 3 without hands (NR;PR;NR)');
    });

    test('a cell count that disagrees with the count', () {
      expectCustom('Square through 3 without hands (NR;PL)');
    });

    test('extra words around "without hands"', () {
      expectCustom('Interrupted square through 3 without hands (NR;PL;NR)');
    });
  });

  test('end to end through the TCB adapter (dance 20273 B2)', () async {
    final figures = await _importedFigures([
      '(8) Square through 3 without hands (NR;PL;NR)',
    ]);
    expect(figures, hasLength(1));
    final f = figures.single;
    expect(f.move, 'circular_hey');
    expect(f.params['who'], 'neighbors');
    expect(f.params['changes'], 3);
    expect(f.params['shoulder'], 'right');
    expect(f.params['who2'], 'partners');
    expect(f.beats, 8);
  });
}
