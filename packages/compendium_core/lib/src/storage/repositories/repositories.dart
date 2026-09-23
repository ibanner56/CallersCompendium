import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/enums.dart';
import '../../model/figure.dart';
import '../../model/figure_source.dart';
import '../../privacy/field_registry.dart';
import '../../privacy/data_classification.dart';
import '../../privacy/settings_registry.dart';
import '../../serialization/figure_codec.dart';
import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import '../shareable_text.dart';
import 'choreographer_repository.dart';
import 'collection_import_event_repository.dart';
import 'custom_field_repository.dart';
import 'dance_repository.dart';
import 'difficulty_level_repository.dart';
import 'program_repository.dart';
import 'published_source_repository.dart';
import 'settings_repository.dart';
import 'sync_local_repository.dart';
import 'tag_repository.dart';
import 'venue_repository.dart';

const _shareableTextNormalisationAlgorithmVersion = 2;
const _taxonomyV35MigrationPageSize = 128;

/// The columns the normalisation pass canonicalizes as JSON rather than as
/// plain text. These are the only columns whose stored value can fail to
/// canonicalize at all, so they are also the only ones for which the pass must
/// be able to name a record to skip — see [_normaliseStoredColumn] and the
/// record-id select in `_normaliseShareableTextIfNeeded`.
const _shareableJsonColumns = {'figures_json', 'tunes_json', 'choices_json'};

