// What an older build keeps of a newer build's record, and that it can put it
// back exactly (spec §6.7). The round trip is the property everything else
// rests on: if merging the kept parts into the known part does not reproduce
// the peer's body byte for byte, this device's wire hash for the record
// differs from the peer's at the same `updatedAt`, and the record never agrees.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

Map<String, Object?> _body(SyncRecordKind kind, Object entity) =>
    syncBodyForEntity(kind, entity, allowedCustomFieldIds: {'cf'});

Map<String, Object?> _danceBody() => _body(
  SyncRecordKind.dance,
  Dance(
    id: 'd1',
    title: 'Shared Dance',
    formation: const Formation(FormationShape.reverseProgressionImproper),
    customFields: [CustomFieldValue(fieldId: 'cf', value: 1.25)],
    links: [
      DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://example.com'),
    ],
    figures: [
      Figure(move: 'swing', params: const {'beats': 8}),
    ],
    createdAt: _stamp,
    updatedAt: _stamp,
  ),
);

Map<String, Object?> _programBody() => _body(
  SyncRecordKind.program,
  Program(
    id: 'p1',
    title: 'Shared Program',
    slots: [
      ProgramSlot(id: 's1', position: 0, text: 'Break'),
      ProgramSlot(id: 's2', position: 1, text: 'Waltz'),
    ],
    createdAt: _stamp,
    updatedAt: _stamp,
  ),
);

Map<String, Object?> _copy(Map<String, Object?> body) =>
    (jsonDecode(canonicalJson(body)) as Map).cast<String, Object?>();

void _expectRoundTrip(SyncRecordKind kind, Map<String, Object?> body) {
  final split = partitionInboundRecordBody(kind, body);
  expect(split.refusedPath, isNull);
  expect(split.retained, isNotNull, reason: 'nothing was kept');
  expect(
    validateShareableRecordBody(kind, split.known).isValid,
    isTrue,
    reason: 'the known part still carries ${split.known}',
  );
  expect(
    canonicalJson(mergeRetainedFields(split.known, split.retained!)),
    canonicalJson(body),
  );
}

