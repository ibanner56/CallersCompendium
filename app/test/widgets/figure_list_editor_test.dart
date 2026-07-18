import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_app/src/widgets/lingo_text_editing_controller.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host that owns a mutable draft list so the editor's in-place edits and
/// add/delete callbacks drive real rebuilds, mirroring the dance editor screen.
class _Host extends StatefulWidget {
  const _Host({
    required this.drafts,
    this.phrase = PhraseStructure.standard,
    this.wireDuplicate = true,
    this.moveParamDefaults,
  });

  final List<FigureDraft> drafts;
  final PhraseStructure phrase;
  final bool wireDuplicate;
  final Map<String, Map<String, Object?>>? moveParamDefaults;

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
            moveParamDefaults: widget.moveParamDefaults,
            onChanged: () => setState(() {}),
            onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
            onDelete: (d) => setState(() => widget.drafts.remove(d)),
            onDuplicate: widget.wireDuplicate
                ? (d) => setState(() {
                    final i = widget.drafts.indexOf(d);
                    if (i == -1) return;
                    widget.drafts.insert(
                      i + 1,
                      FigureDraft(
                        move: d.move,
                        params: Map<String, Object?>.of(d.params),
                        note: d.note,
                        progression: d.progression,
                        schemaVersion: d.schemaVersion,
                      ),
                    );
                  })
                : null,
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
  bool wireDuplicate = true,
  Map<String, Map<String, Object?>>? moveParamDefaults,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _Host(
      drafts: drafts,
      phrase: phrase,
      wireDuplicate: wireDuplicate,
      moveParamDefaults: moveParamDefaults,
    ),
  );
  await tester.pumpAndSettle();
}

/// Expands the accordion editor for the figure at [index] by tapping its
/// collapsed summary row. No-op if the editor is already open.
Future<void> _openFigure(WidgetTester tester, int index) async {
  if (find.byKey(ValueKey('figure-$index-move-input')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
  await tester.pumpAndSettle();
}

/// Opens the ⋮ overflow menu for the figure at [index].
Future<void> _openMenu(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('figure-$index-menu')));
  await tester.pumpAndSettle();
}

/// Dismisses the MoveAutocomplete options overlay (shown while its field is
/// focused) so widgets beneath the field become hittable in a test.
Future<void> _dismissAutocomplete(WidgetTester tester) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// Opens the ⋮ menu for [index] and taps the item with the given [suffix]
/// (e.g. 'move-up', 'move-down', 'cut', 'delete', 'duplicate',
/// 'toggle-progression').
Future<void> _tapMenuItem(WidgetTester tester, int index, String suffix) async {
  await _openMenu(tester, index);
  await tester.tap(find.byKey(ValueKey('figure-$index-$suffix')));
  await tester.pumpAndSettle();
}

Future<void> _selectMove(
  WidgetTester tester,
  int index,
  String typed,
  String optionId,
) async {
  // The Move field only mounts when the figure's editor is expanded.
  await _openFigure(tester, index);
  await tester.enterText(
    find.byKey(ValueKey('figure-$index-move-input')),
    typed,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('figure-$index-move-option-$optionId')));
  await tester.pumpAndSettle();
}

