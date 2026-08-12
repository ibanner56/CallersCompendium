import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/dance_list_entry.dart';

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
    required this.authors,
    required this.tags,
    required this.citedSources,
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

  final Map<String, Dance> dancesById;

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

  final List<DanceForm> forms;
  final List<FormationShape> formations;
  final List<Progression> progressions;
  final List<DanceStatus> statuses;

  /// Distinct assigned [DanceLevel]s present in the collection (sorted by
  /// ordinal); unspecified levels are excluded so an empty facet doesn't show.
  final List<DanceLevel> levels;

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
  /// Roughly one and a half frames at 60 Hz — deliberately a little OVER a
  /// frame, not under. A window shorter than the gap between two sequential
  /// awaits would not collapse the batch it exists to collapse, which is the
  /// whole point (see [watch]); and the delay is only ever paid by a burst,
  /// because the leading edge emits immediately. A single write is not
  /// deferred at all.
  static const coalesceWindow = Duration(milliseconds: 24);

  /// A live [CollectionData], re-read whenever anything it is built from
  /// changes (issue #768).
  ///
  /// ## Why this reloads the snapshot rather than streaming its parts
  ///
  /// [load] composes seven queries across five repositories into one immutable
  /// value that three screens share. Streaming each part and recombining would
  /// emit up to seven times per write and could render a half-updated
  /// snapshot; re-running the load on a single change signal keeps the
  /// existing value atomic and leaves [load] the only place the composition is
  /// expressed.
  ///
  /// ## Why the coalescing window is load-bearing, not a nicety
  ///
  /// Bursts of sequential writes are normal here. Batch tagging in the
  /// Collection updates **one dance per transaction in a loop**
  /// (`dance_list_screen.dart`, `_applyBatchTags`), so tagging 50 dances is 50
  /// commits, and drift notifies per commit. Without a window, one user action
  /// would re-run this seven-query load 50 times and re-run the FTS search
  /// after each — precisely the thrashing issue #340 records, arriving as a
  /// side effect of fixing staleness.
  ///
  /// The imperative code this replaces did not need a window because it
  /// broadcast **once, after** the loop. A stream has no equivalent hook: the
  /// database announces each commit as it happens and cannot know a batch is
  /// still in progress. So the window is what preserves the one-action /
  /// one-reload property that `RefreshCoalescer` gave the scope-based path —
  /// the same guarantee, moved to where the events now originate.
  ///
  /// Emits an initial value immediately, so a subscriber renders without
  /// waiting for a write.
  static Stream<CollectionData> watch(
    CompendiumRepositories repos, {
    String? callerFilter,
    Duration coalesce = coalesceWindow,
  }) => repos
      .watchCollectionSources()
      .transform(_CoalesceTrailing<void>(coalesce))
      .asyncMap((_) => load(repos, callerFilter: callerFilter));

  static Future<CollectionData> load(
    CompendiumRepositories repos, {
    String? callerFilter,
  }) async {
    final dances = await repos.dances.listAll();
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final defs = await repos.customFieldDefs.listAll();
    final publishedSources = await repos.publishedSources.listAll();
    // One read for both: they come from the same query, so asking separately
    // would run it twice and could straddle a write (issue #768).
    final programCounts = await repos.programs.programDerivedCounts(
      callerFilter: callerFilter,
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
    final levels =
        dances.map((d) => d.level).whereType<DanceLevel>().toSet().toList()
          ..sort((a, b) => a.index.compareTo(b.index));
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
      authors: authors,
      tags: tagList,
      citedSources: citedSources,
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

  /// A copy carrying fresh program-derived tallies, leaving everything else —
  /// the dances, the facet vocabularies, the custom-field defs — untouched.
  ///
  /// Deliberately narrow. These two maps are the only part of this snapshot
  /// that a *program*-side write can change, and they are the only part the
  /// Collection list refreshes from a stream (issue #768). Re-running the whole
  /// [load] for them would re-read every dance, choreographer, tag and custom
  /// field to update a badge, which is the over-firing failure issue #340
  /// records. Widen this only for another field a stream actually delivers.
  CollectionData copyWithProgramDerived({
    required Map<String, DateTime> lastCalled,
    required Map<String, DanceCallCounts> callCounts,
  }) => CollectionData(
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
    lastCalled: lastCalled,
    callCounts: callCounts,
    authors: authors,
    tags: tags,
    citedSources: citedSources,
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

  DanceListEntry entryFor(Dance dance) => DanceListEntry(
    dance: dance,
    authorNames: [
      for (final id in dance.authorIds)
        if (choreographerNames[id] != null) choreographerNames[id]!,
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
          if (value.fieldId == def.id) '${def.label}: ${value.value}',
    ],
    lastCalled: lastCalled[dance.id],
    callCounts:
        callCounts[dance.id] ?? const DanceCallCounts(all: 0, performed: 0),
  );
}

/// Collapses events arriving within [window] of each other, emitting the
/// **first** immediately and then at most one per window for as long as the
/// burst continues.
///
/// Not "one leading plus one trailing": the window is deliberately re-armed
/// after each trailing emit, so a burst longer than [window] keeps reporting
/// progress at that rate instead of going silent until it ends. A 200-dance
/// batch should move the UI while it runs. The bound this guarantees is
/// therefore a *rate* — one emit per window — not a total.
///
/// Leading-edge rather than a plain trailing debounce, so the first change a
/// user makes is reflected without waiting out the window; the trailing emit
/// then covers everything that arrived during it. A pure trailing debounce
/// would delay every single-write update by the full window for no benefit.
@visibleForTesting
StreamTransformerBase<T, T> debugCoalesceTrailing<T>(Duration window) =>
    _CoalesceTrailing<T>(window);

class _CoalesceTrailing<T> extends StreamTransformerBase<T, T> {
  const _CoalesceTrailing(this.window);

  final Duration window;

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    var pending = false;
    late T last;

    void flush() {
      timer = null;
      if (!pending) return;
      pending = false;
      controller.add(last);
      // Keep the window open after a trailing emit so a burst that continues
      // past it is still collapsed rather than emitting once per window.
      timer = Timer(window, flush);
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = stream.listen(
          (event) {
            last = event;
            if (timer == null) {
              controller.add(event); // leading edge
              timer = Timer(window, flush);
            } else {
              pending = true;
            }
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            timer = null;
            // Emit anything still held before closing. Without this the final
            // state of a burst is lost whenever the source ends mid-window —
            // a database closed during teardown, or a screen disposed while a
            // batch is still committing — which would contradict the trailing
            // guarantee this transformer exists to provide.
            if (pending) {
              pending = false;
              controller.add(last);
            }
            controller.close();
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
