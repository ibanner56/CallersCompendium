import 'package:meta/meta.dart';

import '../model/dance_link.dart';
import '../model/enums.dart';
import '../util/uuid.dart';
import 'callers_companion_usr_archive.dart';
import 'structured_draft.dart';

/// The result of [buildCcRelatedDanceLinks]: the [DanceLink]s to **add** to
/// each source dance, keyed by its (already-committed) Compendium dance id,
/// plus the non-fatal [ImportIssue]s raised while resolving them.
///
/// [newLinksByDanceId] carries only ADDITIONS — the caller is expected to
/// append these to each dance's existing `links` (never replace them).
@immutable
class CcRelatedDanceLinksResult {
  CcRelatedDanceLinksResult({
    Map<String, List<DanceLink>> newLinksByDanceId = const {},
    List<ImportIssue> issues = const [],
  }) : newLinksByDanceId = Map.unmodifiable({
         for (final entry in newLinksByDanceId.entries)
           entry.key: List<DanceLink>.unmodifiable(entry.value),
       }),
       issues = List.unmodifiable(issues);

  final Map<String, List<DanceLink>> newLinksByDanceId;
  final List<ImportIssue> issues;
}

/// Builds the `relatedDance` [DanceLink]s a CC `.USR` import should add, from
/// the archive's [CcUsrArchive.relatedDancePairs] (issue #688).
///
/// This is a **pure builder** — no repository, no I/O — mirroring
/// [buildCcPrograms]'s philosophy, so it is trivially unit-testable. The app
/// layer (`CallersCompanionUsrImporter.commit`) calls it *after* the dance
/// import commits, passing:
/// - [danceIdByCcRowId]: the same CC-`zk_Dance_ID` → new-Compendium-dance-id
///   map `buildCcPrograms` uses, built from the just-committed
///   [ImportSession](`callers_companion_usr_import.dart`'s
///   `_danceIdByCcRowId`) — so a pair can only resolve to a dance this
///   session actually committed, never an arbitrary/stale id (OWASP: the CC
///   `Dance_Related` ids are untrusted external data).
/// - [existingLinksByDanceId]: each candidate source dance's **current**
///   `relatedDance` links (fetched by the caller before this call), used to
///   dedupe against links a prior import of the same archive already added.
///
///   **Honest caveat on when this actually fires:** `CallersCompanionUsrImporter`
///   commits every CC dance through `ImportPipeline`'s `create`/`reimport`/
///   `link`/`duplicate` actions, and ALL of them rebuild the dance's content —
///   including its `links` — wholesale from the freshly-parsed draft (which
///   never carries links; consistent with re-import's "overwrite, don't
///   merge" philosophy for every other field). So by the time this builder's
///   caller fetches a candidate source dance, its links have *already* been
///   reset to empty by that same commit — [existingLinksByDanceId] is
///   therefore, in the current wiring, always empty for every dance this
///   builder can be asked about (a dance only becomes a candidate at all by
///   resolving through [danceIdByCcRowId], which only ever names dances this
///   very commit just rebuilt). Re-import duplication is thus already
///   prevented structurally by that full-overwrite step, not by this dedupe
///   check. The parameter and check are kept anyway — they are correct,
///   cheap, independently unit-tested, and a safety net if the importer's
///   commit path ever stops fully rebuilding a dance's links (e.g. a future
///   change that merges rather than replaces).
///
/// **Directional only** (issue #688 decision): each `Dance_Related` row
/// produces exactly one directed link, on the SOURCE dance, pointing at the
/// target. Nothing here synthesizes a reverse link. The manual editor has a
/// separate app-layer save path that mirrors links for user edits; imports stay
/// directional so if CC's real data mirrors relationships as two rows,
/// importing each row independently already reproduces that bidirectional
/// *display* without any special-casing.
///
/// **Parse-never-fails, fail-closed-on-injection:** a pair whose source or
/// target CC id did not resolve to a committed dance (not imported this
/// session, or an orphan/typo'd id) is **skipped** with a warning
/// [ImportIssue] — never a [DanceLink] with an unresolved/dangling
/// `targetDanceId`.
CcRelatedDanceLinksResult buildCcRelatedDanceLinks(
  CcUsrArchive archive, {
  required Map<String, String> danceIdByCcRowId,
  required Map<String, List<DanceLink>> existingLinksByDanceId,
  String Function()? newId,
}) {
  final mintId = newId ?? uuidV4;
  final issues = <ImportIssue>[];
  final newLinksByDanceId = <String, List<DanceLink>>{};
  // Within-pass dedupe: a (source, target) pair already queued this call
  // (e.g. the archive listed the same relationship twice) is only added once.
  final queuedPairs = <String>{};

  for (final pair in archive.relatedDancePairs) {
    final sourceDanceId = danceIdByCcRowId[pair.sourceRecordId];
    final targetDanceId = danceIdByCcRowId[pair.targetRecordId];
    if (sourceDanceId == null || targetDanceId == null) {
      final unresolved = sourceDanceId == null
          ? pair.sourceRecordId
          : pair.targetRecordId;
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'cc_related_dance_unresolved',
          message:
              'A Caller\'s Companion related-dance link between dance '
              '#${pair.sourceRecordId} and #${pair.targetRecordId} was not '
              'imported because dance #$unresolved was not committed in '
              'this import.',
        ),
      );
      continue;
    }
    if (sourceDanceId == targetDanceId) {
      // Defensive: the archive layer already drops CC-id self-references, but
      // two distinct CC ids can still resolve to the same committed dance
      // (e.g. a dedupe merge) — never a dance related to itself.
      continue;
    }

    final pairKey = '$sourceDanceId\u0000$targetDanceId';
    if (!queuedPairs.add(pairKey)) continue;

    final alreadyExists = (existingLinksByDanceId[sourceDanceId] ?? const [])
        .any(
          (link) =>
              link.kind == LinkKind.relatedDance &&
              link.targetDanceId == targetDanceId,
        );
    if (alreadyExists) continue;

    newLinksByDanceId
        .putIfAbsent(sourceDanceId, () => [])
        .add(
          DanceLink(
            id: mintId(),
            kind: LinkKind.relatedDance,
            targetDanceId: targetDanceId,
          ),
        );
  }

  return CcRelatedDanceLinksResult(
    newLinksByDanceId: newLinksByDanceId,
    issues: issues,
  );
}
