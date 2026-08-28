import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/program.dart';
import '../storage/repositories/repositories.dart';
import '../storage/repositories/venue_repository.dart';
import '../storage/database.dart';
import 'compendium_archive.dart';

/// Reads the entire core-persisted collection into a [CompendiumArchive] for
/// backup or sharing (`docs/design/imports.md` §"Generic JSON (6.6)").
///
/// This is the export half of the canonical codec: it aggregates every
/// user-content entity (dances, programs, choreographers, published sources,
/// custom-field definitions, tags) via the repositories' `listAll` reads.
/// Serialize the result with `encodeArchive` from `archive_codec.dart`.
class ArchiveExporter {
  ArchiveExporter(this._repos);

  final CompendiumRepositories _repos;

  /// Builds an archive of the current dataset.
  ///
  /// [exportedAt] stamps the envelope (defaults to now, coerced to UTC).
  /// [includeDeleted] carries soft-deleted dances/programs (default `true`) so a
  /// backup is a faithful, restorable snapshot including items still within the
  /// retention window.
  ///
  /// All seven reads run inside a single [CompendiumRepositories.db]
  /// transaction so the export sees one consistent snapshot of the dataset —
  /// without it, a write landing between two reads could produce a
  /// cross-entity-inconsistent archive (e.g. a dance referencing a
  /// choreographer removed by a concurrent edit), which then fails its own
  /// restore (issue #615). The restore side is already transactional; this
  /// closes the asymmetry.
  Future<CompendiumArchive> export({
    DateTime? exportedAt,
    bool includeDeleted = true,
  }) async {
    final ts = (exportedAt ?? DateTime.now()).toUtc();
    return _repos.db.transaction(
      () async => CompendiumArchive(
        exportedAt: ts,
        dances: await _repos.dances.listAll(includeDeleted: includeDeleted),
        programs: await _repos.programs.listAll(includeDeleted: includeDeleted),
        choreographers: await _repos.choreographers.listAll(),
        publishedSources: await _repos.publishedSources.listAll(),
        customFields: await _repos.customFieldDefs.listAll(),
        tags: await _repos.tags.listAll(),
        venues: await _repos.venues.listAll(),
      ),
    );
  }
}

/// Applies a [CompendiumArchive] to a live dataset — the restore/import half of
/// the canonical codec.
///
/// [RestoreMode.replace] (the backup/restore default) clears the existing
/// collection and reloads it from the archive, so the archive becomes the whole
/// dataset. This is the mode under which the design's round-trip identity
/// property holds. [RestoreMode.merge] layers the archive onto the existing
/// collection by id (insert new, update existing); fuzzy dedupe-driven conflict
/// resolution (link/duplicate/skip via `src/imports/dedupe.dart`) for
/// user-to-user sharing is layered on at ROADMAP G.5.
///
/// Safety contract differs by mode:
/// - [RestoreMode.replace] is **all-or-nothing**. The clear and the reload run
///   in one transaction, and if *any* entity fails to write, the whole
///   transaction is rolled back — including the clear — so the user's existing
///   collection is left intact rather than wiped-then-partially-restored. A
///   replace is the operation users reach for when already in trouble, so a bad
///   archive must never be able to destroy live data (issue #430). Callers are
///   expected to fully decode/validate the archive first and refuse to invoke a
///   replace on an archive that did not decode cleanly.
/// - [RestoreMode.merge] is partial-failure tolerant: a single entity that
///   fails to write is recorded in [ArchiveRestoreResult.errors] and the rest
///   still load — never a stack-trace UX.
class ArchiveRestorer {
  ArchiveRestorer(this._repos);

  final CompendiumRepositories _repos;

