import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';

/// Hard cap on the size of an incoming shared archive, in bytes.
///
/// A received file is **untrusted input** (OWASP): AirDrop / "Open with" hands
/// us an arbitrary file. We refuse anything larger than this *before* reading it
/// fully into memory, so a hostile or accidental multi-gigabyte file can't
/// exhaust memory. 25 MiB is far above any realistic program+dances bundle
/// (which is compact JSON) while still bounding the blast radius.
const int kMaxIncomingArchiveBytes = 25 * 1024 * 1024;

/// Reads the bytes of a file at [path]. The default reads from disk (enforcing
/// the size cap); tests inject bytes directly, so no real file or platform
/// channel is touched.
typedef ArchiveByteReader = Future<Uint8List> Function(String path);

/// Raised by the default file reader when a file exceeds the size cap, so the
/// oversized case is rejected *without* reading the whole file into memory.
class OversizedArchiveException implements Exception {
  const OversizedArchiveException(this.length);
  final int length;
  @override
  String toString() => 'OversizedArchiveException($length)';
}

/// Whether an intake attempt imported a bundle or rejected it.
enum ArchiveIntakeStatus { imported, rejected }

/// The outcome of an [ArchiveIntakeService] attempt. Intake **never throws** to
/// the caller: every failure — missing/unreadable file, oversized input,
/// non-text bytes, non-archive JSON, an unsupported (newer) schema, or a commit
/// error — resolves to a [rejected] result carrying a short, non-leaking,
/// user-facing [message]. Success carries the [programId] to auto-open (or
/// `null` when the bundle held only dances) and any non-fatal [issues].
class ArchiveIntakeResult {
  const ArchiveIntakeResult._(
    this.status, {
    this.programId,
    this.message,
    this.issues = const [],
  });

  factory ArchiveIntakeResult.imported({
    String? programId,
    List<ImportIssue> issues = const [],
  }) => ArchiveIntakeResult._(
    ArchiveIntakeStatus.imported,
    programId: programId,
    issues: issues,
  );

  factory ArchiveIntakeResult.rejected(String message) =>
      ArchiveIntakeResult._(ArchiveIntakeStatus.rejected, message: message);

  final ArchiveIntakeStatus status;

  /// The imported program to auto-open, or `null` (bundle had no program).
  final String? programId;

  /// User-facing rejection reason. Deliberately generic — it never echoes
  /// parser internals, paths, or stack traces (no information leak).
  final String? message;

  /// Non-fatal issues raised while importing (e.g. an unresolved dance
  /// reference degraded to a note). Empty on rejection.
  final List<ImportIssue> issues;

  bool get isImported => status == ArchiveIntakeStatus.imported;
  bool get isRejected => status == ArchiveIntakeStatus.rejected;
}

/// Receives a shared [CompendiumArchive] file (from AirDrop / OS "Open with"),
/// **validates it as untrusted input**, and imports it — the program **and** its
/// dances — through the existing shared commit path
/// ([CompendiumArchiveImporter], which drives the core [ImportPipeline]). It
/// then reports the imported program so the UI can auto-open it.
///
/// Validation (OWASP — the file is untrusted):
/// - **Size cap** enforced before the file is read into memory.
/// - Bytes must decode as UTF-8 text.
/// - The text must decode as a **well-formed** [CompendiumArchive]; a root that
///   isn't a Compendium archive is rejected.
/// - The archive's schema version must not be **newer** than this build
///   understands (refuse forward, gracefully — don't guess).
/// - Nothing is executed or trusted beyond the declared schema; import is
///   verbatim and identity-first (dedupe, never duplicate) via the importer.
/// - **Parse-never-throws:** all of the above resolve to a [ArchiveIntakeResult]
///   — the caller never sees an exception or a partial write.
class ArchiveIntakeService {
  ArchiveIntakeService({
    required this.repositories,
    ArchiveByteReader? readBytes,
    this.maxBytes = kMaxIncomingArchiveBytes,
    DateTime Function()? now,
    this.newId,
    this.newSlotId,
  }) : _injectedReader = readBytes,
       _now = now ?? (() => DateTime.now().toUtc());

  final CompendiumRepositories repositories;
  final ArchiveByteReader? _injectedReader;
  final int maxBytes;
  final DateTime Function() _now;
  final String Function()? newId;
  final String Function()? newSlotId;

  /// Reads the file at [path], then imports it. Any read failure is rejected
  /// gracefully; an oversized file is rejected without being read into memory.
  Future<ArchiveIntakeResult> importFromPath(String path) async {
    final Uint8List bytes;
    try {
      bytes = await (_injectedReader ?? _readFileWithCap)(path);
    } on OversizedArchiveException {
      return ArchiveIntakeResult.rejected('That file is too large to import.');
    } catch (_) {
      return ArchiveIntakeResult.rejected("Couldn't read the shared file.");
    }
    return importBytes(bytes);
  }

  /// Validates and imports raw archive [bytes]. Exposed for the intake wiring
  /// and for tests (which inject bytes directly, avoiding disk and channels).
  Future<ArchiveIntakeResult> importBytes(Uint8List bytes) async {
    // Defense in depth: re-check the cap even when bytes are supplied directly.
    if (bytes.length > maxBytes) {
      return ArchiveIntakeResult.rejected('That file is too large to import.');
    }
    if (bytes.isEmpty) {
      return ArchiveIntakeResult.rejected('That file is empty.');
    }

    final String json;
    try {
      json = utf8.decode(bytes);
    } catch (_) {
      return ArchiveIntakeResult.rejected(
        "That file isn't a Caller's Compendium share file.",
      );
    }

    final ArchiveReadResult read;
    try {
      read = decodeArchive(json);
    } catch (_) {
      // decodeArchive is contract-bound not to throw for recoverable problems,
      // but stay defensive — never let anything escape intake.
      return ArchiveIntakeResult.rejected(
        "That file isn't a Caller's Compendium share file.",
      );
    }

    final rootUnreadable = read.errors.any(
      (e) => e.entityType == 'archive' && e.kind == ArchiveErrorKind.read,
    );
    if (rootUnreadable) {
      return ArchiveIntakeResult.rejected(
        "That file isn't a Caller's Compendium share file.",
      );
    }

    final archive = read.archive;
    if (archive.schemaVersion > archiveSchemaVersion) {
      return ArchiveIntakeResult.rejected(
        'That file was made by a newer version of the app. Please update to '
        'import it.',
      );
    }

    if (archive.dances.isEmpty && archive.programs.isEmpty) {
      return ArchiveIntakeResult.rejected(
        "That file didn't contain any dances or programs.",
      );
    }

    try {
      final pipeline = ImportPipeline(
        repositories.dances,
        repositories.choreographers,
      );
      final importer = CompendiumArchiveImporter(
        pipeline,
        repositories.programs,
        repositories.venues,
      );
      final result = await importer.import(
        json,
        archive,
        now: _now(),
        newId: newId,
        newSlotId: newSlotId,
      );
      return ArchiveIntakeResult.imported(
        programId: result.primaryProgramId,
        issues: result.programIssues,
      );
    } catch (_) {
      return ArchiveIntakeResult.rejected("Couldn't import the shared file.");
    }
  }

  Future<Uint8List> _readFileWithCap(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length > maxBytes) {
      throw OversizedArchiveException(length);
    }
    return file.readAsBytes();
  }
}
