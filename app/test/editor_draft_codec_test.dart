import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EditorSnapshot _minimalSnapshot({List<LinkSnapshot> links = const []}) =>
    EditorSnapshot(
      title: 'Test',
      hook: '',
      notes: '',
      phrase: '',
      formationDetail: '',
      form: DanceForm.contra,
      formationShape: FormationShape.dupleImproper,
      progression: Progression.single,
      status: DanceStatus.active,
      authorIds: const [],
      tagIds: const [],
      tunes: const [],
      links: links,
      customValues: const {},
      figureDrafts: const [],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('draft codec v5 —', () {
    test('encodes and decodes a URL-kind link', () {
      final snapshot = _minimalSnapshot(
        links: [
          const LinkSnapshot(
            id: 'l1',
            kind: LinkKind.source,
            url: 'https://example.com',
            label: 'My source',
          ),
        ],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));

      expect(decoded.links, hasLength(1));
      final l = decoded.links.single;
      expect(l.id, 'l1');
      expect(l.kind, LinkKind.source);
      expect(l.url, 'https://example.com');
      expect(l.label, 'My source');
      expect(l.targetDanceId, isNull);
    });

    test('encodes and decodes a relatedDance link', () {
      final snapshot = _minimalSnapshot(
        links: [
          const LinkSnapshot(
            id: 'l2',
            kind: LinkKind.relatedDance,
            url: '',
            label: 'See also',
            targetDanceId: 'd99',
          ),
        ],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));

      expect(decoded.links, hasLength(1));
      final l = decoded.links.single;
      expect(l.id, 'l2');
      expect(l.kind, LinkKind.relatedDance);
      expect(l.targetDanceId, 'd99');
      expect(l.label, 'See also');
      expect(l.url, '');
    });

    test('encodes and decodes a mix of URL and relatedDance links', () {
      final snapshot = _minimalSnapshot(
        links: [
          const LinkSnapshot(
            id: 'l1',
            kind: LinkKind.video,
            url: 'https://v',
            label: '',
          ),
          const LinkSnapshot(
            id: 'l2',
            kind: LinkKind.relatedDance,
            url: '',
            label: '',
            targetDanceId: 'd-target',
          ),
          const LinkSnapshot(
            id: 'l3',
            kind: LinkKind.other,
            url: 'https://o',
            label: 'misc',
          ),
        ],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));

      expect(decoded.links, hasLength(3));
      final rd = decoded.links.firstWhere(
        (l) => l.kind == LinkKind.relatedDance,
      );
      expect(rd.targetDanceId, 'd-target');
    });

    test('snapshot with no links round-trips cleanly', () {
      final decoded = decodeDraft(encodeDraft(_minimalSnapshot()));
      expect(decoded.links, isEmpty);
    });

    test('level and mixedLevel round-trip', () {
      final snapshot = EditorSnapshot(
        title: 'Test',
        hook: '',
        notes: '',
        phrase: '',
        formationDetail: '',
        form: DanceForm.contra,
        formationShape: FormationShape.dupleImproper,
        progression: Progression.single,
        status: DanceStatus.active,
        level: DanceLevel.advanced,
        mixedLevel: true,
        authorIds: const [],
        tagIds: const [],
        tunes: const [],
        links: const [],
        customValues: const {},
        figureDrafts: const [],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(decoded.level, DanceLevel.advanced);
      expect(decoded.mixedLevel, isTrue);
    });

    test('unspecified level is omitted and decodes back to null', () {
      final encoded = encodeDraft(_minimalSnapshot());
      expect(encoded, isNot(contains('"level"')));
      final decoded = decodeDraft(encoded);
      expect(decoded.level, isNull);
      expect(decoded.mixedLevel, isFalse);
    });

    test('v2 draft (no level/mixedLevel) decodes to null/false', () {
      const v2Json =
          '{"v":2,"title":"Old","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","authorIds":[],"tagIds":[],'
          '"tunes":[],"links":[],"customValues":{},"figureDrafts":[]}';
      final decoded = decodeDraft(v2Json);
      expect(decoded.level, isNull);
      expect(decoded.mixedLevel, isFalse);
    });

    test('rejects a future version (v > _kDraftVersion)', () {
      // A draft written by a newer version of the app must be rejected so we
      // never silently mangle data from a schema we don't understand.
      const futureJson =
          '{"v":99,"title":"Future","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","authorIds":[],"tagIds":[],'
          '"tunes":[],"links":[],"customValues":{},"figureDrafts":[]}';

      expect(() => decodeDraft(futureJson), throwsA(isA<FormatException>()));
    });

    test('v1 draft is forward-compatible: URL-kind links are preserved', () {
      // v1→v2 only added an optional targetDanceId to links.  A v1 autosave
      // draft (URL-only links, no relatedDance) must survive an app upgrade
      // so the user does not lose in-progress work.
      const v1Json =
          '{"v":1,"title":"Old Draft","hook":"A hook","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","authorIds":["a1"],'
          '"tagIds":[],"tunes":[],'
          '"links":[{"id":"l1","kind":"source","url":"https://example.com","label":"src"}],'
          '"preservedLinks":[],"customValues":{},"figureDrafts":[]}';

      final decoded = decodeDraft(v1Json);

      expect(decoded.title, 'Old Draft');
      expect(decoded.hook, 'A hook');
      expect(decoded.authorIds, ['a1']);
      expect(decoded.links, hasLength(1));
      expect(decoded.links.single.kind, LinkKind.source);
      expect(decoded.links.single.url, 'https://example.com');
      expect(decoded.links.single.label, 'src');
      expect(decoded.links.single.targetDanceId, isNull);
    });

    test('unknown top-level keys are silently ignored', () {
      // Insert a future key the current codec doesn't know about.
      final encoded = encodeDraft(
        _minimalSnapshot(),
      ).replaceFirst('"v":5', '"v":5,"futureKey":"ignored"');
      final decoded = decodeDraft(encoded);
      expect(decoded.title, 'Test');
    });

    test('composedOn / revisedOn round-trip partial precisions', () {
      final snapshot = EditorSnapshot(
        title: 'Test',
        hook: '',
        notes: '',
        phrase: '',
        formationDetail: '',
        form: DanceForm.contra,
        formationShape: FormationShape.dupleImproper,
        progression: Progression.single,
        status: DanceStatus.active,
        composedOn: PartialDate(1989),
        revisedOn: PartialDate(2004, 3, 15),
        authorIds: const [],
        tagIds: const [],
        tunes: const [],
        links: const [],
        customValues: const {},
        figureDrafts: const [],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(decoded.composedOn, PartialDate(1989));
      expect(decoded.revisedOn, PartialDate(2004, 3, 15));
    });

    test('unspecified dates are omitted and decode back to null', () {
      final encoded = encodeDraft(_minimalSnapshot());
      expect(encoded, isNot(contains('"composedOn"')));
      expect(encoded, isNot(contains('"revisedOn"')));
      final decoded = decodeDraft(encoded);
      expect(decoded.composedOn, isNull);
      expect(decoded.revisedOn, isNull);
    });

    test('v3 draft (no composed/revised dates) decodes to null', () {
      const v3Json =
          '{"v":3,"title":"Old","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","mixedLevel":false,'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[]}';
      final decoded = decodeDraft(v3Json);
      expect(decoded.composedOn, isNull);
      expect(decoded.revisedOn, isNull);
    });

    test('rating round-trips', () {
      final snapshot = EditorSnapshot(
        title: 'Test',
        hook: '',
        notes: '',
        phrase: '',
        formationDetail: '',
        form: DanceForm.contra,
        formationShape: FormationShape.dupleImproper,
        progression: Progression.single,
        status: DanceStatus.active,
        rating: 4,
        authorIds: const [],
        tagIds: const [],
        tunes: const [],
        links: const [],
        customValues: const {},
        figureDrafts: const [],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(decoded.rating, 4);
    });

    test('unrated is omitted and decodes back to null', () {
      final encoded = encodeDraft(_minimalSnapshot());
      expect(encoded, isNot(contains('"rating"')));
      final decoded = decodeDraft(encoded);
      expect(decoded.rating, isNull);
    });

    test('v4 draft (no rating) decodes to null', () {
      const v4Json =
          '{"v":4,"title":"Old","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","mixedLevel":false,'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[]}';
      final decoded = decodeDraft(v4Json);
      expect(decoded.rating, isNull);
    });

    test('rejects an out-of-range rating', () {
      const badJson =
          '{"v":5,"title":"Bad","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","rating":6,'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[]}';
      expect(() => decodeDraft(badJson), throwsA(isA<FormatException>()));
    });
  });
}
