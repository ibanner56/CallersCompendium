import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'package:compendium_core/src/serialization/archive_entity_codec.dart';
import 'reference_jcs_encoder.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

void main() {
  group('record blobs', () {
    test('encode canonicalizes bytes and decodes all eight kinds', () {
      final blobs = <SyncRecordBlob>[
        syncRecordBlobForEntity(
          SyncRecordKind.dance,
          _dance(),
          updatedAt: _stamp,
          existenceAt: _stamp,
          allowedCustomFieldIds: {'cf'},
        )!,
        syncRecordBlobForEntity(
          SyncRecordKind.program,
          _program(),
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!,
        syncRecordBlobForEntity(
          SyncRecordKind.choreographer,
          _choreographer(),
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!,
        syncRecordBlobForEntity(
          SyncRecordKind.tag,
          _tag(),
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!,
        syncRecordBlobForEntity(
          SyncRecordKind.publishedSource,
          _source(),
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!,
        syncRecordBlobForEntity(
          SyncRecordKind.customFieldDef,
          _customField(),
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!,
        syncRecordBlobForEntity(
          SyncRecordKind.venue,
          _venue(),
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!,
        SyncSettingsRecord(
          key: 'custom_dialects',
          value: null,
          updatedAt: _stamp,
          deletedAt: null,
          existenceAt: _stamp,
        ).toBlob()!,
      ];

      for (final blob in blobs) {
        final encoded = encodeSyncRecordBlob(blob);
        expect(
          encoded,
          referenceJcsEncode(blob.toJson()),
          reason: blob.kind.name,
        );
        expect(
          encodeSyncRecordBlobUtf8(blob),
          utf8.encode(encoded),
          reason: blob.kind.name,
        );
        final decoded = decodeSyncRecordBlob(encoded);
        expect(encodeSyncRecordBlob(decoded), encoded);
        expect(decoded.kind, blob.kind);
        expect(decoded.id, blob.id);
      }
    });

    test('keeps shareable nulls present and device-local values absent', () {
      final body = syncBodyForEntity(
        SyncRecordKind.dance,
        _dance(),
        allowedCustomFieldIds: {'cf'},
      );

      expect(body, containsPair('level', isNull));
      expect(body, containsPair('rating', isNull));
      expect(body, containsPair('formation', containsPair('detail', isNull)));
      expect(body, containsPair('authorIds', ['c1', 'c2']));
      expect(body, containsPair('tagIds', ['t1', 't2']));
      final venueBody = syncBodyForEntity(SyncRecordKind.venue, _venue());
      expect(venueBody, isNot(contains('address1')));
    });

    test('keeps null shareable structural fields explicit', () {
      for (final entry in {
        SyncRecordKind.dance: _dance(),
        SyncRecordKind.program: _program(),
        SyncRecordKind.venue: _venue(),
      }.entries) {
        final blob = syncRecordBlobForEntity(
          entry.key,
          entry.value,
          updatedAt: _stamp,
          existenceAt: _stamp,
        )!;
        expect(
          blob.body,
          containsPair('provenance', isNull),
          reason: entry.key.name,
        );
        expect(
          encodeSyncRecordBlob(blob),
          contains('"provenance":null'),
          reason: entry.key.name,
        );
      }
    });

    test('freezes nested body data after validation', () {
      final provenance = <String, Object?>{'source': 'manual'};
      final links = <Object?>[
        <String, Object?>{'id': 'l1', 'kind': 'reference'},
      ];
      final body = <String, Object?>{
        'id': 'd1',
        'title': 'Dance',
        'provenance': provenance,
        'links': links,
      };
      final blob = SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: 'd1',
        updatedAt: _stamp,
        deletedAt: null,
        existenceAt: _stamp,
        body: body,
      );
      final encoded = encodeSyncRecordBlob(blob);

      provenance['futurePrivateField'] = 'secret';
      (links.single! as Map<String, Object?>)['futurePrivateField'] = 'secret';

      expect(encodeSyncRecordBlob(blob), encoded);
      expect(
        () => (blob.body['provenance']! as Map<String, Object?>)['x'] = 'y',
        throwsUnsupportedError,
      );
    });

    test('shared entity builder keeps archive output unchanged', () {
      final archive = CompendiumArchive(exportedAt: _stamp, dances: [_dance()]);
      final archiveBody =
          (archiveToJson(archive)['dances']! as List<Object?>).single
              as Map<String, Object?>;
      expect(archiveBody, archiveDanceToJson(_dance(), const {}));
    });

    group('entity admission', () {
      test('omits non-shareable custom-field definitions', () {
        expect(
          syncRecordBlobForEntity(
            SyncRecordKind.customFieldDef,
            _customField(shareable: false),
            updatedAt: _stamp,
            existenceAt: _stamp,
          ),
          isNull,
        );
      });
    });
  });

  group('settings records', () {
    test('uses key identity and preserves JSON null in body.value', () {
      final record = SyncSettingsRecord(
        key: 'custom_dialects',
        value: null,
        updatedAt: _stamp,
        deletedAt: null,
        existenceAt: _stamp,
      );
      final blob = record.toBlob();
      expect(blob, isNotNull);
      expect(blob!.id, 'custom_dialects');
      expect(blob.body, containsPair('value', isNull));
      expect(
        encodeSyncSettingsRecord(record),
        '{"body":{"value":null},"deletedAt":null,'
        '"existenceAt":"2026-07-15T12:00:00.000Z",'
        '"id":"custom_dialects","kind":"setting",'
        '"updatedAt":"2026-07-15T12:00:00.000Z","v":1}',
      );
    });

    test(
      'fails closed for non-shareable, unknown, and prefix-classified keys',
      () {
        for (final key in ['editor_draft:d1', 'unknown_runtime_key']) {
          expect(
            SyncSettingsRecord(
              key: key,
              value: 'secret',
              updatedAt: _stamp,
              deletedAt: null,
              existenceAt: _stamp,
            ).toBlob(),
            isNull,
            reason: key,
          );
        }
        expect(
          SyncSettingsRecord(
            key: 'custom_dialects',
            value: 'allowed',
            updatedAt: _stamp,
            deletedAt: null,
            existenceAt: _stamp,
          ).toBlob(),
          isNotNull,
        );
      },
    );
  });

  group('manifests', () {
    test('nests same ids under their distinct kinds', () {
      final hash = 'a' * 64;
      final manifest = SyncManifest(
        deviceId: 'device-1',
        epoch: 'epoch-1',
        writtenAt: _stamp,
        records: {
          SyncRecordKind.dance: {'same-id': hash},
          SyncRecordKind.program: {'same-id': hash},
        },
      );
      final encoded = encodeSyncManifest(manifest);
      expect(encoded, contains('"dance":{"same-id":"$hash"'));
      expect(encoded, contains('"program":{"same-id":"$hash"'));
      expect(encodeSyncManifest(decodeSyncManifest(encoded)), encoded);
    });
  });

  group('strict decoding', () {
    test('rejects malformed required record envelope fields', () {
      final valid = _danceBlob().toJson();
      final missingFields = [
        'v',
        'kind',
        'id',
        'updatedAt',
        'deletedAt',
        'existenceAt',
        'body',
      ];
      for (final field in missingFields) {
        final malformed = Map<String, Object?>.from(valid)..remove(field);
        expect(
          () => SyncRecordBlob.fromJson(malformed),
          throwsFormatException,
          reason: 'missing $field',
        );
      }
      for (final field in [
        'v',
        'kind',
        'id',
        'updatedAt',
        'existenceAt',
        'body',
      ]) {
        final malformed = Map<String, Object?>.from(valid)..[field] = null;
        expect(
          () => SyncRecordBlob.fromJson(malformed),
          throwsFormatException,
          reason: 'null $field',
        );
      }
      expect(
        () => SyncRecordBlob.fromJson({...valid, 'kind': 'future'}),
        throwsFormatException,
      );
      expect(
        () => SyncRecordBlob.fromJson({...valid, 'v': 99}),
        throwsFormatException,
      );
      expect(
        () => SyncRecordBlob.fromJson({
          ...valid,
          'updatedAt': '2026-07-15T12:00:00.500Z',
        }),
        throwsFormatException,
      );
      expect(
        () => SyncRecordBlob.fromJson({
          ...valid,
          'updatedAt': '2026-07-15T12:00:00+01:00',
        }),
        throwsFormatException,
      );
      expect(
        () => SyncRecordBlob.fromJson({
          ...valid,
          'deletedAt': '2026-07-15T12:00:00.001Z',
        }),
        throwsFormatException,
      );
      expect(
        () => SyncRecordBlob.fromJson({
          ...valid,
          'existenceAt': '2026-07-15T12:00:00.001Z',
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed manifest fields and entries', () {
      final valid = SyncManifest(
        deviceId: 'device-1',
        epoch: 'epoch-1',
        writtenAt: _stamp,
        records: {
          SyncRecordKind.dance: {'d1': 'a' * 64},
        },
      ).toJson();
      for (final field in ['v', 'deviceId', 'epoch', 'writtenAt', 'records']) {
        final malformed = Map<String, Object?>.from(valid)..remove(field);
        expect(
          () => SyncManifest.fromJson(malformed),
          throwsFormatException,
          reason: 'missing $field',
        );
      }
      expect(
        () => SyncManifest.fromJson({
          ...valid,
          'records': {
            'dance': {'d1': 42},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => SyncManifest.fromJson({
          ...valid,
          'records': {
            'dance': <Object?, Object?>{1: 'a' * 64},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => SyncManifest.fromJson({
          ...valid,
          'records': <String, Object?>{'future': <String, Object?>{}},
        }),
        throwsFormatException,
      );
      expect(
        () => SyncManifest.fromJson({
          ...valid,
          'writtenAt': '2026-07-15T12:00:00.001Z',
        }),
        throwsFormatException,
      );
    });
  });
}

SyncRecordBlob _danceBlob() => syncRecordBlobForEntity(
  SyncRecordKind.dance,
  _dance(),
  updatedAt: _stamp,
  existenceAt: _stamp,
  allowedCustomFieldIds: {'cf'},
)!;

Dance _dance() => Dance(
  id: 'd1',
  title: 'Shared Dance',
  authorIds: const ['c1', 'c2'],
  formation: const Formation(FormationShape.becketCw),
  tagIds: const ['t1', 't2'],
  customFields: [CustomFieldValue(fieldId: 'cf', value: 1.25)],
  createdAt: _stamp,
  updatedAt: _stamp,
);

Program _program() => Program(
  id: 'p1',
  title: 'Shared Program',
  slots: [ProgramSlot(id: 'slot-1', position: 0, text: 'Break')],
  createdAt: _stamp,
  updatedAt: _stamp,
);

Choreographer _choreographer() =>
    Choreographer(id: 'c1', name: 'Caller', email: 'private@example.com');

Tag _tag() => Tag(id: 't1', name: 'Tag');

PublishedSource _source() => PublishedSource(id: 's1', title: 'Source');

CustomFieldDef _customField({bool shareable = true}) => CustomFieldDef(
  id: 'cf',
  key: 'tempo',
  label: 'Tempo',
  type: CustomFieldType.number,
  shareable: shareable,
);

Venue _venue() => Venue(id: 'v1', name: 'Hall', address1: 'private address');
