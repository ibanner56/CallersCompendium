import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A comprehensive archive exercising every entity type and many edge cases
/// (non-standard phrase structure, custom-only figures, metadata-only dances,
/// all custom-field value types, every link kind, partial dates at differing
/// precisions, provenance with a raw payload, a program with no slots).
CompendiumArchive _sampleArchive() {
  final c1 = Choreographer(
    id: 'c1',
    name: 'Alice Choreo',
    website: 'https://alice.example',
    notes: 'prolific',
    email: 'alice@example.com',
    location: 'Portland, OR',
    deceased: true,
  );
  final c2 = Choreographer(id: 'c2', name: 'Traditional');

  final s1 = PublishedSource(
    id: 's1',
    title: 'Zesty Contras',
    author: 'Larry Jennings',
    year: 1983,
    url: 'https://zesty.example',
    notes: 'classic',
  );
  final s2 = PublishedSource(id: 's2', title: 'Give-and-Take');

  final tags = [
    Tag(id: 't1', name: 'chestnut', color: 0xFF00FF00),
    Tag(id: 't2', name: 'becket'),
  ];

  final customFields = [
    CustomFieldDef(
      id: 'f_bool',
      key: 'teach',
      label: 'Needs teaching',
      type: CustomFieldType.boolean,
    ),
    CustomFieldDef(
      id: 'f_choice',
      key: 'tempo',
      label: 'Tempo',
      type: CustomFieldType.choice,
      choices: const ['slow', 'medium', 'fast'],
      searchable: false,
    ),
    CustomFieldDef(
      id: 'f_num',
      key: 'difficulty',
      label: 'Difficulty',
      type: CustomFieldType.number,
    ),
    CustomFieldDef(
      id: 'f_text',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
      showInList: true,
    ),
  ];

  final d1 = Dance(
    id: 'd1',
    title: 'Full Fidelity',
    authorIds: const ['c2', 'c1'],
    form: DanceForm.contra,
    formation: const Formation(
      FormationShape.becketCw,
      detail: 'double progression',
    ),
    progression: Progression.double,
    phraseStructure: '6*8*2',
    figures: [
      Figure(move: 'swing', params: {'who': 'partner', 'beats': 16}),
      Figure(
        move: 'allemande',
        params: {'who': 'neighbor', 'hand': 'right', 'turn': 1.5},
        note: 'smoothly',
        progression: true,
      ),
    ],
    hook: 'a zesty becket',
    callingNotes: 'teach the allemande',
    status: DanceStatus.active,
    level: DanceLevel.intermediate,
    mixedLevel: false,
    rating: 5,
    tunes: const ['Reel de Montreal', 'Growling Old Man'],
    customFields: [
      CustomFieldValue(fieldId: 'f_text', value: 'New England'),
      CustomFieldValue(fieldId: 'f_num', value: 4),
      CustomFieldValue(fieldId: 'f_bool', value: true),
      CustomFieldValue(fieldId: 'f_choice', value: 'fast'),
    ],
    tagIds: const ['t1', 't2'],
    links: [
      DanceLink(
        id: 'l1',
        kind: LinkKind.video,
        url: 'https://youtu.be/x',
        label: 'demo',
      ),
      DanceLink(id: 'l2', kind: LinkKind.relatedDance, targetDanceId: 'd2'),
      DanceLink(id: 'l3', kind: LinkKind.source, url: 'https://src.example'),
    ],
    sourceCitations: [
      SourceCitation(sourceId: 's1', page: '12-14', number: 'A1'),
      SourceCitation(sourceId: 's2'),
    ],
    provenance: Provenance(
      source: ProvenanceSource.callersbox,
      externalId: '3418',
      importedAt: DateTime.utc(2025, 3, 4, 5, 6, 7),
      permission: 'full',
      license: 'CC-BY',
      rawPayload: '{"id":3418,"title":"Full Fidelity"}',
      sourceVersion: '2025-01',
    ),
    composedOn: PartialDate(1989),
    revisedOn: PartialDate(2004, 3, 15),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 2, 2),
    deletedAt: DateTime.utc(2026, 6, 6),
  );

  // Custom-only figures, standard (empty) phrase structure, no optionals.
  final d2 = Dance(
    id: 'd2',
    title: 'All Custom',
    figures: [
      Figure(move: customMove, params: {'text': 'weave the ring', 'beats': 8}),
      Figure(move: customMove, params: {'text': 'do something odd'}),
    ],
    createdAt: DateTime.utc(2026, 1, 3),
    updatedAt: DateTime.utc(2026, 1, 3),
  );

  // Metadata-only stub: no figures at all.
  final d3 = Dance(
    id: 'd3',
    title: 'Stub',
    createdAt: DateTime.utc(2026, 1, 4),
    updatedAt: DateTime.utc(2026, 1, 4),
  );

  final p1 = Program(
    id: 'p1',
    title: 'Spring Fling',
    eventDate: DateTime.utc(2026, 5, 1),
    venue: 'Grange Hall',
    band: 'The Fiddleheads',
    caller: 'Alice',
    dancerLevel: 'intermediate',
    notes: 'sound check at 6',
    status: ProgramStatus.performed,
    hideAlternates: true,
    slots: [
      ProgramSlot(
        id: 'sl1',
        position: 0,
        danceId: 'd1',
        plannedMinutes: 12,
        performedAt: DateTime.utc(2026, 5, 1, 20),
      ),
      ProgramSlot(
        id: 'sl2',
        position: 1,
        danceId: 'd2',
        isAlt: true,
        guestCaller: 'Bob',
      ),
      ProgramSlot(id: 'sl3', position: 2, text: 'break'),
    ],
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 20),
  );

  // A program with no slots and no optional metadata.
  final p2 = Program(
    id: 'p2',
    title: 'Empty Draft',
    createdAt: DateTime.utc(2026, 4, 2),
    updatedAt: DateTime.utc(2026, 4, 2),
  );

  return CompendiumArchive(
    exportedAt: DateTime.utc(2026, 7, 15, 12, 0, 0),
    choreographers: [c1, c2],
    publishedSources: [s1, s2],
    tags: tags,
    customFields: customFields,
    dances: [d1, d2, d3],
    programs: [p1, p2],
  );
}

