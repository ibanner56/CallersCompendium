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
  alternateTitles: ['Monymusk', 'Sir Archibald Grant of Monemusk'],
  barnesReference: 'BIII p. 92',
);

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
      ('a Barnes reference', sampleDance().copyWith(barnesReference: 'NiB')),
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

    test('bounds untrusted values instead of rejecting the dance', () {
      final body = _danceJson(sampleDance())
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
        choreographyFingerprintForDance(sampleDance()),
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
          alternateTitles: ['Monymusk', 'Sir Archibald Grant'],
          barnesReference: 'BIII p. 92',
        ),
      );
      await dances.create(
        sampleDance(
          id: 'nib',
          title: 'Unprinted',
        ).copyWith(barnesReference: 'NiB'),
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
