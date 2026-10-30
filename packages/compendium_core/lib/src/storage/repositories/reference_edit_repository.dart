import 'package:drift/drift.dart';

import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../existence.dart';
import '../reference_rewrite.dart';
import '../shareable_text.dart';
import '../../model/stored_timestamp.dart';
import 'dance_repository.dart';
import 'sync_local_repository.dart';

/// The three kinds a user can rename, merge and delete from a manager
/// (`docs/design/tags-and-people.md`).
enum ReferenceKind {
  tag(SyncRecordKind.tag),

  /// Stored as `choreographers`; user-facing text says "author" (D-3).
  author(SyncRecordKind.choreographer),
  source(SyncRecordKind.publishedSource);

  const ReferenceKind(this.syncKind);

  final SyncRecordKind syncKind;

  /// Tags and authors have a `UNIQUE` name; a source's title is not unique.
  bool get hasNaturalKey => this != ReferenceKind.source;
}

/// A rename found a **live** entry already holding the name, as the app
/// matches names ([naturalKeyMatchKey]). Nothing was written.
///
/// The caller offers a merge: [ReferenceEditRepository.merge] with the
/// renamed entry and every one of [liveIds] (there can be more than one,
/// because the `UNIQUE` index compares bytes and the app folds case).
class ReferenceNameTakenException implements Exception {
  const ReferenceNameTakenException(this.kind, this.name, this.liveIds);

  final ReferenceKind kind;
  final String name;

  /// The live entries holding [name], in ascending id order.
  final List<String> liveIds;

  @override
  String toString() =>
      'ReferenceNameTakenException: ${kind.name} "$name" is held by '
      '${liveIds.join(', ')}';
}

/// An Undo found a **live** entry outside the edit holding a name it would
/// give back: created, or brought by a sync pass, since the edit. Nothing was
/// written; the edit stands.
class ReferenceUndoConflictException implements Exception {
  const ReferenceUndoConflictException(this.kind, this.name, this.holderId);

  final ReferenceKind kind;
  final String name;
  final String holderId;

  @override
  String toString() =>
      'ReferenceUndoConflictException: ${kind.name} "$name" is now held by '
      '$holderId';
}

/// What one rename, merge or delete changed, kept in memory for its Undo.
///
/// Opaque to callers: pass it back to [ReferenceEditRepository.undo]. It lives
/// as long as the snackbar that offers Undo (D-N2-5); nothing is persisted.
final class ReferenceEditUndo {
  ReferenceEditUndo._(this.kind, this.liveDanceCount, this._state);

  final ReferenceKind kind;

  /// Live dances the operation changed: for a tag delete, the dances it was
  /// taken off ("Deleted 'Bouncey' from 12 dances"). Dances in Recently
  /// deleted lose it too but are not counted (trash-policy (b)).
  final int liveDanceCount;

  final _UndoState _state;
}

/// The before-image [ReferenceEditRepository.undo] restores.
final class _UndoState {
  _UndoState({
    required this.rowsBefore,
    required this.touchedIds,
    this.revive = const {},
    this.joinsBefore = const [],
    this.survivorDancesBefore = const {},
    this.survivorId,
    this.aliasesBefore = const [],
    this.aliasesAfter = const [],
    this.retainedBefore = const [],
    this.pendingBefore = const [],
  });

  /// Each entry's row before the edit, to write back (survivor, losers, or
  /// the renamed or deleted entry).
  final Map<String, Object> rowsBefore;

  /// Every entry id involved, for finding the dances to bump and reindex.
  final Set<String> touchedIds;

  /// Entries the edit tombstoned, revived by Undo.
  final Set<String> revive;

  /// The join rows that named a loser or a deleted tag.
  final List<Object> joinsBefore;

  /// For a merge: the dances that already cited the survivor, whose loser
  /// join was dropped rather than moved.
  final Set<String> survivorDancesBefore;
  final String? survivorId;
  final List<IdAliasRow> aliasesBefore;
  final List<IdAliasRow> aliasesAfter;
  final List<RetainedSyncFieldsRow> retainedBefore;
  final List<PendingDeletionRow> pendingBefore;
}

