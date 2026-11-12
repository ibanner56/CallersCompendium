import 'package:compendium_app/src/export/calling_card_highlight.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const move = CallingCardSpanKind.move;
  const dancer = CallingCardSpanKind.dancer;
  const amount = CallingCardSpanKind.amount;
  const plain = CallingCardSpanKind.plain;

  List<(String, CallingCardSpanKind)> spans(
    String line, {
    List<String> moves = const [],
    Set<String> dancers = const {},
  }) {
    final result = highlightFigureLine(line, moves: moves, dancers: dancers);
    expect(result.map((s) => s.text).join(), line, reason: 'joins back');
    return [for (final s in result) (s.text, s.kind)];
  }

  group('highlightFigureLine', () {
    test('moves, dancers and amounts, the rest plain', () {
      expect(
        spans(
          'neighbor allemande left 1½',
          moves: ['allemande'],
          dancers: {'neighbor', 'neighbors'},
        ),
        [
          ('neighbor', dancer),
          (' ', plain),
          ('allemande', move),
          (' left ', plain),
          ('1½', amount),
        ],
      );
    });

    test('whole words only, ignoring case', () {
      expect(spans('Swingers swing', moves: ['swing']), [
        ('Swingers ', plain),
        ('swing', move),
      ]);
      expect(spans('Larks pass left', dancers: {'lark', 'larks'}), [
        ('Larks', dancer),
        (' pass left', plain),
      ]);
    });

    test('a longer name wins over a shorter one inside it', () {
      expect(
        spans(
          'next neighbors swing',
          moves: ['swing'],
          dancers: {'neighbors', 'next neighbors'},
        ),
        [('next neighbors', dancer), (' ', plain), ('swing', move)],
      );
    });

    test('a move wins over a dancer word in the same place', () {
      expect(
        spans('partner swing', moves: ['partner swing'], dancers: {'partner'}),
        [('partner swing', move)],
      );
    });

    test('amounts', () {
      for (final (line, expected) in [
        ('circle left 3 places', '3 places'),
        ('circle left 1 place', '1 place'),
        ('allemande 3/4', '3/4'),
        ('gypsy ¾', '¾'),
        ('dosido once', 'once'),
        ('allemande once and a half', 'once and a half'),
        ('mad robin counterclockwise', 'counterclockwise'),
        ('star clockwise', 'clockwise'),
        ('balance twice', 'twice'),
      ]) {
        final found = [
          for (final (text, kind) in spans(line))
            if (kind == amount) text,
        ];
        expect(found, [expected], reason: line);
      }
      // Numbers inside words are not amounts.
      expect(spans('role1s chain'), [('role1s chain', plain)]);
    });

    test('an empty line has no spans', () {
      expect(spans(''), isEmpty);
    });
  });

  group('on rendered figure lines', () {
    final renderer = FigureRenderer(contraTaxonomy);
    final dialect = Dialect.larksRobins;
    final dancers = renderer.dancerTerms(dialect);

    List<(String, CallingCardSpanKind)> rendered(Figure figure) {
      final line = renderer.renderSummary(figure, dialect);
      return spans(
        line,
        moves: callingCardMoveNames(figure, renderer, dialect),
        dancers: dancers,
      );
    }

    test('a dancer, a move and an amount', () {
      final result = rendered(
        Figure(
          move: 'allemande',
          params: {'who': 'neighbors', 'hand': 'left', 'travel': 1.5},
        ),
      );
      expect(result, contains(('allemande', move)));
      expect(result, contains(('neighbor', dancer)));
      expect(result, contains(('1½', amount)));
    });

    test('the dialect names the dancers', () {
      final result = rendered(
        Figure(move: 'chain', params: {'who': 'role2s', 'beats': 8}),
      );
      expect(result, contains(('robins', dancer)));
      expect(result, contains(('chain', move)));
    });

    test('a move is found under either of its names', () {
      final gypsy = Figure(move: 'gypsy', params: const {});
      final names = callingCardMoveNames(
        gypsy,
        renderer,
        dialect,
        canonicalizeDiscouragedTerms: true,
      );
      expect(names, containsAll(['gypsy', 'shoulder round']));
      final line = renderer.renderSummaryWithCanonicalDiscouragedTerms(
        gypsy,
        dialect,
      );
      final marked = [
        for (final s in highlightFigureLine(
          line,
          moves: names,
          dancers: dancers,
        ))
          if (s.kind == move) s.text,
      ];
      expect(marked, isNotEmpty, reason: line);
    });

    test('a free-text figure is not highlighted', () {
      expect(
        callingCardHighlights(
          Figure(move: customMove, params: const {'text': 'lead once more'}),
        ),
        isFalse,
      );
      expect(callingCardHighlights(Figure(move: 'swing')), isTrue);
    });

    test("a container offers its figures' moves, not its own name", () {
      final figure = Figure.meanwhile(
        figures: [
          Figure(move: 'swing', params: {'who': 'partners'}),
          Figure(move: customMove, params: const {'text': 'meanwhile, wave'}),
        ],
        beats: 8,
      );
      final names = callingCardMoveNames(figure, renderer, dialect);
      expect(names, contains('swing'));
      expect(names, isNot(contains('meanwhile')));
      expect(names, isNot(contains('custom')));
    });

    test("a %S move name takes the figure's default side", () {
      // The line reads "neighbor right gypsy once": the shoulder is left to
      // its default, which the substitution needs to name the move.
      final sided = Dialect(
        name: 'Sided',
        moves: const {'shoulder_round': '%S gypsy'},
      );
      final figure = Figure(move: 'shoulder_round', params: const {});
      final line = renderer.renderSummary(figure, sided);
      final marked = [
        for (final s in highlightFigureLine(
          line,
          moves: callingCardMoveNames(figure, renderer, sided),
          dancers: renderer.dancerTerms(sided),
        ))
          if (s.kind == move) s.text,
      ];
      expect(marked, ['right gypsy'], reason: line);
    });

    test('a container figure highlights the moves inside it', () {
      final figure = Figure.meanwhile(
        figures: [
          Figure(move: 'swing', params: {'who': 'partners'}),
          Figure(move: 'balance', params: {'who': 'neighbors'}),
        ],
        beats: 8,
      );
      final names = callingCardMoveNames(figure, renderer, dialect);
      expect(names, containsAll(['swing', 'balance']));
      final result = rendered(figure);
      expect(result, contains(('swing', move)));
      expect(result, contains(('balance', move)));
    });
  });
}
