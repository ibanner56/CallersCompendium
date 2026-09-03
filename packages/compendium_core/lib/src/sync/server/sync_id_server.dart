import '../sync_id.dart' show deriveSyncIdKey, normalizeSyncId;

/// Server-side adapter for the shared credential definition.
///
/// Athenaeum decodes the wire token first, then passes the result through the
/// same normalizer before deriving its storage key.
String normalizeIncomingSyncId(String decodedSyncId) =>
    normalizeSyncId(decodedSyncId);

/// Resolves an incoming credential to the shared server storage-key function.
String deriveIncomingSyncIdKey(String decodedSyncId, List<int> pepper) =>
    deriveSyncIdKey(normalizeIncomingSyncId(decodedSyncId), pepper);
