// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'settings_keys.dart';
import '../../data/backup_controller_scope.dart';
import '../../data/backup_crypto.dart';
import '../../data/backup_io.dart';
import '../../data/backup_reminder.dart';
import '../../data/backup_service.dart';
import '../../data/confirm_before_delete_scope.dart';
import '../../data/import_io.dart';
import '../../data/reduce_motion_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/require_performed_for_history_scope.dart';
import '../../data/soft_delete_retention.dart';
import '../../data/sort_ignore_articles_scope.dart';
import '../../data/verbose_figure_rendering_scope.dart';
import '../../data/decimal_turns_scope.dart';
import '../../data/venue_entity_mode_scope.dart';
import '../../theme/app_spacing.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/section_header.dart';
import '../import_review_screen.dart';
import '../reparse_custom_figures_screen.dart';
import '../venue_manager_screen.dart';

/// The General settings section: app-wide toggles, soft-delete retention,
/// backup/restore, and the import launcher. Owns its async loads + load-race
/// guards and the backup/import test seams.
class GeneralSection extends StatefulWidget {
  const GeneralSection({
    super.key,
    this.backupSaver,
    this.backupPicker,
    this.backupEncryptor,
    this.backupDecryptor,
    this.importPicker,
    this.urlFetcher,
  });

  /// Test seam for delivering an exported backup file; defaults to
  /// [saveBackupToFile] (temp file + OS share sheet).
  final BackupSaver? backupSaver;

  /// Test seam for choosing a backup file to restore; defaults to
  /// [pickBackupFile] (native open-file dialog).
  final BackupPicker? backupPicker;

  /// Test seam for encrypting a backup export; defaults to
  /// [encryptBackupOffThread] (isolate-backed). Overridden in tests to avoid
  /// spawning an isolate / paying the full KDF cost (issue #461).
  final BackupEncryptor? backupEncryptor;

  /// Test seam for decrypting an encrypted backup on restore; defaults to
  /// [decryptBackupOffThread] (isolate-backed).
  final BackupDecryptor? backupDecryptor;

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
  /// Auto-size Perform cards (ROADMAP G.1). Loaded from settings on first build;
  /// defaults on until loaded. `null` = not yet loaded.
  bool? _autoSizePerform;
  bool _autoSizeRequested = false;
  bool _autoSizeUserSet = false;

  /// Soft-delete retention window (ROADMAP G.4), as the stored `int` day count
  /// (`0` = never auto-purge). `null` = not yet loaded; the view shows the
  /// 30-day default until the read resolves.
  int? _softDeleteRetentionDays;
  bool _softDeleteRetentionRequested = false;
  bool _softDeleteRetentionUserSet = false;

