import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

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
      Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
      Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.5},
        note: 'smoothly',
        progression: true,
      ),
    ],
    hook: 'a zesty becket',
    callingNotes: 'teach the allemande',
    walkthrough:
        'A1: neighbours balance and swing.\n'
        'A2: ladies chain; star left.\nB1: partners balance and swing.',
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
      testFigure(
        move: customMove,
        params: {'text': 'weave the ring', 'beats': 8},
      ),
      customFigure('do something odd', origin: CustomOrigin.importGap),
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
    provenance: Provenance(
      source: ProvenanceSource.callersCompanion,
      externalId: 'usr-9921',
      importedAt: DateTime.utc(2025, 4, 1, 8, 0, 0),
      sourceVersion: '2.3',
    ),
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
  test('reports legacy non-finite custom values with entity context', () {
    final archive = CompendiumArchive(
      exportedAt: DateTime.utc(2026, 1, 1),
      dances: [
        Dance(
          id: 'bad-dance',
          title: 'Legacy value',
          customFields: [
            CustomFieldValue(fieldId: 'bad-number', value: double.infinity),
          ],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    expect(
      () => encodeArchive(archive),
      throwsA(
        isA<ArchiveEncodingException>()
            .having((e) => e.danceId, 'danceId', 'bad-dance')
            .having((e) => e.fieldId, 'fieldId', 'bad-number'),
      ),
    );
  });
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

      // The customOrigin discriminator survives the archive/.ccshare path.
      final d2 = result.archive.dances.firstWhere((d) => d.id == 'd2');
      expect(d2.figures[0].customOrigin, CustomOrigin.userEntered);
      expect(d2.figures[1].customOrigin, CustomOrigin.importGap);
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

      // Provenance is excluded from Program's value equality, so assert it
      // here (issue #610: this used to be silently dropped by the codec).
      final pProv = p1.provenance!;
      expect(pProv.source, ProvenanceSource.callersCompanion);
      expect(pProv.externalId, 'usr-9921');
      expect(pProv.importedAt, DateTime.utc(2025, 4, 1, 8, 0, 0));
      expect(pProv.sourceVersion, '2.3');
    });

    test('composite phrase structures survive archive round-trips', () {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026),
        dances: [
          Dance(
            id: 'composite',
            title: 'Composite Phrases',
            phraseStructure: '3*8*2 + 1*4*2',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );

      final encoded = encodeArchive(archive);
      final result = decodeArchive(encoded);

      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.warnings, isEmpty);
      expect(result.archive.dances.single.phraseStructure.raw, '3*8*2 + 1*4*2');
      expect(encodeArchive(result.archive), encoded);
    });

    test('an empty archive round-trips', () {
      final archive = CompendiumArchive(exportedAt: DateTime.utc(2026));
      final result = decodeArchive(encodeArchive(archive));
      expect(result.hasErrors, isFalse);
      expect(result.archive, archive);
      expect(encodeArchive(result.archive), encodeArchive(archive));
    });

    group('mixer flag (issue #732)', () {
      Dance mixerDance({required bool mixer}) => Dance(
        id: 'dm',
        title: 'Mixer Test',
        mixer: mixer,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      test('a mixer=true dance survives encode -> decode', () {
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026),
          dances: [mixerDance(mixer: true)],
        );
        final result = decodeArchive(encodeArchive(archive));
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
        expect(result.archive.dances.single.mixer, isTrue);
      });

      test('mixer=true is emitted into the encoded JSON', () {
        final json =
            jsonDecode(
                  encodeArchive(
                    CompendiumArchive(
                      exportedAt: DateTime.utc(2026),
                      dances: [mixerDance(mixer: true)],
                    ),
                  ),
                )
                as Map<String, Object?>;
        final dance = (json['dances'] as List)
            .cast<Map<String, Object?>>()
            .single;
        expect(dance['mixer'], isTrue);
      });

      test('an archive with no mixer key decodes to mixer=false', () {
        // Tolerant additive decode: older archives predate the field, so the
        // key is simply absent and must default to false — this is why the
        // archive format needs no version bump.
        final json =
            jsonDecode(
                  encodeArchive(
                    CompendiumArchive(
                      exportedAt: DateTime.utc(2026),
                      dances: [mixerDance(mixer: true)],
                    ),
                  ),
                )
                as Map<String, Object?>;
        final dance = (json['dances'] as List)
            .cast<Map<String, Object?>>()
            .single;
        dance.remove('mixer');
        final result = decodeArchive(jsonEncode(json));
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
        expect(result.archive.dances.single.mixer, isFalse);
      });
    });

    test('a choice field with many options round-trips (issue #373)', () {
      // A reusable adjective pick-list built up over time — every option must
      // survive an export/import cycle unchanged and in order.
      final adjectives = [
        'driving',
        'lyrical',
        'punchy',
        'floaty',
        'connected',
      ];
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026),
        customFields: [
          CustomFieldDef(
            id: 'adj',
            key: 'adjectives',
            label: 'Adjectives',
            type: CustomFieldType.choice,
            choices: adjectives,
          ),
        ],
      );
      final result = decodeArchive(encodeArchive(archive));
      expect(result.hasErrors, isFalse);
      final def = result.archive.customFields.single;
      expect(def.choices, adjectives);
      // Re-encode equality holds too (byte-for-byte stable).
      expect(encodeArchive(result.archive), encodeArchive(archive));
    });

    test('oversized/duplicate choice options are soft-clamped and de-duped on '
        'import (OWASP, issue #373)', () {
      // Craft an archive whose choice field carries an over-length option and
      // a duplicate that collapses onto the same clamped prefix — untrusted
      // import input must be clamped (not rejected) and de-duplicated.
      final base = 'a' * kMaxCustomFieldChoiceLength;
      final json =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final fields = (json['customFields'] as List)
          .cast<Map<String, Object?>>();
      final choiceField = fields.firstWhere((f) => f['id'] == 'f_choice');
      choiceField['choices'] = <String>[
        '$base-EXTRA-ONE', // > bound → clamps to `base`
        '$base-EXTRA-TWO', // > bound → also clamps to `base` (dupe)
        'slow',
      ];

      final result = decodeArchive(jsonEncode(json));
      expect(result.hasErrors, isFalse);
      final def = result.archive.customFields.firstWhere(
        (f) => f.id == 'f_choice',
      );
      // The two oversized values collapse to a single clamped option; 'slow'
      // is preserved. No option exceeds the bound.
      expect(def.choices, [base, 'slow']);
      expect(
        def.choices!.every((c) => c.length <= kMaxCustomFieldChoiceLength),
        isTrue,
      );
    });

    test(
      'a choice VALUE is clamped in lock-step with its clamped option so the '
      'dance still restores (issue #373)',
      () {
        // A dance whose choice value equals an over-length option: clamping the
        // option must also clamp the value, or the value would no longer be a
        // member of the field's options and the dance would be rejected on
        // restore.
        final long = 'z' * (kMaxCustomFieldChoiceLength + 25);
        final clamped = 'z' * kMaxCustomFieldChoiceLength;
        final json =
            jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
        final fields = (json['customFields'] as List)
            .cast<Map<String, Object?>>();
        fields.firstWhere((f) => f['id'] == 'f_choice')['choices'] = <String>[
          long,
          'slow',
        ];
        // Point an existing dance's f_choice value at the over-length option.
        final dances = (json['dances'] as List).cast<Map<String, Object?>>();
        dances.first['customFields'] = <Object?>[
          {'fieldId': 'f_choice', 'value': long},
        ];

        final result = decodeArchive(jsonEncode(json));
        expect(result.hasErrors, isFalse);
        final def = result.archive.customFields.firstWhere(
          (f) => f.id == 'f_choice',
        );
        final value = result.archive.dances.first.customFields.singleWhere(
          (v) => v.fieldId == 'f_choice',
        );
        expect(value.value, clamped);
        // The clamped value is a valid member of the clamped option set.
        expect(def.choices, contains(clamped));
        expect(
          CustomFieldValue(
            fieldId: 'f_choice',
            value: value.value,
          ).matchesType(def),
          isTrue,
        );
      },
    );

    test('a choice field left with no usable options is skipped, not aborted '
        '(issue #373)', () {
      // A malicious archive whose choice field has only a blank option: the
      // field cannot be constructed (needs >=1 real option), but the import
      // must tolerate it as a per-entity skip rather than aborting the whole
      // decode with an uncaught Error.
      final json =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final fields = (json['customFields'] as List)
          .cast<Map<String, Object?>>();
      fields.firstWhere((f) => f['id'] == 'f_choice')['choices'] = <String>[''];

      final result = decodeArchive(jsonEncode(json));
      // Not a fatal error: the offending field is dropped, everything else
      // still decodes.
      expect(result.hasErrors, isTrue);
      expect(
        result.archive.customFields.any((f) => f.id == 'f_choice'),
        isFalse,
      );
      expect(result.archive.customFields, isNotEmpty);
      expect(result.archive.dances, isNotEmpty);
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

    test(
      'an unknown enum value skips its entity as a tracked drop, not an error',
      () {
        final map =
            jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
        final dances = (map['dances'] as List).cast<Map<String, Object?>>();
        dances.firstWhere((d) => d['id'] == 'd2')['status'] = 'from_the_future';

        final result = decodeArchive(jsonEncode(map));
        // Forward-compat: an unrecognized enum value (written by a newer app
        // version) degrades to a warning, never an error. This is what keeps a
        // merely-newer backup from escalating to a fatal decode that would abort
        // a replace restore and wipe the user's live collection (issue #430).
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
        expect(result.warnings, isNotEmpty);
        expect(result.warnings.any((w) => w.contains('d2')), isTrue);
        // The drop is ALSO tracked structurally so the replace gate can refuse
        // an incomplete archive — it must not be lost among warnings.
        expect(result.isIncomplete, isTrue);
        expect(result.droppedEntities, hasLength(1));
        expect(result.droppedEntities.single, contains('d2'));
        // The offending entity is still dropped; the rest load.
        expect(result.archive.dances, hasLength(2));
        expect(result.archive.dances.map((d) => d.id), isNot(contains('d2')));
      },
    );

    test('an unknown REQUIRED enum value also skips as a tracked drop', () {
      // `level` uses the strict `_enumByName` path (no fallback). A newer
      // level value must still skip-with-warning, not error out.
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final dances = (map['dances'] as List).cast<Map<String, Object?>>();
      dances.firstWhere((d) => d['id'] == 'd2')['level'] = 'grandmaster';

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.warnings, isNotEmpty);
      expect(result.isIncomplete, isTrue);
      expect(result.droppedEntities.single, contains('d2'));
      expect(result.archive.dances.map((d) => d.id), isNot(contains('d2')));
    });

    test('a fully-decodable archive is not marked incomplete', () {
      final result = decodeArchive(encodeArchive(_sampleArchive()));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.isIncomplete, isFalse);
      expect(result.droppedEntities, isEmpty);
    });
  });

  group('program provenance (issue #610)', () {
    test('a program with provenance round-trips it byte-for-byte', () {
      final json = encodeArchive(_sampleArchive());
      final result = decodeArchive(json);
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

      final p1 = result.archive.programs.firstWhere((p) => p.id == 'p1');
      expect(p1.provenance, isNotNull);
      expect(p1.provenance!.source, ProvenanceSource.callersCompanion);
      expect(p1.provenance!.externalId, 'usr-9921');

      // Round-trip identity holds with a provenance-bearing program present.
      expect(encodeArchive(result.archive), json);
    });

    test('a backup with no "provenance" key on a program restores cleanly '
        '(backward compat with pre-#610 archives)', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final programs = (map['programs'] as List).cast<Map<String, Object?>>();
      final p1 = programs.firstWhere((p) => p['id'] == 'p1');
      expect(p1.containsKey('provenance'), isTrue);
      p1.remove('provenance');

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.warnings, isEmpty);
      final restored = result.archive.programs.firstWhere((p) => p.id == 'p1');
      expect(restored.provenance, isNull);
    });

    test('a program with an unknown provenance source is dropped as a tracked '
        'drop, not an error (never bricks the rest of the restore)', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final programs = (map['programs'] as List).cast<Map<String, Object?>>();
      final p1 = programs.firstWhere((p) => p['id'] == 'p1');
      (p1['provenance'] as Map<String, Object?>)['source'] =
          'some_future_source';

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.warnings, isNotEmpty);
      expect(result.isIncomplete, isTrue);
      expect(result.droppedEntities.single, contains('p1'));
      // Only p1 is dropped; the rest of the archive still loads.
      expect(result.archive.programs.map((p) => p.id), isNot(contains('p1')));
      expect(result.archive.programs, hasLength(1));
      expect(result.archive.dances, hasLength(3));
    });

    test('an oversized provenance externalId is clamped on decode, not '
        'rejected (OWASP: untrusted archive content)', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      final programs = (map['programs'] as List).cast<Map<String, Object?>>();
      final p1 = programs.firstWhere((p) => p['id'] == 'p1');
      final overlong = 'x' * (kMaxExternalIdLength + 500);
      (p1['provenance'] as Map<String, Object?>)['externalId'] = overlong;

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      final restored = result.archive.programs.firstWhere((p) => p.id == 'p1');
      expect(restored.provenance!.externalId, hasLength(kMaxExternalIdLength));
      expect(
        restored.provenance!.externalId,
        overlong.substring(0, kMaxExternalIdLength),
      );
    });
  });

  group('venue serialization', () {
    // A program that references an embedded venue, plus a standalone venue.
    CompendiumArchive archiveWithVenues() {
      final linked = Venue(
        id: 'v1',
        name: 'Guiding Star Grange',
        address1: '401 Chapman St',
        city: 'Greenfield',
        stateProv: 'MA',
        country: 'USA',
        postalCode: '01301',
        plus4: '1234',
        website: 'https://example.com',
        sponsor: 'Greenfield Dance',
        eventName: 'Second Saturday Contra',
        time: '8pm',
        genericSchedule: '2nd Saturdays',
        price: '\$10',
        notes: 'wooden floor',
        contact1Name: 'Pat',
        contact1Phone: '555-0001',
        contact1Email: 'pat@example.com',
        contact2Name: 'Sam',
        contact2Phone: '555-0002',
        contact2Email: 'sam@example.com',
      );
      final other = Venue(id: 'v2', name: 'Town Hall');
      final program = Program(
        id: 'p1',
        title: 'Spring Fling',
        venueId: 'v1',
        slots: const [],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 20),
      );
      return CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        programs: [program],
        venues: [linked, other],
      );
    }

    test('round-trips an embedded venue and a program.venueId', () {
      final archive = archiveWithVenues();
      final json = encodeArchive(archive);
      final result = decodeArchive(json);

      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.warnings, isEmpty);
      // Design property: re-encoding reproduces the exact bytes.
      expect(encodeArchive(result.archive), json);

      final v1 = result.archive.venues.firstWhere((v) => v.id == 'v1');
      expect(v1, equals(archiveWithVenues().venues.first));
      expect(v1.contact2Email, 'sam@example.com');
      expect(v1.plus4, '1234');
      expect(v1.genericSchedule, '2nd Saturdays');

      final program = result.archive.programs.single;
      expect(program.venueId, 'v1');
    });

    test('stamps a venue-bearing archive at the venue schema version', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      expect(map['schemaVersion'], archiveSchemaVersionVenues);
    });

    test('a program.venueId alone (no venues array) still raises the stamp', () {
      // A dangling venueId with an omitted venues array must still advertise v2
      // so an older reader warns instead of silently dropping the link.
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026),
        programs: [
          Program(
            id: 'p1',
            title: 'Linked',
            venueId: 'v-missing',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final map = jsonDecode(encodeArchive(archive)) as Map<String, Object?>;
      expect(map.containsKey('venues'), isFalse);
      expect(map['schemaVersion'], archiveSchemaVersionVenues);
    });

    test('keeps a venue-less archive at the base version (back-compat)', () {
      final map =
          jsonDecode(encodeArchive(_sampleArchive())) as Map<String, Object?>;
      expect(map['schemaVersion'], archiveSchemaVersionBase);
    });

    test('honors an explicitly higher requested schema version', () {
      final archive = CompendiumArchive(
        schemaVersion: archiveSchemaVersion + 5,
        exportedAt: DateTime.utc(2026),
      );
      final map = jsonDecode(encodeArchive(archive)) as Map<String, Object?>;
      expect(map['schemaVersion'], archiveSchemaVersion + 5);
    });

    test('omits the venues array entirely when there are no venues', () {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026),
        programs: [
          Program(
            id: 'p1',
            title: 'No venue',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final map = jsonDecode(encodeArchive(archive)) as Map<String, Object?>;
      expect(map.containsKey('venues'), isFalse);
      // A program without a venue omits the venueId key too.
      final program = (map['programs'] as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(program.containsKey('venueId'), isFalse);
    });

    test('a legacy bundle with no venues array imports cleanly', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      // Simulate a bundle produced before the venue entity existed.
      map.remove('venues');

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(result.archive.venues, isEmpty);
      // The program still decodes; its venueId (a soft reference) is preserved
      // here — resolving/clearing a now-dangling reference is the restorer's job.
      expect(result.archive.programs.single.venueId, 'v1');
    });

    test('a non-array venues field is reported and skipped', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      map['venues'] = {'not': 'an array'};

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'venue');
      expect(result.archive.venues, isEmpty);
      // Other collections are unaffected.
      expect(result.archive.programs, hasLength(1));
    });

    test('a venues entry that is not an object is skipped', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      (map['venues'] as List).add('i am not an object');

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'venue');
      // The two well-formed venues survived.
      expect(result.archive.venues.map((v) => v.id), containsAll(['v1', 'v2']));
    });

    test(
      'a venue with a blank name is skipped without aborting the import',
      () {
        final map =
            jsonDecode(encodeArchive(archiveWithVenues()))
                as Map<String, Object?>;
        final venues = (map['venues'] as List).cast<Map<String, Object?>>();
        venues.firstWhere((v) => v['id'] == 'v2')['name'] = '   ';

        final result = decodeArchive(jsonEncode(map));
        expect(result.hasErrors, isTrue);
        expect(result.errors.single.entityType, 'venue');
        expect(result.errors.single.entityId, 'v2');
        // The valid venue and the program still load.
        expect(result.archive.venues.map((v) => v.id), ['v1']);
        expect(result.archive.programs, hasLength(1));
      },
    );

    test('a venue field of the wrong type is rejected per-entity', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      final venues = (map['venues'] as List).cast<Map<String, Object?>>();
      // city must be a string; an attacker-supplied number is rejected.
      venues.firstWhere((v) => v['id'] == 'v1')['city'] = 42;

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'venue');
      expect(result.errors.single.entityId, 'v1');
      // The other venue is unaffected.
      expect(result.archive.venues.map((v) => v.id), ['v2']);
    });

    test('a missing required venue id is rejected per-entity', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      final venues = (map['venues'] as List).cast<Map<String, Object?>>();
      venues.firstWhere((v) => v['id'] == 'v1').remove('id');

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'venue');
      expect(result.archive.venues.map((v) => v.id), ['v2']);
    });

    test('unknown/extra venue keys are ignored', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      final venues = (map['venues'] as List).cast<Map<String, Object?>>();
      venues.first['futureField'] = {'anything': true};

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isFalse);
      // Known fields still reconstruct the original venue.
      expect(
        result.archive.venues.firstWhere((v) => v.id == 'v1'),
        equals(archiveWithVenues().venues.first),
      );
    });

    test('a non-string program.venueId is rejected per-entity', () {
      final map =
          jsonDecode(encodeArchive(archiveWithVenues()))
              as Map<String, Object?>;
      final programs = (map['programs'] as List).cast<Map<String, Object?>>();
      programs.single['venueId'] = 7;

      final result = decodeArchive(jsonEncode(map));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.entityType, 'program');
      // Venues are still fully loaded.
      expect(result.archive.venues, hasLength(2));
    });
  });

  group('import sanitization (#444)', () {
    // A hostile archive built BY HAND — `encodeArchive` only ever emits
    // already-clean strings, so the decode-time sanitizer must be exercised
    // with raw JSON that smuggles in control/bidi/format spoofing characters.
    Map<String, Object?> hostileArchive() => {
      'schemaVersion': archiveSchemaVersion,
      'exportedAt': '2026-01-01T00:00:00.000Z',
      'choreographers': [
        {'id': 'c1', 'name': 'Al\u202Eice\u0007'},
      ],
      'dances': [
        {
          'id': 'd1',
          'title': 'Petronella\u202E\u0000',
          'authorIds': ['c1'],
          'phraseStructure': '',
          'hook': 'ho\u200Bok',
          'callingNotes': 'line1\ndan\u0007ger',
          'tunes': ['Tu\uFEFFne'],
          'figures': [
            {
              'move': 'custom',
              'params': {'text': 'balance \u202Eand swing', 'beats': 16},
              'note': 'no\u0007te',
            },
          ],
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      ],
    };

    test('strips control/bidi chars from decoded text before storage', () {
      final result = decodeArchive(jsonEncode(hostileArchive()));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

      final d = result.archive.dances.single;
      expect(d.title, 'Petronella');
      expect(d.hook, 'hook');
      // The legitimate newline survives; only the control byte is removed.
      expect(d.callingNotes, 'line1\ndanger');
      expect(d.tunes, ['Tune']);

      final f = d.figures.single;
      expect(f.params['text'], 'balance and swing');
      expect(f.note, 'note');
      // Non-string params are left untouched.
      expect(f.params['beats'], 16);

      expect(result.archive.choreographers.single.name, 'Alice');
    });

    test('the stored title has no disallowed characters remaining', () {
      final result = decodeArchive(jsonEncode(hostileArchive()));
      final title = result.archive.dances.single.title;
      expect(containsDisallowedText(title), isFalse);
    });

    test('a clean archive still round-trips byte-for-byte (identity)', () {
      // Sanitizing decode must not perturb archives the encoder produced.
      final json = encodeArchive(_sampleArchive());
      expect(encodeArchive(decodeArchive(json).archive), json);
    });

    test('walkthrough survives a JSON round-trip', () {
      // d1 carries a multi-line walkthrough; Dance equality includes it, so the
      // whole-object round-trip below also guards it, but assert explicitly.
      final json = encodeArchive(_sampleArchive());
      final decoded = decodeArchive(
        json,
      ).archive.dances.firstWhere((d) => d.id == 'd1');
      expect(
        decoded.walkthrough,
        'A1: neighbours balance and swing.\n'
        'A2: ladies chain; star left.\nB1: partners balance and swing.',
      );
    });

    test('an over-long walkthrough is clamped on decode (OWASP)', () {
      // A hostile archive with a walkthrough beyond the cap must not fail the
      // import; it is truncated to kMaxWalkthroughLength, not rejected.
      final oversized = 'x' * (kMaxWalkthroughLength + 5000);
      final archive = {
        'schemaVersion': archiveSchemaVersion,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'dances': [
          {
            'id': 'd1',
            'title': 'Long One',
            'authorIds': <String>[],
            'phraseStructure': '',
            'walkthrough': oversized,
            'figures': <Object?>[],
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
          },
        ],
      };
      final result = decodeArchive(jsonEncode(archive));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      expect(
        result.archive.dances.single.walkthrough.length,
        kMaxWalkthroughLength,
      );
    });

    test('control/bidi chars are stripped from a decoded walkthrough', () {
      final archive = {
        'schemaVersion': archiveSchemaVersion,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'dances': [
          {
            'id': 'd1',
            'title': 'Sanitize Me',
            'authorIds': <String>[],
            'phraseStructure': '',
            'walkthrough': 'step1\nstep\u00072\u202E',
            'figures': <Object?>[],
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
          },
        ],
      };
      final result = decodeArchive(jsonEncode(archive));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      // Legitimate newline survives; control byte and bidi override removed.
      expect(result.archive.dances.single.walkthrough, 'step1\nstep2');
    });

    test('figure display overrides round-trip, sanitize, and clamp (#822)', () {
      final archive = {
        'schemaVersion': archiveSchemaVersion,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'dances': [
          {
            'id': 'd1',
            'title': 'Override One',
            'authorIds': <String>[],
            'phraseStructure': '',
            'figures': [
              {
                'move': 'swing',
                'params': {'who': 'partners', 'beats': 16},
                'walkthroughOverride': 'Balance\u0007 and swing.\u202E',
                'wordingOverride': 'Robins\u0007 pass right.\u202E',
              },
              {
                'move': 'circle',
                'params': {'turn': 'left'},
                'walkthroughOverride':
                    'y' * (kMaxWalkthroughSnippetLength + 50),
                'wordingOverride': 'z' * (kMaxWalkthroughSnippetLength + 50),
              },
            ],
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
          },
        ],
      };
      final result = decodeArchive(jsonEncode(archive));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
      final figures = result.archive.dances.single.figures;
      // Control/bidi stripped from the override, exactly like `note`.
      expect(figures[0].walkthroughOverride, 'Balance and swing.');
      expect(figures[0].wordingOverride, 'Robins pass right.');
      // Oversized override truncated, never rejected.
      expect(
        figures[1].walkthroughOverride!.length,
        kMaxWalkthroughSnippetLength,
      );
      expect(figures[1].wordingOverride!.length, kMaxWalkthroughSnippetLength);
    });
  });

  // ---------------------------------------------------------------------------
  // shareable field exclusion (#780)
  // ---------------------------------------------------------------------------

  group('shareable field exclusion (issue #780)', () {
    CompendiumArchive archiveWithExclusion() {
      final shareable = CustomFieldDef(
        id: 'f_shared',
        key: 'region',
        label: 'Region',
        type: CustomFieldType.text,
        shareable: true,
      );
      final private = CustomFieldDef(
        id: 'f_private',
        key: 'email',
        label: 'Organiser email',
        type: CustomFieldType.text,
        shareable: false,
      );
      final dance = Dance(
        id: 'd1',
        title: 'Test Dance',
        customFields: [
          CustomFieldValue(fieldId: 'f_shared', value: 'New England'),
          CustomFieldValue(fieldId: 'f_private', value: 'secret@example.com'),
        ],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      return CompendiumArchive(
        exportedAt: DateTime.utc(2026, 1, 1),
        customFields: [shareable, private],
        dances: [dance],
      );
    }

    test('non-shareable field def is absent from encoded JSON', () {
      final archive = archiveWithExclusion();
      final json = jsonDecode(encodeArchive(archive)) as Map<String, Object?>;
      final fields = (json['customFields'] as List)
          .cast<Map<String, Object?>>();
      final ids = fields.map((f) => f['id'] as String).toList();
      expect(ids, contains('f_shared'));
      expect(
        ids,
        isNot(contains('f_private')),
        reason: 'non-shareable field must not appear in the encoded archive',
      );
    });

    test(
      'dance values for non-shareable field are absent from encoded JSON',
      () {
        final archive = archiveWithExclusion();
        final json = jsonDecode(encodeArchive(archive)) as Map<String, Object?>;
        final dances = (json['dances'] as List).cast<Map<String, Object?>>();
        final values = (dances.single['customFields'] as List)
            .cast<Map<String, Object?>>();
        final fieldIds = values.map((v) => v['fieldId'] as String).toList();
        expect(fieldIds, contains('f_shared'));
        expect(
          fieldIds,
          isNot(contains('f_private')),
          reason:
              'values for non-shareable field must not appear in dance JSON',
        );
      },
    );

    test('shareable field and its values are present in encoded JSON', () {
      // Regression guard: the shareable path must not be accidentally excluded.
      final archive = archiveWithExclusion();
      final json = jsonDecode(encodeArchive(archive)) as Map<String, Object?>;
      final fields = (json['customFields'] as List)
          .cast<Map<String, Object?>>();
      expect(
        fields.any((f) => f['id'] == 'f_shared'),
        isTrue,
        reason: 'shareable field must still appear in the encoded archive',
      );
      final dances = (json['dances'] as List).cast<Map<String, Object?>>();
      final values = (dances.single['customFields'] as List)
          .cast<Map<String, Object?>>();
      expect(
        values.any((v) => v['fieldId'] == 'f_shared'),
        isTrue,
        reason: 'value for shareable field must still appear in dance JSON',
      );
    });

    test(
      'all-shareable archive is bit-identical to baseline (no exclusions)',
      () {
        // Archives that contain no non-shareable fields must produce output
        // identical to before the #780 change — no observer can tell this PR
        // was installed from an archive export alone.
        final baseline =
            _sampleArchive(); // all fields have shareable=true (default)
        final encoded = encodeArchive(baseline);
        final decoded = decodeArchive(encoded);
        expect(decoded.hasErrors, isFalse);
        // Round-trip: re-encoding a decoded archive must match.
        expect(encodeArchive(decoded.archive), encoded);
      },
    );

    test(
      'decoded archive from a non-shareable-field source has shareable=true',
      () {
        // An archive that excluded a field has no entry for it. When the decoded
        // archive is stored and re-exported, the stored fields all have
        // shareable=true (the default). This verifies the decode path's implicit
        // default.
        final archive = archiveWithExclusion();
        final encoded = encodeArchive(archive); // excludes f_private
        final decoded = decodeArchive(encoded);
        expect(decoded.hasErrors, isFalse);
        // Only f_shared survived encoding, and decoded fields default to shareable.
        expect(decoded.archive.customFields, hasLength(1));
        expect(decoded.archive.customFields.single.id, 'f_shared');
        expect(decoded.archive.customFields.single.shareable, isTrue);
      },
    );
  });
}
