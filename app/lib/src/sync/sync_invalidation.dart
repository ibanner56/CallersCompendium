import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart';

/// Invalidates live queries on the database connection that owns the UI.
///
/// The sync worker writes through a separate Drift connection, so its SQLite
/// updates do not reach the main connection's stream query manager. The table
/// groups mirror the repository writers used by [CompendiumSyncStorage].
void markSyncAppliedTablesUpdated(
  CompendiumDatabase database,
  Set<SyncRecordKind> kinds,
) {
  final tables = <TableInfo<Table, Object?>>{};
  for (final kind in kinds) {
    switch (kind) {
      case SyncRecordKind.dance:
        tables.addAll({
          database.dances,
          database.danceAuthors,
          database.danceFigures,
          database.customFieldValues,
          database.danceTags,
          database.danceLinks,
          database.danceSources,
          database.provenance,
        });
      case SyncRecordKind.program:
        tables.addAll({
          database.programs,
          database.programSlots,
          database.programProvenance,
        });
      // Applying one of these kinds can also rewrite the rows that reference
      // it: natural-key reconciliation migrates an identity through
      // `_rewriteLocalReferences`, which rewrites the join rows and bumps the
      // citing dance's `updated_at` for I1. Naming only the kind's own table
      // left a screen whose stream reads `dances` (or the join) showing
      // pre-rewrite data until an unrelated write happened to invalidate it.
      case SyncRecordKind.choreographer:
        tables.addAll({
          database.choreographers,
          database.danceAuthors,
          database.dances,
        });
      case SyncRecordKind.tag:
        tables.addAll({database.tags, database.danceTags, database.dances});
      case SyncRecordKind.publishedSource:
        tables.addAll({
          database.publishedSources,
          database.danceSources,
          database.dances,
        });
      case SyncRecordKind.customFieldDef:
        tables.addAll({
          database.customFieldDefs,
          database.customFieldValues,
          database.dances,
        });
      case SyncRecordKind.difficultyLevel:
        tables.addAll({database.difficultyLevels, database.dances});
      case SyncRecordKind.venue:
        tables.addAll({
          database.venues,
          database.venueProvenance,
          database.programs,
        });
      case SyncRecordKind.setting:
        tables.add(database.settings);
    }
  }
  if (tables.isNotEmpty) database.markTablesUpdated(tables);
}
