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
      case SyncRecordKind.choreographer:
        tables.add(database.choreographers);
      case SyncRecordKind.tag:
        tables.add(database.tags);
      case SyncRecordKind.publishedSource:
        tables.add(database.publishedSources);
      case SyncRecordKind.customFieldDef:
        tables.add(database.customFieldDefs);
      case SyncRecordKind.difficultyLevel:
        tables.add(database.difficultyLevels);
      case SyncRecordKind.venue:
        tables.addAll({database.venues, database.venueProvenance});
      case SyncRecordKind.setting:
        tables.add(database.settings);
    }
  }
  if (tables.isNotEmpty) database.markTablesUpdated(tables);
}
