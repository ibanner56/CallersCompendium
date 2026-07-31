import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Human-facing display rendering of the `meanwhile` container figure (#594),
/// layered on the core model/serialization from #590
/// (`test/model/meanwhile_figure_test.dart` covers the model + the
/// `renderCanonical` byte-stability invariant already).
///
/// `render`/`renderVerbose`/`renderSummary` join concurrent sides with the
/// caller-facing "A while B" idiom; `renderCanonical` MUST stay untouched
/// (still joined with the structural `meanwhile` move id) since it is the
/// dedupe/FTS key.
void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final sideA = Figure(
    move: 'allemande',
    params: const {'who': 'role1', 'hand': 'left', 'turn': 1.5},
  );
  final sideB = Figure(
    move: 'orbit',
    params: const {'who': 'role2', 'turn': 0.5},
  );
  final sideC = Figure(
    move: 'custom',
    params: const {'text': 'gentlespoons balance'},
  );

  group('display renders use "while" (2 sides)', () {
    final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
    final textA = renderer.render(sideA, Dialect.larksRobins);
    final textB = renderer.render(sideB, Dialect.larksRobins);

    test('render() joins the two sides with " while "', () {
      expect(
        renderer.render(container, Dialect.larksRobins),
        '$textA while $textB',
      );
    });

    test('renderVerbose() joins the two sides with " while "', () {
      final verboseA = renderer.renderVerbose(sideA, Dialect.larksRobins);
      final verboseB = renderer.renderVerbose(sideB, Dialect.larksRobins);
      expect(
        renderer.renderVerbose(container, Dialect.larksRobins),
        '$verboseA while $verboseB',
      );
    });

    test('renderSummary() joins the two sides with " while "', () {
      final summaryA = renderer.renderSummary(sideA, Dialect.larksRobins);
      final summaryB = renderer.renderSummary(sideB, Dialect.larksRobins);
      expect(
        renderer.renderSummary(container, Dialect.larksRobins),
        '$summaryA while $summaryB',
      );
    });

    test('never contains the raw "meanwhile" move id in display text', () {
      expect(
        renderer.render(container, Dialect.larksRobins),
        isNot(contains(meanwhileMove)),
      );
    });
  });

  group('display renders chain "while" for 3+ sides', () {
    test('render() chains "A while B while C"', () {
      final container = Figure.meanwhile(
        figures: [sideA, sideB, sideC],
        beats: 8,
      );
      final textA = renderer.render(sideA, Dialect.larksRobins);
      final textB = renderer.render(sideB, Dialect.larksRobins);
      final textC = renderer.render(sideC, Dialect.larksRobins);
      expect(
        renderer.render(container, Dialect.larksRobins),
        '$textA while $textB while $textC',
      );
    });
  });

  group('renderCanonical stays byte-stable and unaffected by this change', () {
    test('canonical join is still the structural "meanwhile" separator', () {
      final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      final canonicalA = renderer.renderCanonical(sideA);
      final canonicalB = renderer.renderCanonical(sideB);
      expect(
        renderer.renderCanonical(container),
        '$canonicalA $meanwhileMove $canonicalB',
      );
      // The dedupe/FTS key never contains the display-only "while" word.
      expect(renderer.renderCanonical(container), isNot(contains(' while ')));
    });

    test('is stable across repeated invocations', () {
      final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      final first = renderer.renderCanonical(container);
      final second = renderer.renderCanonical(container);
      expect(first, second);
    });
  });
}