void main() {
  group('archive JSON round-trip', () {
    test('export -> import -> export is identity (design property)', () {
      final archive = _sampleArchive();
      final json = encodeArchive(archive);
      final result = decodeArchive(json);

      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.warnings, isEmpty);
      // The stated acceptance property: re-encoding the decoded archive
      // reproduces the exact bytes.
      expect(encodeArchive(result.archive), json);
    });

    test('decoding reconstructs entity content (deep spot-check)', () {
      final result = decodeArchive(encodeArchive(_sampleArchive()));
      expect(result.hasErrors, isFalse);

      final d1 = result.archive.dances.firstWhere((d) => d.id == 'd1');
      expect(d1.authorIds, ['c2', 'c1']);
      expect(d1.formation.shape, FormationShape.becketCw);
      expect(d1.formation.detail, 'double progression');
      expect(d1.progression, Progression.double);
      expect(d1.phraseStructure.raw, '6*8*2');
      expect(d1.figures, hasLength(2));
      expect(d1.figures[1].params['turn'], 1.5);
      expect(d1.figures[1].progression, isTrue);
      expect(d1.level, DanceLevel.intermediate);
      expect(d1.rating, 5);
      expect(d1.tunes, hasLength(2));
      expect(d1.customFields.map((v) => v.value), [
        'New England',
        4,
        true,
        'fast',
      ]);
      expect(d1.links.map((l) => l.kind), [
        LinkKind.video,
        LinkKind.relatedDance,
        LinkKind.source,
      ]);
      expect(d1.links[1].targetDanceId, 'd2');
      expect(d1.sourceCitations.first.page, '12-14');
      expect(d1.composedOn, PartialDate(1989));
      expect(d1.revisedOn, PartialDate(2004, 3, 15));
      expect(d1.deletedAt, DateTime.utc(2026, 6, 6));

      // Provenance is excluded from Dance's value equality, so assert it here.
      final prov = d1.provenance!;
      expect(prov.source, ProvenanceSource.callersbox);
      expect(prov.externalId, '3418');
      expect(prov.rawPayload, '{"id":3418,"title":"Full Fidelity"}');
      expect(prov.importedAt, DateTime.utc(2025, 3, 4, 5, 6, 7));

      final f = result.archive.customFields.firstWhere(
        (f) => f.id == 'f_choice',
      );
      expect(f.type, CustomFieldType.choice);
      expect(f.choices, ['slow', 'medium', 'fast']);
      expect(f.searchable, isFalse);

      final p1 = result.archive.programs.firstWhere((p) => p.id == 'p1');
      expect(p1.hideAlternates, isTrue);
      expect(p1.slots, hasLength(3));
      expect(p1.slots[0].plannedMinutes, 12);
      expect(p1.slots[1].isAlt, isTrue);
      expect(p1.slots[1].guestCaller, 'Bob');
    });

    test('an empty archive round-trips', () {
      final archive = CompendiumArchive(exportedAt: DateTime.utc(2026));
      final result = decodeArchive(encodeArchive(archive));
      expect(result.hasErrors, isFalse);
      expect(result.archive, archive);
      expect(encodeArchive(result.archive), encodeArchive(archive));
    });

    test('output is deterministic regardless of input entity order', () {
      final a = _sampleArchive();
      final shuffled = CompendiumArchive(
        exportedAt: a.exportedAt,
        choreographers: a.choreographers.reversed.toList(),
        publishedSources: a.publishedSources.reversed.toList(),
        tags: a.tags.reversed.toList(),
        customFields: a.customFields.reversed.toList(),
        dances: a.dances.reversed.toList(),
        programs: a.programs.reversed.toList(),
      );
      expect(encodeArchive(shuffled), encodeArchive(a));
    });
  });

  group('forward compatibility', () {
    test('unknown top-level and per-entity keys are ignored', () {
      final json = encodeArchive(_sampleArchive());
      final map = jsonDecode(json) as Map<String, Object?>;
      map['futureTopLevelField'] = {'anything': true};
      (map['dances'] as List)
              .cast<Map<String, Object?>>()
              .first['futureField'] =
          'ignored';

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse);
      // Known fields still reconstruct the original archive (JSON identity).
      expect(encodeArchive(result.archive), encodeArchive(_sampleArchive()));
    });

    test('a newer schemaVersion is read with a warning, not an error', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      map['schemaVersion'] = archiveSchemaVersion + 5;

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.archive.schemaVersion, archiveSchemaVersion + 5);
      expect(result.archive.dances, hasLength(3));
    });

    test('a missing schemaVersion defaults to the current version', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      map.remove('schemaVersion');

      final result = decodeArchive(jsonEncode(map));
      expect(result.archive.schemaVersion, archiveSchemaVersion);
      expect(result.hasErrors, isFalse);
    });

    test('an unparseable exportedAt degrades to a warning', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      map['exportedAt'] = 'not-a-date';

      final result = decodeArchive(jsonEncode(map));
      expect(result.warnings, isNotEmpty);
      expect(result.archive.dances, hasLength(3));
    });
  });

  group('error handling', () {
    test('invalid JSON yields a structured error, not a throw', () {
      final result = decodeArchive('{ this is not json');
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'archive');
      expect(result.archive.dances, isEmpty);
    });

    test('a non-object root yields a structured error', () {
      final result = decodeArchive('[1, 2, 3]');
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'archive');
    });

    test('one malformed entity is skipped; the rest still load', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final dances = (map['dances'] as List).cast<Map<String, Object?>>();
      // Corrupt the first dance by removing its required title.
      dances.first.remove('title');

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'dance');
      expect(result.errors.single.kind, ArchiveErrorKind.read);
      // The two well-formed dances survived.
      expect(result.archive.dances, hasLength(2));
      expect(
        result.archive.dances.map((d) => d.id),
        containsAll(<String>['d2', 'd3']),
      );
    });

    test('a non-array entity collection is reported and skipped', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      map['tags'] = {'not': 'an array'};

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.archive.tags, isEmpty);
      // Other collections are unaffected.
      expect(result.archive.dances, hasLength(3));
    });

    test('an unknown enum value fails only its own entity', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final dances = (map['dances'] as List).cast<Map<String, Object?>>();
      dances.firstWhere((d) => d['id'] == 'd2')['status'] = 'from_the_future';

      final result = decodeArchive(jsonEncode(map));
      expect(result.errors.single.entityId, 'd2');
      expect(result.archive.dances, hasLength(2));
    });
  });
}
