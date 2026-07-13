import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host that owns a mutable draft list so the editor's in-place edits and
/// add/delete callbacks drive real rebuilds, mirroring the dance editor screen.
class _Host extends StatefulWidget {
  const _Host({required this.drafts, this.phrase = PhraseStructure.standard});

  final List<FigureDraft> drafts;
  final PhraseStructure phrase;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FigureListEditor(
            drafts: widget.drafts,
            taxonomy: contraTaxonomy,
            phraseStructure: widget.phrase,
            onChanged: () => setState(() {}),
            onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
            onDelete: (d) => setState(() => widget.drafts.remove(d)),
            onReorder: (oldIndex, newIndex) => setState(() {
              final draft = widget.drafts.removeAt(oldIndex);
              widget.drafts.insert(newIndex, draft);
            }),
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  List<FigureDraft> drafts, {
  PhraseStructure phrase = PhraseStructure.standard,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_Host(drafts: drafts, phrase: phrase));
  await tester.pumpAndSettle();
}

Future<void> _selectMove(
  WidgetTester tester,
  int index,
  String typed,
  String optionId,
) async {
  await tester.enterText(
    find.byKey(ValueKey('figure-$index-move-input')),
    typed,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('figure-$index-move-option-$optionId')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty list shows a placeholder and an add button', (
    tester,
  ) async {
    await _pump(tester, []);
    expect(find.text('No figures yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-add')), findsOneWidget);
  });

  testWidgets('add creates an empty figure row', (tester) async {
    final drafts = <FigureDraft>[];
    await _pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsOneWidget);
    expect(drafts, hasLength(1));
  });

  testWidgets('selecting a move seeds the taxonomy default params', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    // Default params surface as concrete editors.
    expect(find.byKey(const ValueKey('figure-0-who')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-beats')), findsOneWidget);
    expect(drafts.single.move, 'swing');
    expect(drafts.single.params['who'], 'partners');
    expect(drafts.single.params['beats'], 8);
  });

  testWidgets('selecting an alias keeps the alias identity and pins', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'see', 'see_saw');

    expect(drafts.single.move, 'see_saw');
    // Alias pins the do-si-do shoulder to left.
    expect(drafts.single.params['shoulder'], 'left');
  });

  testWidgets('unmatched text creates a custom figure', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'scoop them up',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(drafts.single.move, customMove);
    expect(drafts.single.params['text'], 'scoop them up');
    expect(find.byKey(const ValueKey('figure-0-text')), findsOneWidget);
  });

  testWidgets('whitespace-only submission does not create a custom figure', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      '   ',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(drafts.single.move, isNull);
  });

  testWidgets('custom figure text is trimmed', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      '  scoop them up  ',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(drafts.single.move, customMove);
    expect(drafts.single.params['text'], 'scoop them up');
  });

  testWidgets('running beat total warns on underflow', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    // One swing = 8 beats against the standard 64.
    expect(find.byKey(const ValueKey('figure-beats-total')), findsOneWidget);
    expect(find.text('Total: 8 / 64 beats'), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-beats-warning')), findsOneWidget);
    expect(find.text('Under by 56 beats'), findsOneWidget);
  });

  testWidgets('editing beats updates the running total', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();
    expect(find.text('Total: 16 / 64 beats'), findsOneWidget);
    expect(drafts.single.beats, 16);
  });

  testWidgets('derived section labels advance with beats', (tester) async {
    // Two 16-beat figures land in A1 then A2 under the standard structure.
    final drafts = <FigureDraft>[FigureDraft(), FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();
    await _selectMove(tester, 1, 'sw', 'swing');
    await tester.enterText(find.byKey(const ValueKey('figure-1-beats')), '16');
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('figure-0-label'))).data,
      'A1',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('figure-1-label'))).data,
      'A2',
    );
  });

  testWidgets('progression toggle flips the draft flag', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    expect(drafts.single.progression, isFalse);
    await tester.tap(find.byKey(const ValueKey('figure-0-progression')));
    await tester.pumpAndSettle();
    expect(drafts.single.progression, isTrue);
  });

  testWidgets('note field records a note on the draft', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'big and smooth',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.note, 'big and smooth');
  });

  testWidgets('delete removes a figure row', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);
    expect(find.byKey(const ValueKey('figure-1-move-input')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
    await tester.pumpAndSettle();

    expect(drafts, hasLength(1));
    expect(drafts.single.move, 'balance');
  });

  testWidgets('a seeded draft renders its editors and values', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.0, 'beats': 8},
      ),
    ];
    await _pump(tester, drafts);

    expect(find.byKey(const ValueKey('figure-0-hand')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-turn-value')), findsOneWidget);
    // toFigure preserves the seeded values.
    final figure = drafts.single.toFigure()!;
    expect(figure.move, 'allemande');
    expect(figure.params['hand'], 'right');
  });

  // -------------------------------------------------------------------------
  // Lingo-line controller unit tests (run inside a minimal widget context)
  // -------------------------------------------------------------------------

  /// Builds a [LingoTextEditingController], calls [buildTextSpan], and returns
  /// the result synchronously via a callback executed during the widget's build.
  Future<TextSpan> buildLingoSpan(
    WidgetTester tester, {
    required String text,
    required Dialect dialect,
    Taxonomy? taxonomy,
  }) async {
    TextSpan? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final ctrl = LingoTextEditingController(
              text: text,
              dialect: dialect,
              taxonomy: taxonomy,
            );
            captured = ctrl.buildTextSpan(
              context: context,
              style: null,
              withComposing: false,
            );
            return Container();
          },
        ),
      ),
    );
    return captured!;
  }

  /// Flattens a [TextSpan] tree into a list of (text, decoration?, decorationStyle?) triples.
  List<(String, TextDecoration?, TextDecorationStyle?)> flattenSpan(
    TextSpan span,
  ) {
    final result = <(String, TextDecoration?, TextDecorationStyle?)>[];
    void visit(InlineSpan s) {
      if (s is TextSpan) {
        if (s.children != null) {
          for (final child in s.children!) {
            visit(child);
          }
        } else if (s.text != null && s.text!.isNotEmpty) {
          result.add((s.text!, s.style?.decoration, s.style?.decorationStyle));
        }
      }
    }

    if (span.children != null) {
      for (final child in span.children!) {
        visit(child);
      }
    } else {
      result.add((
        span.text ?? '',
        span.style?.decoration,
        span.style?.decorationStyle,
      ));
    }
    return result;
  }

  testWidgets('lingo: discouraged term gets lineThrough decoration', (
    tester,
  ) async {
    final span = await buildLingoSpan(
      tester,
      text: 'gents cross',
      dialect: Dialect.larksRobins,
    );
    final parts = flattenSpan(span);
    final discPart = parts.firstWhere(
      (p) => p.$1.toLowerCase() == 'gents',
      orElse: () => ('', null, null),
    );
    expect(discPart.$2, TextDecoration.lineThrough);
  });

  testWidgets('lingo: role synonym (larks) gets underline decoration', (
    tester,
  ) async {
    final span = await buildLingoSpan(
      tester,
      text: 'larks lead',
      dialect: Dialect.canonical,
    );
    final parts = flattenSpan(span);
    final rolePart = parts.firstWhere(
      (p) => p.$1.toLowerCase() == 'larks',
      orElse: () => ('', null, null),
    );
    expect(rolePart.$2, TextDecoration.underline);
  });

  testWidgets('lingo: canonical role token (role1) gets underline', (
    tester,
  ) async {
    final span = await buildLingoSpan(
      tester,
      text: 'role1 and role2s',
      dialect: Dialect.canonical,
    );
    final parts = flattenSpan(span);
    final r1 = parts.firstWhere(
      (p) => p.$1 == 'role1',
      orElse: () => ('', null, null),
    );
    final r2s = parts.firstWhere(
      (p) => p.$1 == 'role2s',
      orElse: () => ('', null, null),
    );
    expect(r1.$2, TextDecoration.underline);
    expect(r2s.$2, TextDecoration.underline);
  });

  testWidgets('lingo: plain text has no decoration', (tester) async {
    final span = await buildLingoSpan(
      tester,
      text: 'swing your neighbor',
      dialect: Dialect.canonical,
    );
    final parts = flattenSpan(span);
    for (final part in parts) {
      expect(part.$2, isNot(TextDecoration.lineThrough));
      expect(part.$2, isNot(TextDecoration.underline));
    }
  });

  testWidgets('lingo: offsets stay correct after mid-string edit', (
    tester,
  ) async {
    // "hello gents world" — gents at offset 6.
    final spanBefore = await buildLingoSpan(
      tester,
      text: 'hello gents world',
      dialect: Dialect.larksRobins,
    );
    final partsBefore = flattenSpan(spanBefore);
    // Verify gents is in the output with strikethrough.
    expect(
      partsBefore.any(
        (p) =>
            p.$1.toLowerCase() == 'gents' && p.$2 == TextDecoration.lineThrough,
      ),
      isTrue,
    );

    // After inserting 2 chars before "gents": "hello xygents world"
    final spanAfter = await buildLingoSpan(
      tester,
      text: 'hello xygents world',
      dialect: Dialect.larksRobins,
    );
    final partsAfter = flattenSpan(spanAfter);
    // "xygents" is not a word-boundary match for "gents" — no strikethrough.
    expect(
      partsAfter.any(
        (p) =>
            p.$1.toLowerCase().contains('gents') &&
            p.$2 == TextDecoration.lineThrough,
      ),
      isFalse,
    );
  });

  testWidgets('lingo: updateDialect triggers redraw', (tester) async {
    // Start with canonical (no discouraged terms).
    final ctrl = LingoTextEditingController(
      text: 'gents cross',
      dialect: Dialect.canonical,
    );
    TextSpan? firstSpan;
    TextSpan? secondSpan;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            firstSpan ??= ctrl.buildTextSpan(
              context: context,
              style: null,
              withComposing: false,
            );
            return Container();
          },
        ),
      ),
    );

    // Switch to larksRobins (which has "gents" as discouraged).
    ctrl.updateDialect(Dialect.larksRobins);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            secondSpan = ctrl.buildTextSpan(
              context: context,
              style: null,
              withComposing: false,
            );
            return Container();
          },
        ),
      ),
    );

    // After dialect change, "gents" should now be struck through.
    final parts = flattenSpan(secondSpan!);
    expect(
      parts.any(
        (p) =>
            p.$1.toLowerCase() == 'gents' && p.$2 == TextDecoration.lineThrough,
      ),
      isTrue,
    );
  });

  testWidgets(
    'lingo: term that is both discouraged and role synonym always gets '
    'strikethrough (not underline)',
    (tester) async {
      // "gents" is both a legacy role synonym AND in defaultDiscouragedTerms.
      // Strikethrough must win because discouraged has higher priority.
      final span = await buildLingoSpan(
        tester,
        text: 'gents swing',
        dialect: Dialect.larksRobins,
      );
      final parts = flattenSpan(span);
      final gentsPart = parts.firstWhere(
        (p) => p.$1.toLowerCase() == 'gents',
        orElse: () => ('', null, null),
      );
      expect(
        gentsPart.$2,
        TextDecoration.lineThrough,
        reason: 'discouraged takes priority over role at the same position',
      );
    },
  );

  testWidgets(
    'lingo: cut banner shows single-quoted name for custom figure (no doubled '
    'quotes)',
    (tester) async {
      final drafts = <FigureDraft>[
        FigureDraft(
          move: customMove,
          params: {'text': 'my custom step', 'beats': 8},
        ),
        FigureDraft(move: 'balance', params: {'beats': 4}),
      ];
      await _pump(tester, drafts);

      await tester.tap(find.byKey(const ValueKey('figure-0-cut')));
      await tester.pumpAndSettle();

      // Banner text should be '"my custom step" is cut …' — one pair of quotes.
      final bannerFinder = find.byKey(const ValueKey('cut-banner'));
      expect(bannerFinder, findsOneWidget);
      final bannerText = tester.widget<Text>(bannerFinder).data ?? '';
      // Must contain the name in quotes exactly once — not doubled.
      expect(bannerText, contains('"my custom step"'));
      expect(bannerText, isNot(contains('""')));
    },
  );

  testWidgets('lingo: drag handles are absent while cut mode is active', (
    tester,
  ) async {
    // When cut is active the list switches to a plain Column without a
    // ReorderableListView, so no ReorderableDragStartListener is present.
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    // Confirm drag-start listeners exist in normal mode.
    expect(find.byType(ReorderableDragStartListener), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('figure-0-cut')));
    await tester.pumpAndSettle();

    // In cut mode — no drag handles (plain Column is used instead).
    expect(find.byType(ReorderableDragStartListener), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Widget tests: lingo hint in the custom figure text field
  // -------------------------------------------------------------------------

  testWidgets(
    'custom figure text field shows lingo hint for discouraged term',
    (tester) async {
      final drafts = <FigureDraft>[
        FigureDraft(
          move: customMove,
          params: {'text': 'gents cross', 'beats': 8},
        ),
      ];
      await _pump(tester, drafts);

      // The accessible lingo hint should be visible.
      expect(
        find.byKey(const ValueKey('figure-0-text-lingo-hint')),
        findsOneWidget,
      );
      expect(find.textContaining('gents'), findsWidgets);
    },
  );

  testWidgets(
    'custom figure text field shows no hint without discouraged terms',
    (tester) async {
      final drafts = <FigureDraft>[
        FigureDraft(
          move: customMove,
          params: {'text': 'shadow step', 'beats': 8},
        ),
      ];
      await _pump(tester, drafts);

      expect(
        find.byKey(const ValueKey('figure-0-text-lingo-hint')),
        findsNothing,
      );
    },
  );

  testWidgets('custom figure text field lingo hint updates live on edit', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    // Create a custom figure by typing text with a discouraged term.
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'swing with ladies',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Now it's a custom figure; the text field exists.
    expect(find.byKey(const ValueKey('figure-0-text')), findsOneWidget);

    // "ladies" is in defaultDiscouragedTerms — hint should appear.
    expect(
      find.byKey(const ValueKey('figure-0-text-lingo-hint')),
      findsOneWidget,
    );

    // Edit to remove the discouraged term.
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-text')),
      'swing with larks',
    );
    await tester.pumpAndSettle();
    // "larks" is a role term but not discouraged — hint should be gone.
    expect(
      find.byKey(const ValueKey('figure-0-text-lingo-hint')),
      findsNothing,
    );
  });

  // -------------------------------------------------------------------------
  // Reordering tests
  // -------------------------------------------------------------------------

  testWidgets('move-up button is disabled for the first figure', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    final upBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey('figure-0-move-up')),
    );
    expect(upBtn.onPressed, isNull);

    final upBtn1 = tester.widget<IconButton>(
      find.byKey(const ValueKey('figure-1-move-up')),
    );
    expect(upBtn1.onPressed, isNotNull);
  });

  testWidgets('move-down button is disabled for the last figure', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    final downBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey('figure-1-move-down')),
    );
    expect(downBtn.onPressed, isNull);

    final downBtn0 = tester.widget<IconButton>(
      find.byKey(const ValueKey('figure-0-move-down')),
    );
    expect(downBtn0.onPressed, isNotNull);
  });

  testWidgets('move-up button reorders the draft list', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-1-move-up')));
    await tester.pumpAndSettle();

    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'swing');
  });

  testWidgets('move-down button reorders the draft list', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-move-down')));
    await tester.pumpAndSettle();

    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'swing');
  });

  testWidgets('section labels recompute after move-down', (tester) async {
    // Two 16-beat figures: initially A1 then A2.
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 16}),
      FigureDraft(move: 'balance', params: {'beats': 16}),
    ];
    await _pump(tester, drafts);

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('figure-0-label'))).data,
      'A1',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('figure-1-label'))).data,
      'A2',
    );

    await tester.tap(find.byKey(const ValueKey('figure-0-move-down')));
    await tester.pumpAndSettle();

    // After swap the order is the same (16+16 beats), labels stay A1/A2, but
    // the figures should be in the new order.
    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'swing');
  });

  testWidgets('cut shows banner; cancel clears it', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    expect(find.byKey(const ValueKey('cut-banner')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('figure-0-cut')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cut-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cut-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cut-banner')), findsNothing);
  });

  testWidgets('cut button is disabled on the cut figure itself', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-cut')));
    await tester.pumpAndSettle();

    final cutBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey('figure-0-cut')),
    );
    expect(cutBtn.onPressed, isNull);
  });

  testWidgets('paste-end moves cut figure to end of list', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
      FigureDraft(move: 'petronella', params: {'beats': 8}),
    ];
    await _pump(tester, drafts);

    // Cut the first figure (swing).
    await tester.tap(find.byKey(const ValueKey('figure-0-cut')));
    await tester.pumpAndSettle();

    // Paste at end.
    await tester.tap(find.byKey(const ValueKey('paste-end')));
    await tester.pumpAndSettle();

    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'petronella');
    expect(drafts[2].move, 'swing');
  });

  testWidgets('cut/paste: cut last figure, paste before first', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
      FigureDraft(move: 'petronella', params: {'beats': 8}),
    ];
    await _pump(tester, drafts);

    // Cut the last figure (petronella).
    await tester.tap(find.byKey(const ValueKey('figure-2-cut')));
    await tester.pumpAndSettle();

    // Paste before first figure.
    await tester.tap(find.byKey(const ValueKey('paste-top')));
    await tester.pumpAndSettle();

    expect(drafts[0].move, 'petronella');
    expect(drafts[1].move, 'swing');
    expect(drafts[2].move, 'balance');
  });

  testWidgets('cut/paste beat count and warnings recompute correctly', (
    tester,
  ) async {
    // swing=16, balance=4 → total 20.  After swap: balance=4, swing=16 → same total.
    // Use 3 figures where reorder changes the section layout.
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 16}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-cut')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paste-end')));
    await tester.pumpAndSettle();

    // Total beats unchanged — still 20.
    expect(find.text('Total: 20 / 64 beats'), findsOneWidget);
    // Order is now balance, swing.
    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'swing');
  });

  testWidgets('toFigure order matches draft order after reorder', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8, 'who': 'partners'}),
      FigureDraft(move: 'balance', params: {'beats': 4, 'who': 'partners'}),
      FigureDraft(move: 'petronella', params: {'beats': 8}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-2-move-up')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-1-move-up')));
    await tester.pumpAndSettle();

    // petronella should now be first.
    expect(drafts[0].move, 'petronella');
    expect(drafts[1].move, 'swing');
    expect(drafts[2].move, 'balance');

    final figures = [for (final d in drafts) ?d.toFigure()];
    expect(figures[0].move, 'petronella');
    expect(figures[1].move, 'swing');
    expect(figures[2].move, 'balance');
  });

  // -------------------------------------------------------------------------
  // Lingo: move-keyword dotted-underline (defer-lingo-movekw)
  // -------------------------------------------------------------------------

  testWidgets('lingo: recognized move keyword (swing) gets dotted-underline', (
    tester,
  ) async {
    final span = await buildLingoSpan(
      tester,
      text: 'swing your neighbor',
      dialect: Dialect.canonical,
      taxonomy: contraTaxonomy,
    );
    final parts = flattenSpan(span);
    final swingPart = parts.firstWhere(
      (p) => p.$1.toLowerCase() == 'swing',
      orElse: () => ('', null, null),
    );
    expect(swingPart.$2, TextDecoration.underline);
    expect(swingPart.$3, TextDecorationStyle.dotted);
  });

  testWidgets(
    'lingo: move keyword is distinct from role term (different style)',
    (tester) async {
      final span = await buildLingoSpan(
        tester,
        text: 'larks swing',
        dialect: Dialect.canonical,
        taxonomy: contraTaxonomy,
      );
      final parts = flattenSpan(span);
      // Role term "larks": solid underline (no decorationStyle override).
      final larksPart = parts.firstWhere(
        (p) => p.$1.toLowerCase() == 'larks',
        orElse: () => ('', null, null),
      );
      expect(larksPart.$2, TextDecoration.underline);
      expect(
        larksPart.$3,
        isNot(TextDecorationStyle.dotted),
        reason: 'role term uses solid underline (no dotted style)',
      );

      // Move keyword "swing": dotted underline.
      final swingPart = parts.firstWhere(
        (p) => p.$1.toLowerCase() == 'swing',
        orElse: () => ('', null, null),
      );
      expect(swingPart.$2, TextDecoration.underline);
      expect(swingPart.$3, TextDecorationStyle.dotted);
    },
  );

  testWidgets('lingo: discouraged term wins over move keyword for same token', (
    tester,
  ) async {
    // "gypsy" is a search keyword for shoulder_round AND is in the
    // discouraged-terms list for larksRobins dialect. Strikethrough must win.
    final span = await buildLingoSpan(
      tester,
      text: 'gypsy neighbors',
      dialect: Dialect.larksRobins,
      taxonomy: contraTaxonomy,
    );
    final parts = flattenSpan(span);
    final gypsyPart = parts.firstWhere(
      (p) => p.$1.toLowerCase() == 'gypsy',
      orElse: () => ('', null, null),
    );
    expect(
      gypsyPart.$2,
      TextDecoration.lineThrough,
      reason: 'discouraged-strike has higher priority than move-keyword',
    );
  });

  testWidgets('lingo: move keyword updates live on edit', (tester) async {
    // No taxonomy → no dotted underline.
    final spanBefore = await buildLingoSpan(
      tester,
      text: 'step step',
      dialect: Dialect.canonical,
      taxonomy: contraTaxonomy,
    );
    final beforeParts = flattenSpan(spanBefore);
    expect(beforeParts.any((p) => p.$3 == TextDecorationStyle.dotted), isFalse);

    // Now with a recognized move keyword.
    final spanAfter = await buildLingoSpan(
      tester,
      text: 'petronella here',
      dialect: Dialect.canonical,
      taxonomy: contraTaxonomy,
    );
    final afterParts = flattenSpan(spanAfter);
    expect(
      afterParts.any(
        (p) =>
            p.$1.toLowerCase() == 'petronella' &&
            p.$2 == TextDecoration.underline &&
            p.$3 == TextDecorationStyle.dotted,
      ),
      isTrue,
    );
  });

  testWidgets(
    'lingo: move keyword offset stays correct after mid-string position',
    (tester) async {
      // "do a petronella" — "petronella" starts at offset 5.
      final span = await buildLingoSpan(
        tester,
        text: 'do a petronella',
        dialect: Dialect.canonical,
        taxonomy: contraTaxonomy,
      );
      final parts = flattenSpan(span);
      // Preceding text "do a " should not have a dotted underline.
      final preceding = parts.firstWhere(
        (p) => p.$1 == 'do a ',
        orElse: () => ('', null, null),
      );
      expect(preceding.$3, isNot(TextDecorationStyle.dotted));

      // "petronella" itself should.
      final pet = parts.firstWhere(
        (p) => p.$1.toLowerCase() == 'petronella',
        orElse: () => ('', null, null),
      );
      expect(pet.$2, TextDecoration.underline);
      expect(pet.$3, TextDecorationStyle.dotted);
    },
  );

  testWidgets('lingo: no move-keyword decoration when taxonomy is null', (
    tester,
  ) async {
    final span = await buildLingoSpan(
      tester,
      text: 'swing your neighbor',
      dialect: Dialect.canonical,
      // taxonomy omitted — no move-keyword highlighting.
    );
    final parts = flattenSpan(span);
    expect(parts.any((p) => p.$3 == TextDecorationStyle.dotted), isFalse);
  });

  testWidgets('lingo: no false positive for substring of a move keyword', (
    tester,
  ) async {
    // "swinging" is not a word-boundary match for "swing".
    final span = await buildLingoSpan(
      tester,
      text: 'they were swinging',
      dialect: Dialect.canonical,
      taxonomy: contraTaxonomy,
    );
    final parts = flattenSpan(span);
    expect(parts.any((p) => p.$3 == TextDecorationStyle.dotted), isFalse);
  });

  testWidgets(
    'lingo: custom figure text field shows dotted-underline for move keyword',
    (tester) async {
      final drafts = <FigureDraft>[
        FigureDraft(
          move: customMove,
          params: {'text': 'petronella and swing', 'beats': 8},
        ),
      ];
      await _pump(tester, drafts);

      // The field should be visible.
      expect(find.byKey(const ValueKey('figure-0-text')), findsOneWidget);
      // The helper text should mention dotted underline for moves.
      expect(find.textContaining('dotted'), findsOneWidget);
    },
  );
}
