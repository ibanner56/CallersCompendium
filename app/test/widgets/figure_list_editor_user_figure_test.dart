import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/editor/user_figure_draft.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The user's own new figures in the figure list (#1023): offered in a row's
/// move picker, a meanwhile side's too, and edited there by their arguments.
void main() {
  final zoom = UserGlossaryEntry(
    id: 'zoom-id',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'zoom',
    definition: 'A zoom.',
    description: 'Fast.',
    keywords: const ['whoosh'],
    payload: {
      'template': '{who} {move} {pace}',
      'defaultBeats': 6,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'role1s'},
        {
          'key': 'pace',
          'kind': 'choice',
          'choices': [
            {'id': 'c1', 'label': 'slowly'},
            {'id': 'c2', 'label': 'briskly'},
          ],
          'default': 'c1',
        },
      ],
    },
    createdAt: DateTime.utc(2026, 10, 15),
  );

  Future<void> pump(
    WidgetTester tester,
    List<FigureDraft> drafts, {
    List<UserGlossaryEntry>? options,
    bool withFigure = true,
  }) async {
    final repos = openTestRepositories();
    if (withFigure) {
      await tester.runAsync(() => repos.userGlossary.upsert(zoom));
    }
    final userFigures = UserFiguresController(repos.userGlossary);
    addTearDown(userFigures.dispose);
    // The controller's first read of the glossary.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: UserFiguresScope(
          controller: userFigures,
          child: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => FigureListEditor(
                  drafts: drafts,
                  taxonomy: contraTaxonomy,
                  phraseStructure: PhraseStructure.standard,
                  dialect: Dialect.larksRobins,
                  onChanged: () => setState(() {}),
                  onAdd: () => setState(() => drafts.add(FigureDraft())),
                  onDelete: (d) => setState(() => drafts.remove(d)),
                  onReorder: (from, to) => setState(() {
                    drafts.insert(to, drafts.removeAt(from));
                  }),
                  onGroupWithNext: (_) {},
                  onGroupWithNextAsModifier: (_) {},
                  userFigureOptions: options ?? [zoom],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pumpAndSettle();
  }

  FigureDraft use({Map<String, Object?>? args}) => FigureDraft(
    move: customMove,
    params: userFigureDraftParams(
      zoom,
      decodeUserFigureDefinition(zoom.payload)!,
      args: args,
    ),
  );

  testWidgets('a row offers a figure of your own first, found by name or '
      'keyword, and picking it makes the row a use with its defaults', (
    tester,
  ) async {
    final drafts = [FigureDraft()];
    await pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();

    const option = ValueKey('figure-0-move-option-userFigure:zoom-id');
    await type(tester, 'figure-0-move-input', 'whoosh');
    expect(find.byKey(option), findsOneWidget, reason: 'a keyword');
    await type(tester, 'figure-0-move-input', 'zoo');
    expect(find.byKey(option), findsOneWidget);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.first.key, option, reason: 'before the moves');

    await tester.tap(find.byKey(option));
    await tester.pumpAndSettle();
    final draft = drafts.single;
    expect(isUserFigureDraft(draft), isTrue);
    expect(draft.params[userFigureRefKey], 'zoom-id');
    expect(draft.params[userFigureArgsKey], {'who': 'role1s', 'pace': 'c1'});
    expect(draft.params['beats'], 6);
    expect(draft.params['text'], 'role1s zoom slowly');
    expect(
      find.byKey(const ValueKey('figure-0-userFigure-pace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('figure-0-userFigure-beats')),
      findsOneWidget,
    );
  });

  testWidgets('changing an argument re-renders the row\'s line, which stays '
      'attached', (tester) async {
    final drafts = [use()];
    await pump(tester, drafts);
    expect(find.text('larks zoom slowly'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('figure-0-userFigure-pace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('briskly').last);
    await tester.pumpAndSettle();

    final draft = drafts.single;
    expect(draft.params[userFigureArgsKey], {'who': 'role1s', 'pace': 'c2'});
    expect(draft.params['text'], 'role1s zoom briskly');
    expect(isUserFigureDraft(draft), isTrue, reason: 'the check follows');
    expect(find.text('larks zoom briskly'), findsOneWidget);
  });

  testWidgets('a meanwhile side offers a figure of your own, and edits its '
      'arguments but not its beats, which the group owns', (tester) async {
    final drafts = [
      FigureDraft(meanwhileSides: [FigureDraft(), FigureDraft()])
        ..params['beats'] = 8,
    ];
    await pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await type(tester, 'figure-0-side-0-move-input', 'zoom');
    await tester.tap(
      find.byKey(
        const ValueKey('figure-0-side-0-move-option-userFigure:zoom-id'),
      ),
    );
    await tester.pumpAndSettle();

    final side = drafts.single.meanwhileSides!.first;
    expect(isUserFigureDraft(side), isTrue);
    expect(
      find.byKey(const ValueKey('figure-0-side-0-userFigure-pace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('figure-0-side-0-userFigure-beats')),
      findsNothing,
    );
  });

  testWidgets('no figure of your own is offered without options', (
    tester,
  ) async {
    await pump(tester, [FigureDraft()], options: const []);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await type(tester, 'figure-0-move-input', 'zoom');
    expect(
      find.byKey(const ValueKey('figure-0-move-option-userFigure:zoom-id')),
      findsNothing,
    );
  });

  testWidgets('a use whose figure is gone says so and keeps its line', (
    tester,
  ) async {
    final drafts = [use()];
    await pump(tester, drafts, withFigure: false);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('figure-0-userFigure-unavailable')),
      findsOneWidget,
    );
    expect(drafts.single.params['text'], 'role1s zoom slowly');
    expect(isUserFigureDraft(drafts.single), isTrue);
  });

  testWidgets('a row\'s name for screen readers reads a use\'s line in the '
      'dialect, not its stored role tokens', (tester) async {
    await pump(tester, [use()]);
    expect(find.byTooltip('Actions for larks zoom slowly'), findsOneWidget);
    expect(find.byTooltip('Actions for role1s zoom slowly'), findsNothing);
  });
}
