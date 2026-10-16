import 'dart:async';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/decimal_turns_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The user's own figures and notes in the Glossary (#709).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final created = DateTime.utc(2026, 10, 14, 9);

  /// The maintainer's worked example: four pull-bys alternating hands.
  CompoundDefinition grandRightAndLeft() {
    Figure pullBy() => Figure(
      move: 'pull_by',
      params: const {'who': 'neighbors', 'hand': 'right', 'beats': 2},
    );
    return CompoundDefinition(
      params: const [
        CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        CompoundParam(key: 'hand', kind: ParamKind.handedness),
      ],
      figures: [pullBy(), pullBy(), pullBy(), pullBy()],
      bindings: [
        for (var i = 0; i < 4; i++) ...[
          CompoundSlotBinding(figureIndex: i, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(
            figureIndex: i,
            slotKey: 'hand',
            paramKey: 'hand',
            source: i.isEven
                ? CompoundBindingSource.declared
                : CompoundBindingSource.opposite,
          ),
        ],
      ],
    );
  }

  UserGlossaryEntry entry({
    String id = 'grl',
    String kindName = 'compound',
    String name = 'grand right and left',
    Object? payload,
    List<String> keywords = const ['grl'],
  }) => UserGlossaryEntry(
    id: id,
    kindName: kindName,
    name: name,
    definition: 'Pull by alternating hands around the ring.',
    description: 'Four pull-bys, starting with the hand you choose.',
    keywords: keywords,
    payload: payload ?? grandRightAndLeft().toJson(),
    createdAt: created,
  );

  Future<({CompendiumRepositories repos, ValueNotifier<bool> custom})> pump(
    WidgetTester tester, {
    bool custom = true,
    List<UserGlossaryEntry> entries = const [],
    Size size = const Size(500, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    for (final e in entries) {
      await tester.runAsync(() => repos.userGlossary.upsert(e));
    }
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final glossary = ValueNotifier<bool>(true);
    final customFigures = ValueNotifier<bool>(custom);
    final decimals = ValueNotifier<bool>(false);
    final verbose = ValueNotifier<bool>(false);
    for (final n in [glossary, customFigures, decimals, verbose]) {
      addTearDown(n.dispose);
    }
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShowGlossaryScope(
              notifier: glossary,
              child: ShowCustomFiguresScope(
                notifier: customFigures,
                child: DecimalTurnsScope(
                  notifier: decimals,
                  child: VerboseFigureRenderingScope(
                    notifier: verbose,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
        home: const GlossaryScreen(),
      ),
    );
    await tester.pumpAndSettle();
    return (repos: repos, custom: customFigures);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('glossary-search')),
      query,
    );
    await tester.pumpAndSettle();
  }

  const customRow = ValueKey('glossary-entry-custom:grl');

  group('custom figures in the list', () {
    testWidgets('are listed, marked as custom, while Custom Figures is on', (
      tester,
    ) async {
      await pump(tester, entries: [entry()]);
      await search(tester, 'grand right');
      expect(find.byKey(customRow), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(customRow),
          matching: find.text('Custom'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('glossary-add-custom')), findsOneWidget);
    });

    testWidgets('are hidden, not deleted, while it is off', (tester) async {
      final h = await pump(tester, custom: false, entries: [entry()]);
      await search(tester, 'grand right');
      expect(find.byKey(customRow), findsNothing);
      expect(find.byKey(const ValueKey('glossary-add-custom')), findsNothing);
      expect(
        await tester.runAsync(() => h.repos.userGlossary.getById('grl')),
        isNotNull,
      );

      h.custom.value = true;
      await tester.pumpAndSettle();
      expect(find.byKey(customRow), findsOneWidget);
    });

    testWidgets('are found by their other names', (tester) async {
      await pump(tester, entries: [entry()]);
      await search(tester, 'grl');
      expect(find.byKey(customRow), findsOneWidget);
    });

    testWidgets('are found by another name as the dialect shows it, not as '
        'it is stored', (tester) async {
      await pump(
        tester,
        entries: [
          entry(keywords: const ['role1s ring']),
        ],
      );
      await search(tester, 'larks ring');
      expect(find.byKey(customRow), findsOneWidget);
    });

    testWidgets('one that no longer decodes says it needs repair, and one '
        'named like a built-in figure that it needs renaming', (tester) async {
      await pump(
        tester,
        entries: [
          entry(id: 'broken', name: 'broken one', payload: const {'x': 1}),
          entry(id: 'clash', name: 'pull by', keywords: const []),
        ],
      );
      await search(tester, 'broken one');
      expect(find.text('Needs repair'), findsOneWidget);
      await search(tester, 'pull by');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('glossary-entry-custom:clash')),
          matching: find.text('Rename needed'),
        ),
        findsOneWidget,
      );
    });
  });

  group('a figure of your own (#1023)', () {
    UserGlossaryEntry zoom() => entry(
      id: 'zoom-id',
      kindName: UserGlossaryEntryKind.customFigure.name,
      name: 'zoom',
      keywords: const [],
      payload: const {
        'form': 'ecd',
        'template': 'role1s {move} {hand}',
        'defaultBeats': 8,
        'params': [
          {'key': 'hand', 'kind': 'handedness', 'default': 'right'},
        ],
      },
    );

    Future<void> open(WidgetTester tester) async {
      await search(tester, 'zoom');
      await tester.tap(
        find.byKey(const ValueKey('glossary-entry-custom:zoom-id')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows its wording, an example and its dance form, in the '
        'dialect', (tester) async {
      await pump(tester, entries: [zoom()]);
      await open(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('glossary-custom-wording')))
            .data,
        'larks {move} {hand}',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('glossary-custom-example')))
            .data,
        'larks zoom right',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('glossary-custom-form')))
            .data,
        'English (ECD)',
      );
      expect(find.text('Needs repair'), findsNothing);
    });

    testWidgets('deleting it says how many dances use it, and leaves each '
        'with its current wording as plain text', (tester) async {
      final (:repos, custom: _) = await pump(tester, entries: [zoom()]);
      await tester.runAsync(
        () => repos.dances.create(
          Dance(
            id: 'd1',
            title: 'Zoom Reel',
            figures: [
              userFigureUseFigure(
                id: 'zoom-id',
                args: const {'hand': 'left'},
                text: 'a stale line',
              ),
            ],
            createdAt: created,
            updatedAt: created,
          ),
        ),
      );
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('glossary-custom-delete')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('glossary-custom-delete-body')),
            )
            .data,
        "1 dance uses it. It's removed from your Glossary, and that dance "
        'keeps its current wording as plain text.',
      );
      await tester.tap(
        find.byKey(const ValueKey('glossary-custom-delete-confirm')),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final dance = (await tester.runAsync(() => repos.dances.getById('d1')))!;
      final figure = switch (dance.figuresSource) {
        DecodedFigures(:final figures) => figures.single,
        UnreadableFigures() => throw StateError('unreadable'),
      };
      expect(figure.params, {'text': 'role1s zoom left'});
      expect(
        await tester.runAsync(() => repos.userGlossary.getById('zoom-id')),
        isNull,
      );
    });
  });

  group('entries of a kind this build cannot use (#1023)', () {
    for (final kind in ['term', 'someLaterKind']) {
      testWidgets('a $kind entry says it is from a newer version, and cannot '
          'be edited as a compound', (tester) async {
        await pump(
          tester,
          entries: [
            entry(
              id: 'newer',
              kindName: kind,
              name: 'contra corners',
              payload: const {'form': 'contra'},
              keywords: const [],
            ),
          ],
        );
        await search(tester, 'contra corners');
        final row = find.byKey(const ValueKey('glossary-entry-custom:newer'));
        expect(
          find.descendant(of: row, matching: find.text('Newer version')),
          findsOneWidget,
        );
        expect(find.text('Needs repair'), findsNothing);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('glossary-custom-unsupported')),
          findsOneWidget,
        );
        final edit = tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('glossary-custom-edit')),
        );
        expect(edit.onPressed, isNull);
      });
    }
  });

  group('a custom figure\'s detail', () {
    testWidgets('shows its text, its parameters and, folded, what it '
        'expands to', (tester) async {
      await pump(tester, entries: [entry()]);
      await search(tester, 'grand right');
      await tester.tap(find.byKey(customRow));
      await tester.pumpAndSettle();

      expect(
        find.text('Pull by alternating hands around the ring.'),
        findsOneWidget,
      );
      expect(
        find.text('who (dancers), hand (hand)'),
        findsOneWidget,
        reason: 'the parameters with their kinds',
      );
      final panel = find.byKey(const ValueKey('glossary-custom-expands-to'));
      expect(panel, findsOneWidget);
      expect(find.text('Expands to (8 beats)'), findsOneWidget);
      // Folded until asked for (maintainer, #709).
      expect(find.text('neighbor pull by left'), findsNothing);
      await tester.tap(panel);
      await tester.pumpAndSettle();
      final rows = find.descendant(of: panel, matching: find.byType(ListTile));
      expect(
        [
          for (final row in tester.widgetList<ListTile>(rows).skip(1))
            (row.title! as Text).data,
        ],
        [
          'neighbor pull by right',
          'neighbor pull by left',
          'neighbor pull by right',
          'neighbor pull by left',
        ],
        reason: 'the authored arguments, the opposite on every other figure',
      );
    });

    testWidgets('its page title follows a rename made from it', (tester) async {
      await pump(tester, entries: [entry()]);
      await search(tester, 'grand right');
      await tester.tap(find.byKey(customRow));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('grand right and left'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('glossary-custom-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('compound-name')),
        'grand chain',
      );
      await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('grand chain'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('delete asks first, then deletes it softly', (tester) async {
      final h = await pump(tester, entries: [entry()]);
      await search(tester, 'grand right');
      await tester.tap(find.byKey(customRow));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('glossary-custom-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete “grand right and left”?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('glossary-custom-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(customRow), findsNothing);
      final all = await tester.runAsync(
        () => h.repos.userGlossary.listAll(includeDeleted: true),
      );
      expect(all!.single.id, 'grl', reason: 'a tombstone, for sync to carry');
      expect(
        await tester.runAsync(() => h.repos.userGlossary.getById('grl')),
        isNull,
      );
    });
  });

  group('notes on a built-in figure', () {
    testWidgets('are added, stored canonically and shown in the dialect', (
      tester,
    ) async {
      final h = await pump(tester);
      await search(tester, 'swing');
      await tester.tap(find.byKey(const ValueKey('glossary-entry-swing')));
      await tester.pumpAndSettle();

      expect(find.text('No notes yet.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('glossary-notes-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('glossary-notes-field')),
        'Larks finish on the left',
      );
      await tester.tap(find.byKey(const ValueKey('glossary-notes-save')));
      await tester.pumpAndSettle();

      final stored = await tester.runAsync(
        () => h.repos.figureNotes.get('swing'),
      );
      expect(stored!.notes, 'role1s finish on the left');
      // A stored role token reads back lowercase, as a custom figure's text
      // does (docs/design/dialect.md).
      expect(find.text('larks finish on the left'), findsOneWidget);
    });

    testWidgets('a note too long to store says so and is not saved', (
      tester,
    ) async {
      final h = await pump(tester);
      await search(tester, 'swing');
      await tester.tap(find.byKey(const ValueKey('glossary-entry-swing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary-notes-edit')));
      await tester.pumpAndSettle();
      // Within the field's limit as typed, over the stored bound once each
      // "Larks" is stored as "role1s".
      await tester.enterText(
        find.byKey(const ValueKey('glossary-notes-field')),
        'Larks ' * 3333,
      );
      await tester.tap(find.byKey(const ValueKey('glossary-notes-save')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Your notes are too long to save. Shorten them and try again.',
        ),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => h.repos.figureNotes.get('swing')),
        isNull,
      );
      // The dialog stays open on what was typed, so the text is not lost and
      // "shorten them" can be done in place.
      final field = find.byKey(const ValueKey('glossary-notes-field'));
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'Larks ' * 3333);
      await tester.enterText(field, 'Larks finish on the left');
      await tester.tap(find.byKey(const ValueKey('glossary-notes-save')));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(
        (await tester.runAsync(() => h.repos.figureNotes.get('swing')))!.notes,
        'role1s finish on the left',
      );
    });

    testWidgets('an unexpected failure to store leaves Save usable', (
      tester,
    ) async {
      final h = await pump(tester);
      // Not a refusal the repository reports: the write itself fails.
      await tester.runAsync(
        () => h.repos.db.customStatement(
          'CREATE TRIGGER notes_fail BEFORE INSERT ON figure_notes '
          "BEGIN SELECT RAISE(ABORT, 'boom'); END",
        ),
      );
      await search(tester, 'swing');
      await tester.tap(find.byKey(const ValueKey('glossary-entry-swing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary-notes-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('glossary-notes-field')),
        'Larks finish on the left',
      );
      // The failure escapes the button's callback, as an unexpected one does.
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        await tester.tap(find.byKey(const ValueKey('glossary-notes-save')));
        await tester.pumpAndSettle();
      }, (error, _) => uncaught.add(error));
      expect(uncaught, hasLength(1));
      final save = find.byKey(const ValueKey('glossary-notes-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      // And the retry goes through once the failure is gone.
      await tester.runAsync(
        () => h.repos.db.customStatement('DROP TRIGGER notes_fail'),
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(save, findsNothing);
      expect(
        (await tester.runAsync(() => h.repos.figureNotes.get('swing')))!.notes,
        'role1s finish on the left',
      );
    });

    testWidgets('a note the full Glossary has no room for says so, not that '
        'the note is too long', (tester) async {
      final h = await pump(tester);
      // Rows written before there was a budget, put there directly because
      // the repository would now refuse them.
      await tester.runAsync(
        () => h.repos.db.customStatement(
          'INSERT INTO user_glossary_entries '
          '(id, kind, name, definition, description, created_at) '
          "VALUES ('old', 'compound', 'old', 'd', "
          "replace(hex(zeroblob(${maxUserGlossaryBytes + 1024})), '00', 'x'), 0)",
        ),
      );
      await search(tester, 'swing');
      await tester.tap(find.byKey(const ValueKey('glossary-entry-swing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary-notes-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('glossary-notes-field')),
        'Larks finish on the left',
      );
      await tester.tap(find.byKey(const ValueKey('glossary-notes-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('has reached its size limit'), findsOneWidget);
      expect(find.textContaining('too long to save'), findsNothing);
      expect(
        await tester.runAsync(() => h.repos.figureNotes.get('swing')),
        isNull,
      );
      // Still open, with the text the user typed.
      final field = find.byKey(const ValueKey('glossary-notes-field'));
      expect(field, findsOneWidget);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Larks finish on the left',
      );
    });
  });
}
