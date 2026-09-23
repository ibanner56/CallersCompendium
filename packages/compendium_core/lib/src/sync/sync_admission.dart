import 'canonical_json.dart';
import 'sync_codec.dart';
import 'sync_merge.dart';
import 'sync_record_kind.dart';
import 'sync_report.dart';
import 'wire_mapping.dart';
import '../storage/shareable_text.dart';

/// The result of admitting one inbound candidate for reconciliation and apply.
///
/// An accepted candidate carries the canonical wire blob that must be used for
/// persistence and retransmission. A rejected candidate carries one structured
/// report and must not enter reconciliation.
final class SyncInboundCandidateAdmission {
  const SyncInboundCandidateAdmission._({this.candidate, this.report});

  const SyncInboundCandidateAdmission.accepted(SyncMergeCandidate candidate)
    : this._(candidate: candidate);

  const SyncInboundCandidateAdmission.rejected(SyncReport report)
    : this._(report: report);

  final SyncMergeCandidate? candidate;
  final SyncReport? report;
}

/// Admits an inbound candidate without mutating storage.
///
/// The receiver may repair only the redundant timestamp projection carried by
/// dance and program bodies. Any other normalization change changes the
/// content named by the peer's wire hash and therefore requires the sender to
/// update before retrying.
SyncInboundCandidateAdmission admitSyncInboundCandidate(
  SyncMergeCandidate candidate,
) {
  final validation = validateShareableRecordBody(
    candidate.blob.kind,
    candidate.blob.body,
    settingsKey: candidate.blob.kind == SyncRecordKind.setting
        ? candidate.blob.id
        : null,
  );
  if (!validation.isValid) {
    return SyncInboundCandidateAdmission.rejected(
      SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        peerId: candidate.peerId,
        message:
            'Inbound body contains a non-shareable wire path '
            '${validation.invalidPath}.',
      ),
    );
  }
  if (_isReceiveOnlySetting(candidate)) {
    return SyncInboundCandidateAdmission.rejected(
      SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        peerId: candidate.peerId,
        message:
            'Inbound sync transport values are receive-only and were not '
            'adopted.',
      ),
    );
  }

  final Object? normalized;
  try {
    normalized = normalizeShareableJson(candidate.blob.body);
  } on ArgumentError catch (error) {
    return SyncInboundCandidateAdmission.rejected(
      SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        peerId: candidate.peerId,
        message: 'Inbound record body could not be normalized: $error.',
      ),
    );
  } on ShareableJsonKeyCollision catch (error) {
    return SyncInboundCandidateAdmission.rejected(
      SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        peerId: candidate.peerId,
        message:
            'Inbound record body has a normalized key collision: '
            '${error.normalizedKey}.',
      ),
    );
  }
  if (normalized is! Map) {
    return SyncInboundCandidateAdmission.rejected(
      SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        peerId: candidate.peerId,
        message: 'Inbound record body is not an object.',
      ),
    );
  }

  final normalizedBody = Map<String, Object?>.from(normalized);
  final originalForComparison = Map<String, Object?>.from(candidate.blob.body);
  final normalizedForComparison = Map<String, Object?>.from(normalizedBody);
  if (_allowsTimestampProjection(candidate.blob.kind)) {
    originalForComparison
      ..remove('updatedAt')
      ..remove('deletedAt');
    normalizedForComparison
      ..remove('updatedAt')
      ..remove('deletedAt');
  }
  if (canonicalJson(originalForComparison) !=
      canonicalJson(normalizedForComparison)) {
    return SyncInboundCandidateAdmission.rejected(
      SyncReport(
        code: SyncReportCode.nonCanonicalWireBody,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        peerId: candidate.peerId,
        message:
            'Inbound record body is not canonical. Update the sending device '
            'before retrying.',
      ),
    );
  }

  final admittedBody = _projectTimestampFields(
    kind: candidate.blob.kind,
    body: normalizedBody,
    updatedAt: candidate.blob.updatedAt,
    deletedAt: candidate.blob.deletedAt,
  );
  final admittedBlob = SyncRecordBlob(
    v: candidate.blob.v,
    kind: candidate.blob.kind,
    id: candidate.blob.id,
    updatedAt: candidate.blob.updatedAt,
    deletedAt: candidate.blob.deletedAt,
    existenceAt: candidate.blob.existenceAt,
    body: admittedBody,
  );
  if (canonicalJson(admittedBlob.toJson()) ==
      canonicalJson(candidate.blob.toJson())) {
    return SyncInboundCandidateAdmission.accepted(candidate);
  }
  return SyncInboundCandidateAdmission.accepted(
    SyncMergeCandidate(blob: admittedBlob, peerId: candidate.peerId),
  );
}

/// The two settings keys the protocol puts on the wire and must never adopt
/// back: the store address a device is attached to, and its own routing
/// identifier. Adopting either from a peer repoints this device at another
/// store or collides two devices in one manifest namespace.
///
/// This matches on the key name rather than on [EgressClass] deliberately —
/// it is defence in depth that holds even if a classification is got wrong —
/// which is why reclassifying either key does not turn this path red. The
/// send-side half is guarded in `sync_codec_test.dart` instead.
bool _isReceiveOnlySetting(SyncMergeCandidate candidate) =>
    candidate.blob.kind == SyncRecordKind.setting &&
    (candidate.blob.id == 'sync_id' || candidate.blob.id == 'sync_device_id');

bool _allowsTimestampProjection(SyncRecordKind kind) =>
    kind == SyncRecordKind.dance || kind == SyncRecordKind.program;

Map<String, Object?> _projectTimestampFields({
  required SyncRecordKind kind,
  required Map<String, Object?> body,
  required DateTime updatedAt,
  required DateTime? deletedAt,
}) {
  if (!_allowsTimestampProjection(kind)) return body;
  return Map<String, Object?>.from(body)
    ..['updatedAt'] = updatedAt.toIso8601String()
    ..['deletedAt'] = deletedAt?.toIso8601String();
}
