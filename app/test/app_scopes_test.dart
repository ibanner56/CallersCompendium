import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/backup_document.dart'
    show
        defaultBackupCodecRunner,
        runBackupCodecInline,
        runBackupCodecOnIsolate;
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/widgets/app_bootstrap.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/canonical_discouraged_terms_scope.dart';
import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/collection_tile_fields_scope.dart';
import 'package:compendium_app/src/data/colour_dance_theme_scope.dart';
import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/dance_share_fields_scope.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/decimal_turns_scope.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/editor_draft_shutdown_scope.dart';
import 'package:compendium_app/src/data/first_day_of_week_scope.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/data/locale_scope.dart';
import 'package:compendium_app/src/data/matrix_collision_mode_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/program_matrix_column_config_scope.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/data/set_list_color_coding_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/data/sync_writer_lifecycle_scope.dart';
import 'package:compendium_app/src/data/track_history_for_all_callers_scope.dart';
import 'package:compendium_app/src/data/venue_call_count_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_scope.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_app/src/update/update_scope.dart';

import 'support/full_app_harness.dart';

/// Every scope `CompendiumApp` mounts above the navigator, outermost first.
/// Written out by hand (not derived from `_appScopeWrappers`) so removing a
/// wrapper from the production list turns this test red. A new scope is one
/// line in `_appScopeWrappers` plus one line here.
const _appScopeTypes = <Type>[
  RepositoriesScope,
  UpdateScope,
  SyncScope,
  AppThemeScope,
  CustomThemesScope,
  FormationColorsScope,
  DialectLibraryScope,
  ShorthandMappingsScope,
  WalkthroughSnippetLibraryScope,
  ActiveDialectScope,
  RequirePerformedForHistoryScope,
  CollectionTileFieldsScope,
  DanceShareFieldsScope,
  TrackHistoryForAllCallersScope,
  VenueCallCountScope,
  SortIgnoreArticlesScope,
  ReduceMotionScope,
  VerboseFigureRenderingScope,
  CanonicalDiscouragedTermsScope,
  DecimalTurnsScope,
  AggressiveBeatsUpdateScope,
  ConfirmBeforeDeleteScope,
  ColourDanceThemeScope,
  SetListColorCodingScope,
  MatrixCollisionModeScope,
  ProgramMatrixColumnConfigScope,
  DateFormatScope,
  FirstDayOfWeekScope,
  LocaleScope,
  EditorDraftShutdownScope,
  SyncWriterLifecycleScope,
  CollectionFilterScope,
  VenueEntityModeScope,
  ProgramAutoCommitScope,
  CollectionFacetsScope,
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(rootBundle.clear);
  setUp(() => defaultBackupCodecRunner = runBackupCodecInline);
  tearDown(() => defaultBackupCodecRunner = runBackupCodecOnIsolate);

  Future<void> bootApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appData = openTestAppData();
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
  }

  testWidgets('every app scope is mounted above AppBootstrap', (tester) async {
    await bootApp(tester);

    for (final type in _appScopeTypes) {
      expect(find.byType(type), findsOneWidget, reason: '$type is not mounted');
      expect(
        find.ancestor(
          of: find.byType(AppBootstrap),
          matching: find.byType(type),
        ),
        findsOneWidget,
        reason: '$type is not above AppBootstrap',
      );
    }
  });

  testWidgets('scope order is unchanged', (tester) async {
    await bootApp(tester);

    // Outermost first: each scope is an ancestor of the next one.
    for (var i = 0; i < _appScopeTypes.length - 1; i++) {
      expect(
        find.descendant(
          of: find.byType(_appScopeTypes[i]),
          matching: find.byType(_appScopeTypes[i + 1]),
        ),
        findsOneWidget,
        reason: '${_appScopeTypes[i]} must wrap ${_appScopeTypes[i + 1]}',
      );
    }
    expect(
      find.ancestor(
        of: find.byType(CollectionFilterScope),
        matching: find.byType(SyncWriterLifecycleScope),
      ),
      findsOneWidget,
    );
  });
}
