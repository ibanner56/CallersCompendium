import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart'
    show ResultSetImplementation, TableUpdateQuery;

import '../models/dance_list_entry.dart';
import 'coalesce_trailing.dart';

/// Reference/vocabulary data loaded once for the Collection, used both to build
/// facet controls and to hydrate search-result ids into [DanceListEntry]s
/// without re-querying per row.
///
/// Extracted from `dance_list_screen.dart` so the Programs builder's dance
/// picker ([CollectionPicker]) can reuse the exact same load + facet
/// vocabularies + `entryFor` hydration. Behaviour is identical to the previous
/// private `_CollectionData`.
class CollectionData {
  CollectionData({
    required this.dancesById,
    required this.choreographersById,
    required this.choreographerNames,
    required this.tagNames,
    this.tagColors = const {},
    required this.customFieldDefs,
    required this.listFieldDefs,
    required this.choiceFields,
    required this.booleanFields,
    required this.textFields,
    required this.numberFields,
    required this.lastCalled,
    required this.callCounts,
    this.callerFilter,
    required this.authors,
    required this.tags,
    required this.citedSources,
    required this.tunes,
    required this.forms,
    required this.formations,
    required this.progressions,
    required this.statuses,
    required this.levels,
    required this.hasMixedLevel,
    required this.hasMixer,
    required this.hasRating,
    required this.taxonomy,
    required this.sectionLabels,
  });

  /// A copy with the calling tallies replaced and **every other field carried
  /// over by reference**.
  ///
  /// This is the whole of the counts-only reload in [watch]: a write that only
  /// touched `programs`/`program_slots` cannot have changed the dances, the
  /// reference data or any facet vocabulary, so those are reused rather than
  /// re-read. The invariant is "a counts-only emit never changes [dancesById],
  /// the field definitions, [tags] or [citedSources]" — `identical`, not merely
  /// equal, which is also what makes `DanceListScreen`'s `mapEquals` over
  /// [dancesById] cheap for such an emit.
  ///
  /// Deliberately a constructor call listing every field rather than a patch:
  /// a field added to the constructor is a compile error here instead of a
  /// value silently reset to its default. The lazy `…ById` maps are rebuilt on
  /// demand by the new instance.
  CollectionData copyWithProgramCounts(ProgramDerivedCounts counts) =>
      CollectionData(
        dancesById: dancesById,
        choreographersById: choreographersById,
        choreographerNames: choreographerNames,
        tagNames: tagNames,
        tagColors: tagColors,
        customFieldDefs: customFieldDefs,
        listFieldDefs: listFieldDefs,
        choiceFields: choiceFields,
        booleanFields: booleanFields,
        textFields: textFields,
        numberFields: numberFields,
        lastCalled: counts.lastCalled,
        callCounts: counts.callCounts,
        callerFilter: callerFilter,
        authors: authors,
        tags: tags,
        citedSources: citedSources,
        tunes: tunes,
        forms: forms,
        formations: formations,
        progressions: progressions,
        statuses: statuses,
        levels: levels,
        hasMixedLevel: hasMixedLevel,
        hasMixer: hasMixer,
        hasRating: hasRating,
        taxonomy: taxonomy,
        sectionLabels: sectionLabels,
      );

  final Map<String, Dance> dancesById;

  late final Map<String, CustomFieldDef> _customFieldsById = {
    for (final d in customFieldDefs) d.id: d,
  };
  late final Map<String, Tag> _tagsById = {for (final t in tags) t.id: t};
  late final Map<String, PublishedSource> _sourcesById = {
    for (final s in citedSources) s.id: s,
  };

  /// Resolves a custom-field definition (private ones included) by id, for
  /// share paths that must know each field's `shareable` flag.
  CustomFieldDef? customFieldFor(String id) => _customFieldsById[id];

  /// Resolves a tag carried by a live dance, by id.
  Tag? tagFor(String id) => _tagsById[id];

  /// Resolves a published source cited by a dance, by id.
  PublishedSource? publishedSourceFor(String id) => _sourcesById[id];

