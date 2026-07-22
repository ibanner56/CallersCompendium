import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import 'custom_theme.dart';

/// Current version of the composite [BackupDocument] envelope (ROADMAP G.5).
///
/// Bumped when the envelope shape changes in a way a reader must know about.
/// The reader is forward-compatible in the spirit of the 6.6 core codec: it
/// tolerates unknown keys, treats a missing version as the current one, and
/// reads a newer version on a best-effort basis with a warning rather than
/// failing.
const int backupSchemaVersion = 1;

/// A full-fidelity snapshot of the *entire* app state (ROADMAP G.5).
///
/// This wraps the 6.6 core [CompendiumArchive] (user content — dances, programs,
/// choreographers, sources, custom fields, tags) and layers in the app-local
/// pieces 6.6 deliberately excluded: the custom-dialect library (+ active-dialect
/// ref), custom themes (+ active custom theme), and the user preference settings.
///
/// Serialize with [encodeBackup]/[decodeBackup].
class BackupDocument {
  const BackupDocument({
    this.schemaVersion = backupSchemaVersion,
    required this.createdAt,
    required this.core,
    this.customDialects = const [],
    this.activeDialectRef,
    this.customThemes = const [],
    this.activeCustomThemeId,
    this.settings = const {},
  });

  /// The [backupSchemaVersion] this document was written under.
  final int schemaVersion;

  /// When the backup was produced (UTC).
  final DateTime createdAt;

  /// The core user-content archive (see [CompendiumArchive]).
  final CompendiumArchive core;

  /// The user's custom dialects (`kCustomDialectsKey`).
  final List<Dialect> customDialects;

  /// The active dialect name (a preset or custom name), or `null` for the app
  /// default (`kActiveDialectRefKey`).
  final String? activeDialectRef;

  /// The user's custom themes (`kCustomThemesKey`).
  final List<CustomTheme> customThemes;

  /// The active custom theme id, or `null` when a built-in theme is active
  /// (`kActiveCustomThemeKey`).
  final String? activeCustomThemeId;

  /// The backed-up preference settings, keyed by their `SettingsRepository`
  /// key. The set of keys is chosen by the exporter (`backup_service.dart`),
  /// which excludes device-local and structurally-represented keys.
  final Map<String, Object?> settings;
}

/// Outcome of decoding a backup document: the recovered [document] plus any
/// per-entity [errors] and non-fatal [warnings]. Mirrors the core
/// [ArchiveReadResult]; decoding never throws for recoverable problems — a
/// malformed piece is skipped and recorded while the rest still loads.
class BackupReadResult {
  const BackupReadResult({
    required this.document,
    this.errors = const [],
    this.warnings = const [],
    this.fatal = false,
    this.coreHasErrors = false,
    this.coreDroppedEntities = 0,
  });

  final BackupDocument document;
  final List<ArchiveError> errors;
  final List<String> warnings;

  /// Whether the envelope itself was unusable (not valid JSON, not a JSON
  /// object, or missing/invalid `core`). A fatal result must never drive a
  /// destructive restore — there is nothing safe to apply and doing so in
  /// replace mode would wipe live data. Per-entity problems (a single corrupt
  /// dialect/theme/dance) are recorded in [errors] but are NOT fatal.
  final bool fatal;

  /// Whether the **core** archive (the user's collection) had per-entity decode
  /// errors — a dance/program/etc. that could not be read. The envelope is
  /// structurally fine, but the core content did not fully decode.
  ///
  /// A replace restore wipes the live collection before loading the archive, so
  /// applying a core archive that is missing entities would silently lose data.
  /// [BackupService.restoreFromJson] therefore treats this like [fatal] in
  /// replace mode and refuses to touch live data.
  final bool coreHasErrors;

  /// How many core entities were **dropped** during decode because they carried
  /// an unknown enum value (a field written by a newer app version).
  ///
  /// Unlike [coreHasErrors] these are forward-compatible skips — a *merge* can
  /// safely keep the survivors. But a dropped entity still means the decoded
  /// core is not a faithful copy of the backup, so a destructive *replace*
  /// restore off it would silently discard those entities. This is tracked
  /// separately from [warnings] so the "incomplete core" signal cannot be lost
  /// among benign notes: [BackupService.restoreFromJson] refuses a replace when
  /// [coreIncomplete] is set (issue #430).
  final int coreDroppedEntities;

  /// Whether any core entity was dropped for forward-compatibility reasons.
  /// An incomplete core must never drive a destructive replace restore.
  bool get coreIncomplete => coreDroppedEntities > 0;

