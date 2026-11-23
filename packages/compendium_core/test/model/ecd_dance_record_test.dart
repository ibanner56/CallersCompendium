// ECD's additions to the dance record (ADR-006 §12, F2 and F3; Q16): the
// formation shapes, the proper/improper flag, meter and key, and the half-bar
// rule. Storage, backup and sync each carry them, and a dance without them
// encodes exactly as it did before they existed.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveDanceToJson;
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

Dance _ecdDance() => sampleDance().copyWith(
  form: DanceForm.ecd,
  formation: const Formation(FormationShape.dupleMinor, improper: true),
  meter: '3/2',
  musicalKey: 'G minor',
);

Map<String, Object?> _danceJson(Dance dance) =>
    archiveDanceToJson(dance, const {}, includeOptionalFields: true);

void main() {
  group('formation shapes by form', () {
    test('ECD offers the maintainer\'s shapes, with no Becket circle', () {
      expect(offeredFormationShapes(DanceForm.ecd), [
        FormationShape.dupleMinor,
        FormationShape.tripleMinor,
        FormationShape.twoCoupleSet,
        FormationShape.threeCoupleLongways,
        FormationShape.fourCoupleLongways,
        FormationShape.fiveCoupleLongways,
        FormationShape.sixCoupleLongways,
        FormationShape.circle,
        FormationShape.sicilianCircle,
        FormationShape.square,
        FormationShape.other,
      ]);
      expect(
        offeredFormationShapes(DanceForm.ecd),
        isNot(contains(FormationShape.becketCw)),
      );
      expect(
        offeredFormationShapes(DanceForm.ecd),
        isNot(contains(FormationShape.becketCcw)),
      );
    });

    test('contra offers exactly the shapes it had before ECD\'s', () {
      expect(
        offeredFormationShapes(DanceForm.contra),
        FormationShape.values.sublist(
          0,
          FormationShape.values.indexOf(FormationShape.dupleMinor),
        ),
      );
      for (final shape in ecdFormationShapes) {
        if (shape == FormationShape.tripleMinor ||
            shape == FormationShape.sicilianCircle ||
            shape == FormationShape.other) {
          continue;
        }
        expect(contraFormationShapes, isNot(contains(shape)));
      }
    });

    test('a square offers the square set first, a circle and other '
        '(ADR-007 §8.1)', () {
      expect(offeredFormationShapes(DanceForm.square), [
        FormationShape.square,
        FormationShape.circle,
        FormationShape.other,
      ]);
      // Every one is also an ECD shape or shared, so no new value is stored.
      for (final shape in squareFormationShapes) {
        expect(
          ecdFormationShapes.contains(shape) ||
              contraFormationShapes.contains(shape),
          isTrue,
          reason: shape.name,
        );
      }
    });

    test('a dance of a form without the flag never holds improper', () {
      final ecd = _ecdDance();
      expect(ecd.formation.improper, isTrue);
      final contra = ecd.copyWith(form: DanceForm.contra);
      expect(contra.formation.improper, isFalse);
      expect(contra.formation.shape, FormationShape.dupleMinor);
      expect(
        sampleDance()
            .copyWith(
              formation: const Formation(
                FormationShape.dupleImproper,
                improper: true,
              ),
            )
            .formation
            .improper,
        isFalse,
      );
    });

    test('only ECD has a proper/improper flag', () {
      expect(formHasImproperFlag(DanceForm.ecd), isTrue);
      expect(formHasImproperFlag(DanceForm.contra), isFalse);
      expect(formHasImproperFlag(DanceForm.square), isFalse);
    });

    test('improper is part of a formation\'s identity, and defaults to '
        'proper', () {
      const proper = Formation(FormationShape.dupleMinor);
      expect(proper.improper, isFalse);
      expect(proper.copyWith(improper: true), isNot(proper));
      expect(
        proper.copyWith(improper: true).copyWith(detail: 'x').improper,
        isTrue,
      );
    });
  });

  group('archive', () {
    test('round-trips meter, key, improper and an ECD shape', () {
      final dance = _ecdDance();
      final json = encodeArchive(
        CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
      );
      final read = decodeArchive(json);
      expect(read.errors, isEmpty);
      expect(read.archive.dances.single, dance);
      expect(
        (jsonDecode(json) as Map)['schemaVersion'],
        archiveSchemaVersionEcdDanceFields,
      );
    });

    test('a dance without them encodes byte-identically to before: no new '
        'keys, and no stamp', () {
      final dance = sampleDance();
      final body = _danceJson(dance);
      expect(body.keys, isNot(contains('meter')));
      expect(body.keys, isNot(contains('musicalKey')));
      expect((body['formation']! as Map).keys, isNot(contains('improper')));
      expect(
        requiredSchemaVersion(
          CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
        ),
        lessThan(archiveSchemaVersionEcdDanceFields),
      );
    });

    for (final (name, dance) in [
      ('meter', sampleDance().copyWith(meter: '6/8')),
      ('key', sampleDance().copyWith(musicalKey: 'D')),
      (
        'improper',
        sampleDance().copyWith(
          form: DanceForm.ecd,
          formation: const Formation(
            FormationShape.tripleMinor,
            improper: true,
          ),
        ),
      ),
      (
        'an ECD shape',
        sampleDance().copyWith(
          formation: const Formation(FormationShape.circle),
        ),
      ),
    ]) {
      test('$name alone stamps v8', () {
        expect(
          requiredSchemaVersion(
            CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
          ),
          archiveSchemaVersionEcdDanceFields,
        );
      });
    }

    test('clamps an overlong meter or key instead of rejecting the dance', () {
      final body = _danceJson(sampleDance())
        ..['meter'] = 'm' * (kMaxMusicLabelLength + 5)
        ..['musicalKey'] = 'k' * (kMaxMusicLabelLength + 1);
      final read = decodeArchive(
        jsonEncode({
          'schemaVersion': archiveSchemaVersionEcdDanceFields,
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'dances': [body],
        }),
      );
      expect(read.errors, isEmpty);
      final dance = read.archive.dances.single;
      expect(dance.meter, 'm' * kMaxMusicLabelLength);
      expect(dance.musicalKey, 'k' * kMaxMusicLabelLength);
    });
  });

  group('sync', () {
    SyncRecordBlob blobOf(Dance dance) => syncRecordBlobForEntity(
      SyncRecordKind.dance,
      dance,
      updatedAt: dance.updatedAt,
      existenceAt: dance.updatedAt,
    )!;

    test('a body that leaves out meter, key and improper clears them when '
        'applied', () {
      final cleared = _ecdDance().copyWith(
        meter: '',
        musicalKey: '',
        formation: const Formation(FormationShape.dupleMinor),
      );
      final blob = blobOf(cleared);
      expect(blob.body.keys, isNot(contains('meter')));
      final known = syncInboundKnownBody(blob);
      expect(known['meter'], '');
      expect(known['musicalKey'], '');
      expect((known['formation']! as Map)['improper'], isFalse);
    });

    test('a body that carries them keeps them', () {
      final known = syncInboundKnownBody(blobOf(_ecdDance()));
      expect(known['meter'], '3/2');
      expect(known['musicalKey'], 'G minor');
      expect((known['formation']! as Map)['improper'], isTrue);
    });

    test('the choreography fingerprint ignores them, as an older build '
        'does', () {
      final plain = sampleDance().copyWith(
        form: DanceForm.ecd,
        formation: const Formation(FormationShape.dupleMinor),
      );
      expect(
        choreographyFingerprintForDance(_ecdDance()),
        choreographyFingerprintForDance(plain),
      );
      expect(
        choreographyFingerprintForDance(
          plain.copyWith(formation: const Formation(FormationShape.circle)),
        ),
        isNot(choreographyFingerprintForDance(plain)),
      );
    });
  });

  group('storage', () {
    test('a dance round-trips meter, key, improper and an ECD shape', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final dance = _ecdDance();
      await dances.create(dance);
      expect(await dances.getById(dance.id), dance);
    });
  });

  group('half bars (Q16)', () {
    test('half a bar is allowed only where it is a whole number of beats', () {
      final duple = PhraseStructure.parse('4*8*2');
      expect(duple.components.single.allowsHalfBars, isTrue);
      expect(duple.beatsForHalfBars(1), 1);
      expect(duple.beatsForHalfBars(4), 4);

      final triple = PhraseStructure.parse('4*8*3');
      expect(triple.components.single.allowsHalfBars, isFalse);
      expect(triple.beatsForHalfBars(1), isNull);
      expect(triple.beatsForHalfBars(3), isNull);
      expect(triple.beatsForHalfBars(2), 3, reason: 'one whole bar');
      expect(triple.beatsForHalfBars(8), 12);
    });

    test('reads the meter of the part playing at the given beat', () {
      // Two 8-bar phrases in triple time, then two in duple.
      final mixed = PhraseStructure.parse('2*8*3 + 2*8*2');
      expect(mixed.beatsForHalfBars(1, atBeat: 0), isNull);
      expect(mixed.beatsForHalfBars(1, atBeat: 48), 1);
      // Wraps at the end of the structure, as phrase labels do.
      expect(mixed.beatsForHalfBars(1, atBeat: 80), isNull);
      expect(mixed.componentAtBeat(47).beatsPerBar, 3);
      expect(mixed.componentAtBeat(48).beatsPerBar, 2);
    });
  });
}