  Future<ArchiveRestoreResult> restore(
    CompendiumArchive archive, {
    RestoreMode mode = RestoreMode.replace,
  }) async {
    final errors = <ArchiveError>[];
    final causalAt = DateTime.now().toUtc();
    // Distinguishes an intentional abort-to-rollback (replace mode saw a write
    // error) from an unexpected transaction failure, without depending on how
    // the database layer re-surfaces the thrown sentinel.
    var abortedForRollback = false;
    try {
      await _repos.db.transaction(() async {
        // Dances can reference each other (relatedDance links), so intra-batch
        // insert order — and even reference cycles — would otherwise trip
        // foreign keys. Deferring FK enforcement to commit time lets us load the
        // batch in a fixed order and only requires the final state to be
        // consistent.
        await _repos.db.customStatement('PRAGMA defer_foreign_keys = ON');
        if (mode == RestoreMode.replace) {
          // Validate-by-attempt, then commit-or-rollback: clear and reload in
          // the same transaction, but if the reload recorded any per-entity
          // failure, abort so the clear is rolled back too. This guarantees a
          // replace never leaves the user with wiped data and a half-applied
          // archive — either the whole archive writes, or live data is intact.
          await _clearAll();
          await _load(archive, errors, causalAt: causalAt);
          if (errors.isNotEmpty) {
            abortedForRollback = true;
            throw const _RestoreAborted();
          }
        } else {
          await _load(archive, errors, causalAt: causalAt);
        }
      });
    } on Exception catch (e) {
      if (!abortedForRollback) {
        // Deferred foreign-key checks and other integrity constraints only fire
        // at commit time, outside the per-entity `_guard`. Convert any such
        // failure into an archive-level structured error so callers always get
        // a result rather than a stack trace. The transaction has rolled back,
        // so (in replace mode) live data is preserved.
        errors.add(
          ArchiveError(
            kind: ArchiveErrorKind.restore,
            entityType: 'archive',
            message: 'archive could not be restored',
            cause: e,
          ),
        );
      }
    }
    return ArchiveRestoreResult(errors: errors);
  }

