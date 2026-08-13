import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/enums.dart';
import '../../serialization/figure_codec.dart';
import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import 'choreographer_repository.dart';
import 'custom_field_repository.dart';
import 'dance_repository.dart';
import 'program_repository.dart';
import 'published_source_repository.dart';
import 'settings_repository.dart';
import 'tag_repository.dart';
import 'venue_repository.dart';

/// Bundles every repository over a single [CompendiumDatabase], so app code
/// wires up storage once (`CompendiumRepositories(db, taxonomy)`) instead of
/// constructing each repository individually.
class CompendiumRepositories {
  CompendiumRepositories(
    this.db,
    Taxonomy taxonomy, {
    SettingsRepository? settings,
  }) : dances = DanceRepository(db, taxonomy),
       choreographers = ChoreographerRepository(db),
       tags = TagRepository(db),
       customFieldDefs = CustomFieldDefRepository(db),
       programs = ProgramRepository(db),
       publishedSources = PublishedSourceRepository(db),
       venues = VenueRepository(db),
       settings = settings ?? SettingsRepository(db);

  final CompendiumDatabase db;
  final DanceRepository dances;
  final ChoreographerRepository choreographers;
  final TagRepository tags;
  final CustomFieldDefRepository customFieldDefs;
  final ProgramRepository programs;
  final PublishedSourceRepository publishedSources;
  final VenueRepository venues;
  final SettingsRepository settings;

