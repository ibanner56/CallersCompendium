import 'package:compendium_core/compendium_core.dart';

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

  /// Whether any dance carries a star rating (drives the minimum-rating facet;
  /// an all-unrated collection hides it, matching the present-value pattern).
  final bool hasRating;

  final Taxonomy taxonomy;
  final List<String> sectionLabels;

  static Future<CollectionData> load(CompendiumRepositories repos) async {
    final dances = await repos.dances.listAll();
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final defs = await repos.customFieldDefs.listAll();
    final publishedSources = await repos.publishedSources.listAll();
    final lastCalled = await repos.programs.lastCalledByDance();
    final callCounts = await repos.programs.countByDance();

    final dancesById = {for (final d in dances) d.id: d};
    final choreographersById = {for (final c in choreographers) c.id: c};
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};

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
      hasRating: hasRating,
      taxonomy: contraTaxonomy,
      sectionLabels: PhraseStructure.standard.labels,
    );
  }

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
        if (tagNames[id] != null) (id: id, name: tagNames[id]!),
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
