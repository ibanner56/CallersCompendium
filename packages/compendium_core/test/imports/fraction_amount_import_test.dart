// #2120: a figure 8 or poussette fraction that no named value states keeps
// its amount on import, instead of collapsing to a bare `other`.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

Future<Figure> _contraDb(String move, List<Object?> params) async {
  final adapter = ContraDbAdapter();
  final payload = jsonEncode({
    'title': 'Fractions',
    'figures_json': [
      {'move': move, 'parameter_values': params},
    ],
  });
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return figuresOf(draft.dance).single;
}

Figure? _tcb(String text) =>
    parseFigureLine(text, beats: 0, frontEnd: tcbFigureFrontEnd);

void main() {
  group('ContraDB half_or_full', () {
    test('an amount past full is kept as other with that amount', () async {
      final f = await _contraDb('figure 8', ['ones', 1.5, 24]);
      expect(f.params['fraction'], 'other');
      expect(f.params[fractionAmountParam], 1.5);
      final p = await _contraDb('poussette', [
        'larks',
        'neighbors',
        2,
        true,
        12,
      ]);
      expect(p.params['fraction'], 'other');
      expect(p.params[fractionAmountParam], 2);
    });

    test('a named amount stays named and states no amount', () async {
      final f = await _contraDb('figure 8', ['ones', 0.5, 8]);
      expect(f.params['fraction'], 'half');
      expect(f.params.containsKey(fractionAmountParam), isFalse);
    });

    test('an amount outside the domain is other with none', () async {
      final f = await _contraDb('figure 8', ['ones', 0.4, 8]);
      expect(f.params['fraction'], 'other');
      expect(f.params.containsKey(fractionAmountParam), isFalse);
    });
  });

  group('figure text', () {
    test('"Ones figure 8 1 1/2 up" reads the amount', () {
      final f = _tcb('Ones figure 8 1 1/2 up')!;
      expect(f.move, 'figure_8');
      expect(f.params['fraction'], 'other');
      expect(f.params[fractionAmountParam], 1.5);
      expect(f.params['where'], 'above');
    });

    test('"Ones figure 8 1½ up" reads the glyph as the same amount', () {
      final f = _tcb('Ones figure 8 1½ up')!;
      expect(f.params['fraction'], 'other');
      expect(f.params[fractionAmountParam], 1.5);
    });

    test('"Partner poussette clockwise 2 1/2" reads the amount', () {
      final f = _tcb('Partner poussette clockwise 2 1/2')!;
      expect(f.move, 'poussette');
      expect(f.params['fraction'], 'other');
      expect(f.params[fractionAmountParam], 2.5);
    });

    test('"Ones figure 8 1 up" is still a full figure 8', () {
      final f = _tcb('Ones figure 8 1 up')!;
      expect(f.params['fraction'], 'full');
      expect(f.params.containsKey(fractionAmountParam), isFalse);
    });
  });

  group('display read-back (#2121 wording)', () {
    final renderer = FigureRenderer(contraTaxonomy);
    for (final params in <Map<String, Object?>>[
      {'fraction': 'other', 'amount': 1.75},
      {'fraction': 'other', 'amount': 2.0},
      {'fraction': 'other'},
    ]) {
      for (final move in ['figure_8', 'poussette']) {
        test('$move $params', () {
          final figure = testFigure(
            move: move,
            params: {if (move == 'figure_8') 'where': 'above', ...params},
          );
          final text = renderer.renderSummary(figure, Dialect.larksRobins);
          final read = parseFreeTextFigureEntry(
            text,
            dialect: Dialect.larksRobins,
          );
          expect(read, hasLength(1), reason: text);
          expect(read.single.move, move);
          expect(read.single.params['fraction'], 'other');
          expect(read.single.params[fractionAmountParam], params['amount']);
        });
      }
    }

    for (final move in ['figure_8', 'poussette']) {
      test('$move with decimals reads back', () {
        final figure = testFigure(
          move: move,
          params: {
            if (move == 'figure_8') 'where': 'above',
            'fraction': 'other',
            'amount': 1.5,
          },
        );
        final text = renderer.render(
          figure,
          Dialect.larksRobins,
          decimals: true,
        );
        expect(text, contains('1.5'));
        final read = parseFreeTextFigureEntry(
          text,
          dialect: Dialect.larksRobins,
        );
        expect(read.single.move, move, reason: text);
        expect(read.single.params[fractionAmountParam], 1.5);
      });
    }

    test('the legacy word "other" still reads as an unstated other', () {
      final read = parseFreeTextFigureEntry(
        'other poussette - larks pull neighbor back then left',
        dialect: Dialect.larksRobins,
      );
      expect(read.single.params['fraction'], 'other');
      expect(read.single.params.containsKey(fractionAmountParam), isFalse);
    });
  });

  group('re-import diff key', () {
    final tax = contraTaxonomy;
    Figure f8(Map<String, Object?> p) =>
        testFigure(move: 'figure_8', params: p);

    test('a stated amount distinguishes two other figure 8s', () {
      expect(
        figureCanonicalKey(f8({'fraction': 'other', 'amount': 1.5}), tax),
        isNot(figureCanonicalKey(f8({'fraction': 'other', 'amount': 2}), tax)),
      );
    });

    test('a stale amount under a named fraction is not a difference', () {
      expect(
        figureCanonicalKey(f8({'fraction': 'half', 'amount': 2}), tax),
        figureCanonicalKey(f8({'fraction': 'half'}), tax),
      );
    });

    test('a figure with no amount keys as it did before v39', () {
      expect(
        figureCanonicalKey(f8({'fraction': 'other'}), tax),
        isNot(contains('amount')),
      );
    });
  });
}
