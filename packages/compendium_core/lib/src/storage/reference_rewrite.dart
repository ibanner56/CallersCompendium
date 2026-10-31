import 'package:drift/drift.dart';

import '../sync/sync_record_kind.dart';
import 'database.dart';
import 'existence.dart';

/// Moves every local reference to [losingId] onto [survivingId], for two
/// records of [kind] that have become one, and returns the ids of the dances
/// whose references changed.
///
/// Two callers share it, so that they cannot drift apart: sync's collision
/// reconciliation (sync-spec §6.6, "The remap"), and a user's merge of two
/// tags, authors or sources (`docs/design/tags-and-people.md`). Moved here
/// from `CompendiumSyncStorage` unchanged.
///
/// Join rows are re-pointed, live and tombstoned dances alike. Where a dance
/// already cites the survivor, the loser's row is dropped, not merged: an
/// author's position and a citation's page and number are the survivor's.
/// Every affected dance — and, for a dance merge, every program whose slots
/// moved — has its `updated_at` bumped with [nextExistenceStamp], because its
/// serialised content changed without its row being written (§6.5 I1).
///
/// It does not refresh the search index; a caller that needs the affected
/// dances' index rows current rebuilds them from the returned ids.
Future<Set<String>> rewriteLocalReferences(
  CompendiumDatabase db,
  SyncRecordKind kind,
  String losingId,
  String survivingId,
) async {
  if (losingId == survivingId) return const {};
  final affectedDances = <String>{};
  switch (kind) {
    case SyncRecordKind.choreographer:
      final rows = await (db.select(
        db.danceAuthors,
      )..where((row) => row.choreographerId.equals(losingId))).get();
      affectedDances.addAll(rows.map((row) => row.danceId));
      for (final row in rows) {
        final existing =
            await (db.select(db.danceAuthors)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.choreographerId.equals(survivingId),
                ))
                .getSingleOrNull();
        if (existing != null) {
          await (db.delete(db.danceAuthors)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.choreographerId.equals(losingId),
              ))
              .go();
        } else {
          await (db.update(db.danceAuthors)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.choreographerId.equals(losingId),
              ))
              .write(
                DanceAuthorsCompanion(choreographerId: Value(survivingId)),
              );
        }
      }
    case SyncRecordKind.tag:
      final rows = await (db.select(
        db.danceTags,
      )..where((row) => row.tagId.equals(losingId))).get();
      affectedDances.addAll(rows.map((row) => row.danceId));
      for (final row in rows) {
        final existing =
            await (db.select(db.danceTags)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.tagId.equals(survivingId),
                ))
                .getSingleOrNull();
        if (existing != null) {
          await (db.delete(db.danceTags)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.tagId.equals(losingId),
              ))
              .go();
        } else {
          await (db.update(db.danceTags)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.tagId.equals(losingId),
              ))
              .write(DanceTagsCompanion(tagId: Value(survivingId)));
        }
      }
    case SyncRecordKind.publishedSource:
      final rows = await (db.select(
        db.danceSources,
      )..where((row) => row.sourceId.equals(losingId))).get();
      affectedDances.addAll(rows.map((row) => row.danceId));
      for (final row in rows) {
        final existing =
            await (db.select(db.danceSources)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.sourceId.equals(survivingId),
                ))
                .getSingleOrNull();
        if (existing != null) {
          await (db.delete(db.danceSources)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.sourceId.equals(losingId),
              ))
              .go();
        } else {
          await (db.update(db.danceSources)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.sourceId.equals(losingId),
              ))
              .write(DanceSourcesCompanion(sourceId: Value(survivingId)));
        }
      }
    case SyncRecordKind.customFieldDef:
      final rows = await (db.select(
        db.customFieldValues,
      )..where((row) => row.fieldId.equals(losingId))).get();
      affectedDances.addAll(rows.map((row) => row.danceId));
      for (final row in rows) {
        final existing =
            await (db.select(db.customFieldValues)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.fieldId.equals(survivingId),
                ))
                .getSingleOrNull();
        if (existing != null) {
          await (db.delete(db.customFieldValues)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.fieldId.equals(losingId),
              ))
              .go();
        } else {
          await (db.update(db.customFieldValues)..where(
                (table) =>
                    table.danceId.equals(row.danceId) &
                    table.fieldId.equals(losingId),
              ))
              .write(CustomFieldValuesCompanion(fieldId: Value(survivingId)));
        }
      }
    case SyncRecordKind.difficultyLevel:
      final rows = await (db.select(
        db.dances,
      )..where((row) => row.levelId.equals(losingId))).get();
      affectedDances.addAll(rows.map((row) => row.id));
      for (final row in rows) {
        await (db.update(
          db.dances,
        )..where((table) => table.id.equals(row.id))).write(
          DancesCompanion(
            levelId: Value(survivingId),
            updatedAt: Value(row.updatedAt),
          ),
        );
      }
    case SyncRecordKind.dance:
      final slotRows = await (db.select(
        db.programSlots,
      )..where((row) => row.danceId.equals(losingId))).get();
      final affectedPrograms = slotRows.map((row) => row.programId).toSet();
      await (db.update(db.programSlots)
            ..where((row) => row.danceId.equals(losingId)))
          .write(ProgramSlotsCompanion(danceId: Value(survivingId)));

      final linkOwners = await (db.select(
        db.danceLinks,
      )..where((row) => row.targetDanceId.equals(losingId))).get();
      final linkOwnerIds = linkOwners
          .map((row) => row.danceId)
          .where((id) => id != losingId)
          .toSet();
      await (db.update(db.danceLinks)
            ..where((row) => row.targetDanceId.equals(losingId)))
          .write(DanceLinksCompanion(targetDanceId: Value(survivingId)));

      final now = DateTime.now().toUtc();
      for (final programId in affectedPrograms) {
        final row = await (db.select(
          db.programs,
        )..where((table) => table.id.equals(programId))).getSingleOrNull();
        if (row == null) continue;
        await (db.update(
          db.programs,
        )..where((table) => table.id.equals(programId))).write(
          ProgramsCompanion(
            updatedAt: Value(
              nextExistenceStamp(now: now, current: row.updatedAt),
            ),
          ),
        );
      }
      affectedDances.addAll(linkOwnerIds);
    case SyncRecordKind.program:
    case SyncRecordKind.venue:
    case SyncRecordKind.setting:
    case SyncRecordKind.glossaryEntry:
    case SyncRecordKind.figureNote:
      return const {};
  }
  if (affectedDances.isEmpty) return affectedDances;
  final now = DateTime.now().toUtc();
  for (final danceId in affectedDances) {
    final row = await (db.select(
      db.dances,
    )..where((table) => table.id.equals(danceId))).getSingleOrNull();
    if (row == null) continue;
    await (db.update(
      db.dances,
    )..where((table) => table.id.equals(danceId))).write(
      DancesCompanion(
        updatedAt: Value(nextExistenceStamp(now: now, current: row.updatedAt)),
      ),
    );
  }
  return affectedDances;
}