  /// Writes every archive entity in foreign-key-safe order: the entities a
  /// dance references (published sources, choreographers, tags, custom-field
  /// defs) first, then dances, then venues, then programs (whose slots
  /// reference dances and whose `venueId` references a venue).
  ///
  /// Choreographers, tags, and custom-field defs are upserted via methods that
  /// perform natural-key adoption: if a local tombstone holds the same UNIQUE
  /// name/key as the incoming entity, the upsert revives that tombstone under
  /// its *existing* id and returns that id rather than the archived one. The
  /// maps built here (`choreoRemap`, `tagRemap`, `fieldRemap`) capture those
  /// remapped ids and [_applyRemap] applies them to each dance before the dance
  /// is inserted, so a dance's `authorIds`, `tagIds`, and `customFieldValue`
  /// field ids all point at the ids that actually exist in the database.
  ///
  /// If an upsert fails (its id never enters the remap map), any dance that
  /// references the failed entity receives the un-remapped archived id. The
  /// blast radius differs by reference kind:
  /// - **`authorIds` / `tagIds`** — `dance_authors` and `dance_tags` carry
  ///   real foreign keys. With `PRAGMA defer_foreign_keys = ON` those checks
  ///   are deferred to commit time, so the dance insert succeeds and `_guard`
  ///   records nothing, but the transaction commit fails and the entire restore
  ///   is rolled back.
  /// - **`customFields` field ids** — validated inside `DanceRepository` at
  ///   write time as "unknown custom field", which surfaces as an Exception,
  ///   caught by `_guard`. Only that dance is recorded as an error; the rest of
  ///   the restore continues (in merge mode) or aborts (in replace mode).
  ///
  /// Both outcomes are correct: a dangling reference is never silently
  /// persisted.
  Future<void> _load(
    CompendiumArchive archive,
    List<ArchiveError> errors, {
    required DateTime causalAt,
  }) async {
    // archiveId -> writtenId for the three entity kinds that dance references.
    // An entry is only added on success; a failed upsert leaves no entry.
    final choreoRemap = <String, String>{};
    final tagRemap = <String, String>{};
    final fieldRemap = <String, String>{};

    for (final s in archive.publishedSources) {
      await _guard('publishedSource', s.id, errors, () async {
        // publishedSources.upsert returns Future<void> — it contains no
        // adoptTombstonedNaturalKey calls, so its id can never change. No
        // remap needed; the discard is structural, not an oversight.
        await _repos.publishedSources.upsert(s);
      });
    }
    for (final c in archive.choreographers) {
      await _guard('choreographer', c.id, errors, () async {
        final writtenId = await _repos.choreographers.upsert(c);
        choreoRemap[c.id] = writtenId;
      });
    }
    for (final t in archive.tags) {
      await _guard('tag', t.id, errors, () async {
        final writtenId = await _repos.tags.upsert(t);
        tagRemap[t.id] = writtenId;
      });
    }
    for (final f in archive.customFields) {
      await _guard('customField', f.id, errors, () async {
        final writtenId = await _repos.customFieldDefs.upsert(f);
        fieldRemap[f.id] = writtenId;
      });
    }
    for (final d in archive.dances) {
      await _guard('dance', d.id, errors, () async {
        final existingDeleted = await _repos.dances.isDeletedById(d.id);
        final wasTombstoned = existingDeleted == true && d.deletedAt == null;
        final wasLive = existingDeleted == false && d.deletedAt != null;
        final existing = wasTombstoned || wasLive
            ? await _repos.dances.getById(d.id, includeDeleted: true)
            : null;
        if (wasTombstoned) {
          await _repos.dances.restore(d.id, at: causalAt);
        }
        try {
          await _repos.dances.create(
            wasLive
                ? _applyRemap(
                    d,
                    choreoRemap,
                    tagRemap,
                    fieldRemap,
                  ).copyWith(clearDeletedAt: true)
                : _applyRemap(d, choreoRemap, tagRemap, fieldRemap),
          );
          if (wasLive) {
            await _repos.dances.softDelete(d.id, at: causalAt);
          }
        } on Exception {
          if (existing != null) {
            await _repos.dances.create(existing);
            if (wasTombstoned) {
              await _repos.dances.softDelete(d.id, at: causalAt);
            }
          }
          rethrow;
        }
      });
    }
    // Venues before programs: a program's `venueId` soft-references a venue, so
    // the referenced record must land first for the link to resolve.
    for (final v in archive.venues) {
      await _guard('venue', v.id, errors, () async {
        await _repos.venues.upsert(v);
      });
    }
    // Load the set of known venue ids **once** for the whole programs phase:
    // both the dangling-ref resolve-or-null below and the repository's
    // write-time integrity guard validate against this single snapshot, so
    // restoring N venue-linked programs issues one venue query instead of 2·N
    // (a per-program existence read here plus another inside each write).
    // Sound because restore only inserts venues (above) and never deletes one
    // mid-batch, so the snapshot cannot go stale under us.
    final knownVenueIds = await _repos.venues.listAllIds();
    for (final p in archive.programs) {
      await _guard('program', p.id, errors, () async {
        final existingDeleted = await _repos.programs.isDeletedById(p.id);
        final wasTombstoned = existingDeleted == true && p.deletedAt == null;
        final wasLive = existingDeleted == false && p.deletedAt != null;
        final existing = wasTombstoned || wasLive
            ? await _repos.programs.getById(p.id, includeDeleted: true)
            : null;
        if (wasTombstoned) {
          await _repos.programs.restore(p.id, at: causalAt);
        }
        try {
          await _repos.programs.create(
            wasLive
                ? _withResolvedVenue(
                    p.copyWith(clearDeletedAt: true),
                    knownVenueIds,
                  )
                : _withResolvedVenue(p, knownVenueIds),
            knownVenueIds: knownVenueIds,
          );
          if (wasLive) {
            await _repos.programs.softDelete(p.id, at: causalAt);
          }
        } on Exception {
          if (existing != null) {
            await _repos.programs.create(existing);
            if (wasTombstoned) {
              await _repos.programs.softDelete(p.id, at: causalAt);
            }
          }
          rethrow;
        }
      });
    }
  }

