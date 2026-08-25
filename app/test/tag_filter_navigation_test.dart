import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_scope.dart';
import 'package:compendium_app/src/update/update_service.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

Dance _dance({
  required String id,
  required String title,
  List<String> tagIds = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: tagIds,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _pumpShell(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  addTearDown(theme.dispose);
  final requirePerformed = ValueNotifier<bool>(false);
  addTearDown(requirePerformed.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  final updateController = UpdateController(
    repos.settings,
    service: UpdateService(fetcher: (_, {client}) async => null),
  );
  addTearDown(updateController.dispose);
  final filterController = CollectionFilterController();
  addTearDown(filterController.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: UpdateScope(
          controller: updateController,
          child: AppThemeScope(
            notifier: theme,
            child: CustomThemesScope(
              controller: customThemes,
              child: ActiveDialectScope(
                notifier: dialect,
                child: RequirePerformedForHistoryScope(
                  notifier: requirePerformed,
                  // Wired above the root navigator (as in main.dart) so a tag
                  // chip on a pushed detail route can reach it.
                  child: CollectionFilterScope(
                    controller: filterController,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      home: const AppShell(),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _listedTitles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

Future<void> _openDetail(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

/// The tag chip *inside the detail view* (scoped so it never matches the
/// still-mounted list rows, whose chips share the same id-based key).
Finder _detailTagChip(String tagId) => find.descendant(
  of: find.byType(DanceDetailScreen),
  matching: find.byKey(ValueKey('tag-filter-chip-$tagId')),
);

Future<void> _tapDetailTagChip(WidgetTester tester, String tagId) async {
  final chip = _detailTagChip(tagId);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'narrow: tapping a tag on a pushed dance detail pops back and filters '
    'the Collection to that tag',
    (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't2', name: 'energetic'));
      await repos.dances.create(
        _dance(id: 'd1', title: 'Smooth One', tagIds: const ['t1']),
      );
      await repos.dances.create(
        _dance(id: 'd2', title: 'Smooth Two', tagIds: const ['t1']),
      );
      await repos.dances.create(
        _dance(id: 'd3', title: 'Energetic Three', tagIds: const ['t2']),
      );

      await _pumpShell(tester, repos, size: const Size(500, 1400));

      expect(_listedTitles(tester).toSet(), {
        'Smooth One',
        'Smooth Two',
        'Energetic Three',
      });

      await _openDetail(tester, 'Smooth One');
      expect(find.byType(DanceDetailScreen), findsOneWidget);
      await _tapDetailTagChip(tester, 't1');

      // Popped back to the Collection list, filtered to 'smooth'.
      expect(find.byType(DanceDetailScreen), findsNothing);
      expect(_listedTitles(tester).toSet(), {'Smooth One', 'Smooth Two'});
      expect(find.text('Filters (1 active)'), findsOneWidget);
    },
  );

  testWidgets(
    'wide: tapping a tag in the embedded detail pane filters the list pane',
    (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't2', name: 'energetic'));
      await repos.dances.create(
        _dance(id: 'd1', title: 'Smooth One', tagIds: const ['t1']),
      );
      await repos.dances.create(
        _dance(id: 'd2', title: 'Smooth Two', tagIds: const ['t1']),
      );
      await repos.dances.create(
        _dance(id: 'd3', title: 'Energetic Three', tagIds: const ['t2']),
      );

      await _pumpShell(tester, repos, size: const Size(1300, 1400));

      await _openDetail(tester, 'Smooth One');
      expect(find.byType(DanceDetailScreen), findsOneWidget);
      await _tapDetailTagChip(tester, 't1');

      // List pane is filtered; the detail pane still shows the selected dance.
      expect(_listedTitles(tester).toSet(), {'Smooth One', 'Smooth Two'});
      expect(find.text('Filters (1 active)'), findsOneWidget);
    },
  );

  testWidgets('the tag filter is clearable, restoring the full list', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await repos.dances.create(
      _dance(id: 'd1', title: 'Smooth One', tagIds: const ['t1']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Untagged Two'));

    await _pumpShell(tester, repos, size: const Size(500, 1400));

    await _openDetail(tester, 'Smooth One');
    await _tapDetailTagChip(tester, 't1');
    expect(_listedTitles(tester), ['Smooth One']);

    // Open the Filters panel and clear — the full list returns.
    await tester.tap(find.byKey(const ValueKey('filters-panel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-filters')));
    await tester.pumpAndSettle();
    expect(_listedTitles(tester).toSet(), {'Smooth One', 'Untagged Two'});
  });

  testWidgets('filtering by a tag with no other dances shows only that dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'unique'));
    await repos.dances.create(
      _dance(id: 'd1', title: 'Lonely Dance', tagIds: const ['t1']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Other Dance'));

    await _pumpShell(tester, repos, size: const Size(500, 1400));

    await _openDetail(tester, 'Lonely Dance');
    await _tapDetailTagChip(tester, 't1');

    expect(_listedTitles(tester), ['Lonely Dance']);
    expect(find.text('1 dance'), findsOneWidget);
  });

  testWidgets(
    'a tag whose name has special characters filters by id, not by text',
    (tester) async {
      const trickyName = "O'Neil & <b> 50% \"quote\"";
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: trickyName));
      await repos.dances.create(
        _dance(id: 'd1', title: 'Tagged Dance', tagIds: const ['t1']),
      );
      await repos.dances.create(_dance(id: 'd2', title: 'Plain Dance'));

      await _pumpShell(tester, repos, size: const Size(500, 1400));

      await _openDetail(tester, 'Tagged Dance');
      // The chip renders the special-character name literally.
      expect(
        find.descendant(
          of: find.byType(DanceDetailScreen),
          matching: find.text(trickyName),
        ),
        findsOneWidget,
      );
      await _tapDetailTagChip(tester, 't1');

      expect(_listedTitles(tester), ['Tagged Dance']);
    },
  );

  testWidgets('tapping a tag chip on a list row filters in place', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await repos.dances.create(
      _dance(id: 'd1', title: 'Smooth One', tagIds: const ['t1']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Untagged Two'));

    // Wide layout keeps the list pane visible while filtering.
    await _pumpShell(tester, repos, size: const Size(1300, 1400));

    expect(_listedTitles(tester).toSet(), {'Smooth One', 'Untagged Two'});
    final rowChip = find.descendant(
      of: find.byType(DanceListTile),
      matching: find.byKey(const ValueKey('tag-filter-chip-t1')),
    );
    await tester.tap(rowChip.first);
    await tester.pumpAndSettle();
    expect(_listedTitles(tester), ['Smooth One']);
  });
}
