import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show listEquals;

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

/// What one [convertDancesToEcd] changed, kept so [undoEcdConversion] can
/// put it back.
final class EcdConversion {
  const EcdConversion._(this.before, this.removedTagIds);

  /// Each converted dance as it was just before the conversion.
  final List<Dance> before;

  /// The "ECD" tag ids the conversion stripped.
  final Set<String> removedTagIds;

  /// How many dances were converted.
  int get count => before.length;
}

/// Converts every dance still matching [findEcdConvertCandidates] to
/// [DanceForm.ecd] and strips its "ECD" tag(s), in one transaction. Returns
/// what was changed; its [EcdConversion.count] is the number of dances
/// actually updated.
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
Future<EcdConversion> convertDancesToEcd(
  CompendiumRepositories repos, {
  DateTime? at,
}) async {
  final now = at ?? DateTime.now().toUtc();
  return repos.transaction(() async {
    final tagIds = await ecdTagIds(repos);
    final candidates = await findEcdConvertCandidates(repos, tagIds);
    final before = <Dance>[];
    for (final id in candidates) {
      final dance = await repos.dances.getById(id);
      if (dance == null) continue;
      await repos.dances.update(
        dance.copyWith(
          form: DanceForm.ecd,
          tagIds: _withoutTags(dance.tagIds, tagIds),
          updatedAt: now,
        ),
        localUserEdit: true,
      );
      before.add(dance);
    }
    return EcdConversion._(List.unmodifiable(before), Set.unmodifiable(tagIds));
  });
}

/// Undoes [conversion]: gives each converted dance back its form and tags, in
/// one transaction. Returns how many dances were restored.
///
/// Only a dance whose form and tags are still exactly what the conversion
/// left is restored, and only those two fields are written, so an edit made
/// since (or a change sync brought in) is never overwritten. A stripped tag
/// that has since been deleted is not put back.
Future<int> undoEcdConversion(
  CompendiumRepositories repos,
  EcdConversion conversion, {
  DateTime? at,
}) async {
  final now = at ?? DateTime.now().toUtc();
  return repos.transaction(() async {
    final liveTagIds = {for (final tag in await repos.tags.listAll()) tag.id};
    var restored = 0;
    for (final before in conversion.before) {
      final current = await repos.dances.getById(before.id);
      if (current == null || current.form != DanceForm.ecd) continue;
      final converted = _withoutTags(before.tagIds, conversion.removedTagIds);
      if (!listEquals(current.tagIds, converted)) continue;
      await repos.dances.update(
        current.copyWith(
          form: before.form,
          tagIds: [
            for (final tagId in before.tagIds)
              if (liveTagIds.contains(tagId)) tagId,
          ],
          updatedAt: now,
        ),
        localUserEdit: true,
      );
      restored++;
    }
    return restored;
  });
}

List<String> _withoutTags(List<String> tagIds, Set<String> removed) => [
  for (final tagId in tagIds)
    if (!removed.contains(tagId)) tagId,
];
