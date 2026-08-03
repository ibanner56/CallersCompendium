import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Issue #576 — the first-class `meetTarget` hey param.
///
/// A partial hey (`lessThanHalf`/`betweenHalfAndFull`) can now name WHICH pair
/// you run until you meet, encoding ContraDB's deferred `dancer%%N` meeting
/// target. The param is additive: it rides the existing `figures_json` figure
/// codec (no schema bump), the default `unspecified` renders exactly as before
/// (the generic "until someone meets…" clause), a named pair is surfaced ONLY
/// for the two partial lengths, and the hey canonical `renderTemplate`
/// (`{pass1} {move} {shoulder}`) is unchanged, so canonical/FTS/dedupe text and
/// beat math stay byte-stable regardless of the target.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  Figure hey({String? length, String? meetTarget, String? pass1, int? beats}) =>
      invalidTestFigure(
        move: 'hey',
        params: {
          'pass1': ?pass1,
          'length': ?length,
          'meetTarget': ?meetTarget,
          'beats': ?beats,
        },
        reason: 'callers pass hostile tokens such as <script> to prove they are escaped, not executed or blanked',
      );

  group('taxonomy', () {
    final spec = tax.resolve('hey')!.params['meetTarget'];

    test('hey carries an additive meetTarget dancerSet param', () {
      expect(spec, isNotNull);
      expect(spec!.kind, ParamKind.dancerSet);
      expect(spec.defaultValue, 'unspecified');
      expect(spec.choices, isNotNull);
    });

    test('meetTarget draws from ContraDB chooser_pairz + unspecified', () {
      // The 15 pair tokens ContraDB allows as a hey meeting target, plus the
      // unspecified sentinel default. Order is not asserted, only membership.
      expect(spec!.choices!.toSet(), {
        'role1s',
        'role2s',
        'ones',
        'twos',
        'partners',
        'neighbors',
        'sameRoles',
        'firstCorners',
        'secondCorners',
        'shadows',
        'secondShadows',
        'prevNeighbors',
        'nextNeighbors',
        'thirdNeighbors',
        'fourthNeighbors',
        'unspecified',
      });
    });

    test('meetTarget excludes everyone, centers and single dancers', () {
      final choices = spec!.choices!.toSet();
      // everyone/centers are valid pairDancerSets but nonsensical as a hey
      // meeting target — ContraDB's chooser_pairz omits them.
      expect(choices.contains('everyone'), isFalse);
      expect(choices.contains('centers'), isFalse);
      // Single-dancer identities are never a hey target (pairs only).
      for (final single in ParamVocab.singleDancers) {
        expect(choices.contains(single), isFalse, reason: single);
      }
    });

    test(
      'meetTarget has no beat cost — hey goodBeats/paramBeats unchanged',
      () {
        final def = tax.resolve('hey')!;
        expect(def.goodBeats, [8, 16]);
        // A named target must not perturb the derived beats for any length.
        for (final length in [
          'lessThanHalf',
          'half',
          'betweenHalfAndFull',
          'full',
        ]) {
          expect(
            tax.effectiveParams(
              hey(length: length, meetTarget: 'partners'),
            )['beats'],
            tax.effectiveParams(hey(length: length))['beats'],
            reason: 'meetTarget must not change beats for length=$length',
          );
        }
      },
    );

    test('effectiveParams defaults an omitted meetTarget to unspecified', () {
      expect(tax.effectiveParams(hey())['meetTarget'], 'unspecified');
    });
  });

  group('canonical render stays byte-stable (meetTarget never serializes)', () {
    final canonicalDefault = renderer.renderCanonical(
      Figure(move: 'hey', params: {'length': 'lessThanHalf'}),
    );

    for (final target in ['partners', 'neighbors', 'role2s', 'unspecified']) {
      test('meetTarget=$target does not change the canonical line', () {
        expect(
          renderer.renderCanonical(
            hey(length: 'lessThanHalf', meetTarget: target),
          ),
          canonicalDefault,
        );
      });
    }

    test('an unknown/malicious meetTarget token cannot alter canonical', () {
      expect(
        renderer.renderCanonical(
          hey(length: 'lessThanHalf', meetTarget: '<script>'),
        ),
        canonicalDefault,
      );
    });
  });

  group('display render — named target only for partial lengths', () {
    test('unspecified keeps the generic "until someone meets" clause', () {
      expect(
        renderer.render(hey(length: 'lessThanHalf'), Dialect.canonical),
        'role2s start a hey - rights in center, lefts on ends - until someone meets',
      );
      expect(
        renderer.render(hey(length: 'betweenHalfAndFull'), Dialect.canonical),
        'role2s start a hey - rights in center, lefts on ends - until someone meets the second time',
      );
    });

    test('lessThanHalf names the target with a bare "meet"', () {
      expect(
        renderer.render(
          hey(length: 'lessThanHalf', meetTarget: 'neighbors'),
          Dialect.canonical,
        ),
        'role2s start a hey - rights in center, lefts on ends - until neighbors meet',
      );
    });

    test('betweenHalfAndFull names the target + "the second time"', () {
      expect(
        renderer.render(
          hey(length: 'betweenHalfAndFull', meetTarget: 'partners'),
          Dialect.canonical,
        ),
        'role2s start a hey - rights in center, lefts on ends - until partners meet the second time',
      );
    });

    test('the named clause shows on verbose and summary surfaces too', () {
      final f = hey(length: 'lessThanHalf', meetTarget: 'neighbors');
      const expected =
          'role2s start a hey - rights in center, lefts on ends - until neighbors meet';
      expect(renderer.renderVerbose(f, Dialect.canonical), expected);
      expect(renderer.renderSummary(f, Dialect.canonical), expected);
    });

    test('the named target honours a role dialect', () {
      expect(
        renderer.render(
          hey(length: 'lessThanHalf', meetTarget: 'role1s'),
          Dialect.larksRobins,
        ),
        'robins start a hey - rights in center, lefts on ends - until larks meet',
      );
    });

    test('meetTarget is ignored for half/full (no clause, byte-identical)', () {
      expect(
        renderer.render(
          hey(length: 'half', meetTarget: 'partners'),
          Dialect.canonical,
        ),
        'role2s start a half hey - rights in center, lefts on ends',
      );
      expect(
        renderer.render(
          hey(length: 'full', meetTarget: 'partners'),
          Dialect.canonical,
        ),
        'role2s start a full hey - rights in center, lefts on ends',
      );
    });

    test('an unknown or non-string meetTarget falls back to "someone"', () {
      expect(
        renderer.render(
          hey(length: 'lessThanHalf', meetTarget: 'everyone'),
          Dialect.canonical,
        ),
        'role2s start a hey - rights in center, lefts on ends - until someone meets',
      );
      expect(
        renderer.render(
          Figure(
            move: 'hey',
            params: {'length': 'lessThanHalf', 'meetTarget': 42},
          ),
          Dialect.canonical,
        ),
        'role2s start a hey - rights in center, lefts on ends - until someone meets',
      );
    });
  });

  group('persistence — rides figures_json params', () {
    test('a set meetTarget round-trips through the figure codec', () {
      final f = hey(length: 'lessThanHalf', meetTarget: 'neighbors');
      final decoded = figureFromJson(
        jsonDecode(jsonEncode(figureToJson(f))) as Map<String, Object?>,
      );
      expect(decoded.params['meetTarget'], 'neighbors');
    });

    test('a hey that never set meetTarget writes no meetTarget key', () {
      final json = figureToJson(
        Figure(move: 'hey', params: {'length': 'half'}),
      );
      final params = json['params'] as Map?;
      expect(params == null || !params.containsKey('meetTarget'), isTrue);
    });

    test('decoding tolerates an unknown meetTarget value without throwing', () {
      final decoded = figureFromJson({
        'move': 'hey',
        'params': {'length': 'lessThanHalf', 'meetTarget': 'bogus'},
      });
      // The value is preserved (validation flags it) but never crashes decode…
      expect(decoded.params['meetTarget'], 'bogus');
      // …and it renders silently rather than injecting the unknown token.
      expect(
        renderer.render(decoded, Dialect.canonical),
        'role2s start a hey - rights in center, lefts on ends - until someone meets',
      );
    });
  });

  group('validation (OWASP allow-list)', () {
    test('an out-of-domain meetTarget is a hard validation error', () {
      final issues = tax.validateFigure(
        hey(length: 'lessThanHalf', meetTarget: 'sideways'),
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

    test('an excluded pair (everyone) is rejected by the allow-list', () {
      final issues = tax.validateFigure(
        hey(length: 'lessThanHalf', meetTarget: 'everyone'),
      );
      expect(issues.any((i) => i.code == 'invalid_param_value'), isTrue);
    });

    test('every allowed meetTarget token validates clean', () {
      final spec = tax.resolve('hey')!.params['meetTarget']!;
      for (final target in spec.choices!) {
        expect(
          tax.validateFigure(hey(length: 'lessThanHalf', meetTarget: target)),
          isEmpty,
          reason: 'meetTarget=$target should be valid',
        );
      }
    });
  });

  group('renderer allow-list falls back to the dancer vocab (null choices)', () {
    // Guards the defensive branch flagged in review: if a MoveDef ever declared
    // `meetTarget` WITHOUT explicit `choices`, the renderer must fall back to the
    // shared dancer vocabulary rather than accept ANY string — so an unknown /
    // tolerantly-decoded token still degrades to the generic "someone" wording.
    // The shipped hey MoveDef always sets choices, so we build a minimal hey
    // whose `meetTarget` spec omits them to exercise the fallback path.
    final nullChoicesTax = Taxonomy(
      version: 1,
      form: DanceForm.contra,
      moves: const [
        MoveDef(
          id: 'hey',
          displayName: 'hey',
          params: {
            'pass1': ParamSpec(ParamKind.dancerSet, defaultValue: 'role2s'),
            'length': ParamSpec(
              ParamKind.choice,
              defaultValue: 'half',
              choices: ['lessThanHalf', 'half', 'betweenHalfAndFull', 'full'],
            ),
            // Deliberately NO `choices` here — the branch under test.
            'meetTarget': ParamSpec(
              ParamKind.dancerSet,
              defaultValue: 'unspecified',
            ),
            'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
            'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
          },
          renderTemplate: '{pass1} {move} {shoulder}',
        ),
      ],
    );
    final nullChoicesRenderer = FigureRenderer(nullChoicesTax);

    test('a recognized dancer token is still named via the vocab fallback', () {
      expect(
        nullChoicesRenderer.render(
          Figure(
            move: 'hey',
            params: {'length': 'lessThanHalf', 'meetTarget': 'partners'},
          ),
          Dialect.canonical,
        ),
        'role2s start a hey - rights in center, lefts on ends - until partners meet',
      );
    });

    test(
      'an UNrecognized token degrades to "someone meets", not the raw token',
      () {
        final line = nullChoicesRenderer.render(
          Figure(
            move: 'hey',
            params: {'length': 'lessThanHalf', 'meetTarget': 'bogusToken'},
          ),
          Dialect.canonical,
        );
        expect(
          line,
          'role2s start a hey - rights in center, lefts on ends - until someone meets',
        );
        expect(line.contains('bogusToken'), isFalse);
      },
    );
  });
}
