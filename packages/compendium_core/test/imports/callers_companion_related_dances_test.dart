import 'package:compendium_core/src/imports/callers_companion_related_dances.dart';
import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/structured_draft.dart';
import 'package:compendium_core/src/model/dance_link.dart';
import 'package:compendium_core/src/model/enums.dart';
import 'package:test/test.dart';

/// Tests for [buildCcRelatedDanceLinks] — the pure `Dance_Related` →
/// `relatedDance`-[DanceLink] builder. Built against hand-constructed
/// [CcUsrArchive]s (its public constructor) so it is hermetic and
/// Flutter-free — mirrors `callers_companion_programs_test.dart`'s style.
CcUsrArchive _archive(List<CcRelatedDancePair> pairs) => CcUsrArchive(
  dances: const [],
  sets: const [],
  relatedDancePairs: pairs,
  warnings: const [],
);

CcRelatedDancePair _pair(String source, String target) =>
    CcRelatedDancePair(sourceRecordId: source, targetRecordId: target);

void main() {
  var linkId = 0;
  setUp(() => linkId = 0);
  String mintId() => 'link-${linkId++}';

  CcRelatedDanceLinksResult build(
    List<CcRelatedDancePair> pairs, {
    Map<String, String> danceIds = const {},
    Map<String, List<DanceLink>> existingLinks = const {},
  }) => buildCcRelatedDanceLinks(
    _archive(pairs),
    danceIdByCcRowId: danceIds,
    existingLinksByDanceId: existingLinks,
    newId: mintId,
  );

  test('both endpoints imported: adds one directed relatedDance link on the '
      'source dance', () {
    final result = build(
      [_pair('4', '7')],
      danceIds: {'4': 'dance-a', '7': 'dance-b'},
    );

    expect(result.issues, isEmpty);
    expect(result.newLinksByDanceId.keys, ['dance-a']);
    final link = result.newLinksByDanceId['dance-a']!.single;
    expect(link.kind, LinkKind.relatedDance);
    expect(link.targetDanceId, 'dance-b');
    // Never on the reverse dance — directional only, no auto-mirror.
    expect(result.newLinksByDanceId.containsKey('dance-b'), isFalse);
  });

  test('a mirrored pair of rows (A→B and B→A) yields two independent directed '
      'links, never synthesized on our own', () {
    final result = build(
      [_pair('4', '7'), _pair('7', '4')],
      danceIds: {'4': 'dance-a', '7': 'dance-b'},
    );

    expect(
      result.newLinksByDanceId['dance-a']!.single.targetDanceId,
      'dance-b',
    );
    expect(
      result.newLinksByDanceId['dance-b']!.single.targetDanceId,
      'dance-a',
    );
  });

  test('target not imported this session: skipped with a non-fatal warning, '
      'never a dangling targetDanceId', () {
    final result = build(
      [_pair('4', '99')],
      danceIds: {'4': 'dance-a'}, // '99' never resolved
    );

    expect(result.newLinksByDanceId, isEmpty);
    expect(result.issues, hasLength(1));
    expect(result.issues.single.severity, ImportIssueSeverity.warning);
    expect(result.issues.single.code, 'cc_related_dance_unresolved');
    expect(result.issues.single.message, contains('99'));
  });

  test('source not imported this session: skipped with a non-fatal warning, '
      'never a dangling targetDanceId', () {
    final result = build(
      [_pair('99', '4')],
      danceIds: {'4': 'dance-a'}, // '99' never resolved
    );

    expect(result.newLinksByDanceId, isEmpty);
    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('99'));
  });

  test('cross-import dedupe: an existing equivalent link suppresses a '
      'duplicate', () {
    final existing = DanceLink(
      id: 'existing-link',
      kind: LinkKind.relatedDance,
      targetDanceId: 'dance-b',
    );
    final result = build(
      [_pair('4', '7')],
      danceIds: {'4': 'dance-a', '7': 'dance-b'},
      existingLinks: {
        'dance-a': [existing],
      },
    );

    expect(result.newLinksByDanceId, isEmpty);
  });

  test('within-pass dedupe: the same pair appearing twice in the archive '
      'produces only one link', () {
    final result = build(
      [_pair('4', '7'), _pair('4', '7')],
      danceIds: {'4': 'dance-a', '7': 'dance-b'},
    );

    expect(result.newLinksByDanceId['dance-a'], hasLength(1));
  });

  test('two distinct CC ids resolving to the same Compendium dance (a dedupe '
      'merge) never link a dance to itself', () {
    final result = build(
      [_pair('4', '7')],
      danceIds: {'4': 'dance-a', '7': 'dance-a'}, // merged onto one dance
    );

    expect(result.newLinksByDanceId, isEmpty);
  });

  test('existing non-relatedDance links on the source dance never suppress '
      'a new relatedDance link', () {
    final existingSourceLink = DanceLink(
      id: 'src-link',
      kind: LinkKind.source,
      url: 'https://example.com',
    );
    final result = build(
      [_pair('4', '7')],
      danceIds: {'4': 'dance-a', '7': 'dance-b'},
      existingLinks: {
        'dance-a': [existingSourceLink],
      },
    );

    expect(result.newLinksByDanceId['dance-a'], hasLength(1));
  });

  test('mixed pass: one resolved link plus one unresolved skip in the same '
      'call', () {
    final result = build(
      [_pair('4', '7'), _pair('4', '99')],
      danceIds: {'4': 'dance-a', '7': 'dance-b'},
    );

    expect(result.newLinksByDanceId['dance-a'], hasLength(1));
    expect(result.issues, hasLength(1));
  });
}
