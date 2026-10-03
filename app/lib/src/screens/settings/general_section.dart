// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'settings_keys.dart';
import '../../data/sync_writer_lifecycle_scope.dart';
import '../../data/backup_document.dart'
    show
        BackupReadResult,
        decodeBackupOnIsolate,
        decodeBackupSizedOnIsolate,
        defaultBackupCodecRunner;
import '../../data/backup_io.dart';
import '../../data/backup_reminder.dart';
import '../../data/backup_service.dart';
import '../../data/confirm_before_delete_scope.dart';
import '../../data/import_io.dart';
import '../../data/reduce_motion_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/soft_delete_retention.dart';
import '../../data/sort_ignore_articles_scope.dart';
import '../../data/verbose_figure_rendering_scope.dart';
import '../../data/decimal_turns_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/app_spacing.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/section_header.dart';
import '../import_review_screen.dart';
import '../published_collection_navigation.dart';
import '../reparse_custom_figures_screen.dart';

/// The General settings section: app-wide toggles, soft-delete retention,
/// backup/restore, and the import launcher. Owns its async loads + load-race
/// guards and the backup/import test seams.
class GeneralSection extends StatefulWidget {
  const GeneralSection({
    super.key,
    this.backupSaver,
    this.backupPicker,
    this.importPicker,
    this.urlFetcher,
  });

  /// Test seam for delivering an exported backup file; defaults to
  /// [saveBackupToFile] (temp file + OS share sheet).
  final BackupSaver? backupSaver;

  /// Test seam for choosing a backup file to restore; defaults to
  /// [pickBackupFile] (native open-file dialog).
  final BackupPicker? backupPicker;

  /// Test seam for choosing an import file; defaults to [pickImportFile]
  /// (native open-file dialog). Forwarded to [ImportReviewScreen].
  final ImportPicker? importPicker;

  /// Test seam for fetching an import URL; defaults to [fetchImportUrl] (real
  /// HTTP GET). Forwarded to [ImportReviewScreen].
  final UrlFetcher? urlFetcher;

  @override
  State<GeneralSection> createState() => _GeneralSectionState();
}

class _GeneralSectionState extends State<GeneralSection> {
  bool _restoreOperationInFlight = false;
  bool _exportInFlight = false;

  /// Soft-delete retention window (ROADMAP G.4), as the stored `int` day count
  /// (`0` = never auto-purge). `null` = not yet loaded; the view shows the
  /// 30-day default until the read resolves.
  int? _softDeleteRetentionDays;
  bool _softDeleteRetentionRequested = false;
  bool _softDeleteRetentionUserSet = false;
  int _softDeleteRetentionLoadGeneration = 0;