  /// Lazily loads the persisted auto-size preference the first time the General
  /// section is built (avoids reading settings in `initState`, where the
  /// [RepositoriesScope] context is available but this keeps the pattern with
  /// the scope-driven appearance/dialect reads).
  void _ensureAutoSizeLoaded(BuildContext context) {
    if (_autoSizeRequested) return;
    _autoSizeRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kAutoSizePerformKey)
        .then((value) {
          // Don't overwrite a selection the user made before the read resolved.
          if (!mounted || _autoSizeUserSet) return;
          setState(() => _autoSizePerform = value is bool ? value : true);
        })
        .catchError((_) {
          if (!mounted || _autoSizeUserSet) return;
          setState(() => _autoSizePerform = true);
        });
  }

  Future<void> _onAutoSizeChanged(bool value) async {
    setState(() {
      _autoSizeUserSet = true;
      _autoSizePerform = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kAutoSizePerformKey, value);
  }

  /// Lazily loads the persisted soft-delete retention window (ROADMAP G.4) the
  /// first time the General section is built. Mirrors [_ensureAutoSizeLoaded]: a
  /// late read must not clobber a selection the user made before it resolved.
  void _ensureSoftDeleteRetentionLoaded(BuildContext context) {
    if (_softDeleteRetentionRequested) return;
    _softDeleteRetentionRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kSoftDeleteRetentionKey)
        .then((stored) {
          if (!mounted || _softDeleteRetentionUserSet) return;
          setState(
            () => _softDeleteRetentionDays = _retentionSelectionFromStored(
              stored,
            ),
          );
        })
        .catchError((_) {
          if (!mounted || _softDeleteRetentionUserSet) return;
          setState(
            () => _softDeleteRetentionDays = kSoftDeleteRetentionDefaultDays,
          );
        });
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
          if (!mounted) return;
          setState(() => _backupCadence = BackupReminderCadence.off);
        });
    settings
        .get(kLastBackupAtKey)
        .then((stored) {
          if (!mounted) return;
          setState(() => _lastBackupAt = lastBackupAtFromStored(stored));
        })
        .catchError((_) {});
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

  /// Suggested filename for an *encrypted* backup export (issue #461):
  /// `callers-compendium-backup-2026-07-15.ccbackup`.
  String _encryptedBackupFileName(DateTime when) =>
      '${_backupFileStem(when)}.$kEncryptedBackupExtension';

  String _backupFileStem(DateTime when) {
    final d = when.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'callers-compendium-backup-${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Builds the whole-app backup and hands it to the save/share seam, then
  /// stamps the last-backup time on success.
  ///
  /// First offers an export-options dialog (issue #461): the backup is plain
  /// JSON by default, or the user can opt in to encrypting it with a passphrase.
  /// If the user cancels either the options dialog or the native save/share
  /// dialog, this is a clean no-op: no snackbar, no stamped time.
  Future<void> _onExportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final saver = widget.backupSaver ?? saveBackupToFile;
    final encryptor = widget.backupEncryptor ?? encryptBackupOffThread;

    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (_) => const _EncryptExportDialog(),
    );
    if (choice == null) return; // cancelled the options dialog

    try {
      final service = BackupService(repos);
      final now = DateTime.now();
      final json = await service.exportToJson(createdAt: now);

      var payload = json;
      var fileName = _backupFileName(now);
      if (choice.encrypt) {
        final passphrase = choice.passphrase!;
        if (!mounted) return;
        payload = await _runWithProgress(
          () => encryptor(json, passphrase),
          message: l10n.backupEncryptingProgress,
        );
        fileName = _encryptedBackupFileName(now);
      }

      final delivered = await saver(payload, fileName);
      if (!delivered) return;
      await service.recordBackup(now);
      if (!mounted) return;
      setState(() {
        _backupPrefsRequested = true;
        _lastBackupAt = now.toUtc();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice.encrypt ? l10n.backupEncryptedExported : l10n.backupExported,
          ),
        ),
      );
    } on Exception catch (e, st) {
      debugPrint('Backup export failed: $e\n$st');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupExportFailed)));
    }
  }

  /// Prompts for a backup (file or pasted JSON) behind a destructive-replace
  /// confirmation, applies it, then refreshes the live app so the restore shows
  /// without a relaunch.
  ///
  /// If the chosen backup is an encrypted container (issue #461), this prompts
  /// for its passphrase and decrypts it *before* the normal restore path. A
  /// wrong/empty passphrase or a tampered/corrupt container surfaces a clean,
  /// non-destructive error and the restore never runs — zero entities written.
  Future<void> _onRestoreBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final picker = widget.backupPicker ?? pickBackupFile;
    final decryptor = widget.backupDecryptor ?? decryptBackupOffThread;
    final onRestored = BackupControllerScope.maybeOf(context)?.onRestored;

    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreBackupDialog(picker: picker),
    );
    if (raw == null || raw.trim().isEmpty) return;

    var json = raw;
    if (isEncryptedBackup(raw)) {
      if (!mounted) return;
      final passphrase = await showDialog<String>(
        context: context,
        builder: (_) => const _PassphrasePromptDialog(),
      );
      if (passphrase == null || passphrase.isEmpty) return; // cancelled
      try {
        json = await _runWithProgress(
          () => decryptor(raw, passphrase),
          message: l10n.backupDecryptingProgress,
        );
      } on BackupDecryptException catch (e) {
        // Fail closed: the restore never runs, so live data is untouched.
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        return;
      } on Exception catch (e, st) {
        debugPrint('Backup decrypt failed: $e\n$st');
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.backupDecryptFailed)),
        );
        return;
      }
    }

    try {
      final outcome = await BackupService(repos).restoreFromJson(json);
      if (!outcome.applied) {
        if (!mounted) return;
        // Distinguish a genuinely invalid file from a valid-but-incomplete
        // backup that was refused to protect live data (issue #430): a replace
        // that would have dropped entities must never look like a clean
        // success, and must not be mistaken for an unreadable file.
        final message = outcome.incompleteCore
            ? l10n.backupRestoreIncompatibleVersion
            : l10n.backupRestoreInvalidFile;
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      if (onRestored != null) await onRestored();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome.hasErrors
                ? l10n.backupRestoreSkippedProblems(outcome.errors.length)
                : l10n.backupRestored,
          ),
        ),
      );
    } on Exception catch (e, st) {
      debugPrint('Backup restore failed: $e\n$st');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreFailed)));
    }
  }

  /// Runs [task] while showing a non-dismissible modal progress dialog, popping
  /// the dialog when [task] completes or throws. Used to give feedback during
  /// the memory-hard encrypt/decrypt step (issue #461), which is offloaded to a
  /// background isolate but can still take a moment.
  Future<T> _runWithProgress<T>(
    Future<T> Function() task, {
    required String message,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProgressDialog(message: message),
      ),
    );
    try {
      return await task();
    } finally {
      if (mounted) navigator.pop();
    }
  }

  /// Opens the adapter-agnostic import review flow (ROADMAP 6.3), offering the
  /// generic [GenericJsonAdapter] ("Caller's Compendium JSON", default), the
  /// [CallersBoxAdapter] ("The Caller's Box", which resolves a pasted dance URL
  /// or bare id to the `&format=JSON` endpoint before fetching), and the
  /// [ContraDbHtmlAdapter] ("ContraDB", which resolves a pasted dance URL or
  /// bare id to the `contradb.com/dances/N` HTML page and scrapes it). The
  /// screen is fully self-contained (plan → review → commit → undo) and
  /// refreshes the live Collection on commit via [CollectionRefreshScope].
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

  /// Opens the venue manager (browse/create/edit/delete reusable venues).
  Future<void> _onManageVenues() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const VenueManagerScreen()));
  }

  Future<void> _onRequirePerformedForHistoryChanged(bool value) async {
    // Same instant-notifier-then-persist pattern as dialect/theme: flip the
    // live notifier so every dependent (including an open dance-detail screen)
    // rebuilds immediately, then persist in the background.
    RequirePerformedForHistoryScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kRequirePerformedForHistoryKey, value);
  }

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

  Future<void> _onVenueEntityModeChanged(bool value) async {
    // Same instant-notifier-then-persist pattern: flip the live notifier so an
    // open program editor swaps its venue field/picker immediately, then
    // persist in the background. The toggle is entry/display-mode only — both
    // Program.venue and Program.venueId persist independently, so flipping it
    // never clears the other mode's value.
    VenueEntityModeScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kVenueEntityModeKey, value);
  }

  @override
  Widget build(BuildContext context) {
    _ensureAutoSizeLoaded(context);
    _ensureSoftDeleteRetentionLoaded(context);
    _ensureBackupPrefsLoaded(context);
    return _GeneralView(
      requirePerformedForHistory: RequirePerformedForHistoryScope.of(context),
      onRequirePerformedForHistoryChanged: _onRequirePerformedForHistoryChanged,
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
      venueEntityMode: VenueEntityModeScope.of(context),
      onVenueEntityModeChanged: _onVenueEntityModeChanged,
      onManageVenues: _onManageVenues,
      autoSizePerform: _autoSizePerform ?? true,
      onAutoSizeChanged: _onAutoSizeChanged,
      softDeleteRetentionDays:
          _softDeleteRetentionDays ?? kSoftDeleteRetentionDefaultDays,
      onSoftDeleteRetentionChanged: _onSoftDeleteRetentionChanged,
      backupCadence: _backupCadence ?? BackupReminderCadence.off,
      onBackupCadenceChanged: _onBackupCadenceChanged,
      lastBackupAt: _lastBackupAt,
      onExportBackup: _onExportBackup,
      onRestoreBackup: _onRestoreBackup,
      onImportDances: _onImportDances,
      onReparseCustomFigures: _onReparseCustomFigures,
    );
  }
}

