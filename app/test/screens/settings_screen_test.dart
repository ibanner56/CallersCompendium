import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/canonical_discouraged_terms_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/data/track_history_for_all_callers_scope.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_scope.dart';
import 'package:compendium_app/src/widgets/section_header.dart';

import '../support/controllable_sync_transport.dart';
import '../support/noop_sync_transport.dart';
import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final class _SyncNetwork implements SyncNetworkClassifier {
  SyncNetworkKind kind = SyncNetworkKind.unmetered;
  @override
  Future<SyncNetworkKind> current() async => kind;
}

final _syncNetwork = _SyncNetwork();
SyncCoordinator? _syncCoordinator;
SyncPairingProbeFactory? _pairingProbeFactory;

Future<
  ({
    CompendiumRepositories repos,
    ValueNotifier<Dialect> notifier,
    DialectLibraryController dialectLibrary,
    ValueNotifier<AppThemeSelection> themeNotifier,
    CustomThemesController customThemes,
    ValueNotifier<bool> requirePerformedNotifier,
    ValueNotifier<bool> sortIgnoreArticlesNotifier,
    ValueNotifier<bool> trackHistoryForAllCallersNotifier,
  })
>
_pumpSettings(
  WidgetTester tester, {
  Dialect? initialDialect,
  AppThemeSelection? initialTheme,
  bool initialRequirePerformed = false,
  bool initialSortIgnoreArticles = true,
  bool initialTrackHistoryForAllCallers = false,
  Size surfaceSize = const Size(1000, 2600),
  BackupSaver? backupSaver,
}) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();

  // The dialect library owns dialect state; the notifier read by
  // ActiveDialectScope consumers is driven from it (mirroring main.dart).
  final dialectLibrary = DialectLibraryController(repos.settings);
  await dialectLibrary.load();
  if (initialDialect != null) {
    if (dialectLibrary.isPreset(initialDialect.name)) {
      await dialectLibrary.setActive(initialDialect.name);
    } else {
      await dialectLibrary.upsert(initialDialect);
      await dialectLibrary.setActive(initialDialect.name);
    }
  }
  final notifier = ValueNotifier<Dialect>(dialectLibrary.active);
  void syncDialect() => notifier.value = dialectLibrary.active;
  dialectLibrary.addListener(syncDialect);

  final themeNotifier = ValueNotifier<AppThemeSelection>(
    initialTheme ?? AppThemeSelection.system,
  );
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  final shorthandMappings = ShorthandMappingsController(repos.settings);
  await shorthandMappings.load();
  final walkthroughSnippets = WalkthroughSnippetLibraryController(
    repos.settings,
  );
  await walkthroughSnippets.load();
  final requirePerformedNotifier = ValueNotifier<bool>(initialRequirePerformed);
  final sortIgnoreArticlesNotifier = ValueNotifier<bool>(
    initialSortIgnoreArticles,
  );
  final trackHistoryForAllCallersNotifier = ValueNotifier<bool>(
    initialTrackHistoryForAllCallers,
  );
  final canonicalDiscouragedTermsNotifier = ValueNotifier<bool>(true);
  final updateController = UpdateController(repos.settings);
  await updateController.load();
  final syncController = SyncController(
    settings: repos.settings,
    coordinator: () => _syncCoordinator,
    reconfigure: () async {},
    endpoint: Uri.parse('https://sync.example.test'),
    pairingProbeFactory: _pairingProbeFactory,
    classifier: _syncNetwork,
  );
  await syncController.load();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(notifier.dispose);
  addTearDown(() {
    dialectLibrary.removeListener(syncDialect);
    dialectLibrary.dispose();
  });
  addTearDown(themeNotifier.dispose);
  addTearDown(customThemes.dispose);
  addTearDown(shorthandMappings.dispose);
  addTearDown(walkthroughSnippets.dispose);
  addTearDown(requirePerformedNotifier.dispose);
  addTearDown(sortIgnoreArticlesNotifier.dispose);
  addTearDown(trackHistoryForAllCallersNotifier.dispose);
  addTearDown(canonicalDiscouragedTermsNotifier.dispose);
  addTearDown(updateController.dispose);
  addTearDown(syncController.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: CustomThemesScope(
            controller: customThemes,
            child: DialectLibraryScope(
              controller: dialectLibrary,
              child: ActiveDialectScope(
                notifier: notifier,
                child: RequirePerformedForHistoryScope(
                  notifier: requirePerformedNotifier,
                  child: TrackHistoryForAllCallersScope(
                    notifier: trackHistoryForAllCallersNotifier,
                    child: CanonicalDiscouragedTermsScope(
                      notifier: canonicalDiscouragedTermsNotifier,
                      child: SortIgnoreArticlesScope(
                        notifier: sortIgnoreArticlesNotifier,
                        child: UpdateScope(
                          controller: updateController,
                          child: SyncScope(
                            controller: syncController,
                            child: ShorthandMappingsScope(
                              controller: shorthandMappings,
                              child: WalkthroughSnippetLibraryScope(
                                controller: walkthroughSnippets,
                                child: child!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      home: SettingsScreen(backupSaver: backupSaver),
    ),
  );
  await tester.pumpAndSettle();
  return (
    repos: repos,
    notifier: notifier,
    dialectLibrary: dialectLibrary,
    themeNotifier: themeNotifier,
    customThemes: customThemes,
    requirePerformedNotifier: requirePerformedNotifier,
    sortIgnoreArticlesNotifier: sortIgnoreArticlesNotifier,
    trackHistoryForAllCallersNotifier: trackHistoryForAllCallersNotifier,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen — General & Program settings (G.2)', () {
    // Section content only shows once its sidebar entry is picked (side-by-side
    // layout shows only the selected section). The calling-history toggles moved
    // to the Program section (issue #935); sort-ignore stays under General.
    Future<void> openGeneral(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
      await tester.pumpAndSettle();
    }

    Future<void> openProgram(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('settings-nav-program')));
      await tester.pumpAndSettle();
    }

    const toggleKey = ValueKey('general-require-performed-for-history');

    testWidgets('require-performed toggle is present and off by default', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openProgram(tester);

      expect(find.byKey(toggleKey), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byKey(toggleKey));
      expect(toggle.value, isFalse);
    });

    testWidgets('reflects the initial setting value', (tester) async {
      await _pumpSettings(tester, initialRequirePerformed: true);
      await openProgram(tester);

      final toggle = tester.widget<SwitchListTile>(find.byKey(toggleKey));
      expect(toggle.value, isTrue);
    });

    testWidgets('turning it on updates the notifier and persists the setting', (
      tester,
    ) async {
      final harness = await _pumpSettings(tester);
      await openProgram(tester);

      await tester.tap(find.byKey(toggleKey));
      await tester.pumpAndSettle();

      expect(harness.requirePerformedNotifier.value, isTrue);
      expect(
        await harness.repos.settings.get(kRequirePerformedForHistoryKey),
        isTrue,
      );
      final toggle = tester.widget<SwitchListTile>(find.byKey(toggleKey));
      expect(toggle.value, isTrue);
    });

    testWidgets(
      'turning it off updates the notifier and persists the setting',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          initialRequirePerformed: true,
        );
        await openProgram(tester);

        await tester.tap(find.byKey(toggleKey));
        await tester.pumpAndSettle();

        expect(harness.requirePerformedNotifier.value, isFalse);
        expect(
          await harness.repos.settings.get(kRequirePerformedForHistoryKey),
          isFalse,
        );
      },
    );

    testWidgets('the toggle exposes accessible switch semantics', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openProgram(tester);

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byKey(toggleKey),
            matching: find.byType(Switch),
          ),
        ),
        isSemantics(
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });

    const trackAllCallersKey = ValueKey(
      'general-track-history-for-all-callers',
    );

    testWidgets('track-all-callers toggle is present and off by default', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openProgram(tester);

      expect(find.byKey(trackAllCallersKey), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(trackAllCallersKey),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('track-all-callers reflects the initial setting value', (
      tester,
    ) async {
      await _pumpSettings(tester, initialTrackHistoryForAllCallers: true);
      await openProgram(tester);

      final toggle = tester.widget<SwitchListTile>(
        find.byKey(trackAllCallersKey),
      );
      expect(toggle.value, isTrue);
    });

    testWidgets(
      'turning track-all-callers on updates the notifier and persists',
      (tester) async {
        final harness = await _pumpSettings(tester);
        await openProgram(tester);

        await tester.tap(find.byKey(trackAllCallersKey));
        await tester.pumpAndSettle();

        expect(harness.trackHistoryForAllCallersNotifier.value, isTrue);
        expect(
          await harness.repos.settings.get(kTrackHistoryForAllCallersKey),
          isTrue,
        );
        final toggle = tester.widget<SwitchListTile>(
          find.byKey(trackAllCallersKey),
        );
        expect(toggle.value, isTrue);
      },
    );

    testWidgets(
      'turning track-all-callers off updates the notifier and persists',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          initialTrackHistoryForAllCallers: true,
        );
        await openProgram(tester);

        await tester.tap(find.byKey(trackAllCallersKey));
        await tester.pumpAndSettle();

        expect(harness.trackHistoryForAllCallersNotifier.value, isFalse);
        expect(
          await harness.repos.settings.get(kTrackHistoryForAllCallersKey),
          isFalse,
        );
      },
    );

    const sortToggleKey = ValueKey('general-sort-ignore-articles');

    testWidgets('sort-ignore-articles toggle is present and on by default', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openGeneral(tester);

      expect(find.byKey(sortToggleKey), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byKey(sortToggleKey));
      expect(toggle.value, isTrue);
    });

    testWidgets('reflects the initial sort-ignore-articles value', (
      tester,
    ) async {
      await _pumpSettings(tester, initialSortIgnoreArticles: false);
      await openGeneral(tester);

      final toggle = tester.widget<SwitchListTile>(find.byKey(sortToggleKey));
      expect(toggle.value, isFalse);
    });

    testWidgets('turning it off updates the notifier and persists', (
      tester,
    ) async {
      final harness = await _pumpSettings(tester);
      await openGeneral(tester);

      await tester.tap(find.byKey(sortToggleKey));
      await tester.pumpAndSettle();

      expect(harness.sortIgnoreArticlesNotifier.value, isFalse);
      expect(await harness.repos.settings.get(kSortIgnoreArticlesKey), isFalse);
      final toggle = tester.widget<SwitchListTile>(find.byKey(sortToggleKey));
      expect(toggle.value, isFalse);
    });
  });

  group('SettingsScreen — dialect library manager', () {
    // In the side-by-side layout only the selected section's content is shown,
    // so dialect tests must first select the Dialect section.
    Future<void> openDialect(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('settings-nav-dialect')));
      await tester.pumpAndSettle();
    }

    testWidgets('dance details gate is off and child default is disabled', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openDialect(tester);

      final gate = find.byKey(const ValueKey('dialect-canonical-figure-text'));
      final child = find.byKey(
        const ValueKey('dialect-dance-detail-canonical'),
      );
      expect(gate, findsOneWidget);
      expect(child, findsOneWidget);
      expect(tester.widget<SwitchListTile>(gate).value, isFalse);
      expect(tester.widget<SwitchListTile>(child).onChanged, isNull);
      expect(
        find.textContaining('When Canonical figure text is on'),
        findsOneWidget,
      );
    });

    testWidgets('canonical discouraged-term display is on by default', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openDialect(tester);

      final toggle = find.byKey(
        const ValueKey('dialect-canonical-discouraged-terms'),
      );
      expect(toggle, findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('canonical discouraged-term display toggles and persists', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      final toggle = find.byKey(
        const ValueKey('dialect-canonical-discouraged-terms'),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        await ctx.repos.settings.get(kCanonicalDiscouragedTermsKey),
        isFalse,
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    });

    testWidgets('enabling the gate enables and persists the child default', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      final gate = find.byKey(const ValueKey('dialect-canonical-figure-text'));
      final child = find.byKey(
        const ValueKey('dialect-dance-detail-canonical'),
      );
      await tester.tap(gate);
      await tester.pumpAndSettle();
      expect(await ctx.repos.settings.get(kCanonicalFigureTextKey), isTrue);
      expect(tester.widget<SwitchListTile>(child).onChanged, isNotNull);

      await tester.tap(child);
      await tester.pumpAndSettle();
      expect(
        await ctx.repos.settings.get(kDefaultDanceDetailRenderingKey),
        DanceDetailRendering.canonical.name,
      );
    });

    testWidgets('free-text, shorthands, and walkthroughs stay independent', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      final freeText = find.byKey(const ValueKey('dialect-free-text-entry'));
      final shorthands = find.byKey(
        const ValueKey('dialect-figure-shorthands'),
      );
      final walkthroughs = find.byKey(
        const ValueKey('dialect-walkthrough-snippets'),
      );
      expect(freeText, findsOneWidget);
      expect(shorthands, findsOneWidget);
      expect(walkthroughs, findsOneWidget);
      expect(tester.widget<ListTile>(shorthands).enabled, isFalse);

      await tester.tap(freeText);
      await tester.pumpAndSettle();
      expect(await ctx.repos.settings.get(kFreeTextEntryKey), isTrue);
      expect(tester.widget<ListTile>(shorthands).enabled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('dialect-canonical-figure-text')),
      );
      await tester.pumpAndSettle();
      expect(await ctx.repos.settings.get(kCanonicalFigureTextKey), isTrue);
      expect(tester.widget<SwitchListTile>(freeText).value, isTrue);
      expect(tester.widget<ListTile>(walkthroughs).enabled, isTrue);
    });

    testWidgets('renders every preset as a read-only row with a badge', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openDialect(tester);

      for (final preset in Dialect.presets) {
        expect(
          find.byKey(ValueKey('dialect-tile-${preset.name}')),
          findsOneWidget,
          reason: 'Expected a row for ${preset.name}',
        );
        expect(
          find.byKey(ValueKey('dialect-preset-badge-${preset.name}')),
          findsOneWidget,
          reason: 'Expected a preset badge for ${preset.name}',
        );
      }
    });

    testWidgets('only role-neutral presets are offered (no gendered presets)', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openDialect(tester);

      final names = Dialect.presets.map((d) => d.name).toSet();
      expect(names, isNot(contains('Gents/Ladies')));
      expect(names, isNot(contains('Ladles/Gentlespoons')));
      expect(find.text('Gents/Ladies'), findsNothing);
      expect(find.text('Men/Women'), findsNothing);
    });

    testWidgets('default active selection is the app default (Larks/Robins)', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openDialect(tester);

      final group = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(group.groupValue, equals(Dialect.larksRobins.name));
    });

    testWidgets('setting a preset active updates the notifier + persists', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      final tile = find.byKey(
        ValueKey('dialect-tile-${Dialect.leadsFollows.name}'),
      );
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(ctx.dialectLibrary.activeName, equals(Dialect.leadsFollows.name));
      // The bridge mirrors it into the ActiveDialectScope notifier.
      expect(ctx.notifier.value, equals(Dialect.leadsFollows));
      // Persisted as the active-name ref.
      expect(
        await ctx.repos.settings.get(kActiveDialectRefKey),
        equals(Dialect.leadsFollows.name),
      );
    });

    testWidgets('New dialect prompts for a name, opens the editor, and saves', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      await tester.tap(find.byKey(const ValueKey('new-dialect')));
      await tester.pumpAndSettle();

      // Name dialog: accept the default name.
      await tester.enterText(
        find.byKey(const ValueKey('dialect-name-field')),
        'My dialect',
      );
      await tester.tap(find.byKey(const ValueKey('dialect-name-confirm')));
      await tester.pumpAndSettle();

      // Editor route: save immediately.
      expect(find.byKey(const ValueKey('dialect-editor-save')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
      await tester.pumpAndSettle();

      expect(ctx.dialectLibrary.customByName('My dialect'), isNotNull);
      expect(
        find.byKey(const ValueKey('dialect-tile-My dialect')),
        findsOneWidget,
      );
    });

    testWidgets('a canceled New dialect leaves nothing behind', (tester) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      await tester.tap(find.byKey(const ValueKey('new-dialect')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dialect-name-confirm')));
      await tester.pumpAndSettle();

      // Cancel the editor via the system back button.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(ctx.dialectLibrary.customDialects, isEmpty);
    });

    testWidgets('Duplicate from a preset creates a custom copy', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await openDialect(tester);

      await tester.tap(find.byKey(const ValueKey('duplicate-dialect')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('dialect-duplicate-source-${Dialect.leadsFollows.name}'),
        ),
      );
      await tester.pumpAndSettle();

      final copyName = '${Dialect.leadsFollows.name} (copy)';
      expect(ctx.dialectLibrary.customByName(copyName), isNotNull);
      expect(find.byKey(ValueKey('dialect-tile-$copyName')), findsOneWidget);
      // A duplicate does not change the active dialect.
      expect(ctx.dialectLibrary.active, equals(Dialect.larksRobins));
    });

    testWidgets('presets are not editable in place (offer duplicate instead)', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await openDialect(tester);

      await tester.tap(
        find.byKey(ValueKey('dialect-menu-${Dialect.larksRobins.name}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Duplicate to customize'), findsOneWidget);
      expect(find.text('Edit terms'), findsNothing);
    });

    testWidgets('renaming a custom dialect updates the list + active pointer', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await ctx.dialectLibrary.upsert(Dialect(name: 'Old name'));
      await ctx.dialectLibrary.setActive('Old name');
      await openDialect(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dialect-menu-Old name')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('dialect-name-field')),
        'New name',
      );
      await tester.tap(find.byKey(const ValueKey('dialect-name-confirm')));
      await tester.pumpAndSettle();

      expect(ctx.dialectLibrary.customByName('Old name'), isNull);
      expect(ctx.dialectLibrary.customByName('New name'), isNotNull);
      expect(ctx.dialectLibrary.activeName, equals('New name'));
      expect(
        find.byKey(const ValueKey('dialect-tile-New name')),
        findsOneWidget,
      );
    });

    testWidgets('deleting a custom dialect removes it after confirming', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await ctx.dialectLibrary.upsert(Dialect(name: 'Doomed'));
      await ctx.dialectLibrary.setActive('Doomed');
      await openDialect(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dialect-menu-Doomed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // Confirm.
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(ctx.dialectLibrary.customByName('Doomed'), isNull);
      expect(find.byKey(const ValueKey('dialect-tile-Doomed')), findsNothing);
      // Active falls back to the app default.
      expect(ctx.dialectLibrary.active, equals(Dialect.larksRobins));
    });

    testWidgets('editing a custom dialect terms round-trips through upsert', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await ctx.dialectLibrary.upsert(Dialect(name: 'Mine'));
      await openDialect(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dialect-menu-Mine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit terms'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('dialect-role1-singular')),
        'Gent',
      );
      await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
      await tester.pumpAndSettle();

      final saved = ctx.dialectLibrary.customByName('Mine');
      expect(saved, isNotNull);
      expect(saved!.roles['role1']!.singular, equals('Gent'));
      // The name is preserved (edit terms never renames).
      expect(saved.name, equals('Mine'));
    });

    testWidgets('saving an invalid dialect surfaces issues and stays open', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      await ctx.dialectLibrary.upsert(Dialect(name: 'Mine'));
      await openDialect(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dialect-menu-Mine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit terms'));
      await tester.pumpAndSettle();

      // Two roles mapping to the same term is an ambiguous collision.
      await tester.enterText(
        find.byKey(const ValueKey('dialect-role1-singular')),
        'Same',
      );
      await tester.enterText(
        find.byKey(const ValueKey('dialect-role2-singular')),
        'Same',
      );
      await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
      await tester.pumpAndSettle();

      // The editor stays open with the issue surfaced; nothing was saved.
      expect(
        find.byKey(const ValueKey('dialect-validation-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dialect-editor-save')), findsOneWidget);
      expect(ctx.dialectLibrary.customByName('Mine')!.roles, isEmpty);

      // Resolving the collision lets the save go through.
      await tester.enterText(
        find.byKey(const ValueKey('dialect-role2-singular')),
        'Other',
      );
      await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
      await tester.pumpAndSettle();

      final saved = ctx.dialectLibrary.customByName('Mine')!;
      expect(saved.roles['role1']!.singular, equals('Same'));
      expect(saved.roles['role2']!.singular, equals('Other'));
    });
  });

  group('SettingsScreen — theme selection', () {
    testWidgets('renders a preview card for every theme option', (
      tester,
    ) async {
      await _pumpSettings(tester);

      for (final option in AppThemeSelection.values) {
        final card = find.byKey(ValueKey('theme-${option.name}'));
        expect(
          card,
          findsOneWidget,
          reason: 'Expected preview card for ${option.name}',
        );
        // The option's label is shown inside its own card.
        expect(
          find.descendant(of: card, matching: find.text(option.label)),
          findsOneWidget,
          reason: 'Expected label inside card for ${option.name}',
        );
      }
    });

    testWidgets('the active option shows a non-color-only selected state', (
      tester,
    ) async {
      await _pumpSettings(tester, initialTheme: AppThemeSelection.dark);

      // Selection must not rely on color alone: the active card also renders a
      // check icon and a "Selected" label.
      final selectedCard = find.byKey(
        ValueKey('theme-${AppThemeSelection.dark.name}'),
      );
      expect(
        find.descendant(
          of: selectedCard,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: selectedCard, matching: find.text('Selected')),
        findsOneWidget,
      );

      // And an unselected card shows neither.
      final otherCard = find.byKey(
        ValueKey('theme-${AppThemeSelection.light.name}'),
      );
      expect(
        find.descendant(
          of: otherCard,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNothing,
      );
    });

    testWidgets('selecting a theme updates the notifier live', (tester) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      final card = find.byKey(
        ValueKey('theme-${AppThemeSelection.highContrast.name}'),
      );
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(ctx.themeNotifier.value, equals(AppThemeSelection.highContrast));
    });

    testWidgets('selecting a theme persists to SettingsRepository', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      final card = find.byKey(ValueKey('theme-${AppThemeSelection.dark.name}'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      final stored = await ctx.repos.settings.get(kAppThemeKey) as String?;
      expect(stored, equals(AppThemeSelection.dark.name));
    });

    testWidgets('round-trip: stored name is restored to correct selection', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      await repos.settings.set(kAppThemeKey, AppThemeSelection.light.name);

      final name = await repos.settings.get(kAppThemeKey) as String?;
      final selection = AppThemeSelection.forName(name);

      expect(selection, equals(AppThemeSelection.light));
    });

    testWidgets('default-when-unset resolves to null (System default)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();

      final name = await repos.settings.get(kAppThemeKey) as String?;
      final selection =
          AppThemeSelection.forName(name) ?? AppThemeSelection.system;

      expect(selection, equals(AppThemeSelection.system));
    });

    test('themeMode mapping is correct for each selection', () {
      expect(AppThemeSelection.system.themeMode, ThemeMode.system);
      expect(AppThemeSelection.light.themeMode, ThemeMode.light);
      expect(AppThemeSelection.dark.themeMode, ThemeMode.dark);
      // High-contrast forces the dark slot (both theme slots are high-contrast).
      expect(AppThemeSelection.highContrast.themeMode, ThemeMode.dark);
      expect(AppThemeSelection.highContrast.isHighContrast, isTrue);
      expect(AppThemeSelection.light.isHighContrast, isFalse);
      // Gallery palettes follow their pinned scheme's brightness.
      expect(AppThemeSelection.blulocoLight.themeMode, ThemeMode.light);
      expect(AppThemeSelection.monokai.themeMode, ThemeMode.dark);
    });

    test(
      'inGroup orders gallery sections A→Z and the Default group by canvas',
      () {
        // Gallery sections (Light/Dark) list alphabetically by label.
        for (final group in [AppThemeGroup.light, AppThemeGroup.dark]) {
          final labels = AppThemeSelection.inGroup(
            group,
          ).map((s) => s.label).toList();
          final sorted = [...labels]
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          expect(
            labels,
            equals(sorted),
            reason: '${group.label} gallery section should be alphabetical',
          );
        }
        // The Default group uses a curated order (Dark, Soft Dark, High
        // contrast, Light) rather than alphabetical, which reads more
        // intuitively in the Settings pane.
        expect(
          AppThemeSelection.inGroup(
            AppThemeGroup.defaultHearth,
          ).map((s) => s.label),
          equals(['Dark', 'Soft Dark', 'High contrast', 'Light']),
        );
      },
    );

    test('gallery grouping and brightness resolvers are correct', () {
      expect(AppThemeSelection.system.group, AppThemeGroup.system);
      expect(AppThemeSelection.light.group, AppThemeGroup.defaultHearth);
      expect(AppThemeSelection.highContrast.group, AppThemeGroup.defaultHearth);
      expect(AppThemeSelection.blulocoLight.group, AppThemeGroup.light);
      expect(AppThemeSelection.noctis.group, AppThemeGroup.dark);
      expect(AppThemeSelection.monokai.brightness, Brightness.dark);
      expect(AppThemeSelection.noctisLilac.brightness, Brightness.light);
    });

    testWidgets('selecting a gallery palette persists and updates live', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      final card = find.byKey(
        ValueKey('theme-${AppThemeSelection.monokai.name}'),
      );
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(ctx.themeNotifier.value, equals(AppThemeSelection.monokai));
      final stored = await ctx.repos.settings.get(kAppThemeKey) as String?;
      expect(stored, equals(AppThemeSelection.monokai.name));
    });

    testWidgets('gallery renders labeled group headings', (tester) async {
      await _pumpSettings(tester);
      for (final group in AppThemeGroup.values) {
        expect(
          find.text(group.label),
          findsWidgets,
          reason: 'Expected a "${group.label}" section heading',
        );
      }
    });
  });

  group('SettingsScreen — custom themes', () {
    // The Appearance list scrolls (the theme gallery grew), so the custom
    // themes section can sit below the fold. Scroll the content list — located
    // via the always-built gallery — until [target] is on screen.
    Future<void> revealInAppearance(WidgetTester tester, Finder target) async {
      final scrollable = find
          .ancestor(
            of: find.byKey(ValueKey('theme-${AppThemeSelection.system.name}')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    testWidgets('shows an empty-state hint and a New custom theme button', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await revealInAppearance(
        tester,
        find.byKey(const ValueKey('new-custom-theme')),
      );
      expect(find.byKey(const ValueKey('new-custom-theme')), findsOneWidget);
      expect(find.textContaining('saved on this device'), findsOneWidget);
    });

    testWidgets('renders a card for each saved custom theme', (tester) async {
      final ctx = await _pumpSettings(tester);
      final created = await ctx.customThemes.duplicate(
        name: 'Test Theme',
        brightness: Brightness.dark,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.dark()),
      );
      await tester.pumpAndSettle();
      await revealInAppearance(
        tester,
        find.byKey(ValueKey('custom-${created.id}')),
      );

      expect(find.byKey(ValueKey('custom-${created.id}')), findsOneWidget);
      expect(find.text('Test Theme'), findsOneWidget);
    });

    testWidgets('selecting a custom card activates it and clears built-in', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.monokai,
      );
      final created = await ctx.customThemes.duplicate(
        name: 'Test Theme',
        brightness: Brightness.light,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.light()),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(ValueKey('custom-${created.id}'));
      await revealInAppearance(tester, card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(ctx.customThemes.hasActive, isTrue);
      expect(ctx.customThemes.activeId, created.id);
      final storedActive =
          await ctx.repos.settings.get('active_custom_theme') as String?;
      expect(storedActive, created.id);
    });

    testWidgets('selecting a built-in theme clears the active custom theme', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      final created = await ctx.customThemes.duplicate(
        name: 'Test Theme',
        brightness: Brightness.dark,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.dark()),
      );
      await ctx.customThemes.setActive(created.id);
      await tester.pumpAndSettle();
      expect(ctx.customThemes.hasActive, isTrue);

      final builtIn = find.byKey(
        ValueKey('theme-${AppThemeSelection.monokai.name}'),
      );
      await tester.ensureVisible(builtIn);
      await tester.tap(builtIn);
      await tester.pumpAndSettle();

      expect(ctx.customThemes.hasActive, isFalse);
      expect(ctx.themeNotifier.value, AppThemeSelection.monokai);
    });
  });

  group('SettingsScreen — section navigation', () {
    testWidgets('sidebar renders a nav item for every section', (tester) async {
      await _pumpSettings(tester);
      expect(
        find.byKey(const ValueKey('settings-nav-appearance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-dialect')),
        findsOneWidget,
      );
    });

    testWidgets('navigation preserves section order, content, and icon pairs', (
      tester,
    ) async {
      await _pumpSettings(tester, surfaceSize: const Size(500, 900));
      final program = find.byKey(const ValueKey('settings-nav-program'));
      final diagnostics = find.byKey(
        const ValueKey('settings-nav-diagnostics'),
      );
      final experimental = find.byKey(
        const ValueKey('settings-nav-experimental'),
      );
      final about = find.byKey(const ValueKey('settings-nav-about'));

      expect(program, findsOneWidget);
      expect(experimental, findsOneWidget);
      expect(
        tester.getTopLeft(diagnostics).dy,
        lessThan(tester.getTopLeft(experimental).dy),
      );
      expect(
        tester.getTopLeft(experimental).dy,
        lessThan(tester.getTopLeft(about).dy),
      );
      expect(
        find.descendant(
          of: program,
          matching: find.byIcon(Icons.event_note_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: experimental,
          matching: find.byIcon(Icons.psychology_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-nav-updates')),
          matching: find.byIcon(Icons.update_outlined),
        ),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(const Size(1000, 2600));
      await tester.pumpAndSettle();

      await tester.tap(program);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: program, matching: find.byIcon(Icons.event_note)),
        findsOneWidget,
      );
      expect(find.text('Venues'), findsOneWidget);

      await tester.tap(experimental);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'New features may appear here while they are still in development.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: experimental,
          matching: find.byIcon(Icons.psychology),
        ),
        findsOneWidget,
      );

      final updates = find.byKey(const ValueKey('settings-nav-updates'));
      await tester.tap(updates);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: updates, matching: find.byIcon(Icons.update)),
        findsOneWidget,
      );
    });

    testWidgets('appearance is shown by default and dialect is hidden', (
      tester,
    ) async {
      await _pumpSettings(tester);
      // Appearance content: the theme gallery is present.
      expect(
        find.byKey(ValueKey('theme-${AppThemeSelection.system.name}')),
        findsOneWidget,
      );
      // Dialect content is not mounted until its section is selected.
      expect(
        find.byKey(ValueKey('dialect-tile-${Dialect.larksRobins.name}')),
        findsNothing,
      );
    });

    testWidgets('selecting Dialect swaps the content pane', (tester) async {
      await _pumpSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-dialect')));
      await tester.pumpAndSettle();

      // Now dialect tiles are shown and the theme gallery is gone.
      expect(
        find.byKey(ValueKey('dialect-tile-${Dialect.larksRobins.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('theme-${AppThemeSelection.system.name}')),
        findsNothing,
      );
    });

    testWidgets('narrow layout pushes a detail page that updates live', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialDialect: Dialect.larksRobins,
        surfaceSize: const Size(500, 900),
      );

      // Narrow layout: tapping a nav row pushes the section as its own page.
      await tester.tap(find.byKey(const ValueKey('settings-nav-dialect')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('dialect-tile-${Dialect.leadsFollows.name}')),
        findsOneWidget,
      );

      // Selecting a dialect on the pushed page must update it live (the route
      // depends on ActiveDialectScope, so the notifier change rebuilds it).
      await tester.tap(
        find.byKey(ValueKey('dialect-tile-${Dialect.leadsFollows.name}')),
      );
      await tester.pumpAndSettle();
      expect(ctx.notifier.value, Dialect.leadsFollows);

      final group = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(group.groupValue, Dialect.leadsFollows.name);
    });
  });

  group('SectionHeader — shared widget', () {
    testWidgets('settings sections render via the shared SectionHeader', (
      tester,
    ) async {
      await _pumpSettings(tester);

      // The Appearance section is shown by default; its headers are rendered
      // by the shared SectionHeader (extracted from this screen so the dance
      // editor can reuse the identical style).
      expect(find.widgetWithText(SectionHeader, 'Theme'), findsOneWidget);
      expect(
        find.widgetWithText(SectionHeader, 'Custom themes'),
        findsOneWidget,
      );
    });
    group('SettingsScreen — Device Sync (ADR-004/W13)', () {
      Future<void> openExperimental(WidgetTester tester) async {
        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();
      }

      setUp(() {
        _syncNetwork.kind = SyncNetworkKind.unmetered;
        _syncCoordinator = null;
        _pairingProbeFactory = null;
      });

      testWidgets('lives under Experimental, not as its own settings section', (
        tester,
      ) async {
        await _pumpSettings(tester);
        // The section list is the navigation; Device Sync must not be an entry.
        expect(find.text('Device Sync'), findsNothing);

        await openExperimental(tester);
        expect(find.text('Device Sync'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sync-enabled-toggle')),
          findsOneWidget,
        );
      });

      testWidgets('is off by default and shows no status until turned on', (
        tester,
      ) async {
        final harness = await _pumpSettings(tester);
        await openExperimental(tester);

        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('sync-enabled-toggle')),
              )
              .value,
          isFalse,
        );
        expect(find.byKey(const ValueKey('sync-status')), findsNothing);
        expect(find.byKey(const ValueKey('sync-now')), findsNothing);
        expect(await harness.repos.settings.get('sync_enabled'), isNull);
      });

      testWidgets('turning it on persists consent and shows WiFi-only on', (
        tester,
      ) async {
        final harness = await _pumpSettings(tester);
        await openExperimental(tester);

        await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
        await tester.pumpAndSettle();

        expect(await harness.repos.settings.get('sync_enabled'), isTrue);
        expect(find.text('Sync only on WiFi'), findsOneWidget);
        final wifi = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Sync only on WiFi'),
        );
        expect(wifi.value, isTrue);
        expect(find.text('Not connected to a store yet.'), findsOneWidget);
      });

      testWidgets('the not-a-backup disclosure is on the status surface', (
        tester,
      ) async {
        await _pumpSettings(tester);
        await openExperimental(tester);
        await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
        await tester.pumpAndSettle();

        final status = find.byKey(const ValueKey('sync-status'));
        final disclosure = find.byKey(const ValueKey('sync-not-a-backup'));
        expect(status, findsOneWidget);
        expect(disclosure, findsOneWidget);
        expect(
          tester.widget<Text>(disclosure).data,
          contains('Sync is not a backup'),
        );
      });

      testWidgets('warns as the disuse expiry approaches', (tester) async {
        final harness = await _pumpSettings(tester);
        await harness.repos.settings.set('sync_id', 'correct horse battery');
        final controller = SyncScope.of(
          tester.element(find.byType(SettingsScreen)),
        );
        await controller.setEnabled(true);
        await harness.repos.settings.set(
          'sync_last_success_at',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 22))
              .toIso8601String(),
        );
        await controller.load();
        await openExperimental(tester);

        expect(
          find.byKey(const ValueKey('sync-expiry-warning')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('sync-not-a-backup')), findsOneWidget);
      });

      testWidgets(
        'a manual sync on a metered connection explains and routes to '
        'the WiFi setting',
        (tester) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'correct horse battery');
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: NoopSyncCoordinatorTransport(),
            passOperation: ({initialStore}) async =>
                throw StateError('a metered manual sync must not run a pass'),
          );
          addTearDown(_syncCoordinator!.dispose);
          _syncNetwork.kind = SyncNetworkKind.metered;
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(
            find.textContaining('Sync only on WiFi is on'),
            findsOneWidget,
          );
        },
      );
    });

    group('SyncPairingScreen (ADR-004/W13 PR2)', () {
      Future<void> openExperimental(WidgetTester tester) async {
        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();
      }

      Future<void> enableAndOpenPairing(
        WidgetTester tester, {
        BackupSaver? backupSaver,
      }) async {
        await _pumpSettings(tester, backupSaver: backupSaver);
        await openExperimental(tester);
        await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-connect')));
        await tester.pumpAndSettle();
      }

      setUp(() {
        _syncNetwork.kind = SyncNetworkKind.unmetered;
        _syncCoordinator = null;
        _pairingProbeFactory = null;
      });

      testWidgets('the connect button opens the create-or-connect choice, '
          'never inferring either (spec §6.14 item 5)', (tester) async {
        await enableAndOpenPairing(tester);

        expect(
          find.byKey(const ValueKey('sync-pairing-create')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sync-pairing-connect')),
          findsOneWidget,
        );
      });

      testWidgets(
        'creating shows the sharing and no-recovery disclosures, offers a '
        'skippable backup, and reports success once connected',
        (tester) async {
          var createCalls = 0;
          _pairingProbeFactory = (syncId) => SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                throw UnimplementedError('create must not GET'),
            createStore: () async {
              createCalls++;
              return const SyncHttpResponse(
                statusCode: 201,
                kind: SyncResponseKind.created,
                headers: {},
                body: [],
              );
            },
          );
          await enableAndOpenPairing(tester);
          await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('sync-pairing-sharing-disclosure')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('sync-pairing-credential-disclosure')),
            findsOneWidget,
          );
          expect(find.text('Sharing is not collaboration'), findsOneWidget);
          expect(
            find.text("This phrase can't be recovered or revoked"),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-backup-skip')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
          await tester.pumpAndSettle();

          expect(createCalls, 1);
          expect(
            find.byKey(const ValueKey('sync-pairing-complete-dialog')),
            findsOneWidget,
          );
          expect(find.text('Connected'), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-complete-ok')),
          );
          await tester.pumpAndSettle();

          // Back on Settings: paired, and the sync ID is persisted.
          expect(
            find.byKey(const ValueKey('sync-pairing-create')),
            findsNothing,
          );
          expect(find.text('Connected. Not synced yet.'), findsOneWidget);
        },
      );

      testWidgets(
        'creating a phrase that is already in use reports it and starts '
        'nothing (spec §6.14 item 5)',
        (tester) async {
          _pairingProbeFactory = (syncId) => SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                throw UnimplementedError('create must not GET'),
            createStore: () async => const SyncHttpResponse(
              statusCode: 409,
              kind: SyncResponseKind.conflict,
              headers: {},
              body: [],
            ),
          );
          final harness = await _pumpSettings(tester);
          await openExperimental(tester);
          await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-connect')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-backup-skip')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
          await tester.pumpAndSettle();

          expect(
            find.text(
              'That phrase is already in use by another store. Generate a '
              'different one.',
            ),
            findsOneWidget,
          );
          expect(await harness.repos.settings.get('sync_id'), isNull);
        },
      );

      testWidgets(
        'connecting to a phrase with no store reports it and never creates '
        'one (spec §6.2 step 2, §6.14 item 5)',
        (tester) async {
          var getStoreCalls = 0;
          var createStoreCalls = 0;
          _pairingProbeFactory = (syncId) => SyncPairingProbe(
            getStore: ({required previouslyUsed}) async {
              getStoreCalls++;
              expect(
                previouslyUsed,
                isFalse,
                reason: 'a fresh pairing attempt has no local baseline',
              );
              return SyncStoreResult(
                response: const SyncHttpResponse(
                  statusCode: 404,
                  kind: SyncResponseKind.notFound,
                  headers: {},
                  body: [],
                ),
                missingKind: SyncStoreMissingKind.firstTime,
              );
            },
            createStore: () async {
              createStoreCalls++;
              throw StateError('connect must never POST');
            },
          );
          final harness = await _pumpSettings(tester);
          await openExperimental(tester);
          await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-connect')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-connect')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('sync-pairing-phrase-field')),
            'alpha-bravo-charlie-delta',
          );
          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-backup-skip')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
          await tester.pumpAndSettle();

          expect(getStoreCalls, 1);
          expect(createStoreCalls, 0);
          expect(
            find.text(
              "No store has that phrase. Check it against the other device "
              "and try again.",
            ),
            findsOneWidget,
          );
          expect(await harness.repos.settings.get('sync_id'), isNull);
        },
      );

      testWidgets('an incomplete phrase is rejected before any network call', (
        tester,
      ) async {
        var probeBuilt = false;
        _pairingProbeFactory = (syncId) {
          probeBuilt = true;
          throw StateError('must not be reached for an invalid phrase');
        };
        await enableAndOpenPairing(tester);
        await tester.tap(find.byKey(const ValueKey('sync-pairing-connect')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-phrase-field')),
          'only-three-words',
        );
        await tester.tap(
          find.byKey(const ValueKey('sync-pairing-backup-skip')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
        await tester.pumpAndSettle();

        expect(probeBuilt, isFalse);
        expect(
          find.text("That doesn't look like a complete sync phrase."),
          findsOneWidget,
        );
      });

      testWidgets(
        'the backup offer never starts automatically: skip exports nothing, '
        'accept exports exactly once (spec §6.14 item 3)',
        (tester) async {
          var exportCalls = 0;
          Future<bool> saver(String json, String name) async {
            exportCalls++;
            return true;
          }

          _pairingProbeFactory = (syncId) => SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                throw UnimplementedError(),
            createStore: () async => const SyncHttpResponse(
              statusCode: 201,
              kind: SyncResponseKind.created,
              headers: {},
              body: [],
            ),
          );
          await enableAndOpenPairing(tester, backupSaver: saver);
          await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
          await tester.pumpAndSettle();

          // The backup offer is shown but nothing has been exported yet.
          expect(exportCalls, 0);

          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-backup-accept')),
          );
          await tester.pumpAndSettle();

          expect(exportCalls, 1);
        },
      );
    });

    group('Replacement dialog (ADR-004/W13 PR2, spec §6.14 item 6)', () {
      Future<void> openExperimental(WidgetTester tester) async {
        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();
      }

      setUp(() {
        _syncNetwork.kind = SyncNetworkKind.unmetered;
        _syncCoordinator = null;
        _pairingProbeFactory = null;
      });

      testWidgets(
        'explains the missing store without asserting a cause, and confirm '
        'issues exactly one POST while cancel issues none',
        (tester) async {
          final transport = ControllableSyncTransport();
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'configured-store-id-x');
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();

          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: transport,
            passOperation: ({initialStore}) async {
              if (transport.createStoreCalls == 0) {
                return const SyncPassResult(SyncPassStatus.replacementRequired);
              }
              return const SyncPassResult(SyncPassStatus.completed);
            },
          );
          addTearDown(_syncCoordinator!.dispose);
          controller.attachCoordinator(_syncCoordinator);
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('sync-replacement-dialog')),
            findsOneWidget,
          );
          final body = tester
              .widget<Text>(
                find.descendant(
                  of: find.byKey(const ValueKey('sync-replacement-dialog')),
                  matching: find.textContaining('may have expired'),
                ),
              )
              .data!;
          expect(body, contains('or it may have been removed'));

          // Cancel: no POST, and the dialog can reappear later.
          await tester.tap(
            find.byKey(const ValueKey('sync-replacement-cancel')),
          );
          await tester.pumpAndSettle();
          expect(transport.createStoreCalls, 0);
          expect(
            find.byKey(const ValueKey('sync-replacement-dialog')),
            findsNothing,
          );

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('sync-replacement-dialog')),
            findsOneWidget,
          );

          // Confirm: exactly one POST even if the dialog were tapped twice.
          await tester.tap(
            find.byKey(const ValueKey('sync-replacement-confirm')),
          );
          await tester.pumpAndSettle();
          expect(transport.createStoreCalls, 1);
        },
      );
    });
  });
}
