import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'package:compendium_core/src/serialization/archive_entity_codec.dart';
import 'reference_jcs_encoder.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

void main() {
  group('record blobs', () {
    test('encode canonicalizes bytes and decodes all nine kinds', () {
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
          SyncRecordKind.difficultyLevel,
          _difficultyLevel(),
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

      expect(body, containsPair('difficultyLevelId', isNull));
      expect(body, containsPair('rating', isNull));
      expect(
        body,
        containsPair(
          'formation',
          allOf(
            containsPair('shape', 'reverseProgressionImproper'),
            containsPair('detail', isNull),
          ),
        ),
      );
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

    test('rejects non-JSON body values at construction', () {
      for (final value in <Object?>[
        DateTime.utc(2026, 7, 15),
        Uri.parse('https://example.com'),
        double.infinity,
      ]) {
        expect(
          () => SyncRecordBlob(
            kind: SyncRecordKind.dance,
            id: 'd1',
            updatedAt: _stamp,
            deletedAt: null,
            existenceAt: _stamp,
            body: {'id': 'd1', 'title': value},
          ),
          throwsFormatException,
          reason: '$value',
        );
      }
    });

    test('shared entity builder keeps archive output unchanged', () {
      final archive = CompendiumArchive(exportedAt: _stamp, dances: [_dance()]);
      final archiveBody =
          (archiveToJson(archive)['dances']! as List<Object?>).single
              as Map<String, Object?>;
      expect(archiveBody, archiveDanceToJson(_dance(), const {}));
    });

    test('difficulty-level blobs retain tombstone envelope fields', () {
      final blob = syncRecordBlobForEntity(
        SyncRecordKind.difficultyLevel,
        _difficultyLevel(),
        updatedAt: _stamp,
        deletedAt: _stamp,
        existenceAt: _stamp,
      )!;

      expect(blob.deletedAt, _stamp);
      expect(blob.body, {
        'id': DifficultyLevel.intermediateId,
        'label': 'Intermediate',
        'position': 1,
      });
      expect(
        decodeSyncRecordBlob(encodeSyncRecordBlob(blob)).deletedAt,
        _stamp,
      );
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
        // `sync_id` (storeAddress) and `sync_device_id` (protocolIdentifier)
        // are the two keys the protocol puts on the wire, so they are the two
        // most likely to be mistaken for shareable. The spec's conformance
        // section (§9, Classification) names exactly this mutation — "no blob
        // … carries it (mutation: classify it `shareable`)" — but until they
        // were listed here the send side was unguarded. The inbound half is
        // caught by
        // `_isReceiveOnlySetting` (sync_admission.dart), which matches on the
        // key name rather than the class, so reclassifying either key turned
        // no test red.
        for (final key in [
          'editor_draft:d1',
          'unknown_runtime_key',
          'sync_id',
          'sync_device_id',
        ]) {
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
      // A manifest entry is `id -> content hash`, and the hash slot is the
      // only place a *value* could ride along: the id is an entity id or a
      // settings key name, `deviceId` is the `protocolIdentifier`, and `epoch`
      // is minted by the server (§7.1). That is why §9's classification
      // paragraph, which pins a `storeAddress` value against serialisation
      // under the mutation "classify it `shareable`", has a send-side guard
      // for the blob and none for the manifest: a manifest cannot carry a
      // settings value at all, so a guard under that mutation could never
      // fail (#1383).
      //
      // What the two expectations below pin, exactly, so this is not read as
      // more than it is: the RECORD-VALUE slot, at both ends — construction
      // rejects a non-hash string with `ArgumentError`, decoding with
      // `FormatException`. That one slot is pinned here because it was the one
      // the codec constrains and nothing exercised: the `42` case above never
      // reaches the hash check, because the string check in front of it throws
      // first, so relaxing `_validateHash` to "any non-empty string" left the
      // suite green.
      //
      // The other three slots are not pinned here and do not belong here. `v`
      // and `writtenAt` are already covered above. `deviceId` and `epoch` are
      // free-form strings by design — the wire format does not constrain them,
      // and inventing a constraint in the codec would assert something the
      // protocol does not say. What keeps a `storeAddress` out of them is that
      // the caller passes neither: `SyncCoordinator` holds `syncId` and
      // `deviceId` as separate fields and only ever passes `deviceId`
      // (`app/lib/src/sync/sync_coordinator.dart`), and `epoch` comes back from
      // the server. That is a coordinator-level property, so it is argued in
      // the PR rather than asserted here.
      expect(
        () => SyncManifest(
          deviceId: 'device-1',
          epoch: 'epoch-1',
          writtenAt: _stamp,
          records: {
            SyncRecordKind.setting: {'sync_id': 'grand-lake-oyster-catcher'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncManifest.fromJson({
          ...valid,
          'records': {
            'setting': {'sync_id': 'grand-lake-oyster-catcher'},
          },
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
  formation: const Formation(FormationShape.reverseProgressionImproper),
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

DifficultyLevel _difficultyLevel() => DifficultyLevel.intermediate;

Venue _venue() => Venue(id: 'v1', name: 'Hall', address1: 'private address');
