// A square dance's own fields (ADR-007 §8.1): what the record holds
// (`squareKind`), how its main part is repeated (`repeatOrder`), who the new
// partner is (`newPartner`) and whether it is a singing call (`singing`).
// They joined the unreleased schema v42 and archive v8, are kept for every
// form, and a dance that leaves them at their defaults encodes exactly as it
// did before they existed.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveDanceToJson;
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

const _squareKeys = [
  'squareKind',
  'repeatOrder',
  'repeatOrderText',
  'newPartner',
  'newPartnerText',
  'singing',
];

/// A square main part with every field off its default.
Dance _square() => sampleDance().copyWith(
  form: DanceForm.square,
  squareKind: SquareKind.patter,
  repeatOrder: SquareRepeatOrder.other,
  repeatOrderText: 'Heads twice, then sides once',
  newPartner: SquareNewPartner.other,
  newPartnerText: 'The original corner',
  singing: true,
);

Map<String, Object?> _danceJson(Dance dance) =>
    archiveDanceToJson(dance, const {}, includeOptionalFields: true);

void main() {
  group('model', () {
    test('the defaults are a main part with nothing stated', () {
      final dance = sampleDance();
      expect(dance.squareKind, SquareKind.main);
      expect(dance.repeatOrder, SquareRepeatOrder.unstated);
      expect(dance.repeatOrderText, '');
      expect(dance.newPartner, SquareNewPartner.unstated);
      expect(dance.newPartnerText, '');
      expect(dance.singing, isFalse);
    });

    test('the wire names are ADR-007 §8.1\'s, and an unknown one reads as '
        'nothing', () {
      expect(SquareKind.values.map((k) => k.wireName), [
        'main',
        'break',
        'patter',
      ]);
      expect(SquareRepeatOrder.values.map((o) => o.wireName), [
        'unstated',
        'HHSS',
        'HSHS',
        'allFour',
        'other',
      ]);
      expect(SquareNewPartner.values.map((p) => p.wireName), [
        'unstated',
        'none',
        'corner',
        'rightHandRole2',
        'opposite',
        'other',
      ]);
      expect(SquareKind.fromWireName('break'), SquareKind.breakPart);
      expect(SquareKind.fromWireName('breakPart'), isNull);
      expect(SquareRepeatOrder.fromWireName('hhss'), isNull);
      expect(SquareNewPartner.fromWireName(null), isNull);
    });

    test('a text is kept only with `other`, which it describes', () {
      final dance = _square();
      expect(dance.repeatOrderText, 'Heads twice, then sides once');
      expect(dance.newPartnerText, 'The original corner');
      final moved = dance.copyWith(
        repeatOrder: SquareRepeatOrder.headsSidesHeadsSides,
        newPartner: SquareNewPartner.corner,
      );
      expect(moved.repeatOrderText, '');
      expect(moved.newPartnerText, '');
      final built = sampleDance().copyWith(
        repeatOrderText: 'stray',
        newPartnerText: 'stray',
      );
      expect(built.repeatOrderText, '');
      expect(built.newPartnerText, '');
    });

    test('every dance holds the text bound, cut on a character boundary', () {
      final dance = _square().copyWith(
        repeatOrderText: '${'o' * (kMaxSquareDetailLength - 1)}\u{1F3BB}',
        newPartnerText: 'p' * (kMaxSquareDetailLength + 3),
      );
      expect(dance.repeatOrderText, 'o' * (kMaxSquareDetailLength - 1));
      expect(dance.newPartnerText, 'p' * kMaxSquareDetailLength);
    });

    test('they are kept for every form, so changing the form and back loses '
        'nothing', () {
      final square = _square();
      final contra = square.copyWith(form: DanceForm.contra);
      expect(contra.squareKind, SquareKind.patter);
      expect(contra.repeatOrderText, 'Heads twice, then sides once');
      expect(contra.newPartnerText, 'The original corner');
      expect(contra.singing, isTrue);
      expect(contra.copyWith(form: DanceForm.square), square);
    });

    test('copyWith and duplicate carry them, and each counts for '
        'equality', () {
      final dance = _square();
      final copy = dance.duplicate(newId: 'copy', now: DateTime.utc(2026, 2));
      expect(copy.squareKind, dance.squareKind);
      expect(copy.repeatOrder, dance.repeatOrder);
      expect(copy.repeatOrderText, dance.repeatOrderText);
      expect(copy.newPartner, dance.newPartner);
      expect(copy.newPartnerText, dance.newPartnerText);
      expect(copy.singing, isTrue);
      for (final changed in [
        dance.copyWith(squareKind: SquareKind.breakPart),
        dance.copyWith(repeatOrder: SquareRepeatOrder.allFour),
        dance.copyWith(repeatOrderText: 'Sides first'),
        dance.copyWith(newPartner: SquareNewPartner.opposite),
        dance.copyWith(newPartnerText: 'The right-hand robin'),
        dance.copyWith(singing: false),
      ]) {
        expect(dance, isNot(changed));
      }
    });
  });

  group('archive', () {
    test('round-trips them', () {
      final dance = _square();
      final read = decodeArchive(
        encodeArchive(
          CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
        ),
      );
      expect(read.errors, isEmpty);
      expect(read.archive.dances.single, dance);
    });

    test('a dance that leaves them at their defaults writes no new keys and '
        'keeps its earlier stamp', () {
      final dance = sampleDance().copyWith(form: DanceForm.square);
      final body = _danceJson(dance);
      for (final key in _squareKeys) {
        expect(body.keys, isNot(contains(key)), reason: key);
      }
      expect(
        requiredSchemaVersion(
          CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [dance]),
        ),
        lessThan(archiveSchemaVersionEcdDanceFields),
      );
    });

    for (final (name, dance) in [
      ('a break', sampleDance().copyWith(squareKind: SquareKind.breakPart)),
      (
        'a repeat order',
        sampleDance().copyWith(
          repeatOrder: SquareRepeatOrder.headsHeadsSidesSides,
        ),
      ),
      (
        'a new partner',
        sampleDance().copyWith(newPartner: SquareNewPartner.corner),
      ),
      ('a singing call', sampleDance().copyWith(singing: true)),
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

    test('an unknown value reads as the default, and an oversized text is '
        'cut, rather than failing the dance', () {
      final body = _danceJson(_square())
        ..['squareKind'] = 'medley'
        ..['repeatOrder'] = 'other'
        ..['repeatOrderText'] = 'o' * (kMaxSquareDetailLength + 1)
        ..['newPartner'] = 'nextButOne';
      final read = decodeArchive(
        jsonEncode({
          'schemaVersion': archiveSchemaVersionEcdDanceFields,
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'dances': [body],
        }),
      );
      expect(read.errors, isEmpty);
      final dance = read.archive.dances.single;
      expect(dance.squareKind, SquareKind.main);
      expect(dance.repeatOrderText, 'o' * kMaxSquareDetailLength);
      expect(dance.newPartner, SquareNewPartner.unstated);
      // The text describes `other`, so it goes with the value it described.
      expect(dance.newPartnerText, '');
    });
  });

  group('sync', () {
    SyncRecordBlob blobOf(Dance dance) => syncRecordBlobForEntity(
      SyncRecordKind.dance,
      dance,
      updatedAt: dance.updatedAt,
      existenceAt: dance.updatedAt,
    )!;

    test('a body that leaves them out sets them back to the defaults when '
        'applied', () {
      final blob = blobOf(sampleDance());
      for (final key in _squareKeys) {
        expect(blob.body.keys, isNot(contains(key)), reason: key);
      }
      final known = syncInboundKnownBody(blob);
      expect(known['squareKind'], 'main');
      expect(known['repeatOrder'], 'unstated');
      expect(known['repeatOrderText'], '');
      expect(known['newPartner'], 'unstated');
      expect(known['newPartnerText'], '');
      expect(known['singing'], false);
    });

    test('a body that carries them keeps them', () {
      final known = syncInboundKnownBody(blobOf(_square()));
      expect(known['squareKind'], 'patter');
      expect(known['repeatOrder'], 'other');
      expect(known['repeatOrderText'], 'Heads twice, then sides once');
      expect(known['newPartner'], 'other');
      expect(known['newPartnerText'], 'The original corner');
      expect(known['singing'], true);
    });

    test('the choreography fingerprint ignores them, as an older build '
        'does', () {
      expect(
        choreographyFingerprintForDance(_square()),
        choreographyFingerprintForDance(
          sampleDance().copyWith(form: DanceForm.square),
        ),
      );
    });
  });

  group('storage', () {
    test('a dance round-trips them, and clearing them sticks', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final dance = _square();
      await dances.create(dance);
      expect(await dances.getById(dance.id), dance);
      final cleared = dance.copyWith(
        squareKind: SquareKind.main,
        repeatOrder: SquareRepeatOrder.unstated,
        newPartner: SquareNewPartner.unstated,
        singing: false,
        updatedAt: DateTime.utc(2026, 3),
      );
      await dances.update(cleared);
      expect(await dances.getById(dance.id), cleared);
    });

    test(
      'a stored value this build does not know reads as the default',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final dances = DanceRepository(db, contraTaxonomy);
        final dance = _square();
        await dances.create(dance);
        await db.customStatement(
          "UPDATE dances SET square_kind = 'medley', "
          "repeat_order = 'HSSH', new_partner = 'nextButOne' WHERE id = ?",
          [dance.id],
        );
        final read = (await dances.getById(dance.id))!;
        expect(read.squareKind, SquareKind.main);
        expect(read.repeatOrder, SquareRepeatOrder.unstated);
        expect(read.repeatOrderText, '');
        expect(read.newPartner, SquareNewPartner.unstated);
        expect(read.singing, isTrue);
      },
    );
  });
}
