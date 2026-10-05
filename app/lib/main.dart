import 'dart:async';
import 'dart:io' show Directory, File, Platform, exit, stderr;

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;
import 'package:path/path.dart' as p;

import 'l10n/app_localizations.dart';
import 'src/data/active_dialect_scope.dart';
import 'src/data/aggressive_beats_update_scope.dart';
import 'src/data/application_shutdown_controller.dart';
import 'src/data/app_database.dart';
import 'src/data/app_theme_scope.dart';
import 'src/data/archive_intake_labels.dart';
import 'src/data/archive_intake_service.dart';
import 'src/data/backup_io.dart'
    show
        BackupExportTooLargeException,
        BackupSaver,
        backupMegabytes,
        saveBackupToFile;
import 'src/data/backup_reminder.dart';
import 'src/data/backup_service.dart' show exportBackupNow;
import 'src/data/sync_writer_lifecycle_scope.dart';
import 'src/data/callersbox_online.dart';
import 'src/data/collection_filter_scope.dart';
import 'src/data/collection_facets_scope.dart';
import 'src/data/collection_tile_fields_scope.dart';
import 'src/data/dance_share_fields_scope.dart';
import 'src/data/confirm_before_delete_scope.dart';
import 'src/data/contradb_online.dart';
import 'src/data/custom_themes_controller.dart';
import 'src/data/custom_themes_scope.dart';
import 'src/data/date_format_scope.dart';
import 'src/data/dialect_library_controller.dart';
import 'src/data/dialect_library_scope.dart';
import 'src/data/ecd_conversion.dart';
import 'src/data/editor_draft_shutdown_scope.dart';
import 'src/data/first_day_of_week_scope.dart';
import 'src/data/formation_colors_controller.dart';
import 'src/data/formation_colors_scope.dart';
import 'src/data/import_error_labels.dart';
import 'src/data/import_io.dart';
import 'src/data/incoming_file_channel.dart';
import 'src/data/locale_scope.dart';
import 'src/data/migration_error_labels.dart';
import 'src/data/migration_guard.dart';
import 'src/data/online_search.dart';
import 'src/data/online_search_labels.dart';
import 'src/data/persisted_preference.dart';
import 'src/data/colour_dance_theme_scope.dart';
import 'src/data/reduce_motion_scope.dart';
import 'src/data/regional_formats.dart';
import 'src/data/repositories_scope.dart';
import 'src/data/require_performed_for_history_scope.dart';
import 'src/data/track_history_for_all_callers_scope.dart';
import 'src/data/seed_service.dart';
import 'src/data/matrix_collision_mode_scope.dart';
import 'src/data/program_matrix_column_config_scope.dart';
import 'src/data/program_auto_commit_scope.dart';
import 'src/data/set_list_color_coding_scope.dart';
import 'src/data/shorthand_mappings_controller.dart';
import 'src/data/shorthand_mappings_scope.dart';
import 'src/data/single_instance_guard.dart';
import 'src/data/soft_delete_retention.dart';
import 'src/data/sort_ignore_articles_scope.dart';
import 'src/data/verbose_figure_rendering_scope.dart';
import 'src/data/decimal_turns_scope.dart';
import 'src/data/canonical_discouraged_terms_scope.dart';
import 'src/data/display_defaults.dart' show kCanonicalDiscouragedTermsKey;
import 'src/data/venue_entity_mode_scope.dart';
import 'src/data/venue_call_count_scope.dart';
import 'src/data/walkthrough_snippet_library_controller.dart';
import 'src/data/walkthrough_snippet_library_scope.dart';
import 'src/data/window_service.dart';
import 'src/diagnostics/crash_log_store.dart';
import 'src/diagnostics/crash_reporter.dart';
import 'src/diagnostics/error_log.dart';
import 'src/licenses.dart';
import 'src/search/dance_detail_data.dart';
import 'src/screens/app_shell.dart';
import 'src/screens/contradb_program_import_screen.dart';
import 'src/screens/dance_detail_screen.dart';
import 'src/screens/dance_reimport_flow.dart';
import 'src/screens/import_review_screen.dart';
import 'src/screens/settings_screen.dart'
    show
        kAppThemeKey,
        kAutoCommitProgramChangesKey,
        kColourDanceThemeKey,
        kCollectionHiddenFacetsKey,
        kCollectionTileVisibleFieldsKey,
        kEcdConvertPromptDismissedKey,
        kMatrixExactBeatCollisionKey,
        kProgramDanceShareFieldsKey,
        kProgramMatrixColumnsKey,
        kRequirePerformedForHistoryKey,
        kSortIgnoreArticlesKey,
        kTrackHistoryForAllCallersKey,
        kVenueCallCountKey,
        kVenueEntityModeKey;
import 'src/theme/app_theme.dart';
import 'src/app_metadata.dart';
import 'src/sync/sync_controller.dart';
import 'src/sync/sync_coordinator.dart';
import 'src/sync/sync_network.dart';
import 'src/sync/sync_scope.dart';
import 'src/sync/sync_runtime.dart';
import 'src/update/update_controller.dart';
import 'src/update/update_scope.dart';
import 'src/widgets/app_bootstrap.dart';
import 'src/widgets/ecd_convert_prompt_dialog.dart';
import 'src/widgets/online_import_dialogs.dart';

AppData _defaultAppDataFactory() => AppData(openAppDatabase());

const MethodChannel _applicationTerminationChannel = MethodChannel(
  'is.banner.callerscompendium/application_lifecycle',
);
const String _requestApplicationShutdownMethod = 'requestApplicationShutdown';

Future<ResetResult> _resetDatabaseFile(File dbFile) =>
    performReset(dbFile: dbFile, keepPath: true);

Future<void> main() async {
  // Install the local, offline crash log and global error-capture stack (issue
  // #458) as the very first thing, so an error during startup itself is still
  // recorded. [CrashLogStore] resolves its directory lazily on first write, so
  // constructing the reporter before the binding is initialized is safe, and it
  // gives the zone's error handler (below) something to forward to.
  final crashReporter = CrashReporter(store: CrashLogStore.appSupport());
  // Wrap the whole app in a guarded zone so uncaught *async* errors are
  // captured too (sync framework/engine errors go through the handlers
  // installed by [installGlobalErrorHandlers]).
  runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installGlobalErrorHandlers(crashReporter);
    // Installs the seam every caught, user-facing error (issue #963) reaches
    // the same log the three global handlers above write to — see
    // `error_log.dart` for why this can't be a scoped/InheritedWidget lookup.
    installCaughtErrorLog(crashReporter);
    // #441: On desktop, refuse a second instance BEFORE constructing [AppData]
    // (which opens the on-device database) so two processes can't race the
    // migration / derived-rebuild marker and trip `database is locked`. The
    // guard takes an OS advisory lock in the app's private support directory;
    // if another live instance already holds it, this launch exits before any
    // database connection is opened. Crash-safe: the OS releases the advisory
    // lock when the holder dies, so a crashed prior instance never bricks a
    // relaunch. No-op off desktop (mobile owns single-instance; web has no
    // `dart:io`) and in the headless test harness, which never runs `main`.
    if (DesktopSingleInstance.isSupportedPlatform) {
      final result = await DesktopSingleInstance().acquire();
      if (result == SingleInstanceResult.alreadyRunning) {
        stderr.writeln(
          "Caller's Compendium is already running; focus the existing window. "
          'Exiting this second launch to protect the database.',
        );
        exit(0);
      }
    }
    // Register the bundled font (OFL) and ported-code (fmptools, MIT) license
    // texts so Flutter's showLicensePage — reachable from Settings ▸ About ▸
    // View licenses — includes them.
    registerBundledLicenses();
    // [AppData] is opened once here and handed to [CompendiumApp] (which owns
    // disposal) so we never open the database twice. The database itself opens
    // lazily on first use: the desktop window restore (which reads the persisted
    // frame) and the startup sweep both run inside [CompendiumApp]'s bootstrap
    // future, so a database that won't open (corrupt/locked) surfaces on the
    // AppBootstrap error/retry screen instead of throwing out of `main` before
    // `runApp` — which would leave a blank window with no way to recover.
    final appData = AppData(openAppDatabase());
    final editorDraftShutdownController = EditorDraftShutdownController();
    Future<void> closeApp() => flushEditorDraftsThenClose(
      editorDraftShutdownController,
      appData.close,
    );

    final shutdownController = ApplicationShutdownController(closeApp);
    _applicationTerminationChannel.setMethodCallHandler((
      MethodCall call,
    ) async {
      if (call.method != _requestApplicationShutdownMethod) {
        throw PlatformException(
          code: 'not_implemented',
          // Developer-facing platform-channel error, never shown in the UI.
          message:
              'Unsupported application lifecycle method: ${call.method}', // i18n-ignore
        );
      }
      await shutdownController.close();
    });
    final windowService = WindowService(
      appData.repositories.settings,
      onClose: shutdownController.close,
    );
    // Kept as a variable (not just `.call` torn off) so `_CompendiumAppState`
    // can assign `onBeforeAppliedInvalidation` once its `SyncController`
    // exists — this factory is built here, before that controller does.
    final syncCoordinatorFactory = ConfiguredSyncCoordinatorFactory();
    runApp(
      CompendiumApp(
        appData: appData,
        windowService: windowService,
        applicationShutdownController: shutdownController,
        syncCoordinatorFactory: syncCoordinatorFactory.call,
        productionSyncCoordinatorFactory: syncCoordinatorFactory,
        editorDraftShutdownController: editorDraftShutdownController,
        crashReporter: crashReporter,
        migrationPreflight: (onSnapshotFailure) => runMigrationPreflightForApp(
          runningSchemaVersion: kCompendiumSchemaVersion,
          onSnapshotFailure: onSnapshotFailure,
        ),
        seedInitialCollection: (repos) => SeedService(repos).ensureSeeded(),
        incomingFileChannel: IncomingFileChannel(),
      ),
    );
  }, crashReporter);
}

/// Root widget. The on-device database is initially opened in [main] and
/// injected; the reset flow can replace it with a fresh instance. This widget's
/// bootstrap future ([_startupSequence]) then, in order: restores the desktop
/// window frame (no-op off desktop; forces the DB open), runs any pending schema
/// migration / derived-index back-fill via
/// [CompendiumRepositories.ensureMigrated] (schema-v2 `dance_figures.section`),
/// then performs a startup purge sweep that hard-deletes soft-deleted
/// dances AND programs past the configured retention window
/// ([DanceRepository.purgeDeleted] / [ProgramRepository.purgeDeleted]); the
/// window is user-configurable (30 / 90 days / never — ROADMAP G.4), defaulting
/// to 30 days, and the sweep is skipped entirely when set to never. The app
/// then hands the repositories facade down to the Collection screen via
/// [RepositoriesScope]. The once-per-launch `PRAGMA quick_check` integrity probe
/// ([CompendiumDatabase.quickCheck]) is not part of that gated sequence: it runs
/// after the first ready frame, and a failure only raises a warning banner.
///
/// Startup is gated by [AppBootstrap]: the app shows a loading screen until the
/// bootstrap future completes so no screen reads stale data, and an error
/// screen with retry is shown if any step fails — including a database that
/// won't open during the window restore.
/// Sync-local tables whose writes are not user edits.
const _syncBookkeepingTables = {'published_records', 'id_aliases'};