/// The General section: app-wide preference switches (ROADMAP G).
///
/// Hosts the "Require mark-performed for calling history" toggle (ROADMAP G.2,
/// off by default) and the "Auto-size Perform cards" toggle (ROADMAP G.1, on by
/// default). New app-wide switches are added here as additional
/// [SwitchListTile]s.
class _GeneralView extends StatelessWidget {
  const _GeneralView({
    required this.requirePerformedForHistory,
    required this.onRequirePerformedForHistoryChanged,
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
    required this.venueEntityMode,
    required this.onVenueEntityModeChanged,
    required this.onManageVenues,
    required this.autoSizePerform,
    required this.onAutoSizeChanged,
    required this.softDeleteRetentionDays,
    required this.onSoftDeleteRetentionChanged,
    required this.backupCadence,
    required this.onBackupCadenceChanged,
    required this.lastBackupAt,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onImportDances,
    required this.onReparseCustomFigures,
  });

  final bool requirePerformedForHistory;
  final ValueChanged<bool> onRequirePerformedForHistoryChanged;
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
  final bool venueEntityMode;
  final ValueChanged<bool> onVenueEntityModeChanged;

  /// Opens the venue manager screen.
  final Future<void> Function() onManageVenues;
  final bool autoSizePerform;
  final ValueChanged<bool> onAutoSizeChanged;

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
        SectionHeader(title: l10n.settingsGeneralVenuesHeader),
        SwitchListTile(
          key: const ValueKey('general-venue-entity-mode'),
          value: venueEntityMode,
          onChanged: onVenueEntityModeChanged,
          title: Text(l10n.settingsGeneralVenueEntityModeTitle),
          subtitle: Text(l10n.settingsGeneralVenueEntityModeSubtitle),
          isThreeLine: true,
        ),
        ListTile(
          key: const ValueKey('general-manage-venues'),
          leading: const Icon(Icons.place_outlined),
          title: Text(l10n.settingsGeneralManageVenuesTitle),
          subtitle: Text(l10n.settingsGeneralManageVenuesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onManageVenues,
        ),
        SectionHeader(title: l10n.settingsGeneralPerformanceHeader),
        SwitchListTile(
          key: const ValueKey('settings-auto-size-perform'),
          title: Text(l10n.settingsGeneralAutoSizePerformTitle),
          subtitle: Text(l10n.settingsGeneralAutoSizePerformSubtitle),
          value: autoSizePerform,
          onChanged: onAutoSizeChanged,
        ),
        SectionHeader(title: l10n.settingsGeneralCallingHistoryHeader),
        SwitchListTile(
          key: const ValueKey('general-require-performed-for-history'),
          value: requirePerformedForHistory,
          onChanged: onRequirePerformedForHistoryChanged,
          title: Text(l10n.settingsGeneralRequirePerformedForHistoryTitle),
          subtitle: Text(
            l10n.settingsGeneralRequirePerformedForHistorySubtitle,
          ),
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

/// A modal that collects a backup to restore — either by choosing a file (via
/// the injected [picker]) or by pasting JSON — behind an explicit,
/// destructive-replace warning. Returns the chosen JSON string when the user
/// confirms, or `null` if they cancel.
class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog({required this.picker});

  final BackupPicker picker;

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    try {
      final json = await widget.picker();
      if (!mounted || json == null) return;
      _controller.text = json;
    } on BackupFileTooLargeException catch (e) {
      // Surface the size-cap refusal as a friendly message instead of letting
      // it crash the picker: the file was never read, so live data is safe.
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasContent = _controller.text.trim().isNotEmpty;
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
            TextField(
              key: const ValueKey('restore-paste-field'),
              controller: _controller,
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
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: Text(l10n.backupReplaceAllDataAction),
        ),
      ],
    );
  }
}

