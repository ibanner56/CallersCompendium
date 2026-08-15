import 'package:drift/drift.dart';

import '../model/enums.dart';
import '../model/formation.dart';
import 'tables.dart';

part 'database.g.dart';

/// The raw FTS5 virtual table backing full-text search.
///
/// Not a typed drift [Table]: it is a derived index that only the repository
/// layer ever writes to (in lockstep with [DanceFigures]); drift's typed FTS5
/// support targets `content=<table>`/`content=''` tables tied to a rowid
/// convention that doesn't map cleanly onto our text-typed `dances.id`
/// primary key. Deviating from the exact `content=''` sketch in
/// `docs/design/storage.md`, this table carries `dance_id` as an `UNINDEXED`
/// column instead, so rows are matched back to a dance directly without any
/// implicit-`rowid` bookkeeping. Same derived/rebuildable behavior, simpler
/// and more robust to maintain.
const String createDanceFtsSql = '''
CREATE VIRTUAL TABLE dance_fts USING fts5(
  dance_id UNINDEXED,
  title, authors, hook, notes, figures_text, custom_values, sources
)
''';

/// The schema-v2 helper index for section-aware figure search
/// (`docs/design/search.md`). Only the `(move, section)` index is created:
/// the `Then` sequence self-join is driven by `a.dance_id = b.dance_id`, which
/// is already served by the implicit index SQLite creates for the
/// `dance_figures` composite primary key `{danceId, idx}` (same leading
/// column). The correlation column `group_idx` (#748) is compared as a residual
/// filter over that already per-dance-restricted row set — a dance holds only
/// tens of figures — so no separate index on it is needed.
const List<String> searchIndexSql = [
  'CREATE INDEX IF NOT EXISTS dance_figures_move_section '
      'ON dance_figures(move, section)',
];

/// The v14 lookup index over `programs.venue_id`.
///
/// `VenueRepository.delete`'s guard counts the programs still referencing a
/// venue (`SELECT COUNT(id) FROM programs WHERE venue_id = ?`). Because a
/// venue is explicitly reusable across many programs, without this index that
/// COUNT would full-scan the whole `programs` table on every guarded delete
/// (O(total programs)); the index lets SQLite restrict the scan to just the
/// matching references. Declared raw (like [searchIndexSql]) rather than as a
/// drift-managed index. Originally applied in both `onCreate` and the v14
/// upgrade step (so fresh and migrated databases got it identically); the
/// upgrade step was retired along with v11-v19 when the floor was raised to
/// v20 (every surviving database already has this index from its own history),
/// so only `onCreate` still references it.
const List<String> venueLookupIndexSql = [
  'CREATE INDEX IF NOT EXISTS programs_venue_id ON programs(venue_id)',
];

/// Lookup index for `dance_id` on `dance_links` (schema v13).
///
/// Unlike the other dance-child tables — `dance_figures {danceId, idx}`,
/// `dance_authors {danceId, choreographerId}`, `dance_tags {danceId, tagId}`,
/// `dance_sources {danceId, sourceId}`, `custom_field_values {danceId, fieldId}`
/// and `provenance {danceId}` — whose composite primary keys lead with
/// `danceId` (so SQLite's implicit PK index already serves `WHERE dance_id IN
/// (…)`), `dance_links` is keyed on its own `id` alone. Without this index every
/// `dance_id IN (…)` chunk in [DanceRepository.listAll]'s batched link loader
/// (and the single-id lookup behind `getById`) is a full table scan, making the
/// link hydration O(N²) in row work as links grow with the collection. This
/// index turns each lookup into an index seek (`SEARCH … USING INDEX`) — the
/// loader still visits the matched `dance_links` rows to read the other columns
/// (it is a lookup index, not a covering one), but it no longer scans the whole
/// table — so the batching scales in execution work, not only in query count.
const String danceLinksDanceIdIndexSql =
    'CREATE INDEX IF NOT EXISTS dance_links_dance_id ON dance_links(dance_id)';

