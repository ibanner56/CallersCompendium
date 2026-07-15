import 'package:meta/meta.dart';

import '../model/enums.dart';

/// A source-native record captured verbatim during the `fetch` stage of the
/// import pipeline (`docs/design/imports.md`).
///
/// The [payload] is preserved exactly as fetched from the source so that
/// re-import and diffing are always possible: it, together with
/// [sourceVersion], feeds `provenance.raw_payload` / `provenance.source_version`
/// on commit. [permission] / [license] carry the source's own tier/terms
/// verbatim (interpreted by import/export policy, not by the model).
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
  /// revision). Preserved for re-import/diff; feeds `provenance.source_version`.
  final String? sourceVersion;

  /// The record exactly as fetched, preserved byte-for-byte (as text). Feeds
  /// `provenance.raw_payload`.
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
