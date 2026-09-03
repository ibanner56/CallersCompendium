/// Privacy classification for fields persisted by the Athenaeum service.
///
/// This registry is deliberately separate from the client upload allow-list:
/// it describes server persistence, while uploads are checked against the
/// shared [compendium_core] registries.
enum ServerDataCategory { accessControl, protocol, metadata, sharedContent }

enum ServerDataSubject { none, syncParticipant, sharedCollection }

enum ServerDataEgress { serverInternal, authenticatedResponse }

class ServerFieldClassification {
  const ServerFieldClassification({
    required this.category,
    required this.subject,
    required this.egress,
    this.note,
  });

  final ServerDataCategory category;
  final ServerDataSubject subject;
  final ServerDataEgress egress;
  final String? note;
}

/// Every persisted SQLite/configuration field must appear here.
const Map<String, ServerFieldClassification> serverFieldClassifications = {
  'stores.id_key': ServerFieldClassification(
    category: ServerDataCategory.accessControl,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
    note: 'HMAC-derived store address; plaintext sync IDs are never persisted.',
  ),
  'stores.epoch': ServerFieldClassification(
    category: ServerDataCategory.protocol,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'stores.created_at': ServerFieldClassification(
    category: ServerDataCategory.metadata,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'stores.last_seen': ServerFieldClassification(
    category: ServerDataCategory.metadata,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'stores.bytes_used': ServerFieldClassification(
    category: ServerDataCategory.metadata,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'manifests.id_key': ServerFieldClassification(
    category: ServerDataCategory.accessControl,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'manifests.epoch': ServerFieldClassification(
    category: ServerDataCategory.protocol,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'manifests.device_id': ServerFieldClassification(
    category: ServerDataCategory.protocol,
    subject: ServerDataSubject.syncParticipant,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'manifests.etag': ServerFieldClassification(
    category: ServerDataCategory.protocol,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'manifests.written_at': ServerFieldClassification(
    category: ServerDataCategory.metadata,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'manifests.body': ServerFieldClassification(
    category: ServerDataCategory.sharedContent,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'blob_refs.id_key': ServerFieldClassification(
    category: ServerDataCategory.accessControl,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'blob_refs.epoch': ServerFieldClassification(
    category: ServerDataCategory.protocol,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'blob_refs.hash': ServerFieldClassification(
    category: ServerDataCategory.protocol,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'blob_refs.size': ServerFieldClassification(
    category: ServerDataCategory.metadata,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.authenticatedResponse,
  ),
  'blob_refs.uploaded_at': ServerFieldClassification(
    category: ServerDataCategory.metadata,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
  ),
  'config.pepper': ServerFieldClassification(
    category: ServerDataCategory.accessControl,
    subject: ServerDataSubject.sharedCollection,
    egress: ServerDataEgress.serverInternal,
    note: 'Deployment secret; it is required at startup and never persisted.',
  ),
};

const List<String> serverSqliteFields = [
  'stores.id_key',
  'stores.epoch',
  'stores.created_at',
  'stores.last_seen',
  'stores.bytes_used',
  'manifests.id_key',
  'manifests.epoch',
  'manifests.device_id',
  'manifests.etag',
  'manifests.written_at',
  'manifests.body',
  'blob_refs.id_key',
  'blob_refs.epoch',
  'blob_refs.hash',
  'blob_refs.size',
  'blob_refs.uploaded_at',
];

const List<String> serverConfigurationFields = ['config.pepper'];
