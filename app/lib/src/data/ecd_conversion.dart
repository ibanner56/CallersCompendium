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

/// Converts every dance still matching [findEcdConvertCandidates] to
/// [DanceForm.ecd] and strips its "ECD" tag(s), in one transaction. Returns
/// the number of dances actually updated.
///
/// The candidate set and the live "ECD" tag ids are both re-resolved inside
/// the transaction, immediately before writing, rather than reusing whatever
/// [findEcdConvertCandidates] returned when the on-launch prompt decided
/// whether to ask. The prompt's own detection pass can run long before the
/// user answers it (they read the dialog; sync can run concurrently and
/// change a dance's tags/form, rename or delete the "ECD" tag, or retag
/// another dance as "ECD" in the meantime), so re-validating here is what
/// keeps a stale id from forcing a dance sync has since changed, or from
/// stripping a tag id that no longer names "ECD".
Future<int> convertDancesToEcd(
  CompendiumRepositories repos, {
  DateTime? at,
}) async {
  final now = at ?? DateTime.now().toUtc();
  return repos.transaction(() async {
    final tagIds = await ecdTagIds(repos);
    final candidates = await findEcdConvertCandidates(repos, tagIds);
    var converted = 0;
    for (final id in candidates) {
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
    return converted;
  });
}