  /// All choreographers keyed by id, so a share/export path can resolve a
  /// dance's `authorIds` to full [Choreographer] records (mirrors [dancesById]).
  final Map<String, Choreographer> choreographersById;
  final Map<String, String> choreographerNames;
  final Map<String, String> tagNames;

  /// The user's chosen chip colour per tag id (issue #786), absent for tags
  /// with no colour assigned. Resolved once for the whole collection so
  /// [entryFor] stays O(1) per tag rather than re-scanning [tags] per row.
  final Map<String, int> tagColors;
  final List<CustomFieldDef> customFieldDefs;
  final List<CustomFieldDef> listFieldDefs;
  final List<CustomFieldDef> choiceFields;
  final List<CustomFieldDef> booleanFields;
  final List<CustomFieldDef> textFields;
  final List<CustomFieldDef> numberFields;
  final Map<String, DateTime> lastCalled;

  /// The normalized caller scope used to load [callCounts] and [lastCalled].
  /// This is transient query context, not persisted user data, and lets shared
  /// picker searches use the same calling-history scope as their snapshot.
  final String? callerFilter;

  /// Per-dance calling tallies (all vs. performed) for the whole collection,
  /// loaded once so [DanceListTile] can render its "called ×N" chip honoring
  /// the "Require mark-performed" setting without an N+1 per-row query. Dances
  /// never called are absent (treated as zero by [entryFor]).
  final Map<String, DanceCallCounts> callCounts;
  final List<Choreographer> authors;
  final List<Tag> tags;

  /// Published sources cited by at least one dance in the collection (sorted by
  /// title). Drives the Source facet; an empty list hides the facet, matching
  /// the present-value pattern used for authors/tags/rating.
  final List<PublishedSource> citedSources;

  /// Distinct tune names across the collection, sorted case-insensitively, for
  /// the Tunes facet's suggestions. Names that differ only in case appear once
  /// (the first spelling met), since the facet matches ignoring case. Tune
  /// lists that could not be decoded contribute nothing.
  final List<String> tunes;

  final List<DanceForm> forms;
  final List<FormationShape> formations;
  final List<Progression> progressions;
  final List<DanceStatus> statuses;

  /// Configured difficulty levels that are assigned to at least one dance,
  /// ordered by the persisted vocabulary position.
  final List<DifficultyLevel> levels;

  /// Whether any dance is flagged mixed-level (drives the Mixed level facet).
  final bool hasMixedLevel;

  /// Whether any dance is flagged as a mixer (drives the Mixer facet).
  final bool hasMixer;

  /// Whether any dance carries a star rating (drives the minimum-rating facet;
  /// an all-unrated collection hides it, matching the present-value pattern).
  final bool hasRating;

  final Taxonomy taxonomy;
  final List<String> sectionLabels;

  /// The window used to collapse a burst of writes into one reload.
  ///
  /// The value is not tied to batch tagging: `DanceListScreen._batchTag` now
  /// commits once, while other collection operations can still produce
  /// notification bursts.
  /// This window is therefore a conservative burst-coalescing choice rather
  /// than a frame-budget or per-write timing claim.
  ///
  /// Both directions of error, since an unexplained constant invites deletion:
  ///
  /// - **Too short** — it stops collapsing and a burst leaks extra reloads.
  ///   Correctness is unaffected because every emit still carries a complete
  ///   snapshot.
  /// - **Too long** — the tail of a burst takes longer to settle. A single
  ///   write is never affected in either direction, because the leading edge
  ///   emits immediately; the window is only ever paid by a burst.
  ///
  /// A disk-backed sqlite on a phone may produce wider notification spacing,
  /// trading extra reloads against the tail latency of a shorter window.
  static const coalesceWindow = Duration(milliseconds: 24);

