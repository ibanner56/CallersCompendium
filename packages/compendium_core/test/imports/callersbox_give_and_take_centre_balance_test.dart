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

    test('after a bare form long wave, that role forms and balances the '
        'centre wave', () async {
      // Maintainer ruling 2026-11-24: the bare `form long wave` is the larks
      // forming the single wave in the centre, and the balance is of it.
      final figures = await _figuresFor([
        '(0) Form long wave',
        '(4) Men balance long wave in center',
      ]);
      expect(figures, hasLength(1));
      final wave = figures.single;
      expect(wave.move, 'form_a_long_wave');
      expect(wave.params['who'], 'role1s');
      expect(wave.params['balance'], isTrue);
      expect(wave.beats, 4);
      expect(wave.assumedSubject, isFalse);
    });

    test('the same across a phrase boundary', () async {
      final payload = jsonEncode({
        'ID': '42',
        'Name': 'Test Dance',
        'Permission': 'full',
        'phrases': [
          {
            'name': 'A1',
            'figures': [
              '(4) Neighbor allemande left 3/4',
              '(0) Form long wave',
            ],
          },
          {
            'name': 'A2',
            'figures': ['(4) Men balance long wave in center'],
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
      expect(figures.map((f) => f.move), ['allemande', 'form_a_long_wave']);
      expect(figures.last.params['who'], 'role1s');
      expect(figures.last.params['balance'], isTrue);
    });

    test('a role balance with more on its line is refused, and the bare wave '
        'states no role or balance', () async {
      // The fold would drop the extra words or annotation, so the balance stays
      // custom. The bare wave stays the long waves it was: the centre wave's
      // defaults would make it the robins' wave, already balanced, ahead of
      // the larks' balance line (pre-release audit finding C-06).
      void expectRefused(List<Figure> figures, String balance) {
        expect(figures, hasLength(2), reason: balance);
        final wave = figures.first;
        expect(wave.move, 'form_long_waves', reason: balance);
        expect(wave.params['who'], ParamVocab.unspecified, reason: balance);
        expect(wave.params['balance'], isNot(isTrue), reason: balance);
        expect(figures.last.isCustom, isTrue, reason: balance);
        expect(
          figures.last.params['text'],
          contains('balance long wave in center'),
          reason: balance,
        );
      }

      for (final balance in [
        '(4) Men balance long wave in center and slide left',
        '(4) Men balance long wave in center (P2L,P3R)',
        '(4) Women balance long wave in center and slide right',
        '(4) Men, balance long wave in center and slide left',
      ]) {
        expectRefused(
          await _figuresFor(['(0) Form long wave', balance]),
          balance,
        );
        // Across a phrase boundary, the same.
        final payload = jsonEncode({
          'ID': '42',
          'Name': 'Test Dance',
          'Permission': 'full',
          'phrases': [
            {
              'name': 'A1',
              'figures': ['(8) Neighbor swing', '(0) Form long wave'],
            },
            {
              'name': 'A2',
              'figures': [balance],
            },
          ],
        });
        final adapter = CallersBoxAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: payload),
        );
        final across = figuresOf(
          adapter.parse(await adapter.fetch(discovered.single)).dance,
        );
        expect(across.first.move, 'swing', reason: balance);
        expectRefused(across.skip(1).toList(), balance);
      }
    });

    test('a robins\' balance names the robins', () async {
      final figures = await _figuresFor([
        '(0) Form long wave',
        '(4) Women balance long wave in center',
      ]);
      expect(figures.single.move, 'form_a_long_wave');
      expect(figures.single.params['who'], 'role2s');
      expect(figures.single.params['balance'], isTrue);
    });

    test('after held long waves, stays custom', () async {
      // Holds and a facing name the long waves across the set, never a centre
      // wave (maintainer ruling 2026-11-24), so the centre-wave balance after
      // them is not read as one.
      final figures = await _figuresFor([
        '(0) Form long wave (P2L,P3R, women face in)',
        '(4) Men balance long wave in center',
      ]);
      expect(figures.first.move, 'form_long_waves');
      expect(figures.last.isCustom, isTrue);
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