/// Lookup index for `dance_id` on `program_slots` (schema v16).
///
/// `program_slots` is keyed on its own `id` alone (not a `{danceId, ...}`
/// composite), so every per-dance calling-history/stats lookup that filters
/// `program_slots` by `dance_id` — `lastCalledByDance`, `countByDance`,
/// `callingHistoryForDance`, `halfCallingStatsForDance`,
/// `_sortByLastCalled`, and `_cleanupDanglingReferences` — full-scans the
/// whole table. This mirrors the v13 `dance_links_dance_id` index: a plain
/// lookup index (not covering) that turns those scans into index seeks.
const String programSlotsDanceIdIndexSql =
    'CREATE INDEX IF NOT EXISTS program_slots_dance_id '
    'ON program_slots(dance_id)';

/// Settings key marking that a schema migration touched the derived figure
/// index and the `dance_figures` rows must be rebuilt from `figures_json`.
///
/// Written inside `onUpgrade` (so it is durable — it survives a crash between
/// the schema bump and the rebuild) and cleared by
/// [CompendiumRepositories.ensureMigrated] only after the rebuild succeeds.
const String derivedRebuildRequiredKey = '__derived_rebuild_required__';

/// Settings key marking that the one-time purge-corruption repair (#429/#466)
/// has run against this database.
///
/// A pre-fix hard purge could leave two kinds of row that the domain layer
/// rejects: a *dance-only* `program_slots` row nulled to `(danceId, text) =
/// (null, null)` (#429), and a `relatedDance` `dance_links` row whose
/// `targetDanceId` was SET NULL (#466). Either one throws on load and takes
/// down the whole Programs / Collection listing. [CompendiumRepositories.
/// ensureMigrated] repairs any such legacy rows once and then writes this key
/// so the sweep is skipped on every later open.
///
/// Deliberately a durable settings marker rather than a schema bump: the
/// corruption can exist in databases already stamped at the current schema
/// version, so a version-gated migration would miss them.
const String purgeCorruptionRepairDoneKey = '__purge_corruption_repair_done__';

/// Settings key marking that the `dance_figures.section` column has been
/// recomputed under the corrected zero-beat phrase-boundary rule (#844).
///
/// Previous builds attributed a zero-beat figure at a phrase boundary to the
/// *next* phrase; the fix attributes it to the *preceding* one. Existing rows
/// carry the wrong label and must be recomputed.
///
/// Value `'1'` means the recomputation has run. [CompendiumRepositories.
/// ensureMigrated] writes this key *after* [DanceRepository.rebuildAllDerived]
/// succeeds, so a crash between them leaves the key absent and the rebuild
/// retries on the next open. On a fresh install the collection is empty;
/// the rebuild runs but produces no rows and the key is written immediately.
///
/// Deliberately a settings-marker rather than a schema bump: no column shape
/// is changing, only values. #837 set the schema floor at v11; a no-DDL bump
/// would muddy that history.
const String sectionRuleVersionKey = '__section_rule_version__';

/// The value written to [sectionRuleVersionKey] once the rebuild has run.
const String kSectionRuleVersion = '1';

/// Settings key for the one-time inverse-pair move-id normalisation (#870).
/// Written after a successful pass so it runs at most once per database.
const String inversePairNormalisationDoneKey =
    '__inverse_pair_normalisation_done__';

/// Settings key for the one-time `star_promenade.hand` retirement (#843,
/// taxonomy v26). Written after a successful pass so it runs at most once per
/// database.
const String starPromenadeHandRemovalDoneKey =
    '__star_promenade_hand_removal_done__';

/// Settings key for the one-time grip / singleFile canonical-text promotion
/// (#749 Gap B, taxonomy v27). Written after the derived rebuild that indexes
/// `star.grip`, `promenade.singleFile`, and `circle.singleFile` into
/// `dance_fts`, so the rebuild runs exactly once per database.
///
/// The rebuild is owed by the TAXONOMY CHANGE, not by rewrite count: adding
/// these tokens to `renderCanonical` changes the FTS-indexed text for any
/// figure with a non-default grip or singleFile, regardless of whether
/// `figures_json` itself changes.
const String gripSingleFileCanonicalInclusionDoneKey =
    '__grip_single_file_canonical_inclusion_done__';