  /// Lazily loads the persisted soft-delete retention window (ROADMAP G.4) the
  /// first time the General section is built. Mirrors [_ensureAutoSizeLoaded]: a
  /// late read must not clobber a selection the user made before it resolved.
  void _ensureSoftDeleteRetentionLoaded(BuildContext context) {
    if (_softDeleteRetentionRequested) return;
    _softDeleteRetentionRequested = true;
    final loadGeneration = ++_softDeleteRetentionLoadGeneration;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kSoftDeleteRetentionKey)
        .then((stored) {
          if (!mounted ||
              loadGeneration != _softDeleteRetentionLoadGeneration ||
              _softDeleteRetentionUserSet) {
            return;
          }
          setState(
            () => _softDeleteRetentionDays = _retentionSelectionFromStored(
              stored,
            ),
          );
        })
        .catchError((_) {
          // diagnostics: silent — retention setting read failed; falls back to built-in default.
          if (!mounted ||
              loadGeneration != _softDeleteRetentionLoadGeneration ||
              _softDeleteRetentionUserSet) {
            return;
          }
          setState(
            () => _softDeleteRetentionDays = kSoftDeleteRetentionDefaultDays,
          );
        });
  }

  /// Invalidates the cached retention read after a restore. Clear the value
  /// immediately so the dropdown shows the built-in default while the fresh
  /// read resolves; the generation guard prevents an older read from winning.
  void _refreshSoftDeleteRetention() {
    if (!mounted) return;
    setState(() {
      _softDeleteRetentionDays = null;
      _softDeleteRetentionRequested = false;
      _softDeleteRetentionUserSet = false;
    });
    _ensureSoftDeleteRetentionLoaded(context);
  }

  /// Maps a persisted retention value to the `int` the dropdown selects (one of
  /// [kSoftDeleteRetentionDayOptions] or [kSoftDeleteRetentionNever]). Reuses
  /// the shared resolver, then snaps any unrecognized day count to the 30-day
  /// default so the dropdown always has a valid selection.
  int _retentionSelectionFromStored(Object? stored) {
    final resolved = softDeleteRetentionFromStored(stored);
    if (resolved == null) return kSoftDeleteRetentionNever;
    final days = resolved.inDays;
    return kSoftDeleteRetentionDayOptions.contains(days)
        ? days
        : kSoftDeleteRetentionDefaultDays;
  }

  Future<void> _onSoftDeleteRetentionChanged(int value) async {
    setState(() {
      _softDeleteRetentionUserSet = true;
      _softDeleteRetentionDays = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kSoftDeleteRetentionKey, value);
  }

  /// Backup-reminder cadence (ROADMAP G.5). `null` = not yet loaded; the view
  /// shows "Off" until the read resolves.
  BackupReminderCadence? _backupCadence;

  /// Timestamp of the last successful backup export, or `null` for "never".
  DateTime? _lastBackupAt;
  bool _backupPrefsRequested = false;

  /// Lazily loads the backup-reminder cadence + last-backup timestamp the first
  /// time the General section is built, mirroring the other lazy reads here.
  void _ensureBackupPrefsLoaded(BuildContext context) {
    if (_backupPrefsRequested) return;
    _backupPrefsRequested = true;
    final settings = RepositoriesScope.of(context).settings;
    settings
        .get(kBackupReminderCadenceKey)
        .then((stored) {
          if (!mounted) return;
          setState(
            () => _backupCadence = backupReminderCadenceFromStored(stored),
          );
        })
        .catchError((_) {
          // diagnostics: silent — backup cadence setting read failed; falls back to Off.
          if (!mounted) return;
          setState(() => _backupCadence = BackupReminderCadence.off);
        });
    settings
        .get(kLastBackupAtKey)
        .then((stored) {
          if (!mounted) return;
          setState(() => _lastBackupAt = lastBackupAtFromStored(stored));
        })
        .catchError(
          (_) {},
        ); // diagnostics: silent — last-backup timestamp read failed; leaves _lastBackupAt null (no user surface).
  }

  Future<void> _onBackupCadenceChanged(BackupReminderCadence cadence) async {
    setState(() => _backupCadence = cadence);
    await RepositoriesScope.of(
      context,
    ).settings.set(kBackupReminderCadenceKey, cadence.token);
  }

  /// Suggested filename for an exported backup, dated (UTC) so backups sort and
  /// are easy to tell apart, e.g. `callers-compendium-backup-2026-07-15.json`.
  String _backupFileName(DateTime when) => '${_backupFileStem(when)}.json';

  String _backupFileStem(DateTime when) {
    final d = when.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'callers-compendium-backup-${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Builds the whole-app backup and hands it to the save/share seam, then
  /// stamps the last-backup time on success.
  ///
  /// The backup is plain JSON wrapped in a SHA-256 integrity container (issue
  /// #536), so a corrupted or altered file fails to restore loudly. If the user
  /// cancels the native save/share dialog, this is a clean no-op: no snackbar,
  /// no stamped time.
  Future<void> _onExportBackup() async {
    if (_exportInFlight) return;
    _exportInFlight = true;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final saver = widget.backupSaver ?? saveBackupToFile;

    // No done/total exists for an export (the encode is a single worker call),
    // so the bar is indeterminate until the saver returns.
    final closeProgress = _showBackupProgress(
      key: const ValueKey('export-progress'),
      idleLabel: l10n.backupExportInProgress,
    );
    try {
      final service = BackupService(repos);
      final now = DateTime.now();
      final json = await service.exportToJson(createdAt: now);

      final delivered = await saver(json, _backupFileName(now));
      closeProgress();
      if (!delivered) return;
      await service.recordBackup(now);
      if (!mounted) return;
      setState(() {
        _backupPrefsRequested = true;
        _lastBackupAt = now.toUtc();
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupExported)));
    } on BackupExportTooLargeException catch (e, st) {
      closeProgress();
      logCaughtError(e, st, source: 'general_section._onExportBackup');
      messenger.showSnackBar(
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
      closeProgress();
      logCaughtError(e, st, source: 'general_section._onExportBackup');
      if (kDebugMode) {
        debugPrint('Backup export failed: $e\n$st');
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupExportFailed)));
    } finally {
      closeProgress();
      _exportInFlight = false;
    }
  }

  /// Opens a non-dismissable progress dialog and returns the (idempotent)
  /// callback that closes it. The dialog is a modal route, so the caller must
  /// close it before showing a snackbar or returning.
  ///
  /// [progress] drives a determinate bar and [progressLabel] its text once it
  /// holds a `(done, total)`; until then (and always when [progress] is null)
  /// the bar is indeterminate and shows [idleLabel].
  VoidCallback _showBackupProgress({
    required Key key,
    required String idleLabel,
    ValueListenable<(int, int)?>? progress,
    String Function(int done, int total)? progressLabel,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BackupProgressDialog(
          key: key,
          progress: progress,
          idleLabel: idleLabel,
          progressLabel: progressLabel,
        ),
      ),
    );
    var closed = false;
    return () {
      if (closed) return;
      closed = true;
      navigator.pop();
    };
  }

  /// Prompts for a backup (file or pasted JSON) behind a destructive-replace
  /// confirmation, applies it, then refreshes the live app so the restore shows
  /// without a relaunch.
  ///
  /// The backup's SHA-256 integrity checksum (issue #536) is verified inside the
  /// restore: a corrupt or altered file is refused with a clean,
  /// non-destructive error and the restore never runs — zero entities written.
  Future<void> _onRestoreBackup() async {
    if (_restoreOperationInFlight) return;
    _restoreOperationInFlight = true;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final picker = widget.backupPicker ?? pickBackupFile;
    final writerLifecycle = SyncWriterLifecycleScope.maybeOf(context);
    final onRestored = writerLifecycle?.onRestored;
    final runWrite = writerLifecycle?.runWrite;
    VoidCallback? closeProgress;

    try {
      final choice = await showDialog<_RestoreChoice>(
        context: context,
        builder: (_) => _RestoreBackupDialog(picker: picker),
      );
      if (choice == null || choice.json.trim().isEmpty || !mounted) return;

      // Shown before the lifecycle wrapper, which may wait for an active sync
      // pass, so the screen never sits unchanged while the restore is pending.
      // Indeterminate while the file is read; determinate from the first
      // `(0, total)` the core restore reports.
      final progress = ValueNotifier<(int, int)?>(null);
      closeProgress = _showBackupProgress(
        key: const ValueKey('restore-progress'),
        idleLabel: l10n.backupRestorePreparing,
        progress: progress,
        progressLabel: l10n.backupRestoreProgress,
      );

      // A file the dialog already decoded is not decoded again; pasted text (or
      // a file Replace was pressed on mid-decode) is decoded here, under the
      // progress dialog. The result is kept for the settings retry below.
      final read =
          choice.read ??
          await decodeBackupOnIsolate(
            choice.json,
            runner: defaultBackupCodecRunner,
          );
      final outcome = await _runRestoreLifecycle(
        runWrite: runWrite,
        operation: () => BackupService(repos).restoreFromJson(
          choice.json,
          decoded: read,
          onProgress: (done, total) => progress.value = (done, total),
        ),
      );
      if (!outcome.applied) {
        closeProgress();
        if (!mounted) return;
        // Distinguish the refusal reasons so the user gets an accurate message:
        // a failed integrity checksum (corrupt/altered file, #536), a
        // valid-but-incomplete backup refused to protect live data (#430), a
        // backup from a newer schema, a backup with no app section (replace
        // would clear settings it never described), or a genuinely unreadable
        // file.
        final String message;
        if (outcome.integrityFailed) {
          message = l10n.backupRestoreIntegrityFailed;
        } else if (outcome.incompleteCore || outcome.newerSchema) {
          message = l10n.backupRestoreIncompatibleVersion;
        } else if (outcome.missingAppSection) {
          message = l10n.backupRestoreMissingAppSection;
        } else {
          message = l10n.backupRestoreInvalidFile;
        }
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      if (onRestored != null) await onRestored();
      closeProgress();
      if (!mounted) return;
      _refreshSoftDeleteRetention();
      // The core content committed and refreshed, but the separate settings
      // apply failed (#608). The restored dances/programs are safe; offer a
      // retry that re-applies ONLY the settings. Use an indefinite-duration
      // snackbar with the retry action so the sole recovery affordance can't
      // vanish after the default few seconds. The message is clean and
      // localized — the raw exception is logged (debug-guarded) inside the
      // service, never shown here (CWE-209).
      if (outcome.settingsFailed) {
        _showSettingsRestoreFailed(messenger, l10n, repos, read, onRestored);
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome.hasErrors
                ? l10n.backupRestoreSkippedProblems(outcome.errors.length)
                : l10n.backupRestored,
          ),
        ),
      );
    } on Object catch (e, st) {
      closeProgress?.call();
      logCaughtError(e, st, source: 'general_section._onRestoreBackup');
      if (kDebugMode) {
        debugPrint('Backup restore failed: $e\n$st');
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreFailed)));
    } finally {
      closeProgress?.call();
      _restoreOperationInFlight = false;
    }
  }

  /// Serializes the database restore with any coordinator-backed sync pass.
  ///
  /// The post-hook intentionally lives in [finally]: an integrity refusal,
  /// settings-apply failure, thrown restore, or a partially successful
  /// pre-hook must all leave the runtime with a usable coordinator.
  Future<T> _runRestoreLifecycle<T>({
    required Future<T> Function() operation,
    SyncWriterCallback? runWrite,
  }) => runWrite?.call(operation) ?? operation();

  /// Shows the retryable "core restored, settings failed" state (#608) as an
  /// indefinite snackbar carrying a "retry settings" action. Kept separate so
  /// the retry can re-show it on a repeat failure. [onRestored] is re-run after
  /// a successful retry so the live dialect/theme/preference notifiers pick up
  /// the now-applied settings.
  void _showSettingsRestoreFailed(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    CompendiumRepositories repos,
    BackupReadResult read,
    Future<void> Function()? onRestored,
  ) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.backupRestoreSettingsFailed),
        duration: const Duration(days: 365),
        action: SnackBarAction(
          label: l10n.backupRestoreSettingsRetryAction,
          onPressed: () {
            unawaited(
              _retrySettingsRestore(messenger, l10n, repos, read, onRestored),
            );
          },
        ),
      ),
    );
  }

  /// Re-applies ONLY the settings portion of the backup (#608 retry path). The
  /// core is never touched. Shows the success confirmation ONLY when the retry
  /// actually applied (`applied && !settingsFailed`); a recurring settings
  /// failure re-shows the retryable snackbar, and an `applied: false` outcome
  /// (a now-fatal/altered envelope — defensive: the captured JSON already
  /// decoded once, so this is not normally reachable) surfaces the matching
  /// integrity/invalid-file error rather than a false "Settings applied."
  Future<void> _retrySettingsRestore(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    CompendiumRepositories repos,
    BackupReadResult read,
    Future<void> Function()? onRestored,
  ) async {
    try {
      final outcome = await BackupService(repos).retryApplySettingsFrom(read);
      // Only refresh when something was actually applied.
      if (outcome.applied && onRestored != null) await onRestored();
      if (!mounted) return;
      if (outcome.applied) _refreshSoftDeleteRetention();
      if (outcome.settingsFailed) {
        _showSettingsRestoreFailed(messenger, l10n, repos, read, onRestored);
        return;
      }
      if (!outcome.applied) {
        // Nothing was written (the backup no longer decodes / failed its
        // integrity checksum). Report the specific error, never a success.
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              outcome.integrityFailed
                  ? l10n.backupRestoreIntegrityFailed
                  : l10n.backupRestoreInvalidFile,
            ),
          ),
        );
        return;
      }
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupRestoreSettingsRetried)),
      );
    } on Object catch (e, st) {
      logCaughtError(e, st, source: 'general_section._retrySettingsRestore');
      if (kDebugMode) debugPrint('Backup settings retry failed: $e\n$st');
      if (!mounted) return;
      _showSettingsRestoreFailed(messenger, l10n, repos, read, onRestored);
    }
  }

  /// Opens the adapter-agnostic import review flow (ROADMAP 6.3), offering the
  /// generic [GenericJsonAdapter] ("Caller's Compendium JSON", default), the
  /// [CallersBoxAdapter] ("The Caller's Box", which resolves a pasted dance URL
  /// or bare id to the `&format=JSON` endpoint before fetching), and the
  /// [ContraDbHtmlAdapter] ("ContraDB", which resolves a pasted dance URL or
  /// bare id to the `contradb.com/dances/N` HTML page and scrapes it). The
  /// screen is fully self-contained (plan → review → commit → undo); the live
  /// Collection now picks up its writes from the database stream directly.
  Future<void> _onImportDances() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportReviewScreen(
          sources: defaultImportSources(),
          picker: widget.importPicker,
          fetcher: widget.urlFetcher,
        ),
      ),
    );
  }

  /// Opens the #417 "re-check custom figures" flow: a local re-parse of
  /// import-gap custom figures that previews upgrades and applies them behind an
  /// explicit confirmation, preserving all dance metadata.
  Future<void> _onReparseCustomFigures() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReparseCustomFiguresScreen(),
      ),
    );
  }

  Future<void> _onPublishedCollections() =>
      pushPublishedCollectionCatalog(context);

  Future<void> _onSortIgnoreArticlesChanged(bool value) async {
    // Same instant-notifier-then-persist pattern: flip the live notifier so the
    // dance list re-sorts immediately, then persist in the background.
    SortIgnoreArticlesScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kSortIgnoreArticlesKey, value);
  }

  Future<void> _onReduceMotionChanged(bool value) async {
    // Same instant-notifier-then-persist pattern (ROADMAP G.7): flip the live
    // notifier so animation-gated widgets rebuild immediately, then persist.
    ReduceMotionScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kReduceMotionKey, value);
  }

  Future<void> _onVerboseFigureRenderingChanged(bool value) async {
    VerboseFigureRenderingScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kVerboseFigureRenderingKey, value);
  }

  Future<void> _onDecimalTurnsChanged(bool value) async {
    DecimalTurnsScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDecimalTurnsKey, value);
  }

  Future<void> _onConfirmBeforeDeleteChanged(bool value) async {
    ConfirmBeforeDeleteScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kConfirmBeforeDeleteKey, value);
  }

  @override
  Widget build(BuildContext context) {
    _ensureSoftDeleteRetentionLoaded(context);
    _ensureBackupPrefsLoaded(context);
    return _GeneralView(
      sortIgnoreArticles: SortIgnoreArticlesScope.of(context),
      onSortIgnoreArticlesChanged: _onSortIgnoreArticlesChanged,
      reduceMotion: ReduceMotionScope.of(context),
      onReduceMotionChanged: _onReduceMotionChanged,
      verboseFigureRendering: VerboseFigureRenderingScope.of(context),
      onVerboseFigureRenderingChanged: _onVerboseFigureRenderingChanged,
      decimalTurns: DecimalTurnsScope.of(context),
      onDecimalTurnsChanged: _onDecimalTurnsChanged,
      confirmBeforeDelete: ConfirmBeforeDeleteScope.of(context),
      onConfirmBeforeDeleteChanged: _onConfirmBeforeDeleteChanged,
      softDeleteRetentionDays:
          _softDeleteRetentionDays ?? kSoftDeleteRetentionDefaultDays,
      onSoftDeleteRetentionChanged: _onSoftDeleteRetentionChanged,
      backupCadence: _backupCadence ?? BackupReminderCadence.off,
      onBackupCadenceChanged: _onBackupCadenceChanged,
      lastBackupAt: _lastBackupAt,
      onExportBackup: _onExportBackup,
      onRestoreBackup: _onRestoreBackup,
      onImportDances: _onImportDances,
      onPublishedCollections: _onPublishedCollections,
      onReparseCustomFigures: _onReparseCustomFigures,
    );
  }
}