/// The normalized form of [raw] for [column], or **null when the stored value
/// cannot be canonicalized at all**.
///
/// Returning null rather than raising is required, not defensive.
/// `docs/design/sync-spec.md` §4.1 makes skipping the pass's only failure
/// response *so that the pass is total*: "no row raises, so an interrupted pass
/// cannot repeat a failure on every launch". An exception escaping here leaves
/// `ensureMigrated()` failing identically on every launch, which is the app's
/// startup error screen with a Retry that cannot succeed (#1347).
///
/// Three things can fail, and the third is not obvious:
/// * [FormatException] — the text is not JSON.
/// * [ShareableJsonKeyCollision] — two object keys normalize to one key.
/// * [JsonUnsupportedObjectError] — the text *is* valid JSON, decodes, and then
///   cannot be re-encoded. `1e999` is legal JSON syntax that `jsonDecode` reads
///   as `double.infinity`, which `jsonEncode` refuses. The decode/encode round
///   trip is therefore not total over its own accepted input, so "it came from
///   `jsonDecode`, so it must re-encode" is false.
///
/// Only the [_shareableJsonColumns] branch can return null — [
/// normalizeShareableText] has no failing input — so a caller that handles null
/// by recording a skip needs a record id only for those columns.
///
/// [ArgumentError] from a non-String JSON object key is deliberately not caught:
/// `jsonDecode` genuinely cannot produce one (unlike the infinity case above,
/// where the same reasoning does not hold), so catching it here would claim to
/// handle a case that cannot reach this function.
///
/// **This is not a general "may the skip be cleared?" predicate**, and reading
/// it as one is the mistake #1346 had to avoid. It answers that question for
/// the [_shareableJsonColumns] branch only. For every other column the
/// non-JSON branch returns [normalizeShareableText], whose return type is
/// non-nullable, so this function is *statically incapable* of returning null
/// there and the test is vacuously true — while a natural-key row's entry may
/// be cleared only under the two-condition collision test of
/// `docs/design/sync-spec.md` §4.1. Clearing natural-key entries on this
/// predicate would discharge every one of them on sight and re-split exactly
/// the colliding pairs the pass exists to keep whole.
/// Decodes a stored `figures_json` for a one-time maintenance sweep, or null
/// when it cannot be decoded at all.
///
/// The sweeps that use this read raw rows and call the figure transformers
/// directly, so they never pass through `DanceRepository._buildDance` and
/// inherit none of its tolerance. With their marker still pending, an
/// undecodable row therefore aborted `ensureMigrated()` even after the load
/// path was made total — the sweep is on the other side of the call (#1347).
///
/// Both exception types are caught for the reason `decodeFigures` now
/// documents: it throws `ArgumentError` as well as `FormatException`, and
/// `[{"move":""}]` takes the second path.
List<Figure>? _decodeSweepFigures(String storedJson) {
  try {
    return decodeFigures(storedJson);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

String? _normaliseStoredColumn(String column, String raw) {
  if (!_shareableJsonColumns.contains(column)) {
    return normalizeShareableText(raw);
  }
  try {
    return normalizeShareableJsonText(raw);
  } on FormatException {
    return null;
  } on ShareableJsonKeyCollision {
    return null;
  } on JsonUnsupportedObjectError {
    return null;
  }
}

/// The canonical form of a `shareable` settings value, or **null when the
/// stored value cannot be canonicalized at all**.
///
/// The settings half of the pass has its own predicate because it fails for its
/// own reasons: the decode, the normalize AND the re-encode can each throw, and
/// §4.1's totality is a property of the whole round trip rather than of the
/// collision test alone. `jsonDecode` throws [FormatException] on malformed
/// text; [normalizeShareableJson] throws [ShareableJsonKeyCollision] when two
/// object keys normalize to one key, which would silently discard whichever
/// entry the rebuild wrote second; and `jsonEncode` throws
/// [JsonUnsupportedObjectError] on a value `jsonDecode` itself produced
/// (`1e999` is legal JSON that decodes to `double.infinity` and cannot be
/// re-encoded).
///
/// Extracted so the initial scan and the bounded retry cannot drift apart: they
/// have to agree on what "this value is writable now" means, because one
/// records the entry and the other clears it.
String? _normaliseSettingsValue(String raw) {
  try {
    return jsonEncode(normalizeShareableJson(jsonDecode(raw)));
  } on FormatException {
    return null;
  } on ShareableJsonKeyCollision {
    return null;
  } on JsonUnsupportedObjectError {
    return null;
  }
}

Future<void> _retireMissingNormalisationSkips(CompendiumDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT table_name, column_name, record_id FROM normalisation_skips',
      )
      .get();
  for (final row in rows) {
    final table = row.read<String>('table_name');
    final id = row.read<String>('record_id');
    final keyColumn = table == 'settings' ? 'key' : 'id';
    final present = await db
        .customSelect(
          'SELECT 1 FROM $table WHERE $keyColumn = ? LIMIT 1',
          variables: [Variable<String>(id)],
        )
        .get();
    if (present.isEmpty) {
      await db.customStatement(
        'DELETE FROM normalisation_skips WHERE table_name = ? '
        'AND column_name = ? AND record_id = ?',
        [table, row.read<String>('column_name'), id],
      );
    }
  }
}

/// Bundles every repository over a single [CompendiumDatabase], so app code
/// wires up storage once (`CompendiumRepositories(db, taxonomy)`) instead of
/// constructing each repository individually.
class CompendiumRepositories {
  /// [settings], [dances], and [venues] exist as **test seams**, and only as that: each
  /// defaults to the real repository, so no production call site passes either.
  ///
  /// A test that needs to count how many times a screen re-read its data
  /// substitutes a counting subclass here. The alternative — matching SQL text
  /// in a `QueryInterceptor` — can report zero for two different reasons, "it
  /// never ran" and "the query no longer looks like that", and a count that
  /// silently becomes zero turns a ceiling assertion into an assertion about
  /// nothing. A subclass is checked by the compiler instead: rename or
  /// re-signature the method it overrides and the test fails to build.
  CompendiumRepositories(
    this.db,
    Taxonomy taxonomy, {
    SettingsRepository? settings,
    DanceRepository? dances,
    CollectionImportEventRepository? collectionImports,
    ProgramRepository? programs,
    VenueRepository? venues,
  }) : dances = dances ?? DanceRepository(db, taxonomy),
       choreographers = ChoreographerRepository(db),
       tags = TagRepository(db),
       difficultyLevels = DifficultyLevelRepository(db),
       customFieldDefs = CustomFieldDefRepository(db),
       programs = programs ?? ProgramRepository(db),
       publishedSources = PublishedSourceRepository(db),
       venues = venues ?? VenueRepository(db),
       collectionImports =
           collectionImports ?? CollectionImportEventRepository(db),
       settings = settings ?? SettingsRepository(db),
       syncLocal = SyncLocalRepository(db);

  final CompendiumDatabase db;
  final DanceRepository dances;
  final ChoreographerRepository choreographers;
  final TagRepository tags;
  final DifficultyLevelRepository difficultyLevels;
  final CustomFieldDefRepository customFieldDefs;
  final ProgramRepository programs;
  final PublishedSourceRepository publishedSources;
  final VenueRepository venues;
  final CollectionImportEventRepository collectionImports;
  final SettingsRepository settings;
  final SyncLocalRepository syncLocal;

  /// Runs a cross-repository write as one database transaction.
  ///
  /// Repository methods may open nested transactions, but the outer boundary
  /// keeps related records such as staged tags and their owning dances atomic.
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool resetMigrationOnFailure = false,
  }) async {
    try {
      return await db.transaction(action);
    } catch (_) {
      if (resetMigrationOnFailure) _migration = null;
      rethrow;
    }
  }

  /// Clears normalization bookkeeping before a restore or archive import.
  ///
  /// The next [ensureMigrated] must inspect every persisted shareable value
  /// written by the operation rather than trusting a marker or skip row from
  /// the previous dataset.
  Future<void> resetNormalisationStateForRestore() async {
    await db.transaction(() async {
      await db.customUpdate(
        'DELETE FROM normalisation_skips',
        updates: {db.normalisationSkips},
        updateKind: UpdateKind.delete,
      );
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable.withString(shareableTextNormalisationScopeKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    });
    _migration = null;
  }

  /// The scope is derived from the live Drift schema and privacy registry, so
  /// adding a shareable text column cannot be missed by the repair sweep.
  List<(String, String)> get _normalisationColumns {
    final columns = <(String, String)>[];
    for (final table in db.allTables) {
      final primaryKeys = table.$primaryKey
          .map((column) => column.name)
          .toSet();
      for (final column in table.$columns) {
        final classification =
            fieldClassifications['${table.actualTableName}.${column.name}'];
        if (column.type != DriftSqlType.string ||
            classification?.egress != EgressClass.shareable ||
            classification!.isIdentity ||
            primaryKeys.contains(column.name)) {
          continue;
        }
        columns.add((table.actualTableName, column.name));
      }
    }
    columns.sort((a, b) {
      final table = a.$1.compareTo(b.$1);
      return table == 0 ? a.$2.compareTo(b.$2) : table;
    });
    return columns;
  }

  /// Derived from [naturalKeyNormalisationColumns] rather than re-typed, so the
  /// pass's grouping set and the four write-path carve-outs are the same
  /// objects. §4.1 requires exactly this: two writers that spell one column
  /// differently stop correlating with no error raised anywhere (#1348).
  static final _naturalKeys = <(String, String)>[
    for (final column in naturalKeyNormalisationColumns)
      (column.table, column.column),
  ];

  /// Emits once whenever anything the Collection's reference/vocabulary data is
  /// built from changes — the trigger for re-reading a `CollectionData`
  /// snapshot (issue #768).
  ///
  /// A **change signal**, not the data: it carries no payload, because the
  /// snapshot is assembled app-side from a fan-out of queries across seven
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
  ///   from it (forms, formations, progressions, statuses, and the
  ///   mixed-level / mixer / rating flags).
  /// * `choreographers` — author names, and the author facet.
  /// * `tags` — tag names and colours, and the tag facet.
  /// * `difficulty_levels` — the configurable difficulty vocabulary.
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
  /// wider set, not a narrower one, but one chosen per consumer.
  ///
  /// That was written with one axis of disagreement in view, and predicted that
  /// a second would argue for a set built from the caller's needs rather than a
  /// boolean bolted onto a shared one. **A second has since appeared**, over
  /// `programs`/`program_slots`, and it was resolved the predicted way — see
  /// [watchDanceSources], which is a sibling with its own set rather than a
  /// third flag here. `includeVenues` stays a parameter because the venue axis
  /// splits consumers of *this* set; the program axis splits the set itself.
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
          db.difficultyLevels,
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

  /// Emits once whenever anything a **single dance's own record** is built from
  /// changes — the trigger for re-reading a hydrated dance (issue #768).
  ///
  /// Also reused verbatim by `DanceEditorReferenceData` (the app's dance
  /// editor screen, PR 9 of #768): it shares this stream rather than
  /// declaring a second sentinel with identical SQL (which would only add a
  /// `StreamKey` collision surface, per the marker note below, for no
  /// additional coverage). Its *streamed* reference-data set — choreographers,
  /// tags, dances, published sources — is a strict subset of this method's
  /// declared set: `custom_field_defs` is also here (the editor still wakes on
  /// a custom-field-def write) but the editor treats field defs as
  /// draft-adjacent state, loaded once alongside the dance itself rather than
  /// re-read from this stream (see that class's doc for why).
  ///
  /// A change signal, not the data, for the same reason as
  /// [watchCollectionSources]: the read it stands in for is a fan-out across
  /// several repositories with no single row set to hand back.
  ///
  /// ## Why this is a sibling and not `watchCollectionSources`
  ///
  /// It is that set **minus `programs` and `program_slots`**, and the
  /// subtraction is the whole point. A dance's own record is not program-derived
  /// — call tallies and calling history are — so a consumer that renders only
  /// the record has nothing to re-read when a slot is added, marked performed,
  /// or reordered.
  ///
  /// Reusing the wider set would therefore re-run this fan-out on every
  /// program-side write for a consumer that renders none of it. Where such a
  /// consumer *also* shows program-derived data, it does so through a second
  /// stream scoped to that data — so the wider set would cost a full reload on
  /// top of that stream's own emit: one write, two rebuilds, which is issue
  /// #340's over-firing arriving as a side effect of fixing staleness.
  ///
  /// ## The declared table set, justified per entry
  ///
  /// * `dances` — the row itself, and every other dance's title, for resolving
  ///   related-dance links and cross-reference candidates.
  /// * `choreographers` — resolved author names.
  /// * `tags` — tag names and colours.
  /// * `difficulty_levels` — the selected difficulty label.
  /// * `custom_field_defs` — the labels custom-field values are displayed under.
  /// * `published_sources` — the cited sources a record expands its citations
  ///   into.
  ///
  /// `venues` is absent because a dance record carries no venue. `dance_figures`
  /// is absent because figures are decoded from the `figures_json` column on
  /// `dances` and their sections are derived in memory, so nothing reads that
  /// table on this path.
  ///
  /// ## The child tables are omitted, and the invariant is the reason
  ///
  /// Hydrating one dance also reads `dance_authors`, `dance_tags`,
  /// `dance_links`, `dance_sources`, `custom_field_values` and `provenance`.
  /// None is named here, on the same rule [watchCollectionSources] states and
  /// for a set re-derived rather than inherited: **every path that writes one of
  /// them also writes, in the same transaction, at least one table above.**
  /// drift dispatches a transaction's updates as one set on commit, so naming
  /// them would add emits without adding coverage.
  ///
  /// Four of the six are the ones that method already enumerates. The other two
  /// were checked from scratch, because a conclusion about a different set is
  /// not evidence about these:
  ///
  /// * `provenance` — written only by the dance upsert, the archive restore's
  ///   clear-all, and FK cascade from a `dances` delete; all three write
  ///   `dances`. No natural-key adoption path touches it.
  /// * `dance_links` — same three, plus the dangling-reference cleanup, which
  ///   runs inside `purgeDeleted`/`hardDelete` and so also writes `dances`.
  ///
  /// `dance_links` has one writer that genuinely breaks the invariant: the
  /// purge-corruption repair below writes `dance_links`, `program_slots` and
  /// `settings`, and **none of those is in the set above**. It is safe for a
  /// different reason, and the difference is worth keeping rather than
  /// flattening into "it's covered" — it is reachable only from
  /// [ensureMigrated], which the app awaits before it builds a widget, so no
  /// subscriber can exist while it runs. That is app-level ordering, not a
  /// property of this file: **exposing any sweep as a user-triggered button, or
  /// moving one after the first frame, makes `dance_links` a required entry
  /// here.**
  ///
  /// ## The SQL marker is load-bearing
  ///
  /// The marker below differs from [watchCollectionSources]'s, and must. drift
  /// keys its stream cache on `(sql, variables)` and ignores `readsFrom`, so two
  /// sentinels sharing `SELECT 1` are one stream and the second subscriber
  /// silently inherits the first's set — non-deterministically, since which one
  /// wins depends on which subscribed first. That is the full account on
  /// [watchCollectionSources]; the guard is `per_consumer_read_sets_test.dart`,
  /// which asserts the behaviour rather than the marker text.
  Stream<void> watchDanceSources() => db
      .customSelect(
        '/* dance sources */ SELECT 1',
        readsFrom: {
          db.dances,
          db.choreographers,
          db.tags,
          db.difficultyLevels,
          db.customFieldDefs,
          db.publishedSources,
        },
      )
      .watch()
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
      rebuiltThisCall = await _emitGripAndSingleFileIntoCanonicalIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall =
          await _emitPromenadeTurnAndCircleWordingIntoCanonicalIfNeeded(
            alreadyRebuilt: rebuiltThisCall,
            onProgress: onDerivedRebuildProgress,
          );
      rebuiltThisCall = await _emitCompactDosidoSeesawCanonicalTextIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _emitTaxonomyV33CanonicalTextIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _emitTaxonomyV34CanonicalTextIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _normaliseTaxonomyV35FiguresIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _emitModifierContainerCanonicalTextIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _backfillChainHandIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _repairCallersBoxRollAwayIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      // Read BEFORE the pass, which writes this marker itself: its presence is
      // what distinguishes an install that completed the pass under the
      // dance-only rebuild condition — and may therefore be carrying an index
      // the pass left stale — from a database that never ran it at all.
      final normalisationCompletedBefore = await db
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
            variables: [
              Variable.withString(shareableTextNormalisationScopeKey),
            ],
          )
          .get();
      rebuiltThisCall = await _normaliseShareableTextIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        onProgress: onDerivedRebuildProgress,
      );
      rebuiltThisCall = await _repairNormalisationDerivedIndexIfNeeded(
        alreadyRebuilt: rebuiltThisCall,
        owedFromHistory: normalisationCompletedBefore.isNotEmpty,
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

  /// The fingerprint of the whole in-scope set a completed scan covered.
  ///
  /// `docs/design/sync-spec.md` §4.1 (`:676`–`:679`): the marker MUST record
  /// "its columns *and* the `shareable` settings classifications, exact keys
  /// and prefixes alike", and the pass MUST re-run whenever the live set
  /// differs. The settings half is not decorative (#1346 finding 2):
  /// `settings.value_json` is `deviceLocal` at the column level *by design*, so
  /// no settings entry can ever reach the column half — while the scan's
  /// settings half (below) walks live keys through [classifySettingsKey]. A
  /// column-only marker therefore fingerprints less than the scan covers, and
  /// reclassifying a key to `shareable` moves no column, trips no re-run, and
  /// leaves that key's already-written values un-normalized permanently.
  ///
  /// **Classifications, not live keys** (§4.1 `:699`–`:705`). A settings key
  /// may be built at runtime (`editor_draft:<id>`), so fingerprinting live keys
  /// would re-run the pass whenever a user opened an editor — and would be
  /// redundant, since a key that did not exist before is written through the
  /// normalizing path. Only a change to *which keys are classified* brings
  /// already-written values newly into scope.
  ///
  /// `settingsPrefixes` is empty today — no [settingsPrefixClassifications]
  /// entry is `shareable` — and is emitted anyway, because the fingerprint's
  /// job is to notice the day that stops being true.
  ///
  /// Compared by string equality, which is the inequality §4.1 `:740`–`:755`
  /// requires rather than containment: containment never contracts, so a
  /// column reclassified *out* of `shareable` and later back *in* would stay
  /// contained and re-run nothing, while during the interval its rows could
  /// accrue un-normalized text unrecorded.
  String get _normalisationScope {
    final settingsKeys =
        settingsClassifications.entries
            .where((entry) => entry.value.egress == EgressClass.shareable)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    final settingsPrefixes =
        settingsPrefixClassifications.entries
            .where((entry) => entry.value.egress == EgressClass.shareable)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    return jsonEncode({
      'version': _shareableTextNormalisationAlgorithmVersion,
      'columns': _normalisationColumns.map((c) => '${c.$1}.${c.$2}').toList(),
      'settings': settingsKeys,
      'settingsPrefixes': settingsPrefixes,
    });
  }

  /// Runs, retries, or skips the one-time shareable-text normalization pass.
  ///
  /// Returns whether a derived rebuild has happened during this call.
  ///
  /// ## Three outcomes, not two (#1346 finding 1)
  ///
  /// §4.1 (`:582`–`:586`) requires the pass to "re-attempt the recorded rows on
  /// each subsequent open, **clearing an entry once its row is written**", and
  /// states the bound that makes that affordable: "Re-attempting is bounded by
  /// the number of recorded rows rather than by the size of the library, so it
  /// is not a repeated full scan."
  ///
  /// Until this fix there were two outcomes — take the early return, or re-scan
  /// everything — and nothing ever cleared an entry, so one recorded row turned
  /// a one-time pass into a full-library scan on every launch, forever.
  /// Recording one is ordinary use: renaming a tag, choreographer or custom
  /// field to a name another row already holds takes the `collidingEdit` branch
  /// in the owning repository and records one, no Unicode subtlety required.
  ///
  /// So: marker matches and nothing is recorded → return, no scan. Marker
  /// matches and entries remain → retry **only** those rows. Marker differs or
  /// is absent → full scan, which now also discharges the entries it repairs.
  Future<bool> _normaliseShareableTextIfNeeded({
    required bool alreadyRebuilt,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    // Retired FIRST, not only at the end as before: an entry whose row was hard
    // deleted can never be re-attempted, and leaving it until after the work
    // means it forces the very scan it can contribute nothing to.
    await _retireMissingNormalisationSkips(db);

    final marker = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(shareableTextNormalisationScopeKey)],
        )
        .get();
    final skips = await db
        .customSelect(
          'SELECT table_name, column_name, record_id FROM normalisation_skips',
        )
        .get();
    final scope = _normalisationScope;
    final scopeUnchanged =
        marker.isNotEmpty && marker.single.read<String>('value_json') == scope;
    if (scopeUnchanged && skips.isEmpty) {
      return alreadyRebuilt;
    }

    final outcome = scopeUnchanged
        ? await _retryRecordedNormalisationSkips(skips)
        : await _runFullNormalisationScan();

    if (outcome) {
      await runDerivedRebuild(onProgress: onProgress);
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable<String>(derivedRebuildRequiredKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    // Still needed after a full scan: the scan cannot see a row that no longer
    // exists, so an entry for one is only reachable here.
    await _retireMissingNormalisationSkips(db);
    // Only a scan records completion. A retry runs *because* the recorded scope
    // already equals the live one, so re-writing it would store a byte-identical
    // string and wake every `settings` watcher for nothing — and
    // `docs/design/sync-implementation.md:509` states the rule the derived-flag
    // rules around it are shaped against: "retry never writes the completion
    // marker".
    if (!scopeUnchanged) {
      await _writeSweepMarker(shareableTextNormalisationScopeKey, scope);
    }
    return alreadyRebuilt || outcome;
  }

  /// Re-attempts **only** the rows recorded in `normalisation_skips`, clearing
  /// each entry whose row is written or already holds its target.
  ///
  /// This is §4.1's bounded retry (`:582`–`:586`, `:626`–`:657`). Cost is one
  /// row read per recorded entry plus, for a natural-key column, one indexed
  /// occupancy lookup per surviving candidate — neither scaling with the size
  /// of the library.
  ///
  /// ## Each flavour of entry gets its own test
  ///
  /// * **Natural-key collision** — §4.1 `:628`–`:634`: a recorded row is
  ///   written only when **both** hold — no *other recorded row* in the same
  ///   `(table, column)` currently derives the same target, **and** the live
  ///   unique column holds no occupant other than the row itself. Both are
  ///   load-bearing and each catches what the other misses (`:636`–`:657`):
  ///   testing occupancy alone splits a mutually-colliding pair, since neither
  ///   member occupies the target it derives, so whichever the walk reaches
  ///   first is written and the other blocked — and *which* one depends on an
  ///   order no rule fixes, so two devices could normalize opposite members of
  ///   the same pair. Testing recorded-row grouping alone raises against an
  ///   unrelated live row that took the target in the meantime.
  /// * **Un-normalizable JSON** (#1363) — writable exactly when
  ///   [_normaliseStoredColumn] stops returning null.
  /// * **Settings** — writable exactly when [_normaliseSettingsValue] stops
  ///   returning null. Sibling-row collisions cannot arise in this half; a
  ///   settings value is JSON in one column under no `UNIQUE` constraint.
  ///
  /// Targets and group membership are re-derived from live state on every
  /// attempt and never stored, which is why an entry holds only
  /// `(table, column, record_id)` (`:653`–`:657`).
  Future<bool> _retryRecordedNormalisationSkips(List<QueryRow> entries) async {
    final grouped = <(String, String), List<String>>{};
    for (final entry in entries) {
      grouped
          .putIfAbsent((
            entry.read<String>('table_name'),
            entry.read<String>('column_name'),
          ), () => <String>[])
          .add(entry.read<String>('record_id'));
    }
    final inScope = _normalisationColumns.toSet();

    var danceRewrite = false;
    var otherRewrite = false;
    var rebuild = false;
    await db.transaction(() async {
      for (final group in grouped.entries) {
        final (table, column) = group.key;
        final recordIds = group.value;

        if (table == settingsValueNormalisation.table &&
            column == settingsValueNormalisation.column) {
          for (final key in recordIds) {
            if (await _retryRecordedSettingsKey(key)) otherRewrite = true;
          }
          continue;
        }

        // An entry on a column that is no longer in scope — reclassified out of
        // `shareable` — can never become writable: the write path stops
        // normalizing that column, and the scan stops visiting it. Left in
        // place it would pin the early return open forever, which is this
        // finding's own defect in miniature. Dropping it loses nothing: the
        // marker-inequality rule above forces a full re-scan if the column ever
        // returns to scope, and that scan re-judges every one of its rows from
        // scratch.
        if (!inScope.contains((table, column))) {
          for (final recordId in recordIds) {
            await clearNormalisationSkip(
              db,
              table: table,
              column: column,
              recordId: recordId,
            );
          }
          continue;
        }

        final rewroteTable = _naturalKeys.contains((table, column))
            ? await _retryRecordedNaturalKeys(table, column, recordIds)
            : await _retryRecordedJsonRows(table, column, recordIds);
        if (rewroteTable) {
          if (table == 'dances') {
            danceRewrite = true;
          } else {
            otherRewrite = true;
          }
        }
      }

      rebuild = _resolveRebuildDecision(
        danceRewrite: danceRewrite,
        otherRewrite: otherRewrite,
      );
      if (rebuild) await _writeSweepMarker(derivedRebuildRequiredKey, 'true');
    });
    return rebuild;
  }

  /// Decides whether this pass's rewrites owe a rebuild now, or one that must
  /// wait.
  ///
  /// §4.1 `:1007`: "The pass MUST rebuild derived indexes if it wrote
  /// anything", and `:1012`–`:1014`: a pass that wrote nothing — including a
  /// retry in which every recorded row is still blocked — "MUST NOT rebuild
  /// them". Narrowing to the columns that actually feed an index is a **MAY**
  /// (`:1017`–`:1019`), available only against a declared column→index mapping
  /// proven by test; no such mapping exists here, so this takes the
  /// conservative default the spec says is "always available and always
  /// correct".
  ///
  /// That default is what fixes #1346 finding 3. The flag used to be set only
  /// by `if (table == 'dances')`, but a dance's index row is assembled from
  /// three *other* tables — `authors` from `choreographers.name`, `sources`
  /// from `published_sources.title`/`.author`, `custom_values` from
  /// `custom_field_values.value_text` — all four of them `shareable` strings
  /// and so in this pass's scope. Repairing any of them rewrote the source of
  /// an index row, set no flag, ran no rebuild, and wrote the completion marker
  /// anyway.
  ///
  /// A `settings` rewrite counts too. A settings value feeds no index, so this
  /// is strictly conservative — but "wrote anything" is the rule as stated, and
  /// the exemption is the same MAY that would need the same tested mapping.
  /// Whether the pass owes a derived rebuild.
  ///
  /// #1346 gated the triggers it added on whether the library held a `dances`
  /// normalisation skip, because a rebuild that met a row it could not read
  /// raised out of `ensureMigrated()`. #1347 removed that hazard at its source —
  /// `DanceRepository` now loads such a row as `UnreadableFigures` instead of
  /// raising — so there is nothing left to defer and no condition to gate on.
  bool _resolveRebuildDecision({
    required bool danceRewrite,
    required bool otherRewrite,
  }) => danceRewrite || otherRewrite;

  /// Re-attempts the recorded rows of one natural-key `(table, column)`.
  /// Returns whether any row was rewritten.
  Future<bool> _retryRecordedNaturalKeys(
    String table,
    String column,
    List<String> recordIds,
  ) async {
    var rewrote = false;
    // Live value, live target, re-derived per attempt.
    final candidates = <String, (int rowId, String raw, String target)>{};
    for (final recordId in recordIds) {
      final rows = await db
          .customSelect(
            'SELECT rowid AS _rowid, $column FROM $table '
            'WHERE id = ? AND $column IS NOT NULL LIMIT 1',
            variables: [Variable<String>(recordId)],
          )
          .get();
      if (rows.isEmpty) {
        // The row is gone, or its value is now NULL. Either way there is
        // nothing left to re-attempt.
        await clearNormalisationSkip(
          db,
          table: table,
          column: column,
          recordId: recordId,
        );
        continue;
      }
      final raw = rows.single.read<String>(column);
      final target = _normaliseStoredColumn(column, raw);
      // Unreachable while no natural-key column is a JSON column, and left
      // recorded rather than asserted away: if one ever became both, an
      // un-normalizable value must stay recorded, not be silently written.
      if (target == null) continue;
      candidates[recordId] = (rows.single.read<int>('_rowid'), raw, target);
    }

    // Condition (a): no OTHER recorded row in this (table, column) derives the
    // same target.
    final byTarget = <String, List<String>>{};
    for (final candidate in candidates.entries) {
      byTarget.putIfAbsent(candidate.value.$3, () => []).add(candidate.key);
    }
    for (final group in byTarget.entries) {
      if (group.value.length > 1) continue;
      final recordId = group.value.single;
      final (rowId, raw, target) = candidates[recordId]!;
      // Condition (b): the live unique column holds no occupant but this row.
      final occupied = await db
          .customSelect(
            'SELECT rowid FROM $table WHERE $column = ? AND rowid != ? LIMIT 1',
            variables: [Variable<String>(target), Variable<int>(rowId)],
          )
          .get();
      if (occupied.isNotEmpty) continue;
      if (raw != target) {
        // normalization-structure-exempt: this is the normalization backfill
        // itself, writing the value returned by the canonicalizer.
        await db.customUpdate(
          'UPDATE $table SET $column = ? WHERE rowid = ?',
          variables: [Variable<String>(target), Variable<int>(rowId)],
          updates: _updatesForTable(table),
          updateKind: UpdateKind.update,
        );
        rewrote = true;
      }
      // Cleared whether or not a write was needed: §4.1's condition is that the
      // row holds its target, and a row that already did was simply recorded
      // alongside a colliding sibling that has since moved.
      await clearNormalisationSkip(
        db,
        table: table,
        column: column,
        recordId: recordId,
      );
    }
    return rewrote;
  }

  /// Re-attempts the recorded rows of one JSON `(table, column)` (#1363's
  /// flavour of skip). Returns whether any row was rewritten.
  Future<bool> _retryRecordedJsonRows(
    String table,
    String column,
    List<String> recordIds,
  ) async {
    var rewrote = false;
    for (final recordId in recordIds) {
      final rows = await db
          .customSelect(
            'SELECT rowid AS _rowid, $column FROM $table '
            'WHERE id = ? AND $column IS NOT NULL LIMIT 1',
            variables: [Variable<String>(recordId)],
          )
          .get();
      if (rows.isEmpty) {
        await clearNormalisationSkip(
          db,
          table: table,
          column: column,
          recordId: recordId,
        );
        continue;
      }
      final raw = rows.single.read<String>(column);
      final target = _normaliseStoredColumn(column, raw);
      // Still un-normalizable: stays recorded, and stays retried.
      if (target == null) continue;
      if (target != raw) {
        // normalization-structure-exempt: this is the normalization backfill
        // itself, writing the value returned by the canonicalizer.
        await db.customUpdate(
          'UPDATE $table SET $column = ? WHERE rowid = ?',
          variables: [
            Variable<String>(target),
            Variable<int>(rows.single.read<int>('_rowid')),
          ],
          updates: _updatesForTable(table),
          updateKind: UpdateKind.update,
        );
        rewrote = true;
      }
      await clearNormalisationSkip(
        db,
        table: table,
        column: column,
        recordId: recordId,
      );
    }
    return rewrote;
  }

  /// Re-attempts one recorded settings key. Returns whether it was rewritten.
  Future<bool> _retryRecordedSettingsKey(String key) async {
    Future<void> clear() =>
        clearNormalisationSkipAt(db, settingsValueNormalisation, recordId: key);

    // A key reclassified out of `shareable` is out of the pass's scope, on the
    // same reasoning as an out-of-scope column above: the scan would no longer
    // judge it, so its entry can never be discharged by one.
    if (classifySettingsKey(key)?.egress != EgressClass.shareable) {
      await clear();
      return false;
    }
    // Read through drift's typed API rather than as raw SQL, and the reason is
    // the **tombstone**, not the typing. `tools/ci/check_settings_marker_reads`
    // requires every raw `SELECT … FROM settings WHERE key` to carry
    // `AND deleted_at IS NULL`, so that a tombstoned *marker* can never be read
    // back as still set. This is not a marker read: it re-attempts a recorded
    // user settings value, and the scan half whose work it continues walks
    // `SELECT key, value_json FROM settings` unfiltered — so it judges
    // tombstoned rows too, deliberately, because a tombstone still carries a
    // value (`backfill repairs tombstoned shareable settings`). Adding the
    // filter here would make the retry disagree with the scan about the same
    // row. Satisfying the gate by typing rather than by filtering keeps the two
    // halves reading the same set; it is stated here rather than left to be
    // inferred, because a reader who finds the gate first will otherwise read
    // this as an evasion of it.
    final row = await (db.select(
      db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) {
      await clear();
      return false;
    }
    final raw = row.valueJson;
    final encoded = _normaliseSettingsValue(raw);
    // The keys still collide (or the value still cannot round-trip): leave it
    // recorded. Retry succeeds when the user renames or deletes one of the
    // colliding keys, the same shape as the row half's occupancy test.
    if (encoded == null) return false;
    var rewrote = false;
    if (encoded != raw) {
      await db.customUpdate(
        'UPDATE settings SET value_json = ? WHERE key = ?',
        variables: [Variable<String>(encoded), Variable<String>(key)],
        updates: {db.settings},
        updateKind: UpdateKind.update,
      );
      rewrote = true;
    }
    await clear();
    return rewrote;
  }

  /// The full scan over every in-scope column and every `shareable` settings
  /// row, run when the recorded scope differs from the live one.
  Future<bool> _runFullNormalisationScan() async {
    var danceRewrite = false;
    var otherRewrite = false;
    var rebuild = false;
    void markRewrite(String table) {
      if (table == 'dances') {
        danceRewrite = true;
      } else {
        otherRewrite = true;
      }
    }

    await db.transaction(() async {
      for (final (table, column) in _normalisationColumns) {
        final natural = _naturalKeys.contains((table, column));
        // The record id is selected for the natural-key columns, which group on
        // it, and for the JSON columns, whose rows can be skipped as
        // un-normalisable. It is deliberately NOT selected for every table in
        // scope: nothing here establishes that they all have an `id` column, and
        // a blanket select would break the pass for one that does not.
        final keyed = natural || _shareableJsonColumns.contains(column);
        final rows = await db
            .customSelect(
              'SELECT rowid AS _rowid${keyed ? ', id AS _record_id' : ''}, '
              '$column FROM $table '
              'WHERE $column IS NOT NULL',
            )
            .get();
        final targets = <String, List<(int, String, String)>>{};
        for (final row in rows) {
          final raw = row.read<String>(column);
          final target = _normaliseStoredColumn(column, raw);
          if (target == null) {
            // The value cannot be canonicalized at all. Leave the row exactly as
            // stored and record its address, the same guard-record-continue
            // shape the settings half below uses for an in-value key collision.
            // Only a JSON column can return null and `keyed` is true for every
            // one of those, so `_record_id` is in the select above. Nothing is
            // written for this row, so no derived rebuild is owed for it.
            await recordNormalisationSkip(
              db,
              table: table,
              column: column,
              recordId: row.read<String>('_record_id'),
            );
            continue;
          }
          if (natural) {
            targets.putIfAbsent(target, () => []).add((
              row.read<int>('_rowid'),
              row.read<String>('_record_id'),
              target,
            ));
            continue;
          }
          if (target != raw) {
            // normalization-structure-exempt: this is the normalization
            // backfill itself, writing the value returned by the canonicalizer.
            await db.customUpdate(
              'UPDATE $table SET $column = ? WHERE rowid = ?',
              variables: [
                Variable<String>(target),
                Variable<int>(row.read<int>('_rowid')),
              ],
              updates: _updatesForTable(table),
              updateKind: UpdateKind.update,
            );
            markRewrite(table);
          }
          // The row holds its target now, so an entry recorded for it by an
          // earlier pass is discharged — whether this scan wrote it or found it
          // already equal. Guarded on [keyed] because that is exactly the set of
          // columns for which `_record_id` was selected, and equally exactly the
          // set for which an entry can exist: only a JSON column can fail to
          // canonicalize, and a non-natural, non-JSON column is never recorded.
          if (keyed) {
            await clearNormalisationSkip(
              db,
              table: table,
              column: column,
              recordId: row.read<String>('_record_id'),
            );
          }
        }
        if (!natural) continue;
        for (final entry in targets.entries) {
          final group = entry.value;
          if (group.length > 1) {
            for (final (_, recordId, _) in group) {
              await recordNormalisationSkip(
                db,
                table: table,
                column: column,
                recordId: recordId,
              );
            }
            continue;
          }
          final rowId = group.single.$1;
          final target = group.single.$3;
          final occupied = await db
              .customSelect(
                'SELECT rowid FROM $table WHERE $column = ? AND rowid != ? LIMIT 1',
                variables: [Variable<String>(target), Variable<int>(rowId)],
              )
              .get();
          if (occupied.isNotEmpty) {
            await recordNormalisationSkip(
              db,
              table: table,
              column: column,
              recordId: rows
                  .firstWhere((r) => r.read<int>('_rowid') == rowId)
                  .read<String>('_record_id'),
            );
          } else {
            final row = rows.firstWhere((r) => r.read<int>('_rowid') == rowId);
            final raw = row.read<String>(column);
            if (raw != target) {
              // normalization-structure-exempt: this is the normalization
              // backfill itself, writing the value returned by the canonicalizer.
              await db.customUpdate(
                'UPDATE $table SET $column = ? WHERE rowid = ?',
                variables: [Variable<String>(target), Variable<int>(rowId)],
                updates: _updatesForTable(table),
                updateKind: UpdateKind.update,
              );
              markRewrite(table);
            }
            // Singleton group whose target is unoccupied: the row holds its
            // target, so any entry recorded for it — by an earlier pass, or by
            // the write-path carve-out when the user made a colliding edit that
            // has since been resolved — is discharged.
            await clearNormalisationSkip(
              db,
              table: table,
              column: column,
              recordId: row.read<String>('_record_id'),
            );
          }
        }
      }

      for (final row
          in await db
              .customSelect('SELECT key, value_json FROM settings')
              .get()) {
        final key = row.read<String>('key');
        final classification = classifySettingsKey(key);
        if (classification?.egress != EgressClass.shareable) continue;
        final raw = row.read<String>('value_json');
        // The decode, the normalize AND the re-encode all sit behind one
        // predicate ([_normaliseSettingsValue]): each can fail, and §4.1's
        // totality is a property of the whole round trip, not of the collision
        // test alone. Leaving any of them outside it left this half raising on a
        // stored value's content, the same defect as #1347's JSON columns.
        final encoded = _normaliseSettingsValue(raw);
        if (encoded == null) {
          await recordNormalisationSkipAt(
            db,
            settingsValueNormalisation,
            recordId: key,
          );
          continue;
        }
        if (encoded != raw) {
          await db.customUpdate(
            'UPDATE settings SET value_json = ? WHERE key = ?',
            variables: [Variable<String>(encoded), Variable<String>(key)],
            updates: {db.settings},
            updateKind: UpdateKind.update,
          );
          markRewrite('settings');
        }
        await clearNormalisationSkipAt(
          db,
          settingsValueNormalisation,
          recordId: key,
        );
      }

      rebuild = _resolveRebuildDecision(
        danceRewrite: danceRewrite,
        otherRewrite: otherRewrite,
      );
      if (rebuild) {
        // Committed in the SAME transaction as the rewrites above: if the
        // process dies before the rebuild completes, this durable flag survives
        // and forces the owed rebuild on the next open, even though a re-run's
        // own rescan would find nothing left to rewrite.
        await _writeSweepMarker(derivedRebuildRequiredKey, 'true');
      }
    });
    return rebuild;
  }

  /// One-time repair of the derived indexes the normalization pass left stale
  /// while its rebuild condition was `if (table == 'dances')` (#1346 finding
  /// 3).
  ///
  /// Guarded by [normalisationDerivedIndexRepairDoneKey] so it runs at most once
  /// per database. The marker is written AFTER the rebuild succeeds — an
  /// interrupted rebuild retries on the next open.
  ///
  /// [owedFromHistory] is whether the normalization pass had already completed
  /// **before this migration ran** — the only thing that can have left an index
  /// stale under the old dance-only condition. It is false for a database with
  /// no pre-fix pass to have missed, in which case this writes its marker and
  /// rebuilds nothing, so a fresh install never pays a whole-library rebuild for
  /// an index that was never stale.
  ///
  /// **Why a forced rebuild at all, rather than a version bump.** Bumping
  /// [_shareableTextNormalisationAlgorithmVersion] re-runs the pass, which finds
  /// every row already normalized, rewrites nothing, sets no flag and repairs no
  /// index — the rewrite is what the old condition missed, and it has already
  /// happened. Leaving the rows to heal on the next edit of each dance leaves an
  /// unknown number of dances unfindable by author or source text indefinitely,
  /// which §4.1 (`:1028`–`:1031`) calls the costlier of the two errors.
  ///
  /// Returns whether a derived rebuild has happened during this call — i.e.
  /// [alreadyRebuilt] OR this sweep ran one — so the caller can thread the flag.
  Future<bool> _repairNormalisationDerivedIndexIfNeeded({
    required bool alreadyRebuilt,
    required bool owedFromHistory,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [
            Variable.withString(normalisationDerivedIndexRepairDoneKey),
          ],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    // Retire immediately when nothing is owed, and the order still matters
    // even with no blocker left to consult.
    //
    // This database either never completed the pass under the old dance-only
    // condition, or has already been repaired. Leaving the marker absent here
    // would let the pass go on to write the scope marker — and on the next open
    // that scope marker is exactly what [owedFromHistory] reads, so the sweep
    // would wake up believing it owed a repair it had never owed and eventually
    // pay a whole-library rebuild for it. A fresh database with one
    // un-normalisable dance row was enough to trigger that.
    if (!owedFromHistory) {
      await _writeSweepMarker(normalisationDerivedIndexRepairDoneKey, '"done"');
      return alreadyRebuilt;
    }

    // A rebuild earlier in this call already used the current source rows: the
    // normalization pass runs before this sweep and rebuilds after its own
    // writes, so `alreadyRebuilt` here means the indexes are current and a
    // second whole-library pass would be byte-identical.
    if (!alreadyRebuilt) {
      // Durable before the rebuild, in the shape [_backfillChainHandIfNeeded]
      // uses: if the process dies mid-rebuild, the generic pre-check at the top
      // of [_runMigration] performs it on the next open even though this
      // sweep's own marker is still unwritten.
      await _writeSweepMarker(derivedRebuildRequiredKey, 'true');
      await runDerivedRebuild(onProgress: onProgress);
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable<String>(derivedRebuildRequiredKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    // Written AFTER success — if the rebuild throws, the marker is not written
    // and the next startup retries.
    await _writeSweepMarker(normalisationDerivedIndexRepairDoneKey, '"done"');
    return true;
  }

  Set<TableInfo<Table, dynamic>> _updatesForTable(String tableName) => {
    db.allTables.firstWhere((table) => table.actualTableName == tableName),
  };

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
        // normalization-structure-exempt: derived maintenance writes encoded
        // figures already produced from the canonical dance model.
        await db.customUpdate(
          // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
          'UPDATE ${db.dances.actualTableName} SET figures_json = ? '
          'WHERE id = ?',
          variables: [
            Variable<String>(switch (normalised.figuresSource) {
              DecodedFigures(:final figures) => encodeFigures(figures),
              // Unreachable today: the Dance->Dance transformer returns the
              // same instance for an undecodable row, so the `identical`
              // check short-circuits before this. A verbatim passthrough
              // rather than a throw, so that if a future transformer does
              // return one the bytes survive instead of startup dying.
              UnreadableFigures(:final storedJson) => storedJson,
            }),
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
  /// caller can thread the flag onward to later sweeps.
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
      // normalization-structure-exempt: derived maintenance writes encoded
      // figures already produced from the canonical dance model.
      await db.customUpdate(
        // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
        'UPDATE ${db.dances.actualTableName} SET figures_json = ? WHERE id = ?',
        variables: [
          Variable<String>(switch (stripped.figuresSource) {
            DecodedFigures(:final figures) => encodeFigures(figures),
            // Unreachable today: the Dance->Dance transformer returns the
            // same instance for an undecodable row, so the `identical`
            // check short-circuits before this. A verbatim passthrough
            // rather than a throw, so that if a future transformer does
            // return one the bytes survive instead of startup dying.
            UnreadableFigures(:final storedJson) => storedJson,
          }),
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

  /// One-time promenade/circle canonical-text rebuild owed by the v30
  /// taxonomy change (#989). See
  /// [promenadeTurnCircleWordingCanonicalRebuildDoneKey]'s doc comment for the
  /// full rationale (`circle.singleFile`'s widened parenthetical,
  /// `promenade.turn`'s concrete default, `promenade.destination`'s re-gate).
  ///
  /// Identical shape to [_emitGripAndSingleFileIntoCanonicalIfNeeded]: no
  /// `figures_json` rewrite, only the derived index changes, so this pass
  /// calls [runDerivedRebuild] and then writes its marker, with no preceding
  /// data sweep. The debt is owed by the taxonomy change, not by rewrite
  /// count — the same reasoning applies here as it did there.
  ///
  /// Guarded by [promenadeTurnCircleWordingCanonicalRebuildDoneKey] so it runs
  /// at most once per database. The marker is written AFTER the rebuild
  /// succeeds — an interrupted pass retries on the next open (crash-safe).
  ///
  /// Returns whether a derived rebuild has happened during this call —
  /// [alreadyRebuilt] OR this pass ran one — matching the other sweeps.
  Future<bool> _emitPromenadeTurnAndCircleWordingIntoCanonicalIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [
            Variable.withString(
              promenadeTurnCircleWordingCanonicalRebuildDoneKey,
            ),
          ],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);

    // Write the marker AFTER success — if the rebuild throws, the marker is
    // not written and the next startup retries.
    await _writeSweepMarker(
      promenadeTurnCircleWordingCanonicalRebuildDoneKey,
      '"done"',
    );
    // Reached only by running a rebuild (or having had one run earlier this
    // call), so a rebuild has always happened by this point.
    return true;
  }

  /// Rebuilds canonical/FTS text after taxonomy v32 renamed the default
  /// do-si-do and see-saw display names to their compact forms.
  Future<bool> _emitCompactDosidoSeesawCanonicalTextIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [
            Variable.withString(compactDosidoSeesawCanonicalRebuildDoneKey),
          ],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);
    await _writeSweepMarker(
      compactDosidoSeesawCanonicalRebuildDoneKey,
      '"done"',
    );
    return true;
  }

  /// Rebuilds canonical/FTS text after taxonomy v33 changed seeded defaults
  /// and the figure-eight canonical template. It also removes the old parser's
  /// explicit `partners` value from assumed bare `box_circulate` figures so the
  /// new taxonomy default can take effect without touching explicit subjects.
  Future<bool> _emitTaxonomyV33CanonicalTextIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(taxonomyV33CanonicalRebuildDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    final allDances = await dances.listAll(includeDeleted: true);
    for (final dance in allDances) {
      final normalised = dances.normaliseTaxonomyV33Public(dance);
      if (identical(normalised, dance)) continue;
      // Rewrite only figures_json; the bulk rebuild below refreshes all derived
      // rows after the source normalization completes.
      // normalization-structure-exempt: derived maintenance writes encoded
      // figures already produced from the canonical dance model.
      await db.customUpdate(
        // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
        'UPDATE ${db.dances.actualTableName} SET figures_json = ? WHERE id = ?',
        variables: [
          Variable<String>(switch (normalised.figuresSource) {
            DecodedFigures(:final figures) => encodeFigures(figures),
            // Unreachable today: the Dance->Dance transformer returns the
            // same instance for an undecodable row, so the `identical`
            // check short-circuits before this. A verbatim passthrough
            // rather than a throw, so that if a future transformer does
            // return one the bytes survive instead of startup dying.
            UnreadableFigures(:final storedJson) => storedJson,
          }),
          Variable<String>(dance.id),
        ],
        updates: {db.dances},
        updateKind: UpdateKind.update,
      );
    }

    if (!alreadyRebuilt) await runDerivedRebuild(onProgress: onProgress);
    await _writeSweepMarker(taxonomyV33CanonicalRebuildDoneKey, '"done"');
    return true;
  }

  /// Rebuilds canonical/FTS text after taxonomy v34 changed the mad robin
  /// default and normalizes legacy assumed TCB subjects.
  Future<bool> _emitTaxonomyV34CanonicalTextIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(taxonomyV34CanonicalRebuildDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    final allDances = await dances.listAll(includeDeleted: true);
    final rewrites = <(String, String)>[];
    for (final dance in allDances) {
      final normalised = dances.normaliseTaxonomyV34Public(dance);
      if (identical(normalised, dance)) continue;
      rewrites.add((
        dance.id,
        switch (normalised.figuresSource) {
          DecodedFigures(:final figures) => encodeFigures(figures),
          // Unreachable today: the Dance->Dance transformer returns the
          // same instance for an undecodable row, so the `identical`
          // check short-circuits before this. A verbatim passthrough
          // rather than a throw, so that if a future transformer does
          // return one the bytes survive instead of startup dying.
          UnreadableFigures(:final storedJson) => storedJson,
        },
      ));
    }

    final rebuildOwed = !alreadyRebuilt || rewrites.isNotEmpty;
    if (rewrites.isNotEmpty || rebuildOwed) {
      await db.transaction(() async {
        for (final (danceId, figuresJson) in rewrites) {
          // normalization-structure-exempt: derived maintenance writes encoded
          // figures already produced from the canonical dance model.
          await db.customUpdate(
            // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
            'UPDATE ${db.dances.actualTableName} SET figures_json = ? '
            'WHERE id = ?',
            variables: [
              Variable<String>(figuresJson),
              Variable<String>(danceId),
            ],
            updates: {db.dances},
            updateKind: UpdateKind.update,
          );
        }
        if (rebuildOwed) {
          await _writeSweepMarker(derivedRebuildRequiredKey, '"true"');
        }
      });
    }

    if (rebuildOwed) {
      await runDerivedRebuild(onProgress: onProgress);
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable<String>(derivedRebuildRequiredKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    await _writeSweepMarker(taxonomyV34CanonicalRebuildDoneKey, '"done"');
    return true;
  }

  /// Rewrites legacy v34 figure ids and parameter keys, including nested
  /// structural-container children, then rebuilds the derived figure/search
  /// indexes.
  Future<bool> _normaliseTaxonomyV35FiguresIfNeeded({
    required bool alreadyRebuilt,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final marker = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ? '
          'AND deleted_at IS NULL',
          variables: [
            Variable.withString(taxonomyV35FigureNormalizationDoneKey),
          ],
        )
        .get();
    final pending =
        marker.isEmpty || marker.first.read<String>('value_json') != 'true';
    if (!pending) return alreadyRebuilt;

    var rewroteAny = false;
    String? afterId;
    while (true) {
      final rows = afterId == null
          ? await db
                .customSelect(
                  'SELECT id, figures_json FROM ${db.dances.actualTableName} '
                  'ORDER BY id LIMIT ?',
                  variables: [Variable<int>(_taxonomyV35MigrationPageSize)],
                )
                .get()
          : await db
                .customSelect(
                  'SELECT id, figures_json FROM ${db.dances.actualTableName} '
                  'WHERE id > ? ORDER BY id LIMIT ?',
                  variables: [
                    Variable<String>(afterId),
                    Variable<int>(_taxonomyV35MigrationPageSize),
                  ],
                )
                .get();
      if (rows.isEmpty) break;
      afterId = rows.last.read<String>('id');

      final rewrites = <(String, String)>[];
      for (final row in rows) {
        final figures = _decodeSweepFigures(row.read<String>('figures_json'));
        // Skipped, not rewritten: the stored bytes stay exactly as they are.
        if (figures == null) continue;
        final normalized = dances.normaliseTaxonomyV35FiguresPublic(figures);
        if (!identical(normalized, figures)) {
          rewrites.add((row.read<String>('id'), encodeFigures(normalized)));
        }
      }
      if (rewrites.isEmpty) continue;

      rewroteAny = true;
      await db.transaction(() async {
        for (final (danceId, figuresJson) in rewrites) {
          // normalization-structure-exempt: maintenance writes encoded figures
          // produced by the canonical taxonomy normalizer.
          await db.customUpdate(
            // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
            'UPDATE ${db.dances.actualTableName} SET figures_json = ? '
            'WHERE id = ?',
            variables: [
              Variable<String>(figuresJson),
              Variable<String>(danceId),
            ],
            updates: {db.dances},
            updateKind: UpdateKind.update,
          );
        }
        // Keep the rebuild owed if the process stops between pages.
        await _writeSweepMarker(derivedRebuildRequiredKey, '"true"');
      });
    }

    final rebuildOwed = !alreadyRebuilt || rewroteAny;
    if (rebuildOwed && !rewroteAny) {
      await db.transaction(() async {
        await _writeSweepMarker(derivedRebuildRequiredKey, '"true"');
      });
    }

    if (rebuildOwed) {
      await runDerivedRebuild(onProgress: onProgress);
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable<String>(derivedRebuildRequiredKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    await _writeSweepMarker(taxonomyV35FigureNormalizationDoneKey, 'true');
    return alreadyRebuilt || rebuildOwed;
  }

  Future<bool> _emitModifierContainerCanonicalTextIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [
            Variable.withString(modifierContainerCanonicalRebuildDoneKey),
          ],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    if (!alreadyRebuilt) {
      await runDerivedRebuild(onProgress: onProgress);
    }
    await _writeSweepMarker(modifierContainerCanonicalRebuildDoneKey, '"done"');
    return true;
  }

  /// One-time backfill of `chain.hand` from the role-implied side (#976,
  /// taxonomy v28). See [chainHandBackfillDoneKey]'s doc comment for the full
  /// rationale; this pass mirrors
  /// [_normaliseInversePairMoveIdsIfNeeded]'s shape (rewrite-count-gated
  /// rebuild), not the taxonomy-version-owed shape of
  /// [_stripStarPromenadeHandIfNeeded] / [_emitGripAndSingleFileIntoCanonicalIfNeeded]:
  /// a chain's canonical text is byte-identical whether `hand` is the
  /// `unspecified` sentinel or the concrete role-implied side (the renderer
  /// silences either), so the derived index is stale only for the rows this
  /// pass actually rewrites.
  ///
  /// Guarded by [chainHandBackfillDoneKey] so it runs at most once per
  /// database. The marker is written AFTER the pass succeeds — an
  /// interrupted pass retries on the next open.
  ///
  /// **Crash safety across the rewrite/rebuild split:** the row rewrites
  /// below are idempotent (a dance already carrying the role-implied hand
  /// scans as unchanged), which is what makes a bare retry safe for the
  /// rewrites themselves — but NOT sufficient on its own for the rebuild
  /// that must follow them. If a first attempt commits every `figures_json`
  /// rewrite and is then interrupted before the derived rebuild below runs
  /// (or [runDerivedRebuild] throws), a naive retry would rescan, find every
  /// hand already backfilled, compute `rewroteAny = false`, skip the
  /// rebuild, and write the done marker anyway — permanently leaving
  /// `dance_figures`/`dance_fts` stale for the rows the first attempt
  /// rewrote. To close that gap, the rewrite loop and a durable
  /// [derivedRebuildRequiredKey] write are committed together in one
  /// transaction: either both land, or neither does. If the process dies
  /// anywhere after that transaction commits, [derivedRebuildRequiredKey] is
  /// still set, so the NEXT call's unconditional check at the top of
  /// [_runMigration] (which runs before this sweep) performs the owed
  /// rebuild regardless of what this sweep's own rescan finds.
  ///
  /// **Fresh install:** no chain figures exist yet, so the scan finds
  /// nothing to update and writes the marker immediately. The pass is a
  /// no-op.
  ///
  /// Returns whether a derived rebuild has happened during this call — i.e.
  /// [alreadyRebuilt] OR this pass ran one — so the caller can thread the flag
  /// into the next sweep.
  Future<bool> _backfillChainHandIfNeeded({
    bool alreadyRebuilt = false,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(chainHandBackfillDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    final allDances = await dances.listAll(includeDeleted: true);
    var rewroteAny = false;
    await db.transaction(() async {
      for (final dance in allDances) {
        final backfilled = dances.backfillChainHandPublic(dance);
        if (!identical(backfilled, dance)) {
          rewroteAny = true;
          // Rewrite only the figures_json column — nothing else about the
          // dance changes, and a full _upsert would needlessly rebuild
          // derived rows per dance (the bulk rebuild at the end is
          // cheaper).
          // normalization-structure-exempt: derived maintenance writes encoded
          // figures already produced from the canonical dance model.
          await db.customUpdate(
            // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
            'UPDATE ${db.dances.actualTableName} SET figures_json = ? '
            'WHERE id = ?',
            variables: [
              Variable<String>(switch (backfilled.figuresSource) {
                DecodedFigures(:final figures) => encodeFigures(figures),
                // Unreachable today: the Dance->Dance transformer returns the
                // same instance for an undecodable row, so the `identical`
                // check short-circuits before this. A verbatim passthrough
                // rather than a throw, so that if a future transformer does
                // return one the bytes survive instead of startup dying.
                UnreadableFigures(:final storedJson) => storedJson,
              }),
              Variable<String>(dance.id),
            ],
            updates: {db.dances},
            updateKind: UpdateKind.update,
          );
        }
      }
      if (rewroteAny) {
        // Committed in the SAME transaction as the rewrites above (see the
        // crash-safety note): if the process dies before the rebuild below
        // completes, this durable flag survives and forces the owed rebuild
        // on the next open, even though a retry's own rescan would find
        // nothing left to rewrite.
        await _writeSweepMarker(derivedRebuildRequiredKey, 'true');
      }
    });

    // A derived rebuild is needed whenever THIS pass rewrote a row —
    // regardless of whether an earlier sweep in the same call already
    // rebuilt, because that rebuild ran against the OLD figures_json, before
    // this pass's writes. Unlike the taxonomy-version-owed sweeps above,
    // "no rewrites" truly does mean "no staleness" here (a chain's canonical
    // text is unaffected either way, § above), so this is `rewroteAny` alone
    // — not `!alreadyRebuilt || rewroteAny` as in
    // [_normaliseInversePairMoveIdsIfNeeded], whose first disjunct exists for
    // a reason (a canonical-key change) that doesn't apply here.
    final rebuilt = rewroteAny;
    if (rebuilt) {
      await runDerivedRebuild(onProgress: onProgress);
      // The rebuild [derivedRebuildRequiredKey] guarded against has now
      // completed, so clear it — otherwise the next call's unconditional
      // top-of-[_runMigration] check would redo a rebuild that is no longer
      // owed.
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable<String>(derivedRebuildRequiredKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }

    // Write the marker AFTER success — if the rebuild throws, the marker is
    // not written and the next startup retries.
    await _writeSweepMarker(chainHandBackfillDoneKey, '"done"');
    return alreadyRebuilt || rebuilt;
  }

  /// Repairs legacy CallersBox `roll_away` figures whose per-role annotation
  /// was previously retained only as a note (#1192). The source provenance is
  /// part of the predicate because raw CallersBox payloads were removed in
  /// schema v21 and an identical figure may have been authored elsewhere.
  ///
  /// Row rewrites and the durable derived-rebuild marker are committed
  /// together. If the rebuild fails after that transaction, the next startup
  /// rebuilds from the already-repaired source rows before this sweep retries;
  /// this closes the gap where an idempotent rescan would otherwise find no
  /// rewrites and incorrectly skip the rebuild.
  Future<bool> _repairCallersBoxRollAwayIfNeeded({
    required bool alreadyRebuilt,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
          variables: [Variable.withString(callersBoxRollAwayRoleRepairDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return alreadyRebuilt;

    final legacyRows = await db
        .customSelect(
          'SELECT dances.id, dances.figures_json, provenance.source '
          'FROM dances LEFT JOIN provenance '
          'ON provenance.dance_id = dances.id',
          readsFrom: {db.dances, db.provenance},
        )
        .get();
    var rewroteAny = false;
    await db.transaction(() async {
      for (final row in legacyRows) {
        if (row.read<String?>('source') != ProvenanceSource.callersbox.name) {
          continue;
        }
        final figures = _decodeSweepFigures(row.read<String>('figures_json'));
        // Skipped, not rewritten: the stored bytes stay exactly as they are.
        if (figures == null) continue;
        final repaired = dances.repairLegacyCallersBoxRollAwayFiguresPublic(
          figures,
        );
        if (identical(repaired, figures)) continue;
        rewroteAny = true;
        // Rewrite only figures_json; the bulk rebuild below refreshes all
        // derived rows after every source rewrite has committed.
        // normalization-structure-exempt: derived maintenance writes encoded
        // figures already produced from the canonical dance model.
        await db.customUpdate(
          // sync-invariant-exclusion: maintenance-backfill is idempotent; not a sync record edit.
          'UPDATE ${db.dances.actualTableName} SET figures_json = ? '
          'WHERE id = ?',
          variables: [
            Variable<String>(encodeFigures(repaired)),
            Variable<String>(row.read<String>('id')),
          ],
          updates: {db.dances},
          updateKind: UpdateKind.update,
        );
      }
      if (rewroteAny) {
        await _writeSweepMarker(derivedRebuildRequiredKey, 'true');
      }
    });

    if (rewroteAny) {
      await runDerivedRebuild(onProgress: onProgress);
      await db.customUpdate(
        'DELETE FROM ${db.settings.actualTableName} WHERE key = ?',
        variables: [Variable<String>(derivedRebuildRequiredKey)],
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }

    await _writeSweepMarker(callersBoxRollAwayRoleRepairDoneKey, '"done"');
    return alreadyRebuilt || rewroteAny;
  }
}