/// Opens the dropdown param editor keyed [fieldKey] (e.g. `figure-0-prefix`)
/// and taps the menu item whose (humanized) label matches [optionLabel].
Future<void> _selectDropdownOption(
  WidgetTester tester,
  String fieldKey,
  String optionLabel,
) async {
  // The MoveAutocomplete options overlay can occlude taps; drop focus first.
  await _dismissAutocomplete(tester);
  await tester.tap(find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
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

  testWidgets('changing the move resets beats to the new default', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await _selectMove(tester, 0, 'sw', 'swing');
    expect(drafts.single.beats, 8);
    expect(drafts.single.beatsTouched, isFalse);

    // A genuine move change adopts the new move's canonical default.
    await _selectMove(tester, 0, 'ba', 'balance');
    expect(drafts.single.move, 'balance');
    expect(drafts.single.beats, 4);
    expect(drafts.single.beatsTouched, isFalse);
  });

  testWidgets('a manually-set beats value survives a non-move param change', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');
    expect(drafts.single.beats, 8);
    expect(drafts.single.beatsTouched, isFalse);

    // Editing the beats field directly takes ownership of the value.
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();
    expect(drafts.single.beats, 16);
    expect(drafts.single.beatsTouched, isTrue);

    // Changing a non-beats param must not disturb the manual override.
    await _selectDropdownOption(tester, 'figure-0-prefix', 'meltdown');
    expect(drafts.single.params['prefix'], 'meltdown');
    expect(drafts.single.beats, 16);
  });

  testWidgets('a loaded figure preserves its beats through a non-beats edit', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft.fromFigure(
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 12}),
      ),
    ];
    // A loaded dance's authored beats are treated as user-owned.
    expect(drafts.single.beatsTouched, isTrue);

    await _pump(tester, drafts);
    await _openFigure(tester, 0);

    await _selectDropdownOption(tester, 'figure-0-prefix', 'meltdown');
    expect(drafts.single.params['prefix'], 'meltdown');
    expect(drafts.single.beats, 12);
  });

  testWidgets('a loaded figure without beats adopts the canonical default', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft.fromFigure(
        Figure(move: 'swing', params: const {'who': 'partners'}),
      ),
    ];
    // No explicit beats were loaded, so the value is not treated as user-owned.
    expect(drafts.single.beatsTouched, isFalse);

    await _pump(tester, drafts);
    await _openFigure(tester, 0);

    // A non-beats edit resyncs beats to the move's canonical value. Selecting
    // the "meltdown" prefix drives the swing to its ContraDB 16-beat duration
    // (prefixed swings are 16), rather than leaving beats stuck at 0.
    await _selectDropdownOption(tester, 'figure-0-prefix', 'meltdown');
    expect(drafts.single.beats, 16);
  });

  test('taxonomy beats defaults match canonical values', () {
    int beatsFor(String move) =>
        contraTaxonomy.effectiveParams(Figure(move: move))['beats'] as int;
    expect(beatsFor('swing'), 8);
    expect(beatsFor('balance'), 4);
  });

  group('per-move insert defaults (DD.3)', () {
    testWidgets('overlay overrides the taxonomy default on select', (
      tester,
    ) async {
      final drafts = <FigureDraft>[FigureDraft()];
      await _pump(
        tester,
        drafts,
        moveParamDefaults: {
          'circle': {'turn': 'right'},
        },
      );
      await _selectMove(tester, 0, 'circle', 'circle');

      expect(drafts.single.move, 'circle');
      // Overridden param takes the configured value...
      expect(drafts.single.params['turn'], 'right');
      // ...while non-overridden params keep their taxonomy defaults.
      expect(drafts.single.params['places'], 4);
      expect(drafts.single.params['beats'], 8);
    });

    testWidgets('no override for the move uses pure taxonomy defaults', (
      tester,
    ) async {
      final drafts = <FigureDraft>[FigureDraft()];
      await _pump(
        tester,
        drafts,
        moveParamDefaults: {
          'star': {'places': 2},
        },
      );
      await _selectMove(tester, 0, 'circle', 'circle');

      expect(drafts.single.params['turn'], 'left');
      expect(drafts.single.params['places'], 4);
    });

    testWidgets('stale override key not in the move schema is ignored', (
      tester,
    ) async {
      final drafts = <FigureDraft>[FigureDraft()];
      await _pump(
        tester,
        drafts,
        moveParamDefaults: {
          'circle': {'turn': 'right', 'not_a_param': 'x'},
        },
      );
      await _selectMove(tester, 0, 'circle', 'circle');

      expect(drafts.single.params['turn'], 'right');
      expect(drafts.single.params.containsKey('not_a_param'), isFalse);
    });

    testWidgets('null moveParamDefaults leaves behavior unchanged', (
      tester,
    ) async {
      final drafts = <FigureDraft>[FigureDraft()];
      await _pump(tester, drafts);
      await _selectMove(tester, 0, 'circle', 'circle');

      expect(drafts.single.params['turn'], 'left');
      expect(drafts.single.params['places'], 4);
    });
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
    await _openFigure(tester, 0);

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
    await _openFigure(tester, 0);

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
    await _openFigure(tester, 0);

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

    // The note field is on-demand — reveal it via the "+ Add note" button.
    await tester.tap(find.byKey(const ValueKey('figure-0-add-note')));
    await tester.pumpAndSettle();

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
    // Two collapsed summary rows at rest.
    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-summary')), findsOneWidget);

    await _tapMenuItem(tester, 0, 'delete');

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
    await _openFigure(tester, 0);

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

  testWidgets('lingo: role underline uses the theme dialectAccent color', (
    tester,
  ) async {
    const accent = Color(0xFF12AB34);
    TextSpan? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppThemeExtension.fromColorScheme(
              const ColorScheme.light(),
            ).copyWith(dialectAccent: accent),
          ],
        ),
        home: Builder(
          builder: (context) {
            final ctrl = LingoTextEditingController(
              text: 'larks lead',
              dialect: Dialect.canonical,
            );
            captured = ctrl.buildTextSpan(
              context: context,
              style: null,
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    // Walk the span tree collecting (text, decoration, decorationColor).
    final parts = <(String, TextDecoration?, Color?)>[];
    void visit(InlineSpan s) {
      if (s is! TextSpan) return;
      if (s.children != null) {
        for (final child in s.children!) {
          visit(child);
        }
      } else if (s.text != null && s.text!.isNotEmpty) {
        parts.add((s.text!, s.style?.decoration, s.style?.decorationColor));
      }
    }

    visit(captured!);
    final role = parts.firstWhere(
      (p) => p.$1.toLowerCase() == 'larks',
      orElse: () => ('', null, null),
    );
    expect(role.$2, TextDecoration.underline);
    expect(role.$3, accent);
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

      await _tapMenuItem(tester, 0, 'cut');

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

    await _tapMenuItem(tester, 0, 'cut');

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
      await _openFigure(tester, 0);

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
      await _openFigure(tester, 0);

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
    await _openFigure(tester, 0);

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

  testWidgets('move-up menu item is disabled for the first figure', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await _openMenu(tester, 0);
    final upBtn = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('figure-0-move-up')),
    );
    expect(upBtn.onPressed, isNull);
    // Close and inspect the second figure's menu.
    await _openMenu(tester, 0);

    await _openMenu(tester, 1);
    final upBtn1 = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('figure-1-move-up')),
    );
    expect(upBtn1.onPressed, isNotNull);
  });

  testWidgets('move-down menu item is disabled for the last figure', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await _openMenu(tester, 1);
    final downBtn = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('figure-1-move-down')),
    );
    expect(downBtn.onPressed, isNull);
    await _openMenu(tester, 1);

    await _openMenu(tester, 0);
    final downBtn0 = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('figure-0-move-down')),
    );
    expect(downBtn0.onPressed, isNotNull);
  });

  testWidgets('move-up menu item reorders the draft list', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await _tapMenuItem(tester, 1, 'move-up');

    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'swing');
  });

  testWidgets('move-down menu item reorders the draft list', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await _tapMenuItem(tester, 0, 'move-down');
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

    await _tapMenuItem(tester, 0, 'move-down');

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

    await _tapMenuItem(tester, 0, 'cut');

    expect(find.byKey(const ValueKey('cut-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cut-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cut-banner')), findsNothing);
  });

  testWidgets('cut menu item is disabled on the cut figure itself', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await _tapMenuItem(tester, 0, 'cut');

    // Re-open the cut figure's menu — its Cut item is now disabled.
    await _openMenu(tester, 0);
    final cutBtn = tester.widget<MenuItemButton>(
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
    await _tapMenuItem(tester, 0, 'cut');

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
    await _tapMenuItem(tester, 2, 'cut');

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

    await _tapMenuItem(tester, 0, 'cut');
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

    await _tapMenuItem(tester, 2, 'move-up');
    await _tapMenuItem(tester, 1, 'move-up');

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

  testWidgets(
    'lingo: non-keyword text has no dotted underline; recognized move keyword does',
    (tester) async {
      // Text with no known move keyword — no dotted underline expected.
      final spanBefore = await buildLingoSpan(
        tester,
        text: 'step step',
        dialect: Dialect.canonical,
        taxonomy: contraTaxonomy,
      );
      final beforeParts = flattenSpan(spanBefore);
      expect(
        beforeParts.any((p) => p.$3 == TextDecorationStyle.dotted),
        isFalse,
      );

      // Text containing a recognized move keyword — dotted underline expected.
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
    },
  );

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
      await _openFigure(tester, 0);

      // The field should be visible.
      expect(find.byKey(const ValueKey('figure-0-text')), findsOneWidget);
      // The helper text should mention dotted underline for moves.
      expect(find.textContaining('dotted'), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // Collapse-to-sentence accordion redesign
  // -------------------------------------------------------------------------

  testWidgets('collapsed rows show no param editors or note field at rest', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'swing',
        params: {'who': 'partners', 'beats': 8},
        note: 'smooth',
      ),
      FigureDraft(move: 'balance', params: {'who': 'neighbors', 'beats': 4}),
    ];
    await _pump(tester, drafts);

    // Summaries present; no editor widgets in the tree at rest.
    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsNothing);
    expect(find.byKey(const ValueKey('figure-0-who')), findsNothing);
    expect(find.byKey(const ValueKey('figure-0-note')), findsNothing);
    expect(find.byKey(const ValueKey('figure-0-progression')), findsNothing);
    // Rendered sentence + beats show on the summary.
    expect(find.textContaining('swing'), findsWidgets);
    expect(find.text('8 beats'), findsOneWidget);
    // The only always-visible per-row control is the ⋮ menu.
    expect(find.byKey(const ValueKey('figure-0-menu')), findsOneWidget);
  });

  testWidgets('collapsed empty draft shows placeholder and no beats', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    expect(find.text('(empty — choose a move)'), findsOneWidget);
    expect(find.textContaining('beats'), findsNothing);
  });

  testWidgets('collapsed summary renders the swing balance prefix', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'swing',
        params: {'who': 'partners', 'prefix': 'balance', 'beats': 16},
      ),
    ];
    await _pump(tester, drafts);

    // The collapse-to-sentence row surfaces the prefix via FigureRenderer.
    expect(find.textContaining('balance & swing'), findsOneWidget);
  });

  testWidgets('collapsed row exposes button semantics with composite label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'swing',
        params: {'who': 'partners', 'beats': 16},
        progression: true,
        note: 'smooth',
      ),
    ];
    await _pump(tester, drafts);

    final data = tester
        .getSemantics(find.byKey(const ValueKey('figure-0-summary')))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.label, contains('progression'));
    expect(data.label, contains('16 beats'));
    expect(data.label, contains('Figure 1 of 1'));
    expect(data.label, contains('note: smooth'));
    expect(data.hint, 'Activate to edit');
    handle.dispose();
  });

  testWidgets('accordion opens one editor at a time', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      FigureDraft(move: 'balance', params: {'who': 'neighbors', 'beats': 4}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-move-input')), findsNothing);

    // Opening figure 1 auto-collapses figure 0.
    await tester.tap(find.byKey(const ValueKey('figure-1-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsNothing);
    expect(find.byKey(const ValueKey('figure-1-move-input')), findsOneWidget);
  });

  testWidgets('opening a figure focuses its Move field', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('figure-0-move-input')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('opening a figure does not scroll the list viewport', (
    tester,
  ) async {
    // Regression guard: expanding a figure must NOT animate the list to a new
    // scroll offset (the old behavior scrolled the row to alignment 0.1, which
    // felt like the viewport "jumping" on every open).
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final drafts = List<FigureDraft>.generate(
      14,
      (_) =>
          FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 8}),
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: FigureListEditor(
              drafts: drafts,
              taxonomy: contraTaxonomy,
              phraseStructure: PhraseStructure.standard,
              onChanged: () {},
              onAdd: () {},
              onDelete: (_) {},
              onReorder: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll partway down so an upper-middle figure is visible with room to
    // scroll in either direction — the old ensureVisible(alignment: 0.1) would
    // have changed the offset here.
    controller.jumpTo(150);
    await tester.pumpAndSettle();
    final before = controller.offset;

    final summary = find.byKey(const ValueKey('figure-3-summary'));
    expect(summary, findsOneWidget);
    await tester.tap(summary);
    await tester.pumpAndSettle();

    // Editor is open (Move field mounted) but the viewport did not move.
    expect(find.byKey(const ValueKey('figure-3-move-input')), findsOneWidget);
    expect(controller.offset, before);
  });

  testWidgets('add auto-opens the new figure and focuses its Move field', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
    ];
    await _pump(tester, drafts);
    // The existing figure is collapsed.
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('figure-1-move-input')), findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('figure-1-move-input')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'activating a stand_still figure opens the Move field focused and cleared',
    (tester) async {
      final drafts = <FigureDraft>[
        FigureDraft(move: 'stand_still', params: {'beats': 8}),
      ];
      await _pump(tester, drafts);
      // The collapsed summary still reads the placeholder move.
      expect(find.text('stand still'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('figure-0-move-input')),
          matching: find.byType(EditableText),
        ),
      );
      // Field is focused so the caller can type immediately...
      expect(editable.focusNode.hasFocus, isTrue);
      // ...and blank so they don't have to delete the "stand still" placeholder.
      expect(editable.controller.text, isEmpty);
      // The stored draft is NOT mutated: collapsing as-is keeps stand_still × 8.
      expect(drafts.single.move, 'stand_still');
      expect(drafts.single.params['beats'], 8);
    },
  );

  testWidgets('activating a real figure keeps its Move field text', (
    tester,
  ) async {
    // Clearing on open must apply ONLY to stand_still — a real move must never
    // be wiped out from under the caller.
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 8}),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('figure-0-move-input')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, 'swing');
    // An already-set move opens for PARAM edits, not re-entry: the Move text
    // field must NOT steal focus (autofocus is gated to blank/stand_still).
    expect(editable.focusNode.hasFocus, isFalse);
  });

  testWidgets(
    'cold start: add-figure and stand_still-activate both focus the Move '
    'field without any prior manual focus',
    (tester) async {
      // Regression for the PR #140 cold-start gotcha: on a freshly opened
      // editor where nothing has been focused yet, the enclosing FocusScope is
      // not the active scope, so a queued `TextField.autofocus` request is
      // dropped and the Move field opens UNfocused. The bug only healed itself
      // after the user manually tapped some field once. MoveAutocomplete now
      // explicitly requestFocus()es its FocusNode after the first frame, which
      // activates the ancestor scopes and works from a cold start.
      FocusNode moveFocusNode(int index) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(ValueKey('figure-$index-move-input')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;

      final drafts = <FigureDraft>[
        FigureDraft(move: 'stand_still', params: {'beats': 8}),
      ];
      await _pump(tester, drafts);

      // Open path 1: activate the existing stand_still chip. The field must be
      // focused AND cleared, straight from the cold state.
      await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
      await tester.pumpAndSettle();
      expect(moveFocusNode(0).hasFocus, isTrue);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('figure-0-move-input')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );

      // Collapse it again so the next open is the Add path.
      await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
      await tester.pumpAndSettle();

      // Open path 2: add a new figure — its Move field auto-focuses too.
      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('figure-1-move-input')), findsOneWidget);
      expect(moveFocusNode(1).hasFocus, isTrue);
    },
  );

  testWidgets('more than 3 params hide extras behind "More options"', (
    tester,
  ) async {
    // allemande has 4 params (who, hand, turn, beats): first 3 inline, the
    // 4th (beats) behind the disclosure.
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.0, 'beats': 8},
      ),
    ];
    await _pump(tester, drafts);
    await _openFigure(tester, 0);
    // Dismiss the autocomplete options overlay so the params are hittable.
    await _dismissAutocomplete(tester);

    expect(find.byKey(const ValueKey('figure-0-who')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-hand')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-turn-value')), findsOneWidget);
    // 4th param hidden until the disclosure is expanded.
    expect(find.byKey(const ValueKey('figure-0-beats')), findsNothing);
    expect(find.byKey(const ValueKey('figure-0-more-options')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('figure-0-more-options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-beats')), findsOneWidget);
  });

  testWidgets('3 or fewer params render inline with no disclosure', (
    tester,
  ) async {
    // swing has 3 params (who, prefix, beats) — all inline, no disclosure.
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'swing',
        params: {'who': 'partners', 'prefix': 'none', 'beats': 8},
      ),
    ];
    await _pump(tester, drafts);
    await _openFigure(tester, 0);

    expect(find.byKey(const ValueKey('figure-0-who')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-beats')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-more-options')), findsNothing);
  });

  testWidgets('Alt+ArrowDown on a focused row reorders it', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    // Focus the first collapsed row (its enclosing row FocusNode).
    Focus.of(
      tester.element(find.byKey(const ValueKey('figure-0-summary'))),
    ).requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(drafts[0].move, 'balance');
    expect(drafts[1].move, 'swing');
  });

  testWidgets('duplicate menu item clones the figure after the source', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'swing',
        params: {'who': 'partners', 'beats': 8},
        note: 'smooth',
        progression: true,
      ),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);

    await _tapMenuItem(tester, 0, 'duplicate');

    expect(drafts, hasLength(3));
    // Clone inserted right after the source.
    expect(drafts[1].move, 'swing');
    expect(drafts[1].note, 'smooth');
    expect(drafts[1].progression, isTrue);
    // Fresh id + independent params map.
    expect(drafts[1].id, isNot(drafts[0].id));
    expect(identical(drafts[1].params, drafts[0].params), isFalse);
  });

  testWidgets('duplicate menu item is absent when onDuplicate is not wired', (
    tester,
  ) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
    ];
    await _pump(tester, drafts, wireDuplicate: false);

    await _openMenu(tester, 0);
    expect(find.byKey(const ValueKey('figure-0-duplicate')), findsNothing);
    // Other items remain present.
    expect(find.byKey(const ValueKey('figure-0-delete')), findsOneWidget);
  });

  testWidgets('toggle-progression menu item flips the flag', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
    ];
    await _pump(tester, drafts);
    expect(drafts.single.progression, isFalse);

    await _tapMenuItem(tester, 0, 'toggle-progression');

    expect(drafts.single.progression, isTrue);
    // The progression marker glyph now shows on the collapsed summary.
    expect(find.byIcon(progressionIcon), findsOneWidget);
  });

  testWidgets('Escape collapses the open editor', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsNothing);
  });

  testWidgets('Ctrl+Enter commits and opens the next figure', (tester) async {
    final drafts = <FigureDraft>[FigureDraft(), FigureDraft()];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Figure 0 collapsed, figure 1 now open.
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsNothing);
    expect(find.byKey(const ValueKey('figure-1-move-input')), findsOneWidget);
  });

  group('param-value-dependent beats (ContraDB paramBeats)', () {
    // hey's `length` (4th param) and `beats` (10th) live behind the ">3 params"
    // More-options disclosure, so reveal it before touching them.
    Future<void> revealMore(WidgetTester tester, int index) async {
      await _dismissAutocomplete(tester);
      await tester.tap(find.byKey(ValueKey('figure-$index-more-options')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'changing hey length half->full recomputes 8->16 when untouched',
      (tester) async {
        final drafts = <FigureDraft>[FigureDraft()];
        await _pump(tester, drafts);
        await _selectMove(tester, 0, 'hey', 'hey');
        // The default half hey derives 8 beats and stays unowned.
        expect(drafts.single.move, 'hey');
        expect(drafts.single.beats, 8);
        expect(drafts.single.beatsTouched, isFalse);

        await revealMore(tester, 0);
        await _selectDropdownOption(tester, 'figure-0-length', 'full');
        // A full hey re-derives to 16 (ContraDB meetTimes 2 * 8).
        expect(drafts.single.params['length'], 'full');
        expect(drafts.single.beats, 16);
        expect(drafts.single.beatsTouched, isFalse);
      },
    );

    testWidgets('a manual beats override survives a hey length change', (
      tester,
    ) async {
      final drafts = <FigureDraft>[FigureDraft()];
      await _pump(tester, drafts);
      await _selectMove(tester, 0, 'hey', 'hey');
      await revealMore(tester, 0);

      // Editing beats directly takes ownership of the value.
      await tester.enterText(
        find.byKey(const ValueKey('figure-0-beats')),
        '12',
      );
      await tester.pumpAndSettle();
      expect(drafts.single.beats, 12);
      expect(drafts.single.beatsTouched, isTrue);

      // Flipping length must not clobber the manual override.
      await _selectDropdownOption(tester, 'figure-0-length', 'full');
      expect(drafts.single.params['length'], 'full');
      expect(drafts.single.beats, 12);
    });

    testWidgets(
      'a full move change resets beats after a param-driven recompute',
      (tester) async {
        final drafts = <FigureDraft>[FigureDraft()];
        await _pump(tester, drafts);
        await _selectMove(tester, 0, 'hey', 'hey');
        await revealMore(tester, 0);
        await _selectDropdownOption(tester, 'figure-0-length', 'full');
        expect(drafts.single.beats, 16);

        // Switching moves resets to the new move's canonical default and
        // clears ownership (preserving #131 behavior).
        await _selectMove(tester, 0, 'ba', 'balance');
        expect(drafts.single.move, 'balance');
        expect(drafts.single.beats, 4);
        expect(drafts.single.beatsTouched, isFalse);
      },
    );

    testWidgets(
      'toggling rory_o_more balance recomputes beats 8<->4 when untouched',
      (tester) async {
        final drafts = <FigureDraft>[FigureDraft()];
        await _pump(tester, drafts);
        await _selectMove(tester, 0, 'rory', 'rory_o_more');
        // A balanced Rory O'More derives 8 beats and stays unowned.
        expect(drafts.single.move, 'rory_o_more');
        expect(drafts.single.params['balance'], true);
        expect(drafts.single.beats, 8);
        expect(drafts.single.beatsTouched, isFalse);

        // Dropping the balance (a flag param) re-derives to 4 beats.
        await _dismissAutocomplete(tester);
        await tester.tap(find.byKey(const ValueKey('figure-0-balance')));
        await tester.pumpAndSettle();
        expect(drafts.single.params['balance'], false);
        expect(drafts.single.beats, 4);
        expect(drafts.single.beatsTouched, isFalse);
      },
    );
  });

  group('#262 snap beats only when the default actually changes', () {
    testWidgets(
      'snap branch: swing prefix none->balance snaps 8->16 when untouched',
      (tester) async {
        final drafts = <FigureDraft>[FigureDraft()];
        await _pump(tester, drafts);
        await _selectMove(tester, 0, 'sw', 'swing');
        expect(drafts.single.beats, 8);
        expect(drafts.single.beatsTouched, isFalse);

        // Adding a balance prefix moves the default 8->16, so beats snaps.
        await _selectDropdownOption(tester, 'figure-0-prefix', 'balance');
        expect(drafts.single.params['prefix'], 'balance');
        expect(drafts.single.beats, 16);
        expect(drafts.single.beatsTouched, isFalse);
      },
    );

    testWidgets('no-snap branch: a circle turn change leaves beats untouched', (
      tester,
    ) async {
      final drafts = <FigureDraft>[FigureDraft()];
      await _pump(tester, drafts);
      await _selectMove(tester, 0, 'circle', 'circle');
      expect(drafts.single.params['turn'], 'left');
      expect(drafts.single.beats, 8);
      expect(drafts.single.beatsTouched, isFalse);

      // Circle has no paramBeats: the default stays 8 regardless of the
      // direction, so beats must not be re-snapped.
      await _selectDropdownOption(tester, 'figure-0-turn', 'right');
      expect(drafts.single.params['turn'], 'right');
      expect(drafts.single.beats, 8);
      expect(drafts.single.beatsTouched, isFalse);
    });

    testWidgets(
      'opt-out: a manual beats edit survives a default-changing param change',
      (tester) async {
        final drafts = <FigureDraft>[FigureDraft()];
        await _pump(tester, drafts);
        await _selectMove(tester, 0, 'sw', 'swing');

        // The user pins beats to 10, taking ownership of the value.
        await tester.enterText(
          find.byKey(const ValueKey('figure-0-beats')),
          '10',
        );
        await tester.pumpAndSettle();
        expect(drafts.single.beats, 10);
        expect(drafts.single.beatsTouched, isTrue);

        // A balance prefix would normally snap 8->16, but the manual override
        // is never overwritten.
        await _selectDropdownOption(tester, 'figure-0-prefix', 'balance');
        expect(drafts.single.params['prefix'], 'balance');
        expect(drafts.single.beats, 10);
        expect(drafts.single.beatsTouched, isTrue);
      },
    );

    testWidgets(
      'seeds missing beats from the default on a no-default-change edit',
      (tester) async {
        // Older/partial data: a loaded figure with no explicit beats is unowned
        // and reads back as 0 until it's seeded.
        final drafts = <FigureDraft>[
          FigureDraft.fromFigure(
            Figure(move: 'circle', params: const {'turn': 'left'}),
          ),
        ];
        expect(drafts.single.beatsTouched, isFalse);
        expect(drafts.single.beats, 0);

        await _pump(tester, drafts);
        await _openFigure(tester, 0);

        // Changing turn doesn't move circle's (paramBeats-free) default, but a
        // missing count is still seeded to the canonical 8 rather than left at
        // 0.
        await _selectDropdownOption(tester, 'figure-0-turn', 'right');
        expect(drafts.single.params['turn'], 'right');
        expect(drafts.single.beats, 8);
        expect(drafts.single.beatsTouched, isFalse);
      },
    );
  });
}
