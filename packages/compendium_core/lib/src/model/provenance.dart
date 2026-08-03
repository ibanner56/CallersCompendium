import 'package:meta/meta.dart';

import 'enums.dart';

/// Import provenance for a dance: where it came from, when, and under what
/// permission/license. Drives attribution display, honouring source permission
/// tiers, and re-import dedupe (keyed on `(source, externalId)`).
///
/// Carried a `rawPayload` — the record exactly as fetched — until schema v21.
/// Its doc comment justified it as enabling "re-import diffing". Re-import
/// diffing does exist (`figure_diff.dart`, surfaced by the import review
/// screen), but it compares **parsed figures** and never read this column;
/// nothing else read it either, so it was dropped (#781). Re-import dedupes on
/// `(source, externalId)` and re-fetches from the source, which needs no
/// stored copy.
@immutable
class Provenance {
  const Provenance({
    required this.source,
    this.externalId,
    required this.importedAt,
    this.permission,
    this.license,
    this.sourceVersion,
  });

  final ProvenanceSource source;
  final String? externalId;
  final DateTime importedAt;

  /// Source permission tier verbatim (e.g. The Caller's Box "full",
  /// "search"). Interpreted by import/export policy, not by the model.
  final String? permission;
  final String? license;
  final String? sourceVersion;

  @override
  bool operator ==(Object other) =>
      other is Provenance &&
      other.source == source &&
      other.externalId == externalId &&
      other.importedAt == importedAt &&
      other.permission == permission &&
      other.license == license &&
      other.sourceVersion == sourceVersion;

  @override
  int get hashCode => Object.hash(
    source,
    externalId,
    importedAt,
    permission,
    license,
    sourceVersion,
  );
}
