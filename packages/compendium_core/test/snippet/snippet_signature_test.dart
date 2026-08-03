import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

void main() {
  final tax = contraTaxonomy;

  group('figureSnippetSignature', () {
    test('folds taxonomy defaults so explicit == defaulted', () {
      // allemande defaults: who=neighbors, hand=right, turn=1.0.
      final defaulted = Figure(move: 'allemande');
      final explicit = Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.0},
      );
      expect(
        figureSnippetSignature(defaulted, tax),
        figureSnippetSignature(explicit, tax),
      );
    });

    test('distinguishes allemande left ½ from right 1½', () {
      final left = Figure(
        move: 'allemande',
        params: {'hand': 'left', 'turn': 0.5},
      );
      final right = Figure(
        move: 'allemande',
        params: {'hand': 'right', 'turn': 1.5},
      );
      expect(
        figureSnippetSignature(left, tax),
        isNot(figureSnippetSignature(right, tax)),
      );
    });

    test('includes who so partner vs neighbor swings differ', () {
      final partners = Figure(move: 'swing', params: {'who': 'partners'});
      final neighbors = Figure(move: 'swing', params: {'who': 'neighbors'});
      expect(
        figureSnippetSignature(partners, tax),
        isNot(figureSnippetSignature(neighbors, tax)),
      );
    });

    test('excludes beats from the signature', () {
      final a = Figure(move: 'swing', params: {'who': 'partners', 'beats': 16});
      final b = Figure(move: 'swing', params: {'who': 'partners', 'beats': 8});
      expect(figureSnippetSignature(a, tax), figureSnippetSignature(b, tax));
    });

    test('normalizes integral turns without a trailing .0', () {
      final sig = figureSnippetSignature(
        Figure(move: 'allemande', params: {'turn': 1.0}),
        tax,
      );
      expect(sig, contains('turn=1'));
      expect(sig, isNot(contains('turn=1.0')));
    });

    test('is deterministic regardless of param insertion order', () {
      final a = Figure(
        move: 'allemande',
        params: {'turn': 1.5, 'hand': 'left', 'who': 'partners'},
      );
      final b = Figure(
        move: 'allemande',
        params: {'who': 'partners', 'hand': 'left', 'turn': 1.5},
      );
      expect(figureSnippetSignature(a, tax), figureSnippetSignature(b, tax));
    });

    test('returns null for custom / parse-gap figures', () {
      expect(
        figureSnippetSignature(
          testFigure(move: customMove, params: {'text': 'weave the ring'}),
          tax,
        ),
        isNull,
      );
    });

    test('returns null for an unknown move', () {
      expect(
        figureSnippetSignature(Figure(move: 'not_a_real_move'), tax),
        isNull,
      );
    });
  });

  group('describeFigureSignature', () {
    final renderer = FigureRenderer(tax);
    final dialect = Dialect.canonical;

    test('renders a readable label round-tripping from a real figure', () {
      final figure = Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'left', 'turn': 1.5},
      );
      final sig = figureSnippetSignature(figure, tax)!;
      final label = describeFigureSignature(sig, tax, renderer, dialect);
      expect(label, renderer.render(figure, dialect));
      expect(label.toLowerCase(), contains('allemande'));
    });

    test('falls back to the raw signature for an unknown move', () {
      expect(
        describeFigureSignature('bogus_move(x=y)', tax, renderer, dialect),
        'bogus_move(x=y)',
      );
    });

    test('falls back to the raw signature for a malformed string', () {
      expect(
        describeFigureSignature('not a signature!!', tax, renderer, dialect),
        'not a signature!!',
      );
    });
  });
}
