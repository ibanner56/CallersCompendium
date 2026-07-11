import 'package:meta/meta.dart';

import 'enums.dart';

/// Import provenance for a dance: where it came from, when, under what
/// permission/license, and the raw payload as imported (enables re-import
/// diffing, attribution display, and honoring source permission tiers).
@immutable
class Provenance {
  const Provenance({
    required this.source,
    this.externalId,
    required this.importedAt,
    this.permission,
    this.license,
    this.rawPayload,
    this.sourceVersion,
  });

  final ProvenanceSource source;
  final String? externalId;
  final DateTime importedAt;

  /// Source permission tier verbatim (e.g. The Caller's Box "full",
  /// "search"). Interpreted by import/export policy, not by the model.
  final String? permission;
  final String? license;

  /// The record exactly as fetched from the source, for re-import/diff.
  final String? rawPayload;
  final String? sourceVersion;
}
