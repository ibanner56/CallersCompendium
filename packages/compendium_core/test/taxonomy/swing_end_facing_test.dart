import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Issue #543 — the first-class `endFacing` swing param.
///
/// The param is additive: it rides the existing `figures_json` figure codec (no
/// schema bump), the default `in` (across) renders exactly as before, and a
/// display `facing …` clause is appended ONLY for a non-default `out`/`up`/
/// `down`. The swing canonical `renderTemplate` is unchanged, so canonical/FTS/
/// dedupe text stays byte-stable regardless of the facing.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  /// Builds a `swing` fixture.
  ///
  /// Validates at construction by default. A caller passing a deliberately
  /// out-of-domain or hostile value supplies [invalidReason] to opt that ONE
  /// call out — routing the whole helper through `invalidTestFigure` would
  /// disable validation for every caller, most of which are valid, and turn
  /// the opt-out into a general bypass.
  Figure swing({
    String? who,
    String? prefix,
    String? endFacing,
    int? beats,
    String? invalidReason,
  }) {
    final params = <String, Object?>{
      'who': ?who,
      'prefix': ?prefix,
      'endFacing': ?endFacing,
      'beats': ?beats,
    };
    return invalidReason == null
        ? testFigure(move: 'swing', params: params)
        : invalidTestFigure(
            move: 'swing',
            params: params,
            reason: invalidReason,
          );
  }

  group('taxonomy', () {
    final spec = tax.resolve('swing')!.params['endFacing'];

    test('swing carries an additive endFacing choice param', () {
      expect(spec, isNotNull);
      expect(spec!.kind, ParamKind.choice);
      expect(spec.defaultValue, 'in');
      expect(spec.choices, ['in', 'out', 'up', 'down', 'along']);
    });

    test('endFacing reuses the set-relative facing tokens (gateFacings)', () {
      expect(spec!.choices!.toSet(), gateFacings.toSet());
    });

    test(
      'endFacing has no beat cost — swing goodBeats/paramBeats unchanged',
      () {
        final def = tax.resolve('swing')!;
        expect(def.goodBeats, [8, 16]);
        // A non-default facing must not perturb the derived beats.
        expect(
          tax.effectiveParams(swing(endFacing: 'up'))['beats'],
          tax.effectiveParams(swing())['beats'],
        );
      },
    );

    test('effectiveParams defaults an omitted endFacing to in', () {
      expect(tax.effectiveParams(swing())['endFacing'], 'in');
    });
  });

  group('canonical render stays byte-stable (endFacing never serializes)', () {
    final canonicalDefault = renderer.renderCanonical(
      Figure(move: 'swing', params: {'who': 'partners'}),
    );

    for (final facing in ['in', 'out', 'up', 'down', 'along']) {
      test('endFacing=$facing does not change the canonical line', () {
        expect(
          renderer.renderCanonical(swing(who: 'partners', endFacing: facing)),
          canonicalDefault,
        );
      });
    }

    test('an unknown/malicious endFacing token cannot alter canonical', () {
      expect(
        renderer.renderCanonical(
          swing(
            who: 'partners',
            endFacing: '<script>',
            invalidReason:
                'hostile token, to prove it is escaped rather than executed or blanked',
          ),
        ),
        canonicalDefault,
      );
    });
  });

  group('display render — clause only when non-default', () {
    test('default in is silent on every display surface', () {
      final f = swing(who: 'partners', endFacing: 'in');
      expect(renderer.render(f, Dialect.canonical), 'partner swing');
      expect(renderer.renderVerbose(f, Dialect.canonical), 'partner swing');
      expect(renderer.renderSummary(f, Dialect.canonical), 'partner swing');
    });

    test('an omitted endFacing renders exactly like today', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'partners'}),
          Dialect.canonical,
        ),
        'partner swing',
      );
    });

    test('up/down/out/along append a facing clause', () {
      expect(
        renderer.render(
          swing(who: 'partners', endFacing: 'up'),
          Dialect.canonical,
        ),
        'partner swing facing up the hall',
      );
      expect(
        renderer.render(
          swing(who: 'partners', endFacing: 'down'),
          Dialect.canonical,
        ),
        'partner swing facing down the hall',
      );
      expect(
        renderer.render(
          swing(who: 'partners', endFacing: 'out'),
          Dialect.canonical,
        ),
        'partner swing facing out of the set',
      );
      expect(
        renderer.render(
          swing(who: 'partners', endFacing: 'along'),
          Dialect.canonical,
        ),
        'partner swing facing along the set',
      );
    });

    test('the clause shows on verbose and summary surfaces too', () {
      final f = swing(who: 'partners', endFacing: 'up');
      expect(
        renderer.renderVerbose(f, Dialect.canonical),
        'partner swing facing up the hall',
      );
      expect(
        renderer.renderSummary(f, Dialect.canonical),
        'partner swing facing up the hall',
      );
    });

    test('the clause composes with the prefix modifier', () {
      expect(
        renderer.render(
          swing(who: 'neighbors', prefix: 'balance', endFacing: 'down'),
          Dialect.canonical,
        ),
        'neighbor balance & swing facing down the hall',
      );
    });

    test('the clause honours a role dialect for the subject', () {
      expect(
        renderer.render(
          swing(who: 'role1s', endFacing: 'up'),
          Dialect.larksRobins,
        ),
        'larks swing facing up the hall',
      );
    });

    test('an unknown or non-string endFacing renders no clause (allow-listed)', () {
      expect(
        renderer.render(
          swing(
            who: 'partners',
            endFacing: 'sideways',
            invalidReason:
                'out-of-domain endFacing, to prove it is rejected and renders no clause',
          ),
          Dialect.canonical,
        ),
        'partner swing',
      );
      expect(
        renderer.render(
          // invalid-fixture: value is deliberately out of domain — an unknown or non-string endFacing renders no clause (allow-listed)
          Figure(move: 'swing', params: {'who': 'partners', 'endFacing': 42}),
          Dialect.canonical,
        ),
        'partner swing',
      );
    });

    test(
      'a facing swing with an assumed subject keeps the (assumed) marker',
      () {
        final line = renderer.render(
          Figure(
            move: 'swing',
            params: {'who': 'partners', 'endFacing': 'up'},
            assumedSubject: true,
          ),
          Dialect.canonical,
        );
        expect(line, 'partner (assumed) swing facing up the hall');
      },
    );
  });

  group('persistence — rides figures_json params', () {
    test('a non-default endFacing round-trips through the figure codec', () {
      final f = swing(who: 'partners', endFacing: 'up', beats: 16);
      final decoded = figureFromJson(
        jsonDecode(jsonEncode(figureToJson(f))) as Map<String, Object?>,
      );
      expect(decoded.params['endFacing'], 'up');
    });

    test('a swing that never set endFacing writes no endFacing key', () {
      final json = figureToJson(
        Figure(move: 'swing', params: {'who': 'partners'}),
      );
      final params = json['params'] as Map?;
      expect(params == null || !params.containsKey('endFacing'), isTrue);
    });

    test('decoding tolerates an unknown endFacing value without throwing', () {
      final decoded = figureFromJson({
        'move': 'swing',
        'params': {'who': 'partners', 'endFacing': 'bogus'},
      });
      // The value is preserved (validation flags it) but never crashes decode…
      expect(decoded.params['endFacing'], 'bogus');
      // …and it renders silently rather than injecting the unknown token.
      expect(renderer.render(decoded, Dialect.canonical), 'partner swing');
    });
  });

  group('validation (OWASP allow-list)', () {
    test('an out-of-domain endFacing is a hard validation error', () {
      final issues = tax.validateFigure(
        swing(
          who: 'partners',
          endFacing: 'sideways',
          invalidReason:
              'out-of-domain endFacing, to prove it is rejected and renders no clause',
        ),
      );
      expect(
        issues.any(
          (i) =>
              i.code == 'invalid_param_value' &&
              i.severity == ValidationSeverity.error,
        ),
        isTrue,
      );
    });

    test('every allowed endFacing token validates clean', () {
      for (final facing in ['in', 'out', 'up', 'down', 'along']) {
        expect(
          tax.validateFigure(swing(who: 'partners', endFacing: facing)),
          isEmpty,
          reason: 'endFacing=$facing should be valid',
        );
      }
    });
  });

  group('program matrix — endFacing must not fragment swing columns', () {
    Dance dance(String id, List<Figure> figures) => Dance(
      id: id,
      title: id,
      figures: figures,
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
    );

    test('swingColumnKey ignores endFacing', () {
      expect(swingColumnKey('partners'), swingColumnKey('partners'));
      // Two partner swings with different facings share the same column key.
      final a = swing(who: 'partners', endFacing: 'up');
      final b = swing(who: 'partners', endFacing: 'in');
      expect(swingColumnKey(a.params['who']), swingColumnKey(b.params['who']));
    });

    test('facing-varied partner swings collapse to a single matrix column', () {
      final matrix = buildProgramMatrix([
        dance('d1', [swing(who: 'partners', endFacing: 'up')]),
        dance('d2', [swing(who: 'partners', endFacing: 'down')]),
        dance('d3', [swing(who: 'partners')]),
      ]);
      final partnerCols = matrix.columns.where(
        (c) => c.moveId == 'swing:partner',
      );
      expect(partnerCols, hasLength(1));
    });
  });
}
