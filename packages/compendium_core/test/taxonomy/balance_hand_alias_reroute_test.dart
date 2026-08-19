import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helpers for end-to-end adapter tests.
// ---------------------------------------------------------------------------

Map<String, Object?> _dance({
  String? id = '1',
  String name = 'Test Dance',
  List<Map<String, Object?>>? phrases,
}) => {
  'ID': ?id,
  'Name': name,
  'Permission': 'full',
  'FormationBase': 'Duple Minor - Improper',
  'Progression': 'Single',
  'phrases': ?phrases,
};

Map<String, Object?> _phrase(String name, List<String> figures) => {
  'name': name,
  'figures': figures,
};

Future<StructuredDraft> _importOne(String payload) async {
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

/// Tests for #870: balance.hand param, inverse-pair alias re-routing, and
/// TCB balance hand annotation extraction + fold threading.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  // -------------------------------------------------------------------------
  // Part 1: balance.hand param
  // -------------------------------------------------------------------------

  group('Part 1 — balance.hand param', () {
    test('contraTaxonomyVersion is 30', () {
      expect(contraTaxonomyVersion, 30);
      expect(tax.version, 30);
    });

    test('balance exposes a hand param defaulting to unspecified', () {
      final def = tax.resolve('balance');
      expect(def, isNotNull);
      expect(def!.params.containsKey('hand'), isTrue);
      expect(def.params['hand']!.defaultValue, ParamVocab.unspecified);
    });

    test('effectiveParams for balance with no hand → unspecified', () {
      final params = tax.effectiveParams(Figure(move: 'balance'));
      expect(params['hand'], ParamVocab.unspecified);
      expect(params['who'], 'neighbors');
    });

    test('effectiveParams for balance with hand: right', () {
      final params = tax.effectiveParams(
        testFigure(move: 'balance', params: {'hand': 'right'}),
      );
      expect(params['hand'], 'right');
    });

    test('effectiveParams for balance with hand: left', () {
      final params = tax.effectiveParams(
        testFigure(move: 'balance', params: {'hand': 'left'}),
      );
      expect(params['hand'], 'left');
    });

    test('balance validates with hand: right / left / unspecified', () {
      for (final hand in ['right', 'left', 'unspecified']) {
        expect(
          tax.validateFigure(
            testFigure(move: 'balance', params: {'hand': hand}),
          ),
          isEmpty,
          reason: 'hand=$hand should validate',
        );
      }
    });

    test('figureCanonicalKey includes hand=unspecified for balance', () {
      final key = figureCanonicalKey(Figure(move: 'balance'), tax);
      expect(key, contains('hand=unspecified'));
    });

    test('balance renders unchanged (template has no {hand} token)', () {
      expect(
        renderer.renderCanonical(Figure(move: 'balance')),
        'neighbors balance',
      );
      expect(
        renderer.renderCanonical(
          testFigure(move: 'balance', params: {'hand': 'right'}),
        ),
        'neighbors balance',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Part 1b: Balance hand pre-recognizer
  // -------------------------------------------------------------------------

  group('Part 1b — balance hand pre-recognizer', () {
    test('(RH) on balance → hand: right', () {
      final f = parseFigureLine(
        'Neighbor balance (RH)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.move, 'balance');
      expect(f.params['hand'], 'right');
      expect(f.params['who'], 'neighbors');
    });

    test('(LH) on balance → hand: left', () {
      final f = parseFigureLine(
        'Partner balance (LH)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.move, 'balance');
      expect(f.params['hand'], 'left');
      expect(f.params['who'], 'partners');
    });

    test('balance with no hand annotation → defaults to unspecified', () {
      final f = parseFigureLine(
        'Neighbor balance',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.move, 'balance');
      expect(
        f.params.containsKey('hand'),
        isFalse,
        reason: 'no hand should be in figure params — default fills in',
      );
      final effective = tax.effectiveParams(f);
      expect(effective['hand'], ParamVocab.unspecified);
    });

    test('(RH) is consumed, not preserved as a note', () {
      final f = parseFigureLine(
        'Neighbor balance (RH)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.note, isNull);
    });

    test('balance the ring with (RH) is not claimed by pre-recognizer', () {
      final f = parseFigureLine(
        'Balance the ring (RH)',
        frontEnd: tcbFigureFrontEnd,
      );
      // The pre-recognizer should NOT claim "balance the ring" — it only
      // matches when the stripped text resolves to the plain 'balance' move.
      // Assert unconditionally: if it structures at all, it must NOT be
      // 'balance' (which would mean the pre-recognizer wrongly stole it).
      expect(f, isNotNull);
      expect(
        f!.move,
        isNot('balance'),
        reason: 'balance_the_ring should not be claimed as a plain balance',
      );
      expect(f.move, 'balance_the_ring');
      // balance_the_ring has no hand param.
      expect(f.params.containsKey('hand'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Part 2: Alias inverse-pair re-routing
  // -------------------------------------------------------------------------

  group('Part 2 — resolvedMoveId', () {
    test('box_the_gnat with hand: left → swat_the_flea', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'box_the_gnat', params: {'hand': 'left'}),
        ),
        'swat_the_flea',
      );
    });

    test('swat_the_flea with hand: right → box_the_gnat', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'swat_the_flea', params: {'hand': 'right'}),
        ),
        'box_the_gnat',
      );
    });

    test('box_the_gnat with hand: right → unchanged', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'box_the_gnat', params: {'hand': 'right'}),
        ),
        'box_the_gnat',
      );
    });

    test('swat_the_flea with hand: left → unchanged', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'swat_the_flea', params: {'hand': 'left'}),
        ),
        'swat_the_flea',
      );
    });

    test('do_si_do with shoulder: left → see_saw', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'do_si_do', params: {'shoulder': 'left'}),
        ),
        'see_saw',
      );
    });

    test('see_saw with shoulder: right → do_si_do', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'see_saw', params: {'shoulder': 'right'}),
        ),
        'do_si_do',
      );
    });

    test('do_si_do with shoulder: right → unchanged', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'do_si_do', params: {'shoulder': 'right'}),
        ),
        'do_si_do',
      );
    });

    test('see_saw with shoulder: left → unchanged', () {
      expect(
        tax.resolvedMoveId(
          testFigure(move: 'see_saw', params: {'shoulder': 'left'}),
        ),
        'see_saw',
      );
    });

    test(
      'meltdown_swing with any prefix → unchanged (not a handedness pair)',
      () {
        expect(
          tax.resolvedMoveId(
            testFigure(move: 'meltdown_swing', params: {'prefix': 'none'}),
          ),
          'meltdown_swing',
        );
        expect(
          tax.resolvedMoveId(
            testFigure(move: 'meltdown_swing', params: {'prefix': 'meltdown'}),
          ),
          'meltdown_swing',
        );
      },
    );

    test('default params → no re-routing', () {
      // box_the_gnat defaults to hand: right, which is its own identity.
      expect(tax.resolvedMoveId(Figure(move: 'box_the_gnat')), 'box_the_gnat');
      // swat_the_flea defaults to hand: left (from alias pin).
      expect(
        tax.resolvedMoveId(Figure(move: 'swat_the_flea')),
        'swat_the_flea',
      );
    });

    test('canonical keys are identical for both halves of a pair', () {
      final boxLeft = figureCanonicalKey(
        testFigure(move: 'box_the_gnat', params: {'hand': 'left'}),
        tax,
      );
      final swatLeft = figureCanonicalKey(
        testFigure(move: 'swat_the_flea', params: {'hand': 'left'}),
        tax,
      );
      expect(boxLeft, swatLeft, reason: 'both resolve to box_the_gnat MoveDef');
    });
  });

  // -------------------------------------------------------------------------
  // Part 3: Import fold — hand threading
  // -------------------------------------------------------------------------

  group('Part 3 — balance fold with hand threading (end-to-end)', () {
    test(
      'balance (RH) + box the gnat → one merged figure with hand: right',
      () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A1', [
                  '(4) Neighbor balance (RH)',
                  '(4) Neighbor box the gnat',
                ]),
              ],
            ),
          ),
        );
        final a1 = draft.dance.figures;
        // The two lines must fold into a single figure.
        expect(a1, hasLength(1), reason: 'balance + box should fold into one');
        final merged = a1.single;
        expect(merged.move, 'box_the_gnat');
        expect(merged.params['balance'], true);
        expect(merged.params['hand'], 'right');
      },
    );

    test(
      'balance (LH) + swat the flea → one merged figure with hand: left',
      () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A1', [
                  '(4) Neighbor balance (LH)',
                  '(4) Neighbor swat the flea',
                ]),
              ],
            ),
          ),
        );
        final merged = draft.dance.figures.single;
        expect(merged.move, 'swat_the_flea');
        expect(merged.params['balance'], true);
        expect(merged.params['hand'], 'left');
      },
    );

    test(
      'balance (RH) + petronella → no hand threaded (no hand param on move)',
      () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A1', ['(4) Balance (RH)', '(4) Petronella']),
              ],
            ),
          ),
        );
        final merged = draft.dance.figures
            .where((f) => f.move == 'petronella')
            .single;
        expect(merged.params['balance'], true);
        expect(
          merged.params.containsKey('hand'),
          isFalse,
          reason:
              'petronella has no hand param; threading would persist an '
              'undeclared param that fails taxonomy validation',
        );
      },
    );

    test('standalone balance (RH) → balance figure with hand: right', () {
      final f = parseFigureLine(
        'Neighbor balance (RH)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.move, 'balance');
      expect(f.params['hand'], 'right');
    });

    test('standalone balance (LH) → balance figure with hand: left', () {
      final f = parseFigureLine(
        'Partner balance (LH)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.move, 'balance');
      expect(f.params['hand'], 'left');
    });

    test('standalone balance with no hand → no hand in params', () {
      final f = parseFigureLine(
        'Neighbor balance',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      // No hand in figure params.
      expect(f!.params.containsKey('hand'), isFalse);
      // Effective hand from taxonomy.
      final effective = tax.effectiveParams(f);
      expect(effective['hand'], ParamVocab.unspecified);
    });
  });

  // -------------------------------------------------------------------------
  // Alias enumeration verification
  // -------------------------------------------------------------------------

  group('alias enumeration', () {
    test('exactly three aliases in the contra taxonomy', () {
      expect(tax.aliases.length, 3);
    });

    test('exactly two handedness inverse pairs', () {
      final pairs = tax.aliases.values
          .where((a) => a.inversePairId != null)
          .toList();
      expect(pairs.length, 2);
      expect(pairs.map((a) => a.id).toSet(), {'swat_the_flea', 'see_saw'});
    });

    test('meltdown_swing has no inverse pair', () {
      expect(tax.aliases['meltdown_swing']?.inversePairId, isNull);
    });
  });
}
