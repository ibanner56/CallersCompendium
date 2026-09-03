import 'package:compendium_core/compendium_core.dart';

/// Privacy classification for fields persisted by Athenaeum.
///
/// This registry describes server persistence. W11's upload allow-list remains
/// generated from the shared client registries.
const Map<String, DataClassification> serverFieldClassifications = {
  'stores.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note: 'HMAC-derived store address; plaintext sync IDs are never persisted.',
  ),
  'stores.epoch': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'stores.created_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'stores.last_seen': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'stores.bytes_used': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'manifests.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'manifests.epoch': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'manifests.device_id': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.protocolIdentifier,
    isIdentity: true,
    note: 'Opaque routing identifier; never adopted from a peer.',
  ),
  'manifests.etag': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'manifests.written_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'manifests.body': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note: 'Contains only the protocol manifest, not record content.',
  ),
  'blob_refs.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'blob_refs.epoch': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'blob_refs.hash': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'blob_refs.size': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'blob_refs.uploaded_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'deletion_jobs.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'deletion_jobs.epoch': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note: 'Identifies the epoch directory awaiting filesystem cleanup.',
  ),
  'deletion_jobs.queued_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'blob_deletion_jobs.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'blob_deletion_jobs.epoch': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'blob_deletion_jobs.hash': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'blob_deletion_jobs.queued_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'break_glass_access.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Peppered pseudonymous store key; eligible after 30 days and nulled by '
        'the next hourly sweep.',
  ),
  'break_glass_access.accessed_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note: 'Retained audit timestamp without a linkable store key.',
  ),
  'diagnostic_events.status': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'diagnostic_events.id_key': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Peppered pseudonymous store key; eligible after 30 days and removed by '
        'the next hourly sweep.',
  ),
  'diagnostic_events.hash': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
  ),
  'diagnostic_events.recorded_at': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Diagnostic event timestamp; eligible after 30 days and removed by the '
        'next hourly sweep.',
  ),
  'blob_files.body': DataClassification(
    term: DpvTerm.unclassifiedPersonal,
    subject: DataSubject.thirdParty,
    egress: EgressClass.shareable,
    note:
        'Opaque record payload stored by content hash; may contain third-party '
        'data and is intentionally shareable through Device Sync.',
  ),
  'config.pepper': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note: 'Deployment secret; required at startup and never persisted.',
  ),
};

const List<String> serverConfigurationFields = ['config.pepper'];