/// The General section: app-wide preference switches (ROADMAP G).
///
/// Hosts library, accessibility, deleted-items, import, and backup/restore
/// controls. New app-wide switches are added here as additional
/// [SwitchListTile]s. (Program-facing toggles live in [ProgramSection].)
class _GeneralView extends StatelessWidget {
  const _GeneralView({
    required this.sortIgnoreArticles,
    required this.onSortIgnoreArticlesChanged,
    required this.reduceMotion,
    required this.onReduceMotionChanged,
    required this.verboseFigureRendering,
    required this.onVerboseFigureRenderingChanged,
    required this.decimalTurns,
    required this.onDecimalTurnsChanged,
    required this.confirmBeforeDelete,
    required this.onConfirmBeforeDeleteChanged,
    required this.softDeleteRetentionDays,
    required this.onSoftDeleteRetentionChanged,
    required this.backupCadence,
    required this.onBackupCadenceChanged,
    required this.lastBackupAt,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onImportDances,
    required this.onPublishedCollections,
    required this.onReparseCustomFigures,
  });

  final bool sortIgnoreArticles;
  final ValueChanged<bool> onSortIgnoreArticlesChanged;
  final bool reduceMotion;
  final ValueChanged<bool> onReduceMotionChanged;
  final bool verboseFigureRendering;
  final ValueChanged<bool> onVerboseFigureRenderingChanged;
  final bool decimalTurns;
  final ValueChanged<bool> onDecimalTurnsChanged;
  final bool confirmBeforeDelete;
  final ValueChanged<bool> onConfirmBeforeDeleteChanged;

