import 'dart:convert';

import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/tag_manager_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/color_edit_dialog.dart';
import 'package:compendium_app/src/widgets/tag_chip.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fail_once_interceptor.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The Tags manager (FIND-3, `docs/design/tags-and-people.md` T2), which took
/// over the tag-colour screen (issue #786) and adds rename, merge and delete.
Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: const TagManagerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Ids sort in this order, so the surviving id of a merge is easy to read.
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  const c = '00000000-0000-4000-8000-00000000000c';
  final t0 = DateTime.utc(2026, 10, 1);

  late CompendiumRepositories repos;

  setUp(() => repos = openTestRepositories());

  Future<void> tag(String id, String name, {int? color}) async {
    // ignore: unused_result
    await repos.tags.upsert(
      Tag(id: id, name: name, color: color),
      at: t0,
    );
  }

  Future<void> dance(String id, List<String> tags) => repos.dances.create(
    Dance(
      id: id,
      title: 'Dance $id',
      tagIds: tags,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  Future<List<Tag>> liveTags() => repos.tags.listAll();

  /// Opens [id]'s ⋮ menu and picks [action].
  Future<void> act(WidgetTester tester, String id, String action) async {
    await tester.tap(find.byKey(ValueKey('tag-actions-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tag-action-$action-$id')));
    await tester.pumpAndSettle();
  }

  Future<void> rename(WidgetTester tester, String id, String name) async {
    await act(tester, id, 'rename');
    await tester.enterText(
      find.byKey(const ValueKey('library-rename-field')),
      name,
    );
    await tester.tap(find.byKey(const ValueKey('library-rename-confirm')));
    await tester.pumpAndSettle();
  }

  Finder rowSubtitle(String id, String text) => find.descendant(
    of: find.byKey(ValueKey('tag-row-$id')),
    matching: find.text(text),
  );

  group('the list', () {
    testWidgets('a failed load offers Retry, and Retry loads the tags', (
      tester,
    ) async {
      final failer = FailOnceInterceptor('tags');
      final flaky = CompendiumRepositories(
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(failer),
        ),
        contraTaxonomy,
      );
      // ignore: unused_result
      await flaky.tags.upsert(Tag(id: 't1', name: 'chestnut'));
      failer.arm();

      await _pump(tester, flaky);

      expect(failer.fired, isTrue, reason: 'the injected failure must fire');
      expect(find.text("Couldn't load your tags."), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-row-t1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('load-error-retry')));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load your tags."), findsNothing);
      expect(find.byKey(const ValueKey('tag-row-t1')), findsOneWidget);
    });

    testWidgets('explains itself when there are no tags yet', (tester) async {
      await _pump(tester, repos);
      expect(find.byKey(const ValueKey('tag-empty')), findsOneWidget);
    });

    testWidgets('shows each tag as its chip, with its count of live dances', (
      tester,
    ) async {
      await tag(a, 'Bouncey', color: 0xFF2196F3);
      await tag(b, 'Flowy');
      await tag(c, 'Spare');
      await dance('one', [a, b]);
      await dance('two', [a]);
      await dance('trashed', [b]);
      await repos.dances.softDelete('trashed', at: t0);

      await _pump(tester, repos);

      expect(rowSubtitle(a, '2 dances'), findsOneWidget);
      expect(rowSubtitle(b, '1 dance'), findsOneWidget);
      expect(rowSubtitle(c, 'Not used'), findsOneWidget);
      final chip = tester.widget<TagChip>(
        find.descendant(
          of: find.byKey(const ValueKey('tag-row-$a')),
          matching: find.byType(TagChip),
        ),
      );
      expect(chip.color, 0xFF2196F3);
    });

    testWidgets('the count follows a dance into the trash', (tester) async {
      await tag(a, 'Bouncey');
      await dance('one', [a]);
      await _pump(tester, repos);
      expect(rowSubtitle(a, '1 dance'), findsOneWidget);

      await repos.dances.softDelete('one', at: t0);
      await tester.pumpAndSettle();

      expect(rowSubtitle(a, 'Not used'), findsOneWidget);
    });

    testWidgets('search, the Not used filter and the sort', (tester) async {
      await tag(a, 'Zesty');
      await tag(b, 'apple');
      await tag(c, 'Bouncey');
      await dance('one', [a]);
      await dance('two', [a, c]);

      await _pump(tester, repos);

      List<String> order() => [
        for (final element
            in find
                .byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'tag-row-',
                      ),
                )
                .evaluate())
          (element.widget.key! as ValueKey<String>).value.substring(8),
      ];

      expect(order(), [b, c, a], reason: 'by name, ignoring case');

      await tester.tap(find.byKey(const ValueKey('tag-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-sort-count')));
      await tester.pumpAndSettle();
      expect(order(), [a, c, b], reason: 'most-used first');

      await tester.tap(find.byKey(const ValueKey('tag-not-used')));
      await tester.pumpAndSettle();
      expect(order(), [b]);

      await tester.tap(find.byKey(const ValueKey('tag-not-used')));
      await tester.enterText(find.byKey(const ValueKey('tag-search')), 'BOUN');
      await tester.pumpAndSettle();
      expect(order(), [c]);

      await tester.enterText(find.byKey(const ValueKey('tag-search')), 'xyz');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-no-matches')), findsOneWidget);
    });

    testWidgets('tapping a row opens its actions as a sheet', (tester) async {
      await tag(a, 'Bouncey');
      await _pump(tester, repos);

      await tester.tap(find.byKey(const ValueKey('tag-row-$a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-action-delete-$a')));
      await tester.pumpAndSettle();

      expect(await liveTags(), isEmpty);
    });
  });

  group('rename', () {
    testWidgets('writes the new name, and Undo puts the old one back', (
      tester,
    ) async {
      await tag(a, 'Flowing');
      await _pump(tester, repos);

      await rename(tester, a, 'Flowy');

      expect((await repos.tags.getById(a))!.name, 'Flowy');
      expect(find.text('Renamed “Flowing” to “Flowy”'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-manager-undo')));
      await tester.pumpAndSettle();

      expect((await repos.tags.getById(a))!.name, 'Flowing');
    });

    testWidgets('onto an existing name offers a merge, and Merge leaves one '
        'entry', (tester) async {
      await tag(a, 'Flowing', color: 0xFF00FF00);
      await tag(b, 'Flowy');
      await dance('one', [a]);
      await dance('two', [b]);
      await _pump(tester, repos);

      await rename(tester, a, 'flowy');

      expect(find.byKey(const ValueKey('library-merge-offer')), findsOneWidget);
      expect(
        find.text('“Flowy” already exists. Merge “Flowing” into it?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('library-merge-offer-merge')));
      await tester.pumpAndSettle();

      final tags = await liveTags();
      expect(tags, hasLength(1));
      expect(tags.single.id, a, reason: 'the smaller id survives');
      expect(tags.single.name, 'flowy', reason: 'under the typed name');
      expect(find.byKey(const ValueKey('tag-row-$b')), findsNothing);
      expect(rowSubtitle(a, '2 dances'), findsOneWidget);
    });

    testWidgets('Keep editing merges nothing', (tester) async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await _pump(tester, repos);

      await rename(tester, a, 'Flowy');
      await tester.tap(
        find.byKey(const ValueKey('library-merge-offer-keep-editing')),
      );
      await tester.pumpAndSettle();

      expect((await liveTags()).map((t) => t.name), ['Flowing', 'Flowy']);
    });

    testWidgets('onto a name two case variants hold asks which to merge into, '
        'preselecting the exact bytes', (tester) async {
      await tag(a, 'flowy');
      await tag(b, 'Flowy', color: 0xFFFF0000);
      await tag(c, 'Flowing');
      await _pump(tester, repos);

      await rename(tester, c, 'Flowy');

      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        b,
      );
      await tester.tap(find.byKey(const ValueKey('library-merge-offer-merge')));
      await tester.pumpAndSettle();

      final tags = await liveTags();
      expect(tags, hasLength(1));
      expect(tags.single.name, 'Flowy');
      expect(tags.single.color, 0xFFFF0000, reason: "the chosen tag's colour");
      expect(find.text('Combined 3 tags into “Flowy”'), findsOneWidget);
    });
  });

  group('merge into', () {
    testWidgets('the picker lists the other tags, and the merge keeps the '
        'chosen name; Undo splits them again', (tester) async {
      await tag(a, 'Flowy');
      await tag(b, 'Flowing');
      await tag(c, 'Bouncey');
      await dance('one', [b]);
      await _pump(tester, repos);

      await act(tester, b, 'merge');
      expect(
        find.byKey(const ValueKey('library-merge-into-$b')),
        findsNothing,
        reason: 'a tag cannot be merged into itself',
      );
      await tester.enterText(
        find.byKey(const ValueKey('library-merge-search')),
        'flo',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-merge-into-$c')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('library-merge-into-$a')));
      await tester.pumpAndSettle();

      expect((await liveTags()).map((t) => t.name), ['Bouncey', 'Flowy']);
      expect((await repos.dances.getById('one'))!.tagIds, [a]);
      expect(find.text('Merged “Flowing” into “Flowy”'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-manager-undo')));
      await tester.pumpAndSettle();

      expect((await liveTags()).map((t) => t.name), [
        'Bouncey',
        'Flowing',
        'Flowy',
      ]);
      expect((await repos.dances.getById('one'))!.tagIds, [b]);
    });

    testWidgets('a merge rewrites the import tags and keeps one', (
      tester,
    ) async {
      await tag(a, 'Flowy');
      await tag(b, 'Flowing');
      await repos.settings.set(
        kDefaultImportTagNamesKey,
        encodeDefaultImportTagNames(['Flowing', 'Flowy']),
      );
      await _pump(tester, repos);

      await act(tester, b, 'merge');
      await tester.tap(find.byKey(const ValueKey('library-merge-into-$a')));
      await tester.pumpAndSettle();

      // Raw, because the decoder drops duplicates itself.
      expect(
        jsonDecode(
          await repos.settings.get(kDefaultImportTagNamesKey) as String,
        ),
        ['Flowy'],
      );
    });
  });

  group('delete', () {
    testWidgets('asks nothing, and reports the live dances it changed', (
      tester,
    ) async {
      await tag(a, 'Bouncey');
      await dance('one', [a]);
      await dance('two', [a]);
      await dance('trashed', [a]);
      await repos.dances.softDelete('trashed', at: t0);
      await _pump(tester, repos);

      await act(tester, a, 'delete');

      expect(find.byType(AlertDialog), findsNothing, reason: 'Undo exists');
      expect(await liveTags(), isEmpty);
      expect(find.text('Deleted “Bouncey” from 2 dances'), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-row-$a')), findsNothing);
    });

    testWidgets('Undo restores the dances and the import-tags name', (
      tester,
    ) async {
      await tag(a, 'Bouncey');
      await tag(b, 'Easy');
      await dance('one', [a, b]);
      await repos.settings.set(
        kDefaultImportTagNamesKey,
        encodeDefaultImportTagNames(['Bouncey', 'Easy']),
      );
      await _pump(tester, repos);

      await act(tester, a, 'delete');
      expect((await repos.dances.getById('one'))!.tagIds, [b]);
      expect(
        tryDecodeDefaultImportTagNames(
          await repos.settings.get(kDefaultImportTagNamesKey),
        ),
        ['Easy'],
      );

      await tester.tap(find.byKey(const ValueKey('tag-manager-undo')));
      await tester.pumpAndSettle();

      expect((await repos.dances.getById('one'))!.tagIds.toSet(), {a, b});
      expect(
        tryDecodeDefaultImportTagNames(
          await repos.settings.get(kDefaultImportTagNamesKey),
        ),
        ['Bouncey', 'Easy'],
      );
      expect(rowSubtitle(a, '1 dance'), findsOneWidget);
    });

    testWidgets('an Undo whose name has been taken since says so', (
      tester,
    ) async {
      await tag(a, 'Bouncey');
      await _pump(tester, repos);

      await act(tester, a, 'delete');
      // Another tag takes the name before Undo. A case variant, because
      // re-creating the exact bytes would adopt the deleted tag's row.
      await tag(b, 'BOUNCEY');
      await tester.tap(find.byKey(const ValueKey('tag-manager-undo')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('tag-manager-undo-conflict')),
        findsOneWidget,
      );
      expect((await liveTags()).map((t) => t.id), [b]);
    });
  });

  group('colour', () {
    testWidgets('offers Remove colour only for a tag that has one', (
      tester,
    ) async {
      await tag(a, 'chestnut');
      await tag(b, 'becket', color: 0xFF2196F3);
      await _pump(tester, repos);

      await tester.tap(find.byKey(const ValueKey('tag-actions-$a')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tag-action-remove-colour-$a')),
        findsNothing,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await act(tester, b, 'remove-colour');
      // The trap: `copyWith(color: null)` cannot clear a colour, so a naive
      // reset would leave 0xFF2196F3 on disk while the row claimed none.
      expect((await repos.tags.getById(b))!.color, isNull);
    });

    testWidgets('picking a colour persists it, fully opaque', (tester) async {
      await tag(a, 'chestnut');
      await _pump(tester, repos);

      await act(tester, a, 'colour');
      expect(find.byType(ColorEditDialog), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(ColorEditDialog),
          matching: find.byType(TextField),
        ),
        '#2196F3',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect((await repos.tags.getById(a))!.color, 0xFF2196F3);
    });

    testWidgets('cancelling the picker leaves the colour untouched', (
      tester,
    ) async {
      await tag(a, 'chestnut', color: 0xFF2196F3);
      await _pump(tester, repos);

      await act(tester, a, 'colour');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect((await repos.tags.getById(a))!.color, 0xFF2196F3);
    });
  });
}