  /// Emits once whenever anything the Collection's reference/vocabulary data is
  /// built from changes — the trigger for re-reading a `CollectionData`
  /// snapshot (issue #768).
  ///
  /// A **change signal**, not the data: it carries no payload, because the
  /// snapshot is assembled app-side from a fan-out of queries across six
  /// repositories and there is no single row set to hand back. Callers pair it
  /// with their own loader (see `CollectionData.watch`).
  ///
  /// ## The declared table set, justified per entry
  ///
  /// The same rule [ProgramRepository.watchCallingHistoryForDance] states:
  /// `customSelect` is opaque to drift, so every table the *composed read*
  /// touches must be named here or a subscriber silently stops updating. This
  /// set is the union of what `CollectionData.load` reads:
  ///
  /// * `dances` — the collection itself, and every facet vocabulary derived
  ///   from it (forms, formations, progressions, statuses, levels, and the
  ///   mixed-level / mixer / rating flags).
  /// * `choreographers` — author names, and the author facet.
  /// * `tags` — tag names and colours, and the tag facet.
  /// * `custom_field_defs` — the list/searchable field definitions.
  /// * `published_sources` — the cited-source facet.
  /// * `program_slots` and `programs` — the per-dance call tallies and
  ///   last-called stamps, exactly [ProgramRepository.programDerivedCounts]'s
  ///   read set, which is folded into the same snapshot.
  ///
  /// The **join** tables (`dance_authors`, `dance_tags`, `dance_sources`,
  /// `custom_field_values`) are deliberately absent, and the reason is worth
  /// stating precisely, because the obvious version of it is false.
  ///
  /// The claim has now been falsified twice, so it is stated here on the
  /// quantity that actually governs `readsFrom` rather than weakened a third
  /// time. The history is short and worth keeping, because each version was
  /// derived from whichever writers had been looked at:
  ///
  /// 1. *"only `DanceRepository`'s upsert writes them"* — false;
  ///    `ArchiveRestorer._clearAll` deletes all four directly.
  /// 2. *"every path that writes a join table also writes `dances` in the same
  ///    transaction"* — also false; `adoptTombstonedNaturalKey`
  ///    (`existence.dart`) deletes join rows and writes only the **adopted**
  ///    table, never `dances`.
  ///
  /// Enumerating every writer of the four join tables gives the invariant:
  ///
  /// | writer | join-table write | also writes, same transaction |
  /// |---|---|---|
  /// | `DanceRepository` upsert | `into(danceAuthors/Tags/Sources/customFieldValues)` | `dances` |
  /// | `ArchiveRestorer._clearAll` | `delete(...)` on all four | `dances` |
  /// | `adoptTombstonedNaturalKey` | `DELETE FROM <joinTable>` | `tags` / `choreographers` / `custom_field_defs` |
  ///
  /// **Every path that writes a join table also writes, in the same
  /// transaction, at least one table in the set watched above.** For two of
  /// them that table is `dances`; for natural-key adoption it is the adopted
  /// table, which is itself watched. Since drift dispatches a transaction's
  /// updates as one set on commit, a watcher is notified either way — so
  /// naming the join tables here would add emits without adding coverage.
  ///
  /// That is the right shape as well as the true one: `readsFrom` is a
  /// statement about the **watched set**, so the invariant belongs on the
  /// watched set. Both earlier versions named a single table and were falsified
  /// by the first writer that used a different one.
  ///
  /// The condition that breaks it is correspondingly narrow: a write that
  /// touches a join table and leaves **every** watched table untouched in that
  /// transaction. Such a writer would silently under-notify — no error, no
  /// dropped stream, just a Collection view whose tags or authors are wrong
  /// until some unrelated write arrives. If one is ever added, this set must
  /// grow.
  ///
  /// ### How to check a new writer
  ///
  /// The rule is decidable, so it is written as a procedure rather than as a
  /// list of blessed paths — a list goes stale the moment someone adds a path:
  ///
  /// 1. find the enclosing `transaction` of the join-table write;
  /// 2. list every table that transaction writes;
  /// 3. it is safe **iff** that list intersects the `readsFrom` set above.
  ///
  /// **The search in step 1 is where both falsifications came from, so do it
  /// by parameter as well as by name.** A grep for `danceTags` finds the
  /// upsert and `ArchiveRestorer._clearAll`, because those name the table
  /// directly. It does **not** find `adoptTombstonedNaturalKey`, which takes
  /// the table as an argument:
  ///
  /// ```dart
  /// // existence.dart — the table is a parameter, so the identifier
  /// // `dance_tags` appears nowhere in this file.
  /// 'DELETE FROM ${joinTable.actualTableName} WHERE $joinColumn = ?'
  /// ```
  ///
  /// Both earlier versions of this claim were derived from a name-based search
  /// and were falsified by a writer that search could not see. So:
  ///
  /// ```sh
  /// # names the table directly
  /// git grep -nE '(into|delete)\(_?db\.(danceAuthors|danceTags|danceSources|customFieldValues)\)'
  /// # takes it as a parameter
  /// git grep -n 'joinTable'
  /// ```
  ///
  /// `venues` is absent because `CollectionData` reads no venue data.
  ///
  /// ## The raw writes this signal does NOT cover, and why each is out of scope
  ///
  /// Auditing every raw SQL write in this package by target table — a script
  /// rather than a line-grep, since these statements wrap across lines and
  /// interpolate their table names — leaves three groups that still use
  /// `customStatement` and therefore reach no subscriber. They divide by the
  /// *strength* of what makes them safe, and the difference is the point:
  ///
  /// 1. **Structurally unreachable** — every raw write in `database.dart`
  ///    (eleven of them, touching `dances`, `settings` and the six v25 kinds)
  ///    sits inside `MigrationStrategy`, so it runs during `openConnection`,
  ///    before the database can serve a query at all, let alone hold a
  ///    watcher. Nothing can observe them by construction.
  ///
  ///    **"Eleven" counts row writes, not `customStatement` calls.** That file
  ///    has 21 of the latter; the other ten are DDL and a `PRAGMA`, several
  ///    passed as named SQL constants rather than literals, so they are
  ///    invisible to a search keyed on `INSERT`/`UPDATE`/`DELETE`. Re-count by
  ///    walking each call's argument and classifying its leading keyword, or a
  ///    different method will produce 21 and read as a correction to this
  ///    number rather than an answer to a different question.
  /// 2. **Converted, not merely safe** — the repair/normalisation sweeps *in
  ///    this file* used to write four tables raw: `program_slots` and
  ///    `dance_links` (the dangling-reference cleanup), `dances` (the
  ///    `figures_json`-only rewrites), and `settings` (the markers that decide
  ///    whether each sweep is owed). They now go through `customUpdate` with an
  ///    explicit `updates:` set, so every one of them reaches subscribers.
  ///
  ///    They were safe before that only by **ordering** — reached solely
  ///    through [ensureMigrated], which the app awaits in its startup sequence
  ///    before any screen mounts. That is a weaker guarantee than (1): app-level
  ///    sequencing rather than a property of the code, and the same shape as the
  ///    incidental co-location documented on
  ///    `DanceRepository._cleanupDanglingReferences`. Exposing any sweep as a
  ///    "repair my library" button, or moving one after the first frame, would
  ///    have turned it into an invisible write to a watched table with no
  ///    diagnostic. Converting them removes that future rather than documenting
  ///    it — see [ensureMigrated] for why this family was chosen over (1).
  ///
  ///    `settings` is still watched by nothing, so its conversion buys no
  ///    refresh today. It is deliberate all the same: the cost is one call
  ///    shape, and the alternative is a table that becomes exposed silently the
  ///    moment any screen reads a preference reactively. **Before adding such a
  ///    watcher, read the self-trigger hazard on `SettingsRepository`** — a
  ///    naive `settings` stream is woken by the program editor's own autosave.
  /// 3. **Unwatchable** — the `dance_fts` writes in `DanceRepository`. It is an
  ///    FTS index rebuilt from derived rows; nothing streams it and nothing
  ///    should.
  ///
  /// Group 2 was the only live thread here, and it has since been pulled — in
  /// its own change with its own reproduction, rather than folded into the
  /// conversion that made `dances` watched. Groups 1 and 3 stand.
  ///
  /// ## Why [includeVenues] is a parameter and not an entry (issue #944)
  ///
  /// This signal has three consumers and they do not read the same data. The
  /// Collection list renders no venue at all — `CollectionData` does not carry
  /// one — while the program editor and the program summary each resolve a
  /// venue *label* beside it, from a table this set omits.
  ///
  /// Adding `venues` unconditionally would fix their staleness by reloading the
  /// whole Collection snapshot on every venue edit for a screen that displays
  /// no venue, which is issue #340's over-firing: curing staleness by causing
  /// churn. Removing it is what leaves the labels stale. Neither is right,
  /// because **the set is being asked one question on behalf of consumers with
  /// different answers.**
  ///
  /// So the caller states what it renders. That is the whole of the fix: not a
  /// wider set, not a narrower one, but one chosen per consumer. Cheap here
  /// because there is exactly one axis of disagreement — if a second appears,
  /// this becomes an argument for a set built from the caller's needs rather
  /// than a boolean bolted onto a shared one.
  ///
  /// ## The SQL marker is load-bearing (drift `StreamKey`)
  ///
  /// drift caches active query streams by `StreamKey(sql, variables)` and
  /// **`readsFrom` is not part of that key**
  /// (`drift/lib/src/runtime/executor/stream_queries.dart`: `StreamKey` holds
  /// only `sql` and `variables`; `registerStream` returns the cached stream for
  /// an equal key). Two sentinels reading `SELECT 1` with *different* declared
  /// tables are therefore the same stream, and the second subscriber silently
  /// inherits the first's read set — including a narrower one.
  ///
  /// That is this issue's own defect arriving by a route no read set can close:
  /// the set is stated correctly at both call sites and one of them is ignored.
  /// It is also non-deterministic, because which set wins depends on which
  /// screen was opened first.
  ///
  /// So every sentinel carries a distinct comment naming its read set. The
  /// comment changes the SQL text — and therefore the key — while being inert
  /// to SQLite. Any new sentinel must do the same; the guard is
  /// `per_consumer_read_sets_test.dart`, which asserts the *behaviour* (one
  /// stream wakes, the other does not) rather than the marker, so it survives a
  /// change of technique here.
  Stream<void> watchCollectionSources({bool includeVenues = false}) => db
      .customSelect(
        includeVenues
            ? '/* collection sources +venues */ SELECT 1'
            : '/* collection sources */ SELECT 1',
        readsFrom: {
          db.dances,
          db.choreographers,
          db.tags,
          db.customFieldDefs,
          db.publishedSources,
          db.programSlots,
          db.programs,
          // Only for consumers that render a venue label. See above.
          if (includeVenues) db.venues,
        },
      )
      .watch()
      // Discard the sentinel rows: the payload is meaningless and mapping here
      // makes the runtime type genuinely `Stream<void>`, so a caller can
      // transform it without tripping over `Stream<List<QueryRow>>`.
      .map((_) {});