  /// Current soft-delete retention window as the stored `int` day count
  /// (`0` = never auto-purge — see [kSoftDeleteRetentionNever]).
  final int softDeleteRetentionDays;
  final ValueChanged<int> onSoftDeleteRetentionChanged;

  /// Backup-reminder cadence (ROADMAP G.5).
  final BackupReminderCadence backupCadence;
  final ValueChanged<BackupReminderCadence> onBackupCadenceChanged;

  /// When the last successful backup export happened, or `null` for "never".
  final DateTime? lastBackupAt;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;

  /// Opens the import review flow (ROADMAP 6.3).
  final Future<void> Function() onImportDances;
  final Future<void> Function() onPublishedCollections;

  /// Opens the #417 re-check-custom-figures flow.
  final Future<void> Function() onReparseCustomFigures;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      keyboardDismissBehavior: kTextEntryKeyboardDismiss,
      children: [
        SectionHeader(title: l10n.settingsGeneralLibraryHeader),
        SwitchListTile(
          key: const ValueKey('general-sort-ignore-articles'),
          value: sortIgnoreArticles,
          onChanged: onSortIgnoreArticlesChanged,
          title: Text(l10n.settingsGeneralSortIgnoreArticlesTitle),
          subtitle: Text(l10n.settingsGeneralSortIgnoreArticlesSubtitle),
          isThreeLine: true,
        ),
        SectionHeader(title: l10n.settingsGeneralAccessibilityHeader),
        SwitchListTile(
          key: const ValueKey('general-reduce-motion'),
          value: reduceMotion,
          onChanged: onReduceMotionChanged,
          title: Text(l10n.settingsGeneralReduceMotionTitle),
          subtitle: Text(l10n.settingsGeneralReduceMotionSubtitle),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-verbose-figures'),
          value: verboseFigureRendering,
          onChanged: onVerboseFigureRenderingChanged,
          title: Text(l10n.settingsGeneralVerboseFiguresTitle),
          subtitle: Text(l10n.settingsGeneralVerboseFiguresSubtitle),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-decimal-turns'),
          value: decimalTurns,
          onChanged: onDecimalTurnsChanged,
          title: Text(l10n.settingsGeneralDecimalTurnsTitle),
          subtitle: Text(l10n.settingsGeneralDecimalTurnsSubtitle),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-confirm-before-delete'),
          value: confirmBeforeDelete,
          onChanged: onConfirmBeforeDeleteChanged,
          title: Text(l10n.settingsGeneralConfirmBeforeDeleteTitle),
          subtitle: Text(l10n.settingsGeneralConfirmBeforeDeleteSubtitle),
          isThreeLine: true,
        ),
        SectionHeader(title: l10n.settingsGeneralDeletedItemsHeader),
        ListTile(
          title: Text(l10n.settingsGeneralSoftDeleteRetentionTitle),
          subtitle: Text(l10n.settingsGeneralSoftDeleteRetentionSubtitle),
          isThreeLine: true,
          trailing: DropdownButton<int>(
            key: const ValueKey('general-soft-delete-retention'),
            value: softDeleteRetentionDays,
            onChanged: (value) {
              if (value != null) onSoftDeleteRetentionChanged(value);
            },
            items: [
              for (final days in kSoftDeleteRetentionDayOptions)
                DropdownMenuItem(
                  value: days,
                  child: Text(
                    l10n.settingsGeneralSoftDeleteRetentionDays(days),
                  ),
                ),
              DropdownMenuItem(
                value: kSoftDeleteRetentionNever,
                child: Text(l10n.settingsGeneralSoftDeleteRetentionNever),
              ),
            ],
          ),
        ),
        SectionHeader(title: l10n.settingsGeneralImportHeader),
        ListTile(
          title: Text(l10n.importDances),
          subtitle: Text(l10n.settingsGeneralImportDancesSubtitle),
          isThreeLine: true,
          trailing: OutlinedButton.icon(
            key: const ValueKey('import-dances-button'),
            onPressed: onImportDances,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l10n.settingsGeneralImportEllipsisAction),
          ),
        ),
        ListTile(
          key: const ValueKey('published-collections-button'),
          title: Text(l10n.publishedCollectionsTitle),
          subtitle: Text(l10n.publishedCollectionsDescription),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPublishedCollections,
        ),
        ListTile(
          title: Text(l10n.settingsGeneralReparseCustomFiguresTitle),
          subtitle: Text(l10n.settingsGeneralReparseCustomFiguresSubtitle),
          isThreeLine: true,
          trailing: OutlinedButton.icon(
            key: const ValueKey('reparse-custom-figures-button'),
            onPressed: onReparseCustomFigures,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: Text(l10n.settingsGeneralReparseCustomFiguresAction),
          ),
        ),
        SectionHeader(title: l10n.settingsGeneralBackupRestoreHeader),
        ..._buildBackupSection(context),
      ],
    );
  }

  /// The "Backup & restore" controls (ROADMAP G.5): export the whole app to one
  /// JSON file, restore from one (destructive replace, behind a confirm), a
  /// reminder cadence, and a "Last backup" line with a gentle overdue hint.
  List<Widget> _buildBackupSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overdue = isBackupOverdue(
      cadence: backupCadence,
      lastBackupAt: lastBackupAt,
      now: DateTime.now(),
    );
    final lastBackupLabel = lastBackupAt == null
        ? l10n.backupLastBackupNever
        : l10n.backupLastBackupDate(
            MaterialLocalizations.of(
              context,
            ).formatMediumDate(lastBackupAt!.toLocal()),
          );
    return [
      ListTile(
        title: Text(l10n.backupExportTitle),
        subtitle: Text(l10n.backupExportSubtitle),
        isThreeLine: true,
        trailing: FilledButton.tonalIcon(
          key: const ValueKey('backup-export-button'),
          onPressed: onExportBackup,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(l10n.backupExportAction),
        ),
      ),
      ListTile(
        title: Text(l10n.backupRestoreTitle),
        subtitle: Text(l10n.backupRestoreSubtitle),
        isThreeLine: true,
        trailing: OutlinedButton.icon(
          key: const ValueKey('backup-restore-button'),
          onPressed: onRestoreBackup,
          icon: const Icon(Icons.file_download_outlined),
          label: Text(l10n.backupRestoreAction),
        ),
      ),
      ListTile(
        title: Text(l10n.backupReminderTitle),
        subtitle: Text(lastBackupLabel),
        trailing: DropdownButton<BackupReminderCadence>(
          key: const ValueKey('backup-reminder-cadence'),
          value: backupCadence,
          onChanged: (value) {
            if (value != null) onBackupCadenceChanged(value);
          },
          items: [
            DropdownMenuItem(
              value: BackupReminderCadence.off,
              child: Text(l10n.backupReminderOff),
            ),
            DropdownMenuItem(
              value: BackupReminderCadence.weekly,
              child: Text(l10n.backupReminderWeekly),
            ),
            DropdownMenuItem(
              value: BackupReminderCadence.monthly,
              child: Text(l10n.backupReminderMonthly),
            ),
          ],
        ),
      ),
      if (overdue)
        Padding(
          key: const ValueKey('backup-overdue-hint'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.backupOverdueHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

/// What the restore dialog hands back: the backup text, plus its decoded form
/// when the dialog already produced it for a chosen file.
class _RestoreChoice {
  const _RestoreChoice(this.json, [this.read]);

  final String json;
  final BackupReadResult? read;
}

/// A modal that collects a backup to restore — either by choosing a file (via
/// the injected [picker]) or by pasting JSON — behind an explicit,
/// destructive-replace warning. Returns a [_RestoreChoice] when the user
/// confirms, or `null` if they cancel.
///
/// A chosen file is held in state and shown as a summary (date, counts, size)
/// rather than poured into the paste box: laying out megabytes of text froze
/// the dialog for seconds. The paste box is for pasted text only and is
/// disabled while a file is held.
class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog({required this.picker});

  final BackupPicker picker;

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _picking = false;

  /// The chosen file's text, set the moment the picker returns so Replace is
  /// enabled before the decode finishes.
  String? _pickedJson;

  /// The decoded [_pickedJson] and its UTF-8 size; `null` while being read.
  /// Handed on to the restore so the file is decoded once, not twice.
  BackupReadResult? _read;
  int? _sizeBytes;

  /// Set when the decode itself threw: shown as unreadable, with the restore
  /// left to own the refusal.
  bool _decodeFailed = false;

  /// Guards a slow summary decode against a newer pick or a Clear.
  int _pickGeneration = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearFile() {
    setState(() {
      _pickGeneration++;
      _pickedJson = null;
      _read = null;
      _sizeBytes = null;
      _decodeFailed = false;
    });
  }

  Future<void> _chooseFile() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    try {
      final json = await widget.picker();
      if (!mounted || json == null) return;
      final generation = ++_pickGeneration;
      setState(() {
        _controller.clear();
        _pickedJson = json;
        _read = null;
        _sizeBytes = null;
        _decodeFailed = false;
      });
      try {
        final decoded = await decodeBackupSizedOnIsolate(
          json,
          runner: defaultBackupCodecRunner,
        );
        if (!mounted || generation != _pickGeneration) return;
        setState(() {
          _read = decoded.read;
          _sizeBytes = decoded.sizeBytes;
        });
      } on Object catch (e, stackTrace) {
        logCaughtError(e, stackTrace, source: 'general_section._chooseFile');
        if (!mounted || generation != _pickGeneration) return;
        setState(() => _decodeFailed = true);
      }
    } on BackupFileTooLargeException catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'general_section._chooseFile');
      // Surface the size-cap refusal as a friendly message instead of letting
      // it crash the picker: the file was never read, so live data is safe.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).backupFileTooLarge(
              backupMegabytes(e.sizeBytes),
              backupMegabytes(e.maxBytes),
            ),
          ),
        ),
      );
    } on FormatException catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'general_section._chooseFile');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).backupRestoreInvalidFile),
        ),
      );
    } on Object catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'general_section._chooseFile');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).backupChooseFileFailed),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _fileSummary(AppLocalizations l10n) {
    final read = _read;
    final String text;
    if (read == null && !_decodeFailed) {
      text = l10n.backupRestorePreparing;
    } else if (read == null || read.fatal) {
      text = l10n.backupFileUnreadable(
        backupMegabytes(_sizeBytes ?? _pickedJson!.length),
      );
    } else {
      final core = read.document.core;
      text = l10n.backupFileSummary(
        MaterialLocalizations.of(
          context,
        ).formatMediumDate(read.document.createdAt.toLocal()),
        core.dances.where((d) => d.deletedAt == null).length,
        core.programs.where((p) => p.deletedAt == null).length,
        backupMegabytes(_sizeBytes!),
      );
    }
    return Card(
      key: const ValueKey('restore-file-summary'),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(text),
        trailing: TextButton(
          key: const ValueKey('restore-file-clear'),
          onPressed: _clearFile,
          child: Text(l10n.backupFileClearAction),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final holdsFile = _pickedJson != null;
    final hasContent = holdsFile || _controller.text.trim().isNotEmpty;
    return AlertDialog(
      key: const ValueKey('restore-backup-dialog'),
      title: Text(l10n.backupRestoreTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupRestoreDialogBody),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('restore-choose-file'),
              onPressed: _picking ? null : _chooseFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l10n.backupChooseFileAction),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (holdsFile) ...[
              _fileSummary(l10n),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextField(
              key: const ValueKey('restore-paste-field'),
              controller: _controller,
              enabled: !holdsFile,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.backupPasteJsonLabel,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('restore-confirm'),
          onPressed: hasContent
              ? () => Navigator.of(context).pop(
                  holdsFile
                      ? _RestoreChoice(_pickedJson!, _read)
                      : _RestoreChoice(_controller.text),
                )
              : null,
          child: Text(l10n.backupReplaceAllDataAction),
        ),
      ],
    );
  }
}

/// The modal shown while a backup is exported or restored. Not dismissable by
/// the barrier or the back button; its owner closes it. See
/// [_GeneralSectionState._showBackupProgress].
class _BackupProgressDialog extends StatelessWidget {
  const _BackupProgressDialog({
    super.key,
    required this.progress,
    required this.idleLabel,
    required this.progressLabel,
  });

  /// `(done, total)` once known; `null` (or a null notifier) = indeterminate.
  final ValueListenable<(int, int)?>? progress;
  final String idleLabel;
  final String Function(int done, int total)? progressLabel;

  Widget _body((int, int)? value) {
    final total = value?.$2 ?? 0;
    final label = progressLabel;
    final determinate = value != null && total > 0 && label != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: determinate ? value.$1 / total : null),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(determinate ? label(value.$1, total) : idleLabel),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = progress;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: SizedBox(
          width: 320,
          child: source == null
              ? _body(null)
              : ValueListenableBuilder<(int, int)?>(
                  valueListenable: source,
                  builder: (_, value, _) => _body(value),
                ),
        ),
      ),
    );
  }
}
