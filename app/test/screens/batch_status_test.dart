import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';
import '../support/batch_screen_harness.dart';

Dance _dance({
  required String id,
  required String title,
  DanceStatus status = DanceStatus.active,
}) => Dance(
  id: id,
  title: title,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: status,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _enterSelectionMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-select')));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String danceId) async {
  await tester.tap(find.byKey(ValueKey('batch-checkbox-$danceId')));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('batch-more')));
  await tester.pumpAndSettle();
}

Future<void> _setStatus(WidgetTester tester, DanceStatus status) async {
  await _openMenu(tester);
  await tester.tap(find.byKey(const ValueKey('batch-set-status')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('batch-status-option-${status.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-status-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('set-status applies the chosen status to the selected dances', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setStatus(tester, DanceStatus.deprecated);

    expect((await repos.dances.getById('d1'))!.status, DanceStatus.deprecated);
    expect((await repos.dances.getById('d2'))!.status, DanceStatus.deprecated);
    expect((await repos.dances.getById('d3'))!.status, DanceStatus.active);
    expect(find.text('Set status on 2 dances'), findsOneWidget);
  });

  testWidgets('only changed dances are stamped, and Undo restores each prior', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', status: DanceStatus.broken),
    );
    await repos.dances.create(
      _dance(id: 'd2', title: 'Bravo', status: DanceStatus.draft),
    );
    await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
    final alreadyThere = (await repos.dances.getById('d1'))!.updatedAt;
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _toggle(tester, 'd3');
    await _setStatus(tester, DanceStatus.broken);

    // d1 already matched: not counted, not re-stamped.
    expect(find.text('Set status on 2 dances'), findsOneWidget);
    expect((await repos.dances.getById('d1'))!.updatedAt, alreadyThere);
    expect((await repos.dances.getById('d2'))!.status, DanceStatus.broken);
    expect((await repos.dances.getById('d3'))!.status, DanceStatus.broken);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.status, DanceStatus.broken);
    expect((await repos.dances.getById('d1'))!.updatedAt, alreadyThere);
    expect((await repos.dances.getById('d2'))!.status, DanceStatus.draft);
    expect((await repos.dances.getById('d3'))!.status, DanceStatus.active);
  });

  testWidgets('says "No changes" when every dance already has the status', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setStatus(tester, DanceStatus.active);

    expect(find.text('No changes'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('cancelling the status dialog changes nothing', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('batch-set-status')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('batch-status-confirm')),
          )
          .onPressed,
      isNull,
      reason: 'confirm stays disabled until a status is picked',
    );
    await tester.tap(find.byKey(const ValueKey('batch-status-cancel')));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.status, DanceStatus.active);
  });

  testWidgets(
    'the menu is grouped Details / Other, with no mixer or mixed level',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);

      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _openMenu(tester);

      // N4-5's note: "but not mixer or mixed level". The exact list is pinned
      // so a re-added entry fails here, in the order the groups set.
      final entries = tester
          .widgetList<PopupMenuEntry<Object?>>(
            find.byWidgetPredicate(
              (w) => w is PopupMenuItem || w is PopupMenuDivider,
            ),
          )
          .map(
            (w) => w is PopupMenuItem
                ? (w.key as ValueKey<String>?)?.value
                : '---',
          )
          .toList();
      final menuKeys = entries.whereType<String>().toList();
      expect(menuKeys.where((k) => k != '---'), [
        if (menuKeys.contains('batch-select-all-menu')) 'batch-select-all-menu',
        'batch-set-rating',
        'batch-set-status',
        'batch-add-tunes',
        'batch-clear-tunes',
        'batch-edit-custom-field',
      ]);
      final details = menuKeys.indexOf('batch-set-status');
      final other = menuKeys.indexOf('batch-add-tunes');
      expect(
        menuKeys.sublist(details, other),
        contains('---'),
        reason: 'a divider separates Details from Other',
      );
      expect(find.textContaining('ixer'), findsNothing);
      expect(find.textContaining('ixed level'), findsNothing);
    },
  );

  testWidgets('the grouped menu stays usable at 320 x 568 and 2x text', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await pumpBatchScreen(tester, repos);
    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await _openMenu(tester);

    // The menu scrolls rather than overflowing: bring Status into view and use
    // it.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('batch-set-status')),
      50,
      scrollable: find
          .ancestor(
            of: find.byKey(const ValueKey('batch-set-status')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('batch-set-status')));
    await tester.pumpAndSettle();
    final thrown = tester.takeException();
    expect(find.byKey(const ValueKey('batch-status-dialog')), findsOneWidget);
    expect(thrown, isNull);
  });
}
