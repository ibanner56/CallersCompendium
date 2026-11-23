// A dance's other titles (`Dance.alternateTitles`, any form) and where its
// tune is printed in the Barnes books (`Dance.barnesReference`). Both joined
// the unreleased schema v42 and archive v8. Storage, backup, sync and search
// each carry them, and a dance without them encodes exactly as it did before
// they existed.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveDanceToJson;
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

Dance _named() => sampleDance().copyWith(
  form: DanceForm.ecd,
  alternateTitles: ['Monymusk', 'Sir Archibald Grant of Monemusk'],
  barnesReference: 'BIII p. 92',
);

/// A sample dance in the one form that keeps a Barnes reference.
Dance _ecd() => sampleDance().copyWith(form: DanceForm.ecd);

Map<String, Object?> _danceJson(Dance dance) =>
    archiveDanceToJson(dance, const {}, includeOptionalFields: true);

void main() {
  group('model', () {
    test('other titles are trimmed, joined to one line, and lose blanks and '
        'repeats, in the order given', () {
      expect(
        normalizeAlternateTitles([
          '  Monymusk ',
          '',
          '   ',
          'Sir Archibald\nGrant',
          'Monymusk',
          'Second  \t title',
        ]),
        ['Monymusk', 'Sir Archibald Grant', 'Second title'],
      );
      final dance = sampleDance().copyWith(
        alternateTitles: [' Monymusk', 'Monymusk ', ''],
      );
      expect(dance.alternateTitles, ['Monymusk']);
    });

    test('every dance holds the bounds: titles are cut on a character '
        'boundary and only the first ones kept', () {
      final titles = normalizeAlternateTitles([
        '${'t' * (kMaxAlternateTitleLength - 1)}\u{1F3BB}',
        for (var i = 0; i < kMaxAlternateTitles + 5; i++) 'Title $i',
      ]);
      expect(titles, hasLength(kMaxAlternateTitles));
      // The fiddle needs two code units and only one fits: it is dropped
      // whole, never left as half a surrogate pair.
      expect(titles.first, 't' * (kMaxAlternateTitleLength - 1));
      expect(titles.last, 'Title ${kMaxAlternateTitles - 2}');
      final dance = sampleDance().copyWith(
        alternateTitles: [for (var i = 0; i < 30; i++) 'T$i'],
      );
      expect(dance.alternateTitles, hasLength(kMaxAlternateTitles));
    });

    test('every dance holds the Barnes bound, counted in code units and cut '
        'on a character boundary', () {
      // 60 fiddles are 60 characters but 120 code units.
      final dance = _ecd().copyWith(barnesReference: '\u{1F3BB}' * 60);
      expect(dance.barnesReference, '\u{1F3BB}' * 50);
      final odd = _ecd().copyWith(
        barnesReference: '${'b' * (kMaxBarnesReferenceLength - 1)}\u{1F3BB}',
      );
      expect(odd.barnesReference, 'b' * (kMaxBarnesReferenceLength - 1));
    });

    test('only an English dance keeps a Barnes reference: another form '
        'clears it, whatever it was built from', () {
      expect(formHasBarnesReference(DanceForm.ecd), isTrue);
      expect([
        for (final form in DanceForm.values)
          if (form != DanceForm.ecd) formHasBarnesReference(form),
      ], everyElement(isFalse));
      final ecd = _named();
      expect(ecd.barnesReference, 'BIII p. 92');
      final contra = ecd.copyWith(form: DanceForm.contra);
      expect(contra.barnesReference, '');
      expect(contra.alternateTitles, ecd.alternateTitles);
      expect(
        sampleDance().copyWith(barnesReference: 'NiB').barnesReference,
        '',
      );
    });

    test('a column value reads back as the list it was written from', () {
      final titles = ['Monymusk', 'Sir Archibald Grant of Monemusk'];
      final text = alternateTitlesColumnText(titles);
      expect(text, 'Monymusk\nSir Archibald Grant of Monemusk');
      expect(alternateTitlesFromColumnText(text), titles);
      expect(alternateTitlesFromColumnText(''), isEmpty);
    });

    test('copyWith and duplicate carry both, and both count for '
        'equality', () {
      final dance = _named();
      expect(dance.copyWith(title: 'Money Musk').alternateTitles, [
        'Monymusk',
        'Sir Archibald Grant of Monemusk',
      ]);
      final copy = dance.duplicate(newId: 'copy', now: DateTime.utc(2026, 2));
      expect(copy.alternateTitles, dance.alternateTitles);
      expect(copy.barnesReference, 'BIII p. 92');
      expect(dance, isNot(dance.copyWith(barnesReference: 'NiB')));
      expect(dance, isNot(dance.copyWith(alternateTitles: ['Monymusk'])));
    });
  });

  group('archive', () {
    test('round-trips both', () {
      final dance = _named();
      final json = encodeArchive(
        CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
      );
      final read = decodeArchive(json);
      expect(read.errors, isEmpty);
      expect(read.archive.dances.single, dance);
    });

    test('a dance without them writes no new keys and keeps its earlier '
        'stamp', () {
      final dance = sampleDance();
      final body = _danceJson(dance);
      expect(body.keys, isNot(contains('alternateTitles')));
      expect(body.keys, isNot(contains('barnesReference')));
      expect(
        requiredSchemaVersion(
          CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
        ),
        lessThan(archiveSchemaVersionEcdDanceFields),
      );
    });

    for (final (name, dance) in [
      ('an other title', sampleDance().copyWith(alternateTitles: ['Other'])),
      ('a Barnes reference', _ecd().copyWith(barnesReference: 'NiB')),
    ]) {
      test('$name alone stamps v8, so an older reader warns rather than '
          'dropping it', () {
        expect(
          requiredSchemaVersion(
            CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
          ),
          archiveSchemaVersionEcdDanceFields,
        );
      });
    }

    test('a file that gives a contra dance a Barnes reference loses it on '
        'read', () {
      final body = _danceJson(sampleDance())..['barnesReference'] = 'NiB';
      final read = decodeArchive(
        jsonEncode({
          'schemaVersion': archiveSchemaVersionEcdDanceFields,
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'dances': [body],
        }),
      );
      expect(read.errors, isEmpty);
      expect(read.archive.dances.single.barnesReference, '');
    });

    test('bounds untrusted values instead of rejecting the dance', () {
      final body = _danceJson(_ecd())
        ..['alternateTitles'] = [
          't' * (kMaxAlternateTitleLength + 5),
          ' ',
          for (var i = 0; i < kMaxAlternateTitles + 5; i++) 'Title $i',
        ]
        ..['barnesReference'] = 'b' * (kMaxBarnesReferenceLength + 1);
      final read = decodeArchive(
        jsonEncode({
          'schemaVersion': archiveSchemaVersionEcdDanceFields,
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'dances': [body],
        }),
      );
      expect(read.errors, isEmpty);
      final dance = read.archive.dances.single;
      expect(dance.alternateTitles, hasLength(kMaxAlternateTitles));
      expect(dance.alternateTitles.first, 't' * kMaxAlternateTitleLength);
      expect(dance.alternateTitles[1], 'Title 0');
      expect(dance.barnesReference, 'b' * kMaxBarnesReferenceLength);
    });
  });

  group('sync', () {
    SyncRecordBlob blobOf(Dance dance) => syncRecordBlobForEntity(
      SyncRecordKind.dance,
      dance,
      updatedAt: dance.updatedAt,
      existenceAt: dance.updatedAt,
    )!;

    test('a body that leaves them out clears them when applied', () {
      final blob = blobOf(sampleDance());
      expect(blob.body.keys, isNot(contains('alternateTitles')));
      expect(blob.body.keys, isNot(contains('barnesReference')));
      final known = syncInboundKnownBody(blob);
      expect(known['alternateTitles'], isEmpty);
      expect(known['barnesReference'], '');
    });

    test('a body that carries them keeps them', () {
      final known = syncInboundKnownBody(blobOf(_named()));
      expect(known['alternateTitles'], [
        'Monymusk',
        'Sir Archibald Grant of Monemusk',
      ]);
      expect(known['barnesReference'], 'BIII p. 92');
    });

    test('the choreography fingerprint ignores them, as an older build '
        'does', () {
      expect(
        choreographyFingerprintForDance(_named()),
        choreographyFingerprintForDance(_ecd()),
      );
    });
  });

  group('storage', () {
    test('a dance round-trips both', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final dance = _named();
      await dances.create(dance);
      expect(await dances.getById(dance.id), dance);
      final cleared = dance.copyWith(
        alternateTitles: const [],
        barnesReference: '',
        updatedAt: DateTime.utc(2026, 3),
      );
      await dances.update(cleared);
      expect(await dances.getById(dance.id), cleared);
    });
  });

  group('search', () {
    late CompendiumDatabase db;
    late DanceRepository dances;

    setUp(() async {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
      await dances.create(
        sampleDance(id: 'money', title: 'Money Musk').copyWith(
          form: DanceForm.ecd,
          alternateTitles: ['Monymusk', 'Sir Archibald Grant'],
          barnesReference: 'BIII p. 92',
        ),
      );
      await dances.create(
        sampleDance(
          id: 'nib',
          title: 'Unprinted',
        ).copyWith(form: DanceForm.ecd, barnesReference: 'NiB'),
      );
      await dances.create(sampleDance(id: 'plain', title: 'Plain Dance'));
    });
    tearDown(() => db.close());

    test('the Title scope finds a dance by any of its other titles', () async {
      expect(
        await dances.search(
          const FullTextFilter('Monymusk', scope: FullTextScope.title),
        ),
        ['money'],
      );
      // A short word must start a word, here the first of the second title.
      expect(
        await dances.search(
          const FullTextFilter('Si', scope: FullTextScope.title),
        ),
        ['money'],
      );
      expect(
        await dances.search(
          const FullTextFilter('Archibald musk', scope: FullTextScope.title),
        ),
        ['money'],
      );
    });

    test('All fields finds other titles and the Barnes reference', () async {
      expect(await dances.search(const FullTextFilter('Archibald')), ['money']);
      expect(await dances.search(const FullTextFilter('BIII')), ['money']);
      expect(await dances.search(const FullTextFilter('92')), ['money']);
      expect(await dances.search(const FullTextFilter('nib')), ['nib']);
    });

    test('the Author and Figure scopes do not read them', () async {
      expect(
        await dances.search(
          const FullTextFilter('Monymusk', scope: FullTextScope.author),
        ),
        isEmpty,
      );
      expect(
        await dances.search(
          const FullTextFilter('BIII', scope: FullTextScope.figure),
        ),
        isEmpty,
      );
    });
  });
}
