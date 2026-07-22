// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'settings_keys.dart';
import '../../data/backup_controller_scope.dart';
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
  String _backupFileName(DateTime when) {
    final d = when.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'callers-compendium-backup-'
        '${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  /// Builds the whole-app backup and hands it to the save/share seam, then
  /// stamps the last-backup time on success. If the user cancels the native
  /// save/share dialog, this is a clean no-op: no snackbar, no stamped time.
  Future<void> _onExportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final repos = RepositoriesScope.of(context);
    final saver = widget.backupSaver ?? saveBackupToFile;
    try {
      final service = BackupService(repos);
      final now = DateTime.now();
      final json = await service.exportToJson(createdAt: now);
      final delivered = await saver(json, _backupFileName(now));
      if (!delivered) return;
      await service.recordBackup(now);
      if (!mounted) return;
      setState(() {
        _backupPrefsRequested = true;
        _lastBackupAt = now.toUtc();
      });
      messenger.showSnackBar(const SnackBar(content: Text('Backup exported.')));
    } on Exception catch (e, st) {
      debugPrint('Backup export failed: $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't export a backup.")),
      );
    }
  }

  /// Prompts for a backup (file or pasted JSON) behind a destructive-replace
  /// confirmation, applies it, then refreshes the live app so the restore shows
  /// without a relaunch.
  Future<void> _onRestoreBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final repos = RepositoriesScope.of(context);
    final picker = widget.backupPicker ?? pickBackupFile;
    final onRestored = BackupControllerScope.maybeOf(context)?.onRestored;

    final json = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreBackupDialog(picker: picker),
    );
    if (json == null || json.trim().isEmpty) return;

    try {
      final outcome = await BackupService(repos).restoreFromJson(json);
      if (!outcome.applied) {
        if (!mounted) return;
        // Distinguish a genuinely invalid file from a valid-but-incomplete
        // backup that was refused to protect live data (issue #430): a replace
        // that would have dropped entities must never look like a clean
        // success, and must not be mistaken for an unreadable file.
        final message = outcome.incompleteCore
            ? 'This backup contains items this version of the app '
                  "can't read (it may be from a newer version), so the "
                  'restore was cancelled. Your data is unchanged.'
            : "Couldn't restore: the file isn't a valid backup. "
                  'Your data is unchanged.';
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      if (onRestored != null) await onRestored();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome.hasErrors
                ? 'Backup restored with ${outcome.errors.length} '
                      'problem(s) skipped.'
                : 'Backup restored.',
          ),
        ),
      );
    } on Exception catch (e, st) {
      debugPrint('Backup restore failed: $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't restore the backup.")),
      );
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
    return ListView(
      keyboardDismissBehavior: kTextEntryKeyboardDismiss,
      children: [
        SectionHeader(title: 'Library'),
        SwitchListTile(
          key: const ValueKey('general-sort-ignore-articles'),
          value: sortIgnoreArticles,
          onChanged: onSortIgnoreArticlesChanged,
          title: const Text('Ignore leading articles when sorting'),
          subtitle: const Text(
            'When on, the dance list alphabetizes titles ignoring a leading '
            '“the”, “a”, or “an” — so “The Nice Combination” files under N. '
            'Turn off to sort by the literal title.',
          ),
          isThreeLine: true,
        ),
        SectionHeader(title: 'Venues'),
        SwitchListTile(
          key: const ValueKey('general-venue-entity-mode'),
          value: venueEntityMode,
          onChanged: onVenueEntityModeChanged,
          title: const Text('Use reusable venue records'),
          subtitle: const Text(
            'Turn venues into reusable records with address, contacts, and '
            'schedule that many programs can share and you edit in one place. '
            'When off, a program’s venue is a simple free-text field. Switching '
            'is lossless — your typed venue and any linked record are both kept.',
          ),
          isThreeLine: true,
        ),
        ListTile(
          key: const ValueKey('general-manage-venues'),
          leading: const Icon(Icons.place_outlined),
          title: const Text('Manage venues'),
          subtitle: const Text(
            'Browse, edit, and delete your reusable venue records.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onManageVenues,
        ),
        SectionHeader(title: 'Performance'),
        SwitchListTile(
          key: const ValueKey('settings-auto-size-perform'),
          title: const Text('Auto-size Perform cards'),
          subtitle: const Text(
            'Scale each card so the full dance or slot fits the screen without '
            'scrolling. Turn off to set the size yourself with A- / A+.',
          ),
          value: autoSizePerform,
          onChanged: onAutoSizeChanged,
        ),
        SectionHeader(title: 'Calling history'),
        SwitchListTile(
          key: const ValueKey('general-require-performed-for-history'),
          value: requirePerformedForHistory,
          onChanged: onRequirePerformedForHistoryChanged,
          title: const Text('Require “mark performed” for calling history'),
          subtitle: const Text(
            'When on, a dance’s calling history lists only programs whose slot '
            'for that dance was marked performed. When off, a program appears '
            'as soon as it contains the dance.',
          ),
          isThreeLine: true,
        ),
        SectionHeader(title: 'Accessibility'),
        SwitchListTile(
          key: const ValueKey('general-reduce-motion'),
          value: reduceMotion,
          onChanged: onReduceMotionChanged,
          title: const Text('Reduce motion'),
          subtitle: const Text(
            'Dampen or skip non-essential animations, such as animated '
            'scrolling when moving between search results or figures.',
          ),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-verbose-figures'),
          value: verboseFigureRendering,
          onChanged: onVerboseFigureRenderingChanged,
          title: const Text('Always show verbose figure text'),
          subtitle: const Text(
            'Show the full spoken-style figure wording on screen in the dance '
            'view, not only to screen readers. Turn off for the terse notation.',
          ),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-decimal-turns'),
          value: decimalTurns,
          onChanged: onDecimalTurnsChanged,
          title: const Text('Show turns as decimals'),
          subtitle: const Text(
            'Show turn and rotation amounts as decimals (0.75) instead of '
            'fractions (¾). Screen-reader wording is unaffected.',
          ),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-confirm-before-delete'),
          value: confirmBeforeDelete,
          onChanged: onConfirmBeforeDeleteChanged,
          title: const Text('Confirm before delete'),
          subtitle: const Text(
            'Ask for confirmation before deleting a dance or program. Deletes '
            'can still be undone; this just adds an explicit prompt first.',
          ),
          isThreeLine: true,
        ),
        SectionHeader(title: 'Deleted items'),
        ListTile(
          title: const Text('Keep deleted dances for'),
          subtitle: const Text(
            'Deleted dances are kept for this long before being permanently '
            'removed on app launch. Never keeps them until you purge manually.',
          ),
          isThreeLine: true,
          trailing: DropdownButton<int>(
            key: const ValueKey('general-soft-delete-retention'),
            value: softDeleteRetentionDays,
            onChanged: (value) {
              if (value != null) onSoftDeleteRetentionChanged(value);
            },
            items: [
              for (final days in kSoftDeleteRetentionDayOptions)
                DropdownMenuItem(value: days, child: Text('$days days')),
              const DropdownMenuItem(
                value: kSoftDeleteRetentionNever,
                child: Text('Never'),
              ),
            ],
          ),
        ),
        SectionHeader(title: 'Import'),
        ListTile(
          title: const Text('Import dances'),
          subtitle: const Text(
            "Bring dances into your collection from a Caller's Compendium JSON "
            'file. You review every dance and confirm before anything is added.',
          ),
          isThreeLine: true,
          trailing: OutlinedButton.icon(
            key: const ValueKey('import-dances-button'),
            onPressed: onImportDances,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import…'),
          ),
        ),
        ListTile(
          title: const Text('Re-check custom figures'),
          subtitle: const Text(
            'Re-parse imported dances whose figures were kept as custom only '
            'because they could not be recognised at import time. Improved '
            'parsing upgrades them in place — your tags, ratings, and notes '
            'are preserved. You preview and confirm before anything changes.',
          ),
          isThreeLine: true,
          trailing: OutlinedButton.icon(
            key: const ValueKey('reparse-custom-figures-button'),
            onPressed: onReparseCustomFigures,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Re-check…'),
          ),
        ),
        SectionHeader(title: 'Backup & restore'),
        ..._buildBackupSection(context),
      ],
    );
  }

  /// The "Backup & restore" controls (ROADMAP G.5): export the whole app to one
  /// JSON file, restore from one (destructive replace, behind a confirm), a
  /// reminder cadence, and a "Last backup" line with a gentle overdue hint.
  List<Widget> _buildBackupSection(BuildContext context) {
    final overdue = isBackupOverdue(
      cadence: backupCadence,
      lastBackupAt: lastBackupAt,
      now: DateTime.now(),
    );
    final lastBackupLabel = lastBackupAt == null
        ? 'Last backup: never'
        : 'Last backup: '
              '${MaterialLocalizations.of(context).formatMediumDate(lastBackupAt!.toLocal())}';
    return [
      ListTile(
        title: const Text('Export a backup'),
        subtitle: const Text(
          'Save your entire collection, programs, custom fields, dialects, '
          'themes, and settings to a single JSON file you can keep safe or '
          'move to another device.',
        ),
        isThreeLine: true,
        trailing: FilledButton.tonalIcon(
          key: const ValueKey('backup-export-button'),
          onPressed: onExportBackup,
          icon: const Icon(Icons.file_upload_outlined),
          label: const Text('Export'),
        ),
      ),
      ListTile(
        title: const Text('Restore from a backup'),
        subtitle: const Text(
          'Replace everything currently in the app with the contents of a '
          'backup file. This cannot be undone.',
        ),
        isThreeLine: true,
        trailing: OutlinedButton.icon(
          key: const ValueKey('backup-restore-button'),
          onPressed: onRestoreBackup,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Restore'),
        ),
      ),
      ListTile(
        title: const Text('Backup reminder'),
        subtitle: Text(lastBackupLabel),
        trailing: DropdownButton<BackupReminderCadence>(
          key: const ValueKey('backup-reminder-cadence'),
          value: backupCadence,
          onChanged: (value) {
            if (value != null) onBackupCadenceChanged(value);
          },
          items: const [
            DropdownMenuItem(
              value: BackupReminderCadence.off,
              child: Text('Off'),
            ),
            DropdownMenuItem(
              value: BackupReminderCadence.weekly,
              child: Text('Weekly'),
            ),
            DropdownMenuItem(
              value: BackupReminderCadence.monthly,
              child: Text('Monthly'),
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
                  "It's been a while since your last backup — consider "
                  'exporting one now.',
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
    final hasContent = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      key: const ValueKey('restore-backup-dialog'),
      title: const Text('Restore from a backup'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restoring replaces everything currently in the app — your '
              'collection, programs, dialects, themes, and settings — with the '
              "backup's contents. This cannot be undone.",
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('restore-choose-file'),
              onPressed: _picking ? null : _chooseFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose file…'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('restore-paste-field'),
              controller: _controller,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Or paste backup JSON',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('restore-confirm'),
          onPressed: hasContent
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: const Text('Replace all data'),
        ),
      ],
    );
  }
}
