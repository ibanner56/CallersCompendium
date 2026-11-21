// Cross-checks this package's figure vocabulary and parameter defaults against
// the taxonomy that owns them, `compendium_core`'s [contraTaxonomy].
//
// This package does not define the dance representation — it verifies
// choreography expressed in compendium_core's schema. That makes the taxonomy
// an *upstream contract* rather than a reference: every move id this compiler
// claims to build must exist there, and every default it silently supplies for
// an omitted parameter must be the value the taxonomy says to assume. A
// disagreement in either direction is not a cosmetic drift — it means this
// compiler answers a question about a *different dance* than the record
// describes, confidently and without warning.
//
// The defaults check is deliberately mapping-free. Rather than maintain a
// table pairing this package's constructor arguments to upstream parameter
// names — which would itself need auditing — it builds each figure twice:
// once from an empty parameter map (so every default this package applies is
// exercised) and once from the map `Taxonomy.effectiveParams` produces for a
// bare figure (every default the taxonomy applies). If the two Operations are
// equal, the defaults agree; if they differ, they do not. Operation value
// semantics do the comparison.
import 'package:compendium_core/compendium_core.dart' as core;
import 'package:compendium_core/testing.dart' as core_test;
import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Builds a single figure through the real parser and returns the operation,
/// or `null` when the record does not parse.
Operation? buildFigure(String move, Map<String, Object?> params) {
  final record = <String, Object?>{
    'title': 'taxonomy alignment probe',
    'formation': <String, Object?>{'shape': 'dupleImproper'},
    'progression': 'single',
    'figures': <Object?>[
      <String, Object?>{'move': move, 'params': params},
    ],
  };
  return parseDance(record).valueOrNull?.figures.single.operation;
}