  /// Opens the database (running any pending schema migration) and, if a
  /// migration owes a derived-index rebuild, back-fills it.
  ///
  /// This is where the schema-v2 `dance_figures.section` back-fill happens:
  /// `MigrationStrategy.onUpgrade` performs the DDL and durably records
  /// [derivedRebuildRequiredKey] in `settings`, but recomputing the derived
  /// rows needs the taxonomy/renderer owned by [DanceRepository], which the
  /// migration strategy can't reach. Call this once at startup, after
  /// constructing the repositories, before the first read.
  ///
  /// Crash-safe and idempotent: the marker persists until the rebuild
  /// succeeds, so an interrupted upgrade is retried on the next open;
  /// concurrent calls share one in-flight future. A failed attempt clears the
  /// memo so a later call retries rather than replaying the cached failure.
  ///
  /// ## Every write below this point is visible to drift's watchers (#768)
  ///
  /// The sweeps reachable from here used to write with bare `customStatement`,
  /// which drift cannot attribute to a table and therefore does not broadcast.
  /// #932 closed that class in [DanceRepository]; this closed the rest of it.
  ///
  /// Why this family and not `database.dart`'s eleven raw writes, which remain
  /// raw: the full classification is on [watchCollectionSources], and the short
  /// version is that the two are protected by guarantees of different strength.
  /// `database.dart`'s sit inside `MigrationStrategy`, so no query has been
  /// issued yet and no stream can exist to miss them — **structural**, and not
  /// invalidatable by a later edit to this file. These ran on an already-open
  /// database and were safe only because the one production caller runs before
  /// the shell is built — **ordering**, which a future change breaks without
  /// noticing. Both were safe; only one was safe for a reason that survives the
  /// rest of #768.
  ///
  /// [onDerivedRebuildProgress], when supplied, is forwarded to
  /// [DanceRepository.rebuildAllDerived] so the caller (e.g. the app's startup
  /// screen) can show determinate progress for the post-migration derived-index
  /// rebuild instead of an indeterminate spinner (#440).
  Future<void> ensureMigrated({
    DerivedRebuildProgressCallback? onDerivedRebuildProgress,
  }) => _migration ??= _runMigration(onDerivedRebuildProgress);
  Future<void>? _migration;

