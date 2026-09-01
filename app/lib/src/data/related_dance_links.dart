import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;

/// Maximum number of dances that one transitive save may inspect.
const int kMaxTransitiveDanceGroupSize = 100;

/// Saves a dance and reconciles its manually edited related-dance links.
///
/// Related-dance links remain directional in storage. This app-layer helper
/// persists reciprocal directions for editor saves without changing importer
/// behaviour. Only links marked [DanceLink.transitive] participate in graph
/// traversal; ordinary links are reconciled as individual pairs.
Future<void> saveDanceWithRelatedLinks(
  CompendiumRepositories repos, {
  required Dance dance,
  Dance? original,
}) async {
  final before = _relatedLinksByTarget(original?.links);
  final after = _relatedLinksByTarget(dance.links);

  if (after.containsKey(dance.id)) {
    throw const RelatedDanceLinkSaveException.selfLink();
  }

  await repos.db.transaction(() async {
    final cache = <String, Dance?>{dance.id: dance};
    final pendingLinks = <String, List<DanceLink>>{};

    Future<Dance?> load(String id) async {
      if (cache.containsKey(id)) return cache[id];
      final value = await repos.dances.getById(id, includeDeleted: true);
      cache[id] = value;
      return value;
    }

    Future<Set<String>> component(
      String seed, {
      required List<DanceLink> sourceLinks,
    }) async {
      final visited = <String>{};
      final scheduled = <String>{seed};
      final queue = <String>[seed];

      void schedule(String id) {
        if (!scheduled.add(id)) return;
        if (scheduled.length > kMaxTransitiveDanceGroupSize) {
          throw RelatedDanceLinkSaveException.groupTooLarge(
            kMaxTransitiveDanceGroupSize,
          );
        }
        queue.add(id);
      }

      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        if (!visited.add(id)) continue;

        final node = id == dance.id
            ? dance.copyWith(links: sourceLinks)
            : pendingLinks[id] != null
            ? (await load(id))?.copyWith(links: pendingLinks[id])
            : await load(id);
        if (node == null || node.isDeleted) continue;

        for (final link in node.links) {
          if (!link.transitive ||
              link.kind != LinkKind.relatedDance ||
              link.targetDanceId == null) {
            continue;
          }
          final target = await load(link.targetDanceId!);
          if (target != null && !target.isDeleted) schedule(target.id);
        }

        final remainingCapacity =
            kMaxTransitiveDanceGroupSize - scheduled.length;
        final scheduledVariables = [
          for (final scheduledId in scheduled) Variable.withString(scheduledId),
        ];
        final placeholders = List.filled(scheduled.length, '?').join(', ');
        final incoming = await repos.db
            .customSelect(
              'SELECT DISTINCT dance_id FROM dance_links '
              'WHERE target_dance_id = ? AND transitive = 1 '
              'AND dance_id NOT IN ($placeholders) '
              'LIMIT ?',
              variables: [
                Variable.withString(id),
                ...scheduledVariables,
                Variable.withInt(remainingCapacity + 1),
              ],
            )
            .get();
        for (final row in incoming) {
          final ownerId = row.read<String>('dance_id');
          final owner = ownerId == dance.id
              ? dance.copyWith(links: sourceLinks)
              : pendingLinks[ownerId] != null
              ? (await load(ownerId))?.copyWith(links: pendingLinks[ownerId])
              : await load(ownerId);
          if (owner == null || owner.isDeleted) continue;
          if (owner.links.any(
            (link) =>
                link.transitive &&
                link.kind == LinkKind.relatedDance &&
                link.targetDanceId == id,
          )) {
            schedule(owner.id);
          }
        }
      }
      return visited;
    }

    for (final targetId in after.keys) {
      final target = await load(targetId);
      final wasPresent = before.containsKey(targetId);
      if (!wasPresent && (target == null || target.isDeleted)) {
        throw RelatedDanceLinkSaveException.missingTarget(targetId);
      }
    }

    final detached = <String>{};
    final detachComponents = <Set<String>>[];
    for (final entry in before.entries) {
      final wasTransitive = entry.value.any((link) => link.transitive);
      final remainsTransitive =
          after[entry.key]?.any((link) => link.transitive) ?? false;
      if (!wasTransitive || remainsTransitive) continue;
      final group = await component(
        entry.key,
        sourceLinks: original?.links ?? const [],
      );
      detached.addAll(group);
      detachComponents.add(group);
    }

    var sourceLinks = dance.links;
    if (detached.contains(dance.id)) {
      sourceLinks = _removeTransitiveLinksWithin(
        sourceLinks,
        detached,
        preserveAsOrdinaryTargets: {
          for (final entry in after.entries)
            if (!entry.value.any((link) => link.transitive)) entry.key,
        },
      );
    }
    pendingLinks[dance.id] = sourceLinks;
    final nextSource = dance.copyWith(links: sourceLinks);
    final next = <String, Dance>{dance.id: nextSource};

    for (final group in detachComponents) {
      for (final id in group) {
        final node = await load(id);
        if (node == null) continue;
        final links = _removeTransitiveLinksWithin(
          node.links,
          group,
          preserveAsOrdinaryTargets: {
            if (id != dance.id &&
                after[id]?.any((link) => !link.transitive) == true)
              dance.id,
          },
        );
        pendingLinks[id] = links;
        if (!_sameLinks(node.links, links)) {
          next[id] = node.copyWith(links: links, updatedAt: dance.updatedAt);
        }
      }
    }

    // Preserve the ordinary pairwise reciprocal behavior for every direct
    // relation selected in the edited row.
    for (final targetId in after.keys) {
      final isTransitive = after[targetId]!.any((link) => link.transitive);
      if (isTransitive &&
          detached.contains(dance.id) &&
          detached.contains(targetId)) {
        continue;
      }
      final target = await load(targetId);
      if (target == null || target.isDeleted) continue;
      final targetLinks = next[targetId]?.links ?? target.links;
      final reciprocal = _ensureRelatedLink(
        targetLinks,
        targetId: dance.id,
        transitive: isTransitive,
      );
      if (!_sameLinks(targetLinks, reciprocal)) {
        pendingLinks[targetId] = reciprocal;
        next[targetId] = target.copyWith(
          links: reciprocal,
          updatedAt: dance.updatedAt,
        );
      }
    }

    for (final targetId in before.keys) {
      if (after.containsKey(targetId)) continue;
      final wasTransitive = before[targetId]!.any((link) => link.transitive);
      if (wasTransitive &&
          detached.contains(dance.id) &&
          detached.contains(targetId)) {
        continue;
      }
      final target = await load(targetId);
      if (target == null) continue;
      final targetLinks = next[targetId]?.links ?? target.links;
      final links = targetLinks
          .where(
            (link) =>
                link.kind != LinkKind.relatedDance ||
                link.targetDanceId != dance.id,
          )
          .toList();
      if (!_sameLinks(targetLinks, links)) {
        next[targetId] = target.copyWith(
          links: links,
          updatedAt: dance.updatedAt,
        );
      }
    }

    // Complete every component touched by a transitive row. The edited source
    // is passed as an override because it has not been written yet.
    for (final entry in _relatedLinksByTarget(sourceLinks).entries) {
      if (!entry.value.any((link) => link.transitive)) continue;
      final group = await component(entry.key, sourceLinks: sourceLinks);
      if (group.length < 2) continue;
      for (final ownerId in group) {
        final owner = await load(ownerId);
        if (owner == null || owner.isDeleted) continue;
        final ownerLinks = next[ownerId]?.links ?? owner.links;
        var links = ownerLinks;
        for (final targetId in group) {
          if (targetId == ownerId) continue;
          links = _ensureRelatedLink(
            links,
            targetId: targetId,
            transitive: true,
          );
        }
        if (!_sameLinks(ownerLinks, links)) {
          pendingLinks[ownerId] = links;
          next[ownerId] = owner.copyWith(
            links: links,
            updatedAt: dance.updatedAt,
          );
        }
      }
    }

    // Ensure a changed source is always written, while avoiding writes for
    // unaffected members and preserving the repository's update transaction.
    for (final entry in next.entries) {
      if (entry.key == dance.id) {
        if (original == null) {
          await repos.dances.create(entry.value);
        } else {
          await repos.dances.update(entry.value);
        }
      } else {
        final current = await load(entry.key);
        if (current == null || _sameLinks(current.links, entry.value.links)) {
          continue;
        }
        await repos.dances.update(entry.value);
      }
    }
  });
}