/// Result of the export-options dialog: whether to encrypt, and (if so) the
/// chosen passphrase. `null` from the dialog means the user cancelled.
class _ExportChoice {
  const _ExportChoice({required this.encrypt, this.passphrase});

  final bool encrypt;
  final String? passphrase;
}

/// Coarse, advisory passphrase-strength label (issue #461). Purely a UX hint —
/// export is never blocked on strength, only on a non-empty, matching confirm.
({String level, double fraction}) _passphraseStrength(String value) {
  if (value.isEmpty) return (level: '', fraction: 0);
  var score = 0;
  if (value.length >= 8) score++;
  if (value.length >= 12) score++;
  if (value.length >= 16) score++;
  final classes = [
    RegExp(r'[a-z]'),
    RegExp(r'[A-Z]'),
    RegExp(r'\d'),
    RegExp(r'[^A-Za-z0-9]'),
  ].where((r) => r.hasMatch(value)).length;
  if (classes >= 2) score++;
  if (classes >= 3) score++;
  if (score <= 1) return (level: 'weak', fraction: 0.25);
  if (score <= 3) return (level: 'fair', fraction: 0.6);
  return (level: 'strong', fraction: 1);
}

/// Export-options dialog (issue #461): plain JSON by default, with an opt-in to
/// encrypt the backup with a passphrase. When encryption is on it collects a
/// passphrase + confirmation, shows an advisory strength hint, and makes the
/// no-recovery caveat explicit. Returns an [_ExportChoice], or `null` on cancel.
class _EncryptExportDialog extends StatefulWidget {
  const _EncryptExportDialog();

