import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final tax = contraTaxonomy;
  final now = DateTime.utc(2026);

  Dance danceWith(List<Figure> figures) => Dance(
    id: 'd1',
    title: 'Test Dance',
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );

  WalkthroughSnippetLibrary libFor(Figure figure, String text) =>
      WalkthroughSnippetLibrary.empty.withSnippet(
        figureSnippetSignature(figure, tax)!,
        text,
      );

  group('resolveFigureSnippet', () {
    test('override wins over the library default', () {
      final base = Figure(move: 'swing', params: {'who': 'partners'});
      final lib = libFor(base, 'default swing');
      final figure = base.copyWith(walkthroughOverride: 'just this dance');
      expect(resolveFigureSnippet(figure, lib, tax), 'just this dance');
    });

    test('falls back to the library default by signature', () {
      final figure = Figure(move: 'swing', params: {'who': 'partners'});
      final lib = libFor(figure, 'default swing');
      expect(resolveFigureSnippet(figure, lib, tax), 'default swing');
    });

    test('returns null when neither override nor default exists', () {
      final figure = Figure(move: 'swing', params: {'who': 'partners'});
      expect(
        resolveFigureSnippet(figure, WalkthroughSnippetLibrary.empty, tax),
        isNull,
      );
    });

    test('custom figure uses its override (no signature)', () {
      final figure = Figure(
        move: customMove,
        params: {'text': 'weave'},
        walkthroughOverride: 'weave the ring slowly',
      );
      expect(
        resolveFigureSnippet(figure, WalkthroughSnippetLibrary.empty, tax),
        'weave the ring slowly',
      );
    });
  });

  group('assembleWalkthrough', () {
    test('joins per-figure snippets in order, skipping empty ones', () {
      final circle = Figure(move: 'circle', params: {'turn': 'left'});
      final lib = WalkthroughSnippetLibrary.empty.withSnippet(
        figureSnippetSignature(circle, tax)!,
        'Circle left.',
      );
      final dance = danceWith([
        circle,
        Figure(move: 'petronella'), // no snippet -> skipped
        Figure(
          move: 'swing',
          params: {'who': 'partners'},
          walkthroughOverride: 'Swing them!',
        ),
      ]);
      expect(
        assembleWalkthrough(dance: dance, library: lib, taxonomy: tax),
        'Circle left.\n\nSwing them!',
      );
    });

    test('returns empty string when no figure resolves', () {
      final dance = danceWith([Figure(move: 'petronella')]);
      expect(
        assembleWalkthrough(
          dance: dance,
          library: WalkthroughSnippetLibrary.empty,
          taxonomy: tax,
        ),
        '',
      );
    });

    test('soft-clamps the assembled result to kMaxWalkthroughLength', () {
      final big = 'x' * kMaxWalkthroughSnippetLength;
      final figures = [
        Figure(
          move: 'swing',
          params: {'who': 'partners'},
          walkthroughOverride: big,
        ),
        Figure(
          move: 'swing',
          params: {'who': 'neighbors'},
          walkthroughOverride: big,
        ),
        Figure(
          move: 'circle',
          params: {'turn': 'left'},
          walkthroughOverride: big,
        ),
        Figure(
          move: 'circle',
          params: {'turn': 'right'},
          walkthroughOverride: big,
        ),
        Figure(
          move: 'star',
          params: {'hand': 'right'},
          walkthroughOverride: big,
        ),
        Figure(
          move: 'star',
          params: {'hand': 'left'},
          walkthroughOverride: big,
        ),
      ];
      final out = assembleWalkthrough(
        dance: danceWith(figures),
        library: WalkthroughSnippetLibrary.empty,
        taxonomy: tax,
      );
      expect(out.length, kMaxWalkthroughLength);
    });

    test('danceHasAssemblableWalkthrough reflects resolvability', () {
      final figure = Figure(move: 'swing', params: {'who': 'partners'});
      final lib = libFor(figure, 'Swing.');
      expect(
        danceHasAssemblableWalkthrough(danceWith([figure]), lib, tax),
        isTrue,
      );
      expect(
        danceHasAssemblableWalkthrough(
          danceWith([Figure(move: 'petronella')]),
          lib,
          tax,
        ),
        isFalse,
      );
    });
  });
}