/// Settings key for the one-time `chain.hand` role-implied backfill (#976,
/// taxonomy v28). Written after a successful pass so it runs at most once per
/// database.
///
/// For every stored `chain` figure that names a `who` of `role1s`/`role2s`
/// but stores no `hand`, the pass writes the role-implied side
/// (`chainHandForWho`) so structured search (`danceIdsWithFigure`, which
/// queries `move` + stored `params_json` — NOT `Taxonomy.effectiveParams`,
/// per `database.dart`'s own contract below) finds a bare `ladies chain`
/// imported before this release exactly like one imported after it. A chain
/// with no stored `who` is deliberately left alone: its role is unknown, so
/// any hand written for it would come from the taxonomy default rather than
/// the source (see the taxonomy's `chain.hand` doc comment).
///
/// Unlike the taxonomy-version-owed sweeps above (grip/singleFile,
/// star_promenade.hand), this pass's rebuild is owed strictly by ROW COUNT,
/// matching `_normaliseInversePairMoveIdsIfNeeded`: a bare chain's canonical
/// text is unaffected either way (the renderer already silences the
/// role-implied `hand`, whether it is the `unspecified` sentinel pre-backfill
/// or the concrete side post-backfill — see `renderer.dart`'s chain-hand
/// silencing block), so the derived index goes stale only for the rows this
/// pass actually rewrites (`params_json`'s stored `hand`), never
/// unconditionally.
const String chainHandBackfillDoneKey = '__chain_hand_backfill_done__';

/// The current on-disk schema version of [CompendiumDatabase].
///
/// Exposed as a top-level constant (in addition to the [CompendiumDatabase.
/// schemaVersion] getter) so the app-layer migration preflight can compare a
/// file's persisted `user_version` against the running schema *without* opening
/// the database. Keep this and the migration `onUpgrade` steps in lockstep.
const int kCompendiumSchemaVersion = 25;

/// The oldest on-disk schema version this build can still upgrade.
///
/// Schema versions below this were retired (#837, and again raised past v19):
/// their `onUpgrade` steps, fixture databases and `drift_schemas/generated/`
/// dumps have been deleted, so there is no migration path from such a file to
/// head. `onUpgrade` refuses one explicitly rather than running only the
/// surviving steps and silently producing a structurally wrong database.
///
/// The value is the schema version shipped by the oldest *supported release*,
/// `v0.1.0-beta.6` — not simply the oldest version whose code still exists.
/// beta.5 shipped v15 (the last version below this floor ever shipped to a
/// tester) and beta.6 shipped v20, so a database last opened by beta.5 or
/// earlier is below the floor and will be refused; that is deliberate, on the
/// basis that every tester is on beta.6 or later.
///
/// Raising this is a user-visible change: databases below the new floor stop
/// opening. It belongs in `app/CHANGELOG.md`, stated in user-facing terms, with
/// the release whose schema version is being adopted named as the reason.
const int kMinSupportedSchemaVersion = 20;

/// The Caller's Compendium local database.
///
/// The per-version schema log — every version from v1, including the
/// v1–v19 entries retired by #837 — lives in `docs/design/storage.md` under
/// "Schema version history". **Every bump appends an entry there in the same
/// PR**; `tools/ci/check_version_history.py` fails the build otherwise. It is
/// kept there because it is a ledger of decisions already shipped, and it grew
/// on every bump; what constrains this declaration stays below.
///
/// Every future migration must (a) bump [schemaVersion], (b) add a
/// `MigrationStrategy` step for the new version, (c) ship a test that
/// opens a fixture DB created at the previous version and asserts the
/// migrated schema/data (see `test/storage/migration_test.dart`), and (d) add a
/// drift schema dump for the new version under `drift_schemas/` (see the README
/// there). CI enforces (c) and (d): a change to this constant fails the build
/// unless the same PR also adds/changes a migration test, a
/// `test/storage/fixtures/` fixture, or a `drift_schemas/` dump — and
/// `test/storage/schema_verification_test.dart` fails outright if a version has
/// no dump.
///
/// (d) is what asserts *shape*: that a database which reached head by migration
/// is structurally identical to one created fresh at head. The tests under (c)
/// assert data semantics and deliberately do not cover that.
///
/// Release rule: **never bump [schemaVersion] in a PATCH release** — a schema
/// change is a data-format change and must ride at least a MINOR bump (see
/// CONTRIBUTING.md).
@DriftDatabase(
  tables: [
    Dances,
    Choreographers,
    DanceAuthors,
    DanceFigures,
    Programs,
    ProgramSlots,
    CustomFieldDefs,
    CustomFieldValues,
    Tags,
    DanceTags,
    DanceLinks,
    Provenance,
    PublishedSources,
    DanceSources,
    Settings,
    ProgramProvenance,
    Venues,
  ],
)
class CompendiumDatabase extends _$CompendiumDatabase {
  /// Opens the database over [executor].
  ///
  /// Pass [closeStreamsSynchronously] `true` in **widget tests**, and only
  /// there. When the last listener of a `.watch()` stream detaches, drift by
  /// default keeps that stream's cache for one event-loop iteration — via a
  /// zero-duration `Timer` — so a `StreamBuilder` that re-subscribes during a
  /// rebuild does not re-run the query. That is the right behaviour in the app.
  ///
  /// `flutter_test` runs inside `fake_async`, which fails any test that ends
  /// with a timer outstanding. So a widget test that unmounts a screen holding
  /// a reactive read (issue #768) fails with "Pending timers" pointing into
  /// `StreamQueryStore.markAsClosed` — a harness artefact, not a leak, and one
  /// that appears in tests which never mention streams themselves because they
  /// merely mount a shell containing a converted screen. Drift exposes this
  /// flag for exactly that case (see `DatabaseConnection`), and the app's test
  /// helpers set it; production keeps the cache.
  CompendiumDatabase(
    QueryExecutor executor, {
    bool closeStreamsSynchronously = false,
  }) : super(
         DatabaseConnection(
           executor,
           closeStreamsSynchronously: closeStreamsSynchronously,
         ),
       );