void main() {
  group('a part this build does not sync is kept and put back exactly', () {
    test('at the top level', () {
      _expectRoundTrip(
        SyncRecordKind.program,
        _programBody()
          ..['payMinorUnitsV2'] = 1250
          ..['addedLater'] = null,
      );
    });

    test('inside a nested object', () {
      final body = _danceBody();
      body['formation'] = {
        ...(body['formation']! as Map<String, Object?>),
        'handedness': 'left',
      };
      _expectRoundTrip(SyncRecordKind.dance, body);
    });

    test('inside items of every id-keyed list', () {
      final dance = _danceBody();
      for (final key in ['customFields', 'links']) {
        dance[key] = [
          for (final item in dance[key]! as List)
            {...(item as Map<String, Object?>), 'addedLater': key},
        ];
      }
      _expectRoundTrip(SyncRecordKind.dance, dance);

      final program = _programBody();
      program['slots'] = [
        for (final item in program['slots']! as List)
          {...(item as Map<String, Object?>), 'cue': 'x'},
      ];
      _expectRoundTrip(SyncRecordKind.program, program);
    });

    test('a field this build knows but keeps private', () {
      // A newer build may share a choreographer's email; this one never
      // writes the peer's value into its own private field.
      final body = _body(
        SyncRecordKind.choreographer,
        Choreographer(id: 'c1', name: 'Caller'),
      )..['email'] = 'shared@example.com';
      final split = partitionInboundRecordBody(
        SyncRecordKind.choreographer,
        body,
      );
      expect(split.known.containsKey('email'), isFalse);
      _expectRoundTrip(SyncRecordKind.choreographer, body);
    });

    test('kept parts survive a canonical JSON round trip', () {
      final body = _programBody()..['addedLater'] = {'b': 1, 'a': 2.5};
      final split = partitionInboundRecordBody(SyncRecordKind.program, body);
      final stored = _copy(split.retained!);
      expect(
        canonicalJson(mergeRetainedFields(split.known, stored)),
        canonicalJson(body),
      );
    });
  });

  group('a part with nowhere to go back is refused', () {
    test('a key a newer build added to a figure', () {
      final body = _danceBody();
      body['figures'] = [
        for (final figure in body['figures']! as List)
          {...(figure as Map<String, Object?>), 'handHold': 'cross'},
      ];
      expect(
        partitionInboundRecordBody(SyncRecordKind.dance, body).refusedPath,
        'figures.handHold',
      );
    });

    test('a key inside a container figure\'s children', () {
      final body = _danceBody()
        ..['figures'] = [
          {
            'schemaVersion': 1,
            'move': meanwhileMove,
            'params': {
              'beats': 8,
              'figures': [
                {'schemaVersion': 1, 'move': 'swing', 'addedLater': true},
              ],
            },
          },
        ];
      expect(
        partitionInboundRecordBody(SyncRecordKind.dance, body).refusedPath,
        'figures.params.figures.addedLater',
      );
    });

    test('a newer figure schema or custom origin', () {
      for (final (figure, path) in [
        (
          {'schemaVersion': figureSchemaVersion + 1, 'move': 'swing'},
          'figures.schemaVersion',
        ),
        (
          {'schemaVersion': 1, 'move': 'swing', 'customOrigin': 'aiDrafted'},
          'figures.customOrigin',
        ),
      ]) {
        final body = _danceBody()..['figures'] = [figure];
        expect(
          partitionInboundRecordBody(SyncRecordKind.dance, body).refusedPath,
          path,
        );
      }
    });

    test('a tune that is no longer a string', () {
      final body = _danceBody()
        ..['tunes'] = [
          {'title': 'Reel'},
        ];
      expect(
        partitionInboundRecordBody(SyncRecordKind.dance, body).refusedPath,
        'tunes',
      );
    });

    test('a kept part on a list item with no usable id', () {
      final body = _programBody();
      body['slots'] = [
        for (final item in body['slots']! as List)
          {
            for (final entry in (item as Map<String, Object?>).entries)
              if (entry.key != 'id') entry.key: entry.value,
            'cue': 'x',
          },
      ];
      expect(
        partitionInboundRecordBody(SyncRecordKind.program, body).refusedPath,
        'slots.cue',
      );
    });

    test('every figure key this build writes is one it accepts', () {
      // Ties [figureJsonKeys] to the encoder, so a key added to figureToJson
      // without the set refuses this build's own figures.
      final written = figureToJson(
        Figure(
          move: 'swing',
          params: const {'beats': 8},
          note: 'n',
          progression: true,
          customOrigin: CustomOrigin.importGap,
          assumedSubject: true,
          walkthroughOverride: 'w',
          wordingOverride: 'o',
        ),
      );
      expect(figureJsonKeys, containsAll(written.keys));
      expect(unsupportedFigurePath([written]), isNull);
    });
  });

  test('a body with nothing to keep keeps nothing', () {
    final split = partitionInboundRecordBody(
      SyncRecordKind.dance,
      _danceBody(),
    );
    expect(split.retained, isNull);
    expect(split.refusedPath, isNull);
    expect(canonicalJson(split.known), canonicalJson(_danceBody()));
  });

  test('a kept part whose place is gone is dropped with it', () {
    final body = _programBody();
    body['slots'] = [
      for (final item in body['slots']! as List)
        {...(item as Map<String, Object?>), 'cue': 'x'},
    ];
    final split = partitionInboundRecordBody(SyncRecordKind.program, body);
    // This device has since removed slot s1.
    final edited = Map<String, Object?>.of(split.known)
      ..['slots'] = [(split.known['slots']! as List)[1]];
    final merged = mergeRetainedFields(edited, split.retained!);
    final slots = merged['slots']! as List;
    expect(slots, hasLength(1));
    expect((slots.single as Map)['cue'], 'x');
    expect((slots.single as Map)['id'], 's2');
  });

  group('settings', () {
    test('a key this build does not sync is kept whole', () {
      final split = partitionInboundRecordBody(SyncRecordKind.setting, {
        'value': 1,
      }, settingsKey: 'a_setting_added_later');
      expect(split.wholeRecord, isTrue);
      expect(split.refusedPath, isNull);
    });

    test('the transport keys are never kept', () {
      for (final key in ['sync_id', 'sync_device_id']) {
        final split = partitionInboundRecordBody(SyncRecordKind.setting, {
          'value': 'x',
        }, settingsKey: key);
        expect(split.wholeRecord, isFalse, reason: key);
        expect(split.refusedPath, 'value', reason: key);
      }
    });

    test('a shared key splits like any body', () {
      final split = partitionInboundRecordBody(SyncRecordKind.setting, {
        'value': 1,
        'addedLater': true,
      }, settingsKey: 'custom_dialects');
      expect(split.wholeRecord, isFalse);
      expect(split.known, {'value': 1});
      expect(split.retained, isNotNull);
    });
  });
}
