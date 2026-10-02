import 'package:meta/meta.dart';

import '../model/enums.dart';

/// Which pipeline stage produced an [ImportError].
enum ImportStage { discover, fetch, parse, dedupe, commit }

/// Why an import failed, as a closed set the UI can map to one localized,
/// placeholder-free string. This is the only part of an [ImportError] that is
/// rendered: [ImportError.message] may echo user content (CWE-209) and is for
/// logs only. Precedent: `ImportIssue.code` (`structured_draft.dart`).
enum ImportErrorCode {
  /// No specific reason is known; the UI falls back to a per-[ImportStage]
  /// message.
  unknown,

  /// The file or pasted text was empty.
  emptyFile,

  /// The content is not JSON.
  notJson,

  /// The content is JSON (or bytes) but not a Caller's Compendium archive.
  notCompendiumArchive,

  /// The content is not a Caller's Box dance export.
  notCallersBoxDance,

  /// The content is not a ContraDB dance export or page.
  notContraDbDance,

  /// The file is not a readable Caller's Companion `.USR` database.
  notUsrDatabase,

  /// The file exceeds the import size or structure limits.
  fileTooLarge,

  /// A Caller's Box payload was read but contains no dance.
  noDanceAtId,
}

/// A structured import failure carrying source context, so the UI can report
/// "record N from The Caller's Box failed to parse" rather than surfacing a
/// raw stack trace (`docs/design/imports.md`, "Error handling & testing").
///
/// Errors are values, not thrown control flow, for the per-record path: a
/// batch collects them and imports the rest (partial-batch tolerance). They
/// *may* wrap an underlying [cause] for logging. The [message] is a
/// diagnostic description for logs and tests only, never a stack trace; it can
/// echo untrusted parser or user content, so the UI renders [code] instead.
@immutable
class ImportError implements Exception {
  const ImportError({
    required this.stage,
    required this.source,
    required this.message,
    this.code = ImportErrorCode.unknown,
    this.externalId,
    this.cause,
  });

  final ImportStage stage;
  final ProvenanceSource source;

  /// Human-readable, source-contextual description (no stack traces). For
  /// logs and tests only: it may embed user content, so the UI renders [code]
  /// instead.
  final String message;

  /// Typed reason the UI maps to a localized string.
  final ImportErrorCode code;

  /// The source-native id of the record this error concerns, if known.
  final String? externalId;

  /// Optional underlying error for diagnostics/logging only. Never rendered
  /// as UX.
  final Object? cause;

  ImportError copyWith({
    ImportStage? stage,
    ProvenanceSource? source,
    String? message,
    ImportErrorCode? code,
    String? externalId,
    Object? cause,
  }) => ImportError(
    stage: stage ?? this.stage,
    source: source ?? this.source,
    message: message ?? this.message,
    code: code ?? this.code,
    externalId: externalId ?? this.externalId,
    cause: cause ?? this.cause,
  );

  @override
  String toString() {
    final where = externalId == null ? '' : ' (record $externalId)';
    final codeText = code == ImportErrorCode.unknown ? '' : ' <${code.name}>';
    return 'ImportError[${stage.name}]$codeText ${source.name}$where: $message';
  }
}

/// Convenience constructors for the common stages. Kept as factories on a
/// separate extension-free set of helpers so call sites read naturally while
/// [ImportError] stays a single concrete type (its [stage] is the
/// discriminator).
ImportError fetchError(
  ProvenanceSource source,
  String message, {
  String? externalId,
  Object? cause,
}) => ImportError(
  stage: ImportStage.fetch,
  source: source,
  message: message,
  externalId: externalId,
  cause: cause,
);

ImportError parseError(
  ProvenanceSource source,
  String message, {
  String? externalId,
  Object? cause,
}) => ImportError(
  stage: ImportStage.parse,
  source: source,
  message: message,
  externalId: externalId,
  cause: cause,
);

ImportError commitError(
  ProvenanceSource source,
  String message, {
  String? externalId,
  Object? cause,
}) => ImportError(
  stage: ImportStage.commit,
  source: source,
  message: message,
  externalId: externalId,
  cause: cause,
);