void main() {
  group('move vocabulary is owned upstream', () {
    test('every move this compiler builds exists in the core taxonomy', () {
      final unknown = [
        for (final move in supportedMoves)
          if (core.contraTaxonomy.resolve(move) == null) move,
      ];
      expect(
        unknown,
        isEmpty,
        reason:
            'these moves are built here but are not in compendium_core\'s '
            'taxonomy, so no record could legitimately name them',
      );
    });

    test('supportedMoves reports exactly what the parser can build', () {
      for (final move in supportedMoves) {
        expect(
          buildFigure(
            move,
            move == 'pull_by' ? const {'where': 'along'} : const {},
          ),
          isNotNull,
          reason: '$move is advertised as supported but does not parse',
        );
      }
    });
  });

  group('parameter defaults match the taxonomy', () {
    for (final move in supportedMoves) {
      if (move == 'pull_by') continue;
      test('$move assumes the same values the taxonomy does', () {
        final def = core.contraTaxonomy.resolve(move);
        expect(def, isNotNull, reason: '$move is not in the core taxonomy');

        // Every default this package applies.
        final fromOurDefaults = buildFigure(move, const {});
        expect(fromOurDefaults, isNotNull);

        // Every default the taxonomy applies, stated explicitly.
        final effective = core.contraTaxonomy.effectiveParams(
          core_test.testFigure(move: move),
        );
        final fromTaxonomyDefaults = buildFigure(move, effective);

        expect(
          fromTaxonomyDefaults,
          isNotNull,
          reason:
              '$move fails to parse when the taxonomy states its own defaults '
              'explicitly: $effective',
        );
        expect(
          fromTaxonomyDefaults,
          equals(fromOurDefaults),
          reason:
              'omitting $move\'s parameters produces a different figure than '
              'stating the taxonomy\'s defaults for them. This compiler would '
              'answer for a different dance than the record describes.\n'
              '  taxonomy defaults: $effective',
        );
      });
    }

    test('bare canonical pull_by preserves the taxonomy ambiguity', () {
      expect(buildFigure('pull_by', const {}), isNull);
    });
  });

  group('aliases are resolved, not reinvented', () {
    // An alias is an upstream name for a target move with some parameters
    // pinned. The three groups above already exercise them, because
    // `supportedMoves` lists them -- and the defaults check verifies the pins,
    // since a forgotten pin makes the two build paths disagree. What is left
    // is the direction that silently *shrinks*: an alias added upstream for a
    // move this compiler already builds is a record we would start refusing.
    test('every core alias for a move we build is advertised', () {
      final missing = [
        for (final entry in core.contraTaxonomy.aliases.entries)
          if (buildFigure(entry.value.targetMove, entry.value.pinnedParams) !=
                  null &&
              !supportedMoves.contains(entry.key))
            '${entry.key} -> ${entry.value.targetMove}',
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'compendium_core names these as aliases of moves this compiler '
            'builds, so a record may use them, but the parser would refuse',
      );
    });

    test('an alias builds its target with the pinned parameters applied', () {
      for (final entry in core.contraTaxonomy.aliases.entries) {
        final pins = entry.value.pinnedParams;
        if (pins.isEmpty) continue;
        if (buildFigure(entry.value.targetMove, const {}) == null) continue;

        expect(
          buildFigure(entry.key, const {}),
          equals(buildFigure(entry.value.targetMove, pins)),
          reason:
              '${entry.key} should build exactly ${entry.value.targetMove} '
              'with $pins applied',
        );
      }
    });

    test('a stated value wins over a pin, as upstream reads it', () {
      // `Taxonomy.effectiveParams` lets a stated param win and uses the pin
      // only when it is absent; `resolvedMoveId` then routes the figure to the
      // target move. So an alias stating a contradicting value must build
      // exactly what the target builds from the same params -- for
      // `long_lines` stating `formation: inARing`, a deferral, not long lines.
      // Each contradiction is a real value in the param's domain: a value
      // outside it would refuse for its own reason and prove nothing.
      var checked = 0;
      for (final entry in core.contraTaxonomy.aliases.entries) {
        final target = entry.value.targetMove;
        final def = core.contraTaxonomy.moves[target]!;
        for (final pin in entry.value.pinnedParams.entries) {
          final spec = def.params[pin.key]!;
          final contradiction = switch (pin.value) {
            'left' => 'right',
            'right' => 'left',
            _ => spec.choices?.firstWhere(
              (choice) => choice != pin.value && choice != 'unspecified',
            ),
          };
          if (contradiction == null) continue;
          final stated = {pin.key: contradiction};
          checked++;
          expect(
            buildFigure(entry.key, stated),
            equals(buildFigure(target, stated)),
            reason:
                '${entry.key} stating ${pin.key}: $contradiction should read '
                'as $target does',
          );
        }
      }
      // Every pinned alias but none of them skipped silently.
      expect(checked, greaterThanOrEqualTo(6));
    });

    test('a stated `unspecified` is not read as a concrete default', () {
      // `_Params` reads the sentinel as "not stated", which falls back to the
      // default. That is wrong for a param that admits the sentinel yet keeps a
      // concrete default (v39's circle and star `places`): omitting it means
      // the default, stating it means no value was given. Any such param on a
      // move this compiler builds must refuse rather than guess.
      final found = <String>[];
      for (final move in core.contraTaxonomy.moves.entries) {
        if (buildFigure(move.key, const {}) == null) continue;
        for (final param in move.value.params.entries) {
          final spec = param.value;
          final admits = spec.choices?.contains('unspecified') ?? false;
          if (!admits || spec.defaultValue == 'unspecified') continue;
          final id = '${move.key}.${param.key}';
          found.add(id);
          // The in-front pair of a mad robin is descriptive: the figure lands
          // the same whoever steps in front, so its default cannot mislead.
          if (id == 'mad_robin.who') continue;
          expect(
            buildFigure(move.key, {param.key: 'unspecified'}),
            isNull,
            reason:
                '${move.key}.${param.key} read a stated unspecified as its '
                'default ${spec.defaultValue}',
          );
        }
      }
      expect(
        found,
        containsAll(<String>['circle.places', 'star.places', 'mad_robin.who']),
      );
    });

    test('long_lines in another formation is not danced as long lines', () {
      expect(buildFigure('long_lines', const {'formation': 'inARing'}), isNull);
    });

    test('the v35 pull-by migration aliases preserve explicit values', () {
      expect(
        buildFigure('pull_by_dancers', const {'who': 'nextNeighbors'}),
        const PullByDancers(who: WhoSet.nextNeighbors),
      );
      expect(
        buildFigure('pull_by_direction', const {'where': 'across'}),
        const PullByDirection(dir: Direction.across),
      );
      expect(
        buildFigure('pull_by_direction', const {'dir': 'across'}),
        const PullByDirection(dir: Direction.across),
      );
    });
  });
}
