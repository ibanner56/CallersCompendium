import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final dialect = Dialect.larksRobins;
  const structure = PhraseStructure.standard;

  FigureDiffResult diff(List<Figure> oldFigures, List<Figure> newFigures) =>
      diffFigures(
        oldFigures: oldFigures,
        oldStructure: structure,
        newFigures: newFigures,
        newStructure: structure,
        taxonomy: tax,
        renderer: renderer,
        dialect: dialect,
      );

  group('figureCanonicalKey', () {
    test('folds taxonomy defaults so explicit == defaulted', () {
      final defaulted = Figure(move: 'allemande');
      final explicit = Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.0},
      );
      expect(
        figureCanonicalKey(defaulted, tax),
        figureCanonicalKey(explicit, tax),
      );
    });

    test('ignores beats (owner-locked #686 decision)', () {
      final short = Figure(move: 'swing', params: {'beats': 8});
      final long = Figure(move: 'swing', params: {'beats': 16});
      expect(figureCanonicalKey(short, tax), figureCanonicalKey(long, tax));
    });

    test(
      'ignores progression (a top-level Figure field, never in the key)',
      () {
        final a = Figure(move: 'swing', progression: false);
        final b = Figure(move: 'swing', progression: true);
        expect(figureCanonicalKey(a, tax), figureCanonicalKey(b, tax));
      },
    );

    test('ignores note/walkthroughOverride/customOrigin/assumedSubject', () {
      final plain = Figure(move: 'do_si_do');
      final annotated = Figure(
        move: 'do_si_do',
        note: 'scoop them up',
        walkthroughOverride: 'do-si-do your neighbor',
        customOrigin: CustomOrigin.importGap,
        assumedSubject: true,
      );
      expect(
        figureCanonicalKey(plain, tax),
        figureCanonicalKey(annotated, tax),
      );
    });

    test('distinguishes a real param difference (hand)', () {
      final left = Figure(move: 'allemande', params: {'hand': 'left'});
      final right = Figure(move: 'allemande', params: {'hand': 'right'});
      expect(
        figureCanonicalKey(left, tax),
        isNot(figureCanonicalKey(right, tax)),
      );
    });

    test('custom figures key on trimmed/whitespace-collapsed text', () {
      final a = customFigure('  Circle   left   once  around  ');
      final b = customFigure('Circle left once around');
      expect(figureCanonicalKey(a, tax), figureCanonicalKey(b, tax));
    });

    test('custom figures with real text differences key differently', () {
      final a = customFigure('Circle left once around');
      final b = customFigure('Circle right once around');
      expect(figureCanonicalKey(a, tax), isNot(figureCanonicalKey(b, tax)));
    });

    test('malformed (non-String) custom text is treated as empty, never throws '
        '(OWASP: params come from untrusted import content)', () {
      final malformed = invalidTestFigure(
        move: customMove,
        params: {'text': 42},
        reason:
            'non-String custom text must be treated as empty and never throw (OWASP: import content is untrusted)',
      );
      expect(() => figureCanonicalKey(malformed, tax), returnsNormally);
      expect(
        figureCanonicalKey(malformed, tax),
        figureCanonicalKey(customFigure(''), tax),
      );
    });

    test('meanwhile container folds all sides into one key', () {
      final a = Figure.meanwhile(
        beats: 8,
        figures: [
          Figure(move: 'allemande', params: {'hand': 'left'}),
          customFigure('shadow does a solo twirl'),
        ],
      );
      final aAgain = Figure.meanwhile(
        beats: 8,
        figures: [
          Figure(move: 'allemande', params: {'hand': 'left'}),
          customFigure('shadow does a solo twirl'),
        ],
      );
      final differentSide = Figure.meanwhile(
        beats: 8,
        figures: [
          Figure(move: 'allemande', params: {'hand': 'right'}),
          customFigure('shadow does a solo twirl'),
        ],
      );
      expect(figureCanonicalKey(a, tax), figureCanonicalKey(aAgain, tax));
      expect(
        figureCanonicalKey(a, tax),
        isNot(figureCanonicalKey(differentSide, tax)),
      );
    });

    test('meanwhile beats-only difference still folds identical (beats '
        'excluded even at the container level)', () {
      final a = Figure.meanwhile(
        beats: 8,
        figures: [
          Figure(move: 'allemande'),
          Figure(move: 'do_si_do'),
        ],
      );
      final b = Figure.meanwhile(
        beats: 16,
        figures: [
          Figure(move: 'allemande'),
          Figure(move: 'do_si_do'),
        ],
      );
      expect(figureCanonicalKey(a, tax), figureCanonicalKey(b, tax));
    });

    test('unknown move still gets a comparable key (never throws/null)', () {
      // invalid-fixture: move is deliberately outside the taxonomy — unknown move still gets a comparable key (never throws/null)
      final a = Figure(move: 'some_future_move', params: {'foo': 'bar'});
      // invalid-fixture: move is deliberately outside the taxonomy — unknown move still gets a comparable key (never throws/null)
      final b = Figure(move: 'some_future_move', params: {'foo': 'bar'});
      // invalid-fixture: move is deliberately outside the taxonomy — unknown move still gets a comparable key (never throws/null)
      final c = Figure(move: 'some_future_move', params: {'foo': 'baz'});
      expect(figureCanonicalKey(a, tax), figureCanonicalKey(b, tax));
      expect(figureCanonicalKey(a, tax), isNot(figureCanonicalKey(c, tax)));
    });
  });

  group('diffFigures', () {
    test('identical canonical sequences → identical, no entries', () {
      final figures = [
        Figure(move: 'allemande', params: {'hand': 'left'}),
        Figure(move: 'swing'),
      ];
      final result = diff(figures, figures);
      expect(result.identical, isTrue);
      expect(result.entries, isEmpty);
      expect(result.truncated, isFalse);
      expect(result.omittedCount, 0);
    });

    test('dialect-only / annotation-only differences still compare '
        'identical (regression guard)', () {
      final oldFigures = [
        Figure(move: 'allemande', params: {'hand': 'left'}, note: 'gently'),
      ];
      final newFigures = [
        Figure(
          move: 'allemande',
          params: {'hand': 'left', 'beats': 16},
          walkthroughOverride: 'go left',
        ),
      ];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isTrue);
    });

    test('a single real param change produces a removed+added pair', () {
      final oldFigures = [
        Figure(move: 'allemande', params: {'hand': 'left'}),
      ];
      final newFigures = [
        Figure(move: 'allemande', params: {'hand': 'right'}),
      ];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].kind, FigureDiffKind.removed);
      expect(result.entries[1].kind, FigureDiffKind.added);
      expect(result.entries[0].displayText, contains('left'));
      expect(result.entries[1].displayText, contains('right'));
    });

    test('added figure at the end produces one added entry', () {
      final oldFigures = [Figure(move: 'swing')];
      final newFigures = [Figure(move: 'swing'), Figure(move: 'do_si_do')];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.entries, hasLength(1));
      expect(result.entries.single.kind, FigureDiffKind.added);
    });

    test('removed figure at the start produces one removed entry', () {
      final oldFigures = [Figure(move: 'do_si_do'), Figure(move: 'swing')];
      final newFigures = [Figure(move: 'swing')];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.entries, hasLength(1));
      expect(result.entries.single.kind, FigureDiffKind.removed);
    });

    test('reordered-but-otherwise-identical figures are NOT identical '
        '(order matters)', () {
      final a = [Figure(move: 'swing'), Figure(move: 'do_si_do')];
      final b = [Figure(move: 'do_si_do'), Figure(move: 'swing')];
      final result = diff(a, b);
      expect(result.identical, isFalse);
    });

    test('phrase labels on entries reflect deriveSections', () {
      // 16 beats per phrase (standard structure): a leading 16-beat swing
      // occupies A1. The differing figure that follows starts at beat 16 with
      // no explicit beat count (beats == 0). Beat 16 is the A1/A2 boundary;
      // a zero-beat figure at a phrase boundary is attributed to the preceding
      // phrase (A1), not the one that follows — see labelForFigure.
      final oldFigures = [
        Figure(move: 'swing', params: {'beats': 16}),
        Figure(move: 'allemande', params: {'hand': 'left'}),
      ];
      final newFigures = [
        Figure(move: 'swing', params: {'beats': 16}),
        Figure(move: 'allemande', params: {'hand': 'right'}),
      ];
      final result = diff(oldFigures, newFigures);
      expect(result.entries, hasLength(2));
      for (final entry in result.entries) {
        expect(entry.phraseLabel, 'A1');
      }
    });

    test('custom figure whitespace-only difference is identical', () {
      final oldFigures = [customFigure('Circle left once around')];
      final newFigures = [customFigure('  Circle   left once   around  ')];
      expect(diff(oldFigures, newFigures).identical, isTrue);
    });

    test('custom figure real text difference produces a diff', () {
      final oldFigures = [customFigure('Circle left once around')];
      final newFigures = [customFigure('Circle right once around')];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.entries, hasLength(2));
    });

    test('meanwhile sub-figure difference produces a diff at the container '
        'position', () {
      final oldFigures = [
        Figure.meanwhile(
          beats: 8,
          figures: [
            Figure(move: 'allemande', params: {'hand': 'left'}),
            Figure(move: 'do_si_do'),
          ],
        ),
      ];
      final newFigures = [
        Figure.meanwhile(
          beats: 8,
          figures: [
            Figure(move: 'allemande', params: {'hand': 'right'}),
            Figure(move: 'do_si_do'),
          ],
        ),
      ];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.entries, hasLength(2));
    });

    test('truncates rendered entries at kMaxFigureDiffLines', () {
      // Two entirely disjoint canonical-key spaces (different moves), so the
      // LCS finds zero overlap and every figure on both sides shows up as a
      // removed/added line — comfortably over kMaxFigureDiffLines.
      final count = kMaxFigureDiffLines + 5;
      final oldFigures = [
        for (var i = 0; i < count; i++)
          invalidTestFigure(
            move: 'allemande',
            params: {'turn': 1.0 + i},
            reason:
                'the loop sweeps turn past the taxonomy domain to exceed kMaxFigureDiffLines',
          ),
      ];
      final newFigures = [
        for (var i = 0; i < count; i++)
          invalidTestFigure(
            move: 'do_si_do',
            params: {'turn': 1.0 + i},
            reason:
                'the loop sweeps turn past the taxonomy domain to exceed kMaxFigureDiffLines',
          ),
      ];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.truncated, isTrue);
      expect(result.entries.length, kMaxFigureDiffLines);
      expect(result.omittedCount, greaterThan(0));
    });

    test('declines the full diff above kMaxFiguresForDiff, reporting a '
        'coarse omittedCount without throwing', () {
      final count = kMaxFiguresForDiff + 1;
      final oldFigures = [
        for (var i = 0; i < count; i++) Figure(move: 'swing'),
      ];
      final newFigures = [
        for (var i = 0; i < count; i++) Figure(move: 'do_si_do'),
      ];
      final result = diff(oldFigures, newFigures);
      expect(result.identical, isFalse);
      expect(result.truncated, isTrue);
      expect(result.entries, isEmpty);
      expect(result.omittedCount, oldFigures.length + newFigures.length);
    });
  });

  group('figuresCanonicallyIdentical', () {
    bool identical(List<Figure> oldFigures, List<Figure> newFigures) =>
        figuresCanonicallyIdentical(
          oldFigures: oldFigures,
          newFigures: newFigures,
          taxonomy: tax,
        );

    test('agrees with diffFigures.identical on an identical sequence', () {
      final figures = [
        Figure(move: 'allemande', params: {'hand': 'left'}),
        Figure(move: 'swing'),
      ];
      expect(identical(figures, figures), isTrue);
      expect(diff(figures, figures).identical, isTrue);
    });

    test('agrees with diffFigures.identical on a differing sequence', () {
      final oldFigures = [
        Figure(move: 'allemande', params: {'hand': 'left'}),
      ];
      final newFigures = [
        Figure(move: 'allemande', params: {'hand': 'right'}),
      ];
      expect(identical(oldFigures, newFigures), isFalse);
      expect(diff(oldFigures, newFigures).identical, isFalse);
    });

    test('ignores dialect/annotation-only differences, same as diffFigures '
        '(regression guard)', () {
      final oldFigures = [
        Figure(move: 'allemande', params: {'hand': 'left'}, note: 'gently'),
      ];
      final newFigures = [
        Figure(
          move: 'allemande',
          params: {'hand': 'left', 'beats': 16},
          walkthroughOverride: 'go left',
        ),
      ];
      expect(identical(oldFigures, newFigures), isTrue);
    });

    test('never computes the O(n·m) LCS pass — no FigureRenderer/Dialect '
        'required and no exception above kMaxFiguresForDiff', () {
      final count = kMaxFiguresForDiff + 1;
      final oldFigures = [
        for (var i = 0; i < count; i++) Figure(move: 'swing'),
      ];
      final newFigures = [
        for (var i = 0; i < count; i++) Figure(move: 'do_si_do'),
      ];
      expect(identical(oldFigures, newFigures), isFalse);
    });
  });
}
