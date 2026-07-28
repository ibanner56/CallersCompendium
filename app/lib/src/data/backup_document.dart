import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'custom_theme.dart';

/// Current version of the composite [BackupDocument] envelope (ROADMAP G.5).
///
/// Bumped when the envelope shape changes in a way a reader must know about.
/// The reader is forward-compatible in the spirit of the 6.6 core codec: it
/// tolerates unknown keys, treats a missing version as the current one, and
/// reads a newer version on a best-effort basis with a warning rather than
/// failing.
const int backupSchemaVersion = 1;

/// Current version of the backup **container** envelope (issue #536).
///
/// The container wraps the [BackupDocument] JSON [payload] with a SHA-256
/// integrity checksum so a corrupted or altered backup fails to restore
/// *loudly* instead of silently importing garbage. This is deliberately just a
/// plain hash, not a keyed MAC: it detects accidental corruption and casual
/// tampering, **not** a determined adversary (who could recompute the hash).
/// Confidentiality is intentionally out of scope — backups replaced the former
/// opt-in `.ccbackup` encryption (see #536 for the rationale).
///
/// Bumped independently of [backupSchemaVersion], which versions the *document*
/// carried inside the payload.
const int backupContainerVersion = 1;

/// The only checksum algorithm the container understands. A backup that names
/// anything else is refused rather than trusted.
const String kBackupChecksumAlgorithm = 'sha256';

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
    this.integrityFailed = false,
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

  /// Whether the backup was refused specifically because its **integrity
  /// checksum did not verify** (issue #536) — the file is corrupt or was
  /// altered after export, so restoring it could import garbage. Always implies
  /// [fatal]; tracked separately so the UI can say "this backup failed its
  /// integrity check" instead of a generic "invalid file".
  final bool integrityFailed;

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

/// Serializes [doc] to an integrity-checked backup **container** string
/// (issue #536): the canonical document JSON [payload] wrapped with a SHA-256
/// checksum over its exact UTF-8 bytes. [decodeBackup] verifies that checksum
/// and refuses a payload that has been corrupted or altered.
///
/// The nested core archive is emitted via the core codec's canonical
/// [archiveToJson] (structured JSON, not a double-encoded string), so the
/// document round-trips deterministically.
String encodeBackup(BackupDocument doc) =>
    jsonEncode(_wrapWithChecksum(encodeBackupPayload(doc)));

/// Serializes just the [doc] payload (no container/checksum) to a JSON string.
///
/// This is the exact byte sequence the container checksums and that
/// [backupFromJson] decodes. Exposed for tests and callers that need the raw
/// document; production export goes through [encodeBackup].
String encodeBackupPayload(BackupDocument doc) => jsonEncode(backupToJson(doc));

/// Wraps a document [payload] JSON string in the checksum container object.
Map<String, Object?> _wrapWithChecksum(String payload) => {
  'backupContainer': backupContainerVersion,
  'checksum': {
    'algorithm': kBackupChecksumAlgorithm,
    'value': _sha256Hex(payload),
  },
  'payload': payload,
};

/// Lowercase hex SHA-256 of [text]'s UTF-8 bytes.
String _sha256Hex(String text) =>
    crypto.sha256.convert(utf8.encode(text)).toString();

/// Constant-time comparison of two equal-purpose hex strings, so verifying the
/// checksum never leaks position-of-first-difference timing (defensive; the
/// hash isn't secret, but constant-time compare is the correct habit).
bool _hexEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

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

/// A fatal, nothing-applied [BackupReadResult] carrying a single backup-level
/// [message]. Used for envelope problems that must refuse a restore outright.
BackupReadResult _fatalBackup(String message) => BackupReadResult(
  document: _emptyDoc(),
  errors: [
    ArchiveError(
      kind: ArchiveErrorKind.read,
      entityType: 'backup',
      message: message, // i18n-ignore: internal diagnostic, never shown
    ),
  ],
  fatal: true,
);

