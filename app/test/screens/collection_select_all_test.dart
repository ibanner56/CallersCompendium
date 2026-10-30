import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/batch_screen_harness.dart';
import '../support/test_repositories.dart';

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<CompendiumRepositories> _seed(WidgetTester tester) async {
  final repos = openTestRepositories();
  await repos.dances.create(_dance('d1', 'Alpha'));
  await repos.dances.create(_dance('d2', 'Bravo'));
  await repos.dances.create(_dance('d3', 'Charlie'));
  await pumpBatchScreen(tester, repos);
  return repos;
}

Future<void> _longPress(WidgetTester tester, String title) async {
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('collection-search-field')),
    text,
  );
  await tester.pumpAndSettle();
}

final _selectAll = find.byKey(const ValueKey('batch-select-all'));

void main() {
  testWidgets('Select all selects every result and toggles to Deselect all', (
    tester,
  ) async {
    await _seed(tester);
    await _longPress(tester, 'Alpha');
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('Select all 3'), findsOneWidget);

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.byTooltip('Deselect all 3'), findsOneWidget);

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byTooltip('Select all 3'), findsOneWidget);
  });

  testWidgets('a search that hides a selected row keeps it and counts it', (
    tester,
  ) async {
    await _seed(tester);
    await _longPress(tester, 'Alpha');
    await _search(tester, 'Bravo');

    expect(find.text('1 selected'), findsOneWidget);
    expect(
      find.text('1 dance · 1 selected (1 not shown)'),
      findsOneWidget,
      reason: 'Alpha is selected but the list shows only Bravo',
    );

    await tester.tap(find.byKey(const ValueKey('batch-deselect-not-shown')));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('batch-deselect-not-shown')),
      findsNothing,
    );
  });

  testWidgets('Select all takes the results only and keeps hidden picks', (
    tester,
  ) async {
    await _seed(tester);
    await _longPress(tester, 'Alpha');
    await _search(tester, 'Bravo');

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.textContaining('(1 not shown)'), findsOneWidget);

    // Deselect all clears the shown rows only.
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('Select all is disabled while a search is pending', (
    tester,
  ) async {
    await _seed(tester);
    await _longPress(tester, 'Alpha');
    await tester.enterText(
      find.byKey(const ValueKey('collection-search-field')),
      'Bravo',
    );
    // Inside the debounce window: the list is about to be replaced.
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.widget<IconButton>(_selectAll).onPressed, isNull);

    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(_selectAll).onPressed, isNotNull);
  });

  testWidgets('a dance that no longer exists leaves the selection', (
    tester,
  ) async {
    final repos = await _seed(tester);
    await _longPress(tester, 'Alpha');
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);

    await repos.dances.softDelete('d2', at: DateTime.utc(2026, 2, 1));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('turning online search on ends selection mode', (tester) async {
    await _seed(tester);
    await _longPress(tester, 'Alpha');
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('online-search-enable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('batch-exit')), findsNothing);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('on a phone width Select all moves into the ⋮ menu', (
    tester,
  ) async {
    await _seed(tester);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    await _longPress(tester, 'Alpha');
    expect(_selectAll, findsNothing);

    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-select-all-menu')));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
  });

  testWidgets('the menu opens on an empty selection for Select all', (
    tester,
  ) async {
    await _seed(tester);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    await _longPress(tester, 'Alpha');
    await tester.tap(find.byKey(const ValueKey('batch-checkbox-d1')));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('batch-select-all-menu')), findsOneWidget);
    final rating = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const ValueKey('batch-set-rating')),
    );
    expect(rating.enabled, isFalse);
  });
}