  /// A live [CollectionData], re-read whenever anything it is built from
  /// changes (issue #768).
  ///
  /// ## Why this reloads the snapshot rather than streaming its parts
  ///
  /// [load] composes a fan-out of queries across seven repositories into one
  /// immutable value that three screens share.
  ///
  /// Deliberately no query count. An earlier draft said "seven queries across
  /// five repositories" and both numbers were wrong — but the query count is
  /// worse than wrong, it is **not a constant**: `dances.listAll` eagerly
  /// loads its join tables with `IN (?)` reads that are skipped when there are
  /// no dances, so a measured load runs **6** statements on an empty
  /// collection and **12** with any dances in it. A number here cannot be
  /// correct for both, so the shape is described instead. The repository count
  /// is fixed in code and safe to state; the statement count is a property of
  /// the data. Streaming each part and
  /// recombining would emit once per part per write and could render a
  /// half-updated snapshot; so a content write re-runs [load] on a single
  /// change signal, which keeps the value atomic and leaves [load] the only
  /// place the composition is expressed.
  ///
  /// ## Program-only bursts refresh just the tallies
  ///
  /// The one part of the snapshot that program writes can change is the
  /// per-dance calling tallies ([lastCalled], [callCounts]) — about 1% of a
  /// full load on a large library — yet saving a program or marking a dance
  /// performed used to pay for the whole thing, up to three times (the
  /// Collection list, the program editor and the program summary each hold a
  /// watch). So the change signal is the set of tables written, unioned across
  /// the coalescing window. When that set is within `programs`/`program_slots`
  /// (plus `venues` when [watchVenues]) the stream re-reads only
  /// `programDerivedCounts` and emits [copyWithProgramCounts]; any other table
  /// in the set, or the first emission, runs the full [load]. The invariant:
  /// **a counts-only emit never changes [dancesById], the field definitions,
  /// [tags] or [citedSources]** — they are the previous snapshot's own
  /// objects. A `venues`-only write under [watchVenues] is counts-only too
  /// (it still emits, so a subscriber that renders a venue label next to this
  /// data is woken exactly as before; the re-read is the cheap one).
  ///
  /// This no longer subscribes to `watchCollectionSources`: it watches the same
  /// table set through `tableUpdates` because it needs to know *which* tables
  /// changed, which the sentinel's payload cannot say. That method stays, with
  /// its read set, for the consumers that only need "something changed".
  ///
  /// ## Why the coalescing window is load-bearing, not a nicety
  ///
  /// Bursts of sequential writes are possible here. Batch tagging in the
  /// Collection writes all affected dances in one transaction, while other
  /// collection operations can still emit several source-table notifications.
  /// Without a window, one user action could re-run this whole-snapshot load
  /// and the FTS search for each notification — precisely the thrashing issue
  /// #340 records, arriving as a side effect of fixing staleness.
  ///
  /// The window preserves the one-action / one-reload property that
  /// `RefreshCoalescer` gave the scope-based path — the same guarantee, moved
  /// to where the events now originate.
  ///
  /// ## This is a property of the migration, not of this screen
  ///
  /// The general statement of it now lives on [CoalesceTrailing], because the
  /// remaining conversions (issue #768) each meet it and each needs a window
  /// measured against its own burst shape. What is specific to this call is
  /// that batch tagging now emits one transaction-level commit behind a
  /// whole-snapshot load, while other operations can still produce bursts.
  ///
  /// Emits an initial value immediately, so a subscriber renders without
  /// waiting for a write.
  /// [watchVenues] adds `venues` to the watched set for consumers that render a
  /// venue label beside this data (issue #944). `CollectionData` itself carries
  /// no venue — the Collection list renders none — so it defaults to false and
  /// only the program editor and program summary opt in. See
  /// `CompendiumRepositories.watchCollectionSources` for why this is a
  /// parameter rather than an entry.
  static Stream<CollectionData> watch(
    CompendiumRepositories repos, {
    String? callerFilter,
    Duration coalesce = coalesceWindow,
    bool watchVenues = false,
  }) {
    final db = repos.db;
    final normalizedCallerFilter = normalizeCallingHistoryCaller(callerFilter);
    // The same set `watchCollectionSources` declares, as table names.
    final watched = <ResultSetImplementation<dynamic, dynamic>>{
      db.dances,
      db.choreographers,
      db.tags,
      db.difficultyLevels,
      db.customFieldDefs,
      db.publishedSources,
      db.programSlots,
      db.programs,
      if (watchVenues) db.venues,
    };
    final countsOnlyTables = {
      db.programSlots.actualTableName,
      db.programs.actualTableName,
      if (watchVenues) db.venues.actualTableName,
    };

    final out = StreamController<CollectionData>();
    StreamSubscription<void>? updatesSub;
    StreamSubscription<CollectionData>? loadSub;
    StreamController<void>? signal;

    out.onListen = () {
      // Tables written since the last reload began. Taken (and cleared) when
      // the window closes, so a write during a reload is seen by the next one.
      final changed = <String>{};
      // The first emission is always the full load.
      var needsFull = true;
      CollectionData? current;
      final signals = signal = StreamController<void>();

      // Subscribed before the first load starts, so a write during it is not
      // lost.
      updatesSub = db
          .tableUpdates(TableUpdateQuery.onAllTables(watched))
          .listen(
            (updates) {
              for (final u in updates) {
                changed.add(u.table);
              }
              signals.add(null);
            },
            onError: signals.addError,
            onDone: () {
              // The source ended (database closed): end now rather than after
              // an in-flight load, which may never return.
              if (!out.isClosed) unawaited(out.close());
            },
          );
      signals.add(null);

      loadSub = signals.stream
          .transform(CoalesceTrailing<void>(coalesce))
          .asyncMap((_) async {
            final tables = {...changed};
            changed.clear();
            final previous = current;
            if (!needsFull && tables.isEmpty) return null;
            final full =
                needsFull ||
                previous == null ||
                !countsOnlyTables.containsAll(tables);
            final next = full
                ? await load(repos, callerFilter: normalizedCallerFilter)
                : previous.copyWithProgramCounts(
                    await repos.programs.programDerivedCounts(
                      callerFilter: normalizedCallerFilter,
                    ),
                  );
            // Only now: a failed full load must be retried in full, not papered
            // over by a counts-only copy of a stale snapshot.
            needsFull = false;
            current = next;
            return next;
          })
          .where((snapshot) => snapshot != null)
          .cast<CollectionData>()
          .listen(
            (snapshot) {
              if (!out.isClosed) out.add(snapshot);
            },
            onError: (Object e, StackTrace st) {
              if (!out.isClosed) out.addError(e, st);
            },
          );
    };
    out.onCancel = () async {
      await updatesSub?.cancel();
      await loadSub?.cancel();
      await signal?.close();
    };
    return out.stream;
  }