/// Decodes a backup string into a [BackupDocument]. Forward-compatible and
/// partial-failure tolerant: unknown keys are ignored, a newer `backupVersion`
/// reads best-effort with a warning, and a malformed section is skipped and
/// recorded in [BackupReadResult.errors] while the rest still loads.
///
/// Accepts two shapes (issue #536):
/// - the current **container** — `{backupContainer, checksum, payload}` — whose
///   `payload` is the document JSON string. Its SHA-256 checksum is verified
///   first; a missing, malformed, or mismatched checksum is refused as
///   [BackupReadResult.integrityFailed] (and [BackupReadResult.fatal]) so a
///   corrupt/altered file never drives a restore.
/// - a legacy **bare** document object (a plain `.json` exported before #536, or
///   the inner payload itself), which is decoded directly with no checksum.
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
          message:
              'backup file is not valid JSON', // i18n-ignore: internal diagnostic, never shown
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
          message:
              'backup file is not a JSON object', // i18n-ignore: internal diagnostic, never shown
        ),
      ],
      fatal: true,
    );
  }
  final map = root.cast<String, Object?>();

  // Container format (#536): a String `payload` means this is a checksummed
  // container. Verify integrity before trusting anything inside. Containers
  // never nest — the verified payload is decoded as a bare document directly,
  // so a maliciously nested container can't drive unbounded recursion.
  final rawPayload = map['payload'];
  if (rawPayload is String) {
    // The container carries an explicit version (#536). Validate it before
    // trusting the envelope: a missing/malformed version, or one newer than
    // this build understands, is refused *cleanly* rather than mis-decoded
    // against v1 assumptions (a future envelope may move the checksum or change
    // the payload contract). This is a format-version refusal, not a tamper
    // signal, so it is fatal but not `integrityFailed`.
    final rawContainerVersion = map['backupContainer'];
    if (rawContainerVersion is! int) {
      return _fatalBackup(
        'backup container is missing or has a malformed version',
      );
    }
    if (rawContainerVersion > backupContainerVersion) {
      return _fatalBackup(
        'backup container is a newer, unsupported version '
        '($rawContainerVersion > $backupContainerVersion)',
      );
    }
    final integrityError = _verifyContainerChecksum(map, rawPayload);
    if (integrityError != null) {
      return BackupReadResult(
        document: _emptyDoc(),
        errors: [integrityError],
        fatal: true,
        integrityFailed: true,
      );
    }
    Object? inner;
    try {
      inner = jsonDecode(rawPayload);
    } on FormatException catch (e) {
      return BackupReadResult(
        document: _emptyDoc(),
        errors: [
          ArchiveError(
            kind: ArchiveErrorKind.read,
            entityType: 'backup',
            message:
                'backup payload is not valid JSON', // i18n-ignore: internal diagnostic, never shown
            cause: e,
          ),
        ],
        fatal: true,
      );
    }
    if (inner is! Map) {
      return BackupReadResult(
        document: _emptyDoc(),
        errors: const [
          ArchiveError(
            kind: ArchiveErrorKind.read,
            entityType: 'backup',
            message:
                'backup payload is not a JSON object', // i18n-ignore: internal diagnostic, never shown
          ),
        ],
        fatal: true,
      );
    }
    return backupFromJson(inner.cast<String, Object?>());
  }

  // Legacy bare document (plain `.json` exported before #536): decode directly.
  return backupFromJson(map);
}

/// Verifies a container's SHA-256 [payload] checksum. Returns `null` when the
/// checksum is present, uses the supported algorithm, and matches; otherwise
/// returns the [ArchiveError] describing why the backup must be refused.
///
/// A container that omits the checksum, names an unsupported algorithm, or
/// whose value doesn't match is treated as a failed integrity check rather than
/// trusted — the whole point is that stripping/altering the checksum can't
/// launder a tampered payload past the guard.
ArchiveError? _verifyContainerChecksum(
  Map<String, Object?> container,
  String payload,
) {
  ArchiveError fail(String message) => ArchiveError(
    kind: ArchiveErrorKind.read,
    entityType: 'backup',
    message: message, // i18n-ignore: internal diagnostic, never shown
  );

  final rawChecksum = container['checksum'];
  if (rawChecksum is! Map) {
    return fail('backup container is missing its integrity checksum');
  }
  final checksum = rawChecksum.cast<String, Object?>();
  final algorithm = checksum['algorithm'];
  if (algorithm != kBackupChecksumAlgorithm) {
    return fail('backup uses an unsupported checksum algorithm');
  }
  final value = checksum['value'];
  if (value is! String || value.isEmpty) {
    return fail('backup integrity checksum is missing or malformed');
  }
  if (!_hexEquals(_sha256Hex(payload), value.toLowerCase())) {
    return fail('backup failed its integrity check (corrupt or altered)');
  }
  return null;
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
        message:
            'core section is not an object; no content restored', // i18n-ignore: internal diagnostic, never shown
      ),
    );
  } else {
    coreFatal = true;
    errors.add(
      const ArchiveError(
        kind: ArchiveErrorKind.read,
        entityType: 'backup',
        message:
            'backup has no core section; no content restored', // i18n-ignore: internal diagnostic, never shown
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
                  message:
                      'a custom dialect could not be read', // i18n-ignore: internal diagnostic, never shown
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
                  message:
                      'a custom theme could not be read', // i18n-ignore: internal diagnostic, never shown
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