Map<String, List<DanceLink>> _relatedLinksByTarget(List<DanceLink>? links) {
  final result = <String, List<DanceLink>>{};
  for (final link in links ?? const <DanceLink>[]) {
    if (link.kind != LinkKind.relatedDance || link.targetDanceId == null) {
      continue;
    }
    (result[link.targetDanceId!] ??= []).add(link);
  }
  return result;
}

List<DanceLink> _removeTransitiveLinksWithin(
  List<DanceLink> links,
  Set<String> group, {
  Set<String> preserveAsOrdinaryTargets = const {},
}) => [
  for (final link in links)
    if (link.kind != LinkKind.relatedDance ||
        !link.transitive ||
        link.targetDanceId == null ||
        !group.contains(link.targetDanceId))
      link
    else if (preserveAsOrdinaryTargets.contains(link.targetDanceId))
      DanceLink(
        id: link.id,
        kind: link.kind,
        url: link.url,
        targetDanceId: link.targetDanceId,
        label: link.label,
      ),
];

List<DanceLink> _ensureRelatedLink(
  List<DanceLink> links, {
  required String targetId,
  required bool transitive,
}) {
  final matches = [
    for (final link in links)
      if (link.kind == LinkKind.relatedDance && link.targetDanceId == targetId)
        link,
  ];
  if (matches.isEmpty) {
    return [
      ...links,
      DanceLink(
        id: uuidV4(),
        kind: LinkKind.relatedDance,
        targetDanceId: targetId,
        transitive: transitive,
      ),
    ];
  }

  final canonical = matches.firstWhere(
    (link) => (link.label ?? '').trim().isNotEmpty,
    orElse: () => matches.first,
  );
  final canonicalLink = transitive && !canonical.transitive
      ? DanceLink(
          id: canonical.id,
          kind: canonical.kind,
          targetDanceId: canonical.targetDanceId,
          label: canonical.label,
          transitive: true,
        )
      : canonical;
  final matchIds = {for (final link in matches) link.id};
  return [
    for (final link in links)
      if (!matchIds.contains(link.id) || link.id == canonical.id)
        link.id == canonical.id ? canonicalLink : link,
  ];
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
      maxSize = null,
      reason = 'self-link';

  const RelatedDanceLinkSaveException.missingTarget(this.targetDanceId)
    : maxSize = null,
      reason = 'missing-target';

  const RelatedDanceLinkSaveException.groupTooLarge(this.maxSize)
    : targetDanceId = null,
      reason = 'group-too-large';

  final String? targetDanceId;
  final int? maxSize;
  final String reason;

  @override
  String toString() {
    if (targetDanceId != null) {
      return 'RelatedDanceLinkSaveException($reason: $targetDanceId)';
    }
    if (maxSize != null) {
      return 'RelatedDanceLinkSaveException($reason: $maxSize)';
    }
    return 'RelatedDanceLinkSaveException($reason)';
  }
}
