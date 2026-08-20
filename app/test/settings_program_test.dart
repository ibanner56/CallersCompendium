import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/matrix_collision_mode_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/data/track_history_for_all_callers_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/screens/settings/matrix_column_editor_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

/// Pumps the [SettingsScreen] and opens the Program section, wiring every scope
/// the Program pane reads (venues, matrix-collision, and the two calling-history
/// notifiers). The Program section is where issue #935 relocated these controls
/// from General; later phases attach the matrix column editor here.
Future<ValueNotifier<bool>> _pumpProgram(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool initialExactBeatCollision = true,
  bool initialAutoCommit = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final venueMode = ValueNotifier<bool>(false);
  final exactBeatCollision = ValueNotifier<bool>(initialExactBeatCollision);
  final requirePerformed = ValueNotifier<bool>(false);
  final trackAllCallers = ValueNotifier<bool>(false);
  final autoCommit = ValueNotifier<bool>(initialAutoCommit);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(venueMode.dispose);
  addTearDown(exactBeatCollision.dispose);
  addTearDown(requirePerformed.dispose);
  addTearDown(trackAllCallers.dispose);
  addTearDown(autoCommit.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: VenueEntityModeScope(
                notifier: venueMode,
                child: MatrixCollisionModeScope(
                  notifier: exactBeatCollision,
                  child: RequirePerformedForHistoryScope(
                    notifier: requirePerformed,
                    child: TrackHistoryForAllCallersScope(
                      notifier: trackAllCallers,
                      child: ProgramAutoCommitScope(
                        notifier: autoCommit,
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
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-program')));
  await tester.pumpAndSettle();
  return exactBeatCollision;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('Program pane renders all four relocated subsections', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpProgram(tester, repos);

    // Venues
    expect(
      find.byKey(const ValueKey('general-venue-entity-mode')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('general-manage-venues')), findsOneWidget);
    // Programs (matrix collision)
    expect(
      find.byKey(const ValueKey('general-matrix-exact-beat-collision')),
      findsOneWidget,
    );
    // Performance (auto-size)
    expect(
      find.byKey(const ValueKey('settings-auto-size-perform')),
      findsOneWidget,
    );
    // Calling history
    expect(
      find.byKey(const ValueKey('general-require-performed-for-history')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('general-track-history-for-all-callers')),
      findsOneWidget,
    );
  });

  testWidgets('matrix-columns entry point opens the editor screen', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpProgram(tester, repos);

    final entry = find.byKey(
      const ValueKey('program-configure-matrix-columns'),
    );
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(MatrixColumnEditorScreen), findsOneWidget);
  });

  testWidgets('auto-size Perform toggle defaults on and is AT-reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repos = openTestRepositories();

    await _pumpProgram(tester, repos);

    final toggle = find.byKey(const ValueKey('settings-auto-size-perform'));
    expect(toggle, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(toggle).value,
      isTrue,
      reason: 'auto-size defaults on (ROADMAP G.1)',
    );
    // The switch is reachable and toggleable by assistive tech.
    expect(
      tester.getSemantics(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      ),
      isSemantics(
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
        isEnabled: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('program auto-commit toggle defaults off and is AT-reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repos = openTestRepositories();

    await _pumpProgram(tester, repos);

    final toggle = find.byKey(
      const ValueKey('settings-auto-commit-program-changes'),
    );
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(
      tester.getSemantics(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      ),
      isSemantics(
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
        isEnabled: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('toggling program auto-commit persists the setting', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpProgram(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('settings-auto-commit-program-changes')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('settings-auto-commit-program-changes')),
          )
          .value,
      isTrue,
    );
    expect(await repos.settings.get(kAutoCommitProgramChangesKey), isTrue);
  });

  testWidgets('toggling auto-size off persists the setting', (tester) async {
    final repos = openTestRepositories();

    await _pumpProgram(tester, repos);

    await tester.tap(find.byKey(const ValueKey('settings-auto-size-perform')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('settings-auto-size-perform')),
          )
          .value,
      isFalse,
    );
    expect(await repos.settings.get(kAutoSizePerformKey), isFalse);
  });

  testWidgets(
    'matrix-collision toggle still round-trips through its notifier',
    (tester) async {
      final repos = openTestRepositories();
      final notifier = await _pumpProgram(tester, repos);

      await tester.tap(
        find.byKey(const ValueKey('general-matrix-exact-beat-collision')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('general-matrix-exact-beat-collision')),
            )
            .value,
        isFalse,
      );
      expect(notifier.value, isFalse);
      expect(await repos.settings.get(kMatrixExactBeatCollisionKey), isFalse);
    },
  );
}
