import 'package:compendium_core/compendium_core.dart';

import '../editor/editor_draft_codec.dart' show kDanceEditorDraftKeyPrefix;
import 'backup_document.dart';
import 'backup_reminder.dart';
import 'custom_theme.dart';
import 'custom_themes_controller.dart';
import 'dialect_library_controller.dart';
import 'window_service.dart' show kWindowFrameKey;

/// Settings keys that are NOT carried in a backup's `app.settings` map.
///
/// Two reasons a key is excluded:
/// - **structurally represented** — the dialect library and custom themes travel
///   in their own typed sections of the [BackupDocument], so their raw settings
///   blobs would be redundant (and could disagree with the typed sections):
///   [kCustomDialectsKey], [kActiveDialectRefKey], [kActiveDialectKey],
///   [kCustomThemesKey], [kActiveCustomThemeKey].
/// - **device-local / backup metadata** — geometry and backup bookkeeping that
///   must not travel between machines or be rewritten by restoring an old file:
///   [kWindowFrameKey], [kLastBackupAtKey], [kBackupReminderCadenceKey].
const Set<String> kBackupSettingsDenylist = {
  kCustomDialectsKey,
  kActiveDialectRefKey,
  kActiveDialectKey,
  kCustomThemesKey,
  kActiveCustomThemeKey,
  kWindowFrameKey,
  kLastBackupAtKey,
  kBackupReminderCadenceKey,
};

/// Key *prefixes* excluded from backups. Some settings-table keys are dynamic
/// (built per-entity), so they can't be named as exact denylist entries:
/// - [kDanceEditorDraftKeyPrefix] — transient, device-local dance-editor
///   autosave drafts (`editor_draft:<id>`); unsaved in-progress edits that are
///   neither user content nor preferences and must never travel in a backup.
const Set<String> kBackupSettingsDenylistPrefixes = {
  kDanceEditorDraftKeyPrefix,
};

/// Whether a settings-table [key] is eligible to travel in a backup's
/// `app.settings` map (and thus be fully replaced on restore).
///
/// The denylist ([kBackupSettingsDenylist] + [kBackupSettingsDenylistPrefixes])
/// is the single source of truth for "device-local / structurally-represented /
/// don't touch". Everything else is by definition backup-eligible content that a
/// restore replaces.
bool isBackupEligibleSettingKey(String key) {
  if (kBackupSettingsDenylist.contains(key)) return false;
  for (final prefix in kBackupSettingsDenylistPrefixes) {
    if (key.startsWith(prefix)) return false;
  }
  return true;
}

/// Outcome of restoring a [BackupDocument] to the live app.
class BackupRestoreOutcome {
  const BackupRestoreOutcome({
    this.errors = const [],
    this.warnings = const [],
    this.applied = false,
  });

  final List<ArchiveError> errors;
  final List<String> warnings;

  /// Whether the restore actually wrote to live data. `false` means the backup
  /// was rejected before anything was touched (a fatal envelope error such as
  /// invalid JSON or a missing/invalid `core` section), so the live app is
  /// unchanged and no refresh is warranted.
  final bool applied;

  bool get hasErrors => errors.isNotEmpty;
}

/// Builds and applies whole-app backups (ROADMAP G.5).
///
/// The service is UI-free and depends only on [CompendiumRepositories]: it reads
/// core content through [ArchiveExporter] and the app-local pieces straight from
/// the `settings` table (which the dialect/theme controllers keep current on
/// every mutation), and applies a restore by writing core content through
/// [ArchiveRestorer] (replace mode) and the app-local pieces back into `settings`.
///
/// Refreshing the live UI after a restore (reloading the dialect/theme
/// controllers and re-reading the preference notifiers) is the caller's job —
/// see the `onRestored` callback wired in `main.dart`.
class BackupService {
  BackupService(this._repos);

  final CompendiumRepositories _repos;

  /// Builds a [BackupDocument] snapshot of the current app state.
  Future<BackupDocument> buildDocument({DateTime? createdAt}) async {
    final core = await ArchiveExporter(_repos).export();
    final allSettings = await _repos.settings.all();

    final customDialects = _readDialects(allSettings[kCustomDialectsKey]);
    final activeDialectRef = allSettings[kActiveDialectRefKey];
    final customThemes = _readThemes(allSettings[kCustomThemesKey]);
    final activeThemeId = allSettings[kActiveCustomThemeKey];

    final settings = <String, Object?>{
      for (final entry in allSettings.entries)
        if (isBackupEligibleSettingKey(entry.key)) entry.key: entry.value,
    };

    return BackupDocument(
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      core: core,
      customDialects: customDialects,
      activeDialectRef: activeDialectRef is String ? activeDialectRef : null,
      customThemes: customThemes,
      activeCustomThemeId: activeThemeId is String ? activeThemeId : null,
      settings: settings,
    );
  }

