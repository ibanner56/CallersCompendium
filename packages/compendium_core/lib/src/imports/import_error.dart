import 'package:meta/meta.dart';

import '../model/enums.dart';

/// Which pipeline stage produced an [ImportError].
enum ImportStage { discover, fetch, parse, dedupe, commit }

/// A structured import failure carrying source context, so the UI can report
/// "record N from The Caller's Box failed to parse" rather than surfacing a
/// raw stack trace (`docs/design/imports.md`, "Error handling & testing").
///
/// Errors are values, not thrown control flow, for the per-record path: a
/// batch collects them and imports the rest (partial-batch tolerance). They
/// *may* wrap an underlying [cause] for logging, but the [message] is the
/// user-facing text and never a stack trace.
@immutable
class ImportError implements Exception {
  const ImportError({
    required this.stage,
    required this.source,
    required this.message,
    this.externalId,
    this.cause,
  });

  final ImportStage stage;
  final ProvenanceSource source;

  /// Human-readable, source-contextual description (no stack traces).
  final String message;

  /// The source-native id of the record this error concerns, if known.
  final String? externalId;

  /// Optional underlying error for diagnostics/logging only. Never rendered
  /// as UX.
  final Object? cause;

  ImportError copyWith({
    ImportStage? stage,
    ProvenanceSource? source,
    String? message,
    String? externalId,
    Object? cause,
  }) => ImportError(
    stage: stage ?? this.stage,
    source: source ?? this.source,
    message: message ?? this.message,
    externalId: externalId ?? this.externalId,
    cause: cause ?? this.cause,
  );

  @override
  String toString() {
    final where = externalId == null ? '' : ' (record $externalId)';
    return 'ImportError[${stage.name}] ${source.name}$where: $message';
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
