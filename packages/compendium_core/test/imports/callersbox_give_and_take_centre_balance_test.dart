import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import '../figures_support.dart';

/// Two Caller's Box line shapes that used to stay free text (2026-11-24, on
/// Hudson's "try it and see"): `Men go forward` / `Men bring back partner` as
/// one give and take, and `Men balance long wave in center` on its own line as
/// a balance where the dancers stand. Wordings are verbatim corpus samples.
Future<List<Figure>> _figuresFor(List<String> lines) async {
  final payload = jsonEncode({
    'ID': '42',
    'Name': 'Test Dance',
    'Permission': 'full',
    'phrases': [
      {'name': 'A1', 'figures': lines},
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return figuresOf(adapter.parse(raw).dance);
}

void main() {
  group('go forward, then bring back: one give and take', () {
    test('larks bring back their partners', () async {
      final figures = await _figuresFor([
        '(4) Men go forward',
        '(4) Men bring back partner',
      ]);
      expect(figures, hasLength(1));
      final f = figures.single;
      expect(f.move, 'give_and_take');
      expect(f.params['who'], 'role1s');
      expect(f.params['whom'], 'partners');
      expect(f.beats, 8);
    });

    test(
      'robins bring back their neighbours, and the next line is kept',
      () async {
        final figures = await _figuresFor([
          '(4) Women go forward',
          '(4) Women bring back neighbor',
          '(8) Neighbor swing',
        ]);
        expect(figures.map((f) => f.move), ['give_and_take', 'swing']);
        expect(figures.first.params['who'], 'role2s');
        expect(figures.first.params['whom'], 'neighbors');
      },
    );

    test(
      'different roles, or another second line, stay as they were',
      () async {
        final mixed = await _figuresFor([
          '(4) Women go forward',
          '(4) Men bring back partner',
        ]);
        expect(mixed, hasLength(2));
        expect(mixed.every((f) => f.isCustom), isTrue);

        final fallBack = await _figuresFor([
          '(4) Men go forward',
          '(4) Men fall back',
        ]);
        expect(fallBack, hasLength(2));
        expect(fallBack.every((f) => f.isCustom), isTrue);
      },
    );
  });

  group('a role balancing the long wave it already stands in', () {
    test('after an allemande, reads as a balance with a note', () async {
      final figures = await _figuresFor([
        '(4) Men allemande left 3/4',
        '(4) Men balance long wave in center',
      ]);
      expect(figures.map((f) => f.move), ['allemande', 'balance']);
      final balance = figures.last;
      expect(balance.params['who'], 'role1s');
      expect(balance.note, 'long wave in center');
      expect(balance.beats, 4);
    });

    test(
      'across a phrase boundary, the guard still sees the forming wave',
      () async {
        final payload = jsonEncode({
          'ID': '42',
          'Name': 'Test Dance',
          'Permission': 'full',
          'phrases': [
            {
              'name': 'A1',
              'figures': ['(4) Men walk forward; form long wave in center'],
            },
            {
              'name': 'A2',
              'figures': ['(4) Women balance long wave in center'],
            },
          ],
        });
        final adapter = CallersBoxAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: payload),
        );
        final figures = figuresOf(
          adapter.parse(await adapter.fetch(discovered.single)).dance,
        );
        expect(figures.map((f) => f.move), ['form_a_long_wave', 'custom']);
      },
    );

    test('after a walk forward, still folds into the forming wave', () async {
      final figures = await _figuresFor([
        '(4) Women walk forward; form long wave in center',
        '(4) Women balance long wave in center',
      ]);
      expect(figures, hasLength(1));
      expect(figures.single.move, 'form_a_long_wave');
      expect(figures.single.params['balance'], isTrue);
    });

    test('a qualified wave balance stays custom', () async {
      final figures = await _figuresFor([
        '(4) Men allemande left 3/4',
        '(4) Women balance long wave in center (WL)',
      ]);
      expect(figures.last.isCustom, isTrue);
    });
  });
}
