import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// An import-gap custom figure carrying [text] as its stored (scrubbed) source
/// line — exactly how #398 leaves an unparseable line at import time.
Figure importGap(String text, {int beats = 0, bool progression = false}) =>
    customFigure(
      text,
      beats: beats,
      progression: progression,
      origin: CustomOrigin.importGap,
    );

void main() {
  group('reparseImportGapFigures', () {
    test('upgrades an import-gap custom whose text now parses structured', () {
      final result = reparseImportGapFigures([importGap('Neighbor swing')]);

      expect(result.upgradedCount, 1);
      final f = result.figures.single;
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
    });

    test('preserves beats and progression when upgrading', () {
      final result = reparseImportGapFigures([
        importGap('Neighbor swing', beats: 12, progression: true),
      ]);

      final f = result.figures.single;
      expect(f.move, 'swing');
      expect(f.params['beats'], 12);
      expect(f.progression, isTrue);
    });

    test('leaves an import-gap custom that still will not parse unchanged', () {
      final original = importGap('hey for four');
      final result = reparseImportGapFigures([original]);

      expect(result.upgradedCount, 0);
      expect(result.figures.single, same(original));
      expect(result.figures.single.customOrigin, CustomOrigin.importGap);
    });

    test('never touches a user-entered custom, even if its text parses', () {
      final userCustom = customFigure('Neighbor swing');
      final result = reparseImportGapFigures([userCustom]);

      expect(result.upgradedCount, 0);
      expect(result.figures.single, same(userCustom));
      expect(result.figures.single.isCustom, isTrue);
    });

    test('never touches an already-structured figure', () {
      final structured = Figure(
        move: 'swing',
        params: const {'who': 'partners', 'beats': 8},
      );
      final result = reparseImportGapFigures([structured]);

      expect(result.upgradedCount, 0);
      expect(result.figures.single, same(structured));
    });

    test('returns the input list unchanged when nothing upgrades', () {
      final input = [importGap('hey for four'), customFigure('Neighbor swing')];
      final result = reparseImportGapFigures(input);

      expect(result.changed, isFalse);
      expect(result.figures, same(input));
    });

    test('upgrades only the qualifying figures in a mixed list', () {
      final structured = Figure(move: 'circle', params: const {'beats': 8});
      final input = [
        structured,
        importGap('Neighbor swing'), // upgrades
        importGap('hey for four'), // stays custom
        customFigure('Neighbor swing'), // user-entered, untouched
      ];

      final result = reparseImportGapFigures(input);

      expect(result.upgradedCount, 1);
      expect(result.figures[0], same(structured));
      expect(result.figures[1].move, 'swing');
      expect(result.figures[1].isCustom, isFalse);
      expect(result.figures[2].isCustom, isTrue);
      expect(result.figures[2].customOrigin, CustomOrigin.importGap);
      expect(result.figures[3].isCustom, isTrue);
      expect(result.figures[3].customOrigin, CustomOrigin.userEntered);
    });

    test('is idempotent — a second run changes nothing further', () {
      final first = reparseImportGapFigures([
        importGap('Neighbor swing'),
        importGap('hey for four'),
      ]);
      expect(first.upgradedCount, 1);

      final second = reparseImportGapFigures(first.figures);
      expect(second.upgradedCount, 0);
      expect(second.figures, same(first.figures));
    });

    group('untrusted stored text guards (parse-never-fails)', () {
      test('non-String text is left as import-gap without throwing', () {
        // A hand-built custom figure with a non-String text param — treat as
        // malformed stored data and leave it alone.
        final figure = invalidTestFigure(
          move: customMove,
          params: const {'text': 42},
          customOrigin: CustomOrigin.importGap,
          reason:
              'malformed stored data: a non-String text param must be left alone rather than throwing',
        );

        final result = reparseImportGapFigures([figure]);
        expect(result.upgradedCount, 0);
        expect(result.figures.single, same(figure));
      });

      test('empty/whitespace text is left unchanged', () {
        final figure = testFigure(
          move: customMove,
          params: const {'text': '   '},
          customOrigin: CustomOrigin.importGap,
        );

        final result = reparseImportGapFigures([figure]);
        expect(result.upgradedCount, 0);
        expect(result.figures.single, same(figure));
      });

      test(
        'oversized text is skipped (no unbounded work) without throwing',
        () {
          final huge = 'Neighbor swing ${'x' * (maxReparseTextLength + 1)}';
          final figure = testFigure(
            move: customMove,
            params: {'text': huge},
            customOrigin: CustomOrigin.importGap,
          );

          final result = reparseImportGapFigures([figure]);
          expect(result.upgradedCount, 0);
          expect(result.figures.single, same(figure));
        },
      );

      test('oversized RAW text is rejected before trimming', () {
        // A huge raw string that would trim down to a small parseable line must
        // still be rejected on its RAW length — we never do the multi-MB
        // trim/copy just to discover it is short after whitespace removal.
        final huge = '${' ' * (maxReparseTextLength + 1)}Neighbor swing ';
        final figure = testFigure(
          move: customMove,
          params: {'text': huge},
          customOrigin: CustomOrigin.importGap,
        );

        final result = reparseImportGapFigures([figure]);
        expect(result.upgradedCount, 0);
        expect(result.figures.single, same(figure));
      });
    });

    group('note handling on upgrade', () {
      test('merges a distinct original note with the recognizer note', () {
        final figure = testFigure(
          move: customMove,
          params: const {'text': 'Ladies chain to neighbor'},
          note: 'scoop them up',
          customOrigin: CustomOrigin.importGap,
        );

        final result = reparseImportGapFigures([figure]);
        expect(result.upgradedCount, 1);
        final f = result.figures.single;
        expect(f.move, 'chain');
        // Both notes retained (original first), so neither is dropped.
        expect(f.note, 'scoop them up; to neighbor');
      });

      test('keeps the original note when the recognizer adds none', () {
        final figure = testFigure(
          move: customMove,
          params: const {'text': 'Neighbor swing'},
          note: 'big smiles',
          customOrigin: CustomOrigin.importGap,
        );

        final result = reparseImportGapFigures([figure]);
        expect(result.figures.single.move, 'swing');
        expect(result.figures.single.note, 'big smiles');
      });

      test('keeps the recognizer note when the original had none', () {
        final result = reparseImportGapFigures([
          importGap('Ladies chain to neighbor'),
        ]);
        expect(result.figures.single.note, 'to neighbor');
      });

      test('does not duplicate an identical note', () {
        final figure = testFigure(
          move: customMove,
          params: const {'text': 'Ladies chain to neighbor'},
          note: 'to neighbor',
          customOrigin: CustomOrigin.importGap,
        );

        final result = reparseImportGapFigures([figure]);
        expect(result.figures.single.note, 'to neighbor');
      });
    });

    test('empty figure list is a no-op', () {
      final result = reparseImportGapFigures(const []);
      expect(result.upgradedCount, 0);
      expect(result.figures, isEmpty);
    });

    group('fan-out across source front-ends', () {
      test('upgrades an import-gap custom whose text is a CallersBox/TCB hey '
          'pass-list (the fan-out reaches the TCB front-end)', () {
        final result = reparseImportGapFigures([
          importGap('hey 1/2 (ml;pr)', beats: 8),
        ]);
        expect(result.upgradedCount, 1);
        final f = result.figures.single;
        expect(f.isCustom, isFalse);
        expect(f.move, 'hey');
        expect(f.params['beats'], 8);
      });

      test('the hey upgrade is idempotent (a second run changes nothing)', () {
        final first = reparseImportGapFigures([importGap('hey 1/2 (ml;pr)')]);
        final second = reparseImportGapFigures(first.figures);
        expect(second.upgradedCount, 0);
        expect(identical(second.figures, first.figures), isTrue);
      });

      test('upgrades an old TCB `||` whole-custom to a meanwhile container '
          '(#591/#572)', () {
        // Before #591, an import-gap custom stored the WHOLE `||` line
        // verbatim (parse-never-fails, but simultaneity wasn't modeled).
        // The reparse-upgrade mechanism now fans it into the same
        // meanwhile container a fresh import produces, without the user
        // deleting/re-importing.
        final result = reparseImportGapFigures([
          importGap('Balance || swing', beats: 6),
        ]);
        expect(result.upgradedCount, 1);
        final f = result.figures.single;
        expect(f.isCustom, isFalse);
        expect(f.isMeanwhile, isTrue);
        expect(f.params['beats'], 6);
        expect(f.subFigures.map((s) => s.move), ['balance', 'swing']);
      });

      test('upgrades an old ContraDB `while` whole-custom to a meanwhile '
          'container (#591/#572)', () {
        final result = reparseImportGapFigures([
          importGap(
            'gentlespoons dance out while ladles dance in to a long wave '
            'in the center - balance the wave',
            beats: 8,
          ),
        ]);
        expect(result.upgradedCount, 1);
        final f = result.figures.single;
        expect(f.isCustom, isFalse);
        expect(f.isMeanwhile, isTrue);
        expect(f.params['beats'], 8);
        expect(f.subFigures[0].isCustom, isTrue);
        expect(f.subFigures[1].move, 'form_a_long_wave');
      });

      test('a `||` line that still degrades entirely to custom (7+ sides) '
          'stays import-gap, unchanged (idempotent safety net)', () {
        final line = List.filled(7, 'Circle left').join(' || ');
        final original = importGap(line, beats: 8);
        final result = reparseImportGapFigures([original]);
        expect(result.upgradedCount, 0);
        expect(result.figures.single, same(original));
      });

      test('the `||` meanwhile upgrade is idempotent (a second run changes '
          'nothing)', () {
        final first = reparseImportGapFigures([
          importGap('Balance || swing', beats: 6),
        ]);
        expect(first.upgradedCount, 1);
        final second = reparseImportGapFigures(first.figures);
        expect(second.upgradedCount, 0);
        expect(identical(second.figures, first.figures), isTrue);
      });
    });

    // --- meanwhile recursion ---
    // Before this fix, reparseImportGapFigures iterated the top-level list
    // only. _tryUpgrade bails on `!figure.isCustom`; a meanwhile container is
    // never isCustom, so any custom figures nested inside a meanwhile were
    // permanently invisible to reparse — upgradedCount would be 0 for any
    // meanwhile input regardless of its sides.
    group('meanwhile recursion', () {
      test(
          'upgrades an import-gap custom side inside an existing meanwhile '
          'container', () {
        // "Neighbor swing" structures; "give and take" does not.
        final container = Figure.meanwhile(
          figures: [
            importGap('Neighbor swing', beats: 8),
            importGap('give and take', beats: 8),
          ],
          beats: 16,
        );
        final result = reparseImportGapFigures([container]);

        expect(result.upgradedCount, 1);
        final rebuilt = result.figures.single;
        expect(rebuilt.isMeanwhile, isTrue);
        expect(rebuilt.subFigures[0].move, 'swing');
        expect(rebuilt.subFigures[1].isCustom, isTrue);
      });

      // Mutation falsification: the naive implementation rebuilds the container
      // using sum-of-side-beats rather than preserving the container's own
      // beats. Use beats:10 (container) vs beats:6 (each side) so summing
      // sides yields 12 ≠ 10, and the test catches the mutation.
      test(
          'preserves container beats when rebuilding — container beats are '
          'the authoritative section total, not the sum of sides', () {
        final container = Figure.meanwhile(
          figures: [
            importGap('Neighbor swing', beats: 6),
            importGap('give and take', beats: 6),
          ],
          beats: 10,
        );
        final result = reparseImportGapFigures([container]);

        expect(result.upgradedCount, 1);
        expect(result.figures.single.beats, 10);
      });

      test('no-op when no side structures — input list identity preserved', () {
        final container = Figure.meanwhile(
          figures: [
            importGap('give and take', beats: 8),
            importGap('secret figure', beats: 8),
          ],
          beats: 16,
        );
        final result = reparseImportGapFigures([container]);

        expect(result.changed, isFalse);
        expect(result.upgradedCount, 0);
        expect(identical(result.figures, [container]), isFalse);
        expect(result.figures.single, same(container));
      });

      test('idempotent — second run finds nothing further to upgrade', () {
        final container = Figure.meanwhile(
          figures: [
            importGap('Neighbor swing', beats: 8),
            importGap('give and take', beats: 8),
          ],
          beats: 16,
        );
        final first = reparseImportGapFigures([container]);
        expect(first.upgradedCount, 1);

        final second = reparseImportGapFigures(first.figures);
        expect(second.upgradedCount, 0);
        expect(identical(second.figures, first.figures), isTrue);
      });

      test('counts each upgraded side, not each container', () {
        // Both sides of this meanwhile structure; upgradedCount should be 2.
        final container = Figure.meanwhile(
          figures: [
            importGap('Neighbor swing', beats: 8),
            importGap('Circle left 3/4', beats: 8),
          ],
          beats: 16,
        );
        final result = reparseImportGapFigures([container]);

        expect(result.upgradedCount, 2);
      });
    });
  });
}
