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

/// Whether an intake attempt produced a validated bundle or rejected it.
enum ArchiveIntakeStatus { validated, rejected }

/// Why an intake attempt was rejected. This is the stable, localization-friendly
/// discriminator the UI maps to a user-facing string (via
/// `archive_intake_labels.dart`) — intake itself never bakes English prose.
///
/// Every reason maps to a **generic, non-leaking** message: none echoes a path,
/// raw bytes, or lower-layer parser text (CWE-209).
enum ArchiveIntakeRejectionReason {
  /// The file exceeds the size cap (rejected before/without full read).
  tooLarge,

  /// The file could not be read from disk at all.
  unreadable,

  /// The file was empty.
  empty,

  /// The bytes are not a well-formed Caller's Compendium archive (bad UTF-8,
  /// non-archive JSON, or an unreadable envelope).
  notArchive,

  /// The archive was written by a newer app version than this build understands.
  newerVersion,

  /// The archive decoded fine but carried neither dances nor programs.
  noContent,
}

/// The outcome of an [ArchiveIntakeService] attempt. Intake **never throws** to
/// the caller: every failure — missing/unreadable file, oversized input,
/// non-text bytes, non-archive JSON, an unsupported (newer) schema, or an empty
/// bundle — resolves to a [rejected] result carrying a stable, non-leaking
/// [reason] the UI maps to a user-facing string.
///
/// A [validated] result carries the decoded [archive], the raw [json] the
/// review screen re-plans from, and the pre-computed [entityCount]
/// ([compendiumArchiveEntityCount]) used to decide the soft-cap warning. It
/// **does not** write anything: the commit is deferred to the review/consent
/// screen so nothing lands in the collection until the user confirms
/// (issue #432).
class ArchiveIntakeValidation {
  const ArchiveIntakeValidation._(
    this.status, {
    this.json,
    this.archive,
    this.entityCount = 0,
    this.reason,
  });

  factory ArchiveIntakeValidation.validated({
    required String json,
    required CompendiumArchive archive,
    required int entityCount,
  }) => ArchiveIntakeValidation._(
    ArchiveIntakeStatus.validated,
    json: json,
    archive: archive,
    entityCount: entityCount,
  );

  factory ArchiveIntakeValidation.rejected(
    ArchiveIntakeRejectionReason reason,
  ) => ArchiveIntakeValidation._(ArchiveIntakeStatus.rejected, reason: reason);

  final ArchiveIntakeStatus status;

  /// The raw, validated archive JSON. The review screen re-plans the dance side
  /// from this via the same `GenericJsonAdapter` path every import uses.
  final String? json;

  /// The decoded, validated archive. Committed (dances + programs + venues) by
  /// the review screen through [CompendiumArchiveImporter] **after** consent.
  final CompendiumArchive? archive;

  /// Total entities the bundle would write (dances + choreographers + programs
  /// + venues), computed pre-render from the validated decode — never trusted
  /// from a self-reported field in the untrusted bundle.
  final int entityCount;

  /// User-facing rejection reason as a stable discriminator. Deliberately
  /// carries no prose — the UI maps it to a generic, non-leaking localized
  /// string (`archive_intake_labels.dart`); it never echoes parser internals,
  /// paths, or stack traces (no information leak).
  final ArchiveIntakeRejectionReason? reason;

  bool get isValidated => status == ArchiveIntakeStatus.validated;
  bool get isRejected => status == ArchiveIntakeStatus.rejected;
}

/// Receives a shared [CompendiumArchive] file (from AirDrop / OS "Open with"),
/// and **validates it as untrusted input** — without writing anything.
///
/// This is the ingest gate for the share target (issue #298 receive side): the
/// bundle is decoded and every safety check runs Dart-side **before** any UI is
/// shown and **before** any write. A validated result is then handed to the
/// existing import review/consent screen, which is the only thing that commits —
/// so a shared/AirDropped bundle can never silently write into the trusted
/// collection without the user confirming first (issue #432).
///
/// Validation (OWASP — the file is untrusted):
/// - **Size cap** enforced before the file is read into memory.
/// - Bytes must decode as UTF-8 text.
/// - The text must decode as a **well-formed** [CompendiumArchive]; a root that
///   isn't a Compendium archive is rejected.
/// - The archive's schema version must not be **newer** than this build
///   understands (refuse forward, gracefully — don't guess).
/// - An empty bundle (no dances and no programs) is rejected.
/// - **Parse-never-throws:** all of the above resolve to an
///   [ArchiveIntakeValidation] — the caller never sees an exception.
class ArchiveIntakeService {
  ArchiveIntakeService({
    ArchiveByteReader? readBytes,
    this.maxBytes = kMaxIncomingArchiveBytes,
  }) : _injectedReader = readBytes;

  final ArchiveByteReader? _injectedReader;
  final int maxBytes;

  /// Reads the file at [path], then validates it. Any read failure is rejected
  /// gracefully; an oversized file is rejected without being read into memory.
  Future<ArchiveIntakeValidation> validateFromPath(String path) async {
    final Uint8List bytes;
    try {
      bytes = await (_injectedReader ?? _readFileWithCap)(path);
    } on OversizedArchiveException {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.tooLarge,
      );
    } catch (_) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.unreadable,
      );
    }
    return validateBytes(bytes);
  }

  /// Validates raw archive [bytes] and, on success, returns the decoded archive,
  /// the raw JSON, and the entity count — **without writing anything**. Exposed
  /// for the intake wiring and for tests (which inject bytes directly, avoiding
  /// disk and channels).
  Future<ArchiveIntakeValidation> validateBytes(Uint8List bytes) async {
    // Defense in depth: re-check the cap even when bytes are supplied directly.
    if (bytes.length > maxBytes) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.tooLarge,
      );
    }
    if (bytes.isEmpty) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.empty,
      );
    }

    final String json;
    try {
      json = utf8.decode(bytes);
    } catch (_) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.notArchive,
      );
    }

    final ArchiveReadResult read;
    try {
      read = decodeArchive(json);
    } catch (_) {
      // decodeArchive is contract-bound not to throw for recoverable problems,
      // but stay defensive — never let anything escape intake.
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.notArchive,
      );
    }

    final rootUnreadable = read.errors.any(
      (e) => e.entityType == 'archive' && e.kind == ArchiveErrorKind.read,
    );
    if (rootUnreadable) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.notArchive,
      );
    }

    final archive = read.archive;
    if (archive.schemaVersion > archiveSchemaVersion) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.newerVersion,
      );
    }

    if (archive.dances.isEmpty && archive.programs.isEmpty) {
      return ArchiveIntakeValidation.rejected(
        ArchiveIntakeRejectionReason.noContent,
      );
    }

    return ArchiveIntakeValidation.validated(
      json: json,
      archive: archive,
      entityCount: compendiumArchiveEntityCount(archive),
    );
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
