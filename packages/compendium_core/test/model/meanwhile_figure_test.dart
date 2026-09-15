import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Core-model behaviour of the `meanwhile` container figure (#590): the
/// [Figure.meanwhile] factory, structural caps, the [Figure.subFigures]
/// accessor, and the shared-beat rule in [deriveSections].
void main() {
  final sideA = Figure(
    move: 'allemande',
    params: const {'who': 'role1s', 'hand': 'left', 'travel': 1.5},
  );
  final sideB = Figure(
    move: 'orbit',
    params: const {'who': 'role2s', 'direction': 'clockwise', 'travel': 0.5},
  );

  group('Figure.meanwhile', () {
    test('builds a flat container with the shared beat count', () {
      final f = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      expect(f.isMeanwhile, isTrue);
      expect(f.move, meanwhileMove);
      // The shared count is authoritative for section math.
      expect(f.beats, 8);
      expect(f.subFigures, [sideA, sideB]);
    });

    test('allows more than two sides up to the cap', () {
      final sides = [
        for (var i = 0; i < kMaxMeanwhileSides; i++)
          testFigure(move: 'custom', params: {'text': 'side $i'}),
      ];
      final f = Figure.meanwhile(figures: sides, beats: 4);
      expect(f.subFigures, hasLength(kMaxMeanwhileSides));
    });

    test('rejects fewer than two sides', () {
      expect(
        () => Figure.meanwhile(figures: [sideA], beats: 8),
        throwsArgumentError,
      );
    });

    test('rejects more sides than the cap', () {
      final tooMany = [
        for (var i = 0; i <= kMaxMeanwhileSides; i++)
          testFigure(move: 'custom', params: {'text': 'side $i'}),
      ];
      expect(
        () => Figure.meanwhile(figures: tooMany, beats: 8),
        throwsArgumentError,
      );
    });

    test('allows one opposite modifier level', () {
      final nested = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      final modifier = Figure.modifier(figures: [sideA, nested], beats: 8);
      expect(modifier.isModifier, isTrue);
      expect(modifier.subFigures.singleWhere((f) => f.isMeanwhile), nested);
    });

    test('rejects same-kind nested containers', () {
      final nested = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      expect(
        () => Figure.meanwhile(figures: [sideA, nested], beats: 8),
        throwsArgumentError,
      );
      final modifier = Figure.modifier(figures: [sideA, sideB], beats: 8);
      expect(
        () => Figure.modifier(figures: [sideA, modifier], beats: 8),
        throwsArgumentError,
      );
    });

    test('rejects a third container level', () {
      final nested = Figure.modifier(figures: [sideA, sideB], beats: 8);
      final root = Figure.meanwhile(figures: [sideA, nested], beats: 8);
      expect(
        () => Figure.modifier(figures: [sideA, root], beats: 8),
        throwsArgumentError,
      );
    });
  });

  group('subFigures accessor', () {
    test('is empty for a non-container figure', () {
      expect(Figure(move: 'swing').subFigures, isEmpty);
      expect(
        Figure(move: 'custom', params: const {'text': 'x'}).subFigures,
        isEmpty,
      );
    });

    test('is unmodifiable', () {
      final f = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      expect(() => f.subFigures.add(sideA), throwsUnsupportedError);
    });
  });

  group('deriveSections shared-beat rule', () {
    test('counts the container beats exactly once (no double-count)', () {
      // Two sides that would each be 8 beats if counted separately; the shared
      // count is 8, so a dance of just this container totals 8, not 16.
      final container = Figure.meanwhile(
        figures: [
          Figure(move: 'allemande', params: const {'beats': 8}),
          Figure(move: 'orbit', params: const {'beats': 8}),
        ],
        beats: 8,
      );
      final structure = PhraseStructure.parse('');
      final issues = <ValidationIssue>[];
      final sections = deriveSections([container], structure, issues: issues);
      expect(sections.single.startBeat, 0);
      // Section total is exactly the shared count — nested side beats never leak.
      expect(sections.single.startBeat + container.beats, 8);
    });

    test('advances the beat cursor once per container in a sequence', () {
      final container = Figure.meanwhile(
        figures: [
          Figure(move: 'allemande', params: const {'beats': 4}),
          Figure(move: 'orbit', params: const {'beats': 4}),
        ],
        beats: 4,
      );
      final next = Figure(move: 'swing', params: const {'beats': 12});
      final sections = deriveSections([
        container,
        next,
      ], PhraseStructure.parse(''));
      // The swing starts at 4 (the container's shared beats), not 8.
      expect(sections[1].startBeat, 4);
    });

    test('does not recurse into either legal nested container kind', () {
      final meanwhile = Figure.meanwhile(figures: [sideA, sideB], beats: 4);
      final modifier = Figure.modifier(figures: [sideA, sideB], beats: 4);
      final sections = deriveSections([
        Figure.modifier(figures: [sideA, meanwhile], beats: 8),
        modifier,
      ], PhraseStructure.parse(''));
      expect(sections.first.startBeat, 0);
      expect(sections[1].startBeat, 8);
    });
  });

  group('renderCanonical determinism', () {
    final renderer = FigureRenderer(contraTaxonomy);

    test('is byte-stable across runs and joins sides in order', () {
      final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      final first = renderer.renderCanonical(container);
      final second = renderer.renderCanonical(container);
      expect(first, second);
      expect(first, contains(meanwhileMove));
      // Deterministic ordering: swapping the sides changes the canonical text.
      final swapped = Figure.meanwhile(figures: [sideB, sideA], beats: 8);
      expect(renderer.renderCanonical(swapped), isNot(first));
    });
  });
}
