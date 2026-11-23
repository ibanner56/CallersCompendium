import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The sequence container in [FigureListEditor]: its picker entry, Add menu
/// entry, row-menu grouping, the steps' own beats and total, and the
/// four-step and one-phrase limits.
class _Host extends StatefulWidget {
  const _Host({required this.drafts, required this.phrase, this.onEdit});

  final List<FigureDraft> drafts;
  final PhraseStructure phrase;

  /// Called for every edit the editor reports to its host.
  final VoidCallback? onEdit;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _aggressive = ValueNotifier(false);

  @override
  void dispose() {
    _aggressive.dispose();
    super.dispose();
  }

  void _groupWithNext(FigureDraft draft, String kind) => setState(() {
    final i = widget.drafts.indexOf(draft);
    final group = FigureDraft.group(kind, draft, widget.drafts[i + 1]);
    widget.drafts
      ..removeRange(i, i + 2)
      ..insert(i, group);
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    home: AggressiveBeatsUpdateScope(
      notifier: _aggressive,
      child: Scaffold(
        body: SingleChildScrollView(
          child: FigureListEditor(
            drafts: widget.drafts,
            taxonomy: contraTaxonomy,
            phraseStructure: widget.phrase,
            onChanged: () {
              widget.onEdit?.call();
              setState(() {});
            },
            onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
            onAddSequence: () {
              final draft = FigureDraft(
                sequenceFigures: [FigureDraft(), FigureDraft()],
              );
              setState(() => widget.drafts.add(draft));
              return Future.value(draft.id);
            },
            onDelete: (d) => setState(() => widget.drafts.remove(d)),
            onGroupWithNext: (d) => _groupWithNext(d, meanwhileMove),
            onGroupWithNextAsSequence: (d) => _groupWithNext(d, sequenceMove),
            onConvertToSequence: (d) =>
                setState(() => d.convertContainerTo(sequenceMove)),
            onCollapseMeanwhileGroup: (group, remaining) => setState(() {
              widget.drafts[widget.drafts.indexOf(group)] = remaining;
            }),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<FigureDraft> drafts, {
  PhraseStructure phrase = PhraseStructure.standard,
  VoidCallback? onEdit,
}) async {
  const size = Size(1200, 2400);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    _Host(drafts: drafts, phrase: phrase, onEdit: onEdit),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
  await tester.pumpAndSettle();
}

FigureDraft _step(String move, int beats) =>
    FigureDraft(move: move, params: {'beats': beats}, beatsTouched: true);

void main() {
  testWidgets('the move picker turns a row into a sequence', (tester) async {
    final drafts = [FigureDraft()];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'seq',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('figure-0-move-option-sequence')),
    );
    await tester.pumpAndSettle();

    expect(drafts.single.isSequenceGroup, isTrue);
    expect(drafts.single.sequenceFigures, hasLength(2));
    expect(find.text('Sequence (2 figures)'), findsOneWidget);
  });

  testWidgets('the Add menu inserts and opens a sequence', (tester) async {
    final drafts = <FigureDraft>[];
    await _pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-add-sequence')));
    await tester.pumpAndSettle();

    expect(drafts.single.isSequenceGroup, isTrue);
    expect(find.byKey(const ValueKey('figure-0-sequence-beats')), findsOne);
  });

  testWidgets('each step edits its own beats, which add up to the total', (
    tester,
  ) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 8)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(find.text('12 beats in total'), findsOneWidget);
    // No shared Beats field: the steps own the count.
    expect(find.byKey(const ValueKey('figure-0-sequence-beats')), findsOne);
    expect(
      find.byKey(const ValueKey('figure-0-sequence-beats-beats')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-1-beats')),
      '12',
    );
    await tester.pumpAndSettle();

    expect(drafts.single.beats, 16);
    expect(find.text('16 beats in total'), findsOneWidget);
    expect(drafts.single.toFigure()!.beats, 16);
  });

  testWidgets('a free-text step edits its own beats like any other step', (
    tester,
  ) async {
    final custom = FigureDraft(
      move: customMove,
      params: {'text': 'funky thing', 'beats': 8},
      beatsTouched: true,
    );
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), custom]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(find.text('12 beats in total'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-1-beats')),
      '4',
    );
    await tester.pumpAndSettle();

    expect(custom.params['beats'], 4);
    expect(find.text('8 beats in total'), findsOneWidget);
    final built = drafts.single.toFigure()!;
    expect(built.beats, 8);
    expect(built.subFigures.last.params['beats'], 4);
  });

  testWidgets('a free-text step with no stored count is seeded, not zeroed', (
    tester,
  ) async {
    final custom = FigureDraft(move: customMove, params: {'text': 'old line'});
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), custom]),
    ];
    var edits = 0;
    await _pump(tester, drafts, onEdit: () => edits++);
    await _open(tester, 0);

