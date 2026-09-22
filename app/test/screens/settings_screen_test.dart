import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
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
    syncLocal: repos.syncLocal,
    coordinator: () => _syncCoordinator,
    reconfigure: () async {},
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

/// Opens the Device Sync section of the Experimental pane when it starts
/// collapsed (sync off); a no-op when it is already open.
Future<void> _expandSyncSection(WidgetTester tester) async {
  if (find.byKey(const ValueKey('sync-enabled-toggle')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const ValueKey('sync-section')));
  await tester.pumpAndSettle();
}

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
        await _expandSyncSection(tester);
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
        expect(find.text('DEVICE SYNC'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();
        expect(find.text('DEVICE SYNC'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sync-enabled-toggle')),
          findsNothing,
          reason: 'collapsed while sync is off',
        );

        await _expandSyncSection(tester);
        expect(
          find.byKey(const ValueKey('sync-enabled-toggle')),
          findsOneWidget,
        );
      });

      testWidgets('starts expanded while sync is on, so its status is in '
          'view', (tester) async {
        final harness = await _pumpSettings(tester);
        await harness.repos.settings.set('sync_enabled', true);
        await SyncScope.of(tester.element(find.byType(SettingsScreen))).load();
        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('sync-status')), findsOneWidget);
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

      testWidgets('exclude-imports is off by default and persists when toggled '
          '(ADR-004/W13 PR3)', (tester) async {
        final harness = await _pumpSettings(tester);
        await openExperimental(tester);
        await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
        await tester.pumpAndSettle();

        final toggle = find.byKey(
          const ValueKey('sync-exclude-imports-toggle'),
        );
        expect(
          tester.widget<SwitchListTile>(toggle).value,
          isFalse,
          reason: 'off by default (spec §6.1)',
        );
        expect(
          await harness.repos.settings.get('sync_exclude_imports'),
          isNull,
        );

        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(
          await harness.repos.settings.get('sync_exclude_imports'),
          isTrue,
        );
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

      testWidgets(
        'a failed pass is shown, and an earlier last-synced time is not lost',
        (tester) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'correct horse battery');
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          var shouldFail = false;
          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: NoopSyncCoordinatorTransport(),
            passOperation: ({initialStore}) async => shouldFail
                ? const SyncPassResult(SyncPassStatus.failed)
                : const SyncPassResult(SyncPassStatus.completed),
          );
          addTearDown(_syncCoordinator!.dispose);
          await openExperimental(tester);

          // A completed pass first, to establish a last-synced time.
          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();
          expect(find.textContaining('Last synced'), findsOneWidget);

          // A failed pass must replace the stale "last synced" headline —
          // not be silently absorbed by it — while still naming the earlier
          // success separately.
          shouldFail = true;
          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(find.text('Last sync failed.'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('sync-status-last-success')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a stale-epoch pass reports the store changed, not a stale success',
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
                const SyncPassResult(SyncPassStatus.staleEpoch),
          );
          addTearDown(_syncCoordinator!.dispose);
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(find.textContaining('was replaced'), findsOneWidget);
        },
      );

      testWidgets(
        'a store that no longer exists is explained without claiming a '
        'cause the server did not give',
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
                const SyncPassResult(SyncPassStatus.replacementRequired),
          );
          addTearDown(_syncCoordinator!.dispose);
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(find.textContaining('may have expired'), findsOneWidget);
        },
      );

      testWidgets(
        'a phrase no store has ever answered to is reported as not found, '
        'not as expired',
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
                const SyncPassResult(SyncPassStatus.firstTimeStoreRequired),
          );
          addTearDown(_syncCoordinator!.dispose);
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          // §6.2 keeps a never-seen phrase apart from a store that has gone:
          // nothing existed to expire, so the expiry wording would explain a
          // store that was never there.
          expect(find.textContaining('No store has this'), findsOneWidget);
          expect(find.textContaining('may have expired'), findsNothing);
        },
      );

      // A *report* is defined by the spec as a user-visible, non-blocking
      // notice that outlasts the pass which raised it
      // (docs/design/sync-spec.md:46). The engine raises twelve codes and the
      // isolate ships them across intact, but nothing in `app/lib` read
      // `SyncPassResult.reports`, so a pass that ended `completed` while
      // holding a permanent equal-`updatedAt` divergence looked exactly like
      // a clean sync (#1349 finding 1).
      group('pass reports (spec §2 "report", §6.3, §6.4)', () {
        /// Pairs the device, turns sync on, and installs a coordinator whose
        /// pass returns whatever [result] currently holds, so a test can walk
        /// a sequence of passes through the real controller and widget rather
        /// than an inline fake of either.
        Future<({SyncController controller, List<int> passes})> pumpPassing(
          WidgetTester tester,
          SyncPassResult Function() result,
        ) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'correct horse battery');
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          final passes = <int>[];
          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: NoopSyncCoordinatorTransport(),
            passOperation: ({initialStore}) async {
              passes.add(1);
              return result();
            },
          );
          addTearDown(_syncCoordinator!.dispose);
          await openExperimental(tester);
          return (controller: controller, passes: passes);
        }

        Future<void> syncNow(WidgetTester tester) async {
          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();
        }

        const tie = SyncReport(
          code: SyncReportCode.equalUpdatedAt,
          kind: SyncRecordKind.dance,
          recordId: 'dance-1',
          message: 'Different record bodies have the same updatedAt.',
        );
        const divergence = ValueKey('sync-notice-divergence');

        testWidgets('an equal-updatedAt tie on a completed pass is shown '
            'beside the status', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [tie],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(find.byKey(divergence), findsOneWidget);
          // The pass completed, so the headline is still the success line: a
          // report names a condition, it does not fail the pass.
          expect(find.textContaining('Last synced'), findsOneWidget);
        });

        testWidgets('the notice survives the next pass that raises the same '
            'condition, and is shown once', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [tie],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);
          await syncNow(tester);

          expect(find.byKey(divergence), findsOneWidget);
        });

        testWidgets('the notice stops being shown once a completed pass no '
            'longer raises it', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [tie],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);
          expect(find.byKey(divergence), findsOneWidget);

          result = const SyncPassResult(SyncPassStatus.completed);
          await syncNow(tester);

          expect(find.byKey(divergence), findsNothing);
        });

        testWidgets('a notice outlives a pass that failed before it could '
            're-check the condition', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [tie],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          // A pass that never reached the merge raises nothing; clearing on
          // it would retract a standing divergence for an unrelated network
          // failure, which is the same class of silence as #1349 itself.
          result = const SyncPassResult(SyncPassStatus.failed);
          await syncNow(tester);

          expect(find.byKey(divergence), findsOneWidget);
          expect(find.text('Last sync failed.'), findsOneWidget);
        });

        testWidgets('a local creation kept from a peer deletion is surfaced '
            '(§6.4)', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [
              SyncReport(
                code: SyncReportCode.unseenLocalCreation,
                kind: SyncRecordKind.program,
                recordId: 'program-1',
                message: 'A locally-created record would be resolved out.',
              ),
            ],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(
            find.byKey(const ValueKey('sync-notice-keptLocalCreation')),
            findsOneWidget,
          );
        });

        testWidgets('every code that skips a record reaches the '
            'skipped-record notice', (tester) async {
          const codes = [
            SyncReportCode.quarantinedRecord,
            SyncReportCode.unresolvedBlob,
            SyncReportCode.nonCanonicalWireBody,
            SyncReportCode.invalidClassification,
            SyncReportCode.malformedRecord,
            SyncReportCode.blobIdentityMismatch,
            SyncReportCode.unresolvedReference,
          ];
          var result = const SyncPassResult(SyncPassStatus.completed);
          await pumpPassing(tester, () => result);

          for (final code in codes) {
            result = SyncPassResult(
              SyncPassStatus.completed,
              // Every code in this group describes an *inbound* record, so
              // each carries the peer it came from. `quarantinedRecord`
              // without one is a different condition entirely — see the
              // local-quarantine test below.
              reports: [
                SyncReport(code: code, message: 'skipped', peerId: 'peer-1'),
              ],
            );
            await syncNow(tester);
            expect(
              find.byKey(const ValueKey('sync-notice-skippedRecord')),
              findsOneWidget,
              reason: '$code must reach the skipped-record notice',
            );
          }
        });

        // `quarantinedRecord` is raised for two different conditions and
        // `peerId` is the only thing that tells them apart: an inbound record
        // held back (peer id set), and a local row peer-only repair could not
        // rescue, withheld from publication with its dependents (peer id
        // null). Showing "records from another device … check their app
        // version" for the local case is the reported defect in miniature —
        // sending the user to the wrong device.
        testWidgets('a locally quarantined record is not reported as another '
            "device's skipped record", (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [
              SyncReport(
                code: SyncReportCode.quarantinedRecord,
                kind: SyncRecordKind.dance,
                recordId: 'dance-9',
                message:
                    'Record remained quarantined after peer-only timestamp '
                    'repair; 2 database-FK dependents withheld.',
              ),
            ],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(
            find.byKey(const ValueKey('sync-notice-quarantinedLocal')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('sync-notice-skippedRecord')),
            findsNothing,
            reason: 'nothing was received, so nothing was skipped',
          );
          expect(
            find.textContaining('another device'),
            findsNothing,
            reason: 'the remedy is this device, not another one',
          );
        });

        testWidgets('a suspect peer clock is surfaced', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [
              SyncReport(
                code: SyncReportCode.clockSuspect,
                message: 'Every peer timestamp exceeded the clock window.',
              ),
            ],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(
            find.byKey(const ValueKey('sync-notice-clock')),
            findsOneWidget,
          );
        });

        testWidgets('an inbound update deferred by a concurrent local edit is '
            'surfaced', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [
              SyncReport(
                code: SyncReportCode.concurrentLocalChange,
                kind: SyncRecordKind.dance,
                recordId: 'dance-2',
                message: 'Local record changed while sync was preparing.',
              ),
            ],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(
            find.byKey(const ValueKey('sync-notice-deferredInbound')),
            findsOneWidget,
          );
        });

        testWidgets('a publication no peer has reflected is surfaced', (
          tester,
        ) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [
              SyncReport(
                code: SyncReportCode.unreflectedPublication,
                kind: SyncRecordKind.dance,
                recordId: 'dance-3',
                message: 'Not reflected for three consecutive passes.',
              ),
            ],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(
            find.byKey(const ValueKey('sync-notice-unreflectedPublication')),
            findsOneWidget,
          );
        });

        testWidgets('two conditions in one pass each get their own notice', (
          tester,
        ) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [
              tie,
              SyncReport(
                code: SyncReportCode.clockSuspect,
                message: 'Every peer timestamp exceeded the clock window.',
              ),
            ],
          );
          await pumpPassing(tester, () => result);
          await syncNow(tester);

          expect(find.byKey(divergence), findsOneWidget);
          expect(
            find.byKey(const ValueKey('sync-notice-clock')),
            findsOneWidget,
          );
        });

        testWidgets('a notice needs no gesture to clear and gates no later '
            'pass (spec line 46)', (tester) async {
          var result = const SyncPassResult(
            SyncPassStatus.completed,
            reports: [tie],
          );
          final pumped = await pumpPassing(tester, () => result);
          await syncNow(tester);

          final notice = tester.widget<ListTile>(find.byKey(divergence));
          expect(notice.onTap, isNull, reason: 'a report is not a prompt');
          expect(notice.trailing, isNull, reason: 'there is nothing to clear');

          result = const SyncPassResult(SyncPassStatus.completed);
          await syncNow(tester);

          expect(pumped.passes.length, 2, reason: 'reporting gates no pass');
          expect(find.byKey(divergence), findsNothing);
        });
      });

      // Declining a replacement pauses the coordinator; every automatic
      // trigger then answers `paused` without running a pass. With no arm for
      // it the status surface fell back to "Last synced <old date>", which is
      // the one thing that is certainly not true (#1349 finding 2).
      group('paused after a declined replacement (spec §6.3 step 1)', () {
        testWidgets('an automatic trigger after declining still says sync is '
            'paused, not that it last synced', (tester) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'correct horse battery');
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          var result = const SyncPassResult(SyncPassStatus.completed);
          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: NoopSyncCoordinatorTransport(),
            passOperation: ({initialStore}) async => result,
          );
          addTearDown(_syncCoordinator!.dispose);
          // As `main.dart` does when it builds a coordinator: without it the
          // controller never learns a replacement is pending and the real
          // dialog never opens.
          controller.attachCoordinator(_syncCoordinator);
          await openExperimental(tester);

          // One success first, so the stale line the bug fell back to is
          // actually available to fall back to.
          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();
          expect(find.textContaining('Last synced'), findsOneWidget);

          result = const SyncPassResult(SyncPassStatus.replacementRequired);
          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sync-replacement-cancel')),
          );
          await tester.pumpAndSettle();

          // An automatic trigger: the coordinator answers `paused` without
          // running a pass, and that answer is what overwrote the decline's
          // own explanation.
          await controller.onAppStart();
          await tester.pumpAndSettle();

          // Asserted on the headline itself, not merely somewhere on screen:
          // the defect was the headline reverting to "Last synced <old date>"
          // while the store it names is gone.
          final status = tester.widget<ListTile>(
            find.byKey(const ValueKey('sync-status')),
          );
          expect(
            (status.title! as Text).data,
            contains('Sync is paused'),
            reason: 'the headline must not fall back to "Last synced <date>"',
          );
          // The earlier success is still named, separately, as it is for
          // every other non-success status.
          expect(
            find.byKey(const ValueKey('sync-status-last-success')),
            findsOneWidget,
          );
        });

        testWidgets('a manual sync decides again and clears the paused line', (
          tester,
        ) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'correct horse battery');
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          var result = const SyncPassResult(SyncPassStatus.replacementRequired);
          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: NoopSyncCoordinatorTransport(),
            passOperation: ({initialStore}) async => result,
          );
          addTearDown(_syncCoordinator!.dispose);
          controller.attachCoordinator(_syncCoordinator);
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sync-replacement-cancel')),
          );
          await tester.pumpAndSettle();
          await controller.onAppStart();
          await tester.pumpAndSettle();
          expect(find.textContaining('Sync is paused'), findsOneWidget);

          result = const SyncPassResult(SyncPassStatus.completed);
          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(find.textContaining('Sync is paused'), findsNothing);
          expect(find.textContaining('Last synced'), findsOneWidget);
        });
      });

      group('the sync phrase on the status surface', () {
        const phrase = 'alpha-bravo-charlie-delta';
        const mask =
            '••••-••••'
            '-••••-••••';

        Future<SyncController> pumpPaired(
          WidgetTester tester, {
          String syncId = phrase,
        }) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', syncId);
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          await openExperimental(tester);
          return controller;
        }

        testWidgets('is the first row under Status, masked until asked for', (
          tester,
        ) async {
          await pumpPaired(tester);

          final row = find.byKey(const ValueKey('sync-id'));
          expect(row, findsOneWidget);
          expect(
            tester.getTopLeft(row).dy,
            lessThan(
              tester.getTopLeft(find.byKey(const ValueKey('sync-status'))).dy,
            ),
            reason: 'it opens the Status section',
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('sync-id-value')))
                .data,
            mask,
          );
          expect(find.text(phrase), findsNothing);
          expect(find.byKey(const ValueKey('sync-id-caution')), findsOneWidget);
        });

        testWidgets('Show reveals it and hides it again', (tester) async {
          await pumpPaired(tester);

          await tester.tap(find.byKey(const ValueKey('sync-id-reveal')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('sync-id-value')))
                .data,
            phrase,
          );

          await tester.tap(find.byKey(const ValueKey('sync-id-reveal')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('sync-id-value')))
                .data,
            mask,
          );
        });

        testWidgets('copies the phrase without putting it on screen', (
          tester,
        ) async {
          String? clipboardText;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardText = (call.arguments as Map)['text'] as String?;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await pumpPaired(tester);

          await tester.tap(find.byKey(const ValueKey('sync-id-copy')));
          await tester.pumpAndSettle();

          expect(clipboardText, phrase);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('sync-id-value')))
                .data,
            mask,
            reason: 'copying is the whole point; revealing is not required',
          );
          expect(find.byKey(const ValueKey('sync-id-copied')), findsOneWidget);
        });

        testWidgets('a revealed phrase is re-masked when the phrase changes '
            'underneath it', (tester) async {
          final controller = await pumpPaired(tester);
          await tester.tap(find.byKey(const ValueKey('sync-id-reveal')));
          await tester.pumpAndSettle();
          expect(find.text(phrase), findsOneWidget);

          // Detaching and attaching to a different store must not leave the
          // new store's phrase on screen because the old one was revealed.
          await controller.detach();
          await tester.pumpAndSettle();
          await controller.completePairing(
            'echo-foxtrot-golf-hotel',
            Uri.parse(kDefaultSyncEndpoint),
          );
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('sync-id-value')))
                .data,
            mask,
          );
          expect(find.text('echo-foxtrot-golf-hotel'), findsNothing);
        });

        testWidgets('lays out on a phone-width screen', (tester) async {
          // Two trailing buttons beside a label that is far longer in every
          // other locale is exactly the shape that overflows on a narrow
          // screen, and Experimental is a pane a caller opens on a phone.
          final harness = await _pumpSettings(
            tester,
            surfaceSize: const Size(360, 1400),
          );
          await harness.repos.settings.set('sync_id', phrase);
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          await openExperimental(tester);

          expect(find.byKey(const ValueKey('sync-id')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('is absent until a store is connected', (tester) async {
          await _pumpSettings(tester);
          await openExperimental(tester);
          await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('sync-id')), findsNothing);
        });
      });

      group('disconnect (spec glossary: detach)', () {
        Future<CompendiumRepositories> pumpPaired(WidgetTester tester) async {
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set(
            'sync_id',
            'alpha-bravo-charlie-delta',
          );
          final controller = SyncScope.of(
            tester.element(find.byType(SettingsScreen)),
          );
          await controller.setEnabled(true);
          await controller.load();
          await openExperimental(tester);
          return harness.repos;
        }

        testWidgets('is offered only while paired', (tester) async {
          await _pumpSettings(tester);
          await openExperimental(tester);
          await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('sync-disconnect')), findsNothing);
        });

        testWidgets('cancelling changes nothing', (tester) async {
          final repos = await pumpPaired(tester);
          await tester.tap(find.byKey(const ValueKey('sync-disconnect')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('sync-disconnect-dialog')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('sync-disconnect-cancel')),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('sync-disconnect')), findsOneWidget);
          expect(
            await repos.settings.get('sync_id'),
            'alpha-bravo-charlie-delta',
          );
        });

        testWidgets('confirming forgets the phrase, offers Connect again, and '
            'leaves sync turned on', (tester) async {
          final repos = await pumpPaired(tester);
          await tester.tap(find.byKey(const ValueKey('sync-disconnect')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sync-disconnect-confirm')),
          );
          await tester.pumpAndSettle();

          expect(await repos.settings.contains('sync_id'), isFalse);
          expect(find.byKey(const ValueKey('sync-disconnect')), findsNothing);
          expect(find.byKey(const ValueKey('sync-connect')), findsOneWidget);
          expect(await repos.settings.get('sync_enabled'), isTrue);
          expect(find.text('Not connected to a store yet.'), findsOneWidget);
        });
      });

      testWidgets(
        'a crashing sync pass is reported as failed, not an unhandled error',
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
                throw StateError('sync isolate crashed'),
          );
          addTearDown(_syncCoordinator!.dispose);
          await openExperimental(tester);

          await tester.tap(find.byKey(const ValueKey('sync-now')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Last sync failed.'), findsOneWidget);
        },
      );
    });

    group('SyncPairingScreen (ADR-004/W13 PR2)', () {
      Future<void> openExperimental(WidgetTester tester) async {
        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();
        await _expandSyncSection(tester);
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
        'the completion dialog reports the real fresh-attach duplicate '
        'count once the first pass has actually run',
        (tester) async {
          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                throw UnimplementedError(),
            createStore: () async => const SyncHttpResponse(
              statusCode: 201,
              kind: SyncResponseKind.created,
              headers: {},
              body: [],
            ),
          );
          final harness = await _pumpSettings(tester);
          await harness.repos.ensureMigrated();
          _syncCoordinator = SyncCoordinator(
            syncId: 'configured',
            deviceId: 'device',
            store: CompendiumSyncCoordinatorStore(harness.repos),
            transport: NoopSyncCoordinatorTransport(),
            passOperation: ({initialStore}) async => const SyncPassResult(
              SyncPassStatus.completed,
              duplicateCount: 2,
            ),
          );
          addTearDown(_syncCoordinator!.dispose);
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
            find.text('Found and merged 2 duplicate dances.'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'creating shows the sharing and no-recovery disclosures, offers a '
        'skippable backup, and reports success once connected',
        (tester) async {
          var createCalls = 0;
          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
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
          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
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
          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
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

      testWidgets('offers a generated phrase that carries no weakness '
          'warning, and lets the user replace it', (tester) async {
        await enableAndOpenPairing(tester);
        await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('sync-pairing-phrase')),
        );
        final generated = field.controller!.text;
        expect(SyncId.tryParse(generated), isNotNull);
        expect(generated.split('-'), hasLength(4));
        expect(
          find.byKey(const ValueKey('sync-pairing-weak-phrase-warning')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-phrase')),
          'password-qwerty-dragon-monkey',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('sync-pairing-weak-phrase-warning')),
          findsOneWidget,
          reason: 'spec §8 requires an advisory warning below the reference',
        );

        await tester.tap(find.byKey(const ValueKey('sync-pairing-regenerate')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sync-pairing-weak-phrase-warning')),
          findsNothing,
        );
      });

      testWidgets('creates with a weak chosen phrase anyway: the warning never '
          'blocks (spec §8)', (tester) async {
        String? created;
        _pairingProbeFactory = (syncId, endpoint) {
          created = syncId;
          return SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                throw StateError('create must not GET'),
            createStore: () async => const SyncHttpResponse(
              statusCode: 201,
              kind: SyncResponseKind.created,
              headers: {},
              body: [],
            ),
          );
        };
        final harness = await _pumpSettings(tester);
        await openExperimental(tester);
        await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-connect')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
        await tester.pumpAndSettle();
        // Mixed case and padding: the stored ID is the normalised one.
        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-phrase')),
          '  Password-QWERTY-Dragon-Monkey  ',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('sync-pairing-weak-phrase-warning')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('sync-pairing-backup-skip')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
        await tester.pumpAndSettle();

        expect(created, 'password-qwerty-dragon-monkey');
        expect(
          await harness.repos.settings.get('sync_id'),
          'password-qwerty-dragon-monkey',
        );
      });

      testWidgets('a chosen phrase that is not four words is rejected before '
          'any network call', (tester) async {
        var probeBuilt = false;
        _pairingProbeFactory = (syncId, endpoint) {
          probeBuilt = true;
          throw StateError('must not be reached for an invalid phrase');
        };
        await enableAndOpenPairing(tester);
        await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-phrase')),
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

      testWidgets('an incomplete phrase is rejected before any network call', (
        tester,
      ) async {
        var probeBuilt = false;
        _pairingProbeFactory = (syncId, endpoint) {
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

      testWidgets('the server field is pre-filled with the default and shows '
          'no custom-server warning for it, in both modes', (tester) async {
        await enableAndOpenPairing(tester);
        for (final mode in ['sync-pairing-create', 'sync-pairing-connect']) {
          await tester.tap(find.byKey(ValueKey(mode)));
          await tester.pumpAndSettle();

          final field = tester.widget<TextField>(
            find.byKey(const ValueKey('sync-pairing-endpoint-field')),
          );
          expect(field.controller!.text, kDefaultSyncEndpoint, reason: mode);
          expect(
            find.byKey(const ValueKey('sync-pairing-custom-endpoint-warning')),
            findsNothing,
            reason: mode,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-connect')));
          await tester.pumpAndSettle();
        }
      });

      testWidgets('changing the server to another host warns and names it '
          '(spec §8)', (tester) async {
        await enableAndOpenPairing(tester);
        await tester.tap(find.byKey(const ValueKey('sync-pairing-connect')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-endpoint-field')),
          'https://sync.example.test/',
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('sync-pairing-custom-endpoint-warning')),
          findsOneWidget,
        );
        expect(find.text('Custom server: sync.example.test'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-endpoint-field')),
          kDefaultSyncEndpoint,
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('sync-pairing-custom-endpoint-warning')),
          findsNothing,
        );
      });

      testWidgets('a server address that fails entry validation is rejected '
          'before any network call', (tester) async {
        var probeBuilt = false;
        _pairingProbeFactory = (syncId, endpoint) {
          probeBuilt = true;
          throw StateError('must not be reached for an invalid endpoint');
        };
        await enableAndOpenPairing(tester);
        await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('sync-pairing-backup-skip')),
        );
        await tester.pumpAndSettle();

        // Plaintext to a non-loopback host, and an https address carrying a
        // query: the one message must be accurate for both.
        for (final rejected in [
          'http://sync.example.test/',
          'https://sync.example.test/?q=1',
        ]) {
          await tester.enterText(
            find.byKey(const ValueKey('sync-pairing-endpoint-field')),
            rejected,
          );
          await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
          await tester.pumpAndSettle();

          expect(probeBuilt, isFalse, reason: rejected);
          expect(
            find.text(
              "That isn't a valid server address. Use an https:// address "
              'with no username, ? or # part (plain http:// works only for '
              'localhost or 127.0.0.1).',
            ),
            findsOneWidget,
            reason: rejected,
          );
        }
      });

      testWidgets('connecting to a custom server probes that server, persists '
          'it, and keeps it on the status surface', (tester) async {
        Uri? probedEndpoint;
        _pairingProbeFactory = (syncId, endpoint) {
          probedEndpoint = endpoint;
          return SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                const SyncStoreResult(
                  response: SyncHttpResponse(
                    statusCode: 200,
                    kind: SyncResponseKind.success,
                    headers: {},
                    body: [],
                  ),
                ),
            createStore: () async =>
                throw StateError('connect must never POST'),
          );
        };
        final harness = await _pumpSettings(tester);
        await openExperimental(tester);
        await tester.tap(find.byKey(const ValueKey('sync-enabled-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sync-custom-endpoint')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('sync-connect')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-pairing-connect')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-phrase-field')),
          'alpha-bravo-charlie-delta',
        );
        await tester.enterText(
          find.byKey(const ValueKey('sync-pairing-endpoint-field')),
          'https://sync.example.test/',
        );
        await tester.tap(
          find.byKey(const ValueKey('sync-pairing-backup-skip')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('sync-pairing-complete-ok')),
        );
        await tester.pumpAndSettle();

        expect(probedEndpoint, Uri.parse('https://sync.example.test/'));
        expect(
          await harness.repos.settings.get('sync_endpoint'),
          'https://sync.example.test/',
        );
        expect(
          find.text('Syncing with a custom server: sync.example.test'),
          findsOneWidget,
        );
      });

      testWidgets(
        'a transport failure while creating is reported, not left to crash '
        'the button callback',
        (tester) async {
          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
            getStore: ({required previouslyUsed}) async =>
                throw UnimplementedError(),
            createStore: () async =>
                throw const SyncTransportException('simulated timeout'),
          );
          await enableAndOpenPairing(tester);
          await tester.tap(find.byKey(const ValueKey('sync-pairing-create')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-backup-skip')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.text(
              "Device Sync isn't available right now. Check your "
              "connection and try again.",
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'the backup offer never starts automatically: skip exports nothing, '
        'accept exports exactly once (spec §6.14 item 3)',
        (tester) async {
          var exportCalls = 0;
          Future<bool> saver(String json, String name) async {
            exportCalls++;
            return true;
          }

          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
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

      testWidgets(
        'skipping the backup offer exports nothing (spec §6.14 item 3)',
        (tester) async {
          var exportCalls = 0;
          Future<bool> saver(String json, String name) async {
            exportCalls++;
            return true;
          }

          _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
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

          await tester.tap(
            find.byKey(const ValueKey('sync-pairing-backup-skip')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sync-pairing-continue')));
          await tester.pumpAndSettle();

          expect(exportCalls, 0);
        },
      );

      testWidgets('a rapid double tap on backup accept starts only one export '
          '(spec §6.14 item 3)', (tester) async {
        var exportCalls = 0;
        final gate = Completer<bool>();
        Future<bool> saver(String json, String name) {
          exportCalls++;
          return gate.future;
        }

        _pairingProbeFactory = (syncId, endpoint) => SyncPairingProbe(
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

        final accept = find.byKey(const ValueKey('sync-pairing-backup-accept'));
        await tester.tap(accept);
        await tester.pump();
        // The first export is still pending on `gate`; a second tap while
        // the button is disabled must have no effect.
        await tester.tap(accept);
        await tester.pump();

        gate.complete(true);
        await tester.pumpAndSettle();

        expect(exportCalls, 1);
      });
    });

    group('Replacement dialog (ADR-004/W13 PR2, spec §6.14 item 6)', () {
      Future<void> openExperimental(WidgetTester tester) async {
        await tester.tap(
          find.byKey(const ValueKey('settings-nav-experimental')),
        );
        await tester.pumpAndSettle();
        await _expandSyncSection(tester);
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

      testWidgets(
        'a replacement already pending when the section first builds still '
        'shows the dialog, without a during-build assertion',
        (tester) async {
          final transport = ControllableSyncTransport();
          final harness = await _pumpSettings(tester);
          await harness.repos.settings.set('sync_id', 'configured-store-id-y');
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
            passOperation: ({initialStore}) async =>
                const SyncPassResult(SyncPassStatus.replacementRequired),
          );
          addTearDown(_syncCoordinator!.dispose);
          controller.attachCoordinator(_syncCoordinator);

          // Make the decision pending before DeviceSyncSection has ever been
          // built for this controller — the app is still on Appearance.
          await controller.syncNow();
          expect(controller.replacementPending, isTrue);

          await openExperimental(tester);

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('sync-replacement-dialog')),
            findsOneWidget,
          );
        },
      );
    });
  });
}
