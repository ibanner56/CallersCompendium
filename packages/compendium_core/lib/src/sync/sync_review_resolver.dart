import 'sync_review.dart';
import 'sync_storage.dart';

/// Coordinates the persisted queue with the production sync storage adapter.
///
/// The resolver is intentionally small: [CompendiumSyncStorage] owns the
/// transaction-bound writes, while this type supplies the app-facing list and
/// decision API.
final class SyncReviewQueueResolver {
  const SyncReviewQueueResolver(this.storage);

  final CompendiumSyncStorage storage;

  Future<List<SyncReviewQueueItem>> list() async {
    final rows = await storage.repositories.syncLocal.listReviewQueue();
    return [for (final row in rows) SyncReviewQueueItem.fromRow(row)];
  }

  Future<void> resolve({
    required SyncReviewQueueItem item,
    required SyncReviewAction action,
    String? newNaturalKey,
  }) => storage.resolveReviewQueue(
    expectedRow: item.row,
    action: action,
    newNaturalKey: newNaturalKey,
  );
}
