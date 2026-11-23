// Settings ▸ Program ▸ Perform mode ▸ Swap a dance (#2346).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/screens/settings/perform_swap_defaults_screen.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

Future<CompendiumRepositories> _pump(
  WidgetTester tester, {
  Object? stored,
}) async {
  final repos = openTestRepositories();
  if (stored != null) {
    await repos.settings.set(kPerformSwapDefaultsKey, stored);
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const PerformSwapDefaultsScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return repos;
}

Finder _switch(PerformSwapKeepItem item) =>
    find.byKey(ValueKey('perform-swap-default-${item.name}'));

bool _on(WidgetTester tester, PerformSwapKeepItem item) =>
    tester.widget<SwitchListTile>(_switch(item)).value;

void main() {
  testWidgets('every item starts on, and turning one off stores it', (
    tester,
  ) async {
    final repos = await _pump(tester);
    for (final item in PerformSwapKeepItem.values) {
      expect(_on(tester, item), isTrue, reason: item.name);
    }
    expect(find.text('Same formation'), findsOneWidget);
    expect(find.text('This level or easier'), findsOneWidget);
    expect(find.text('Same type'), findsOneWidget);
    expect(find.text("Not already in tonight's program"), findsOneWidget);

    await tester.tap(_switch(PerformSwapKeepItem.levelOrEasier));
    await tester.pumpAndSettle();
    expect(_on(tester, PerformSwapKeepItem.levelOrEasier), isFalse);
    final stored = readPerformSwapDefaults(
      await repos.settings.get(kPerformSwapDefaultsKey),
    );
    expect(stored.isNewer, isFalse);
    expect(stored.defaults.levelOrEasier, isFalse);
    expect(stored.defaults.formation, isTrue);
  });

  testWidgets('a stored value shows as stored, and an edit keeps what this '
      'build does not know', (tester) async {
    final repos = await _pump(
      tester,
      stored: {
        'version': 1,
        'keep': {'sameType': false, 'laterItem': true},
      },
    );
    expect(_on(tester, PerformSwapKeepItem.sameType), isFalse);
    await tester.tap(_switch(PerformSwapKeepItem.formation));
    await tester.pumpAndSettle();
    final stored = await repos.settings.get(kPerformSwapDefaultsKey);
    expect((stored! as Map)['keep'], {
      'laterItem': true,
      'formation': false,
      'levelOrEasier': true,
      'sameType': false,
      'notInProgram': true,
    });
  });

  testWidgets('a value from a newer version is shown read-only and never '
      'overwritten', (tester) async {
    const newer = {
      'version': 2,
      'keep': {'formation': false},
    };
    final repos = await _pump(tester, stored: newer);
    expect(
      find.byKey(const ValueKey('perform-swap-defaults-newer')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SwitchListTile>(_switch(PerformSwapKeepItem.formation))
          .onChanged,
      isNull,
    );
    await tester.tap(_switch(PerformSwapKeepItem.formation));
    await tester.pumpAndSettle();
    expect(await repos.settings.get(kPerformSwapDefaultsKey), newer);
  });
}
