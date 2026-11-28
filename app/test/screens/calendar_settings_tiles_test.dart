import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings/calendar_settings_tiles.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Settings ▸ Calendar's own tiles. The import and startup behaviour they
/// configure is covered by the calendar import and startup tests.
void main() {
  Future<void> pumpTiles(
    WidgetTester tester,
    CompendiumRepositories repos,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            RepositoriesScope(repositories: repos, child: child!),
        home: const Scaffold(
          body: SingleChildScrollView(child: CalendarSettingsTiles()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the title filter dialog saves the filter, trimmed', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await pumpTiles(tester, repos);
    final tile = find.byKey(const ValueKey('calendar-settings-filter'));
    expect(
      find.descendant(of: tile, matching: find.text('Every event')),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calendar-settings-filter-field')),
      '  contra  ',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-settings-save')));
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kCalendarImportTitleFilterKey), 'contra');
    expect(
      find.descendant(of: tile, matching: find.text('"contra"')),
      findsOneWidget,
    );
  });
}
