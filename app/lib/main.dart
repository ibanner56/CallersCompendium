import 'dart:async';
import 'dart:io' show Directory, File, Platform, exit, stderr;

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'l10n/app_localizations.dart';
import 'src/data/active_dialect_scope.dart';
import 'src/data/aggressive_beats_update_scope.dart';
import 'src/data/app_database.dart';
import 'src/data/app_theme_scope.dart';
import 'src/data/archive_intake_labels.dart';
import 'src/data/archive_intake_service.dart';
import 'src/data/backup_controller_scope.dart';
import 'src/data/collection_filter_scope.dart';
import 'src/data/collection_refresh_scope.dart';
import 'src/data/collection_tile_fields_scope.dart';
import 'src/data/confirm_before_delete_scope.dart';
import 'src/data/custom_themes_controller.dart';
import 'src/data/custom_themes_scope.dart';
import 'src/data/date_format_scope.dart';
import 'src/data/dialect_library_controller.dart';
import 'src/data/dialect_library_scope.dart';
import 'src/data/first_day_of_week_scope.dart';
import 'src/data/formation_colors_controller.dart';
import 'src/data/formation_colors_scope.dart';
import 'src/data/import_error_labels.dart';
import 'src/data/import_io.dart';
import 'src/data/incoming_file_channel.dart';
import 'src/data/locale_scope.dart';
import 'src/data/migration_error_labels.dart';
import 'src/data/migration_guard.dart';
import 'src/data/programs_refresh_scope.dart';
import 'src/data/colour_dance_theme_scope.dart';
import 'src/data/reduce_motion_scope.dart';
import 'src/data/regional_formats.dart';
import 'src/data/repositories_scope.dart';
import 'src/data/require_performed_for_history_scope.dart';
import 'src/data/track_history_for_all_callers_scope.dart';
import 'src/data/seed_service.dart';
import 'src/data/matrix_collision_mode_scope.dart';
import 'src/data/set_list_color_coding_scope.dart';
import 'src/data/shorthand_mappings_controller.dart';
import 'src/data/shorthand_mappings_scope.dart';
import 'src/data/single_instance_guard.dart';
import 'src/data/soft_delete_retention.dart';
import 'src/data/sort_ignore_articles_scope.dart';
import 'src/data/verbose_figure_rendering_scope.dart';
import 'src/data/decimal_turns_scope.dart';
import 'src/data/venue_entity_mode_scope.dart';
import 'src/data/walkthrough_snippet_library_controller.dart';
import 'src/data/walkthrough_snippet_library_scope.dart';
import 'src/data/window_service.dart';
import 'src/diagnostics/crash_log_store.dart';
import 'src/diagnostics/crash_reporter.dart';
import 'src/diagnostics/error_log.dart';
import 'src/licenses.dart';
import 'src/screens/app_shell.dart';
import 'src/screens/contradb_program_import_screen.dart';
import 'src/screens/import_review_screen.dart';
import 'src/screens/settings_screen.dart'
    show
        kAppThemeKey,
        kColourDanceThemeKey,
        kCollectionTileVisibleFieldsKey,
        kMatrixExactBeatCollisionKey,
        kRequirePerformedForHistoryKey,
        kSortIgnoreArticlesKey,
        kTrackHistoryForAllCallersKey,
        kVenueEntityModeKey;
