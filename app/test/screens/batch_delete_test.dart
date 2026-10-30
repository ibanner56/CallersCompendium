// Collection's batch Delete (N4-S3): one transaction, Confirm before delete,
// a counted snackbar with Undo, and a failure path.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/batch_screen_harness.dart';
import '../support/test_repositories.dart';

Dance _dance({required String id, required String title, String? levelId}) =>
    Dance(
      id: id,
      title: title,
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      difficultyLevelId: levelId,
      figures: const [],
      customFields: const [],
      hook: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _seed(CompendiumRepositories repos, {String? levelId}) async {
  await repos.dances.create(_dance(id: 'd1', title: 'Alpha', levelId: levelId));
  await repos.dances.create(_dance(id: 'd2', title: 'Bravo', levelId: levelId));
  await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
}

Future<void> _selectFirstTwo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-select')));
  await tester.pumpAndSettle();
  for (final id in ['d1', 'd2']) {
    await tester.tap(find.byKey(ValueKey('batch-checkbox-$id')));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapDelete(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('batch-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-delete')));
  await tester.pumpAndSettle();
}

Future<Set<String>> _liveIds(CompendiumRepositories repos) async => {
  for (final dance in await repos.dances.listAll()) dance.id,
};

void main() {
  testWidgets('with Confirm before delete off, deletes at once and Undo '
      'brings the dances back', (tester) async {
    final repos = openTestRepositories();
    await _seed(repos);
    await pumpBatchScreen(tester, repos);

    await _selectFirstTwo(tester);
    await _tapDelete(tester);

    expect(
      find.byKey(const ValueKey('confirm-delete-dialog')),
      findsNothing,
      reason: 'N4-4 = a: the setting is off, so no dialog',
    );
    expect(await _liveIds(repos), {'d3'});
    expect(find.text('Deleted 2 dances'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Bravo'), findsNothing);
    expect(find.text('Charlie'), findsOneWidget);
    // Selection mode has ended.
    expect(find.byKey(const ValueKey('batch-exit')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(await _liveIds(repos), {'d1', 'd2', 'd3'});
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
  });

  testWidgets('with Confirm before delete on, one dialog names the count', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seed(repos);
    await pumpBatchScreen(tester, repos, confirmBeforeDelete: true);

    await _selectFirstTwo(tester);
    await _tapDelete(tester);

    expect(find.byKey(const ValueKey('confirm-delete-dialog')), findsOneWidget);
    expect(
      find.text('2 dances will be deleted. You can undo this.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
    await tester.pumpAndSettle();
    expect(await _liveIds(repos), {'d1', 'd2', 'd3'});
    expect(
      find.byKey(const ValueKey('batch-exit')),
      findsOneWidget,
      reason: 'Cancel keeps the selection',
    );

    await _tapDelete(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confirm-delete-dialog')), findsNothing);
    expect(await _liveIds(repos), {'d3'});
    expect(find.text('Deleted 2 dances'), findsOneWidget);
  });

  testWidgets('Undo revives a level deleted while the dances were in the '
      'trash', (tester) async {
    final repos = openTestRepositories();
    final level = await repos.difficultyLevels.createCustom(
      label: 'Challenge',
      position: 9,
    );
    await _seed(repos, levelId: level.id);
    await pumpBatchScreen(tester, repos);

    await _selectFirstTwo(tester);
    await _tapDelete(tester);
    // B8: the trash does not protect the level, so it can go meanwhile.
    await tester.runAsync(
      () => repos.difficultyLevels.delete(level.id, at: DateTime.now().toUtc()),
    );
    expect(await repos.difficultyLevels.getById(level.id), isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(await _liveIds(repos), {'d1', 'd2', 'd3'});
    expect(await repos.difficultyLevels.getById(level.id), level);
  });

  testWidgets('a failure deletes nothing, says so, and keeps the selection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seed(repos);
    await pumpBatchScreen(tester, repos);
    await repos.db.customStatement(
      'CREATE TEMP TRIGGER fail_d2 BEFORE UPDATE OF deleted_at ON dances '
      "WHEN NEW.id = 'd2' AND NEW.deleted_at IS NOT NULL "
      "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );

    await _selectFirstTwo(tester);
    await _tapDelete(tester);

    expect(await _liveIds(repos), {'d1', 'd2', 'd3'});
    expect(
      find.byKey(const ValueKey('batch-apply-error-snackbar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('batch-exit')), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('Delete is last in the menu, after a divider', (tester) async {
    final repos = openTestRepositories();
    await _seed(repos);
    await pumpBatchScreen(tester, repos);

    await _selectFirstTwo(tester);
    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();

    final entries = tester
        .widgetList<PopupMenuEntry<Object?>>(
          find.byWidgetPredicate(
            (w) => w is PopupMenuItem || w is PopupMenuDivider,
          ),
        )
        .map(
          (w) =>
              w is PopupMenuItem ? (w.key as ValueKey<String>?)?.value : '---',
        )
        .toList();
    expect(entries.last, 'batch-delete');
    expect(entries[entries.length - 2], '---');
  });
}
