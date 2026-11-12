import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

void main() {
  final tax = contraTaxonomy;

  group('figureSnippetSignature', () {
    test('migrates legacy pull-by dimensions and zig-zag slide keys', () {
      expect(
        migrateFigureSnippetSignature('pull_by_dancers(who=neighbors)'),
        'pull_by(where=unspecified,who=neighbors)',
      );
      expect(
        migrateFigureSnippetSignature('pull_by_direction(where=along)'),
        'pull_by(where=along,who=unspecified)',
      );
      expect(
        migrateFigureSnippetSignature('zig_zag(turn=right)'),
        'zig_zag(slide=right)',
      );
    });

    test('rebuilds migrated parameters in sorted order', () {
      expect(
        migrateFigureSnippetSignature('circle(places=3,turn=right)'),
        'circle(direction=right,places=3)',
      );
    });

    test('folds taxonomy defaults so explicit == defaulted', () {
      // allemande defaults: who=neighbors, hand=right, travel=1.5.
      final defaulted = Figure(move: 'allemande');
      final explicit = Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'travel': 1.5},
      );
      expect(
        figureSnippetSignature(defaulted, tax),
        figureSnippetSignature(explicit, tax),
      );
    });

    test('distinguishes allemande left ½ from right 1½', () {
      final left = Figure(
        move: 'allemande',
        params: {'hand': 'left', 'travel': 0.5},
      );
      final right = Figure(
        move: 'allemande',
        params: {'hand': 'right', 'travel': 1.5},
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
        Figure(move: 'allemande', params: {'travel': 1.0}),
        tax,
      );
      expect(sig, contains('travel=1'));
      expect(sig, isNot(contains('travel=1.0')));
    });

    test('is deterministic regardless of param insertion order', () {
      final a = Figure(
        move: 'allemande',
        params: {'travel': 1.5, 'hand': 'left', 'who': 'partners'},
      );
      final b = Figure(
        move: 'allemande',
        params: {'who': 'partners', 'hand': 'left', 'travel': 1.5},
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
        // invalid-fixture: move is deliberately outside the taxonomy — returns null for an unknown move
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
        params: {'who': 'neighbors', 'hand': 'left', 'travel': 1.5},
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

  group('an other fraction amount (#2120)', () {
    final renderer = FigureRenderer(tax);
    Figure f8(Map<String, Object?> p) =>
        testFigure(move: 'figure_8', params: p);

    test('a stated amount joins the signature', () {
      expect(
        figureSnippetSignature(f8({'fraction': 'other', 'amount': 1.5}), tax),
        'figure_8(amount=1.5,fraction=other,who=ones)',
      );
      expect(
        figureSnippetSignature(f8({'fraction': 'other', 'amount': 2}), tax),
        'figure_8(amount=2,fraction=other,who=ones)',
      );
    });

    test('every key a pre-v39 figure could have is unchanged', () {
      expect(
        figureSnippetSignature(f8({'fraction': 'other'}), tax),
        'figure_8(fraction=other,who=ones)',
      );
      // A stale amount under a named fraction is not part of the figure.
      expect(
        figureSnippetSignature(f8({'fraction': 'half', 'amount': 2}), tax),
        'figure_8(fraction=half,who=ones)',
      );
    });

    test('migration keeps a figure 8 amount and still renames orbit', () {
      expect(
        migrateFigureSnippetSignature(
          'figure_8(amount=1.5,fraction=other,who=ones)',
        ),
        'figure_8(amount=1.5,fraction=other,who=ones)',
      );
      expect(
        migrateFigureSnippetSignature('orbit(amount=0.5,turn=clockwise)'),
        'orbit(direction=clockwise,travel=0.5)',
      );
    });

    test('a signature with an amount describes as its figure', () {
      expect(
        describeFigureSignature(
          'figure_8(amount=1.5,fraction=other,who=ones)',
          tax,
          renderer,
          Dialect.larksRobins,
        ),
        startsWith('ones 1½ figure 8'),
      );
    });
  });
}