  static Future<CollectionData> load(
    CompendiumRepositories repos, {
    String? callerFilter,
  }) async {
    final normalizedCallerFilter = normalizeCallingHistoryCaller(callerFilter);
    final dances = await repos.dances.listAll();
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listReferencedByLiveDances();
    final defs = await repos.customFieldDefs.listAll();
    final publishedSources = await repos.publishedSources.listAll();
    // One read for both: they come from the same query, so asking separately
    // would run it twice and could straddle a write (issue #768).
    final programCounts = await repos.programs.programDerivedCounts(
      callerFilter: normalizedCallerFilter,
    );
    final lastCalled = programCounts.lastCalled;
    final callCounts = programCounts.callCounts;

    final dancesById = {for (final d in dances) d.id: d};
    final choreographersById = {for (final c in choreographers) c.id: c};
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};
    // A null-aware element: tags with no colour assigned are simply absent.
    final tagColors = {for (final t in tags) t.id: ?t.color};

    // Facet vocabularies: only values actually present in the collection, so
    // empty facets don't clutter the panel (matching the Phase 3.1 approach).
    final forms = dances.map((d) => d.form).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final formations = dances.map((d) => d.formation.shape).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final progressions = dances.map((d) => d.progression).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final statuses = dances.map((d) => d.status).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final configuredLevels = await repos.difficultyLevels.listAll();
    final usedLevelIds = {
      for (final dance in dances)
        if (dance.difficultyLevelId != null) dance.difficultyLevelId!,
    };
    final levels = configuredLevels
        .where((level) => usedLevelIds.contains(level.id))
        .toList();
    final hasMixedLevel = dances.any((d) => d.mixedLevel);
    final hasMixer = dances.any((d) => d.mixer);
    final hasRating = dances.any((d) => d.rating != null);

