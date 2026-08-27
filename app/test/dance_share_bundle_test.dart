import 'package:compendium_app/src/export/dance_share_bundle.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 1, 1);

void main() {
  test('contains referenced metadata and share-safe choreographer data', () {
    final dance = Dance(
      id: 'd1',
      title: 'Rory O\'More',
      authorIds: const ['c1'],
      tagIds: const ['t1'],
      sourceCitations: [SourceCitation(sourceId: 's1', page: '12')],
      customFields: [
        CustomFieldValue(fieldId: 'f1', value: 'yes'),
        CustomFieldValue(fieldId: 'f2', value: 'private'),
      ],
      createdAt: _now,
      updatedAt: _now,
    );
    final shareableField = CustomFieldDef(
      id: 'f1',
      key: 'teach',
      label: 'Needs teaching',
      type: CustomFieldType.text,
      shareable: true,
    );
    final privateField = CustomFieldDef(
      id: 'f2',
      key: 'private',
      label: 'Private',
      type: CustomFieldType.text,
      shareable: false,
    );

    final archive = decodeArchive(
      buildDanceShareBundle(
        dance,
        now: _now,
        choreographerFor: (_) => Choreographer(
          id: 'c1',
          name: 'Caller',
          email: 'caller@example.com',
          location: 'Somewhere',
          deceased: true,
        ),
        tagFor: (_) => Tag(id: 't1', name: 'chestnut', color: 0xFF00FF00),
        publishedSourceFor: (_) => PublishedSource(
          id: 's1',
          title: 'A book',
          author: 'An author',
          year: 1984,
        ),
        customFieldFor: (id) => id == 'f1' ? shareableField : privateField,
      ),
    ).archive;

    expect(archive.dances.single.id, 'd1');
    expect(archive.tags.single.id, 't1');
    expect(archive.publishedSources.single.id, 's1');
    expect(archive.customFields.map((field) => field.id), ['f1']);
    expect(archive.choreographers.single.email, isNull);
    expect(archive.choreographers.single.location, isNull);
    expect(archive.choreographers.single.deceased, isFalse);
    expect(archive.dances.single.customFields.map((value) => value.fieldId), [
      'f1',
    ]);
  });

  test(
    'rejects unresolved references instead of emitting a dangling archive',
    () {
      final dance = Dance(
        id: 'd1',
        title: 'Dance',
        tagIds: const ['missing'],
        createdAt: _now,
        updatedAt: _now,
      );

      expect(
        () => buildDanceShareBundle(
          dance,
          choreographerFor: (_) => null,
          tagFor: (_) => null,
          publishedSourceFor: (_) => null,
          customFieldFor: (_) => null,
        ),
        throwsStateError,
      );
    },
  );

  test('uses safe names and the same payload for both extensions', () {
    final dance = Dance(
      id: 'd1',
      title: 'Rory/O\'More',
      createdAt: _now,
      updatedAt: _now,
    );
    ({String name, String json}) build(String extension) => (
      name: danceShareBundleFileName(dance.title, extension: extension),
      json: buildDanceShareBundle(
        dance,
        now: _now,
        choreographerFor: (_) => null,
        tagFor: (_) => null,
        publishedSourceFor: (_) => null,
        customFieldFor: (_) => null,
      ),
    );

    final ccshare = build(danceShareBundleExtension);
    final json = build(danceShareJsonExtension);
    expect(ccshare.name, 'Rory_O_More.ccshare');
    expect(json.name, 'Rory_O_More.json');
    expect(ccshare.json, json.json);
  });
}
