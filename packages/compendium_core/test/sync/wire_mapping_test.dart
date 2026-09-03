import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../../tool/generate_sync_allow_list.dart' as generator;

final _now = DateTime.utc(2026, 7, 15, 12);

void main() {
  test('the generated artifact is fresh', () {
    expect(
      File(
        Directory('packages/compendium_core').existsSync()
            ? 'packages/compendium_core/lib/src/sync/generated_sync_allow_list.dart'
            : 'lib/src/sync/generated_sync_allow_list.dart',
      ).readAsStringSync(),
      generator.renderSyncAllowList(),
    );
  });

  test('maps every real archive wire path to a classified source field', () {
    final archive = _sampleArchive();
    final root =
        jsonDecode(
              encodeArchive(archive, mode: ArchiveSerializationMode.backup),
            )
            as Map<String, Object?>;

    final archiveKinds = <String, SyncRecordKind>{
      'dances': SyncRecordKind.dance,
      'programs': SyncRecordKind.program,
      'choreographers': SyncRecordKind.choreographer,
      'publishedSources': SyncRecordKind.publishedSource,
      'customFields': SyncRecordKind.customFieldDef,
      'tags': SyncRecordKind.tag,
      'venues': SyncRecordKind.venue,
    };
    var observedRecords = 0;
    for (final MapEntry(key: archiveKey, value: kind) in archiveKinds.entries) {
      final records = root[archiveKey] as List<Object?>;
      expect(records, isNotEmpty, reason: archiveKey);
      for (final record in records) {
        observedRecords++;
        for (final path in _wirePaths(kind, record)) {
          final mapping = syncWireFields[kind]!.where(
            (field) => field.path == path,
          );
          expect(
            mapping,
            isNotEmpty,
            reason: '$kind emitted unmapped wire path $path',
          );
          if (mapping.single.sourceFields.isNotEmpty) {
            for (final source in mapping.single.sourceFields) {
              expect(
                fieldClassifications[source],
                isNotNull,
                reason: '$kind.$path references unknown source $source',
              );
            }
          }
        }
      }
    }
    expect(observedRecords, greaterThanOrEqualTo(7));

    final mappedSources = {
      for (final fields in syncWireFields.values)
        for (final field in fields) ...field.sourceFields,
    };
    final missingShareable =
        fieldClassifications.entries
            .where(
              (entry) =>
                  entry.value.egress == EgressClass.shareable &&
                  !mappedSources.contains(entry.key) &&
                  !syncWireMappingExceptions.contains(entry.key),
            )
            .map((entry) => entry.key)
            .toList()
          ..sort();
    expect(missingShareable, isEmpty);
  });

  test('projects only shareable values and validates received bodies', () {
    final root =
        jsonDecode(
              encodeArchive(
                _sampleArchive(),
                mode: ArchiveSerializationMode.backup,
              ),
            )
            as Map<String, Object?>;
    const archiveKinds = <String, SyncRecordKind>{
      'dances': SyncRecordKind.dance,
      'programs': SyncRecordKind.program,
      'choreographers': SyncRecordKind.choreographer,
      'publishedSources': SyncRecordKind.publishedSource,
      'customFields': SyncRecordKind.customFieldDef,
      'tags': SyncRecordKind.tag,
      'venues': SyncRecordKind.venue,
    };
    const positiveSentinels = <SyncRecordKind, String>{
      SyncRecordKind.dance: 'Full Fidelity',
      SyncRecordKind.program: 'Spring Fling',
      SyncRecordKind.choreographer: 'Alice Choreo',
      SyncRecordKind.publishedSource: 'Zesty Contras',
      SyncRecordKind.customFieldDef: 'tempo',
      SyncRecordKind.tag: 'chestnut',
      SyncRecordKind.venue: 'Public Hall',
    };
    for (final MapEntry(key: archiveKey, value: kind) in archiveKinds.entries) {
      for (final rawBody in root[archiveKey]! as List<Object?>) {
        final body = rawBody as Map<String, Object?>;
        final projected = projectShareableRecordBody(
          kind,
          body,
          allowedCustomFieldIds: kind == SyncRecordKind.dance
              ? {'f1'}
              : const {},
        );
        if (kind == SyncRecordKind.customFieldDef &&
            body['shareable'] == false) {
          expect(projected, isEmpty);
          continue;
        }
        expect(projected, isNotEmpty, reason: '$kind has no projected fields');
        expect(
          jsonEncode(projected),
          contains(positiveSentinels[kind]!),
          reason: '$kind lost its shareable sentinel',
        );
        expect(
          validateShareableRecordBody(kind, projected).isValid,
          isTrue,
          reason: '$kind projection did not validate',
        );
        final projectedJson = jsonEncode(projected);
        expect(
          projectedJson,
          isNot(contains('private-contact@example.com')),
          reason: '$kind leaked a private contact',
        );
        expect(
          projectedJson,
          isNot(contains('SECRET-ADDRESS')),
          reason: '$kind leaked a private address',
        );
        for (final field in syncWireFields[kind]!) {
          if (field.sourceFields.isEmpty) continue;
          final classifications = field.sourceFields
              .map((source) => fieldClassifications[source])
              .toList();
          if (classifications.every(
            (classification) => classification?.egress != EgressClass.shareable,
          )) {
            final projectedValues = _valuesAtPath(
              projected,
              field.path.split('.'),
            );
            expect(
              projectedValues.where((value) => value != null),
              isEmpty,
              reason: '$kind leaked non-shareable path ${field.path}',
            );
          }
        }
      }
    }
    final dance =
        (root['dances']! as List<Object?>).single as Map<String, Object?>;
    expect(
      jsonEncode(
        projectShareableRecordBody(
          SyncRecordKind.dance,
          dance,
          allowedCustomFieldIds: {'f1'},
        ),
      ),
      isNot(contains('PRIVATE-CUSTOM-VALUE')),
    );
    final choreographer =
        (root['choreographers']! as List<Object?>).single
            as Map<String, Object?>;
    final unknownChoreographer = Map<String, Object?>.from(choreographer)
      ..remove('email')
      ..remove('location')
      ..remove('deceased')
      ..['futureField'] = 'unknown';
    expect(
      validateShareableRecordBody(
        SyncRecordKind.choreographer,
        unknownChoreographer,
      ).invalidPath,
      'futureField',
    );
  });

  test('resolves exact, prefixed, and unknown setting keys fail closed', () {
    expect(
      isShareableWirePath(
        SyncRecordKind.setting,
        'value',
        settingsKey: 'custom_dialects',
      ),
      isTrue,
    );
    expect(
      isShareableWirePath(
        SyncRecordKind.setting,
        'value',
        settingsKey: 'editor_draft:d1',
      ),
      isFalse,
    );
    expect(
      projectShareableRecordBody(SyncRecordKind.setting, {
        'id': 'mystery',
        'value': 'secret',
      }, settingsKey: 'unknown_runtime_key'),
      {'id': 'mystery'},
    );
    expect(
      validateShareableRecordBody(SyncRecordKind.setting, {
        'id': 'mystery',
        'value': 'secret',
      }, settingsKey: 'unknown_runtime_key').invalidPath,
      'value',
    );

    const synthetic = DataClassification(
      term: DpvTerm.nonPersonal,
      subject: DataSubject.appUser,
      egress: EgressClass.shareable,
    );
    settingsPrefixClassifications['test_shareable:'] = synthetic;
    try {
      expect(
        projectShareableRecordBody(SyncRecordKind.setting, {
          'id': 'test_shareable:1',
          'value': 'allowed',
        }, settingsKey: 'test_shareable:1'),
        {'id': 'test_shareable:1', 'value': 'allowed'},
      );
      expect(
        validateShareableRecordBody(SyncRecordKind.setting, {
          'id': 'test_shareable:1',
          'value': 'allowed',
        }, settingsKey: 'test_shareable:1').isValid,
        isTrue,
      );
    } finally {
      settingsPrefixClassifications.remove('test_shareable:');
    }
  });

  test('does not treat dotted keys as nested wire paths', () {
    final validation = validateShareableRecordBody(SyncRecordKind.dance, {
      'formation.shape': 'private',
    });
    expect(validation.isValid, isFalse);
  });
}