  /// Writes a one-shot migration-sweep marker so drift's watchers see it.
  ///
  /// Five sweeps in this file record completion the same way. Routing them
  /// through one helper means the SQL identifier, the notified table and the
  /// update kind cannot drift apart in five places independently — the same
  /// reason #932 interpolated `actualTableName` rather than repeating a
  /// literal.
  ///
  /// ## Why no `updateKind`
  ///
  /// `INSERT OR REPLACE` is genuinely BOTH kinds: it inserts when the marker is
  /// absent and replaces an existing row when it is not, and which one happens
  /// is not knowable at the call site. Drift treats a null kind as "unspecified"
  /// and matches it against every `limitUpdateKind` filter
  /// (`stream_queries.dart`, `SpecificUpdateQuery.matches`: `update.kind == null
  /// || limitUpdateKind == null || update.kind == limitUpdateKind`).
  ///
  /// So omitting it is the accurate encoding rather than the lazy one. Naming a
  /// kind here would be a guess, and a wrong guess is worse than silence: a
  /// future rule filtering on the other kind would silently not match, which is
  /// exactly the invisible-write failure this change exists to remove.
  Future<void> _writeSweepMarker(String key, String valueJson) async {
    await db.customUpdate(
      'INSERT OR REPLACE INTO ${db.settings.actualTableName} '
      '(key, value_json) VALUES (?, ?)',
      variables: [Variable<String>(key), Variable<String>(valueJson)],
      updates: {db.settings},
    );
  }

