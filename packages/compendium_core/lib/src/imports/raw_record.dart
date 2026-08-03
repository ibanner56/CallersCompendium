import 'package:meta/meta.dart';

import '../model/enums.dart';

/// A source-native record captured verbatim during the `fetch` stage of the
/// import pipeline (`docs/design/imports.md`).
///
/// The [payload] is preserved exactly as fetched so the adapter's `parse` step
/// has the unmodified source to work from. It is **not persisted**: it fed
/// `provenance.raw_payload` until schema v21 dropped that column (#781), since
/// nothing ever read it back. [sourceVersion], [permission] and [license] *are*
/// persisted, onto the matching `provenance` columns (interpreted by
/// import/export policy, not by the model).
///
/// Re-import does not depend on a stored payload: it dedupes on
/// `(source, externalId)` and re-fetches from the source.
///
/// This is a pure value object with no knowledge of how the payload is parsed
/// — that is the adapter's `parse` step, which turns a [RawRecord] into a
/// [StructuredDraft].
@immutable
class RawRecord {
  const RawRecord({
    required this.source,
    this.externalId,
    this.sourceVersion,
    required this.payload,
    this.contentType,
    this.permission,
    this.license,
  });

  /// Which source this record came from.
  final ProvenanceSource source;

  /// Stable source-native identifier (e.g. a The Caller's Box dance id). Used
  /// as the primary dedupe key `(source, externalId)`; `null` for sources that
  /// have no stable per-record id.
  final String? externalId;

  /// Opaque source/schema version tag (e.g. a snapshot date or format
  /// revision). Feeds `provenance.source_version`.
  final String? sourceVersion;

  /// The record exactly as fetched, preserved byte-for-byte (as text), for the
  /// adapter's `parse` step. In-memory only — never persisted (see above).
  final String payload;

  /// Optional MIME/content hint for the payload (e.g. `application/json`),
  /// informational only.
  final String? contentType;

  /// The source's permission tier verbatim (e.g. The Caller's Box `full` /
  /// `search`). Copied onto `provenance.permission`; interpreted by policy.
  final String? permission;

  /// The source's license string verbatim, if any. Copied onto
  /// `provenance.license`.
  final String? license;

  RawRecord copyWith({
    ProvenanceSource? source,
    String? externalId,
    String? sourceVersion,
    String? payload,
    String? contentType,
    String? permission,
    String? license,
  }) => RawRecord(
    source: source ?? this.source,
    externalId: externalId ?? this.externalId,
    sourceVersion: sourceVersion ?? this.sourceVersion,
    payload: payload ?? this.payload,
    contentType: contentType ?? this.contentType,
    permission: permission ?? this.permission,
    license: license ?? this.license,
  );

  @override
  bool operator ==(Object other) =>
      other is RawRecord &&
      other.source == source &&
      other.externalId == externalId &&
      other.sourceVersion == sourceVersion &&
      other.payload == payload &&
      other.contentType == contentType &&
      other.permission == permission &&
      other.license == license;

  @override
  int get hashCode => Object.hash(
    source,
    externalId,
    sourceVersion,
    payload,
    contentType,
    permission,
    license,
  );

  @override
  String toString() =>
      'RawRecord(${source.name}, externalId: $externalId, '
      '${payload.length} bytes)';
}