List<Object?> _valuesAtPath(Object? value, List<String> segments) {
  if (segments.isEmpty) return [value];
  if (value is List) {
    return [for (final item in value) ..._valuesAtPath(item, segments)];
  }
  if (value is Map && value.containsKey(segments.first)) {
    return _valuesAtPath(value[segments.first], segments.sublist(1));
  }
  return const [];
}

Set<String> _wirePaths(SyncRecordKind kind, Object? value, [String path = '']) {
  if (value is List) {
    return {for (final item in value) ..._wirePaths(kind, item, path)};
  }
  if (value is! Map) return path.isEmpty ? {} : {path};

  final paths = <String>{};
  for (final entry in value.entries) {
    if (entry.key is! String) continue;
    final child = path.isEmpty ? entry.key as String : '$path.${entry.key}';
    paths.add(child);
    final isContainer = syncWireFields[kind]!.any(
      (field) => field.path == child && field.sourceFields.isEmpty,
    );
    if (isContainer) {
      paths.addAll(_wirePaths(kind, entry.value, child));
    }
  }
  return paths;
}

CompendiumArchive _sampleArchive() {
  final choreographer = Choreographer(
    id: 'c1',
    name: 'Alice Choreo',
    website: 'https://alice.example',
    notes: 'prolific',
    email: 'private-contact@example.com',
    location: 'SECRET-ADDRESS',
    deceased: true,
  );
  final source = PublishedSource(
    id: 's1',
    title: 'Zesty Contras',
    author: 'Larry Jennings',
    year: 1983,
    url: 'https://source.example',
    notes: 'classic',
  );
  final customField = CustomFieldDef(
    id: 'f1',
    key: 'tempo',
    label: 'Tempo',
    type: CustomFieldType.choice,
    choices: const ['slow', 'fast'],
    searchable: false,
    showInList: true,
    shareable: true,
  );
  final privateCustomField = CustomFieldDef(
    id: 'private',
    key: 'private',
    label: 'Private',
    type: CustomFieldType.text,
    shareable: false,
  );
  final dance = Dance(
    id: 'd1',
    title: 'Full Fidelity',
    authorIds: const ['c1'],
    formation: const Formation(FormationShape.becketCw, detail: 'double'),
    phraseStructure: '6*8*2',
    figures: [
      Figure(move: 'swing', params: {'who': 'partners'}),
    ],
    hook: 'zesty',
    callingNotes: 'teach',
    walkthrough: 'walk',
    level: DanceLevel.intermediate,
    rating: 5,
    tunes: const ['Reel'],
    customFields: [
      CustomFieldValue(fieldId: 'f1', value: 'fast'),
      CustomFieldValue(fieldId: 'private', value: 'PRIVATE-CUSTOM-VALUE'),
    ],
    tagIds: const ['t1'],
    links: [
      DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://video.example'),
    ],
    sourceCitations: [SourceCitation(sourceId: 's1', page: '12', number: 'A1')],
    provenance: Provenance(
      source: ProvenanceSource.callersbox,
      externalId: '3418',
      importedAt: _now,
      permission: 'full',
      license: 'CC-BY',
      sourceVersion: '2025-01',
    ),
    composedOn: PartialDate(1989),
    revisedOn: PartialDate(2004, 3, 15),
    createdAt: _now,
    updatedAt: _now,
    deletedAt: _now,
  );
  final program = Program(
    id: 'p1',
    title: 'Spring Fling',
    eventDate: _now,
    venue: 'Public Hall',
    venueId: 'v1',
    band: 'The Fiddleheads',
    caller: 'Alice',
    dancerLevel: 'intermediate',
    notes: 'sound check',
    status: ProgramStatus.performed,
    hideAlternates: true,
    slots: [
      ProgramSlot(
        id: 'sl1',
        position: 0,
        danceId: 'd1',
        text: 'note',
        isAlt: true,
        guestCaller: 'Bob',
        plannedMinutes: 12,
        performedAt: _now,
      ),
    ],
    provenance: Provenance(
      source: ProvenanceSource.callersCompanion,
      externalId: 'usr-1',
      importedAt: _now,
    ),
    createdAt: _now,
    updatedAt: _now,
    deletedAt: _now,
  );
  final venue = Venue(
    id: 'v1',
    name: 'Public Hall',
    address1: 'SECRET-ADDRESS',
    address2: 'Suite 2',
    city: 'Portland',
    stateProv: 'OR',
    country: 'US',
    postalCode: '97201',
    plus4: '1234',
    website: 'https://hall.example',
    sponsor: 'Community Org',
    eventName: 'Spring Dance',
    time: '7pm',
    genericSchedule: 'first Friday',
    price: '10',
    notes: 'bring chairs',
    contact1Name: 'Private Contact',
    contact1Phone: '555-0100',
    contact1Email: 'private-contact@example.com',
    contact2Name: 'Second Contact',
    contact2Phone: '555-0101',
    contact2Email: 'second@example.com',
    provenance: Provenance(
      source: ProvenanceSource.callersCompanion,
      importedAt: _now,
    ),
  );
  return CompendiumArchive(
    exportedAt: _now,
    dances: [dance],
    programs: [program],
    choreographers: [choreographer],
    publishedSources: [source],
    customFields: [customField, privateCustomField],
    tags: [Tag(id: 't1', name: 'chestnut', color: 7)],
    venues: [venue],
  );
}