  @override
  int get schemaVersion => kCompendiumSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(createDanceFtsSql);
      for (final sql in searchIndexSql) {
        await customStatement(sql);
      }
      await customStatement(danceLinksDanceIdIndexSql);
      for (final sql in venueLookupIndexSql) {
        await customStatement(sql);
      }
      await customStatement(programSlotsDanceIdIndexSql);
    },
    onUpgrade: (m, from, to) async {
      // Belt-and-suspenders downgrade guard. drift is forward-only and has no
      // `onDowngrade`; it invokes `onUpgrade` whenever the stored version
      // differs from the running one — *including* `from > to` (a file written
      // by a newer build). None of the `if (from < N)` steps below would fire,
      // so drift would silently stamp `user_version` DOWN to `to` while leaving
      // newer tables/columns in place, risking corruption. Refuse instead. The
      // app layer normally catches this earlier (see the migration preflight in
      // `app/lib/src/data/migration_guard.dart`); this is the last line of
      // defense for any open path that bypasses it.
      if (from > to) {
        throw StateError(
          'Refusing to migrate the database down: it was created at schema '
          'version $from by a newer build, but this build only understands '
          'version $to.',
        );
      }
      // Schema floor (#828). Versions below [kMinSupportedSchemaVersion] were
      // retired: their `onUpgrade` steps, fixtures and schema dumps are gone, so
      // there is no path from such a file to head. Refuse it explicitly.
      //
      // This check is NOT optional cleanup. Without it a below-floor database
      // would open, run only the surviving steps, and end up structurally wrong
      // with no error at all — silent corruption of a user's collection, which
      // is a far worse outcome than refusing to open the file.
      //
      // KNOWN GAP — the app layer does *not* yet catch this earlier, unlike the
      // downgrade case above. `runMigrationPreflight` reads `user_version`
      // without opening the database and throws `DatabaseDowngradeError`, which
      // `AppBootstrap` renders as a dedicated terminal screen with no Retry;
      // `MigrationSnapshotAborted` gets the same treatment. This error is not
      // one of those types, so it falls through to the generic
      // `appBootstrapError` screen — **with a Retry button that can never
      // succeed**. The user is protected from the silent corruption above, but
      // is told nothing useful and can retry forever.
      //
      // The fix mirrors the downgrade path and is deliberately not bundled with
      // the retirement (it lands on `app_en.arb` and the generated l10n, which
      // several changes are converging on): add a typed `DatabaseTooOldError`
      // thrown from `runMigrationPreflight` in
      // `app/lib/src/data/migration_guard.dart`, a label in
      // `app/lib/src/data/migration_error_labels.dart`, a new ARB key, and a
      // no-Retry branch in `app/lib/src/widgets/app_bootstrap.dart`. This throw
      // then stays as the backstop for any open path that bypasses the
      // preflight, exactly as the downgrade guard above does.
      if (from < kMinSupportedSchemaVersion) {
        throw StateError(
          'This database was created at schema version $from by a build from '
          'before the first supported release, and cannot be upgraded: the '
          'migration steps for versions below $kMinSupportedSchemaVersion were '
          'retired. Open it with an older build of Caller\'s Compendium first, '
          'or start from a fresh database.',
        );
      }

      if (from < 21) {
        // Issues #781/#782: the first migration in this schema's history to
        // REMOVE storage rather than add or rewrite it. Three drops, all of
        // storage that no code path ever read:
        //
        //   * `provenance.raw_payload` — the verbatim imported source record.
        //     For an HTML import this was the whole source page (~7.5 KB for
        //     this repo's own ContraDB fixture), per dance, round-tripping
        //     through every backup. It was justified as enabling "re-import
        //     diffing"; that feature exists (`figure_diff.dart`) but compares
        //     PARSED figures and never read this column. Re-import dedupes on
        //     `(source, external_id)` and re-fetches, so nothing regresses.
        //   * `program_provenance.raw_payload` — the same column on the
        //     program side, where no import path ever wrote it. It is null for
        //     every row that has ever existed, so this half is a pure no-op on
        //     real data.
        //   * the `snapshots` table — scaffolding for hosted-archive "update
        //     available" prompts, a feature since CUT (ROADMAP 6.2/6.3;
        //     `docs/design/callersbox-snapshot.md` is marked superseded).
        //     `SnapshotRepository.upsert` had no call sites, so the table is
        //     empty in every real database.
        //
        // This DELETES user data (the dance-side payloads) and is not
        // reversible by downgrading. That was a deliberate call: the data was
        // unreadable by any feature, and carrying it forever costs every user
        // storage and backup size for nothing.
        //
        // `alterTable` rebuilds each provenance table from its current Dart
        // definition and copies the surviving columns across by name — the
        // portable route, and the one that does not depend on the host
        // SQLite being new enough for `ALTER TABLE … DROP COLUMN` (3.35+),
        // which we cannot assume across six platforms.
        await m.alterTable(TableMigration(provenance));
        await m.alterTable(TableMigration(programProvenance));
        await m.deleteTable('snapshots');

        // No derived rebuild is owed: none of the three feeds `dance_figures`
        // or `dance_fts`, so the search indexes are unaffected.
      }

      if (from < 22) {
        // Issue #748: add the derived `dance_figures.group_idx` correlation
        // column so the `Then` sequence operator can tell a genuine "before /
        // after" pair from two *concurrent* sides of one `meanwhile` container.
        //
        // Before this, `Then` correlated on `a.idx < b.idx`; but the #590
        // flattener gives a container's concurrent sides consecutive `idx`
        // values (the `{danceId, idx}` PK forces a distinct idx per row), so
        // `a.idx < b.idx` held between two sides that are simultaneous by
        // construction and `Then(X, Y)` — and symmetrically `Then(Y, X)` —
        // matched an `X while Y` container. The concurrency signal was absent
        // from the index entirely, so this needs a schema column, not just a
        // query change. `group_idx` is shared by every row flattened from one
        // top-level figure and monotonic across them (see `_insertDerivedRows`);
        // `Then` now correlates on `a.group_idx < b.group_idx`.
        //
        // Like the v2 `section` add, existing rows get the column DEFAULT (0),
        // which is wrong for correlation (every row would share group 0), so a
        // derived rebuild is owed to repopulate `group_idx` from `figures_json`.
        // The rebuild needs the taxonomy/renderer, unreachable from
        // `MigrationStrategy`, so durably record that it is owed (crash-safe);
        // `CompendiumRepositories.ensureMigrated()` then regenerates
        // `dance_figures` + `dance_fts` from `figures_json`.
        await m.addColumn(danceFigures, danceFigures.groupIdx);
        await customStatement(
          'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
          [derivedRebuildRequiredKey, 'true'],
        );
      }

      if (from < 23) {
        // Issue #780: add `custom_field_defs.shareable` — a per-field flag
        // controlling whether the field and its values travel in shared
        // archives. DEFAULT 1 (shareable = true) so every existing row
        // preserves today's behaviour: a pre-v23 custom field continues to
        // travel in archives after upgrade. Users opt out per-field. No figure
        // index is touched; no derived rebuild is required.
        await m.addColumn(customFieldDefs, customFieldDefs.shareable);
      }

      if (from < 24) {
        // Issue #732: add `dances.mixer` — a boolean flag marking a dance in
        // which dancers change partners each time through. DEFAULT 0
        // (mixer = false) so every existing row preserves today's behaviour:
        // the concept could not be expressed before, so nothing was a mixer,
        // and the additive default keeps it that way after upgrade. Users set
        // it per-dance in the editor, and the Caller's Box importer infers it
        // (see `callersbox_adapter.dart`). No figure index is touched; no
        // derived rebuild is required.
        await m.addColumn(dances, dances.mixer);
      }

      if (from < 25) {
        // Issue #898: the Device Sync schema migration. Adds the sync timestamp
        // triple to every syncable kind — twenty columns across eight tables —
        // and converts the entity-level hard deletes to tombstones. See the
        // note at the top of `tables.dart` for what each of the three columns
        // means and why none of them can be folded into another.
        //
        // Six tables gain all three (`settings`, `choreographers`, `tags`,
        // `published_sources`, `custom_field_defs`, `venues`); `dances` and
        // `programs` already carry `updated_at`/`deleted_at` and gain only
        // `existence_at`.
        //
        // Every column is NULLABLE, so there is no DEFAULT to preserve
        // behaviour with — the back-fill below does that job instead. This is
        // forced: SQLite's ALTER TABLE ADD COLUMN refuses a NOT NULL column
        // unless it carries a *constant* default, and no constant is a truthful
        // timestamp (an epoch-0 sentinel reads as a real 1970 stamp, which is
        // worse than NULL). A 12-step table rebuild per table would allow NOT
        // NULL, and was rejected as disproportionate for a migration whose
        // stated design goal is a reviewable blast radius.
        //
        // No figure index is touched; no derived rebuild is required. Nothing
        // reads `existence_at` yet — there is no sync client — so this step is
        // behaviour-preserving apart from deletions becoming observable.
        // ADD COLUMN, GUARDED — and the guard is load-bearing, not defensive
        // tidiness. `m.createTable` in a historical step builds the table from
        // *today's* Dart definition, not the definition that was current when
        // that step was written. `venues` used to be created by the `from < 14`
        // step (v14, "first-class venue entity"; see the schema history in
        // `docs/design/storage.md`), which meant a database arriving from
        // v11..v13 reached this point with
        // `venues` already carrying all three v25 columns, and an unguarded
        // `addColumn` would fail with "duplicate column name: updated_at". That
        // exact `from` range is no longer reachable — v11..v19 were retired when
        // the floor was raised to v20 (every database that can now reach
        // `onUpgrade` already had `venues` created back when it was still on a
        // pre-v25 build, so this specific hazard cannot recur) — but the guard is
        // kept and written generically, not scoped to `venues`, so a future
        // table-creating step cannot reintroduce the same class of failure.
        //
        // Skipping is correct rather than merely safe: a table created from
        // today's definition already has the column in its final shape, and
        // `createTable` leaves it empty, so there is nothing to back-fill
        // either.
        Future<void> addColumnIfMissing(
          TableInfo<Table, dynamic> table,
          GeneratedColumn<Object> column,
        ) async {
          final existing = await customSelect(
            "SELECT name FROM pragma_table_info('${table.actualTableName}')",
          ).get();
          final present = {
            for (final row in existing) row.read<String>('name'),
          };
          if (present.contains(column.name)) return;
          await m.addColumn(table, column);
        }

        await addColumnIfMissing(settings, settings.updatedAt);
        await addColumnIfMissing(settings, settings.deletedAt);
        await addColumnIfMissing(settings, settings.existenceAt);
        await addColumnIfMissing(choreographers, choreographers.updatedAt);
        await addColumnIfMissing(choreographers, choreographers.deletedAt);
        await addColumnIfMissing(choreographers, choreographers.existenceAt);
        await addColumnIfMissing(tags, tags.updatedAt);
        await addColumnIfMissing(tags, tags.deletedAt);
        await addColumnIfMissing(tags, tags.existenceAt);
        await addColumnIfMissing(publishedSources, publishedSources.updatedAt);
        await addColumnIfMissing(publishedSources, publishedSources.deletedAt);
        await addColumnIfMissing(
          publishedSources,
          publishedSources.existenceAt,
        );
        await addColumnIfMissing(customFieldDefs, customFieldDefs.updatedAt);
        await addColumnIfMissing(customFieldDefs, customFieldDefs.deletedAt);
        await addColumnIfMissing(customFieldDefs, customFieldDefs.existenceAt);
        await addColumnIfMissing(venues, venues.updatedAt);
        await addColumnIfMissing(venues, venues.deletedAt);
        await addColumnIfMissing(venues, venues.existenceAt);
        await addColumnIfMissing(dances, dances.existenceAt);
        await addColumnIfMissing(programs, programs.existenceAt);

        // T₀ — one instant sampled here and written to every live row, so that
        // no live row outranks another and the first real transition on any
        // device establishes the ordering. `updated_at` on the six tables that
        // just gained it is stamped from the same sample: same number, two
        // different meanings ("this row's content was last written at" and
        // "this row's existence was last decided at"), which happen to coincide
        // because the migration is the only event either column can point at.
        // That coincidence is confined to those six tables — `dances` and
        // `programs` keep their own per-row `updated_at`, so there the two
        // columns diverge immediately, which is what the migration test
        // asserts against.
        //
        // Stored as unix seconds because that is drift's mapping for
        // DateTimeColumn (see `existence.dart` for why the tick size follows
        // from this).
        final t0 = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        // THE BACK-FILL RULE, AND WHY THE OBVIOUS CHOICE IS WRONG.
        //
        // `existence_at` MUST NOT be copied from `updated_at`. That is the
        // natural thing to reach for and it reintroduces, through the
        // migration, the exact coupling the third column exists to break: a
        // device that *edited* a live record after another device *deleted* it
        // would carry `existence_at = updated_at` greater than the tombstone's,
        // its live copy would outrank the tombstone, and the record would come
        // back on first sync. At launch the entire corpus is pre-migration
        // rows, so that would be the common case rather than an edge case.
        //
        // Back-fill from the row's existence history instead:
        //   * live               -> T₀
        //   * already tombstoned -> its own `deleted_at`, which is when its
        //                           existence actually last changed. This is
        //                           the one case where a pre-existing column
        //                           carries the right meaning.
        //
        // COALESCE expresses exactly that, and is applied uniformly to all
        // eight tables. On the six that gained `deleted_at` in this same step
        // it can only ever take the T₀ branch (the column is new, so every row
        // is live); writing it the same way everywhere states the rule once
        // rather than encoding "these tables cannot have tombstones yet" as an
        // invisible assumption that a later change could falsify.
        //
        // ACCEPTED CONSEQUENCE (maintainer decision, recorded in
        // docs/design/sync.md): T₀ is a per-device sampled clock, not a
        // hardcoded pre-release constant, so it is necessarily later than any
        // deletion already in the past. A device that deleted record R before
        // migrating carries `existence_at = deleted_at` for it; a device that
        // never deleted R and migrates later carries T₀, which is greater — so
        // on first sync the live copy outranks the tombstone and R comes back.
        // This is not bounded by the migration window: T₀ remains a record's
        // operative existence value until that record has another live<->
        // deleted transition. The alternative (a hardcoded pre-release
        // constant) was considered and not taken.
        for (final table in const [
          'settings',
          'choreographers',
          'tags',
          'published_sources',
          'custom_field_defs',
          'venues',
        ]) {
          await customStatement(
            'UPDATE $table SET updated_at = ?, '
            'existence_at = COALESCE(deleted_at, ?)',
            [t0, t0],
          );
        }
        for (final table in const ['dances', 'programs']) {
          await customStatement(
            'UPDATE $table SET existence_at = COALESCE(deleted_at, ?)',
            [t0],
          );
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.wasCreated) return;
      // Defensive: guards a hand-rolled DB (e.g. restored from an
      // external backup) that predates the FTS5 table.
      final tables = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='dance_fts'",
      ).get();
      if (tables.isEmpty) {
        await customStatement(createDanceFtsSql);
      }
    },
  );

  /// Runs SQLite's `PRAGMA quick_check`, returning `true` when the database
  /// reports `ok`. Wired into app startup (`_CompendiumAppState._startupSequence`
  /// in `app/lib/main.dart`) so it runs once per app launch per
  /// `docs/design/storage.md` ("Durability"); a failure is surfaced to the user
  /// as a non-fatal corruption warning.
  Future<bool> quickCheck() async {
    final rows = await customSelect('PRAGMA quick_check').get();
    return rows.length == 1 && rows.first.data.values.first == 'ok';
  }
}