  /// Remaps a dance's entity references from archived ids to the ids that were
  /// actually written by the upserts.
  ///
  /// When natural-key adoption occurs (a tombstoned choreographer/tag/field def
  /// already holds the incoming entity's UNIQUE name/key), the upsert revives
  /// the tombstoned row under its existing id and returns that id. The archived
  /// id referenced by the dance would then dangle. This method substitutes the
  /// written id wherever the archived id appears, for all three reference kinds:
  /// [Dance.authorIds], [Dance.tagIds], and [Dance.customFields] field ids.
  ///
  /// A reference whose archived id is absent from the map (because its upsert
  /// failed and was recorded by [_guard]) is left as-is; the subsequent
  /// [DanceRepository.create] call will surface the dangling reference as its
  /// own [_guard]-caught error.
  Dance _applyRemap(
    Dance d,
    Map<String, String> choreoRemap,
    Map<String, String> tagRemap,
    Map<String, String> fieldRemap,
  ) {
    if (choreoRemap.isEmpty && tagRemap.isEmpty && fieldRemap.isEmpty) return d;
    return d.copyWith(
      authorIds: d.authorIds.map((id) => choreoRemap[id] ?? id).toList(),
      tagIds: d.tagIds.map((id) => tagRemap[id] ?? id).toList(),
      customFields: d.customFields
          .map(
            (v) => CustomFieldValue(
              fieldId: fieldRemap[v.fieldId] ?? v.fieldId,
              value: v.value,
            ),
          )
          .toList(),
    );
  }

  /// Guards against a **dangling** `venueId` from an untrusted bundle: if the
  /// program references a venue absent from [knownVenueIds] (the venues present
  /// after the archive's own venues were loaded, plus any pre-existing ones),
  /// the link is cleared before the program is written. `venueId` is a soft
  /// reference (no DB foreign key), so a dangling value would not fail at
  /// commit — but leaving one silently in place is exactly what the
  /// OWASP-aligned import contract forbids, so it is nulled rather than
  /// persisted as an unresolvable reference. A resolvable (or already-null)
  /// `venueId` is left untouched.
  Program _withResolvedVenue(Program p, LiveVenueIds knownVenueIds) {
    final venueId = p.venueId;
    if (venueId == null) return p;
    return knownVenueIds.contains(venueId) ? p : p.copyWith(clearVenueId: true);
  }

  /// Removes every user-content row (and its derived indexes) so a
  /// [RestoreMode.replace] loads into a clean database. Deletes join/derived
  /// tables before their parents to respect foreign keys, and clears the
  /// non-FK-linked FTS5 virtual tables explicitly.
  Future<void> _clearAll() async {
    final db = _repos.db;
    for (final table in const ['dance_fts', 'dance_substring_fts']) {
      await db.customStatement('DELETE FROM $table');
    }
    await db.delete(db.danceFigures).go();
    await db.delete(db.danceAuthors).go();
    await db.delete(db.danceTags).go();
    await db.delete(db.danceLinks).go();
    await db.delete(db.danceSources).go();
    await db.delete(db.customFieldValues).go();
    await db.delete(db.provenance).go();
    await db.delete(db.programSlots).go();
    await db.delete(db.dances).go();
    await db.delete(db.programs).go();
    await db.delete(db.customFieldDefs).go();
    await db.delete(db.tags).go();
    await db.delete(db.choreographers).go();
    await db.delete(db.publishedSources).go();
    await db.delete(db.venues).go();
    await db.customStatement('DELETE FROM normalisation_skips');
    await db.customStatement(
      'DELETE FROM settings WHERE key = ?',
      [shareableTextNormalisationScopeKey],
    );
  }

  Future<void> _guard(
    String entityType,
    String entityId,
    List<ArchiveError> errors,
    Future<void> Function() op,
  ) async {
    try {
      await op();
    } on Exception catch (e) {
      // Catch only Exceptions: Dart Errors signal programming/contract bugs and
      // should surface, not be swallowed as data-quality issues. Keep the
      // user-facing message stable (no engine-specific SQL leaking in); the raw
      // exception is preserved in `cause` for diagnostics.
      errors.add(
        ArchiveError(
          kind: ArchiveErrorKind.restore,
          entityType: entityType,
          entityId: entityId,
          message: 'could not be restored',
          cause: e,
        ),
      );
    }
  }
}

/// Internal signal used to roll back a [RestoreMode.replace] transaction when
/// the reload recorded a per-entity failure. It carries no data — the failures
/// are already collected in the caller's `errors` list — and only exists to
/// abort the transaction so the preceding `_clearAll()` is undone.
class _RestoreAborted implements Exception {
  const _RestoreAborted();
}