/// Rename, merge and delete for tags, authors and sources, with Undo
/// (`docs/design/tags-and-people.md`, branch T1).
///
/// One class for the three kinds, not three copies in their repositories:
/// the steps are the same, and copies would drift. Every operation runs in one
/// transaction, so a caller can wrap it with its own writes (the app rewrites
/// `default_import_tag_names` in the same `repos.transaction`).
///
/// Sync: a merge adds no record kind and no key. Its peers learn of it from
/// ordinary records — the survivor's edit, the loser's tombstone under the
/// loser's own name freed with a suffix, and the bumped dances — and the alias
/// it records files a peer's later citations of the loser under the survivor
/// (sync-spec §6.6, "The remap", amended 2026-10-30).
class ReferenceEditRepository {
  ReferenceEditRepository(this._db, this._dances, this._syncLocal);

  final CompendiumDatabase _db;
  final DanceRepository _dances;
  final SyncLocalRepository _syncLocal;

  /// Every entry of [kind], live or tombstoned, whose name the app treats as
  /// [name] ([naturalKeyMatchKey]), other than [excludeId], in ascending id
  /// order. Empty for sources, which have no natural key.
  ///
  /// `TagRepository.idByName` returns one id with live rows first, which
  /// hides a tombstone holding the exact bytes and a live case-variant whose
  /// id sorts later; a rename has to see them all.
  Future<List<({String id, String name, bool deleted})>> nameMatches(
    ReferenceKind kind,
    String name, {
    String? excludeId,
  }) async {
    if (!kind.hasNaturalKey) return const [];
    final wanted = naturalKeyMatchKey(name);
    final rows = switch (kind) {
      ReferenceKind.tag => [
        for (final row in await _db.select(_db.tags).get())
          (id: row.id, name: row.name, deleted: row.deletedAt != null),
      ],
      ReferenceKind.author => [
        for (final row in await _db.select(_db.choreographers).get())
          (id: row.id, name: row.name, deleted: row.deletedAt != null),
      ],
      ReferenceKind.source =>
        const <({String id, String name, bool deleted})>[],
    };
    return [
      for (final row in rows)
        if (row.id != excludeId && naturalKeyMatchKey(row.name) == wanted) row,
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// How many live dances cite [id]. Dances in Recently deleted do not count:
  /// they never protect an entry (trash-policy (b)).
  Future<int> liveDanceCount(ReferenceKind kind, String id) {
    final (join, key, dance) = _joinColumns(kind);
    return liveDanceCitationCount(
      _db,
      joinTable: join,
      keyColumn: key,
      danceIdColumn: dance,
      id: id,
    );
  }

  /// Renames the live entry [id] to [name].
  ///
  /// Throws [ReferenceNameTakenException], writing nothing, when a live entry
  /// already holds the name; the caller offers [merge]. A case-only rename is
  /// a plain rename only when no other entry matches.
  ///
  /// A **tombstone** holding the name is freed first, with the name-only write
  /// [merge] uses for a loser, so it is neither refused nor revived: renaming
  /// it through `upsert` would bring it back to life. Every tombstone the
  /// lookup finds is freed, whichever bytes it holds.
  ///
  /// A source has no natural key, so its rename never collides. Its rename
  /// refreshes the search index's `sources` text, as an author's rename
  /// refreshes `authors`.
  ///
  /// Undo writes the old name back. A tombstone the rename freed keeps its
  /// suffixed name: it is out of sight either way, and putting the name back
  /// could take it from the entry Undo restores.
  Future<ReferenceEditUndo> rename(
    ReferenceKind kind,
    String id,
    String name, {
    DateTime? at,
  }) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final before = await _readRow(kind, id);
      if (before == null || _deletedAt(before) != null) {
        throw StateError('cannot rename ${kind.name} "$id": not live');
      }
      final matches = await nameMatches(kind, name, excludeId: id);
      final live = [
        for (final match in matches)
          if (!match.deleted) match.id,
      ];
      if (live.isNotEmpty) {
        throw ReferenceNameTakenException(kind, name, live);
      }
      for (final match in matches) {
        await _freeName(kind, match.id, now: now);
      }
      await _writeFields(
        kind,
        _withName(kind, before, normalizeShareableText(name)),
        now: now,
      );
      final dances = await _citingDances(kind, {id});
      await _reindex(kind, dances);
      return ReferenceEditUndo._(
        kind,
        0,
        _UndoState(rowsBefore: {id: before}, touchedIds: {id}),
      );
    });
  }

  /// Merges [otherIds] into [intoId]: one entry is left, citing every dance
  /// any of them cited.
  ///
  /// [intoId] is the entry the user merged *into*: the result holds its
  /// fields, under [name] when given (a rename that collided) or its own name
  /// otherwise. Empty fields take the others' values, in ascending id order;
  /// a tag's colour, an author's website, notes, email and location, and a
  /// source's author, year, URL and notes. An author is deceased if any of
  /// them is (D-N2-2 (b)). Notes are never concatenated.
  ///
  /// The **id** that survives is the smallest of all of them, whichever entry
  /// the user chose (sync-spec §6.6: every "which record survives" decision
  /// uses the smaller UUID, or opposite merges on two devices never converge).
  /// So the result is written under that id, and every other id is a loser,
  /// [intoId] included when it is not the smallest.
  ///
  /// In one transaction, for each loser in ascending id order:
  ///
  /// 1. its name is freed with a suffix by a name-only write
  ///    (`<name>_<first 8 hex digits of its id>`, or all 32 if that is
  ///    taken), which leaves `deleted_at` and `existence_at` alone and
  ///    cancels no pending deletion;
  /// 2. its join rows move to the survivor, live and trashed dances alike,
  ///    and a dance citing both keeps the survivor's
  ///    ([rewriteLocalReferences]), which bumps every affected dance;
  /// 3. it is tombstoned, not erased: the tombstone is how peers learn of the
  ///    merge;
  /// 4. `loser → survivor` is recorded through
  ///    [SyncLocalRepository.remapIdentity], which also collapses alias
  ///    chains, moves retained sync fields and unions publication markers.
  ///
  /// Then the survivor's fields are written, a tombstone holding [name] is
  /// freed as [rename] frees it, and the affected dances' search rows are
  /// rebuilt.
  Future<ReferenceEditUndo> merge(
    ReferenceKind kind, {
    required String intoId,
    required Iterable<String> otherIds,
    String? name,
    DateTime? at,
  }) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final all = {intoId, ...otherIds};
      if (all.length < 2) {
        throw ArgumentError.value(otherIds, 'otherIds', 'nothing to merge');
      }
      final rowsBefore = <String, Object>{};
      for (final id in all) {
        final row = await _readRow(kind, id);
        if (row == null || _deletedAt(row) != null) {
          throw StateError('cannot merge ${kind.name} "$id": not live');
        }
        rowsBefore[id] = row;
      }
      final ordered = all.toList()..sort();
      final survivorId = ordered.first;
      final losers = ordered.skip(1).toList();
      final chosen = rowsBefore[intoId]!;
      final targetName = name == null
          ? _name(kind, chosen)
          : normalizeShareableText(name);
      final merged = _withName(
        kind,
        _fillBlanks(kind, rowsBefore[survivorId]!, chosen, [
          for (final id in ordered)
            if (id != intoId) rowsBefore[id]!,
        ]),
        targetName,
      );

      // A live entry outside the merge holding the name — created, or brought
      // by a sync pass, since the rename that offered this merge — would be
      // left beside the result as a duplicate, or break the UNIQUE index.
      final outside = [
        for (final match in await nameMatches(kind, targetName))
          if (!match.deleted && !all.contains(match.id)) match.id,
      ];
      if (outside.isNotEmpty) {
        throw ReferenceNameTakenException(kind, targetName, outside);
      }

      final joinsBefore = await _readJoins(kind, losers.toSet());
      final survivorDancesBefore = await _citingDances(kind, {survivorId});
      final aliasesBefore = await _aliases(kind);
      final retainedBefore = await _retained(kind, all);
      final pendingBefore = await _pending(kind, all);

      for (final loser in losers) {
        if (kind.hasNaturalKey) await _freeName(kind, loser, now: now);
      }
      if (kind.hasNaturalKey) {
        for (final match in await nameMatches(kind, targetName)) {
          if (match.deleted && !all.contains(match.id)) {
            await _freeName(kind, match.id, now: now);
          }
        }
      }
      for (final loser in losers) {
        await rewriteLocalReferences(_db, kind.syncKind, loser, survivorId);
        await _syncLocal.deletePendingDeletion(
          kind: kind.syncKind,
          recordId: loser,
        );
        await _stampExistence(kind, loser, now: now, deleted: true);
        await _syncLocal.remapIdentity(
          kind: kind.syncKind,
          losingId: loser,
          survivingId: survivorId,
        );
      }
      await _writeFields(kind, merged, now: now);
      // Merging into an entry is a deliberate edit of it, so it cancels a
      // peer's deletion this device holds for it (§6.8).
      await cancelPendingSyncDeletionForLocalEdit(
        _db,
        kind: kind.syncKind,
        recordId: survivorId,
        table: _table(kind),
        keyColumn: 'id',
        at: now,
      );
      final dances = await _citingDances(kind, {survivorId});
      await _reindex(kind, dances);
      return ReferenceEditUndo._(
        kind,
        await _liveDances(dances),
        _UndoState(
          rowsBefore: rowsBefore,
          revive: losers.toSet(),
          joinsBefore: joinsBefore,
          survivorDancesBefore: survivorDancesBefore,
          survivorId: survivorId,
          aliasesBefore: aliasesBefore,
          aliasesAfter: await _aliases(kind),
          retainedBefore: retainedBefore,
          pendingBefore: pendingBefore,
          touchedIds: all,
        ),
      );
    });
  }

  /// Deletes the tag [id] from every dance that has it, then tombstones it
  /// (D-N2-7 = (a)).
  ///
  /// The `dance_tags` rows go from live dances and from dances in Recently
  /// deleted, and each of those dances is bumped: its serialised `tagIds`
  /// changed (§6.5 I1). Keeping the rows, as [TagRepository.delete] does,
  /// would leave this device holding joins its peers drop, so a revival here
  /// would re-tag old dances and not there. Re-creating the name later
  /// therefore does not re-tag them either.
  ///
  /// Authors and sources have no delete here: they keep their guarded
  /// repository deletes, offered only for an unused entry (D-N2-4).
  Future<ReferenceEditUndo> deleteTag(String id, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      const kind = ReferenceKind.tag;
      final before = await _readRow(kind, id);
      if (before == null || _deletedAt(before) != null) {
        throw StateError('cannot delete tag "$id": not live');
      }
      final joinsBefore = await _readJoins(kind, {id});
      final dances = {
        for (final join in joinsBefore) (join as DanceTagRow).danceId,
      };
      final liveCount = await liveDanceCount(kind, id);
      await (_db.delete(_db.danceTags)..where((t) => t.tagId.equals(id))).go();
      await _bumpDances(dances, now: now);
      await _stampExistence(kind, id, now: now, deleted: true);
      return ReferenceEditUndo._(
        kind,
        liveCount,
        _UndoState(
          rowsBefore: {id: before},
          touchedIds: {id},
          revive: {id},
          joinsBefore: joinsBefore,
        ),
      );
    });
  }

  /// Reverses [token]'s edit, as ordinary edits stamped now, so peers take
  /// the undone state whether or not a sync pass ran in between (§6.4: a
  /// revival stamps above the tombstone it revives).
  ///
  /// For a merge, in order: the survivor's fields come back first, freeing
  /// its old name for a loser; each loser is revived under its old name with
  /// its old fields; the join rows come back with their positions and
  /// citation page and number; the `id_aliases` rows the merge's
  /// [SyncLocalRepository.remapIdentity] added or rewrote are put back, and
  /// both ids' retained sync fields and held deletions restored. The
  /// survivor's publication marker stays: §6.6 never drops one, and a pass in
  /// between may have published the survivor in its own right. Every touched
  /// dance is bumped again.
  ///
  /// An alias row a sync pass has changed since is left as the pass left it.
  Future<void> undo(ReferenceEditUndo token, {DateTime? at}) {
    final now = resolveStamp(at);
    final kind = token.kind;
    final state = token._state;
    return _db.transaction(() async {
      final survivorId = state.survivorId;
      if (kind.hasNaturalKey) {
        // Undo gives each entry its old name back. A live entry outside the
        // edit holding one now refuses the Undo before anything is written; a
        // tombstone holding one gives it up, as a rename frees it.
        final freeing = <String>{};
        for (final row in state.rowsBefore.values) {
          final name = _name(kind, row);
          for (final match in await nameMatches(kind, name)) {
            if (state.touchedIds.contains(match.id)) continue;
            if (!match.deleted) {
              throw ReferenceUndoConflictException(kind, name, match.id);
            }
            freeing.add(match.id);
          }
        }
        for (final id in freeing) {
          await _freeName(kind, id, now: now);
        }
      }
      // Survivor (or the renamed or deleted entry) first, losers after, so a
      // name the survivor took is free again before a loser needs it back.
      final order = state.rowsBefore.keys.toList()
        ..sort((a, b) {
          if (a == survivorId) return -1;
          if (b == survivorId) return 1;
          return a.compareTo(b);
        });
      for (final id in order) {
        await _writeFields(kind, state.rowsBefore[id]!, now: now);
        if (state.revive.contains(id)) {
          await _stampExistence(kind, id, now: now, deleted: false);
        }
      }

      final dances = <String>{};
      for (final join in state.joinsBefore) {
        final danceId = _joinDanceId(join);
        dances.add(danceId);
        await _restoreJoin(
          join,
          movedTo:
              survivorId != null &&
                  !state.survivorDancesBefore.contains(danceId)
              ? survivorId
              : null,
        );
      }

      await _restoreAliases(kind, state.aliasesBefore, state.aliasesAfter);
      if (survivorId != null) {
        await _restoreRetained(kind, state, survivorId);
        // The losers' held deletions come back with them. The survivor's is
        // not put back: the merge cancelled it as a deliberate edit and raised
        // its existence stamp (§6.8), which an Undo does not lower again.
        for (final row in state.pendingBefore) {
          if (row.recordId == survivorId) continue;
          await _db
              .into(_db.pendingDeletions)
              .insert(row, mode: InsertMode.insertOrReplace);
        }
      }

      dances.addAll(await _citingDances(kind, state.touchedIds));
      await _bumpDances(dances, now: now);
      await _reindex(kind, dances);
    });
  }

  /// Puts back the retained sync fields the merge's `remapIdentity` moved:
  /// each loser's own, and nothing on the survivor unless it held its own
  /// before. A row a sync pass has written for the survivor since is left.
  Future<void> _restoreRetained(
    ReferenceKind kind,
    _UndoState state,
    String survivorId,
  ) async {
    final before = {for (final row in state.retainedBefore) row.recordId: row};
    for (final id in state.touchedIds) {
      if (id == survivorId) continue;
      await (_db.delete(_db.retainedSyncFields)..where(
            (t) => t.kind.equals(kind.syncKind.name) & t.recordId.equals(id),
          ))
          .go();
      final row = before[id];
      if (row != null) await _db.into(_db.retainedSyncFields).insert(row);
    }
    if (before.containsKey(survivorId)) return;
    final moved = {
      for (final row in state.retainedBefore) (row.payload, row.wholeRecord),
    };
    final current =
        await (_db.select(_db.retainedSyncFields)..where(
              (t) =>
                  t.kind.equals(kind.syncKind.name) &
                  t.recordId.equals(survivorId),
            ))
            .getSingleOrNull();
    if (current != null &&
        moved.contains((current.payload, current.wholeRecord))) {
      await (_db.delete(_db.retainedSyncFields)..where(
            (t) =>
                t.kind.equals(kind.syncKind.name) &
                t.recordId.equals(survivorId),
          ))
          .go();
    }
  }

  /// Stamps an existence transition of entry [id] past its own `updated_at`
  /// as well as its `existence_at`. [stampExistenceTransition] writes
  /// `updated_at = at`, which alone could repeat the stamp a name-only write
  /// just took, or fall below one from a clock that ran ahead, while the body
  /// changes (§6.5 I1).
  Future<void> _stampExistence(
    ReferenceKind kind,
    String id, {
    required DateTime now,
    required bool deleted,
  }) async {
    final row = await _readRow(kind, id);
    if (row == null) return;
    await stampExistenceTransition(
      _db,
      table: _table(kind),
      keyColumn: 'id',
      key: id,
      at: _stamp(now, _updatedAt(row)),
      deleted: deleted,
    );
  }

  static DateTime? _updatedAt(Object row) => switch (row) {
    TagRow() => row.updatedAt,
    ChoreographerRow() => row.updatedAt,
    PublishedSourceRow() => row.updatedAt,
    _ => throw ArgumentError.value(row, 'row'),
  };

  // ---------------------------------------------------------------------
  // Per-kind plumbing.

  TableInfo<Table, dynamic> _table(ReferenceKind kind) => switch (kind) {
    ReferenceKind.tag => _db.tags,
    ReferenceKind.author => _db.choreographers,
    ReferenceKind.source => _db.publishedSources,
  };

  (TableInfo<Table, dynamic>, GeneratedColumn<String>, GeneratedColumn<String>)
  _joinColumns(ReferenceKind kind) => switch (kind) {
    ReferenceKind.tag => (
      _db.danceTags,
      _db.danceTags.tagId,
      _db.danceTags.danceId,
    ),
    ReferenceKind.author => (
      _db.danceAuthors,
      _db.danceAuthors.choreographerId,
      _db.danceAuthors.danceId,
    ),
    ReferenceKind.source => (
      _db.danceSources,
      _db.danceSources.sourceId,
      _db.danceSources.danceId,
    ),
  };

  Future<Object?> _readRow(ReferenceKind kind, String id) => switch (kind) {
    ReferenceKind.tag => (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(id))).getSingleOrNull(),
    ReferenceKind.author => (_db.select(
      _db.choreographers,
    )..where((t) => t.id.equals(id))).getSingleOrNull(),
    ReferenceKind.source => (_db.select(
      _db.publishedSources,
    )..where((t) => t.id.equals(id))).getSingleOrNull(),
  };

  static DateTime? _deletedAt(Object row) => switch (row) {
    TagRow() => row.deletedAt,
    ChoreographerRow() => row.deletedAt,
    PublishedSourceRow() => row.deletedAt,
    _ => throw ArgumentError.value(row, 'row'),
  };

  static String _name(ReferenceKind kind, Object row) => switch (row) {
    TagRow() => row.name,
    ChoreographerRow() => row.name,
    PublishedSourceRow() => row.title,
    _ => throw ArgumentError.value(row, 'row'),
  };

  static Object _withName(ReferenceKind kind, Object row, String name) =>
      switch (row) {
        TagRow() => row.copyWith(name: name),
        ChoreographerRow() => row.copyWith(name: name),
        PublishedSourceRow() => row.copyWith(title: name),
        _ => throw ArgumentError.value(row, 'row'),
      };

  /// The survivor row ([survivor], for its id and existence columns) holding
  /// [chosen]'s fields, with each empty one taken from [others] in order.
  static Object _fillBlanks(
    ReferenceKind kind,
    Object survivor,
    Object chosen,
    List<Object> others,
  ) {
    T? first<T>(T? own, T? Function(Object row) read) {
      if (!_isBlank(own)) return own;
      for (final other in others) {
        final value = read(other);
        if (!_isBlank(value)) return value;
      }
      return own;
    }

    switch (chosen) {
      case TagRow():
        final s = survivor as TagRow;
        return s.copyWith(
          name: chosen.name,
          color: Value(first(chosen.color, (r) => (r as TagRow).color)),
        );
      case ChoreographerRow():
        final s = survivor as ChoreographerRow;
        return s.copyWith(
          name: chosen.name,
          website: Value(
            first(chosen.website, (r) => (r as ChoreographerRow).website),
          ),
          notes: Value(
            first(chosen.notes, (r) => (r as ChoreographerRow).notes),
          ),
          email: Value(
            first(chosen.email, (r) => (r as ChoreographerRow).email),
          ),
          location: Value(
            first(chosen.location, (r) => (r as ChoreographerRow).location),
          ),
          deceased:
              chosen.deceased ||
              others.any((r) => (r as ChoreographerRow).deceased),
        );
      case PublishedSourceRow():
        final s = survivor as PublishedSourceRow;
        return s.copyWith(
          title: chosen.title,
          author: Value(
            first(chosen.author, (r) => (r as PublishedSourceRow).author),
          ),
          year: Value(
            first(chosen.year, (r) => (r as PublishedSourceRow).year),
          ),
          url: Value(first(chosen.url, (r) => (r as PublishedSourceRow).url)),
          notes: Value(
            first(chosen.notes, (r) => (r as PublishedSourceRow).notes),
          ),
        );
      default:
        throw ArgumentError.value(chosen, 'chosen');
    }
  }

  static bool _isBlank(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);

  /// Writes [row]'s content columns, bumping `updated_at` past its current
  /// value. `deleted_at` and `existence_at` are left as they stand: existence
  /// transitions are [stampExistenceTransition]'s, and this never revives.
  Future<void> _writeFields(
    ReferenceKind kind,
    Object row, {
    required DateTime now,
  }) async {
    switch (row) {
      case TagRow():
        final current = await _readRow(kind, row.id) as TagRow?;
        await (_db.update(_db.tags)..where((t) => t.id.equals(row.id))).write(
          TagsCompanion(
            name: Value(row.name),
            color: Value(row.color),
            updatedAt: Value(_stamp(now, current?.updatedAt)),
          ),
        );
      case ChoreographerRow():
        final current = await _readRow(kind, row.id) as ChoreographerRow?;
        await (_db.update(
          _db.choreographers,
        )..where((t) => t.id.equals(row.id))).write(
          ChoreographersCompanion(
            name: Value(row.name),
            website: Value(row.website),
            notes: Value(row.notes),
            email: Value(row.email),
            location: Value(row.location),
            deceased: Value(row.deceased),
            updatedAt: Value(_stamp(now, current?.updatedAt)),
          ),
        );
      case PublishedSourceRow():
        final current = await _readRow(kind, row.id) as PublishedSourceRow?;
        await (_db.update(
          _db.publishedSources,
        )..where((t) => t.id.equals(row.id))).write(
          PublishedSourcesCompanion(
            title: Value(row.title),
            author: Value(row.author),
            year: Value(row.year),
            url: Value(row.url),
            notes: Value(row.notes),
            updatedAt: Value(_stamp(now, current?.updatedAt)),
          ),
        );
      default:
        throw ArgumentError.value(row, 'row');
    }
  }

  static DateTime _stamp(DateTime now, DateTime? current) =>
      nextExistenceStamp(now: now, current: current);

  /// Frees the name entry [id] holds: `<name>_<8 hex>` from its id, or all 32
  /// hex digits if that is taken too, as §6.6's custom-field rule derives a
  /// key. Only this device derives it, so it need not converge the way that
  /// rule must; it borrows the shape. A name-only write: see [_writeFields].
  Future<void> _freeName(
    ReferenceKind kind,
    String id, {
    required DateTime now,
  }) async {
    final row = await _readRow(kind, id);
    if (row == null) return;
    final hex = id.replaceAll('-', '').toLowerCase();
    final base = _name(kind, row);
    for (final suffix in {hex.length > 8 ? hex.substring(0, 8) : hex, hex}) {
      final freed = '${base}_$suffix';
      if ((await nameMatches(kind, freed, excludeId: id)).isEmpty) {
        await _writeFields(kind, _withName(kind, row, freed), now: now);
        return;
      }
    }
    throw StateError('cannot free the name of ${kind.name} "$id"');
  }

  Future<List<Object>> _readJoins(ReferenceKind kind, Set<String> ids) async =>
      switch (kind) {
        ReferenceKind.tag => await (_db.select(
          _db.danceTags,
        )..where((t) => t.tagId.isIn(ids))).get(),
        ReferenceKind.author => await (_db.select(
          _db.danceAuthors,
        )..where((t) => t.choreographerId.isIn(ids))).get(),
        ReferenceKind.source => await (_db.select(
          _db.danceSources,
        )..where((t) => t.sourceId.isIn(ids))).get(),
      };

  static String _joinDanceId(Object join) => switch (join) {
    DanceTagRow() => join.danceId,
    DanceAuthorRow() => join.danceId,
    DanceSourceRow() => join.danceId,
    _ => throw ArgumentError.value(join, 'join'),
  };

  /// Puts [join], a loser's join row, back. Where the merge moved it to the
  /// survivor ([movedTo]) and that row is still there, it is moved back in
  /// place, so an author or citation keeps a position an edit since gave it.
  /// Otherwise it is inserted at its old position, or after the last one if
  /// an edit since took that position: never dropped.
  Future<void> _restoreJoin(Object join, {required String? movedTo}) async {
    switch (join) {
      case DanceTagRow():
        if (movedTo != null) {
          await (_db.delete(_db.danceTags)..where(
                (t) => t.danceId.equals(join.danceId) & t.tagId.equals(movedTo),
              ))
              .go();
        }
        await _db
            .into(_db.danceTags)
            .insert(join, mode: InsertMode.insertOrIgnore);
      case DanceAuthorRow():
        final moved = movedTo == null
            ? 0
            : await (_db.update(_db.danceAuthors)..where(
                    (t) =>
                        t.danceId.equals(join.danceId) &
                        t.choreographerId.equals(movedTo),
                  ))
                  .write(
                    DanceAuthorsCompanion(
                      choreographerId: Value(join.choreographerId),
                    ),
                  );
        if (moved > 0) return;
        final rows = await (_db.select(
          _db.danceAuthors,
        )..where((t) => t.danceId.equals(join.danceId))).get();
        if (rows.any((r) => r.choreographerId == join.choreographerId)) return;
        await _db
            .into(_db.danceAuthors)
            .insert(
              rows.any((r) => r.position == join.position)
                  ? join.copyWith(
                      position: _nextPosition(rows.map((r) => r.position)),
                    )
                  : join,
            );
      case DanceSourceRow():
        final moved = movedTo == null
            ? 0
            : await (_db.update(_db.danceSources)..where(
                    (t) =>
                        t.danceId.equals(join.danceId) &
                        t.sourceId.equals(movedTo),
                  ))
                  .write(
                    DanceSourcesCompanion(
                      sourceId: Value(join.sourceId),
                      page: Value(join.page),
                      number: Value(join.number),
                    ),
                  );
        if (moved > 0) return;
        final rows = await (_db.select(
          _db.danceSources,
        )..where((t) => t.danceId.equals(join.danceId))).get();
        if (rows.any((r) => r.sourceId == join.sourceId)) return;
        await _db
            .into(_db.danceSources)
            .insert(
              rows.any((r) => r.position == join.position)
                  ? join.copyWith(
                      position: _nextPosition(rows.map((r) => r.position)),
                    )
                  : join,
            );
      default:
        throw ArgumentError.value(join, 'join');
    }
  }

  static int _nextPosition(Iterable<int> positions) =>
      positions.fold(-1, (a, b) => a > b ? a : b) + 1;

  Future<Set<String>> _citingDances(
    ReferenceKind kind,
    Set<String> ids,
  ) async => {
    for (final join in await _readJoins(kind, ids)) _joinDanceId(join),
  };

  Future<int> _liveDances(Set<String> danceIds) async {
    if (danceIds.isEmpty) return 0;
    final rows = await (_db.select(
      _db.dances,
    )..where((t) => t.id.isIn(danceIds) & t.deletedAt.isNull())).get();
    return rows.length;
  }

  /// Bumps each dance's `updated_at`: its serialised references changed
  /// without its row being written (§6.5 I1).
  Future<void> _bumpDances(
    Set<String> danceIds, {
    required DateTime now,
  }) async {
    final at = unixSeconds(now);
    for (final id in danceIds) {
      // normalization-structure-exempt: writes `updated_at` only, no
      // shareable text.
      await _db.customUpdate(
        // sync-invariant-exclusion: join-hydrated-body the dance's tag, author or source rows changed.
        'UPDATE ${_db.dances.actualTableName} '
        'SET updated_at = MAX(updated_at + 1, ?) WHERE id = ?',
        variables: [Variable<int>(at), Variable<String>(id)],
        updates: {_db.dances},
        updateKind: UpdateKind.update,
      );
    }
  }

  /// Rebuilds the search rows of [danceIds]: an author's name and a source's
  /// title and author are indexed text. Tags are not, so a tag edit needs none.
  Future<void> _reindex(ReferenceKind kind, Set<String> danceIds) async {
    if (kind == ReferenceKind.tag || danceIds.isEmpty) return;
    await _dances.reindexDerived(danceIds);
  }

  Future<List<IdAliasRow>> _aliases(ReferenceKind kind) => (_db.select(
    _db.idAliases,
  )..where((t) => t.kind.equals(kind.syncKind.name))).get();

  Future<List<RetainedSyncFieldsRow>> _retained(
    ReferenceKind kind,
    Set<String> ids,
  ) =>
      (_db.select(_db.retainedSyncFields)..where(
            (t) => t.kind.equals(kind.syncKind.name) & t.recordId.isIn(ids),
          ))
          .get();

  Future<List<PendingDeletionRow>> _pending(
    ReferenceKind kind,
    Set<String> ids,
  ) =>
      (_db.select(_db.pendingDeletions)..where(
            (t) => t.kind.equals(kind.syncKind.name) & t.recordId.isIn(ids),
          ))
          .get();

  /// Reverses what a merge did to `id_aliases`: a row it added is removed and
  /// a row whose chain it collapsed points where it did before, each only if
  /// it still reads as the merge left it.
  Future<void> _restoreAliases(
    ReferenceKind kind,
    List<IdAliasRow> before,
    List<IdAliasRow> after,
  ) async {
    final beforeByLoser = {for (final row in before) row.losingId: row};
    final current = {for (final row in await _aliases(kind)) row.losingId: row};
    for (final row in after) {
      final previous = beforeByLoser[row.losingId];
      if (previous == row) continue;
      if (current[row.losingId] != row) continue;
      if (previous == null) {
        await (_db.delete(_db.idAliases)..where(
              (t) =>
                  t.kind.equals(kind.syncKind.name) &
                  t.losingId.equals(row.losingId),
            ))
            .go();
      } else {
        await _db
            .into(_db.idAliases)
            .insert(previous, mode: InsertMode.insertOrReplace);
      }
    }
  }
}