    // Seeding is not an edit: opening a row must not mark the dance dirty.
    expect(edits, 0);
    expect(custom.params['beats'], isNotNull);
    expect(find.text('${drafts.single.beats} beats in total'), findsOneWidget);
    expect(drafts.single.beats, greaterThan(4));
    expect(drafts.single.toFigure()!.subFigures.last.beats, custom.beats);
    expect(custom.beats, greaterThan(0));
  });

  testWidgets('a free-text meanwhile side still shows no beats of its own', (
    tester,
  ) async {
    final drafts = [
      FigureDraft(
        meanwhileSides: [
          _step('balance', 4),
          FigureDraft(move: customMove, params: {'text': 'x', 'beats': 8}),
        ],
      ),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(find.byKey(const ValueKey('figure-0-side-1-beats')), findsNothing);
  });

  testWidgets('a sequence stops at four steps', (tester) async {
    final drafts = [
      FigureDraft(
        sequenceFigures: [for (var i = 0; i < 3; i++) _step('balance', 2)],
      ),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.tap(find.byKey(const ValueKey('figure-0-add-side')));
    await tester.pumpAndSettle();

    expect(drafts.single.sequenceFigures, hasLength(kMaxSequenceFigures));
    expect(find.byKey(const ValueKey('figure-0-add-side')), findsNothing);
    expect(find.text('Maximum of 4 figures in a sequence.'), findsOneWidget);
  });

  testWidgets('no step is added once the steps fill a phrase', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 8), _step('swing', 8)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(find.byKey(const ValueKey('figure-0-add-side')), findsNothing);
    expect(
      find.text('These figures fill one phrase (16 beats).'),
      findsOneWidget,
    );
  });

  testWidgets('a sequence longer than a phrase is flagged', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 8), _step('swing', 12)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(
      find.byKey(const ValueKey('figure-0-sequence-over-phrase')),
      findsOneWidget,
    );
  });

  testWidgets('the phrase is the dance\'s own', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 8), _step('swing', 8)]),
    ];
    await _pump(tester, drafts, phrase: PhraseStructure.parse('4*12*2'));
    await _open(tester, 0);

    expect(find.byKey(const ValueKey('figure-0-add-side')), findsOneWidget);
  });

  group('a sequence fits the phrase it sits in (23 November 2026)', () {
    // A1 and A2 are 8 beats each, B is 16: a tune in one meter whose phrases
    // differ in length.
    final uneven = PhraseStructure.parse('2*4*2 + 1*8*2');

    testWidgets('no step is added once the steps fill a short phrase', (
      tester,
    ) async {
      final drafts = [
        FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 4)]),
      ];
      await _pump(tester, drafts, phrase: uneven);
      await _open(tester, 0);
      expect(find.byKey(const ValueKey('figure-0-add-side')), findsNothing);
      expect(
        find.text('These figures fill one phrase (8 beats).'),
        findsOneWidget,
      );
    });

    testWidgets('the same steps in the long phrase may take another', (
      tester,
    ) async {
      final drafts = [
        _step('swing', 8),
        _step('swing', 8),
        FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 4)]),
      ];
      await _pump(tester, drafts, phrase: uneven);
      await _open(tester, 2);
      expect(find.byKey(const ValueKey('figure-2-add-side')), findsOneWidget);
    });

    testWidgets('"Group with next as sequence" follows the phrase the first '
        'row sits in', (tester) async {
      final drafts = [
        _step('balance', 4),
        _step('swing', 8),
        _step('swing', 4),
        _step('balance', 4),
        _step('swing', 8),
      ];
      await _pump(tester, drafts, phrase: uneven);

      // From beat 0, in an 8-beat phrase: 4 + 8 is too long.
      await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('figure-0-group-with-next-sequence')),
        findsNothing,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // From beat 16, in B: the same 4 + 8 fits.
      await tester.tap(find.byKey(const ValueKey('figure-3-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('figure-3-group-with-next-sequence')),
      );
      await tester.pumpAndSettle();
      expect(drafts, hasLength(4));
      expect(drafts.last.isSequenceGroup, isTrue);
      expect(drafts.last.beats, 12);
    });
  });

  testWidgets('"Group with next as sequence" is offered only when it fits', (
    tester,
  ) async {
    final drafts = [
      _step('balance', 4),
      _step('swing', 12),
      _step('swing', 16),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-1-menu')));
    await tester.pumpAndSettle();
    // 12 + 16 beats is longer than a phrase; a meanwhile is still offered.
    expect(
      find.byKey(const ValueKey('figure-1-group-with-next-sequence')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('figure-1-group-with-next')), findsOne);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('figure-0-group-with-next-sequence')),
    );
    await tester.pumpAndSettle();

    expect(drafts, hasLength(2));
    expect(drafts.first.isSequenceGroup, isTrue);
    expect(drafts.first.beats, 16);
  });

  testWidgets('a meanwhile side can become a sequence', (tester) async {
    final drafts = [
      FigureDraft(meanwhileSides: [_step('balance', 4), _step('orbit', 8)])
        ..params['beats'] = 8,
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-0-move-input')),
      'seq',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('figure-0-side-0-move-option-sequence')),
    );
    await tester.pumpAndSettle();

    final side = drafts.single.meanwhileSides!.first;
    expect(side.isSequenceGroup, isTrue);
    expect(side.sequenceFigures!.first.move, 'balance');
  });

  testWidgets('a sequence step cannot become another sequence', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 8)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-0-move-input')),
      'seq',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('figure-0-side-0-move-option-sequence')),
      findsNothing,
    );
  });

  testWidgets('a group takes an optional title, shown before its figures', (
    tester,
  ) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 12)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    final field = find.byKey(const ValueKey('figure-0-container-title'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Flutterwheel');
    await tester.pumpAndSettle();

    expect(drafts.single.containerTitle, 'Flutterwheel');
    final figure = drafts.single.toFigure()!;
    expect(figure.containerTitle, 'Flutterwheel');
    expect(
      find.textContaining('Flutterwheel - ', findRichText: true),
      findsWidgets,
    );

    // Clearing the field clears the title.
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(drafts.single.params.containsKey(containerTitleKey), isFalse);
    expect(drafts.single.toFigure()!.containerTitle, isNull);
  });

  testWidgets('a group nested in another has its own title field', (
    tester,
  ) async {
    final inner = FigureDraft(
      sequenceFigures: [_step('balance', 4), _step('swing', 4)],
    );
    final drafts = [
      FigureDraft(meanwhileSides: [inner, _step('swing', 8)])
        ..params['beats'] = 8,
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.tap(
      find.byKey(ValueKey('nested-container-${inner.id}')).first,
    );
    await tester.pumpAndSettle();

    final fields = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.endsWith('-container-title'),
    );
    expect(fields, findsNWidgets(2));
  });

  testWidgets('the title field counts length as the model does, so save never '
      'cuts what it shows', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 12)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    // 41 emoji: 41 characters to the reader, 82 UTF-16 code units.
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-container-title')),
      '\u{1F483}' * 41,
    );
    await tester.pumpAndSettle();

    final title = drafts.single.containerTitle;
    expect(title.length, lessThanOrEqualTo(kMaxContainerTitleLength));
    expect(title, '\u{1F483}' * 40);
    expect(drafts.single.toFigure()!.containerTitle, title);
  });

  testWidgets('the title field measures role words as Save stores them, so '
      'save keeps all it shows', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 12)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    // 80 units as typed; "men" is stored as "role1s", three units longer.
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-container-title')),
      'men ${'x' * 76}',
    );
    await tester.pumpAndSettle();

    final shown = drafts.single.containerTitle;
    expect(shown.length, lessThan(kMaxContainerTitleLength));
    final saved = drafts.single.toFigure(
      canonicalizeNote: (text) =>
          canonicalizeText(text.trim(), Dialect.canonical),
    )!;
    expect(
      saved.containerTitle,
      canonicalizeText(shown.trim(), Dialect.canonical),
    );
  });
}
