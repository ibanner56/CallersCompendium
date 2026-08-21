import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EditorSnapshot _minimalSnapshot({
  List<LinkSnapshot> links = const [],
  List<SourceCitation> sourceCitations = const [],
  List<FigureDraftSnapshot> figureDrafts = const [],
}) => EditorSnapshot(
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
  sourceCitations: sourceCitations,
  customValues: const {},
  figureDrafts: figureDrafts,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('draft codec v6 —', () {
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

    test('figure draft assumedSubject round-trips (#460)', () {
      final snapshot = _minimalSnapshot();
      final withDrafts = EditorSnapshot(
        title: snapshot.title,
        hook: snapshot.hook,
        notes: snapshot.notes,
        phrase: snapshot.phrase,
        formationDetail: snapshot.formationDetail,
        form: snapshot.form,
        formationShape: snapshot.formationShape,
        progression: snapshot.progression,
        status: snapshot.status,
        authorIds: snapshot.authorIds,
        tagIds: snapshot.tagIds,
        tunes: snapshot.tunes,
        links: snapshot.links,
        sourceCitations: snapshot.sourceCitations,
        customValues: snapshot.customValues,
        figureDrafts: const [
          FigureDraftSnapshot(
            id: 'f-assumed',
            move: 'allemande',
            params: {'who': 'neighbors', 'hand': 'left'},
            note: '',
            progression: false,
            schemaVersion: figureSchemaVersion,
            assumedSubject: true,
          ),
          FigureDraftSnapshot(
            id: 'f-stated',
            move: 'swing',
            params: {'who': 'partners'},
            note: '',
            progression: false,
            schemaVersion: figureSchemaVersion,
          ),
        ],
      );

      final encoded = encodeDraft(withDrafts);
      // Additive shape: written only for the assumed draft.
      expect(encoded, contains('"assumedSubject":true'));

      final decoded = decodeDraft(encoded);
      final assumed = decoded.figureDrafts.firstWhere(
        (d) => d.id == 'f-assumed',
      );
      final stated = decoded.figureDrafts.firstWhere((d) => d.id == 'f-stated');
      expect(assumed.assumedSubject, isTrue);
      expect(stated.assumedSubject, isFalse);
    });

    test('figure draft customOrigin round-trips (#419)', () {
      final snapshot = _minimalSnapshot();
      final withDrafts = EditorSnapshot(
        title: snapshot.title,
        hook: snapshot.hook,
        notes: snapshot.notes,
        phrase: snapshot.phrase,
        formationDetail: snapshot.formationDetail,
        form: snapshot.form,
        formationShape: snapshot.formationShape,
        progression: snapshot.progression,
        status: snapshot.status,
        authorIds: snapshot.authorIds,
        tagIds: snapshot.tagIds,
        tunes: snapshot.tunes,
        links: snapshot.links,
        sourceCitations: snapshot.sourceCitations,
        customValues: snapshot.customValues,
        figureDrafts: const [
          FigureDraftSnapshot(
            id: 'f-gap',
            move: customMove,
            params: {'text': 'kept verbatim'},
            note: '',
            progression: false,
            schemaVersion: figureSchemaVersion,
            customOrigin: CustomOrigin.importGap,
          ),
          FigureDraftSnapshot(
            id: 'f-user',
            move: customMove,
            params: {'text': 'my own call'},
            note: '',
            progression: false,
            schemaVersion: figureSchemaVersion,
          ),
        ],
      );

      final encoded = encodeDraft(withDrafts);
      // Additive shape: written only for the parser-gap custom.
      expect(encoded, contains('"customOrigin":"importGap"'));

      final decoded = decodeDraft(encoded);
      final gap = decoded.figureDrafts.firstWhere((d) => d.id == 'f-gap');
      final user = decoded.figureDrafts.firstWhere((d) => d.id == 'f-user');
      expect(gap.customOrigin, CustomOrigin.importGap);
      expect(user.customOrigin, CustomOrigin.userEntered);
    });

    test('figure draft wordingOverride round-trips (#822)', () {
      final snapshot = _minimalSnapshot(
        figureDrafts: const [
          FigureDraftSnapshot(
            id: 'f-wording',
            move: 'swing',
            params: {'who': 'partners'},
            note: '',
            progression: false,
            schemaVersion: figureSchemaVersion,
            wordingOverride: 'A custom line.',
          ),
        ],
      );

      final encoded = encodeDraft(snapshot);
      expect(encoded, contains('"wordingOverride":"A custom line."'));
      expect(
        decodeDraft(encoded).figureDrafts.single.wordingOverride,
        'A custom line.',
      );
    });

    test('a legacy/garbage customOrigin decodes to userEntered', () {
      const legacy =
          '{"v":6,"title":"T","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":'
          '"dupleImproper","progression":"single","status":"active",'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[{"id":"f1","move":"custom",'
          '"params":{"text":"x"},"note":"","progression":false,'
          '"sv":1,"customOrigin":"bogus"}]}';
      final decoded = decodeDraft(legacy);
      expect(
        decoded.figureDrafts.single.customOrigin,
        CustomOrigin.userEntered,
      );
    });

    test('a legacy figure draft without assumedSubject decodes to false', () {
      const legacy =
          '{"v":6,"title":"T","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":'
          '"dupleImproper","progression":"single","status":"active",'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[{"id":"f1","move":"swing",'
          '"params":{"who":"partners"},"note":"","progression":false,'
          '"sv":1}]}';
      final decoded = decodeDraft(legacy);
      expect(decoded.figureDrafts.single.assumedSubject, isFalse);
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
        sourceCitations: const [],
        customValues: const {},
        figureDrafts: const [],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(decoded.level, DanceLevel.advanced);
      expect(decoded.mixedLevel, isTrue);
    });

    test('mixer round-trips (issue #732)', () {
      final snapshot = EditorSnapshot(
        title: 'Test',
        hook: '',
        notes: '',
        phrase: '',
        formationDetail: '',
        form: DanceForm.contra,
        formationShape: FormationShape.circleMixer,
        progression: Progression.single,
        status: DanceStatus.active,
        mixer: true,
        authorIds: const [],
        tagIds: const [],
        tunes: const [],
        links: const [],
        sourceCitations: const [],
        customValues: const {},
        figureDrafts: const [],
      );

      final encoded = encodeDraft(snapshot);
      expect(encoded, contains('"mixer":true'));
      expect(decodeDraft(encoded).mixer, isTrue);
    });

    test('an older draft with no mixer key decodes to false (issue #732)', () {
      // A v8 draft predates the mixer field entirely; the key is absent and
      // must default to false (why the additive change needs no data upgrade).
      const v8Json =
          '{"v":8,"title":"Old","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","mixedLevel":false,'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"sourceCitations":[],"customValues":{},"figureDrafts":[]}';
      final decoded = decodeDraft(v8Json);
      expect(decoded.mixer, isFalse);
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
      ).replaceFirst('"v":6', '"v":6,"futureKey":"ignored"');
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
        sourceCitations: const [],
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
        sourceCitations: const [],
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

    test('sourceCitations round-trip with page and number', () {
      final snapshot = _minimalSnapshot(
        sourceCitations: [
          SourceCitation(sourceId: 's1', page: '12-14', number: 'A1'),
          SourceCitation(sourceId: 's2'),
        ],
      );

      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(decoded.sourceCitations, hasLength(2));
      final first = decoded.sourceCitations.first;
      expect(first.sourceId, 's1');
      expect(first.page, '12-14');
      expect(first.number, 'A1');
      final second = decoded.sourceCitations[1];
      expect(second.sourceId, 's2');
      expect(second.page, isNull);
      expect(second.number, isNull);
    });

    test('no sourceCitations is omitted and decodes back to empty', () {
      final encoded = encodeDraft(_minimalSnapshot());
      expect(encoded, isNot(contains('"sourceCitations"')));
      final decoded = decodeDraft(encoded);
      expect(decoded.sourceCitations, isEmpty);
    });

    test('v5 draft (no sourceCitations) decodes to empty list', () {
      const v5Json =
          '{"v":5,"title":"Old","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active","mixedLevel":false,'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[]}';
      final decoded = decodeDraft(v5Json);
      expect(decoded.sourceCitations, isEmpty);
    });

    test('rejects a malformed sourceCitation (missing sourceId)', () {
      const badJson =
          '{"v":6,"title":"Bad","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active",'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"sourceCitations":[{"page":"12"}],'
          '"customValues":{},"figureDrafts":[]}';
      expect(() => decodeDraft(badJson), throwsA(isA<FormatException>()));
    });

    test('rejects sourceCitations that is not an array', () {
      const badJson =
          '{"v":6,"title":"Bad","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active",'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"sourceCitations":"nope",'
          '"customValues":{},"figureDrafts":[]}';
      expect(() => decodeDraft(badJson), throwsA(isA<FormatException>()));
    });

    test('walkthrough round-trips (v7)', () {
      final snapshot = _minimalSnapshotWith(
        walkthrough: 'A1: balance and swing.\nB1: circle left.',
      );
      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(decoded.walkthrough, 'A1: balance and swing.\nB1: circle left.');
    });

    test('an empty walkthrough is omitted from the encoded JSON', () {
      final json = encodeDraft(_minimalSnapshotWith(walkthrough: ''));
      expect(json.contains('walkthrough'), isFalse);
    });

    test('a pre-walkthrough (v6) draft decodes with an empty walkthrough', () {
      const v6Json =
          '{"v":6,"title":"Old","hook":"","notes":"","phrase":"",'
          '"formationDetail":"","form":"contra","formationShape":"dupleImproper",'
          '"progression":"single","status":"active",'
          '"authorIds":[],"tagIds":[],"tunes":[],"links":[],'
          '"customValues":{},"figureDrafts":[]}';
      expect(decodeDraft(v6Json).walkthrough, '');
    });
  });
}

EditorSnapshot _minimalSnapshotWith({required String walkthrough}) =>
    EditorSnapshot(
      title: 'Test',
      hook: '',
      notes: '',
      walkthrough: walkthrough,
      phrase: '',
      formationDetail: '',
      form: DanceForm.contra,
      formationShape: FormationShape.dupleImproper,
      progression: Progression.single,
      status: DanceStatus.active,
      authorIds: const [],
      tagIds: const [],
      tunes: const [],
      links: const [],
      sourceCitations: const [],
      customValues: const {},
      figureDrafts: const [],
    );