class CompendiumApp extends StatefulWidget {
  const CompendiumApp({
    super.key,
    required this.appData,
    required this.windowService,
    this.initialRequirePerformedForHistory = false,
    this.migrationPreflight,
    this.integrityCheck,
    this.backupSaver,
    this.crashReporter,
    this.seedInitialCollection,
    this.incomingFileChannel,
    this.incomingFileReader,
    this.incomingFileDeleter,
    this.incomingUrlFetcher,
    this.nowOverride,
    this.appDataFactory = _defaultAppDataFactory,
    this.windowServiceFactory,
    this.databaseFileResolver = resolveDatabaseFile,
    this.databaseResetter = _resetDatabaseFile,
    this.applicationShutdownController,
    this.syncCoordinatorFactory,
    this.productionSyncCoordinatorFactory,
    this.syncNetworkClassifier = const ConnectivityPlusNetworkClassifier(),
    this.syncDebounce = kSyncChangeDebounce,
    this.syncPairingProbeFactory,
    this.editorDraftShutdownController,
  });

  /// The initially opened database + repositories facade. Injected from [main]
  /// so the desktop window frame can be read before `runApp`; the app owns its
  /// disposal and replaces it after a successful reset.
  final AppData appData;

  /// The desktop window service to tear down on dispose (no-op off desktop).
  final WindowService windowService;

  /// Serializes database shutdown requested by AppKit or the desktop window.
  ///
  /// The reset flow swaps this controller's action to its replacement database,
  /// so native termination never closes a stale connection.
  final ApplicationShutdownController? applicationShutdownController;

  /// Constructs the configured Device Sync coordinator after startup has
  /// opened and migrated the database. W13 supplies the endpoint/configuration
  /// surface; omitting this keeps Device Sync disabled.
  final Future<SyncCoordinator?> Function(CompendiumRepositories repositories)?
  syncCoordinatorFactory;

  /// The same production factory as [syncCoordinatorFactory], exposed as an
  /// object (rather than the bound `.call` closure above) so
  /// `_CompendiumAppState` can assign its `onBeforeAppliedInvalidation` hook
  /// once `SyncController` exists (that factory is built in `main`, before
  /// this widget's state does). `null` in every test: they inject their own
  /// [syncCoordinatorFactory] and construct a [SyncCoordinator] directly, so
  /// this hook never applies to them.
  final ConfiguredSyncCoordinatorFactory? productionSyncCoordinatorFactory;

  /// Reports whether the connection is metered for *Sync only on WiFi*
  /// (spec §6.12). Injected in widget tests, where the platform channel does
  /// not answer under fake async.
  final SyncNetworkClassifier syncNetworkClassifier;

  /// The delay between a local change and the automatic pass it triggers.
  /// Widget tests override this to something small; production uses the
  /// documented default.
  final Duration syncDebounce;

  /// Test seam for the pairing screen's create/connect probe; production
  /// builds a live [SyncHttpClient] against the endpoint the form supplies.
  final SyncPairingProbeFactory? syncPairingProbeFactory;

  /// Coordinates final draft persistence before ordinary application
  /// termination. The reset flow deliberately bypasses this coordinator while
  /// closing the database before deleting it.
  final EditorDraftShutdownController? editorDraftShutdownController;

  /// Initial value for the history preference notifier. Exposed for widget
  /// tests that need to verify replacement resets a stale in-memory value.
  @visibleForTesting
  final bool initialRequirePerformedForHistory;

  /// Data-safety preflight run as the *first* bootstrap step, before anything
  /// forces the database open (see `migration_guard.dart`): it guards against
  /// opening a file written by a newer build (throws [DatabaseDowngradeError],
  /// routed to the [AppBootstrap] error screen) and snapshots the file before a
  /// pending upgrade migration. It is handed a [SnapshotFailureDecision] seam so
  /// that, when the pre-migration snapshot fails, it can ask the user whether to
  /// proceed without a backup or abort (issue #442) — the app supplies
  /// [_CompendiumAppState._confirmProceedWithoutBackup], which pumps a blocking
  /// consent dialog on the root navigator. Injected from [main]; left `null` in
  /// tests that don't exercise it (the step is then skipped), mirroring
  /// [integrityCheck].
  final Future<void> Function(SnapshotFailureDecision onSnapshotFailure)?
  migrationPreflight;

  /// Once-per-launch data-integrity probe (`PRAGMA quick_check`), run after the
  /// first frame so a large database does not delay the first screen. Returns
  /// `true` when the database is healthy; `false` triggers a (non-fatal)
  /// corruption warning. Defaults to [CompendiumDatabase.quickCheck]; injected
  /// in tests to exercise the warning path.
  final Future<bool> Function()? integrityCheck;

  /// Save/share seam used by the overdue-backup reminder banner's Export backup
  /// action. Defaults to [saveBackupToFile]; injected in tests so no real
  /// file/share plugin is invoked, mirroring the General settings section.
  final BackupSaver? backupSaver;

  /// Local, offline crash-log sink for global error capture (issue #458). The
  /// startup integrity probe routes a *thrown* failure here so a real
  /// underlying fault is capturable in the field. Injected from [main]; left
  /// `null` in tests that don't exercise it (the routing is then a no-op),
  /// mirroring [integrityCheck].
  final CrashLogSink? crashReporter;

  /// One-time first-run collection seed, run during bootstrap right after the
  /// schema migration so the app never opens to a completely empty collection
  /// (seeds "The Baby Rose" by David Kaynor on a fresh, empty install; a no-op
  /// on every later launch — see [SeedService]). Injected from [main]; left
  /// `null` in tests that don't exercise it (the step is then skipped), so a
  /// seed failure is non-fatal to startup, mirroring [integrityCheck].
  final Future<void> Function(CompendiumRepositories repos)?
  seedInitialCollection;

  /// Delivers a shared [CompendiumArchive] file the OS handed the app (AirDrop /
  /// "Open with" / a share intent), including whether native code staged an
  /// app-owned copy for Dart to remove after intake (issue #298, receive side).
  /// Injected from [main] with a real [IncomingFileChannel]; left `null` in
  /// tests that don't exercise intake, which disables the wiring entirely
  /// (no platform-channel traffic), and can be given a fake channel to drive
  /// intake without the OS.
  final IncomingFileChannel? incomingFileChannel;

  /// Reads the bytes of an incoming shared file for [ArchiveIntakeService].
  /// Defaults to the service's disk reader (which enforces the size cap before
  /// reading). Injected in widget tests so intake runs entirely in-memory with
  /// no real file I/O — real disk reads would be started inside the test's
  /// faked-time zone and never complete. Left `null` in production.
  final ArchiveByteReader? incomingFileReader;

  /// Deletes an app-owned incoming staging copy after intake. Defaults to the
  /// asynchronous filesystem deleter in production; injected in widget tests
  /// so cleanup does not depend on real I/O completing inside fake async.
  @visibleForTesting
  final Future<void> Function(String path)? incomingFileDeleter;

  /// Program-page fetcher handed to the [ContraDbProgramImportScreen] opened
  /// from a shared URL (issue #343), so the screen's auto-fetch can be driven
  /// without real network in widget tests. Defaults to `null` in production,
  /// where the screen uses its own network-backed `fetchImportUrl`.
  final UrlFetcher? incomingUrlFetcher;

  /// Test-only override for the wall clock used by the startup soft-delete
  /// sweep (see [_bootstrap]). Defaults to `null`, i.e. `DateTime.now()` in
  /// production; widget tests inject a fixed instant so the retention-window
  /// purge assertions don't depend on real wall-clock timing (issue #459
  /// de-flake). It only affects the sweep's `now`; it does not touch the
  /// single-snapshot purge design in [DanceRepository.purgeDeleted].
  final DateTime Function()? nowOverride;

  /// Creates a fresh database facade after an in-process reset. The default
  /// opens the on-device database; the seam keeps reset lifecycle tests
  /// independent from platform storage.
  final AppData Function() appDataFactory;

  /// Creates the window service for replacement databases. When omitted,
  /// replacement services use the production [WindowService] constructor.
  final WindowService Function(SettingsRepository settings)?
  windowServiceFactory;

  /// Resolves the database file used by the reset flow.
  final Future<File> Function() databaseFileResolver;

  /// Deletes the database file during reset.
  final Future<ResetResult> Function(File dbFile) databaseResetter;

  @override
  State<CompendiumApp> createState() => _CompendiumAppState();
}

class _CompendiumAppState extends State<CompendiumApp> {
  late AppData _appData;
  late WindowService _windowService;
  late Future<void> _bootstrap;
  late final EditorDraftShutdownController _editorDraftShutdownController;

