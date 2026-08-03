import 'package:compendium_app/src/widgets/program_matrix_table.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/l10n_harness.dart';
import 'package:compendium_core/testing.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13);

  Dance dance(
    String id,
    String title,
    List<Figure> figures, {
    Formation? formation,
  }) => Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
    formation: formation ?? const Formation(FormationShape.dupleImproper),
  );

  // Figures carry realistic beats so phrase derivation (A1/A2/B1/B2…) is
  // meaningful: each figure fills one 16-beat phrase, so a dance's figures
  // occupy sequential phrases (figure 0 → A1, figure 1 → A2, …). This mirrors
  // real dances and keeps the same-figure-same-phrase collision check (#582)
  // from firing spuriously just because every beats-less figure would derive
  // to A1.
  Figure move(String id, [int beats = 16]) =>
      testFigure(move: id, params: {'beats': beats});
  Figure swing([String? who, int beats = 16]) =>
      testFigure(move: 'swing', params: {'who': ?who, 'beats': beats});
  Figure hey([String? length, int beats = 16]) =>
      testFigure(move: 'hey', params: {'length': ?length, 'beats': beats});

  Future<void> pump(
    WidgetTester tester, {
    required List<Dance> dances,
    int omittedFreeTextCount = 0,
    Set<String> altDanceIds = const {},
    Dialect? dialect,
    List<ProgramHalf?>? halves,
    Set<int> hiddenColumns = const {},
    ValueChanged<int>? onHideColumn,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,

        home: Scaffold(
          body: ProgramMatrixTable(
            matrix: buildProgramMatrix(dances, halves: halves),
            taxonomy: contraTaxonomy,
            dialect: dialect ?? Dialect.canonical,
            omittedFreeTextCount: omittedFreeTextCount,
            altDanceIds: altDanceIds,
            hiddenColumns: hiddenColumns,
            onHideColumn: onHideColumn,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders move column headers and dance row headers', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'Butterfly', [swing(), move('balance')]),
        dance('d2', 'Broken Sixpence', [swing()]),
      ],
    );

    // Row headers (dance titles).
    expect(find.text('Butterfly'), findsOneWidget);
    expect(find.text('Broken Sixpence'), findsOneWidget);
    // Swing is split by role: a partner-swing column (shared) plus the
    // always-present neighbor-swing baseline.
    expect(find.text('partner swing'), findsOneWidget);
    expect(find.text('neighbor swing'), findsOneWidget);
    expect(find.text('balance'), findsOneWidget);
  });

  testWidgets('renders split swing and hey headers present in the program', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing('role1s'), hey('full')]),
      ],
      dialect: Dialect.larksRobins,
    );

    // Baseline swing columns always render...
    expect(find.text('partner swing'), findsOneWidget);
    expect(find.text('neighbor swing'), findsOneWidget);
    // ...the present role split renders (dialect-aware role term)...
    expect(find.text('lark swing'), findsOneWidget);
    // ...and the present hey length renders (full only — no half baseline).
    expect(find.text('full hey'), findsOneWidget);
    expect(find.text('half hey'), findsNothing);
  });

  testWidgets('presence marks use an icon + semantics, not colour alone', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing(), move('balance')]),
        dance('d2', 'B', [move('balance'), swing()]),
      ],
    );

    // Three distinct shapes are in play so no state relies on colour alone:
    // a star for a move's program debut, a flag for a dance's own opening
    // figure (when not also a debut), and a check for any other present move.
    expect(find.byIcon(Icons.star), findsWidgets);
    expect(find.byIcon(Icons.flag_outlined), findsWidgets);
    expect(find.byIcon(Icons.check), findsWidgets);

    // A opens on a partner swing that also debuts here → star, both states.
    expect(
      find.bySemanticsLabel(
        "A, partner swing: present, introduced here, dance's first figure",
      ),
      findsOneWidget,
    );
    // balance debuts in A (mid-dance) → star, "introduced here" only.
    expect(
      find.bySemanticsLabel('A, balance: present, introduced here'),
      findsOneWidget,
    );
    // B opens on balance, but balance already debuted in A → flag only.
    expect(
      find.bySemanticsLabel("B, balance: present, dance's first figure"),
      findsOneWidget,
    );
    // B's partner swing is a plain repeat → check, "present".
    expect(find.bySemanticsLabel('B, partner swing: present'), findsOneWidget);
  });

  testWidgets('debut star and dance-first flag land on the correct columns', (
    tester,
  ) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing('neighbors')]),
      ],
    );

    // The legend spells out the meaning of each shape in text.
    expect(find.text('Introduced here'), findsOneWidget);
    expect(find.text("Dance's first figure"), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Same phrase as adjacent dance'), findsOneWidget);
    // A opens with a neighbor swing → the neighbor split column is both its
    // program debut and its first figure; the partner baseline is not present.
    expect(
      find.bySemanticsLabel(
        "A, neighbor swing: present, introduced here, dance's first figure",
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('A, partner swing: not present'),
      findsOneWidget,
    );
  });

  testWidgets('header cells are flagged as semantic headers', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
      ],
    );

    expect(find.bySemanticsLabel('Move: partner swing'), findsOneWidget);
    expect(find.bySemanticsLabel('Dance: A'), findsOneWidget);
  });

  testWidgets('absent cell announces "not present"', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
        dance('d2', 'B', [move('balance')]),
      ],
    );
    // A has no balance; B has no swing (so the baseline partner-swing column is
    // absent for B).
    expect(find.bySemanticsLabel('A, balance: not present'), findsOneWidget);
    expect(
      find.bySemanticsLabel('B, partner swing: not present'),
      findsOneWidget,
    );
  });

  testWidgets('empty matrix (no dances) shows the auto-fill empty state', (
    tester,
  ) async {
    await pump(tester, dances: const []);
    expect(find.text('No structured figures yet'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('empty matrix still notes omitted free-text slots', (
    tester,
  ) async {
    await pump(tester, dances: const [], omittedFreeTextCount: 3);
    expect(find.text('No structured figures yet'), findsOneWidget);
    expect(find.textContaining('3 free-text slots'), findsOneWidget);
  });

  testWidgets('omitted free-text slots are noted in a caption', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
      ],
      omittedFreeTextCount: 2,
    );
    expect(find.textContaining('2 free-text slots'), findsOneWidget);
  });

  testWidgets('alt dances are badged in the row header', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
        dance('d2', 'Alt Dance', [move('balance')]),
      ],
      altDanceIds: {'d2'},
    );
    expect(find.text('ALT'), findsOneWidget);
    expect(find.bySemanticsLabel('Alternate dance: Alt Dance'), findsOneWidget);
  });

  testWidgets('column labels honour the active dialect', (tester) async {
    await pump(
      tester,
      dances: [
        dance('d1', 'A', [swing()]),
      ],
      dialect: Dialect(name: 'Test', moves: const {'swing': 'twirl'}),
    );
    expect(find.text('partner twirl'), findsOneWidget);
    expect(find.text('neighbor twirl'), findsOneWidget);
    expect(find.text('partner swing'), findsNothing);
  });

  group('formation column (#663)', () {
    testWidgets('pinned formation column shows each dance\'s formation', (
      tester,
    ) async {
      await pump(
        tester,
        dances: [
          dance('d1', 'A', [
            swing(),
          ], formation: const Formation(FormationShape.becketCw)),
          dance('d2', 'B', [swing()]),
        ],
      );

      // Static header (no tooltip, matching #662's removal).
      expect(find.text('Formation'), findsOneWidget);
      // Per-row formation labels.
      expect(find.text('Becket (CW)'), findsOneWidget);
      expect(find.text('Duple improper'), findsOneWidget);
      // Each cell carries its own semantics label, independent of the
      // adjacent row header.
      expect(
        find.bySemanticsLabel('A, formation: Becket (CW)'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('B, formation: Duple improper'),
        findsOneWidget,
      );
    });

    testWidgets('formation free-text detail is appended to the label', (
      tester,
    ) async {
      await pump(
        tester,
        dances: [
          dance(
            'd1',
            'A',
            [swing()],
            formation: const Formation(
              FormationShape.other,
              detail: 'square set',
            ),
          ),
        ],
      );
      expect(find.textContaining('square set'), findsOneWidget);
    });
  });

  group('column-header tooltip removal (#662)', () {
    testWidgets('column headers have no tooltip — the label is the only text', (
      tester,
    ) async {
      await pump(
        tester,
        dances: [
          dance('d1', 'A', [swing(), move('balance')]),
        ],
      );

      // Scoped to the column-header cells specifically (rather than a
      // tree-wide `find.byType(Tooltip)`, which would also flag any
      // Tooltip legitimately added elsewhere in the matrix later): each
      // header label's own widget subtree has no Tooltip ancestor.
      for (final label in ['partner swing', 'neighbor swing', 'balance']) {
        expect(
          find.ancestor(of: find.text(label), matching: find.byType(Tooltip)),
          findsNothing,
        );
      }
    });

    testWidgets('header semantics label survives tooltip removal', (
      tester,
    ) async {
      await pump(
        tester,
        dances: [
          dance('d1', 'A', [swing()]),
        ],
      );

      // The accessible name was always sourced from the Semantics wrapper
      // above the (now-removed) Tooltip, not the Tooltip itself.
      expect(find.bySemanticsLabel('Move: partner swing'), findsOneWidget);
      expect(find.bySemanticsLabel('Move: neighbor swing'), findsOneWidget);
    });
  });

  group('header-strip scroll cue (#662)', () {
    Future<void> pumpAtWidth(
      WidgetTester tester, {
      required List<Dance> dances,
      required double width,
    }) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: ProgramMatrixTable(
              matrix: buildProgramMatrix(dances),
              taxonomy: contraTaxonomy,
              dialect: Dialect.canonical,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const rightCue = ValueKey('program-matrix-header-scroll-right');
    const leftCue = ValueKey('program-matrix-header-scroll-left');

    // Enough distinct moves that the header strip overflows even a
    // reasonably wide (but still tablet-range) surface.
    final manyMoveDances = [
      dance('d1', 'A', [
        swing(),
        move('balance'),
        move('do_si_do'),
        move('circle'),
        move('allemande'),
        move('star'),
        move('promenade'),
        move('right_left_through'),
        move('chain'),
        move('box_the_gnat'),
        move('california_twirl'),
        move('pass_through'),
        move('star_through'),
        move('poussette'),
        move('cross_trails'),
        hey('full'),
      ]),
    ];

    testWidgets('shows only the right cue when overflowing at rest', (
      tester,
    ) async {
      await pumpAtWidth(tester, dances: manyMoveDances, width: 700);

      expect(find.byKey(rightCue), findsOneWidget);
      expect(find.byKey(leftCue), findsNothing);
    });

    testWidgets(
      'right cue disappears and left cue appears once scrolled to the end',
      (tester) async {
        await pumpAtWidth(tester, dances: manyMoveDances, width: 700);

        await tester.drag(
          find.byKey(const ValueKey('program-matrix-body-h-scroll')),
          const Offset(-4000, 0),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(rightCue), findsNothing);
        expect(find.byKey(leftCue), findsOneWidget);
      },
    );

    testWidgets('neither cue shows when the matrix fits without overflow', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        dances: [
          dance('d1', 'A', [swing()]),
        ],
        width: 1400,
      );

      expect(find.byKey(rightCue), findsNothing);
      expect(find.byKey(leftCue), findsNothing);
    });
  });

  group('phone-width compact view (< 600dp)', () {
    Future<void> pumpNarrow(
      WidgetTester tester, {
      required List<Dance> dances,
      int omittedFreeTextCount = 0,
      Set<String> altDanceIds = const {},
      Dialect? dialect,
      List<ProgramHalf?>? halves,
      Set<int> hiddenColumns = const {},
    }) async {
      // A 360dp phone: below ProgramMatrixTable.compactBreakpoint (600), so the
      // wide scrolling grid is replaced by the condensed by-move view.
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,

          home: Scaffold(
            body: ProgramMatrixTable(
              matrix: buildProgramMatrix(dances, halves: halves),
              taxonomy: contraTaxonomy,
              dialect: dialect ?? Dialect.canonical,
              omittedFreeTextCount: omittedFreeTextCount,
              altDanceIds: altDanceIds,
              hiddenColumns: hiddenColumns,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('surfaces moves that repeat across the set', (tester) async {
      await pumpNarrow(
        tester,
        dances: [
          dance('d1', 'A', [swing(), move('balance')]),
          dance('d2', 'B', [swing(), move('balance')]),
        ],
      );

      // The core insight is presented directly, grouped by move — no
      // horizontal scrolling needed to see what repeats.
      expect(find.text('Repeated moves'), findsOneWidget);

      // Each repeated move states how many of the set's dances use it...
      expect(
        find.bySemanticsLabel('Move: partner swing, used in 2 of 2 dances'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Move: balance, used in 2 of 2 dances'),
        findsOneWidget,
      );

      // ...and the per-dance table semantics are preserved on each chip. A
      // opens with the swing (its debut + first figure); B opens with it too
      // but the swing already debuted in A, so B carries the dance-first flag.
      // Both dances open with the partner swing in the same phrase (A1), so
      // that move is also a same-figure-same-phrase collision (#582).
      expect(
        find.bySemanticsLabel(
          "A, formation: Duple improper, partner swing: present, repeats in "
          "the same phrase as an adjacent dance, introduced here, dance's "
          "first figure",
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          "B, formation: Duple improper, partner swing: present, repeats in "
          "the same phrase as an adjacent dance, dance's first figure",
        ),
        findsOneWidget,
      );
      // balance debuts in A (mid-dance, phrase A2) and is a plain repeat in B —
      // also in A2 in both dances, so it collides too.
      expect(
        find.bySemanticsLabel(
          'A, formation: Duple improper, balance: present, repeats in the '
          'same phrase as an adjacent dance, introduced here',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'B, formation: Duple improper, balance: present, repeats in the '
          'same phrase as an adjacent dance',
        ),
        findsOneWidget,
      );
    });

    testWidgets('marks the debut of a repeated move with a star', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        dances: [
          // A opens on the swing (its debut + first figure); B opens on
          // balance, so the shared partner swing is B's second figure — present
          // but neither a debut nor B's first figure.
          dance('d1', 'A', [swing()]),
          dance('d2', 'B', [move('balance'), swing()]),
        ],
      );

      expect(find.text('Repeated moves'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          "A, formation: Duple improper, partner swing: present, introduced "
          "here, dance's first figure",
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'B, formation: Duple improper, partner swing: present',
        ),
        findsOneWidget,
      );
      // The program debut is a distinct shape (star), not colour alone.
      expect(find.byIcon(Icons.star), findsWidgets);
    });

    testWidgets('notes when no moves repeat across the dances', (tester) async {
      await pumpNarrow(
        tester,
        dances: [
          dance('d1', 'A', [move('balance')]),
          dance('d2', 'B', [move('allemande')]),
        ],
      );

      expect(find.textContaining('No moves repeat'), findsOneWidget);
      expect(find.text('Repeated moves'), findsNothing);
      // Every move is still listed (nothing dropped) under "Used once".
      expect(find.text('Used once'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Move: balance, used in 1 of 2 dances'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Move: allemande, used in 1 of 2 dances'),
        findsOneWidget,
      );
    });

    testWidgets('keeps the container table semantics for assistive tech', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        dances: [
          dance('d1', 'A', [swing()]),
          dance('d2', 'B', [swing()]),
        ],
      );
      // The announced move count reflects what the compact view actually shows
      // (the unused neighbor-swing baseline column is dropped), so the label
      // stays accurate for assistive tech.
      expect(
        find.bySemanticsLabel('Programming matrix: 2 dances by 1 move'),
        findsOneWidget,
      );
    });

    testWidgets('surfaces ALT dances in the chip label and badge', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        dances: [
          dance('d1', 'A', [swing()]),
          dance('d2', 'Alt Dance', [swing()]),
        ],
        altDanceIds: {'d2'},
      );
      // The alternate-slot distinction (only in the wide row header) is carried
      // into the compact chip's semantics and shown with the alt_route icon. A
      // opens the swing (its debut + first figure); Alt Dance opens it too but
      // after the debut, so it carries only the dance-first flag. Both open the
      // partner swing in the same phrase (A1), so it also collides (#582).
      expect(
        find.bySemanticsLabel(
          "Alt Dance (alternate dance), formation: Duple improper, partner "
          "swing: present, repeats in the same phrase as an adjacent dance, "
          "dance's first figure",
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          "A, formation: Duple improper, partner swing: present, repeats in "
          "the same phrase as an adjacent dance, introduced here, dance's "
          "first figure",
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.alt_route), findsWidgets);
    });

    testWidgets('shows the formation badge only for non-default formations', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        dances: [
          dance('d1', 'A', [
            swing(),
          ], formation: const Formation(FormationShape.becketCw)),
          dance('d2', 'B', [swing()]),
        ],
      );
      // Visual badge appears only for the atypical (non-duple-improper)
      // formation, keeping the common case's chip compact...
      expect(find.text('Becket (CW)'), findsOneWidget);
      expect(find.text('Duple improper'), findsNothing);
      // ...but screen readers always hear both dances' formation via the
      // chip's semantics, regardless of the visual shortcut.
      expect(
        find.bySemanticsLabel(
          "A, formation: Becket (CW), partner swing: present, repeats in "
          "the same phrase as an adjacent dance, introduced here, dance's "
          "first figure",
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          "B, formation: Duple improper, partner swing: present, repeats "
          "in the same phrase as an adjacent dance, dance's first figure",
        ),
        findsOneWidget,
      );
    });

    testWidgets('handles dances with no comparable moves', (tester) async {
      // Figure-less dances produce only the unused swing baseline columns, so
      // the compact view has nothing to list — it must say so plainly rather
      // than claim a move list that isn't there.
      await pumpNarrow(
        tester,
        dances: [dance('d1', 'A', const []), dance('d2', 'B', const [])],
      );
      expect(find.textContaining('no moves to compare'), findsOneWidget);
      expect(find.text('Repeated moves'), findsNothing);
      expect(find.text('Used once'), findsNothing);
      expect(
        find.bySemanticsLabel('Programming matrix: 2 dances by 0 moves'),
        findsOneWidget,
      );
    });

    testWidgets('still notes omitted free-text slots', (tester) async {
      await pumpNarrow(
        tester,
        dances: [
          dance('d1', 'A', [swing()]),
          dance('d2', 'B', [swing()]),
        ],
        omittedFreeTextCount: 2,
      );
      expect(find.textContaining('2 free-text slots'), findsOneWidget);
    });

    testWidgets('empty matrix still shows the auto-fill empty state', (
      tester,
    ) async {
      await pumpNarrow(tester, dances: const []);
      expect(find.text('No structured figures yet'), findsOneWidget);
    });
  });

  group('half badge', () {
    testWidgets('wide grid renders 1st/2nd badges with icon + text', (
      tester,
    ) async {
      await pump(
        tester,
        dances: [
          dance('d1', 'A', [move('balance')]),
          dance('d2', 'B', [move('balance')]),
        ],
        halves: const [ProgramHalf.first, ProgramHalf.second],
      );

      // Icon + text (never colour alone), per WCAG 1.4.1.
      expect(find.text('1st'), findsOneWidget);
      expect(find.text('2nd'), findsOneWidget);
      expect(find.byIcon(Icons.looks_one_outlined), findsOneWidget);
      expect(find.byIcon(Icons.looks_two_outlined), findsOneWidget);

      // Screen-reader phrasing folds the half into the row header label.
      expect(find.bySemanticsLabel('Dance: A, first half'), findsOneWidget);
      expect(find.bySemanticsLabel('Dance: B, second half'), findsOneWidget);
    });

    testWidgets('no badge when the program has no halves', (tester) async {
      await pump(
        tester,
        dances: [
          dance('d1', 'A', [move('balance')]),
          dance('d2', 'B', [move('balance')]),
        ],
      );

      expect(find.text('1st'), findsNothing);
      expect(find.text('2nd'), findsNothing);
      expect(find.bySemanticsLabel('Dance: A'), findsOneWidget);
    });

    testWidgets('compact view carries the half into chip semantics', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,

          home: Scaffold(
            body: ProgramMatrixTable(
              matrix: buildProgramMatrix(
                [
                  dance('d1', 'A', [swing(), move('balance')]),
                  dance('d2', 'B', [swing(), move('balance')]),
                ],
                halves: const [ProgramHalf.first, ProgramHalf.second],
              ),
              taxonomy: contraTaxonomy,
              dialect: Dialect.canonical,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both dances open with the partner swing in the same phrase (A1), so it
      // is also a same-figure-same-phrase collision (#582).
      expect(
        find.bySemanticsLabel(
          "A (first half), formation: Duple improper, partner swing: "
          "present, repeats in the same phrase as an adjacent dance, "
          "introduced here, dance's first figure",
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          "B (second half), formation: Duple improper, partner swing: "
          "present, repeats in the same phrase as an adjacent dance, "
          "dance's first figure",
        ),
        findsOneWidget,
      );
    });
  });

  group('same-figure-same-phrase collision glyph (#582)', () {
    // Steer a move into a phrase by padding the beats ahead of it (default
    // 4x16 structure: A1 0-15, A2 16-31, B1 32-47, B2 48-63).
    Figure fig(String id, int beats) =>
        invalidTestFigure(move: id, params: {'beats': beats}, reason: 'callers pass arbitrary move ids, including ones outside the taxonomy, to steer a move into a given phrase');

    testWidgets('flags both cells when a move repeats in the same phrase of an '
        'adjacent dance', (tester) async {
      await pump(
        tester,
        dances: [
          // balance lands in B1 (beat 32) in both dances; the fillers differ so
          // only balance collides.
          dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 16)]),
          dance('d2', 'B', [fig('circle_left', 32), fig('balance', 16)]),
        ],
      );

      expect(find.byIcon(Icons.report), findsWidgets);
      // d1's balance is also its program debut for that move.
      expect(
        find.bySemanticsLabel(
          'A, balance: present, repeats in the same phrase as an adjacent '
          'dance, introduced here',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'B, balance: present, repeats in the same phrase as an adjacent '
          'dance',
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not flag the same move in a different phrase', (
      tester,
    ) async {
      await pump(
        tester,
        dances: [
          // balance in B1 (beat 32).
          dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 16)]),
          // balance in A2 (beat 16) — a different phrase, so no collision.
          dance('d2', 'B', [fig('circle_left', 16), fig('balance', 16)]),
        ],
      );

      // The only release_alert icon is the legend key — no cell collides.
      expect(
        find.bySemanticsLabel(
          'A, balance: present, repeats in the same phrase as an adjacent '
          'dance, introduced here',
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          'B, balance: present, repeats in the same phrase as an adjacent '
          'dance',
        ),
        findsNothing,
      );
      // d1's balance is a mid-dance debut (phrase B1); d2's balance neither
      // opens the dance nor debuts the move — plain "present" in both cases.
      expect(
        find.bySemanticsLabel('A, balance: present, introduced here'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('B, balance: present'), findsOneWidget);
    });

    testWidgets('compact view surfaces the collision on the dance chip', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: ProgramMatrixTable(
              matrix: buildProgramMatrix([
                dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 16)]),
                dance('d2', 'B', [fig('circle_left', 32), fig('balance', 16)]),
              ]),
              taxonomy: contraTaxonomy,
              dialect: Dialect.canonical,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.report), findsWidgets);
      expect(
        find.bySemanticsLabel(
          'A, formation: Duple improper, balance: present, repeats in the '
          'same phrase as an adjacent dance, introduced here',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'B, formation: Duple improper, balance: present, repeats in the '
          'same phrase as an adjacent dance',
        ),
        findsOneWidget,
      );
    });
  });

  group('hide columns (#669)', () {
    testWidgets(
      'tapping a column\'s hide glyph reports its index; hiding that index '
      'removes only that column\'s header and cells, leaving the rest '
      'correctly paired',
      (tester) async {
        int? hiddenIndex;
        final dances = [
          dance('d1', 'A', [swing(), move('balance')]),
          dance('d2', 'B', [move('balance'), swing()]),
        ];
        await pump(
          tester,
          dances: dances,
          onHideColumn: (c) => hiddenIndex = c,
        );

        await tester.tap(find.byTooltip('Hide balance column'));
        await tester.pump();
        expect(hiddenIndex, isNotNull);

        // Re-pump with that index hidden — mirrors how the host screen reacts
        // to `onHideColumn` by adding the reported index to its own state.
        await pump(tester, dances: dances, hiddenColumns: {hiddenIndex!});

        expect(find.text('balance'), findsNothing);
        expect(
          find.bySemanticsLabel('A, balance: present, introduced here'),
          findsNothing,
        );
        // The other columns are unaffected and still correctly paired with
        // their own data — confirms columns are skipped by identity, not by
        // silently reindexing the remaining ones.
        expect(find.text('partner swing'), findsOneWidget);
        expect(find.text('neighbor swing'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            "A, partner swing: present, introduced here, dance's first figure",
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('B, partner swing: present'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the announced dances-by-moves count drops when a column is hidden',
      (tester) async {
        int? hiddenIndex;
        final dances = [
          dance('d1', 'A', [swing()]),
          dance('d2', 'B', [swing()]),
        ];
        await pump(
          tester,
          dances: dances,
          onHideColumn: (c) => hiddenIndex = c,
        );

        // Unlike the compact view, the wide grid counts every column
        // (partner + the always-emitted neighbor baseline), not just present
        // ones. The label's semantics node merges with the pinned Formation
        // header's ("#663) label as a descendant, so match by prefix.
        expect(
          find.bySemanticsLabel(
            RegExp('^Programming matrix: 2 dances by 2 moves'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Hide neighbor swing column'));
        await tester.pump();
        expect(hiddenIndex, isNotNull);

        await pump(tester, dances: dances, hiddenColumns: {hiddenIndex!});

        expect(
          find.bySemanticsLabel(
            RegExp('^Programming matrix: 2 dances by 1 move\\b'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the compact (phone-width) view also respects an externally-supplied '
      'hidden set, though it has no hide UI of its own',
      (tester) async {
        int? hiddenIndex;
        final dances = [
          dance('d1', 'A', [swing(), move('balance')]),
          dance('d2', 'B', [move('balance')]),
        ];
        // Learn balance's stable column index from the wide view first —
        // the compact view has no per-column hide glyph, but shares the same
        // underlying column indices from the same `buildProgramMatrix` call.
        await pump(
          tester,
          dances: dances,
          onHideColumn: (c) => hiddenIndex = c,
        );
        await tester.tap(find.byTooltip('Hide balance column'));
        await tester.pump();
        expect(hiddenIndex, isNotNull);

        await tester.binding.setSurfaceSize(const Size(360, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              body: ProgramMatrixTable(
                matrix: buildProgramMatrix(dances),
                taxonomy: contraTaxonomy,
                dialect: Dialect.canonical,
                hiddenColumns: {hiddenIndex!},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Balance repeats across both dances, so absent the hide it would
        // show as a "repeated move" card — hidden, it shows nowhere.
        expect(find.text('balance'), findsNothing);
        expect(find.text('partner swing'), findsOneWidget);
      },
    );

    testWidgets(
      'the hide glyph is reachable without hovering: it is visible at rest '
      '(not hover-gated) and hit-testable without any pointer hover',
      (tester) async {
        await pump(
          tester,
          dances: [
            dance('d1', 'A', [swing()]),
          ],
          onHideColumn: (_) {},
        );

        final tooltipFinder = find.byTooltip('Hide partner swing column');
        expect(tooltipFinder, findsOneWidget);

        // Resting opacity is non-zero (touch users never trigger hover), so
        // the glyph isn't invisible/undiscoverable without a mouse.
        final restingOpacity = tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: tooltipFinder,
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity;
        expect(restingOpacity, greaterThan(0));
        expect(restingOpacity, lessThan(1));

        // No hover was simulated above, yet the button is still tappable —
        // proving the affordance isn't hover-gated for interaction.
        await tester.tap(tooltipFinder);
        await tester.pump();
      },
    );

    testWidgets(
      'hovering the column header reveals the glyph at full opacity',
      (tester) async {
        await pump(
          tester,
          dances: [
            dance('d1', 'A', [swing()]),
          ],
          onHideColumn: (_) {},
        );

        final tooltipFinder = find.byTooltip('Hide partner swing column');
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.text('partner swing')));
        await tester.pumpAndSettle();

        final hoveredOpacity = tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: tooltipFinder,
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity;
        expect(hoveredOpacity, 1);
      },
    );
  });
}
