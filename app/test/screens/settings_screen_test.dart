import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import '../support/test_repositories.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<({CompendiumRepositories repos, ValueNotifier<Dialect> notifier})>
_pumpSettings(WidgetTester tester, {Dialect? initialDialect}) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();

  final notifier = ValueNotifier<Dialect>(
    initialDialect ?? Dialect.larksRobins,
  );

  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(notifier.dispose);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return (repos: repos, notifier: notifier);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen — dialect selection', () {
    testWidgets('renders all preset names', (tester) async {
      await _pumpSettings(tester);

      for (final preset in Dialect.presets) {
        expect(
          find.byKey(ValueKey('dialect-${preset.name}')),
          findsOneWidget,
          reason: 'Expected radio tile for ${preset.name}',
        );
        expect(find.text(preset.name), findsOneWidget);
      }
    });

    testWidgets('default selection matches active dialect notifier', (
      tester,
    ) async {
      await _pumpSettings(tester, initialDialect: Dialect.larksRobins);

      // The Larks/Robins tile should be visible with the right value.
      final radio = tester.widget<RadioListTile<Dialect>>(
        find.byKey(ValueKey('dialect-${Dialect.larksRobins.name}')),
      );
      expect(radio.value, equals(Dialect.larksRobins));
    });

    testWidgets('selecting a preset updates the notifier live', (tester) async {
      final ctx = await _pumpSettings(
        tester,
        initialDialect: Dialect.larksRobins,
      );

      // Tap the Gents/Ladies radio tile.
      await tester.tap(
        find.byKey(ValueKey('dialect-${Dialect.gentsLadies.name}')),
      );
      await tester.pumpAndSettle();

      expect(ctx.notifier.value, equals(Dialect.gentsLadies));
    });

    testWidgets('selecting a preset persists to SettingsRepository', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialDialect: Dialect.larksRobins,
      );

      await tester.tap(
        find.byKey(ValueKey('dialect-${Dialect.leadsFollows.name}')),
      );
      await tester.pumpAndSettle();

      final stored = await ctx.repos.settings.get(kActiveDialectKey) as String?;
      expect(stored, equals(Dialect.leadsFollows.name));
    });

    testWidgets('round-trip: stored name is restored to correct preset', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      // Pre-set the stored value.
      await repos.settings.set(kActiveDialectKey, Dialect.gentsLadies.name);

      final name = await repos.settings.get(kActiveDialectKey) as String?;
      final preset = name != null ? Dialect.forName(name) : null;

      expect(preset, equals(Dialect.gentsLadies));
    });

    testWidgets('default-when-unset falls back to larksRobins', (tester) async {
      // Dialect.forName on a missing key → null → default larksRobins.
      final repos = openTestRepositories();
      await repos.ensureMigrated();

      final name = await repos.settings.get(kActiveDialectKey) as String?;
      final preset =
          (name != null ? Dialect.forName(name) : null) ?? Dialect.larksRobins;

      expect(preset, equals(Dialect.larksRobins));
    });
  });
}
