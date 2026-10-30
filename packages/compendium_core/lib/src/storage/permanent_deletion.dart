/// "Permanently delete" in Recently deleted, for dances and programs (LIFE-2).
///
/// A trashed record no device has published is erased outright, as it always
/// was. A **published** one cannot be: Device Sync forfeits the right to erase
/// a record once it has named it in a manifest (`sync-spec.md` §3.1), because a
/// peer may hold it live and the next pass would download it back. Before
/// LIFE-2 such a record stayed in Recently deleted, whole, for ever, while the
/// snackbar said it was gone.
///
/// It is now **blanked**: every name, text field and association is removed,
/// and only the deletion record remains — kind, id, timestamps, a placeholder
/// title and the empty values of every other field, a few hundred bytes. The
/// maintainer chose this on 2026-10-29 (LIFE-2 option (a); round 2, `R2-life2-retire` (a): hide it and
/// blank its content, with no retirement of the deletion record).
///
/// The retention purge does the same to a published record whose time in the
/// trash has run out (`DanceRepository.purgeDeleted`), but leaves its existence
/// stamp alone, because expiry is not a new deletion; a tie between tombstones
/// takes the mark in the merge. Neither it nor the startup sweep rewrites the
/// records citing a
/// dance; a cited dance keeps its title until nothing cites it
/// (`DanceRepository.removePermanentlyDeleted` says why).
///
/// ## How a permanently deleted tombstone is recognised
///
/// Its `deleted_at` is [permanentlyDeletedAt], the unix epoch. That is the
/// value the "Permanently delete" action has always backdated `deleted_at` to,
/// so builds that predate blanking left the same mark on the records they could
/// not erase, and [isPermanentlyDeleted] finds those too. `deleted_at` travels
/// on the sync envelope and in backups, so the mark also hides the record on
/// every peer and after a restore — which a device-local flag could not.
///
/// The blanked body carries a fresh `updated_at`, so it wins last-writer-wins
/// among the tombstone copies peers hold (`sync-spec.md` §6.4: content is
/// decided by the greatest `updatedAt` among the copies that agree with the
/// winning state) and replaces their copies of the content too.
library;

/// The `deleted_at` of a tombstone the user permanently deleted.
final DateTime permanentlyDeletedAt = DateTime.utc(1970);

/// Whether [deletedAt] marks a permanently deleted tombstone, which Recently
/// deleted does not show.
bool isPermanentlyDeleted(DateTime? deletedAt) =>
    deletedAt != null && deletedAt.isAtSameMomentAs(permanentlyDeletedAt);

/// The title a blanked dance or program keeps. Both models require a non-empty
/// title, and the record is never shown, so it names nothing.
const String blankedRecordTitle = '—';

/// What "Permanently delete" did to one record.
enum PermanentDeletion {
  /// The record was erased: no device had published it.
  erased,

  /// The record was blanked and hidden; its deletion record remains so other
  /// devices delete it too.
  blanked,

  /// Nothing: the record was missing, or not in Recently deleted.
  none,
}