  Future<void> _runMigration(
    DerivedRebuildProgressCallback? onDerivedRebuildProgress,
  ) async {
    try {
      // Force the lazily-opened database to run its migration strategy now, so
      // the marker (if any) reflects this open before we check it.
      await db.customSelect('SELECT 1').get();
      var rebuiltThisCall = false;
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ? '
            'AND deleted_at IS NULL',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      if (marker.isNotEmpty) {
        await runDerivedRebuild(onProgress: onDerivedRebuildProgress);
        rebuiltThisCall = true;
        // A HARD delete, deliberately, unlike `SettingsRepository.remove`.
        // This is migration bookkeeping rather than user data: there is nothing
        // for a peer to learn from a tombstone here, and the marker's whole
        // contract is "absent means the rebuild is done" — tombstoning it would
        // leave a row that the raw reads above must then keep filtering out
        // forever. Every one of those reads does filter `deleted_at IS NULL`
        // anyway, so a marker can neither be read back as still-set after this
        // clears it nor be resurrected by a stale row.
        await db.customUpdate(
          'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
          variables: [Variable<String>(derivedRebuildRequiredKey)],
          updates: {db.settings},
          updateKind: UpdateKind.delete,
        );
      }
      await _repairPurgeCorruptionIfNeeded();
      // Each sweep below reports back whether a derived rebuild has happened
      // during THIS call, so a later sweep can skip a byte-identical second
      // pass. The flag is threaded rather than recomputed because the sweeps
      // can each trigger the first rebuild of the call, and the "exactly one
      // rebuild" property is asserted in migration_test.dart.
      rebuiltThisCall = await _recomputeSectionLabelsIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _normaliseInversePairMoveIdsIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _stripStarPromenadeHandIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      // The last sweep's result is deliberately not assigned: nothing follows
      // it today. It still REPORTS, so that adding a sweep after it is a
      // one-line change rather than a change to the contract above.
      await _emitGripAndSingleFileIntoCanonicalIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
    } catch (_) {
      // Don't cache a failed migration: clear the memo so a subsequent call
      // retries. The durable marker is still set (only deleted after a
      // successful rebuild), so the retry re-does the back-fill.
      _migration = null;
      rethrow;
    }
  }