import 'src/theme/app_theme.dart';
import 'src/app_metadata.dart';
import 'src/update/update_controller.dart';
import 'src/update/update_scope.dart';
import 'src/widgets/app_bootstrap.dart';

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
    // Register the bundled font license texts (OFL) so Flutter's
    // showLicensePage — reachable from Settings ▸ About ▸ View licenses —
    // includes them.
    registerBundledFontLicenses();
    // [AppData] is opened once here and handed to [CompendiumApp] (which owns
    // disposal) so we never open the database twice. The database itself opens
    // lazily on first use: the desktop window restore (which reads the persisted
    // frame) and the startup sweep both run inside [CompendiumApp]'s bootstrap
    // future, so a database that won't open (corrupt/locked) surfaces on the
    // AppBootstrap error/retry screen instead of throwing out of `main` before
    // `runApp` — which would leave a blank window with no way to recover.
    final appData = AppData(openAppDatabase());
    final windowService = WindowService(appData.repositories.settings);
    runApp(
      CompendiumApp(
        appData: appData,
        windowService: windowService,
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

/// Root widget. The on-device database is opened once (in [main]) and injected;
/// this widget's bootstrap future ([_startupSequence]) then, in order: restores
/// the desktop window frame (no-op off desktop; forces the DB open), runs any
/// pending schema migration / derived-index back-fill via
/// [CompendiumRepositories.ensureMigrated] (schema-v2 `dance_figures.section`),
/// runs a fast `PRAGMA quick_check` integrity probe once per launch
/// ([CompendiumDatabase.quickCheck]; a failure warns the user but still opens
/// the app), then performs a startup purge sweep that hard-deletes soft-deleted
/// dances AND programs past the configured retention window
/// ([DanceRepository.purgeDeleted] / [ProgramRepository.purgeDeleted]); the
/// window is user-configurable (30 / 90 days / never — ROADMAP G.4), defaulting
/// to 30 days, and the sweep is skipped entirely when set to never. The app
/// then hands the repositories facade down to the Collection screen via
/// [RepositoriesScope].
///
/// Startup is gated by [AppBootstrap]: the app shows a loading screen until the
/// bootstrap future completes so no screen reads stale data, and an error
/// screen with retry is shown if any step fails — including a database that
/// won't open during the window restore.
class CompendiumApp extends StatefulWidget {
  const CompendiumApp({
    super.key,
    required this.appData,
    required this.windowService,
    this.migrationPreflight,
    this.integrityCheck,
    this.crashReporter,
    this.seedInitialCollection,
    this.incomingFileChannel,
    this.incomingFileReader,
    this.incomingUrlFetcher,
    this.nowOverride,
  });

  /// The already-opened database + repositories facade. Injected from [main]
  /// so the desktop window frame can be read before `runApp`; the app owns its
  /// disposal.
  final AppData appData;

  /// The desktop window service to tear down on dispose (no-op off desktop).
  final WindowService windowService;

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

  /// Fast, once-per-launch data-integrity probe run during bootstrap. Returns
  /// `true` when the database is healthy; `false` triggers a (non-fatal)
  /// corruption warning. Defaults to [CompendiumDatabase.quickCheck]; injected
  /// in tests to exercise the warning path.
  final Future<bool> Function()? integrityCheck;

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

  /// Delivers the path of a shared [CompendiumArchive] file the OS handed the
  /// app (AirDrop / "Open with" / a share intent) so it can be imported and the
  /// restored program auto-opened (issue #298, receive side). Injected from
  /// [main] with a real [IncomingFileChannel]; left `null` in tests that don't
  /// exercise intake, which disables the wiring entirely (no platform-channel
  /// traffic), and can be given a fake channel to drive intake without the OS.
  final IncomingFileChannel? incomingFileChannel;

  /// Reads the bytes of an incoming shared file for [ArchiveIntakeService].
  /// Defaults to the service's disk reader (which enforces the size cap before
  /// reading). Injected in widget tests so intake runs entirely in-memory with
  /// no real file I/O — real disk reads would be started inside the test's
  /// faked-time zone and never complete. Left `null` in production.
  final ArchiveByteReader? incomingFileReader;

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

  @override
  State<CompendiumApp> createState() => _CompendiumAppState();
}

class _CompendiumAppState extends State<CompendiumApp> {
  late final AppData _appData;
  late Future<void> _bootstrap;

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
  final ValueNotifier<AppThemeSelection> _themeNotifier = ValueNotifier(
    AppThemeSelection.system,
  );
  final ValueNotifier<bool> _requirePerformedForHistoryNotifier = ValueNotifier(
    false,
  );
  final ValueNotifier<Set<CollectionTileField>> _collectionTileFieldsNotifier =
      ValueNotifier(CollectionTileField.all);
  final ValueNotifier<bool> _trackHistoryForAllCallersNotifier = ValueNotifier(
    false,
  );
  final ValueNotifier<bool> _sortIgnoreArticlesNotifier = ValueNotifier(true);
  // Tri-state (issue #447): null = unset → follow the OS-level Reduce Motion
  // preference (MediaQuery.disableAnimations); true/false = explicit in-app
  // override. Resolved to an effective bool by ReduceMotionScope.of.
  final ValueNotifier<bool?> _reduceMotionNotifier = ValueNotifier<bool?>(null);
  final ValueNotifier<bool> _verboseFigureRenderingNotifier = ValueNotifier(
    false,
  );
  final ValueNotifier<bool> _decimalTurnsNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _aggressiveBeatsUpdateNotifier = ValueNotifier(
    false,
  );
  final ValueNotifier<bool> _confirmBeforeDeleteNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _venueEntityModeNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _colourDanceThemeNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _setListColorCodingNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _matrixExactBeatCollisionNotifier = ValueNotifier(
    true,
  );
  final ValueNotifier<DateFormatSetting> _dateFormatNotifier = ValueNotifier(
    DateFormatSetting.system,
  );
  final ValueNotifier<FirstDayOfWeekPref> _firstDayOfWeekNotifier =
      ValueNotifier(FirstDayOfWeekPref.system);

  /// The user's chosen app-interface locale; `null` follows the system locale.
  /// Drives `MaterialApp.locale` directly, so it is included in the
  /// [Listenable.merge] below and the app re-renders in the selected language
  /// live when it changes. Loaded (and validated against
  /// [AppLocalizations.supportedLocales]) in [_loadPreferences].
  final ValueNotifier<Locale?> _localeNotifier = ValueNotifier(null);

  /// App-level "the collection changed, reload it" signal (ROADMAP 6.3).
  /// Bumped by the import review flow (reached from Settings) so the live
  /// Collection list re-boots without a relaunch. Exposed via
  /// [CollectionRefreshScope].
  final ValueNotifier<int> _collectionRefreshNotifier = ValueNotifier(0);

  /// App-level "program data changed, reload the program views" signal
  /// (issue #768). Bumped by every screen that writes a program or its slots —
  /// the builder, the summary, the "add to program" sheet, the import routes —
  /// so the Programs list, the summary pane, the Collection's "called N times"
  /// badge and the dance detail screen's calling history all reflect the write
  /// without a relaunch. Exposed via [ProgramsRefreshScope].
  final ValueNotifier<int> _programsRefreshNotifier = ValueNotifier(0);

  /// App-level "tap a tag → show the Collection filtered to it" coordinator
  /// (issue #414). Provided via [CollectionFilterScope] above the root
  /// navigator so pushed detail routes can reach it.
  final CollectionFilterController _collectionFilterController =
      CollectionFilterController();
  late final CustomThemesController _customThemes;
  late final FormationColorsController _formationColors;
  late final DialectLibraryController _dialectLibrary;

  /// Owns the user's shorthand → figure(s) mappings (issue #420), consulted by
  /// the free-text entry path. Loaded during bootstrap; exposed via
  /// [ShorthandMappingsScope].
  late final ShorthandMappingsController _shorthandMappings;

  /// Owns the user's personal walkthrough snippet library (#411): per-figure
  /// step descriptions keyed by figure signature. Loaded during bootstrap;
  /// exposed via [WalkthroughSnippetLibraryScope].
  late final WalkthroughSnippetLibraryController _walkthroughSnippets;

  /// Owns the update-check preferences and latest check result (ADR-002 §4/§5).
  /// Loaded during bootstrap; the auto-check (opt-in, default off) is kicked off
  /// once per launch after preferences load.
  late final UpdateController _updateController;

  /// Result of the once-per-launch [_runIntegrityCheck]. `false` means the
  /// `PRAGMA quick_check` probe failed, so the ready app surfaces a (non-fatal)
  /// corruption warning. Guarded by [_corruptionBannerShown] so the banner is
  /// only shown once per successful bootstrap.
  bool _dataIntegrityOk = true;
  bool _corruptionBannerShown = false;

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
  StreamSubscription<String>? _incomingFileSub;

  /// Subscription to URLs shared into the app while it is running (issue #343).
  /// Null when no [CompendiumApp.incomingFileChannel] was injected.
  StreamSubscription<String>? _incomingUrlSub;

  /// Guards the one-time cold-start file check so it runs only once, after the
  /// ready UI is first shown.
  bool _initialFileChecked = false;

  @override
  void initState() {
    super.initState();
    _appData = widget.appData;
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
    _updateController = UpdateController(_appData.repositories.settings);
    // Listen for files opened while the app is running (AirDrop / "Open with"
    // on an already-launched app). The cold-start file is pulled once the ready
    // UI is shown (see [_buildReadyApp]). No-op when intake is not wired.
    final channel = widget.incomingFileChannel;
    if (channel != null) {
      channel.start();
      _incomingFileSub = channel.files.listen(_handleIncomingFile);
      _incomingUrlSub = channel.urls.listen(_handleIncomingUrl);
    }
    _bootstrap = _startupSequence();
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
  Future<void> _handleIncomingFile(String path) async {
    final intake = ArchiveIntakeService(readBytes: widget.incomingFileReader);
    final validation = await intake.validateFromPath(path);
    if (!mounted) return;

    if (validation.isRejected) {
      final messenger = _messengerKey.currentState;
      final messengerContext = _messengerKey.currentContext;
      if (messenger != null &&
          messengerContext != null &&
          messengerContext.mounted) {
        final l10n = AppLocalizations.of(messengerContext);
        messenger.showSnackBar(
          SnackBar(
            key: const ValueKey('shared-import-error'),
            content: Text(
              archiveIntakeRejectionMessage(l10n, validation.reason!),
            ),
          ),
        );
      }
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
  }

  /// Handles a URL shared into the app from the OS share sheet / an
  /// `ACTION_SEND` intent (issue #343) — e.g. a ContraDB program page shared
  /// from Safari or Chrome.
  ///
  /// The raw string is **untrusted OS input**: any app or user can share any
  /// string here. It is OWASP-validated at this ingest boundary by
  /// [extractSharedContraDbProgramUrl] — which pulls exactly one `https` URL
  /// token out of the payload (Chrome/Samsung Internet share a bare URL;
  /// Firefox shares `"title\nurl"`), then runs the strict
  /// [validateSharedContraDbProgramUrl] (https only, `contradb.com` host
  /// allow-list, `/programs/N` path) — *before* it reaches the import pipeline.
  /// A bad share surfaces a generic snackbar (never echoing the raw input) and
  /// never navigates or writes. A valid share opens
  /// [ContraDbProgramImportScreen] pre-filled + auto-fetching, so the user
  /// reviews the preview before committing — the URL then flows through the
  /// existing hardened `buildContraDbProgramUrl → fetchImportUrl →
  /// parseContraDbProgram → resolveContraDbProgram` pipeline (SSRF-guarded,
  /// #332), which re-validates at fetch time. Defense in depth.
  Future<void> _handleIncomingUrl(String raw) async {
    final String validated;
    try {
      validated = extractSharedContraDbProgramUrl(raw);
    } on UrlFetchException catch (e, stackTrace) {
      // UrlFetchException is log-safe by construction (typed reason + status/
      // timeout fields only, never a URL or raw prose — see
      // `import_io.dart`'s `UrlFetchException` doc), so it's always logged
      // here regardless of whether there's a mounted surface to also show it
      // on (issue #963 — this was the reported failure path: a caught error
      // that reached a snackbar but never the diagnostic log).
      logCaughtError(e, stackTrace, source: 'main._handleIncomingUrl');
      if (!mounted) return;
      // Localize the curated, URL-free failure reason. Use the navigator's
      // context (under MaterialApp's Localizations); if it isn't available yet
      // there is no localized surface to show, so skip silently.
      final navContext = _navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          key: const ValueKey('shared-url-import-error'),
          content: Text(importErrorMessage(AppLocalizations.of(navContext), e)),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ContraDbProgramImportScreen(
          initialUrl: validated,
          programFetcher: widget.incomingUrlFetcher,
        ),
      ),
    );
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
    await widget.windowService.initialize();
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
    // Fast, once-per-launch integrity probe (SQLite `PRAGMA quick_check`, per
    // `docs/design/storage.md` "Durability"). A failure is advisory — the app
    // still opens, but [build] surfaces a corruption warning so the user can
    // restore from a backup (Stage 1.7). A thrown probe (not just a `false`
    // result) is treated as a failed check too, so startup continues and warns
    // rather than blocking the whole app on the error/retry screen. (This is
    // deliberately distinct from a DB-open failure during the window restore
    // above, which stays fatal and routes to the error/retry screen.)
    try {
      _integrityProbeThrew = false;
      _dataIntegrityOk = await _runIntegrityCheck();
    } catch (error, stackTrace) {
      // The probe *threw* — an I/O error, a locked DB, a corruption-adjacent
      // fault — which is distinct from a probe that merely *returned* false.
      // This catch previously swallowed the error with zero diagnostic (issue
      // #458, main.dart callout): log it (mirroring the first-run-seed path
      // above) and route it into the local crash-log sink so a real underlying
      // fault is capturable in the field rather than silently collapsing into
      // the generic advisory banner. The `_integrityProbeThrew` flag preserves
      // the "threw" vs "returned false" distinction for that banner.
      _dataIntegrityOk = false;
      _integrityProbeThrew = true;
      if (kDebugMode) {
        debugPrint('Integrity probe threw: $error\n$stackTrace');
      }
      logCaughtError(error, stackTrace, source: 'integrity-probe');
    }
    // Resolve the configured soft-delete retention window (ROADMAP G.4),
    // defaulting to 30 days when unset. A `null` window means "never
    // auto-purge", so the startup sweep is skipped entirely.
    final retention = softDeleteRetentionFromStored(
      await _appData.repositories.settings.get(kSoftDeleteRetentionKey),
    );
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
    // Kick off the automatic background update check once per launch. It is a
    // no-op unless the user opted in (default off) and never blocks startup or
    // surfaces an error — fire-and-forget per the ADR-002 §5 privacy contract.
    unawaited(_updateController.maybeAutoCheck());
  }

  /// Loads every persisted preference and app-local controller from the
  /// `settings` table into the live notifiers/controllers. Extracted from the
  /// startup sequence so a backup restore (ROADMAP G.5) can re-run exactly this
  /// step — via [reloadFromSettings] — to refresh the UI without a relaunch.
  Future<void> _loadPreferences() async {
    // Load the persisted dialect library (custom dialects + active-name ref),
    // migrating any legacy single-dialect blob one time, then seed the notifier
    // with the resolved active dialect (defaults to Larks/Robins when unset).
    await _dialectLibrary.load();
    _dialectNotifier.value = _dialectLibrary.active;
    // Load the persisted theme selection, defaulting to System when unset.
    // Defensive (issue #609): the stored value is untrusted (a restored backup
    // can smuggle a non-string under this key). Guard with `is String` instead
    // of an unchecked `as String?` cast so a wrong-typed value degrades to the
    // System default rather than throwing here and bricking startup on every
    // subsequent launch.
    final storedTheme = await _appData.repositories.settings
        .get(kAppThemeKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    final themeName = storedTheme is String ? storedTheme : null;
    final selection = AppThemeSelection.forName(themeName);
    if (selection != null) _themeNotifier.value = selection;
    // Load the "require mark-performed for calling history" setting (ROADMAP
    // G.2), defaulting to off (false) when unset.
    final requirePerformed = await _appData.repositories.settings.get(
      kRequirePerformedForHistoryKey,
    );
    if (requirePerformed is bool) {
      _requirePerformedForHistoryNotifier.value = requirePerformed;
    }
    // Load the "track calling history for all callers" setting (issue #583),
    // defaulting to off (false) when unset.
    final trackAllCallers = await _appData.repositories.settings.get(
      kTrackHistoryForAllCallersKey,
    );
    if (trackAllCallers is bool) {
      _trackHistoryForAllCallersNotifier.value = trackAllCallers;
    }
    // Load the "ignore leading articles when sorting" setting, defaulting to
    // on (true) when unset.
    final sortIgnoreArticles = await _appData.repositories.settings.get(
      kSortIgnoreArticlesKey,
    );
    if (sortIgnoreArticles is bool) {
      _sortIgnoreArticlesNotifier.value = sortIgnoreArticles;
    }
    // Load the accessibility toggles (ROADMAP G.7). Reduce-motion is tri-state
    // (issue #447, WCAG 2.3.3): a stored `bool` is an explicit in-app override,
    // while an absent key leaves the notifier `null` so the scope follows the
    // OS-level Reduce Motion preference. Only coerce a genuine `bool` into an
    // override so a missing key (or a read failure, coerced to `null` below)
    // keeps "follow OS". The remaining toggles default to off (false) when
    // unset; a read failure falls back so startup never blocks on a settings
    // hiccup.
    final reduceMotion = await _appData.repositories.settings
        .get(kReduceMotionKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (reduceMotion is bool) _reduceMotionNotifier.value = reduceMotion;
    final verboseFigures = await _appData.repositories.settings
        .get(kVerboseFigureRenderingKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (verboseFigures is bool) {
      _verboseFigureRenderingNotifier.value = verboseFigures;
    }
    // Load the "show turns as decimals" display toggle (#368), off by default
    // when unset. Opt-in, so a read failure or missing key stays off (keeps the
    // fraction-glyph default). Coerced through `is bool` so a garbage stored
    // value can never flip the toggle on.
    final decimalTurns = await _appData.repositories.settings
        .get(kDecimalTurnsKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (decimalTurns is bool) {
      _decimalTurnsNotifier.value = decimalTurns;
    }
    // Load the "aggressively recompute figure beats" toggle (#689), off by
    // default when unset. Opt-in, so a read failure or missing/corrupt stored
    // value keeps today's behavior (only recompute beats while untouched).
    final aggressiveBeatsUpdate = await _appData.repositories.settings
        .get(kAggressiveBeatsUpdateKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (aggressiveBeatsUpdate is bool) {
      _aggressiveBeatsUpdateNotifier.value = aggressiveBeatsUpdate;
    }
    final confirmBeforeDelete = await _appData.repositories.settings
        .get(kConfirmBeforeDeleteKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (confirmBeforeDelete is bool) {
      _confirmBeforeDeleteNotifier.value = confirmBeforeDelete;
    }
    // Load the "venue entity mode" setting, off by default when unset. Opt-in,
    // so a read failure or missing key keeps the simple free-text venue field.
    final venueEntityMode = await _appData.repositories.settings
        .get(kVenueEntityModeKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (venueEntityMode is bool) {
      _venueEntityModeNotifier.value = venueEntityMode;
    }
    // Load the colour-tint easter egg (#307), off by default when unset. It is
    // opt-in, so a read failure or missing key stays off.
    final colourDanceTheme = await _appData.repositories.settings
        .get(kColourDanceThemeKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (colourDanceTheme is bool) {
      _colourDanceThemeNotifier.value = colourDanceTheme;
    } else {
      _colourDanceThemeNotifier.value = false;
    }
    // Load the "colour-code set-list rows" Appearance setting (issue #270),
    // defaulting to on (true) when unset. Defensive: a read failure keeps the
    // on-by-default state so startup never blocks on a settings hiccup.
    final setListColorCoding = await _appData.repositories.settings
        .get(kSetListColorCodingKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    if (setListColorCoding is bool) {
      _setListColorCodingNotifier.value = setListColorCoding;
    }
    // Load the Programs "flag exact beat overlap only" matrix-collision
    // setting (issue #962), defaulting to on (true) when unset. Defensive: a
    // read failure keeps the on-by-default state so startup never blocks on a
    // settings hiccup.
    final matrixExactBeatCollision = await _appData.repositories.settings
        .get(kMatrixExactBeatCollisionKey)
        .catchError((_) => null);
    if (matrixExactBeatCollision is bool) {
      _matrixExactBeatCollisionNotifier.value = matrixExactBeatCollision;
    }
    // Load the regional-format preference (ROADMAP G.8), defaulting to System
    // when unset. Defensive: a read failure or garbage token resolves to the
    // safe System default via the resolver. For the custom variant (#584) the
    // raw pattern is loaded from a second key and validated on use; a
    // missing/over-long/garbage pattern collapses back to System.
    final dateFormat = await _appData.repositories.settings
        .get(kDateFormatKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    final dateFormatCustom = await _appData.repositories.settings
        .get(kDateFormatCustomPatternKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    _dateFormatNotifier.value = dateFormatSettingFromStored(
      dateFormat,
      dateFormatCustom,
    );
    // Load the first-day-of-week preference (ROADMAP G.8), defaulting to System
    // when unset. Defensive: a read failure or garbage token resolves to the
    // safe System default via the resolver.
    final firstDayOfWeek = await _appData.repositories.settings
        .get(kFirstDayOfWeekKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    _firstDayOfWeekNotifier.value = firstDayOfWeekPrefFromStored(
      firstDayOfWeek,
    );
    // Load the app-language preference (ROADMAP G.8). SECURITY (OWASP): the
    // stored tag is untrusted — [localeFromStored] only ever resolves it to a
    // locale that is actually in [AppLocalizations.supportedLocales], and a
    // missing/garbage value falls back to the system locale (`null`) without
    // throwing, so a corrupted setting can never crash startup or select an
    // unsupported locale.
    final locale = await _appData.repositories.settings
        .get(kLocaleKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    _localeNotifier.value = localeFromStored(
      locale,
      AppLocalizations.supportedLocales,
    );
    // Load any locally-saved custom themes and the active one (if set).
    await _customThemes.load();
    // Load the user's per-formation label colour overrides (issue #367).
    await _formationColors.load();
    // Load the user's shorthand → figure(s) mappings (issue #420). Decoded
    // defensively; a corrupt payload degrades to "no mappings".
    await _shorthandMappings.load();
    // Load the user's personal walkthrough snippet library (#411). Decoded
    // defensively; a corrupt payload degrades to "no snippets".
    await _walkthroughSnippets.load();
    // Load the update-check preferences (beta opt-in, auto-check opt-in, and
    // the dismissed banner version), all defaulting to the safe off/none state.
    await _updateController.load();
    // Load the collection tile visible fields preference (issue #767).
    // Stored as a JSON list of CollectionTileField name strings.
    // See CollectionTileFieldsScope.decodeStored for the three-case logic.
    final storedTileFields = await _appData.repositories.settings
        .get(kCollectionTileVisibleFieldsKey)
        .catchError(
          (_) => null,
        ); // diagnostics: silent — startup settings read failed; falls back to the documented default above.
    _collectionTileFieldsNotifier.value =
        CollectionTileFieldsScope.decodeStored(storedTileFields);
  }

  /// Re-reads all preferences and app-local controllers from the (freshly
  /// restored) `settings` table so the live UI reflects a backup restore
  /// without a relaunch (ROADMAP G.5). Wired to the backup controls via
  /// [BackupControllerScope].
  Future<void> reloadFromSettings() async {
    await _loadPreferences();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_incomingFileSub?.cancel());
    unawaited(_incomingUrlSub?.cancel());
    widget.incomingFileChannel?.dispose();
    _dialectNotifier.dispose();
    _themeNotifier.dispose();
    _requirePerformedForHistoryNotifier.dispose();
    _collectionTileFieldsNotifier.dispose();
    _trackHistoryForAllCallersNotifier.dispose();
    _sortIgnoreArticlesNotifier.dispose();
    _reduceMotionNotifier.dispose();
    _verboseFigureRenderingNotifier.dispose();
    _decimalTurnsNotifier.dispose();
    _aggressiveBeatsUpdateNotifier.dispose();
    _confirmBeforeDeleteNotifier.dispose();
    _venueEntityModeNotifier.dispose();
    _colourDanceThemeNotifier.dispose();
    _setListColorCodingNotifier.dispose();
    _matrixExactBeatCollisionNotifier.dispose();
    _dateFormatNotifier.dispose();
    _firstDayOfWeekNotifier.dispose();
    _localeNotifier.dispose();
    _collectionRefreshNotifier.dispose();
    _programsRefreshNotifier.dispose();
    _derivedRebuildProgress.dispose();
    _collectionFilterController.dispose();
    _customThemes.dispose();
    _formationColors.dispose();
    _dialectLibrary.removeListener(_syncActiveDialect);
    _dialectLibrary.dispose();
    _shorthandMappings.dispose();
    _walkthroughSnippets.dispose();
    _updateController.dispose();
    widget.windowService.dispose();
    // dispose() can't be async; explicitly mark the close as fire-and-forget
    // rather than silently dropping an unawaited Future (unawaited_futures).
    unawaited(_appData.close());
    super.dispose();
  }

  /// Runs the once-per-launch data-integrity probe, using the injected
  /// [CompendiumApp.integrityCheck] when provided (tests) or the database's
  /// [CompendiumDatabase.quickCheck] otherwise.
  Future<bool> _runIntegrityCheck() =>
      (widget.integrityCheck ?? _appData.db.quickCheck)();

  void _retry() {
    setState(() {
      _corruptionBannerShown = false;
      _bootstrap = _startupSequence();
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
    final dbFile = await resolveDatabaseFile();
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

    final dbFile = await resolveDatabaseFile();
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
    await _appData.close();
    final result = await performReset(dbFile: dbFile);
    if (result is ResetFailed) {
      // Deletion failed: the file is intact. Reopen so the app is not left
      // with a closed database, then surface the error.
      if (mounted) {
        setState(() {
          _appData = AppData(openAppDatabase());
          _corruptionBannerShown = false;
          _bootstrap = _startupSequence();
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
    // Deletion succeeded — reopen a fresh database and restart bootstrap.
    setState(() {
      _appData = AppData(openAppDatabase());
      _corruptionBannerShown = false;
      _bootstrap = _startupSequence();
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
        messenger.showMaterialBanner(
          MaterialBanner(
            content: Text(
              _integrityProbeThrew
                  ? 'A database integrity check failed to complete, so your '
                        'data could not be verified this launch. If problems '
                        'persist, consider restoring from a backup. Technical '
                        'details were saved to Settings ▸ Diagnostics.'
                  : 'A database integrity check failed. Your local data may be '
                        'corrupt — consider restoring from a backup.',
            ),
            leading: const Icon(Icons.warning_amber_outlined),
            actions: [
              TextButton(
                onPressed: messenger.hideCurrentMaterialBanner,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );
      });
    }
    // Cold start: the app may have been launched to open a shared file. Pull it
    // once now that the ready UI is shown, so the imported program opens over
    // the app shell (not the loading screen). No-op when intake isn't wired.
    final channel = widget.incomingFileChannel;
    if (channel != null && !_initialFileChecked) {
      _initialFileChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final path = await channel.initialFile();
        if (mounted && path != null) await _handleIncomingFile(path);
        if (!mounted) return;
        // Cold start via a shared URL (issue #343): pull it once too. Files and
        // URLs are mutually exclusive for a single launch, so at most one of
        // these does anything.
        final url = await channel.initialUrl();
        if (mounted && url != null) await _handleIncomingUrl(url);
      });
    }
    return const AppShell();
  }

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
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          theme: lightTheme,
          darkTheme: darkTheme,
          highContrastTheme: AppTheme.highContrast,
          highContrastDarkTheme: AppTheme.highContrast,
          themeMode: themeMode,
          builder: (context, child) => RepositoriesScope(
            repositories: _appData.repositories,
            child: UpdateScope(
              controller: _updateController,
              child: AppThemeScope(
                notifier: _themeNotifier,
                child: CustomThemesScope(
                  controller: _customThemes,
                  child: FormationColorsScope(
                    controller: _formationColors,
                    child: DialectLibraryScope(
                      controller: _dialectLibrary,
                      child: ShorthandMappingsScope(
                        controller: _shorthandMappings,
                        child: WalkthroughSnippetLibraryScope(
                          controller: _walkthroughSnippets,
                          child: ActiveDialectScope(
                            notifier: _dialectNotifier,
                            child: RequirePerformedForHistoryScope(
                              notifier: _requirePerformedForHistoryNotifier,
                              child: CollectionTileFieldsScope(
                                notifier: _collectionTileFieldsNotifier,
                                child: TrackHistoryForAllCallersScope(
                                  notifier: _trackHistoryForAllCallersNotifier,
                                  child: SortIgnoreArticlesScope(
                                    notifier: _sortIgnoreArticlesNotifier,
                                    child: ReduceMotionScope(
                                      notifier: _reduceMotionNotifier,
                                      child: VerboseFigureRenderingScope(
                                        notifier:
                                            _verboseFigureRenderingNotifier,
                                        child: DecimalTurnsScope(
                                          notifier: _decimalTurnsNotifier,
                                          child: AggressiveBeatsUpdateScope(
                                            notifier:
                                                _aggressiveBeatsUpdateNotifier,
                                            child: ConfirmBeforeDeleteScope(
                                              notifier:
                                                  _confirmBeforeDeleteNotifier,
                                              child: ColourDanceThemeScope(
                                                notifier:
                                                    _colourDanceThemeNotifier,
                                                child: SetListColorCodingScope(
                                                  notifier:
                                                      _setListColorCodingNotifier,
                                                  child: MatrixCollisionModeScope(
                                                    notifier:
                                                        _matrixExactBeatCollisionNotifier,
                                                    child: DateFormatScope(
                                                      notifier:
                                                          _dateFormatNotifier,
                                                      child: FirstDayOfWeekScope(
                                                        notifier:
                                                            _firstDayOfWeekNotifier,
                                                        child: LocaleScope(
                                                          notifier:
                                                              _localeNotifier,
                                                          child: BackupControllerScope(
                                                            onRestored:
                                                                reloadFromSettings,
                                                            child: CollectionRefreshScope(
                                                              revision:
                                                                  _collectionRefreshNotifier,
                                                              child: ProgramsRefreshScope(
                                                                revision:
                                                                    _programsRefreshNotifier,
                                                                child: CollectionFilterScope(
                                                                  controller:
                                                                      _collectionFilterController,
                                                                  child: VenueEntityModeScope(
                                                                    notifier:
                                                                        _venueEntityModeNotifier,
                                                                    child:
                                                                        child!,
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
              ),
            ),
          ),
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