  /// Determinate progress of the post-migration derived-index rebuild, surfaced
  /// on the [AppBootstrap] loading screen so a large-collection rebuild shows a
  /// progress bar instead of appearing hung (#440). `null` until (and unless) a
  /// rebuild is actually owed; set from [_startupSequence] via the
  /// `onDerivedRebuildProgress` callback that [CompendiumRepositories.ensureMigrated]
  /// forwards to the repository.
  final ValueNotifier<DerivedRebuildProgress?> _derivedRebuildProgress =
      ValueNotifier<DerivedRebuildProgress?>(null);
  final ValueNotifier<Dialect> _dialectNotifier = ValueNotifier(
    Dialect.larksRobins,
  );
  final _themeNotifier = PreferenceNotifier<AppThemeSelection>(
    key: kAppThemeKey,
    defaultValue: AppThemeSelection.system,
    // The stored value is untrusted (issue #609): a non-string or an unknown
    // name degrades to the System default.
    decode: (Object? v) =>
        AppThemeSelection.forName(v is String ? v : null) ??
        AppThemeSelection.system,
    encode: (v) => v.name,
  );
  // The constructor seam only seeds the first frame; reset and load go through
  // the literal `false` default, so this is `late final` to read the widget.
  late final _requirePerformedForHistoryNotifier = PreferenceNotifier<bool>(
    key: kRequirePerformedForHistoryKey,
    defaultValue: false,
    initialValue: widget.initialRequirePerformedForHistory,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _collectionTileFieldsNotifier =
      PreferenceNotifier<Set<CollectionTileField>>(
        key: kCollectionTileVisibleFieldsKey,
        defaultValue: CollectionTileField.all,
        decode: CollectionTileFieldsScope.decodeStored,
        encode: (v) => v.map((f) => f.toJson()).toList(),
      );
  final _danceShareFieldsNotifier = PreferenceNotifier<Set<DanceShareField>>(
    key: kProgramDanceShareFieldsKey,
    defaultValue: DanceShareField.allExceptTunes,
    decode: DanceShareFieldsScope.decodeStored,
    encode: (v) => v.map((f) => f.toJson()).toList(),
  );
  final _collectionHiddenFacetsNotifier = PreferenceNotifier<Set<String>>(
    key: kCollectionHiddenFacetsKey,
    defaultValue: const <String>{},
    decode: CollectionFacetsScope.decodeStored,
    encode: CollectionFacetsScope.encode,
  );
  final _trackHistoryForAllCallersNotifier = PreferenceNotifier<bool>(
    key: kTrackHistoryForAllCallersKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _venueCallCountNotifier = PreferenceNotifier<int>(
    key: kVenueCallCountKey,
    defaultValue: kVenueCallCountDefault,
    decode: venueCallCountFromStored,
    encode: (v) => v,
  );
  final _sortIgnoreArticlesNotifier = PreferenceNotifier<bool>(
    key: kSortIgnoreArticlesKey,
    defaultValue: true,
    decode: (Object? v) => v is bool ? v : true,
    encode: (v) => v,
  );
  // Tri-state (issue #447): null = unset → follow the OS-level Reduce Motion
  // preference (MediaQuery.disableAnimations); true/false = explicit in-app
  // override. Resolved to an effective bool by ReduceMotionScope.of.
  final _reduceMotionNotifier = PreferenceNotifier<bool?>(
    key: kReduceMotionKey,
    defaultValue: null,
    decode: (Object? v) => v is bool ? v : null,
    encode: (v) => v,
  );
  final _verboseFigureRenderingNotifier = PreferenceNotifier<bool>(
    key: kVerboseFigureRenderingKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _canonicalDiscouragedTermsNotifier = PreferenceNotifier<bool>(
    key: kCanonicalDiscouragedTermsKey,
    defaultValue: true,
    decode: (Object? v) => v is bool ? v : true,
    encode: (v) => v,
  );
  final _decimalTurnsNotifier = PreferenceNotifier<bool>(
    key: kDecimalTurnsKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _aggressiveBeatsUpdateNotifier = PreferenceNotifier<bool>(
    key: kAggressiveBeatsUpdateKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _confirmBeforeDeleteNotifier = PreferenceNotifier<bool>(
    key: kConfirmBeforeDeleteKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _venueEntityModeNotifier = PreferenceNotifier<bool>(
    key: kVenueEntityModeKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _autoCommitProgramChangesNotifier = PreferenceNotifier<bool>(
    key: kAutoCommitProgramChangesKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _colourDanceThemeNotifier = PreferenceNotifier<bool>(
    key: kColourDanceThemeKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _setListColorCodingNotifier = PreferenceNotifier<bool>(
    key: kSetListColorCodingKey,
    defaultValue: true,
    decode: (Object? v) => v is bool ? v : true,
    encode: (v) => v,
  );
  final _matrixExactBeatCollisionNotifier = PreferenceNotifier<bool>(
    key: kMatrixExactBeatCollisionKey,
    defaultValue: true,
    decode: (Object? v) => v is bool ? v : true,
    encode: (v) => v,
  );
  final _programMatrixColumnsNotifier = PreferenceNotifier<MatrixColumnConfig>(
    key: kProgramMatrixColumnsKey,
    defaultValue: MatrixColumnConfig.empty,
    // A malformed blob falls back to empty (issue #935).
    decode: (Object? v) =>
        MatrixColumnConfig.tryDecode(v) ?? MatrixColumnConfig.empty,
    encode: (v) => v.toJson(),
  );
  final _dateFormatNotifier = DateFormatPreferenceNotifier();
  final _firstDayOfWeekNotifier = PreferenceNotifier<FirstDayOfWeekPref>(
    key: kFirstDayOfWeekKey,
    defaultValue: FirstDayOfWeekPref.system,
    decode: firstDayOfWeekPrefFromStored,
    encode: (v) => v.token,
  );

  /// The user's chosen app-interface locale; `null` follows the system locale.
  /// Drives `MaterialApp.locale` directly, so it is included in the
  /// [Listenable.merge] below and the app re-renders in the selected language
  /// live when it changes. Loaded (and validated against
  /// [AppLocalizations.supportedLocales]) in [_loadPreferences].
  final _localeNotifier = PreferenceNotifier<Locale?>(
    key: kLocaleKey,
    defaultValue: null,
    // The stored tag is untrusted (OWASP): only a supported locale resolves.
    decode: (Object? v) =>
        localeFromStored(v, AppLocalizations.supportedLocales),
    encode: localeToTag,
  );

  /// App-level "tap a tag → show the Collection filtered to it" coordinator
  /// (issue #414). Provided via [CollectionFilterScope] above the root
  /// navigator so pushed detail routes can reach it.
  final CollectionFilterController _collectionFilterController =
      CollectionFilterController();
  late CustomThemesController _customThemes;
  late FormationColorsController _formationColors;
  late DialectLibraryController _dialectLibrary;

  /// Owns the user's shorthand → figure(s) mappings (issue #420), consulted by
  /// the free-text entry path. Loaded during bootstrap; exposed via
  /// [ShorthandMappingsScope].
  late ShorthandMappingsController _shorthandMappings;

  /// Owns the user's personal walkthrough snippet library (#411): per-figure
  /// step descriptions keyed by figure signature. Loaded during bootstrap;
  /// exposed via [WalkthroughSnippetLibraryScope].
  late WalkthroughSnippetLibraryController _walkthroughSnippets;

  /// Owns the update-check preferences and latest check result (ADR-002 §4/§5).
  /// Loaded during bootstrap; the auto-check (opt-in, default off) is kicked off
  /// once per launch after preferences load.
  late UpdateController _updateController;
  late SyncController _syncController;

  /// Starts a Device Sync pass when the app returns to the foreground (spec
  /// §6.12). The rate limit and the §6.12 gate are the controller's
  /// ([SyncController.onAppResumed]); this only forwards the event. Reads
  /// [_syncController] at the event, so a controller rebuilt by
  /// [_replaceDatabaseBackedServices] is the one asked.
  late final AppLifecycleListener _syncLifecycleListener;
  StreamSubscription<Set<TableUpdate>>? _syncChangeSubscription;
  SyncCoordinator? _syncCoordinator;
  Future<void>? _syncCoordinatorDisposeFuture;
  Future<void>? _syncWriterTail;

  /// `true` for the span between a writer boundary ([_runSyncWriter]) claiming
  /// exclusivity (just before disposing whatever coordinator exists) and its
  /// own `operation()` returning. Cleared in the writer's `finally` *before*
  /// that same `finally` calls the writer's post-operation reconfigure, not
  /// after that reconfigure completes: the hazard this flag closes is a sync
  /// pass running concurrently with the writer's `operation()` itself (e.g. a
  /// backup restore's raw writes), and that hazard is over the instant
  /// `operation()` returns, so the flag does not need to — and does not —
  /// survive into the writer's own reconfigure.
  ///
  /// A sync reconfiguration ([_configureSyncCoordinatorNow]) that resolves its
  /// factory while this is true must not install (or start a pass on) the
  /// coordinator it just built: the writer already owns exclusivity, and the
  /// writer's own `finally` reconfigures once it is safe. Without this check,
  /// a reconfigure still awaiting `factory(...)` when a writer starts finds
  /// nothing to dispose (the coordinator isn't installed yet), so the
  /// writer's operation (e.g. a backup restore) can run concurrently with a
  /// pass the just-resolved factory starts — the race spec §6.11 forbids.
  bool _syncWriterExclusive = false;
  bool _shutdownRequested = false;

  /// Result of the once-per-launch [_runIntegrityCheck]. `false` means the
  /// `PRAGMA quick_check` probe failed, so the ready app surfaces a (non-fatal)
  /// corruption warning. Guarded by [_corruptionBannerShown] so the banner is
  /// only shown once per successful bootstrap.
  bool _dataIntegrityOk = true;
  bool _corruptionBannerShown = false;

  /// Guards the once-per-launch overdue-backup reminder banner (DAT-05). "Not
  /// now" dismisses it for this launch only; nothing is persisted.
  bool _backupReminderShown = false;

  /// `true` when the once-per-launch integrity probe *threw* (as opposed to
  /// returning `false`). Kept distinct so the advisory banner can tell the user
  /// the check couldn't complete rather than reporting a definitive failure
  /// (issue #458). Reset on each bootstrap run.
  bool _integrityProbeThrew = false;

  /// Routes shared-file imports (issue #298) to a screen and surfaces
  /// snackbars: a global navigator + messenger so the incoming-file handler can
  /// open the imported program and report results from outside the widget tree.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Subscription to files delivered while the app is running. Null when no
  /// [CompendiumApp.incomingFileChannel] was injected (intake disabled).
  StreamSubscription<IncomingFile>? _incomingFileSub;

  /// Subscription to URLs shared into the app while it is running (issue #343).
  /// Null when no [CompendiumApp.incomingFileChannel] was injected.
  StreamSubscription<String>? _incomingUrlSub;

  /// App-owned staging paths still being processed. Disposal may race with
  /// validation or the review route, so cleanup is idempotently shared by both
  /// the intake future and [dispose].
  final Set<String> _ownedIncomingPaths = <String>{};
  bool _incomingIntakeDisposed = false;

  bool _incomingDanceImporting = false;

  /// Guards the one-time cold-start file check so it runs only once, after the
  /// ready UI is first shown.
  bool _initialFileChecked = false;

  /// Guards the one-time on-launch ECD-convert prompt so it is considered at
  /// most once per launch — whether or not it ends up shown — after the
  /// ready UI is first shown. See [_maybeShowEcdConvertPrompt].
  bool _ecdConvertPromptChecked = false;

  @override
  void initState() {
    super.initState();
    _editorDraftShutdownController =
        widget.editorDraftShutdownController ?? EditorDraftShutdownController();
    _windowService = widget.windowService;
    _initializeDatabaseBackedServices(widget.appData);
    _syncLifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
    widget.applicationShutdownController?.replaceCloseApp(_closeForShutdown);
    // Listen for files opened while the app is running (AirDrop / "Open with"
    // on an already-launched app). The cold-start file is pulled once the ready
    // UI is shown (see [_buildReadyApp]). No-op when intake is not wired.
    final channel = widget.incomingFileChannel;
    if (channel != null) {
      channel.start();
      _incomingFileSub = channel.files.listen(_handleIncomingFile);
      _incomingUrlSub = channel.urls.listen(_handleIncomingUrl);
    }
    _bootstrap = _runBootstrap();
  }

  void _initializeDatabaseBackedServices(AppData appData) {
    _appData = appData;
    _customThemes = CustomThemesController(_appData.repositories.settings);
    _formationColors = FormationColorsController(
      _appData.repositories.settings,
    );
    // The dialect library owns dialect state; the active dialect flows out
    // through [_dialectNotifier] (read by every existing ActiveDialectScope
    // consumer) via [_syncActiveDialect], so the rest of the app is unchanged.
    _dialectLibrary = DialectLibraryController(_appData.repositories.settings);
    _dialectLibrary.addListener(_syncActiveDialect);
    _shorthandMappings = ShorthandMappingsController(
      _appData.repositories.settings,
    );
    _walkthroughSnippets = WalkthroughSnippetLibraryController(
      _appData.repositories.settings,
    );
    _updateController = UpdateController(
      _appData.repositories.settings,
      onMacosShutdown: _windowService.closeForUpdate,
    );
    _syncController = SyncController(
      settings: _appData.repositories.settings,
      coordinator: () => _syncCoordinator,
      reconfigure: _configureSyncCoordinator,
      syncLocal: _appData.repositories.syncLocal,
      runExclusive: _runSyncWriter,
      pairingProbeFactory: widget.syncPairingProbeFactory,
      classifier: widget.syncNetworkClassifier,
      debounce: widget.syncDebounce,
    );
    // The production coordinator invalidates the main connection's live
    // queries before its pass's own `coordinator.trigger()` call returns
    // (issue: post-apply invalidation scheduling a redundant pass); route
    // that signal through the controller so it can tell its own
    // invalidation apart from a genuine local edit landing in the same
    // instant, rather than scheduling a pointless follow-up pass after every
    // pass that applied anything.
    widget.productionSyncCoordinatorFactory?.onBeforeAppliedInvalidation =
        _syncController.expectSyncAppliedInvalidation;
    // Each attach mints a device ID inside the factory; that write is sync
    // bookkeeping, not an edit that should schedule a second pass.
    widget.productionSyncCoordinatorFactory?.onBeforeDeviceIdMinted =
        _syncController.expectOwnSettingsWrite;
    // Local writes schedule one debounced automatic pass (spec §6.12). Settings
    // rows are reported separately because shareable preferences are sync
    // records too, while the controller's own bookkeeping writes to that table
    // must not re-trigger a pass.
    _syncChangeSubscription = _appData.repositories.db.tableUpdates().listen((
      updates,
    ) {
      final tables = {for (final u in updates) u.table}
        ..removeAll(_syncBookkeepingTables);
      if (tables.isEmpty) return;
      _syncController.notifyLocalChange(
        settingsOnly: tables.length == 1 && tables.contains('settings'),
      );
    });
  }

  void _replaceDatabaseBackedServices() {
    // Controllers retain their SettingsRepository, so they must be recreated
    // with the replacement database rather than reusing closed repositories.
    _resetAppPreferenceNotifiers();
    _windowService.dispose();
    _customThemes.dispose();
    _formationColors.dispose();
    _dialectLibrary.removeListener(_syncActiveDialect);
    _dialectLibrary.dispose();
    _shorthandMappings.dispose();
    _walkthroughSnippets.dispose();
    _updateController.dispose();
    unawaited(_syncChangeSubscription?.cancel());
    _syncController.dispose();
    _syncCoordinator = null;

    final appData = widget.appDataFactory();
    _windowService =
        widget.windowServiceFactory?.call(appData.repositories.settings) ??
        WindowService(
          appData.repositories.settings,
          onClose:
              widget.applicationShutdownController?.close ?? _closeForShutdown,
        );
    _initializeDatabaseBackedServices(appData);
    widget.applicationShutdownController?.replaceCloseApp(_closeForShutdown);
  }

  Future<void> _disposeSyncCoordinator() {
    final existing = _syncCoordinatorDisposeFuture;
    if (existing != null) return existing;

    final coordinator = _syncCoordinator;
    _syncCoordinator = null;
    _syncController.attachCoordinator(null);
    final future = Future<void>.sync(() async {
      await coordinator?.dispose();
    });
    _syncCoordinatorDisposeFuture = future;
    future
        .whenComplete(() => _clearSyncCoordinatorDisposeFuture(future))
        .ignore();
    return future;
  }

  Future<T> _runSyncWriter<T>(Future<T> Function() operation) async {
    final prior = _syncWriterTail;
    final release = Completer<void>();
    final tail = release.future;
    _syncWriterTail = tail;
    try {
      if (prior != null) await prior;
      if (_shutdownRequested) {
        throw StateError('cannot start a database writer during shutdown');
      }
      // Claimed before disposing so a reconfigure whose factory is still
      // resolving cannot install a coordinator (or start a pass) once it
      // returns — it must find `_syncWriterExclusive` true and back off. See
      // the field doc for the race this closes.
      _syncWriterExclusive = true;
      try {
        await _disposeSyncCoordinator();
        if (_shutdownRequested) {
          throw StateError('cannot start a database writer during shutdown');
        }
        return await operation();
      } finally {
        // Released before the writer's own reconfigure so that call — unlike
        // one racing in from outside — is free to install its coordinator.
        _syncWriterExclusive = false;
        if (!_shutdownRequested && mounted) {
          await _configureSyncCoordinator();
        }
      }
    } finally {
      if (!release.isCompleted) release.complete();
      if (identical(_syncWriterTail, tail)) _syncWriterTail = null;
    }
  }

  void _clearSyncCoordinatorDisposeFuture(Future<void> future) {
    if (identical(_syncCoordinatorDisposeFuture, future)) {
      _syncCoordinatorDisposeFuture = null;
    }
  }

  Future<void> _closeForShutdown() async {
    _shutdownRequested = true;
    final writer = _syncWriterTail;
    if (writer != null) await writer;
    await _disposeSyncCoordinator();
    await _closeAppData(_appData);
  }

  Future<void> _closeAppData(AppData appData) async {
    await flushEditorDraftsThenClose(
      _editorDraftShutdownController,
      appData.close,
    );
  }

  /// Every settings-backed preference, in one place: the reset and the load
  /// iterate this list, so a preference listed here cannot be left out of
  /// either. (The dialect is not here: it comes from the dialect library, not a
  /// settings key.)
  late final List<PreferenceNotifier<Object?>> _preferences = [
    _requirePerformedForHistoryNotifier,
    _trackHistoryForAllCallersNotifier,
    _sortIgnoreArticlesNotifier,
    _reduceMotionNotifier,
    _verboseFigureRenderingNotifier,
    _canonicalDiscouragedTermsNotifier,
    _decimalTurnsNotifier,
    _aggressiveBeatsUpdateNotifier,
    _confirmBeforeDeleteNotifier,
    _venueEntityModeNotifier,
    _autoCommitProgramChangesNotifier,
    _colourDanceThemeNotifier,
    _setListColorCodingNotifier,
    _matrixExactBeatCollisionNotifier,
    _themeNotifier,
    _collectionTileFieldsNotifier,
    _danceShareFieldsNotifier,
    _collectionHiddenFacetsNotifier,
    _venueCallCountNotifier,
    _programMatrixColumnsNotifier,
    _dateFormatNotifier,
    _firstDayOfWeekNotifier,
    _localeNotifier,
  ];

  void _resetAppPreferenceNotifiers() {
    _dialectNotifier.value = Dialect.larksRobins;
    for (final p in _preferences) {
      p.reset();
    }
  }

  void _startBootstrap() {
    _corruptionBannerShown = false;
    _backupReminderShown = false;
    // The deferred probe re-runs after this bootstrap succeeds; clear any
    // verdict from a previous database so it cannot raise a stale banner.
    _dataIntegrityOk = true;
    _integrityProbeThrew = false;
    // Let AppBootstrap subscribe before running a replacement bootstrap, so a
    // synchronously failing preflight is still delivered to its recovery UI.
    final bootstrap = Completer<void>();
    _bootstrap = bootstrap.future;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _runBootstrap();
        bootstrap.complete();
      } on Object catch (error, stackTrace) {
        // diagnostics: silent — already logged (main.bootstrap) by
        // `_runBootstrap`; the FutureBuilder surfaces it in the recovery UI.
        bootstrap.completeError(error, stackTrace);
      }
    });
  }

  /// Runs [_startupSequence], recording any failure in the crash log (source
  /// `main.bootstrap`) exactly once before rethrowing it to the recovery UI.
  Future<void> _runBootstrap() async {
    try {
      await _startupSequence();
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'main.bootstrap');
      rethrow;
    }
  }

  /// Mirrors the library's resolved active dialect into [_dialectNotifier] so
  /// every `ActiveDialectScope` consumer sees changes live.
  void _syncActiveDialect() {
    _dialectNotifier.value = _dialectLibrary.active;
  }

  /// Handles a shared [CompendiumArchive] file (issue #298, receive side) the OS
  /// handed the app, routing it through the same import review/consent screen the
  /// manual imports use (issue #432) — nothing is committed until the user
  /// confirms.
  ///
  /// The file is **untrusted input**: [ArchiveIntakeService] enforces the size
  /// cap, validates the archive schema/version, and never throws — a bad file
  /// resolves to a rejection message shown in a snackbar and **writes nothing**
  /// (fail closed). A valid bundle is decoded Dart-side *before* any UI renders,
  /// then handed to [ImportReviewScreen], which previews it, applies per-entity
  /// dispositions, and commits (dances + programs + venues) only on the user's
  /// confirmation — offering a transient Undo afterwards.
  Future<void> _handleIncomingFile(IncomingFile incomingFile) async {
    _trackOwnedIncomingFile(incomingFile);
    if (_incomingIntakeDisposed) {
      await _cleanupOwnedIncomingFile(incomingFile.path);
      return;
    }
    try {
      // Native refused to stage an over-cap file: there is no path to read or
      // delete, so surface the same rejection intake would have produced.
      if (incomingFile.rejection == IncomingFileRejection.tooLarge) {
        if (!mounted) return;
        _showIncomingFileRejection(ArchiveIntakeRejectionReason.tooLarge);
        return;
      }
      final intake = ArchiveIntakeService(readBytes: widget.incomingFileReader);
      final validation = await intake.validateFromPath(incomingFile.path);
      if (!mounted) return;

      if (validation.isRejected) {
        _showIncomingFileRejection(validation.reason!);
        return;
      }

      await _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => ImportReviewScreen(
            sources: defaultImportSources(),
            sharedBundle: SharedBundleImport(
              json: validation.json!,
              archive: validation.archive!,
              entityCount: validation.entityCount,
            ),
          ),
        ),
      );
    } finally {
      await _cleanupOwnedIncomingFile(incomingFile.path);
    }
  }

  void _showIncomingFileRejection(ArchiveIntakeRejectionReason reason) {
    final messenger = _messengerKey.currentState;
    final messengerContext = _messengerKey.currentContext;
    if (messenger == null ||
        messengerContext == null ||
        !messengerContext.mounted) {
      return;
    }
    final l10n = AppLocalizations.of(messengerContext);
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('shared-import-error'),
        content: Text(archiveIntakeRejectionMessage(l10n, reason)),
      ),
    );
  }

  void _trackOwnedIncomingFile(IncomingFile incomingFile) {
    if (incomingFile.appOwned) _ownedIncomingPaths.add(incomingFile.path);
  }

  Future<void> _cleanupOwnedIncomingFile(String path) async {
    if (!_ownedIncomingPaths.remove(path)) return;
    await _deleteIncomingFile(path);
  }

  Future<void> _deleteIncomingFile(String path) async {
    try {
      final deleter = widget.incomingFileDeleter;
      if (deleter != null) {
        await deleter(path);
        return;
      }
      final stagedFile = File(path);
      if (await stagedFile.exists()) {
        await stagedFile.delete();
      }
    } on Object catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'main._handleIncomingFile.cleanup',
      );
    }
  }

  /// Handles a URL shared into the app from the OS share sheet / an
  /// `ACTION_SEND` intent (issue #343) — e.g. a supported ContraDB program or
  /// single-dance page shared from Safari or Chrome.
  ///
  /// The raw string is **untrusted OS input**: any app or user can share any
  /// string here. It is OWASP-validated at this ingest boundary by
  /// [extractSharedContraDbProgramUrl] / [extractSharedDanceLink] — which pull
  /// exactly one `https` URL token out of the payload (Chrome/Samsung Internet
  /// share a bare URL; Firefox shares `"title\nurl"`), then require a
  /// source-allowlisted program or dance-page shape *before* it reaches an
  /// import pipeline. A bad share surfaces a generic snackbar (never echoing
  /// the raw input) and never navigates or writes.
  Future<void> _handleIncomingUrl(String raw) async {
    String? programUrl;
    SharedDanceLink? danceLink;
    try {
      programUrl = extractSharedContraDbProgramUrl(raw);
    } on UrlFetchException {
      try {
        danceLink = extractSharedDanceLink(raw);
      } on UrlFetchException catch (_, danceStackTrace) {
        const error = UrlFetchException(
          UrlFetchFailureReason.unsupportedSharedLink,
        );
        logCaughtError(
          error,
          danceStackTrace,
          source: 'main._handleIncomingUrl',
        );
        if (!mounted) return;
        final navContext = _navigatorKey.currentContext;
        if (navContext == null || !navContext.mounted) return;
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            key: const ValueKey('shared-url-import-error'),
            content: Text(
              importErrorMessage(AppLocalizations.of(navContext), error),
            ),
          ),
        );
        return;
      }
    }

    if (danceLink != null) {
      await _openIncomingDancePreview(danceLink);
      return;
    }

    if (!mounted || programUrl == null) return;
    await _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ContraDbProgramImportScreen(
          initialUrl: programUrl,
          programFetcher: widget.incomingUrlFetcher,
        ),
      ),
    );
  }

  Future<void> _beginIncomingReimport(DanceDetailData detail) async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await DanceReimportCoordinator(
      repos: _appData.repositories,
      callersBox: CallersBoxOnline(jsonFetcher: widget.incomingUrlFetcher),
      contraDb: ContraDbOnline(htmlFetcher: widget.incomingUrlFetcher),
    ).open(context, detail);
  }

  Future<void> _openIncomingDancePreview(SharedDanceLink link) async {
    final navigator = _navigatorKey.currentState;
    final navContext = _navigatorKey.currentContext;
    if (navigator == null || navContext == null || !navContext.mounted) return;

    final OnlineSearchService service;
    final OnlineSearchResultRow result;
    switch (link.source) {
      case SharedDanceSource.callersBox:
        service = CallersBoxOnline(jsonFetcher: widget.incomingUrlFetcher);
        result = OnlineSearchResultRow(
          source: OnlineSource.callersBox,
          id: link.id,
          name: '',
          author: '',
          formation: '',
        );
      case SharedDanceSource.contraDb:
        service = ContraDbOnline(htmlFetcher: widget.incomingUrlFetcher);
        result = OnlineSearchResultRow(
          source: OnlineSource.contraDb,
          id: link.id,
          name: '',
          author: '',
          formation: '',
        );
    }

    showDialog<void>(
      context: navContext,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          key: ValueKey('incoming-dance-preview-loading'),
        ),
      ),
    );

    late OnlinePreview preview;
    try {
      preview = await service.loadPreview(_appData.repositories, result);
    } on UrlFetchException catch (e, stackTrace) {
      // UrlFetchException is log-safe by construction (typed reason + status/
      // timeout fields only, never a URL or raw prose — see
      // `import_io.dart`'s `UrlFetchException` doc), so it's always logged
      // here regardless of whether there's a mounted surface to also show it.
      logCaughtError(e, stackTrace, source: 'main._openIncomingDancePreview');
      if (!mounted || !navContext.mounted) return;
      navigator.pop();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(importErrorMessage(AppLocalizations.of(navContext), e)),
        ),
      );
      return;
    } catch (e, stackTrace) {
      logCaughtErrorTypeOnly(
        e,
        stackTrace,
        source: 'main._openIncomingDancePreview',
      );
      if (!mounted || !navContext.mounted) return;
      navigator.pop();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              navContext,
            ).onlineLoadError(service.source.label),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    navigator.pop();
    final imported = await navigator.push<OnlineImportResult>(
      MaterialPageRoute<OnlineImportResult>(
        builder: (_) => DanceDetailScreen.preview(
          data: preview.detail,
          onImport: () => _importIncomingDance(service, preview),
        ),
      ),
    );
    if (!mounted || !navContext.mounted || imported == null) return;
    final danceId = imported.danceId;
    if (imported.danceCount == 1 && danceId != null) {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DanceDetailScreen(
            danceId: danceId,
            onReimport: _beginIncomingReimport,
          ),
        ),
      );
    }
    if (!mounted || !navContext.mounted) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          onlineImportMessage(AppLocalizations.of(navContext), imported),
        ),
      ),
    );
  }

  Future<void> _importIncomingDance(
    OnlineSearchService service,
    OnlinePreview preview,
  ) async {
    if (_incomingDanceImporting) return;
    _incomingDanceImporting = true;
    final navigator = _navigatorKey.currentState;
    final navContext = _navigatorKey.currentContext;
    if (navigator == null || navContext == null || !navContext.mounted) {
      _incomingDanceImporting = false;
      return;
    }
    final l10n = AppLocalizations.of(navContext);
    try {
      final imported = await resolveAndImportOnline(
        navContext,
        service: service,
        repos: _appData.repositories,
        preview: preview,
        l10n: l10n,
      );
      if (imported == null || !mounted) return; // cancelled, or gone
      if (mounted && navigator.canPop()) navigator.pop(imported);
    } on UrlFetchException catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'main._importIncomingDance');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(importErrorMessage(l10n, e))),
        );
      }
    } catch (e, stackTrace) {
      logCaughtErrorTypeOnly(
        e,
        stackTrace,
        source: 'main._importIncomingDance',
      );
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(l10n.onlineImportError)),
        );
      }
    } finally {
      _incomingDanceImporting = false;
    }
  }

  /// Consent seam for the pre-migration snapshot guard (issue #442). Passed to
  /// [runMigrationPreflight] and invoked *only* when the automatic pre-upgrade
  /// backup fails. Because the preflight is the very first bootstrap step — the
  /// full app UI doesn't exist yet — this pumps a blocking dialog on the root
  /// navigator (over the bootstrap loading screen) that spells out the
  /// data-loss risk and names the likely cause, then returns the user's
  /// explicit choice: `true` to migrate without a backup, `false` (the safe
  /// default) to abort startup. Returning `false` makes the guard throw
  /// [MigrationSnapshotAborted], which the [AppBootstrap] terminal screen
  /// renders — so no schema change happens until the user decides.
  Future<bool> _confirmProceedWithoutBackup(SnapshotFailure failure) async {
    // The root navigator's overlay may not be mounted for the first frame yet
    // (the snapshot can fail before the app has settled). Wait for it; if it
    // never becomes available there is no way to ask, so fail closed.
    await WidgetsBinding.instance.endOfFrame;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;

    final l10n = AppLocalizations.of(context);
    final sentence = snapshotCauseSentence(l10n, failure.cause);
    final causeBlock = sentence.isEmpty ? '' : '\n\n$sentence';
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(l10n.migrationSnapshotConsentTitle),
          content: Text(l10n.migrationSnapshotConsentBody(causeBlock)),
          actions: [
            // Safest choice is the default: Quit, autofocused so a keyboard
            // Enter/confirm aborts rather than proceeding without a backup.
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.migrationSnapshotConsentQuit),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.migrationSnapshotConsentProceed),
            ),
          ],
        ),
      ),
    );
    // A dismissed dialog (blocked above, but belt-and-braces) is the safe
    // default: decline, so the guard fails closed.
    return proceed ?? false;
  }

  Future<void> _startupSequence() async {
    // Data-safety preflight, before anything opens the database (Phase 7):
    // refuse to open a file written by a newer build (routes to the error
    // screen) and snapshot the file before a pending upgrade migration. Runs
    // first so no drift open — including the window restore below — precedes it.
    if (widget.migrationPreflight != null) {
      await widget.migrationPreflight!(_confirmProceedWithoutBackup);
    }
    // Restore the last-known desktop window size/position (no-op off desktop).
    // This reads the persisted frame, which forces the database open, so it
    // runs here — inside the bootstrapped future gated by [AppBootstrap] —
    // rather than before `runApp`. A corrupt/locked database therefore surfaces
    // on the error/retry screen instead of throwing out of `main` and leaving a
    // blank window with no way to recover (Stage 1.6).
    await _windowService.initialize();
    // Reset progress at the start of each attempt (retry re-runs this) so a
    // prior run's final value never lingers on the loading screen.
    _derivedRebuildProgress.value = null;
    await _appData.repositories.ensureMigrated(
      onDerivedRebuildProgress: (progress) =>
          _derivedRebuildProgress.value = progress,
    );
    // First-run seed (issue: "first launch is never empty"): insert exactly one
    // seed dance on a fresh, empty install so the collection is never empty,
    // and never again thereafter (idempotent via a settings latch; safe to skip
    // for an already-populated collection). Best-effort: a failure to load the
    // bundled seed asset must not brick startup, so it is caught and swallowed
    // here (advisory, like the integrity probe below) rather than routed to the
    // error/retry screen. The seam is null in tests that don't exercise it.
    if (widget.seedInitialCollection != null) {
      try {
        await widget.seedInitialCollection!(_appData.repositories);
      } catch (error, stackTrace) {
        // Intentionally non-fatal: the app still opens (empty at worst), and
        // the seed latch stays unset so a later launch can retry. Log the
        // failure (like the backup/export paths) so a missing or invalid
        // bundled asset is diagnosable in the field rather than silent.
        if (kDebugMode) {
          debugPrint('First-run seed failed: $error\n$stackTrace');
        }
        logCaughtError(error, stackTrace, source: 'main.first-run-seed');
      }
    }
    // Resolve the configured soft-delete retention window (ROADMAP G.4),
    // defaulting to 30 days when unset. A `null` window means "never
    // auto-purge", so the startup sweep is skipped entirely.
    //
    // An unreadable setting must not block startup, but it must not fall back to
    // the 30-day default either: a user who chose "never" would then have
    // deleted items purged that they meant to keep. So a failed read skips the
    // sweep for this launch (the same as "never") and is logged.
    Duration? retention;
    try {
      retention = softDeleteRetentionFromStored(
        await _appData.repositories.settings.get(kSoftDeleteRetentionKey),
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'startup.soft_delete_retention_read',
      );
    }
    if (retention != null) {
      // Share one `now` so dances and programs are swept against the same
      // cutoff. Both honor the retention promise shown in their Recently-Deleted
      // screens ("Auto-deleted in N days"); previously only dances were purged,
      // so soft-deleted programs accumulated forever (Stage 1.2).
      final now = (widget.nowOverride ?? () => DateTime.now().toUtc())();
      await _appData.repositories.dances.purgeDeleted(
        now: now,
        retention: retention,
      );
      await _appData.repositories.programs.purgeDeleted(
        now: now,
        retention: retention,
      );
    }
    await _loadPreferences();
    await _configureSyncCoordinator();
    // Kick off the automatic background update check once per launch. It is a
    // no-op unless the user opted in (default off) and never blocks startup or
    // surfaces an error — fire-and-forget per the ADR-002 §5 privacy contract.
    unawaited(_updateController.maybeAutoCheck());
    // Scheduled only here, at the success tail, so a failed attempt that Retry
    // re-runs never queues a probe and each successful bootstrap probes once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runDeferredIntegrityProbe());
    });
  }

  /// Once-per-launch integrity probe (SQLite `PRAGMA quick_check`, per
  /// `docs/design/storage.md` "Durability"), run after the first frame so a
  /// large database does not delay the first screen. A failure is advisory —
  /// the app is already open, and [_buildReadyApp] surfaces a corruption
  /// warning so the user can restore from a backup (Stage 1.7). A thrown probe
  /// (not just a `false` result) is treated as a failed check too, so it warns
  /// rather than routing to the error/retry screen. (This is deliberately
  /// distinct from a DB-open failure during the window restore in
  /// [_startupSequence], which stays fatal.)
  Future<void> _runDeferredIntegrityProbe() async {
    var ok = true;
    var threw = false;
    try {
      ok = await _runIntegrityCheck();
    } catch (error, stackTrace) {
      // The probe *threw* — an I/O error, a locked DB, a corruption-adjacent
      // fault — which is distinct from a probe that merely *returned* false.
      // Log it (mirroring the first-run-seed path) and route it into the local
      // crash-log sink so a real underlying fault is capturable in the field
      // rather than silently collapsing into the generic advisory banner. The
      // `_integrityProbeThrew` flag preserves the "threw" vs "returned false"
      // distinction for that banner.
      ok = false;
      threw = true;
      if (kDebugMode) {
        debugPrint('Integrity probe threw: $error\n$stackTrace');
      }
      logCaughtError(error, stackTrace, source: 'integrity-probe');
    }
    if (!mounted || ok) return;
    // setState so [_buildReadyApp] raises the banner on the next build.
    setState(() {
      _integrityProbeThrew = threw;
      _dataIntegrityOk = false;
    });
  }

  /// Reconfigurations run one at a time, in request order. An enable that is
  /// still resolving its factory cannot then install a coordinator after a
  /// later disable has already returned, and the last request always wins.
  Future<void> _syncConfigureTail = Future<void>.value();

  /// [startPass] is false only for pairing, which runs and observes its own
  /// single pass (see [SyncController.completePairing]). Every other caller
  /// wants the ordinary unawaited app-start trigger at the end of
  /// [_configureSyncCoordinatorNow].
  Future<void> _configureSyncCoordinator({bool startPass = true}) {
    final run = _syncConfigureTail.then(
      (_) => _configureSyncCoordinatorNow(startPass: startPass),
    );
    _syncConfigureTail = run.catchError((Object error, StackTrace stackTrace) {
      logCaughtError(error, stackTrace, source: 'main.sync-configure-queue');
    });
    return run;
  }

  Future<void> _configureSyncCoordinatorNow({required bool startPass}) async {
    await _disposeSyncCoordinator();

    final factory = widget.syncCoordinatorFactory;
    if (factory == null || !mounted || _shutdownRequested) return;
    SyncCoordinator? coordinator;
    try {
      coordinator = await factory(_appData.repositories);
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'main.sync-configure');
      return;
    }
    if (!mounted || _shutdownRequested || _syncWriterExclusive) {
      // A writer boundary (backup restore / shared-archive import) claimed
      // exclusivity while `factory(...)` above was still resolving. Installing
      // this coordinator now — even without starting a pass — would let a
      // concurrent trigger (e.g. "Sync Now") reach it mid-write. Dispose it
      // unused; the writer's own `finally` reconfigures once it is done.
      await coordinator?.dispose();
      return;
    }
    _syncCoordinator = coordinator;
    _syncController.attachCoordinator(coordinator);
    if (coordinator == null || !startPass) return;
    unawaited(_runSyncStart());
  }

  void _onAppResumed() {
    if (_shutdownRequested) return;
    unawaited(_runSyncResume());
  }

  Future<void> _runSyncResume() async {
    try {
      await _syncController.onAppResumed();
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'main.sync-resume');
    }
  }

  Future<void> _runSyncStart() async {
    try {
      await _syncController.onAppStart();
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'main.sync-app-start');
    }
  }

  /// Loads every persisted preference and app-local controller from the
  /// `settings` table into the live notifiers/controllers. Extracted from the
  /// startup sequence so a backup restore (ROADMAP G.5) can re-run exactly this
  /// step — via [reloadFromSettings] — to refresh the UI without a relaunch.
  ///
  /// Two phases: every read is awaited into a local first (each guarded, so one
  /// unreadable key leaves that preference at its default instead of failing
  /// startup), then a single synchronous block resets the notifiers and applies
  /// every decoded value. There is no `await` between the reset and the last
  /// assignment, so no frame is built between them: a restore never renders the
  /// default theme or language while the reads are in flight. (Synchronous
  /// notifier listeners still see the reset values for the instant before the
  /// restored ones are assigned.)
  Future<void> _loadPreferences() async {
    // Phase 1: read everything.
    // Load the persisted dialect library (custom dialects + active-name ref),
    // migrating any legacy single-dialect blob one time. A failure leaves the
    // Larks/Robins default; it is logged because the load can also write.
    await _guardedControllerLoad(
      'startup.dialect_library_load',
      _dialectLibrary.load,
    );
    // Every settings-backed preference (key, default and decoder live on each
    // [PreferenceNotifier]). Every read is guarded, so one unreadable key leaves
    // that preference at its default. The stored values are untrusted: a
    // restored backup can smuggle any JSON type under a key, and each decoder
    // degrades a wrong-typed value to its default. Reduce-motion is tri-state
    // (issue #447, WCAG 2.3.3): a stored `bool` is an explicit in-app override,
    // an absent key leaves it `null` so the scope follows the OS-level Reduce
    // Motion setting.
    final storedPreferences = <Object?>[
      for (final p in _preferences)
        await p.read(_appData.repositories.settings),
    ];
    // Locally-saved custom themes (and the active one), the per-formation label
    // colour overrides (issue #367), the shorthand → figure(s) mappings (issue
    // #420), the personal walkthrough snippet library (#411), the update-check
    // preferences and the sync settings. Each decodes defensively; a failed or
    // corrupt load degrades to that controller's empty/default state.
    await _guardedControllerLoad(
      'startup.custom_themes_load',
      _customThemes.load,
    );
    await _guardedControllerLoad(
      'startup.formation_colors_load',
      _formationColors.load,
    );
    await _guardedControllerLoad(
      'startup.shorthand_mappings_load',
      _shorthandMappings.load,
    );
    await _guardedControllerLoad(
      'startup.walkthrough_snippets_load',
      _walkthroughSnippets.load,
    );
    await _guardedControllerLoad('startup.update_load', _updateController.load);
    await _guardedControllerLoad('startup.sync_load', _syncController.load);
    // Phase 2: reset, then apply every decoded value. Synchronous — no `await`
    // from here to the end of the method.
    _resetAppPreferenceNotifiers();
    _dialectNotifier.value = _dialectLibrary.active;
    for (var i = 0; i < _preferences.length; i++) {
      _preferences[i].applyStored(storedPreferences[i]);
    }
  }

  /// Runs a controller's `load()` so a failure does not fail startup (or a
  /// backup restore). Each controller's `load()` is transactional — it reads
  /// everything before it changes state — so a failure leaves the controller
  /// exactly as it was (its defaults at startup, its pre-restore state on a
  /// restore), never a mix. Logged, not silent: some loads also write (the
  /// dialect library's first-run migration), and a swallowed write failure
  /// should still be diagnosable.
  Future<void> _guardedControllerLoad(
    String source,
    Future<void> Function() load,
  ) async {
    try {
      await load();
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: source);
    }
  }

  /// Re-reads all preferences and app-local controllers from the (freshly
  /// restored) `settings` table so the live UI reflects a backup restore
  /// without a relaunch (ROADMAP G.5). Wired to the backup controls via
  /// [SyncWriterLifecycleScope].
  Future<void> reloadFromSettings() async {
    await _loadPreferences();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _incomingIntakeDisposed = true;
    for (final path in List<String>.of(_ownedIncomingPaths)) {
      unawaited(_cleanupOwnedIncomingFile(path));
    }
    unawaited(_incomingFileSub?.cancel());
    unawaited(_incomingUrlSub?.cancel());
    unawaited(_disposeSyncCoordinator());
    widget.incomingFileChannel?.dispose();
    _dialectNotifier.dispose();
    _themeNotifier.dispose();
    _requirePerformedForHistoryNotifier.dispose();
    _collectionTileFieldsNotifier.dispose();
    _danceShareFieldsNotifier.dispose();
    _collectionHiddenFacetsNotifier.dispose();
    _trackHistoryForAllCallersNotifier.dispose();
    _venueCallCountNotifier.dispose();
    _sortIgnoreArticlesNotifier.dispose();
    _reduceMotionNotifier.dispose();
    _verboseFigureRenderingNotifier.dispose();
    _canonicalDiscouragedTermsNotifier.dispose();
    _decimalTurnsNotifier.dispose();
    _aggressiveBeatsUpdateNotifier.dispose();
    _confirmBeforeDeleteNotifier.dispose();
    _venueEntityModeNotifier.dispose();
    _autoCommitProgramChangesNotifier.dispose();
    _colourDanceThemeNotifier.dispose();
    _setListColorCodingNotifier.dispose();
    _matrixExactBeatCollisionNotifier.dispose();
    _programMatrixColumnsNotifier.dispose();
    _dateFormatNotifier.dispose();
    _firstDayOfWeekNotifier.dispose();
    _localeNotifier.dispose();
    _derivedRebuildProgress.dispose();
    _collectionFilterController.dispose();
    _customThemes.dispose();
    _formationColors.dispose();
    _dialectLibrary.removeListener(_syncActiveDialect);
    _dialectLibrary.dispose();
    _shorthandMappings.dispose();
    _walkthroughSnippets.dispose();
    _updateController.dispose();
    unawaited(_syncChangeSubscription?.cancel());
    _syncLifecycleListener.dispose();
    _syncController.dispose();
    _windowService.dispose();
    super.dispose();
  }

  /// Runs the once-per-launch data-integrity probe, using the injected
  /// [CompendiumApp.integrityCheck] when provided (tests) or the database's
  /// [CompendiumDatabase.quickCheck] otherwise.
  Future<bool> _runIntegrityCheck() =>
      (widget.integrityCheck ?? _appData.db.quickCheck)();

  /// Retry from the generic startup-error screen. Rebuilds the database-backed
  /// world (as the reset path does, minus the file deletion) because a failed
  /// database open is cached by the drift connection and would rethrow on every
  /// later query against the same [AppData].
  Future<void> _retry() async {
    // Retry stays tappable while the teardown below awaits; a second call would
    // replace the replacement `AppData` without closing it and run the startup
    // sequence twice.
    if (_retrying) return;
    _retrying = true;
    try {
      await _retryReopen();
    } finally {
      _retrying = false;
    }
  }

  bool _retrying = false;

  Future<void> _retryReopen() async {
    await _disposeSyncCoordinator();
    try {
      await _appData.close();
    } on Object catch (_) {
      // diagnostics: silent — closing a connection whose open failed rethrows
      // that same cached failure, which `_runBootstrap` already logged; it must
      // not stop Retry from reopening a fresh connection.
    }
    if (!mounted) return;
    setState(() {
      _replaceDatabaseBackedServices();
      _startBootstrap();
    });
  }

  /// Back Up + Reset action for the below-floor recovery screen (issue #841).
  ///
  /// Delegates the fail-closed snapshot logic to [performBackUpAndReset] (see
  /// `migration_guard.dart`): if the snapshot fails, shows a failure dialog and
  /// returns without wiping. Only wipes after the snapshot succeeds and the user
  /// confirms a second dialog.
  Future<void> _backUpAndReset(DatabaseBelowFloorError error) async {
    await WidgetsBinding.instance.endOfFrame;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final l10n = AppLocalizations.of(context);
    final dbFile = await widget.databaseFileResolver();
    final snapshotDir = Directory(
      p.join(dbFile.parent.path, kDatabaseBackupsDirName),
    );

    final result = await performBackUpAndReset(
      dbFile: dbFile,
      snapshotDir: snapshotDir,
      fileVersion: error.fileVersion,
      appVersion: kAppVersion,
      platform:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      bridgeTag: error.bridgeTag,
    );

    if (result is BackUpFailed) {
      if (!context.mounted) return;
      final causeText = snapshotCauseSentence(l10n, result.cause);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(l10n.migrationBelowFloorBackupFailedTitle),
          content: Text(
            causeText.isEmpty
                ? l10n.migrationBelowFloorBackupFailedBody
                : '${l10n.migrationBelowFloorBackupFailedBody} $causeText',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        ),
      );
      return; // Snapshot failed: do NOT wipe.
    }

    // Snapshot written — confirm then wipe, showing where the files were saved.
    if (!context.mounted) return;
    final ready = result as BackUpReady;
    final pathLines = StringBuffer(l10n.migrationBelowFloorResetConfirmBody);
    pathLines
      ..write('\n\n')
      ..write(l10n.migrationBelowFloorBackupSavedAt(ready.snapshotFile.path));
    if (ready.diagnosticLogFile != null) {
      pathLines
        ..write('\n')
        ..write(
          l10n.migrationBelowFloorDiagnosticLogSavedAt(
            ready.diagnosticLogFile!.path,
          ),
        );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(l10n.migrationBelowFloorResetConfirmTitle),
          content: Text(pathLines.toString()),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.migrationBelowFloorBackUpAndReset),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await _doReset(dbFile, l10n);
  }

  /// Reset Only action for the below-floor recovery screen (issue #841).
  ///
  /// The `error` parameter is unused here but matches the callback type
  /// (`void Function(DatabaseBelowFloorError)`) shared with [_backUpAndReset],
  /// so both slots on [AppBootstrap] accept the same signature.
  Future<void> _resetOnly(DatabaseBelowFloorError error) async {
    await WidgetsBinding.instance.endOfFrame;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(l10n.migrationBelowFloorResetConfirmTitle),
          content: Text(l10n.migrationBelowFloorResetOnlyConfirmBody),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.migrationBelowFloorResetOnly),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final dbFile = await widget.databaseFileResolver();
    await _doReset(dbFile, l10n);
  }

  /// Wipes the database file and reopens a fresh one, restarting the bootstrap
  /// sequence so the app opens to a clean state.
  ///
  /// Delegates to [performReset] (see `migration_guard.dart`) for an injectable,
  /// testable deletion seam. On [ResetFailed], the database file is still
  /// present: reopen it and restart bootstrap so the user lands back on the
  /// recovery screen rather than a blank one.
  Future<void> _doReset(File dbFile, AppLocalizations l10n) async {
    // Close the database before deleting its file so the OS (particularly
    // Windows) does not hold a lock that prevents deletion.
    await _disposeSyncCoordinator();
    await _appData.close();
    final result = await widget.databaseResetter(dbFile);
    if (result is ResetFailed) {
      // Deletion failed: the file is intact. Reopen so the app is not left
      // with a closed database, then surface the error.
      if (mounted) {
        setState(() {
          _replaceDatabaseBackedServices();
          _startBootstrap();
        });
        final context = _navigatorKey.currentContext;
        if (context != null && context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.error_outline),
              title: Text(l10n.migrationBelowFloorWipeFailedTitle),
              content: Text(l10n.migrationBelowFloorWipeFailedBody),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.commonOk),
                ),
              ],
            ),
          );
        }
      }
      return;
    }
    if (!mounted) return;
    // Deletion succeeded — reopen a fresh database-backed runtime and restart
    // bootstrap.
    setState(() {
      _replaceDatabaseBackedServices();
      _startBootstrap();
    });
  }

  /// Content shown once the bootstrap future succeeds. When the integrity probe
  /// failed, schedules a one-time dismissible warning banner (the app still
  /// opens — the failure is advisory).
  Widget _buildReadyApp(BuildContext context) {
    if (!_dataIntegrityOk && !_corruptionBannerShown) {
      _corruptionBannerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final l10n = AppLocalizations.of(context);
        messenger.showMaterialBanner(
          MaterialBanner(
            content: Text(
              _integrityProbeThrew
                  ? l10n.startupIntegrityCheckIncomplete
                  : l10n.startupIntegrityCheckFailed,
            ),
            leading: const Icon(Icons.warning_amber_outlined),
            actions: [
              TextButton(
                onPressed: messenger.hideCurrentMaterialBanner,
                child: Text(l10n.updateBannerDismiss),
              ),
            ],
          ),
        );
      });
    }
    // Cold start: the app may have been launched to open a shared file. Pull it
    // once now that the ready UI is shown, so the imported program opens over
    // the app shell (not the loading screen). No-op when intake isn't wired.
    //
    // The ECD-convert prompt is chained strictly *after* this intake settles,
    // in the same post-frame callback, rather than scheduled independently:
    // both flows can push a modal route, and `_openIncomingDancePreview`'s
    // loading spinner is dismissed with a bare `navigator.pop()` that targets
    // whatever is on top of the stack. Racing them let the ECD dialog land on
    // top of that spinner, so its own pop closed the wrong route and orphaned
    // the spinner permanently.
    final channel = widget.incomingFileChannel;
    if (channel != null && !_initialFileChecked) {
      _initialFileChecked = true;
      _ecdConvertPromptChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _runColdStartIntake(channel);
        if (!context.mounted) return;
        await _maybeShowEcdConvertPrompt(context);
        if (!context.mounted) return;
        await _maybeShowBackupReminder(context);
      });
    } else if (!_ecdConvertPromptChecked) {
      _ecdConvertPromptChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _maybeShowEcdConvertPrompt(context);
        if (!context.mounted) return;
        await _maybeShowBackupReminder(context);
      });
    } else if (!_backupReminderShown) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowBackupReminder(context),
      );
    }
    return const AppShell();
  }

  /// Shows, once per launch, a [MaterialBanner] when the user's chosen backup
  /// reminder cadence says a backup is overdue (DAT-05). Runs after the
  /// cold-start intake and ECD prompt settle so it never races a modal route.
  /// A settings read failure shows nothing. "Not now" hides it for this launch
  /// only; no snooze is persisted.
  Future<void> _maybeShowBackupReminder(BuildContext context) async {
    if (_backupReminderShown) return;
    _backupReminderShown = true;
    final bool overdue;
    try {
      final settings = _appData.repositories.settings;
      final cadence = backupReminderCadenceFromStored(
        await settings.get(kBackupReminderCadenceKey),
      );
      if (cadence == BackupReminderCadence.off) return;
      final lastBackupAt = lastBackupAtFromStored(
        await settings.get(kLastBackupAtKey),
      );
      overdue = isBackupOverdue(
        cadence: cadence,
        lastBackupAt: lastBackupAt,
        now: DateTime.now(),
      );
    } on Object {
      // diagnostics: silent — advisory reminder; a settings read failure just
      // shows nothing and must never break startup.
      return;
    }
    if (!overdue || !mounted || !context.mounted) return;
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    final l10n = AppLocalizations.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        key: const ValueKey('backup-reminder-banner'),
        content: Text(l10n.backupReminderBannerText),
        leading: const Icon(Icons.backup_outlined),
        actions: [
          TextButton(
            onPressed: () => _exportFromBackupReminder(l10n),
            child: Text(l10n.backupReminderBannerExport),
          ),
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: Text(l10n.backupReminderBannerNotNow),
          ),
        ],
      ),
    );
  }

  bool _backupReminderExporting = false;

  Future<void> _exportFromBackupReminder(AppLocalizations l10n) async {
    if (_backupReminderExporting) return;
    _backupReminderExporting = true;
    final messenger = _messengerKey.currentState;
    try {
      final delivered = await exportBackupNow(
        _appData.repositories,
        widget.backupSaver ?? saveBackupToFile,
        DateTime.now(),
      );
      if (!delivered || !mounted) return;
      messenger?.hideCurrentMaterialBanner();
      messenger?.showSnackBar(SnackBar(content: Text(l10n.backupExported)));
    } on BackupExportTooLargeException catch (e, st) {
      logCaughtError(e, st, source: 'main.backupReminderExport');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            l10n.backupExportTooLarge(
              backupMegabytes(e.sizeBytes),
              backupMegabytes(e.maxBytes),
            ),
          ),
        ),
      );
    } on Object catch (e, st) {
      logCaughtError(e, st, source: 'main.backupReminderExport');
      messenger?.showSnackBar(SnackBar(content: Text(l10n.backupExportFailed)));
    } finally {
      _backupReminderExporting = false;
    }
  }

  Future<void> _runColdStartIntake(IncomingFileChannel channel) async {
    if (!mounted) return;
    final file = await channel.initialFile();
    if (!mounted) {
      if (file != null) {
        _trackOwnedIncomingFile(file);
        await _cleanupOwnedIncomingFile(file.path);
      }
      return;
    }
    if (file != null) await _handleIncomingFile(file);
    if (!mounted) return;
    // Cold start via a shared URL (issue #343): pull it once too. Files and
    // URLs are mutually exclusive for a single launch, so at most one of
    // these does anything.
    final url = await channel.initialUrl();
    if (mounted && url != null) await _handleIncomingUrl(url);
  }

  /// Offers, once per launch, to convert every live non-[DanceForm.ecd] dance
  /// tagged "ECD" (case-insensitive) to [DanceForm.ecd] and drop the tag.
  /// Skipped when the user has previously opted out via the dialog's "don't
  /// show this again" checkbox, or when nothing in the collection currently
  /// matches. Errors are caught and logged rather than surfaced — this is an
  /// advisory convenience prompt, not part of the startup gate.
  Future<void> _maybeShowEcdConvertPrompt(BuildContext context) async {
    try {
      if (!context.mounted) return;
      final repos = _appData.repositories;
      final dismissed = await repos.settings.get(kEcdConvertPromptDismissedKey);
      if (dismissed == true || !context.mounted) return;
      // Only decides whether to ask: the actual conversion re-resolves both
      // the tag and the candidate set fresh, immediately before writing (see
      // `convertDancesToEcd`), so this snapshot going stale while the dialog
      // is up cannot force a wrong write.
      final hasCandidate = await findEcdConvertCandidates(
        repos,
        await ecdTagIds(repos),
      ).then((candidates) => candidates.isNotEmpty);
      if (!hasCandidate || !context.mounted) return;
      final result = await showEcdConvertPromptDialog(context);
      if (result == null || !context.mounted) return;
      if (result.dontShowAgain) {
        await repos.settings.set(kEcdConvertPromptDismissedKey, true);
      }
      if (!result.convert || !context.mounted) return;
      final now = (widget.nowOverride ?? () => DateTime.now().toUtc())();
      final converted = await convertDancesToEcd(repos, at: now);
      if (!context.mounted || converted == 0) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).startupEcdConvertSnackbar(converted),
            ),
          ),
        );
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'main.ecd-convert-prompt');
    }
  }

  /// The preference/controller scopes mounted above the navigator, outermost
  /// first. `build` folds them (reversed) onto the `MaterialApp.builder` child.
  /// New scopes are added here and to `test/app_scopes_test.dart`.
  List<Widget Function(Widget child)> _appScopeWrappers() => [
    (child) =>
        RepositoriesScope(repositories: _appData.repositories, child: child),
    (child) => UpdateScope(controller: _updateController, child: child),
    (child) => SyncScope(controller: _syncController, child: child),
    (child) => AppThemeScope(notifier: _themeNotifier, child: child),
    (child) => CustomThemesScope(controller: _customThemes, child: child),
    (child) => FormationColorsScope(controller: _formationColors, child: child),
    (child) => DialectLibraryScope(controller: _dialectLibrary, child: child),
    (child) =>
        ShorthandMappingsScope(controller: _shorthandMappings, child: child),
    (child) => WalkthroughSnippetLibraryScope(
      controller: _walkthroughSnippets,
      child: child,
    ),
    (child) => ActiveDialectScope(notifier: _dialectNotifier, child: child),
    (child) => RequirePerformedForHistoryScope(
      notifier: _requirePerformedForHistoryNotifier,
      child: child,
    ),
    (child) => CollectionTileFieldsScope(
      notifier: _collectionTileFieldsNotifier,
      child: child,
    ),
    (child) => DanceShareFieldsScope(
      notifier: _danceShareFieldsNotifier,
      child: child,
    ),
    (child) => TrackHistoryForAllCallersScope(
      notifier: _trackHistoryForAllCallersNotifier,
      child: child,
    ),
    (child) =>
        VenueCallCountScope(notifier: _venueCallCountNotifier, child: child),
    (child) => SortIgnoreArticlesScope(
      notifier: _sortIgnoreArticlesNotifier,
      child: child,
    ),
    (child) => ReduceMotionScope(notifier: _reduceMotionNotifier, child: child),
    (child) => VerboseFigureRenderingScope(
      notifier: _verboseFigureRenderingNotifier,
      child: child,
    ),
    (child) => CanonicalDiscouragedTermsScope(
      notifier: _canonicalDiscouragedTermsNotifier,
      child: child,
    ),
    (child) => DecimalTurnsScope(notifier: _decimalTurnsNotifier, child: child),
    (child) => AggressiveBeatsUpdateScope(
      notifier: _aggressiveBeatsUpdateNotifier,
      child: child,
    ),
    (child) => ConfirmBeforeDeleteScope(
      notifier: _confirmBeforeDeleteNotifier,
      child: child,
    ),
    (child) => ColourDanceThemeScope(
      notifier: _colourDanceThemeNotifier,
      child: child,
    ),
    (child) => SetListColorCodingScope(
      notifier: _setListColorCodingNotifier,
      child: child,
    ),
    (child) => MatrixCollisionModeScope(
      notifier: _matrixExactBeatCollisionNotifier,
      child: child,
    ),
    (child) => ProgramMatrixColumnConfigScope(
      notifier: _programMatrixColumnsNotifier,
      child: child,
    ),
    (child) => DateFormatScope(notifier: _dateFormatNotifier, child: child),
    (child) =>
        FirstDayOfWeekScope(notifier: _firstDayOfWeekNotifier, child: child),
    (child) => LocaleScope(notifier: _localeNotifier, child: child),
    (child) => EditorDraftShutdownScope(
      controller: _editorDraftShutdownController,
      child: child,
    ),
    (child) => SyncWriterLifecycleScope(
      runWrite: _runSyncWriter,
      onRestored: reloadFromSettings,
      child: child,
    ),
    (child) => CollectionFilterScope(
      controller: _collectionFilterController,
      child: child,
    ),
    (child) =>
        VenueEntityModeScope(notifier: _venueEntityModeNotifier, child: child),
    (child) => ProgramAutoCommitScope(
      notifier: _autoCommitProgramChangesNotifier,
      child: child,
    ),
    (child) => CollectionFacetsScope(
      notifier: _collectionHiddenFacetsNotifier,
      child: child,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // The theme depends on two sources — the built-in selection and the active
    // custom theme — and both are MaterialApp properties, so the MaterialApp
    // must rebuild when either changes. The locale is likewise a MaterialApp
    // property (drives `locale:`), so it joins the merge too.
    return ListenableBuilder(
      listenable: Listenable.merge([
        _themeNotifier,
        _customThemes,
        _localeNotifier,
      ]),
      builder: (context, _) {
        final selection = _themeNotifier.value;
        final activeCustom = _customThemes.active;
        // Wiring cases (`ux-modernization.md` §4 / §4A / §4B):
        //  • custom active — a locally-saved custom theme wins over the
        //                    built-in selection; pin its scheme into both slots.
        //  • system        — follow the OS via themeMode, Hearth light/dark.
        //  • highContrast  — force the outline-driven HC theme into both slots.
        //  • pinned        — any other built-in selection pins one concrete
        //                    scheme into both slots.
        final ThemeData lightTheme;
        final ThemeData darkTheme;
        final ThemeMode themeMode;
        if (activeCustom != null) {
          final pinned = AppTheme.fromScheme(activeCustom.toScheme());
          lightTheme = pinned;
          darkTheme = pinned;
          themeMode = activeCustom.themeMode;
        } else {
          themeMode = selection.themeMode;
          if (selection == AppThemeSelection.system) {
            lightTheme = AppTheme.light;
            darkTheme = AppTheme.dark;
          } else if (selection.isHighContrast) {
            lightTheme = AppTheme.highContrast;
            darkTheme = AppTheme.highContrast;
          } else {
            final pinned = AppTheme.fromScheme(selection.scheme!);
            lightTheme = pinned;
            darkTheme = pinned;
          }
        }

        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          locale: _localeNotifier.value,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeListResolutionCallback: (locales, supported) =>
              resolveSystemLocale(locales, supported),
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          theme: lightTheme,
          darkTheme: darkTheme,
          highContrastTheme: AppTheme.highContrast,
          highContrastDarkTheme: AppTheme.highContrast,
          themeMode: themeMode,
          builder: (context, child) => _appScopeWrappers().reversed
              .fold<Widget>(child!, (inner, wrap) => wrap(inner)),
          home: AppBootstrap(
            future: _bootstrap,
            onRetry: _retry,
            onBackUpAndReset: _backUpAndReset,
            onResetOnly: _resetOnly,
            builder: _buildReadyApp,
            rebuildProgress: _derivedRebuildProgress,
          ),
        );
      },
    );
  }
}