  /// Builds a backup and returns it as a JSON string.
  Future<String> exportToJson({DateTime? createdAt}) async =>
      encodeBackup(await buildDocument(createdAt: createdAt));

  /// Records a successful backup by stamping [kLastBackupAtKey] with [at] (UTC).
  Future<void> recordBackup(DateTime at) =>
      _repos.settings.set(kLastBackupAtKey, at.toUtc().toIso8601String());

  /// Decodes [json] and applies it, replacing all current data.
  ///
  /// Core content is restored via [ArchiveRestorer] in [RestoreMode.replace];
  /// the app-local dialects, themes, and preference settings are written back
  /// into the `settings` table. Tolerant throughout: decode/restore problems are
  /// collected into the returned [BackupRestoreOutcome] rather than thrown.
  ///
  /// A **fatal** decode (invalid JSON, non-object root, or a missing/invalid
  /// `core` section) aborts before touching live data, so a corrupt or wrong
  /// file can never wipe the user's content. Such a restore returns
  /// [BackupRestoreOutcome.applied] `false`.
  Future<BackupRestoreOutcome> restoreFromJson(String json) async {
    final read = decodeBackup(json);
    final errors = <ArchiveError>[...read.errors];
    final warnings = <String>[...read.warnings];

    if (read.fatal) {
      // Nothing safe to restore — leave live data untouched.
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: false,
      );
    }

    final doc = read.document;
    final restoreResult = await ArchiveRestorer(
      _repos,
    ).restore(doc.core, mode: RestoreMode.replace);
    errors.addAll(restoreResult.errors);
    warnings.addAll(restoreResult.warnings);

    await _applyAppSettings(doc);

    return BackupRestoreOutcome(
      errors: errors,
      warnings: warnings,
      applied: true,
    );
  }

  /// Writes the backup's app-local pieces into the `settings` table so the
  /// dialect/theme controllers and preference notifiers pick them up on reload.
  ///
  /// This is a **replace**: existing non-denylisted preference keys that are
  /// absent from the backup are removed first, so restoring an older backup
  /// can't leave stale preferences behind. Denylisted keys (device-local
  /// geometry, backup metadata, and the structurally-represented dialect/theme
  /// keys) are preserved and handled explicitly below.
  Future<void> _applyAppSettings(BackupDocument doc) async {
    final settings = _repos.settings;

    final existing = await settings.all();
    final backedUp = doc.settings.keys.toSet();
    for (final key in existing.keys) {
      if (!isBackupEligibleSettingKey(key)) continue;
      if (backedUp.contains(key)) continue;
      await settings.remove(key);
    }

    // Dialect library: rewrite the custom list and the active ref, plus keep the
    // legacy full-blob key in sync for any reader that still resolves the active
    // dialect from it.
    await settings.set(kCustomDialectsKey, [
      for (final d in doc.customDialects) d.toJson(),
    ]);
    await settings.set(kActiveDialectRefKey, doc.activeDialectRef);
    final active = Dialect.resolveByName(
      doc.activeDialectRef,
      candidates: doc.customDialects,
    );
    if (active != null) await settings.set(kActiveDialectKey, active.toJson());

    // Custom themes: rewrite the list and the active id.
    await settings.set(kCustomThemesKey, [
      for (final t in doc.customThemes) t.toJson(),
    ]);
    await settings.set(kActiveCustomThemeKey, doc.activeCustomThemeId);

    // Preference settings: re-apply every backed-up key. The predicate guards
    // against a hand-edited or hostile backup smuggling a denylisted/device-local
    // key into `app.settings`.
    for (final entry in doc.settings.entries) {
      if (!isBackupEligibleSettingKey(entry.key)) continue;
      await settings.set(entry.key, entry.value);
    }
  }

  List<Dialect> _readDialects(Object? raw) {
    final result = <Dialect>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          try {
            result.add(Dialect.fromJson(entry.cast<String, Object?>()));
          } on Object {
            // Skip a corrupt entry rather than losing the whole library.
          }
        }
      }
    }
    return result;
  }

  List<CustomTheme> _readThemes(Object? raw) {
    final result = <CustomTheme>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          try {
            result.add(CustomTheme.fromJson(entry.cast<String, Object?>()));
          } on Object {
            // Skip a corrupt entry rather than losing every theme.
          }
        }
      }
    }
    return result;
  }
}