  @override
  State<_EncryptExportDialog> createState() => _EncryptExportDialogState();
}

class _EncryptExportDialogState extends State<_EncryptExportDialog> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _encrypt = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canExport {
    if (!_encrypt) return true;
    final pass = _passphrase.text;
    return pass.isNotEmpty && pass == _confirm.text;
  }

  void _submit() {
    if (!_canExport) return;
    Navigator.of(context).pop(
      _ExportChoice(
        encrypt: _encrypt,
        passphrase: _encrypt ? _passphrase.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final passphrasesDiffer =
        _encrypt &&
        _confirm.text.isNotEmpty &&
        _passphrase.text != _confirm.text;
    final strength = _passphraseStrength(_passphrase.text);
    return AlertDialog(
      key: const ValueKey('export-backup-dialog'),
      title: Text(l10n.backupExportTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.backupExportDialogBody),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                key: const ValueKey('export-encrypt-toggle'),
                contentPadding: EdgeInsets.zero,
                value: _encrypt,
                onChanged: (v) => setState(() => _encrypt = v),
                title: Text(l10n.backupEncryptToggleTitle),
                subtitle: Text(l10n.backupEncryptToggleSubtitle),
              ),
              if (_encrypt) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('export-passphrase-field'),
                  controller: _passphrase,
                  obscureText: _obscure,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.backupPassphraseLabel,
                    suffixIcon: IconButton(
                      key: const ValueKey('export-passphrase-visibility'),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _obscure
                          ? l10n.backupShowPassphrase
                          : l10n.backupHidePassphrase,
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('export-confirm-field'),
                  controller: _confirm,
                  obscureText: _obscure,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.backupConfirmPassphraseLabel,
                    errorText: passphrasesDiffer
                        ? l10n.backupPassphrasesDontMatch
                        : null,
                  ),
                ),
                if (strength.level.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: strength.fraction,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.backupPassphraseStrength(strength.level),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Container(
                  key: const ValueKey('export-no-recovery-warning'),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.backupNoRecoveryWarning,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('export-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('export-confirm'),
          onPressed: _canExport ? _submit : null,
          child: Text(
            _encrypt
                ? l10n.backupEncryptAndExportAction
                : l10n.backupExportAction,
          ),
        ),
      ],
    );
  }
}

/// Prompts for the passphrase of an encrypted backup during restore (issue
/// #461). Returns the passphrase, or `null` on cancel.
class _PassphrasePromptDialog extends StatefulWidget {
  const _PassphrasePromptDialog();

  @override
  State<_PassphrasePromptDialog> createState() =>
      _PassphrasePromptDialogState();
}

class _PassphrasePromptDialogState extends State<_PassphrasePromptDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasContent = _controller.text.isNotEmpty;
    return AlertDialog(
      key: const ValueKey('decrypt-passphrase-dialog'),
      title: Text(l10n.backupEnterPassphraseTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupEnterPassphraseBody),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('decrypt-passphrase-field'),
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.backupPassphraseLabel,
                suffixIcon: IconButton(
                  key: const ValueKey('decrypt-passphrase-visibility'),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscure
                      ? l10n.backupShowPassphrase
                      : l10n.backupHidePassphrase,
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('decrypt-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('decrypt-confirm'),
          onPressed: hasContent ? _submit : null,
          child: Text(l10n.backupUnlockAndRestoreAction),
        ),
      ],
    );
  }
}

/// A minimal non-dismissible progress dialog shown while the encrypt/decrypt
/// step runs (issue #461).
class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('backup-progress-dialog'),
      content: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
