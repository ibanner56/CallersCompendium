import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../editor/editor_draft_codec.dart' show kDanceEditorDraftKeyPrefix;
import '../editor/program_editor_draft_codec.dart'
    show kProgramEditorDraftKeyPrefix;
import 'backup_document.dart';
import 'backup_reminder.dart';
import 'backup_settings_schema.dart';
import 'custom_theme.dart';
import 'custom_themes_controller.dart';
import 'dialect_library_controller.dart';
import '../screens/settings/settings_keys.dart'
    show kSyncDeviceIdKey, kSyncIdKey;
import 'window_service.dart' show kWindowFrameKey;

/// Settings keys that are NOT carried in a backup's `app.settings` map.
///
/// Four reasons a key is excluded:
/// - **structurally represented** — the dialect library and custom themes travel
///   in their own typed sections of the [BackupDocument], so their raw settings
///   blobs would be redundant (and could disagree with the typed sections):
///   [kCustomDialectsKey], [kActiveDialectRefKey], [kActiveDialectKey],
///   [kCustomThemesKey], [kActiveCustomThemeKey].
/// - **device-local / backup metadata** — geometry and backup bookkeeping that
///   must not travel between machines or be rewritten by restoring an old file:
///   [kWindowFrameKey], [kLastBackupAtKey], [kBackupReminderCadenceKey],
///   [taxonomyV33CanonicalRebuildDoneKey].
/// - **sync security state** — credentials and per-installation routing state
///   must never be copied through a backup, even though their transport-specific
///   privacy classes are not [EgressClass.deviceLocal]:
///   [kSyncIdKey], [kSyncDeviceIdKey].
const Set<String> kBackupSettingsDenylist = {
  kCustomDialectsKey,
  kActiveDialectRefKey,
  kActiveDialectKey,
  kCustomThemesKey,
  kActiveCustomThemeKey,
  kWindowFrameKey,
  kLastBackupAtKey,
  kBackupReminderCadenceKey,
  taxonomyV33CanonicalRebuildDoneKey,
  kSyncIdKey,
  kSyncDeviceIdKey,
};

/// Key *prefixes* excluded from backups. Some settings-table keys are dynamic
/// (built per-entity), so they can't be named as exact denylist entries:
/// - [kDanceEditorDraftKeyPrefix] — transient, device-local dance-editor
///   autosave drafts (`editor_draft:<id>`); unsaved in-progress edits that are
///   neither user content nor preferences and must never travel in a backup.
/// - [kProgramEditorDraftKeyPrefix] — the program-editor equivalent
///   (`program_editor_draft:<id>`); same device-local, transient rationale.
const Set<String> kBackupSettingsDenylistPrefixes = {
  kDanceEditorDraftKeyPrefix,
  kProgramEditorDraftKeyPrefix,
};

