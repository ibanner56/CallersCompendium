import 'package:compendium_core/compendium_core.dart';

/// Live tag ids whose name matches "ECD" case-insensitively — the same
/// [naturalKeyMatchKey] comparison [TagRepository.idByName] uses, applied to
/// every live tag rather than just the best match, since a legacy case-only
/// duplicate ("ECD" and "ecd" as separate rows) must count as the same tag
/// for this prompt. Empty when no live tag matches.
Future<Set<String>> ecdTagIds(CompendiumRepositories repos) async {
  final wanted = naturalKeyMatchKey('ECD');
  final tags = await repos.tags.listAll();
  return {
    for (final tag in tags)
      if (naturalKeyMatchKey(tag.name) == wanted) tag.id,
  };
}

/// Ids of live dances that are not already [DanceForm.ecd] but carry at least
/// one of [tagIds]. Returns no candidates without querying when [tagIds] is
/// empty (no "ECD" tag exists), since an empty [OrFilter] compiles to `FALSE`
/// anyway.
Future<List<String>> findEcdConvertCandidates(
  CompendiumRepositories repos,
  Set<String> tagIds,
) {
  if (tagIds.isEmpty) return Future.value(const []);
  return repos.dances.search(
    AndFilter([
      const NotFilter(FormFilter(DanceForm.ecd)),
      OrFilter([for (final id in tagIds) TagFilter(id)]),
    ]),
  );
}

/// Converts each dance in [danceIds] to [DanceForm.ecd] and strips every tag
/// in [tagIds] from it, in one transaction. A dance that no longer exists (or
/// was deleted between detection and confirmation) is silently skipped.
/// Returns the number of dances actually updated.
Future<int> convertDancesToEcd(
  CompendiumRepositories repos,
  List<String> danceIds,
  Set<String> tagIds, {
  DateTime? at,
}) async {
  final now = at ?? DateTime.now().toUtc();
  var converted = 0;
  await repos.transaction(() async {
    for (final id in danceIds) {
      final dance = await repos.dances.getById(id);
      if (dance == null) continue;
      await repos.dances.update(
        dance.copyWith(
          form: DanceForm.ecd,
          tagIds: [
            for (final tagId in dance.tagIds)
              if (!tagIds.contains(tagId)) tagId,
          ],
          updatedAt: now,
        ),
        localUserEdit: true,
      );
      converted++;
    }
  });
  return converted;
}
