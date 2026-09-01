import 'package:compendium_core/compendium_core.dart';

/// Saves a dance and reconciles its manually edited related-dance links.
///
/// Related-dance links remain directional in storage. This app-layer helper
/// persists the reciprocal direction for editor saves without changing import
/// behaviour.
Future<void> saveDanceWithRelatedLinks(
  CompendiumRepositories repos, {
  required Dance dance,
  Dance? original,
}) async {
  final before = {
    for (final link in original?.links ?? const <DanceLink>[])
      if (link.kind == LinkKind.relatedDance && link.targetDanceId != null)
        link.targetDanceId!,
  };
  final after = {
    for (final link in dance.links)
      if (link.kind == LinkKind.relatedDance && link.targetDanceId != null)
        link.targetDanceId!,
  };

  if (after.contains(dance.id)) {
    throw const RelatedDanceLinkSaveException.selfLink();
  }

  final added = after.difference(before);
  final affected = {...before, ...after}..remove(dance.id);

  await repos.db.transaction(() async {
    final targets = <String, Dance?>{};
    for (final targetId in affected) {
      final target = await repos.dances.getById(targetId, includeDeleted: true);
      if (added.contains(targetId) && (target == null || target.isDeleted)) {
        throw RelatedDanceLinkSaveException.missingTarget(targetId);
      }
      targets[targetId] = target;
    }

    if (original == null) {
      await repos.dances.create(dance);
    } else {
      await repos.dances.update(dance);
    }

    for (final targetId in affected) {
      final target = targets[targetId];
      if (target == null) continue; // The old target was purged.

      final keepReciprocal = after.contains(targetId) && !target.isDeleted;
      final existingReciprocals = target.links
          .where(
            (link) =>
                link.kind == LinkKind.relatedDance &&
                link.targetDanceId == dance.id,
          )
          .toList();
      final nextLinks = [...target.links];

      if (keepReciprocal) {
        if (existingReciprocals.isEmpty) {
          nextLinks.add(
            DanceLink(
              id: uuidV4(),
              kind: LinkKind.relatedDance,
              targetDanceId: dance.id,
            ),
          );
        } else if (existingReciprocals.length > 1) {
          final keepId = existingReciprocals
              .firstWhere(
                (l) => (l.label ?? '').trim().isNotEmpty,
                orElse: () => existingReciprocals.first,
              )
              .id;
          nextLinks.removeWhere(
            (link) =>
                link.kind == LinkKind.relatedDance &&
                link.targetDanceId == dance.id &&
                link.id != keepId,
          );
        }
      } else if (before.contains(targetId) && !after.contains(targetId)) {
        nextLinks.removeWhere(
          (link) =>
              link.kind == LinkKind.relatedDance &&
              link.targetDanceId == dance.id,
        );
      } else {
        continue;
      }

      if (_sameLinks(target.links, nextLinks)) continue;
      await repos.dances.update(
        target.copyWith(links: nextLinks, updatedAt: dance.updatedAt),
      );
    }
  });
}

bool _sameLinks(List<DanceLink> first, List<DanceLink> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

class RelatedDanceLinkSaveException implements Exception {
  const RelatedDanceLinkSaveException.selfLink()
    : targetDanceId = null,
      reason = 'self-link';

  const RelatedDanceLinkSaveException.missingTarget(this.targetDanceId)
    : reason = 'missing-target';

  final String? targetDanceId;
  final String reason;

  @override
  String toString() => targetDanceId == null
      ? 'RelatedDanceLinkSaveException($reason)'
      : 'RelatedDanceLinkSaveException($reason: $targetDanceId)';
}