  bool get hasErrors => errors.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

/// Serializes [doc] to a JSON string. The nested core archive is emitted via
/// the core codec's canonical [archiveToJson] (structured JSON, not a
/// double-encoded string), so the whole document round-trips deterministically.
String encodeBackup(BackupDocument doc) => jsonEncode(backupToJson(doc));

/// The JSON object for [doc].
Map<String, Object?> backupToJson(BackupDocument doc) => {
  'backupVersion': doc.schemaVersion,
  'createdAt': doc.createdAt.toUtc().toIso8601String(),
  'core': archiveToJson(doc.core),
  'app': {
    'dialects': {
      'custom': [for (final d in doc.customDialects) d.toJson()],
      'activeRef': doc.activeDialectRef,
    },
    'themes': {
      'custom': [for (final t in doc.customThemes) t.toJson()],
      'activeId': doc.activeCustomThemeId,
    },
    'settings': doc.settings,
  },
};

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

BackupDocument _emptyDoc() => BackupDocument(
  createdAt: _epoch,
  core: CompendiumArchive(exportedAt: _epoch),
);

/// Decodes a backup JSON string into a [BackupDocument]. Forward-compatible and
/// partial-failure tolerant: unknown keys are ignored, a newer `backupVersion`
/// reads best-effort with a warning, and a malformed section is skipped and
/// recorded in [BackupReadResult.errors] while the rest still loads.
BackupReadResult decodeBackup(String json) {
  Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (e) {
    return BackupReadResult(
      document: _emptyDoc(),
      errors: [
        ArchiveError(
          kind: ArchiveErrorKind.read,
          entityType: 'backup',
          message: 'backup file is not valid JSON',
          cause: e,
        ),
      ],
      fatal: true,
    );
  }
  if (root is! Map) {
    return BackupReadResult(
      document: _emptyDoc(),
      errors: const [
        ArchiveError(
          kind: ArchiveErrorKind.read,
          entityType: 'backup',
          message: 'backup file is not a JSON object',
        ),
      ],
      fatal: true,
    );
  }
  return backupFromJson(root.cast<String, Object?>());
}

/// Decodes an already-parsed backup object. See [decodeBackup].
BackupReadResult backupFromJson(Map<String, Object?> root) {
  final errors = <ArchiveError>[];
  final warnings = <String>[];

  final rawVersion = root['backupVersion'];
  final version = rawVersion is int ? rawVersion : backupSchemaVersion;
  if (rawVersion is int && rawVersion > backupSchemaVersion) {
    warnings.add(
      'backup written by a newer version ($rawVersion > $backupSchemaVersion); '
      'reading on a best-effort basis',
    );
  }

  DateTime createdAt = _epoch;
  final rawCreatedAt = root['createdAt'];
  if (rawCreatedAt is String) {
    final parsed = DateTime.tryParse(rawCreatedAt);
    if (parsed != null) {
      createdAt = parsed.toUtc();
    } else {
      warnings.add('ignoring unparseable createdAt "$rawCreatedAt"');
    }
  }

  // --- core archive ---
  // A backup with no usable `core` is fatal: a destructive replace restore off
  // an empty archive would wipe live content. We record the problem and mark
  // the result fatal so the service refuses to touch live data.
  var coreFatal = false;
  var coreHasErrors = false;
  var coreDroppedEntities = 0;
  CompendiumArchive core = CompendiumArchive(exportedAt: _epoch);
  final rawCore = root['core'];
  if (rawCore is Map) {
    final coreResult = archiveFromJson(rawCore.cast<String, Object?>());
    core = coreResult.archive;
    coreHasErrors = coreResult.hasErrors;
    coreDroppedEntities = coreResult.droppedEntities.length;
    errors.addAll(coreResult.errors);
    warnings.addAll(coreResult.warnings);
  } else if (rawCore != null) {
    coreFatal = true;
    errors.add(
      const ArchiveError(
        kind: ArchiveErrorKind.read,
        entityType: 'backup',
        message: 'core section is not an object; no content restored',
      ),
    );
  } else {
    coreFatal = true;
    errors.add(
      const ArchiveError(
        kind: ArchiveErrorKind.read,
        entityType: 'backup',
        message: 'backup has no core section; no content restored',
      ),
    );
  }

  // --- app-local pieces ---
  final customDialects = <Dialect>[];
  String? activeDialectRef;
  final customThemes = <CustomTheme>[];
  String? activeCustomThemeId;
  var settings = <String, Object?>{};

  final rawApp = root['app'];
  if (rawApp is Map) {
    final app = rawApp.cast<String, Object?>();

    final rawDialects = app['dialects'];
    if (rawDialects is Map) {
      final dialects = rawDialects.cast<String, Object?>();
      final rawCustom = dialects['custom'];
      if (rawCustom is List) {
        for (final entry in rawCustom) {
          if (entry is Map) {
            try {
              customDialects.add(
                Dialect.fromJson(entry.cast<String, Object?>()),
              );
            } on Object catch (e) {
              errors.add(
                ArchiveError(
                  kind: ArchiveErrorKind.read,
                  entityType: 'dialect',
                  message: 'a custom dialect could not be read',
                  cause: e,
                ),
              );
            }
          }
        }
      }
      final ref = dialects['activeRef'];
      if (ref is String) activeDialectRef = ref;
    }

    final rawThemes = app['themes'];
    if (rawThemes is Map) {
      final themes = rawThemes.cast<String, Object?>();
      final rawCustom = themes['custom'];
      if (rawCustom is List) {
        for (final entry in rawCustom) {
          if (entry is Map) {
            try {
              customThemes.add(
                CustomTheme.fromJson(entry.cast<String, Object?>()),
              );
            } on Object catch (e) {
              errors.add(
                ArchiveError(
                  kind: ArchiveErrorKind.read,
                  entityType: 'theme',
                  message: 'a custom theme could not be read',
                  cause: e,
                ),
              );
            }
          }
        }
      }
      final id = themes['activeId'];
      if (id is String) activeCustomThemeId = id;
    }

    final rawSettings = app['settings'];
    if (rawSettings is Map) {
      settings = rawSettings.cast<String, Object?>();
    }
  }

  return BackupReadResult(
    document: BackupDocument(
      schemaVersion: version,
      createdAt: createdAt,
      core: core,
      customDialects: customDialects,
      activeDialectRef: activeDialectRef,
      customThemes: customThemes,
      activeCustomThemeId: activeCustomThemeId,
      settings: settings,
    ),
    errors: errors,
    warnings: warnings,
    fatal: coreFatal,
    coreHasErrors: coreHasErrors,
    coreDroppedEntities: coreDroppedEntities,
  );
}
