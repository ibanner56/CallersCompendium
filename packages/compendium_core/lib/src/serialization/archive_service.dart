import '../model/program.dart';
import '../storage/repositories/repositories.dart';
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
  Future<CompendiumArchive> export({
    DateTime? exportedAt,
    bool includeDeleted = true,
  }) async => CompendiumArchive(
    exportedAt: (exportedAt ?? DateTime.now()).toUtc(),
    dances: await _repos.dances.listAll(includeDeleted: includeDeleted),
    programs: await _repos.programs.listAll(includeDeleted: includeDeleted),
    choreographers: await _repos.choreographers.listAll(),
    publishedSources: await _repos.publishedSources.listAll(),
    customFields: await _repos.customFieldDefs.listAll(),
    tags: await _repos.tags.listAll(),
    venues: await _repos.venues.listAll(),
  );
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
/// Restore is transactional and partial-failure tolerant: a single entity that
/// fails to write is recorded in [ArchiveRestoreResult.errors] and the rest
/// still load — never a stack-trace UX.
class ArchiveRestorer {
  ArchiveRestorer(this._repos);

  final CompendiumRepositories _repos;

  Future<ArchiveRestoreResult> restore(
    CompendiumArchive archive, {
    RestoreMode mode = RestoreMode.replace,
  }) async {
    final errors = <ArchiveError>[];
    try {
      await _repos.db.transaction(() async {
        // Dances can reference each other (relatedDance links), so intra-batch
        // insert order — and even reference cycles — would otherwise trip
        // foreign keys. Deferring FK enforcement to commit time lets us load the
        // batch in a fixed order and only requires the final state to be
        // consistent.
        await _repos.db.customStatement('PRAGMA defer_foreign_keys = ON');
        if (mode == RestoreMode.replace) {
          await _clearAll();
        }
        await _load(archive, errors);
      });
    } on Exception catch (e) {
      // Deferred foreign-key checks and other integrity constraints only fire at
      // commit time, outside the per-entity `_guard`. Convert any such failure
      // into an archive-level structured error so callers always get a result
      // rather than a stack trace.
      errors.add(
        ArchiveError(
          kind: ArchiveErrorKind.restore,
          entityType: 'archive',
          message: 'archive could not be restored',
          cause: e,
        ),
      );
    }
    return ArchiveRestoreResult(errors: errors);
  }

  /// Writes every archive entity in foreign-key-safe order: the entities a
  /// dance references (published sources, choreographers, tags, custom-field
  /// defs) first, then dances, then venues, then programs (whose slots
  /// reference dances and whose `venueId` references a venue).
  Future<void> _load(
    CompendiumArchive archive,
    List<ArchiveError> errors,
  ) async {
    for (final s in archive.publishedSources) {
      await _guard('publishedSource', s.id, errors, () async {
        await _repos.publishedSources.upsert(s);
      });
    }
    for (final c in archive.choreographers) {
      await _guard('choreographer', c.id, errors, () async {
        await _repos.choreographers.upsert(c);
      });
    }
    for (final t in archive.tags) {
      await _guard('tag', t.id, errors, () async {
        await _repos.tags.upsert(t);
      });
    }
    for (final f in archive.customFields) {
      await _guard('customField', f.id, errors, () async {
        await _repos.customFieldDefs.upsert(f);
      });
    }
    for (final d in archive.dances) {
      await _guard('dance', d.id, errors, () async {
        await _repos.dances.create(d);
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
        await _repos.programs.create(
          _withResolvedVenue(p, knownVenueIds),
          knownVenueIds: knownVenueIds,
        );
      });
    }
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
  Program _withResolvedVenue(Program p, Set<String> knownVenueIds) {
    final venueId = p.venueId;
    if (venueId == null) return p;
    return knownVenueIds.contains(venueId) ? p : p.copyWith(clearVenueId: true);
  }

  /// Removes every user-content row (and its derived indexes) so a
  /// [RestoreMode.replace] loads into a clean database. Deletes join/derived
  /// tables before their parents to respect foreign keys, and clears the
  /// non-FK-linked `dance_fts` virtual table explicitly.
  Future<void> _clearAll() async {
    final db = _repos.db;
    await db.customStatement('DELETE FROM dance_fts');
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
