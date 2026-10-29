import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/tag_colors_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/color_edit_dialog.dart';

import '../support/fail_once_interceptor.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The tag-colour picker (issue #786), the surface that finally gives
/// `tags.color` a writer.
Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: const TagColorsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late CompendiumRepositories repos;

  setUp(() => repos = openTestRepositories());

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
    expect(find.byKey(const ValueKey('tag-color-t1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('load-error-retry')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load your tags."), findsNothing);
    expect(find.byKey(const ValueKey('tag-color-t1')), findsOneWidget);
  });

  testWidgets('lists every tag, colourless ones included', (tester) async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'chestnut'));
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'becket', color: 0xFF2196F3));

    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('tag-color-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-color-t2')), findsOneWidget);
  });

  testWidgets('offers a reset only for a tag that has a colour', (
    tester,
  ) async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'chestnut'));
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'becket', color: 0xFF2196F3));

    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('tag-color-reset-t1')), findsNothing);
    expect(find.byKey(const ValueKey('tag-color-reset-t2')), findsOneWidget);
  });

  testWidgets('picking a colour persists it, fully opaque', (tester) async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'chestnut'));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('tag-color-t1')));
    await tester.pumpAndSettle();
    expect(find.byType(ColorEditDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), '#2196F3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect((await repos.tags.getById('t1'))!.color, 0xFF2196F3);
  });

  testWidgets('resetting clears the colour rather than keeping it', (
    tester,
  ) async {
    // The trap: `copyWith(color: null)` cannot clear a colour, so a naive
    // reset would leave 0xFF2196F3 on disk while the row claimed no colour.
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFF2196F3));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('tag-color-reset-t1')));
    await tester.pumpAndSettle();

    expect((await repos.tags.getById('t1'))!.color, isNull);
    // The row updates in place, so the reset action disappears with it.
    expect(find.byKey(const ValueKey('tag-color-reset-t1')), findsNothing);
  });

  testWidgets('cancelling the picker leaves the colour untouched', (
    tester,
  ) async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFF2196F3));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('tag-color-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await repos.tags.getById('t1'))!.color, 0xFF2196F3);
  });

  testWidgets('explains itself when there are no tags yet', (tester) async {
    await _pump(tester, repos);
    expect(find.byKey(const ValueKey('tag-colours-empty')), findsOneWidget);
  });
}