  /// The derived-index rebuild step of [ensureMigrated]. Extracted so tests can
  /// inject a transient failure and assert the marker survives and the retry
  /// succeeds. [onProgress] is forwarded to [DanceRepository.rebuildAllDerived].
  @protected
  @visibleForTesting
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) => dances.rebuildAllDerived(onProgress: onProgress);

  /// One-time repair for databases corrupted by a pre-fix hard purge (#429,
  /// #466). A `program_slots` row nulled to `(danceId, text) = (null, null)`
  /// carries no dance and no caption, so it is removed; a `relatedDance`
  /// `dance_links` row whose `targetDanceId` was SET NULL no longer points at
  /// anything, so it too is removed. Both cases otherwise throw on load and
  /// take down the whole Programs / Collection listing.
  ///
  /// Guarded by [purgeCorruptionRepairDoneKey] so it runs at most once per
  /// database (idempotent — a healthy database simply deletes nothing and marks
  /// the sweep done). Runs in a single transaction with the marker write so an
  /// interrupted repair is retried on the next open. Deliberately schema-version
  /// agnostic: the corruption can exist in databases already at the current
  /// version, which a version-gated migration would miss.
  Future<void> _repairPurgeCorruptionIfNeeded() async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(purgeCorruptionRepairDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return;
    await db.transaction(() async {
      await db.customUpdate(
        'DELETE FROM ${db.programSlots.actualTableName} '
        'WHERE dance_id IS NULL AND text IS NULL',
        updates: {db.programSlots},
        updateKind: UpdateKind.delete,
      );
      await db.customUpdate(
        'DELETE FROM ${db.danceLinks.actualTableName} '
        'WHERE kind = ? AND target_dance_id IS NULL',
        variables: [Variable<String>(LinkKind.relatedDance.name)],
        updates: {db.danceLinks},
        updateKind: UpdateKind.delete,
      );
      await _writeSweepMarker(purgeCorruptionRepairDoneKey, 'true');
    });
  }

  /// Recomputes `dance_figures.section` for all dances using the corrected
  /// zero-beat phrase-boundary rule (#844), if this has not already been done.
  ///
  /// Guarded by [sectionRuleVersionKey] so it runs at most once per database.
  /// The marker is written *after* a rebuild completes — an interrupted rebuild
  /// leaves the key absent and the sweep retries on the next open.
  ///
  /// [alreadyRebuilt] should be true when the caller already ran a full
  /// [runDerivedRebuild] earlier in this call (e.g. for [derivedRebuildRequiredKey]).
  /// In that case the section values are already correct and a second rebuild
  /// would be byte-identical work; the key is written directly instead.
  /// [onProgress] is forwarded to [runDerivedRebuild] when a rebuild is needed.
  ///
  /// Returns whether a derived rebuild has happened during this call — i.e.
  /// [alreadyRebuilt] OR this sweep ran one — so the caller can thread the flag
  /// into the next sweep.
  Future<bool> _recomputeSectionLabelsIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND value_json = ? '
          'AND deleted_at IS NULL',
          variables: [
            Variable.withString(sectionRuleVersionKey),
            Variable.withString('"$kSectionRuleVersion"'),
          ],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;
    // Skip the rebuild if one already ran this call — it used the current
    // labelForFigure code, so section values are already correct.
    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);
    await _writeSweepMarker(sectionRuleVersionKey, '"$kSectionRuleVersion"');
    return true;
  }

  /// One-time normalisation of `figures_json` for inverse-pair alias
  /// re-routing (#870). Scans all dances, and for any figure whose move id
  /// should be re-routed (e.g. `box_the_gnat{hand: left}` →
  /// `swat_the_flea`), rewrites `figures_json` with the corrected id.
  ///
  /// Guarded by [inversePairNormalisationDoneKey] so it runs at most once.
  /// The marker is written AFTER the pass succeeds — an interrupted
  /// normalisation retries on the next open.
  ///
  /// When [alreadyRebuilt] is true (a derived rebuild already ran this call),
  /// the derived rows are already correct — UNLESS this pass rewrites any
  /// `figures_json` rows, in which case a second rebuild is needed because
  /// the prior one ran against the pre-normalisation data. When false, a
  /// rebuild always follows because the balance.hand addition changes
  /// canonical keys even if no move ids were re-routed.
  ///
  /// **Fresh install:** no incoherent figures exist, so the scan finds
  /// nothing to update and writes the marker immediately. The pass is a
  /// no-op.
  ///
  /// Returns whether a derived rebuild has happened during this call — i.e.
  /// [alreadyRebuilt] OR this pass ran one — so the caller can thread the flag
  /// into the next sweep.
  Future<bool> _normaliseInversePairMoveIdsIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(inversePairNormalisationDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    final allDances = await dances.listAll(includeDeleted: true);
    var rewroteAny = false;
    for (final dance in allDances) {
      final normalised = dances.normaliseMoveIdsPublic(dance);
      if (!identical(normalised, dance)) {
        rewroteAny = true;
        // Rewrite only the figures_json column — nothing else about the dance
        // changes, and a full _upsert would needlessly rebuild derived rows
        // per dance (the bulk rebuild at the end is cheaper).
        await db.customUpdate(
          'UPDATE ${db.dances.actualTableName} SET figures_json = ? '
          'WHERE id = ?',
          variables: [
            Variable<String>(encodeFigures(normalised.figures)),
            Variable<String>(dance.id),
          ],
          updates: {db.dances},
          updateKind: UpdateKind.update,
        );
      }
    }

    // A derived rebuild is needed when:
    // - no rebuild has run yet this call (balance.hand changes canonical keys
    //   for every balance figure even if no figures_json was rewritten), OR
    // - this pass rewrote figures_json rows (the derived index is now stale
    //   even if a prior rebuild already ran — it ran against the old data).
    final rebuilt = !alreadyRebuilt || rewroteAny;
    if (rebuilt) {
      await runDerivedRebuild(onProgress: onProgress);
    }

    // Write the marker AFTER success — if the rebuild throws, the marker is
    // not written and the next startup retries.
    await _writeSweepMarker(inversePairNormalisationDoneKey, '"done"');
    return alreadyRebuilt || rebuilt;
  }

  /// One-time retirement of the `star_promenade.hand` param (#843, taxonomy
  /// v26). Scans all dances, strips a `hand` the MoveDef no longer declares
  /// from every stored `star_promenade` figure (including `meanwhile` sides),
  /// and rebuilds the derived index.
  ///
  /// Guarded by [starPromenadeHandRemovalDoneKey] so it runs at most once. The
  /// marker is written AFTER the pass succeeds — an interrupted pass retries on
  /// the next open.
  ///
  /// **The rebuild is owed by the TAXONOMY CHANGE, not by the rewrite count**
  /// — this is the one place this pass differs in spirit from
  /// [_normaliseInversePairMoveIdsIfNeeded], and the distinction is
  /// load-bearing:
  ///
  /// - **Every `star_promenade` figure's canonical key changes, not just the
  ///   ones that stored a `hand`.** `figureCanonicalKey` builds from
  ///   `Taxonomy.effectiveParams`, which used to fill `hand: right` for figures
  ///   that omitted it. Removing the declaration drops `hand=right` from every
  ///   key. So gating the rebuild on "did we rewrite any `figures_json`?" would
  ///   skip it precisely for the databases whose star promenades never stored
  ///   an explicit hand — the common case — leaving a stale FTS/dedupe index
  ///   forever. The rewrite count is the wrong signal entirely.
  /// - Nothing triggers a rebuild from the taxonomy version. `Taxonomy.version`
  ///   is stored on the object and never read by any runtime code, so this pass
  ///   is the ONLY thing that re-indexes for v26. (The v25 doc block in
  ///   `contra_taxonomy.dart` used to claim otherwise; corrected there.)
  ///
  /// [alreadyRebuilt] is still honoured, and unlike #870's pass it is honoured
  /// even when this pass rewrote rows. That is safe for a reason specific to
  /// this change: the strip removes a param the MoveDef no longer declares, so
  /// it changes NO derived value — `effectiveParams` was already ignoring it.
  /// A rebuild that ran earlier in this call therefore produced exactly the
  /// rows a post-strip rebuild would. #870's pass cannot make that claim
  /// because re-routing changes `figure.move`, which every derived row depends
  /// on.
  ///
  /// **Fresh install:** no stored figure carries the retired param, the scan
  /// rewrites nothing, and the rebuild (if not already done this call) runs
  /// over an empty database before the marker is written.
  ///
  /// The strip itself is hygiene rather than a correctness fix — a leftover
  /// `hand` is already inert, per the reasoning above. It stops dead data
  /// silently resurrecting if a later taxonomy re-declares `hand` on this move
  /// with a different meaning.
  ///
  /// Returns whether a derived rebuild has happened during this call — i.e.
  /// [alreadyRebuilt] OR this pass ran one — matching the other sweeps, so the
  /// caller can thread the flag onward. This pass is currently LAST in the
  /// chain and its caller discards the value; it is returned anyway because the
  /// point of the contract is the sweep that gets added after it.
  Future<bool> _stripStarPromenadeHandIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(starPromenadeHandRemovalDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    final allDances = await dances.listAll(includeDeleted: true);
    for (final dance in allDances) {
      final stripped = dances.stripStarPromenadeHandPublic(dance);
      if (identical(stripped, dance)) continue;
      // Rewrite only the figures_json column — nothing else about the dance
      // changes, and a full _upsert would needlessly rebuild derived rows per
      // dance (the bulk rebuild below is cheaper).
      await db.customUpdate(
        'UPDATE ${db.dances.actualTableName} SET figures_json = ? WHERE id = ?',
        variables: [
          Variable<String>(encodeFigures(stripped.figures)),
          Variable<String>(dance.id),
        ],
        updates: {db.dances},
        updateKind: UpdateKind.update,
      );
    }

    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);

    // Write the marker AFTER success — if the rebuild throws, the marker is
    // not written and the next startup retries.
    await _writeSweepMarker(starPromenadeHandRemovalDoneKey, '"done"');
    // Reached only by running a rebuild (or having had one run earlier this
    // call), so a rebuild has always happened by this point.
    return true;
  }

  /// One-time promotion of `star.grip`, `promenade.singleFile`, and
  /// `circle.singleFile` from display-only to canonical render tokens
  /// (#749 Gap B, taxonomy v27).
  ///
  /// Since taxonomy v27 these three params appear in `renderCanonical` → the
  /// `dance_fts` index, making stars searchable by "wrist grip" / "hands
  /// across" and promenade/circle figures by "single file". No `figures_json`
  /// rewrite is needed — only the derived index (canonical text + FTS row)
  /// changes. This pass therefore calls [runDerivedRebuild] and then writes
  /// its marker, with no preceding data sweep.
  ///
  /// **The rebuild is owed by the TAXONOMY CHANGE, not by rewrite count.**
  /// Existing derived rows in `dance_figures`/`dance_fts` were computed with
  /// the old renderer and their canonical text is stale. Gating on "did any
  /// `figures_json` row change?" would be zero — no source data changed — and
  /// the stale derived index would remain. The debt is unconditional; only the
  /// CALL is skipped when an earlier sweep in the same `ensureMigrated` has
  /// already rebuilt. (New figures imported after this code ships are not
  /// affected — `DanceRepository._upsert` calls `_rebuildDerived` at write
  /// time, so they always get the current renderer output.)
  ///
  /// Guarded by [gripSingleFileCanonicalInclusionDoneKey] so it runs at most
  /// once per database. The marker is written AFTER the rebuild succeeds — an
  /// interrupted pass retries on the next open (crash-safe).
  ///
  /// Returns whether a derived rebuild has happened during this call —
  /// [alreadyRebuilt] OR this pass ran one — matching the other sweeps.
  Future<bool> _emitGripAndSingleFileIntoCanonicalIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [
            Variable.withString(gripSingleFileCanonicalInclusionDoneKey),
          ],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);

    // Write the marker AFTER success — if the rebuild throws, the marker is
    // not written and the next startup retries.
    await _writeSweepMarker(gripSingleFileCanonicalInclusionDoneKey, '"done"');
    // Reached only by running a rebuild (or having had one run earlier this
    // call), so a rebuild has always happened by this point.
    return true;
  }
}
