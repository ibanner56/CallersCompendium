import 'package:compendium_core/compendium_core.dart';

/// One [SavedSearchContext] for loading a saved search (#2325): everything
/// the resolver checks a search against, read once from the live data, never
/// per reference. The settings that are not part of a search (Settings ▸
/// Calling history) are the host's live values, passed in, so a saved search
/// runs with the settings in force when it runs.
///
/// The merge aliases come from one bulk read
/// ([SyncLocalRepository.aliasMaps]); the resolver follows chains in memory.
Future<SavedSearchContext> readSavedSearchContext(
  CompendiumRepositories repos, {
  required DateTime today,
  required Taxonomy taxonomy,
  required SavedSearchTextCodec text,
  String? callerFilter,
  bool performedOnly = false,
  bool requireEventDate = false,
  CallingHistoryTracking tracking = CallingHistoryTracking.defaults,
  String? currentProgramId,
}) async {
  final tags = await repos.tags.listAll();
  final authors = await repos.choreographers.listAll();
  final sources = await repos.publishedSources.listAll();
  final levels = await repos.difficultyLevels.listAll();
  final venues = await repos.venues.listAll();
  final glossary = await repos.userGlossary.listAll();
  final defs = await repos.customFieldDefs.listAll();
  final aliases = await repos.syncLocal.aliasMaps();
  return SavedSearchContext(
    today: today,
    taxonomy: taxonomy,
    callerFilter: callerFilter,
    performedOnly: performedOnly,
    requireEventDate: requireEventDate,
    tracking: tracking,
    currentProgramId: currentProgramId,
    tagIds: {for (final t in tags) t.id},
    authorIds: {for (final a in authors) a.id},
    sourceIds: {for (final s in sources) s.id},
    levelIds: {for (final l in levels) l.id},
    venueIds: {for (final v in venues) v.id},
    userFigureIds: {
      for (final e in glossary)
        if (e.kind == UserGlossaryEntryKind.customFigure) e.id,
    },
    customFieldDefs: defs,
    aliases: aliases,
    text: text,
  );
}