/// Whether a settings-table [key] is eligible to travel in a backup's
/// `app.settings` map (and thus be fully replaced on restore).
///
/// The denylist ([kBackupSettingsDenylist] + [kBackupSettingsDenylistPrefixes])
/// is the single source of truth for settings that are structurally represented,
/// device-local, backup metadata, or sync security state. Everything else is by
/// definition backup-eligible content that a restore replaces.
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
    this.incompleteCore = false,
    this.integrityFailed = false,
    this.settingsFailed = false,
  });

  final List<ArchiveError> errors;
  final List<String> warnings;

  /// Whether the restore actually wrote to live data. `false` means the backup
  /// was rejected before anything was touched (a fatal envelope error such as
  /// invalid JSON or a missing/invalid `core` section, an incomplete core, or a
  /// core restore that failed and rolled back), so the live app is unchanged
  /// and no refresh is warranted.
  final bool applied;

  /// Whether the restore was refused because the backup's core did not decode
  /// completely — some entities were dropped (an unknown enum from a newer app
  /// version) or failed to decode. Distinguishes "the file isn't a valid
  /// backup" from "this is a valid but partially-unreadable backup, so a
  /// destructive replace was cancelled to protect your data" (issue #430), so
  /// the UI never reports a clean success when entities were skipped/refused.
  final bool incompleteCore;

  /// Whether the restore was refused because the backup failed its **integrity
  /// checksum** (issue #536) — corrupt or altered file, nothing applied. Lets
  /// the UI say so specifically instead of a generic "invalid file".
  final bool integrityFailed;

  /// Whether the **core** content restored and committed successfully but the
  /// subsequent **app-settings** apply step failed (issue #608).
  ///
  /// The core (dances/programs/etc.) and app settings (SharedPreferences-style
  /// `settings` table) live in two independent stores that cannot share one
  /// transaction, so once the core has committed it CANNOT be part of a settings
  /// rollback. When the settings-apply step genuinely fails (the settings store
  /// throws / is unavailable — as opposed to a single invalid value, which #609
  /// already degrades to its default), the owner-decided behavior is to KEEP the
  /// successfully-restored core (no disproportionate pre-restore snapshot /
  /// rollback) and surface a specific, retryable error rather than silently
  /// accepting the partial state or misreporting a total failure.
  ///
  /// On this path [applied] is `true` — the core changed, so the UI should still
  /// refresh — and the UI surfaces a clean, localized, actionable message with a
  /// "retry settings" affordance that re-runs ONLY the settings apply via
  /// [BackupService.retryApplySettings]. Distinct from [hasErrors] (some
  /// entities skipped) and from an outright refusal ([applied] is `false`, where
  /// nothing was written).
  final bool settingsFailed;

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

  /// Decodes [json] and applies it to the live app.
  ///
  /// Core content is restored via [ArchiveRestorer]; the app-local dialects,
  /// themes, and preference settings are written back into the `settings` table.
  /// Tolerant throughout: decode/restore problems are collected into the
  /// returned [BackupRestoreOutcome] rather than thrown.
  ///
  /// [mode] selects the core restore strategy and, with it, how strict the
  /// pre-flight guard is:
  /// - [RestoreMode.replace] (default, used by the settings "restore backup"
  ///   flow) is **destructive** — it wipes the live collection before loading
  ///   the archive — so it is refused before touching live data unless the
  ///   backup decoded *completely*. A restore is refused when:
  ///   - the envelope is **fatal** (invalid JSON, non-object root, or a
  ///     missing/invalid `core` section), or
  ///   - the core had a per-entity decode **error**
  ///     ([BackupReadResult.coreHasErrors]), or
  ///   - the core **dropped** entities for forward-compatibility
  ///     ([BackupReadResult.coreIncomplete]) — e.g. a dance carrying an enum
  ///     value written by a newer app version.
  ///   Committing a partially-decoded or reduced archive in replace mode would
  ///   swap the user's data for an incomplete copy — exactly the loss this
  ///   guard prevents (issue #430). Such a restore returns
  ///   [BackupRestoreOutcome.applied] `false` with the live app untouched.
  /// - [RestoreMode.merge] is **additive** and stays tolerant: it applies
  ///   whatever decoded, keeping survivors and recording the rest.
  ///
  /// A fatal envelope is refused in both modes. In replace mode, if the core
  /// restore itself fails it is rolled back atomically and this method returns
  /// `applied: false` **without** mutating app settings (dialect/theme/prefs),
  /// so a failed replace never leaves core intact but preferences overwritten.
  ///
  /// If the core commits but the SEPARATE app-settings apply then fails (the
  /// settings store throws / is unavailable — issue #608), the restored core is
  /// KEPT (it cannot share the core's transaction, so it is not rolled back) and
  /// this returns `applied: true` with [BackupRestoreOutcome.settingsFailed]
  /// `true`. The caller surfaces a retryable error and can re-run only the
  /// settings apply via [retryApplySettings]; the exception is never rethrown.
  Future<BackupRestoreOutcome> restoreFromJson(
    String json, {
    RestoreMode mode = RestoreMode.replace,
  }) async {
    final read = decodeBackup(json);
    final errors = <ArchiveError>[...read.errors];
    final warnings = <String>[...read.warnings];

    // A fatal envelope has nothing safe to apply in any mode.
    if (read.fatal) {
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: false,
        integrityFailed: read.integrityFailed,
      );
    }

    // Replace is destructive, so it must only run on a backup that decoded
    // completely: a per-entity decode error OR a forward-compat drop means the
    // decoded archive is not a faithful copy, and committing it would silently
    // lose data (#430). Merge is additive and tolerates both.
    if (mode == RestoreMode.replace &&
        (read.coreHasErrors || read.coreIncomplete)) {
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: false,
        incompleteCore: read.coreIncomplete,
      );
    }

    final doc = read.document;
    final restoreResult = await ArchiveRestorer(
      _repos,
    ).restore(doc.core, mode: mode);
    errors.addAll(restoreResult.errors);
    warnings.addAll(restoreResult.warnings);

    // A replace restore is transactional and all-or-nothing: if it recorded any
    // error it rolled the whole thing back and the live core is untouched. Do
    // NOT mutate app settings or report success in that case — otherwise a
    // failed replace would leave core data intact while overwriting
    // dialect/theme/preferences and misreporting the restore as applied.
    if (mode == RestoreMode.replace && restoreResult.hasErrors) {
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: false,
      );
    }

    // Core is committed and durable at this point. Applying app settings is a
    // SEPARATE, non-transactional batch of writes into an independent store, so
    // a failure here (the settings store throws / is unavailable) CANNOT roll
    // the core back. Rather than let that exception propagate — which the UI
    // would mislabel as a total "restore failed" even though the core is safely
    // restored — keep the restored core and report a specific, retryable
    // settings failure (#608). A single invalid VALUE does not reach here: #609
    // validates each value inside [_applyAppSettings] and skips it to its
    // default; this guard is for a genuine failure of the apply step itself.
    //
    // Catch [Exception], NOT bare [Object]: a genuine settings-store failure is
    // an Exception (I/O / unavailable), whereas an [Error] signals a programming
    // bug that must surface loudly rather than be silently downgraded to a
    // routine "settings failed". Log the caught failure (guarded so it never
    // reaches a release build, per #617) so the failure isn't invisible.
    try {
      await _applyAppSettings(doc, warnings);
    } on Exception catch (e, st) {
      // diagnostics: silent — settings-apply failed; outcome returned to caller (general_section._onRestoreBackup) which handles user surface.
      if (kDebugMode) {
        debugPrint('Restore: settings-apply failed after core commit: $e\n$st');
      }
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: true,
        settingsFailed: true,
      );
    }

    return BackupRestoreOutcome(
      errors: errors,
      warnings: warnings,
      applied: true,
    );
  }

  /// Re-applies ONLY the app-settings portion of [json] against data whose core
  /// has already been restored — the retry path for issue #608's
  /// core-restored-but-settings-failed state.
  ///
  /// The core is deliberately NOT touched: this method never runs
  /// [ArchiveRestorer], so it cannot re-wipe or re-load the (already correct)
  /// collection. It re-decodes [json] so the untrusted backup is re-validated
  /// end-to-end every time — envelope well-formedness, the SHA-256 integrity
  /// checksum (#536), and, inside [_applyAppSettings], the per-key type/range
  /// schema (#609) — before any value is written. A fatal envelope (invalid
  /// JSON / missing core / failed checksum) yields `applied: false` and nothing
  /// is applied.
  ///
  /// Idempotent: [_applyAppSettings] is a full REPLACE of the backup-eligible
  /// settings keys (it removes stale eligible keys, then re-sets each backed-up
  /// key), so running it once or several times converges to the same state.
  /// This makes the retry safe to invoke repeatedly, and a settings-apply
  /// failure that recurs is reported (again) as [BackupRestoreOutcome.applied]
  /// `true` with [BackupRestoreOutcome.settingsFailed] `true` rather than thrown
  /// (an [Error], i.e. a programming bug, is deliberately NOT caught so it
  /// surfaces; the caught [Exception] is logged in debug builds).
  Future<BackupRestoreOutcome> retryApplySettings(String json) async {
    final read = decodeBackup(json);
    final errors = <ArchiveError>[...read.errors];
    final warnings = <String>[...read.warnings];

    // Without a well-formed envelope there is no document to apply. Nothing was
    // touched, so this is a clean refusal (applied: false), mirroring the
    // pre-core-commit refusals in [restoreFromJson].
    if (read.fatal) {
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: false,
        integrityFailed: read.integrityFailed,
      );
    }

    try {
      await _applyAppSettings(read.document, warnings);
    } on Exception catch (e, st) {
      // diagnostics: silent — settings-apply retry failed; outcome returned to caller (general_section._retrySettingsRestore) which handles user surface.
      if (kDebugMode) {
        debugPrint('Restore: settings-apply retry failed: $e\n$st');
      }
      return BackupRestoreOutcome(
        errors: errors,
        warnings: warnings,
        applied: true,
        settingsFailed: true,
      );
    }

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
  Future<void> _applyAppSettings(
    BackupDocument doc,
    List<String> warnings,
  ) async {
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

    // Preference settings: re-apply every backed-up key. The eligibility
    // predicate guards against a hand-edited or hostile backup smuggling a
    // denylisted/device-local key into `app.settings`.
    //
    // SECURITY / RESILIENCE (issue #609, OWASP input validation): the restored
    // settings blob is UNTRUSTED — its checksum proves integrity, not schema
    // validity. Each value is validated against a per-key type/range schema
    // before it is written. An invalid (wrong-type / out-of-range) value is
    // NOT persisted; instead the key is removed so its live reader falls back
    // to the safe default, and a non-fatal warning is recorded. This degrades a
    // corrupt value gracefully instead of letting it reach an unchecked cast
    // and brick startup — while every valid key still restores. Unknown
    // (forward-compatible) keys have no schema and pass through unchanged.
    for (final entry in doc.settings.entries) {
      if (!isBackupEligibleSettingKey(entry.key)) continue;
      if (validateBackupSettingValue(entry.key, entry.value) == false) {
        await settings.remove(entry.key);
        warnings.add(
          'Skipped an invalid value for "${entry.key}" from the backup; '
          'using its default instead.',
        );
        continue;
      }
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
            // diagnostics: silent — skip a corrupt entry rather than losing
            // the whole library.
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
            // diagnostics: silent — skip a corrupt entry rather than losing
            // every theme.
          }
        }
      }
    }
    return result;
  }
}
