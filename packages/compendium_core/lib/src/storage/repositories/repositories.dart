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
  /// [onDerivedRebuildProgress], when supplied, is forwarded to
  /// [DanceRepository.rebuildAllDerived] so the caller (e.g. the app's startup
  /// screen) can show determinate progress for the post-migration derived-index
  /// rebuild instead of an indeterminate spinner (#440).
  Future<void> ensureMigrated({
    DerivedRebuildProgressCallback? onDerivedRebuildProgress,
  }) => _migration ??= _runMigration(onDerivedRebuildProgress);
  Future<void>? _migration;

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
        await db.customStatement('DELETE FROM settings WHERE key = ?', [
          derivedRebuildRequiredKey,
        ]);
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
      // The last sweep's result is deliberately not assigned: nothing follows
      // it today. It still REPORTS, so that adding a sweep after it is a
      // one-line change rather than a change to the contract above.
      await _stripStarPromenadeHandIfNeeded(
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
      await db.customStatement(
        'DELETE FROM program_slots WHERE dance_id IS NULL AND text IS NULL',
      );
      await db.customStatement(
        'DELETE FROM dance_links WHERE kind = ? AND target_dance_id IS NULL',
        [LinkKind.relatedDance.name],
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
        [purgeCorruptionRepairDoneKey, 'true'],
      );
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
    await db.customStatement(
      'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
      [sectionRuleVersionKey, '"$kSectionRuleVersion"'],
    );
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
        await db.customStatement(
          'UPDATE dances SET figures_json = ? WHERE id = ?',
          [encodeFigures(normalised.figures), dance.id],
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
    await db.customStatement(
      'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
      [inversePairNormalisationDoneKey, '"done"'],
    );
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
      await db.customStatement(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        [encodeFigures(stripped.figures), dance.id],
      );
    }

    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);

    // Write the marker AFTER success — if the rebuild throws, the marker is
    // not written and the next startup retries.
    await db.customStatement(
      'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
      [starPromenadeHandRemovalDoneKey, '"done"'],
    );
    // Reached only by running a rebuild (or having had one run earlier this
    // call), so a rebuild has always happened by this point.
    return true;
  }
}
