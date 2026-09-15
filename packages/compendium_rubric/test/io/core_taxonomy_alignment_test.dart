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
          buildFigure(move, const {}),
          isNotNull,
          reason: '$move is advertised as supported but does not parse',
        );
      }
    });
  });

  group('parameter defaults match the taxonomy', () {
    for (final move in supportedMoves) {
      test('$move assumes the same values the taxonomy does', () {
        final def = core.contraTaxonomy.resolve(move);
        expect(def, isNotNull, reason: '$move is not in the core taxonomy');

        // Every default this package applies.
        final fromOurDefaults = buildFigure(move, const {});
        expect(fromOurDefaults, isNotNull);

        // Every default the taxonomy applies, stated explicitly.
        final effective = core.contraTaxonomy.effectiveParams(
          core.Figure(move: move),
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
          if (buildFigure(entry.value.targetMove, const {}) != null &&
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

    test('a pinned parameter is not overridable by the record', () {
      // The pins *are* the alias: a see saw whose record also said
      // `shoulder: right` would not be a see saw.
      for (final entry in core.contraTaxonomy.aliases.entries) {
        if (entry.key == 'pull_by_dancers' ||
            entry.key == 'pull_by_direction') {
          continue;
        }
        final pins = entry.value.pinnedParams;
        if (pins.isEmpty) continue;
        if (buildFigure(entry.value.targetMove, const {}) == null) continue;

        final contradicted = {
          for (final pin in pins.entries)
            pin.key: pin.value == 'left' ? 'right' : 'left',
        };
        expect(
          buildFigure(entry.key, contradicted),
          equals(buildFigure(entry.key, const {})),
          reason: '${entry.key} let a record override its pinned $pins',
        );
      }
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
    });
  });
}