    final usedAuthorIds = {for (final d in dances) ...d.authorIds};
    final usedTagIds = {for (final d in dances) ...d.tagIds};
    final authors =
        choreographers.where((c) => usedAuthorIds.contains(c.id)).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final tagList = tags.where((t) => usedTagIds.contains(t.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final usedSourceIds = {
      for (final d in dances)
        for (final c in d.sourceCitations) c.sourceId,
    };
    final citedSources =
        publishedSources.where((s) => usedSourceIds.contains(s.id)).toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );

    // First spelling wins per case-folded name; iteration follows `dances`, so
    // which spelling that is depends on load order, not on anything the user
    // can see — acceptable because the facet matches ignoring case anyway.
    final tuneByFold = <String, String>{};
    for (final d in dances) {
      if (d.tunesSource case DecodedTunes(:final tunes)) {
        for (final t in tunes) {
          final name = t.trim();
          if (name.isNotEmpty) {
            tuneByFold.putIfAbsent(name.toLowerCase(), () => name);
          }
        }
      }
    }
    final tuneList = tuneByFold.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final searchable = defs.where((d) => d.searchable).toList();

    return CollectionData(
      dancesById: dancesById,
      choreographersById: choreographersById,
      choreographerNames: choreographerNames,
      tagNames: tagNames,
      tagColors: tagColors,
      customFieldDefs: defs,
      listFieldDefs: defs.where((d) => d.showInList).toList(),
      choiceFields: searchable
          .where((d) => d.type == CustomFieldType.choice)
          .toList(),
      booleanFields: searchable
          .where((d) => d.type == CustomFieldType.boolean)
          .toList(),
      textFields: searchable
          .where((d) => d.type == CustomFieldType.text)
          .toList(),
      numberFields: searchable
          .where((d) => d.type == CustomFieldType.number)
          .toList(),
      lastCalled: lastCalled,
      callCounts: callCounts,
      callerFilter: normalizedCallerFilter,
      authors: authors,
      tags: tagList,
      citedSources: citedSources,
      tunes: tuneList,
      forms: forms,
      formations: formations,
      progressions: progressions,
      statuses: statuses,
      levels: levels,
      hasMixedLevel: hasMixedLevel,
      hasMixer: hasMixer,
      hasRating: hasRating,
      taxonomy: contraTaxonomy,
      sectionLabels: PhraseStructure.standard.labels,
    );
  }

  DanceListEntry entryFor(
    Dance dance, {
    Map<String, String> choreographerNamesOverride = const {},
  }) {
    DifficultyLevel? difficultyLevel;
    for (final level in levels) {
      if (level.id == dance.difficultyLevelId) {
        difficultyLevel = level;
        break;
      }
    }
    return DanceListEntry(
      dance: dance,
      difficultyLevel: difficultyLevel,
      authorNames: [
        for (final id in dance.authorIds)
          ?(choreographerNamesOverride[id] ?? choreographerNames[id]),
      ],
      tagNames: [
        for (final id in dance.tagIds)
          if (tagNames[id] != null) tagNames[id]!,
      ],
      tags: [
        for (final id in dance.tagIds)
          if (tagNames[id] != null)
            (id: id, name: tagNames[id]!, color: tagColors[id]),
      ],
      listCustomFields: [
        for (final def in listFieldDefs)
          for (final value in dance.customFields)
            if (value.fieldId == def.id)
              (label: def.label, value: value.value.toString()),
      ],
      lastCalled: lastCalled[dance.id],
      callCounts:
          callCounts[dance.id] ?? const DanceCallCounts(all: 0, performed: 0),
    );
  }
}
