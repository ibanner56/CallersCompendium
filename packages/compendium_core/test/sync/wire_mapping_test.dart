import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import '../../tool/generate_sync_allow_list.dart' as generator;
import '../storage/test_database.dart';

final _now = DateTime.utc(2026, 7, 15, 12);

/// The eight entity kinds. `setting` is excluded throughout: its wire fields
/// are resolved per settings key through `settingsRegistry`, not through the
/// archive codec, and are covered by the settings-key cases below.
const _entityKinds = <SyncRecordKind>[
  SyncRecordKind.dance,
  SyncRecordKind.program,
  SyncRecordKind.choreographer,
  SyncRecordKind.publishedSource,
  SyncRecordKind.customFieldDef,
  SyncRecordKind.difficultyLevel,
  SyncRecordKind.tag,
  SyncRecordKind.venue,
];

/// Every registry column the eight entity kinds map a wire path to.
///
/// Derived from the mapping under test, so it cannot drift away from it: a
/// column added to `syncWireFields` is seeded and asserted from the moment it
/// is added, and one removed stops being asserted.
Set<String> get _inScopeColumns => {
  for (final kind in _entityKinds)
    for (final field in syncWireFields[kind]!) ...field.sourceFields,
};

void main() {
  test('the generated artifact is fresh', () {
    expect(
      // Normalize CRLF -> LF so a Windows checkout is compared like-for-like
      // against the LF-emitting generator; only line endings are stripped, so
      // real content drift still fails. See the repository .gitattributes.
      File(
        Directory('packages/compendium_core').existsSync()
            ? 'packages/compendium_core/lib/src/sync/generated_sync_allow_list.dart'
            : 'lib/src/sync/generated_sync_allow_list.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
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
      'difficultyLevels': SyncRecordKind.difficultyLevel,
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
    expect(observedRecords, greaterThanOrEqualTo(8));

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

  // ---------------------------------------------------------------------------
  // Spec §3.3: the registry is keyed snake_case `table.column`, the codec emits
  // bare camelCase, and the mapping between them "MUST be proven by test rather
  // than hand-maintained". `syncWireFields` is hand-written, and the tests above
  // prove only COVERAGE — that every emitted path has an entry, and every
  // shareable column has a path. They do not prove any entry names the RIGHT
  // column. Re-pointing `contact2Phone` at `venues.notes` left the entire
  // compendium_core suite green while the generated allow-list gained
  // `contact2Phone`, admitting a venue contact's phone number on both ends
  // (#1359). That is the fail-open ADR-004's allow-list decision exists to
  // prevent.
  //
  // The two tests below prove every pairing, by dependency rather than by
  // matching values. For each column in turn the fixture is rebuilt with that
  // one column carrying a different value, and the set of wire paths whose
  // value changed must be exactly the set of paths the mapping declares for it.
  //
  // Proving it this way, rather than by seeding a distinct sentinel per column
  // and matching it at its path, is what makes the proof total:
  //   * it holds in BOTH directions — the declared path must change (the
  //     mapping does not under-claim) and no other path may (it does not
  //     over-claim), so a swap between two columns fails twice;
  //   * booleans are covered. Ten columns are `bool`, and a sentinel scheme
  //     cannot give them distinct values, so a pairing swapped between two of
  //     them would be invisible. A change is observable regardless of the value
  //     space;
  //   * so are foreign keys, which must equal the row they reference and
  //     therefore cannot carry a value unique to themselves, and JSON-backed
  //     columns, whose wire value is a structure rather than a scalar;
  //   * a column nothing seeds fails rather than passing vacuously: if the
  //     fixture does not wire a column through, varying it changes nothing and
  //     the expected path set is not empty.
  //
  // What they do NOT prove is that the fixture puts each value in the column it
  // names — the model-field-to-column half of the chain. That is what
  // `every seeded value reaches the registry column that names it` below
  // anchors, against the real schema.
  test('every wire path depends on exactly the columns it declares', () {
    final unproven = <String>[];
    for (final column in _inScopeColumns) {
      final expected = _pathsDeclaring(column);
      final actual = _changedPaths(column, projected: false);
      if (!_sameTargets(actual, expected)) {
        unproven.add(
          '$column\n'
          '     mapping declares: ${_format(expected)}\n'
          '     actually reaches: ${_format(actual)}',
        );
      }
    }
    expect(
      unproven,
      isEmpty,
      reason:
          'Changing these columns did not change exactly the wire paths\n'
          '`syncWireFields` says they feed. A column reaching a path it does '
          'not\ndeclare is a mis-pairing: the path inherits the wrong '
          'classification.\n\n${unproven.join('\n')}\n',
    );
  });

  test('projection admits a column exactly when its class allows egress', () {
    final leaks = <String>[];
    for (final column in _inScopeColumns) {
      // `custom_field_defs.shareable` is the one column that controls egress of
      // another rather than travelling as an ordinary field: with it false the
      // whole definition and all its values are withheld (`field_registry.dart`
      // custom_field_defs.shareable, #780), so varying it changes every path of
      // that kind by design. Its own pairing is proven by the test above, which
      // reads the unprojected body, and the behaviour it controls is asserted
      // in 'withholds a non-shareable custom field definition entirely' below.
      if (column == 'custom_field_defs.shareable') continue;
      final shareable =
          fieldClassifications[column]!.egress == EgressClass.shareable;
      final expected = shareable ? _pathsDeclaring(column) : const <_Target>{};
      final actual = _changedPaths(column, projected: true);
      if (!_sameTargets(actual, expected)) {
        leaks.add(
          '$column (${fieldClassifications[column]!.egress.name})\n'
          '     may reach: ${_format(expected)}\n'
          '     reaches:   ${_format(actual)}',
        );
      }
    }
    expect(
      leaks,
      isEmpty,
      reason:
          'A non-shareable column must reach no wire path after projection, '
          'and a\nshareable one must still reach its own. This is not a '
          'vacuous absence\ncheck: the test above proves each of these columns '
          'does reach its path\nBEFORE projection, so a column that stops '
          'mattering here was really\nwithheld rather than never seeded.'
          '\n\n${leaks.join('\n')}\n',
    );
  });

  // The two tests above prove the wire half of the chain: wire path P carries
  // registry column C. They take the fixture's word for the other half — that
  // putting a value in model field M is putting it in column C. Nothing else
  // checks that. `data_classification_coverage_test.dart` proves every registry
  // key names a real schema column, in both directions, but not that the right
  // value reaches it; and a repository round-trip test writes and reads through
  // the same mapping, so a field consistently persisted to the wrong column
  // round-trips perfectly.
  //
  // That gap matters because the classification is attached to the COLUMN. If
  // `Venue.contact2Phone` were persisted to `venues.notes`, the privacy
  // decision recorded for `venues.contact2_phone` would govern a column the
  // value never reaches, and the phone number would be travelling under
  // `venues.notes`'s shareable classification — the same fail-open as a wrong
  // pairing, one layer down.
  //
  // So this runs the same differential against the real schema: vary one
  // column's seed, persist through the ordinary repositories, and require the
  // stored value to change in that column and no other. Because it compares a
  // column against itself across two writes, it needs to know nothing about how
  // drift stores an enum, a date or a JSON blob.
  //
  // It anchors the WRITE path. Reading back into a model shares these table
  // definitions and is covered by the repositories' own round-trip tests.
  test('every seeded value reaches the registry column that names it', () async {
    // A foreign key holds, by definition, the value of the primary key it
    // references, so moving one moves both and no write can tell them apart.
    // That is a property of the schema, not a gap in the fixture, and it is
    // declared rather than skipped so an undeclared inseparable pair still
    // fails. It is privacy-neutral only because both sides carry the same
    // classification, which is asserted below rather than assumed: if a key
    // column were ever classified differently from the key it points at, this
    // aliasing would be hiding exactly the mismatch the test exists to find.
    const keyAliases = <String, String>{
      'dance_authors.choreographer_id': 'choreographers.id',
      'dance_tags.tag_id': 'tags.id',
      'dance_sources.source_id': 'published_sources.id',
      'dance_links.target_dance_id': 'dances.id',
      'dances.level_id': 'difficulty_levels.id',
      'custom_field_values.field_id': 'custom_field_defs.id',
      'programs.venue_id': 'venues.id',
      'program_slots.dance_id': 'dances.id',
    };
    for (final MapEntry(key: foreign, value: primary) in keyAliases.entries) {
      expect(
        fieldClassifications[foreign]!.egress,
        fieldClassifications[primary]!.egress,
        reason: '$foreign and $primary must not be classified apart',
      );
    }

    final baseline = await _storedColumns(_Fixture(null));
    final misplaced = <String>[];
    for (final column in _inScopeColumns) {
      final varied = await _storedColumns(_Fixture(column));
      final changed = <String>{
        for (final key in _inScopeColumns)
          if (!_sameValues(baseline[key]!, varied[key]!)) key,
      };
      final expected = <String>{
        column,
        if (keyAliases.containsKey(column)) keyAliases[column]!,
      };
      if (!(changed.length == expected.length &&
          changed.containsAll(expected))) {
        final landed = changed.isEmpty
            ? '(nothing)'
            : (changed.toList()..sort()).join(', ');
        misplaced.add(
          '$column changed: $landed '
          '(expected ${(expected.toList()..sort()).join(', ')})',
        );
      }
    }
    expect(
      misplaced,
      isEmpty,
      reason:
          'These fixture values did not land in the column the mapping names '
          'them by,\nso the classification recorded for that column is not the '
          'one governing\nthe value its wire path carries.\n\n'
          '${misplaced.join('\n')}\n',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a multi-source wire path is admitted only when every column is', () {
    // `customFields.value` is the only path with more than one source column,
    // and both are shareable today, so the generator's rule is not observable
    // from the committed registry. Classifying either one out must remove the
    // path: admitting it because the OTHER column is shareable would emit both
    // (#1359). `fieldClassifications` is a mutable top-level map, which is how
    // the settings-prefix case below injects a classification too.
    const path = 'customFields.value';
    final columns = sourceFieldsForWirePath(SyncRecordKind.dance, path);
    expect(columns, hasLength(2));
    expect(
      generator.renderSyncAllowList(),
      contains("'$path'"),
      reason: 'both columns are shareable today',
    );

    for (final column in columns) {
      final original = fieldClassifications[column]!;
      fieldClassifications[column] = const DataClassification(
        term: DpvTerm.emailAddress,
        subject: DataSubject.thirdParty,
        egress: EgressClass.deviceLocal,
      );
      try {
        expect(
          generator.renderSyncAllowList(),
          isNot(contains("'$path'")),
          reason:
              'with $column non-shareable, $path must fail closed rather than '
              'ride in on its sibling',
        );
      } finally {
        fieldClassifications[column] = original;
      }
    }
  });

  test('withholds a non-shareable custom field definition entirely', () {
    final private = CustomFieldDef(
      id: 'private',
      key: 'private',
      label: 'Private',
      type: CustomFieldType.text,
      shareable: false,
    );
    expect(syncBodyForEntity(SyncRecordKind.customFieldDef, private), isEmpty);
  });

  test('projects only allowed custom field values and validates bodies', () {
    final fixture = _Fixture(null);
    final dance = fixture.dance();
    final projected = syncBodyForEntity(
      SyncRecordKind.dance,
      dance,
      allowedCustomFieldIds: fixture.allowedCustomFieldIds,
    );
    expect(projected, isNotEmpty);
    expect(
      validateShareableRecordBody(SyncRecordKind.dance, projected).isValid,
      isTrue,
    );

    // A value whose definition is not in the allowed set is dropped even though
    // `customFields.value` is an admitted path.
    final withheld = syncBodyForEntity(
      SyncRecordKind.dance,
      dance,
      allowedCustomFieldIds: const {},
    );
    expect(withheld['customFields'], isEmpty);

    final choreographer = syncBodyForEntity(
      SyncRecordKind.choreographer,
      fixture.choreographer(),
    );
    final unknown = Map<String, Object?>.from(choreographer)
      ..['futureField'] = 'unknown';
    expect(
      validateShareableRecordBody(
        SyncRecordKind.choreographer,
        unknown,
      ).invalidPath,
      'futureField',
    );
  });

  test('accepts queued legacy program timing as dance timing', () {
    final blob = SyncRecordBlob.fromJson({
      'v': syncWireVersion,
      'kind': 'program',
      'id': 'p1',
      'updatedAt': '2026-07-15T12:00:00Z',
      'deletedAt': null,
      'existenceAt': '2026-07-15T12:00:00Z',
      'body': {
        'id': 'p1',
        'slots': [
          {
            'id': 's1',
            'position': 0,
            'danceId': 'd1',
            'isAlt': false,
            'plannedMinutes': 8,
          },
        ],
      },
    });

    final slot = (blob.body['slots']! as List).single as Map<String, Object?>;
    expect(slot['plannedMinutes'], isNull);
    expect(slot['danceMinutes'], 8);
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

// ---------------------------------------------------------------------------
// Differential pairing machinery
// ---------------------------------------------------------------------------

/// One (kind, wire path) pair.
typedef _Target = ({SyncRecordKind kind, String path});

/// The wire paths `syncWireFields` says [column] feeds.
Set<_Target> _pathsDeclaring(String column) => {
  for (final kind in _entityKinds)
    for (final field in syncWireFields[kind]!)
      if (field.sourceFields.contains(column)) (kind: kind, path: field.path),
};

/// The wire paths whose value changes when only [column] changes.
///
/// [projected] selects the boundary: `false` reads the archive body the codec
/// builds from the entity, `true` reads what `syncBodyForEntity` actually puts
/// on the wire — the same body after the allow-list projection. The difference
/// between the two is precisely the egress decision.
Set<_Target> _changedPaths(String column, {required bool projected}) {
  final before = _bodies(null, projected: projected);
  final after = _bodies(column, projected: projected);
  final changed = <_Target>{};
  for (final kind in _entityKinds) {
    final left = _leafValues(kind, before[kind]!);
    final right = _leafValues(kind, after[kind]!);
    for (final path in {...left.keys, ...right.keys}) {
      if (left[path] != right[path]) changed.add((kind: kind, path: path));
    }
  }
  return changed;
}

Map<SyncRecordKind, Map<String, Object?>> _bodies(
  String? varied, {
  required bool projected,
}) {
  final fixture = _Fixture(varied);
  Map<String, Object?> body(SyncRecordKind kind, Object entity) => projected
      ? syncBodyForEntity(
          kind,
          entity,
          allowedCustomFieldIds: fixture.allowedCustomFieldIds,
        )
      : _archiveBody(kind, entity);
  return {
    SyncRecordKind.dance: body(SyncRecordKind.dance, fixture.dance()),
    SyncRecordKind.program: body(SyncRecordKind.program, fixture.program()),
    SyncRecordKind.choreographer: body(
      SyncRecordKind.choreographer,
      fixture.choreographer(),
    ),
    SyncRecordKind.publishedSource: body(
      SyncRecordKind.publishedSource,
      fixture.publishedSource(),
    ),
    SyncRecordKind.customFieldDef: body(
      SyncRecordKind.customFieldDef,
      fixture.customFieldDef(),
    ),
    SyncRecordKind.difficultyLevel: body(
      SyncRecordKind.difficultyLevel,
      fixture.difficultyLevel(),
    ),
    SyncRecordKind.tag: body(SyncRecordKind.tag, fixture.tag()),
    SyncRecordKind.venue: body(SyncRecordKind.venue, fixture.venue()),
  };
}

/// The archive body `syncBodyForEntity` projects, before it projects it.
///
/// This mirrors that function's own switch (`sync_codec.dart`) rather than
/// calling it, because the unprojected body is exactly what the projection step
/// consumes and there is no other way to observe it. Keeping the same
/// `includeOptionalFields: true` matters: without it an absent optional field
/// and a withheld one look alike.
Map<String, Object?> _archiveBody(SyncRecordKind kind, Object entity) =>
    switch (kind) {
      SyncRecordKind.dance => archiveDanceToJson(
        entity as Dance,
        const {},
        includeOptionalFields: true,
      ),
      SyncRecordKind.program => archiveProgramToJson(
        entity as Program,
        includeOptionalFields: true,
      ),
      SyncRecordKind.choreographer => archiveChoreographerToJson(
        entity as Choreographer,
        includeOptionalFields: true,
      ),
      SyncRecordKind.tag => archiveTagToJson(
        entity as Tag,
        includeOptionalFields: true,
      ),
      SyncRecordKind.publishedSource => archivePublishedSourceToJson(
        entity as PublishedSource,
        includeOptionalFields: true,
      ),
      SyncRecordKind.customFieldDef => archiveCustomFieldDefToJson(
        entity as CustomFieldDef,
        includeShareable: true,
        includeOptionalFields: true,
      ),
      SyncRecordKind.difficultyLevel => archiveDifficultyLevelToJson(
        entity as DifficultyLevel,
      ),
      SyncRecordKind.venue => archiveVenueToJson(
        entity as Venue,
        includeOptionalFields: true,
      ),
      SyncRecordKind.setting => throw StateError('settings have no entity'),
    };

/// Flattens [body] to wire path -> encoded value.
///
/// Structural containers recurse (their descendants carry the columns); a
/// mapped leaf does not, so a column whose wire value is a JSON structure —
/// `figures`, `tunes`, `choices` — is compared whole rather than walked into.
/// List elements collapse onto the container's path, which is how the mapping
/// addresses them (`links.url`, not `links.0.url`).
Map<String, Object?> _leafValues(
  SyncRecordKind kind,
  Map<String, Object?> body,
) {
  final values = <String, List<Object?>>{};
  void walk(String path, Object? value) {
    if (value is List && _isContainer(kind, path)) {
      for (final item in value) {
        walk(path, item);
      }
      return;
    }
    if (value is Map && _isContainer(kind, path)) {
      for (final entry in value.entries) {
        if (entry.key is! String) continue;
        final child = path.isEmpty ? entry.key as String : '$path.${entry.key}';
        walk(child, entry.value);
      }
      return;
    }
    (values[path] ??= []).add(value);
  }

  walk('', body);
  return {
    for (final entry in values.entries) entry.key: jsonEncode(entry.value),
  };
}

/// Whether [path] is a structural container rather than a mapped leaf. The root
/// always is; otherwise the mapping decides, so the walk stops exactly where
/// `syncWireFields` says a column begins.
bool _isContainer(SyncRecordKind kind, String path) {
  if (path.isEmpty) return true;
  for (final field in syncWireFields[kind]!) {
    if (field.path == path) return field.sourceFields.isEmpty;
  }
  // An unmapped path is walked so that whatever it carries is still observed;
  // the coverage test above is what fails when one exists.
  return true;
}

// ---------------------------------------------------------------------------
// Schema anchor
// ---------------------------------------------------------------------------

/// Writes [fixture]'s entities through the ordinary repositories and reads back
/// every in-scope column.
///
/// Only in-scope columns are read. The bookkeeping columns beside them —
/// `existence_at` above all — are stamped from the clock on write, so including
/// them would make every pair of runs differ for reasons that have nothing to
/// do with the column under test.
Future<Map<String, List<Object?>>> _storedColumns(_Fixture fixture) async {
  final db = openTestDatabase();
  try {
    final choreographers = ChoreographerRepository(db);
    for (final record in [
      fixture.choreographer(),
      ...fixture.auxChoreographers(),
    ]) {
      _expectKept(await choreographers.upsert(record), record.id);
    }
    final tags = TagRepository(db);
    for (final record in [fixture.tag(), ...fixture.auxTags()]) {
      _expectKept(await tags.upsert(record), record.id);
    }
    final sources = PublishedSourceRepository(db);
    for (final record in [
      fixture.publishedSource(),
      ...fixture.auxPublishedSources(),
    ]) {
      await sources.upsert(record);
    }
    final levels = DifficultyLevelRepository(db);
    for (final record in [
      fixture.difficultyLevel(),
      ...fixture.auxDifficultyLevels(),
    ]) {
      await levels.upsert(record);
    }
    final defs = CustomFieldDefRepository(db);
    for (final record in [
      fixture.customFieldDef(),
      ...fixture.auxCustomFieldDefs(),
    ]) {
      _expectKept(await defs.upsert(record), record.id);
    }
    final venues = VenueRepository(db);
    for (final record in [fixture.venue(), ...fixture.auxVenues()]) {
      await venues.upsert(record);
    }
    final dances = DanceRepository(db, contraTaxonomy);
    for (final record in [...fixture.auxDances(), fixture.dance()]) {
      await dances.create(record);
    }
    await ProgramRepository(db).create(fixture.program());

    final stored = <String, List<Object?>>{};
    for (final column in _inScopeColumns) {
      final dot = column.indexOf('.');
      final table = column.substring(0, dot);
      final name = column.substring(dot + 1);
      final rows = await db
          .customSelect('SELECT "$name" AS value FROM "$table"')
          .get();
      stored[column] = [for (final row in rows) row.data['value']]
        ..sort((a, b) => '$a'.compareTo('$b'));
    }
    return stored;
  } finally {
    await db.close();
  }
}

/// These repositories return the id the record actually occupies, because a
/// write whose natural key already belongs to another row adopts that row
/// instead (`TagRepository.upsert`). Adoption would silently repoint the
/// fixture's foreign keys at a record it did not build, so it is asserted
/// against rather than ignored.
void _expectKept(String actualId, String requestedId) => expect(
  actualId,
  requestedId,
  reason: 'the fixture must not collide with an existing natural key',
);

bool _sameValues(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameTargets(Set<_Target> left, Set<_Target> right) =>
    left.length == right.length && left.containsAll(right);

String _format(Set<_Target> targets) {
  if (targets.isEmpty) return '(nothing)';
  final rendered = [
    for (final target in targets) '${target.kind.name}.${target.path}',
  ]..sort();
  return rendered.join(', ');
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

/// Columns whose value is not a plain string, with the two values the fixture
/// alternates between. Every other in-scope column defaults to a pair of
/// strings derived from its own name.
///
/// The pairs need only differ from each other; they do not need to be unique
/// across columns, because each column is varied on its own and the assertion
/// is which paths CHANGED.
const _valuePairs = <String, List<Object?>>{
  'choreographers.deceased': [false, true],
  'dances.form': ['contra', 'ecd'],
  'dances.formation_shape': ['becketCw', 'dupleProper'],
  'dances.progression': ['single', 'triple'],
  'dances.status': ['active', 'draft'],
  'dances.phrase_structure': ['6*8*2', '4*8*2'],
  'dances.rating': [3, 4],
  'dances.mixed_level': [false, true],
  'dances.mixer': [false, true],
  'dances.composed_on': ['1989', '1990'],
  'dances.revised_on': ['2004-03-15', '2005-04-16'],
  'dances.created_at': _earlier,
  'dances.updated_at': _earlier,
  'dances.deleted_at': _earlier,
  'dance_links.kind': ['video', 'source'],
  'dance_links.transitive': [false, true],
  'custom_field_values.value_num': [41, 42],
  'custom_field_defs.type': ['choice', 'text'],
  'custom_field_defs.show_in_list': [false, true],
  'custom_field_defs.searchable': [false, true],
  'custom_field_defs.shareable': [true, false],
  'difficulty_levels.position': [2, 3],
  'tags.color': [7, 8],
  'published_sources.year': [1983, 1984],
  'programs.event_date': _earlier,
  'programs.status': ['draft', 'performed'],
  'programs.hide_alternates': [false, true],
  'programs.created_at': _earlier,
  'programs.updated_at': _earlier,
  'programs.deleted_at': _earlier,
  'program_slots.position': [0, 1],
  'program_slots.is_alt': [false, true],
  'program_slots.is_purged_dance': [false, true],
  'program_slots.walkthrough_minutes': [3, 4],
  'program_slots.dance_minutes': [9, 10],
  'program_slots.performed_at': _earlier,
  'provenance.source': ['callersbox', 'contradb'],
  'provenance.imported_at': _earlier,
  'program_provenance.source': ['callersbox', 'contradb'],
  'program_provenance.imported_at': _earlier,
  'venue_provenance.source': ['callersbox', 'contradb'],
  'venue_provenance.imported_at': _earlier,
};

const _earlier = ['2031-01-05T00:00:00.000Z', '2032-02-06T00:00:00.000Z'];

/// Ids of records that exist only so a foreign-key column has something to
/// point at. They are never the subject of an assertion, so they carry no seed.
const _auxNumberFieldId = 'aux-number-field';
const _auxLinkId = 'aux-related-link';
const _auxSlotId = 'aux-slot';

/// Builds the eight subject entities with at most one column varied.
///
/// Every in-scope column is wired through exactly one model field here. That
/// wiring is the one hand-written step left in the chain, and it is not taken
/// on trust: a column wired to the wrong model field changes the wrong wire
/// path and fails the pairing test, and a column wired nowhere changes nothing
/// and fails it too.
class _Fixture {
  _Fixture(this._varied);

  final String? _varied;

  Object? _raw(String column) {
    final pair = _valuePairs[column] ?? [column, '$column (varied)'];
    return pair[_varied == column ? 1 : 0];
  }

  String _str(String column) => _raw(column)! as String;
  int _int(String column) => _raw(column)! as int;
  bool _flag(String column) => _raw(column)! as bool;
  DateTime _date(String column) => DateTime.parse(_str(column));

  /// Both values of the custom-field-definition id, so varying that column
  /// changes which definition a value cites without also withholding the value
  /// — the projection drops a value whose definition is not allowed, which
  /// would otherwise register as a change at `customFields.value` too.
  Set<String> get allowedCustomFieldIds => {
    'custom_field_values.field_id',
    'custom_field_values.field_id (varied)',
    _auxNumberFieldId,
  };

  // The records that exist only so a foreign-key column has a row to point at.
  // They are built from the same accessors as the values that cite them, so
  // varying a key column moves the citation and its target together instead of
  // leaving a dangling reference.
  List<Choreographer> auxChoreographers() => [
    Choreographer(
      id: _str('dance_authors.choreographer_id'),
      name: 'Aux Author',
    ),
  ];

  List<Tag> auxTags() => [Tag(id: _str('dance_tags.tag_id'), name: 'aux tag')];

  List<PublishedSource> auxPublishedSources() => [
    PublishedSource(id: _str('dance_sources.source_id'), title: 'Aux Source'),
  ];

  List<DifficultyLevel> auxDifficultyLevels() => [
    DifficultyLevel(
      id: _str('dances.level_id'),
      label: 'Aux Level',
      position: 97,
    ),
  ];

  List<CustomFieldDef> auxCustomFieldDefs() => [
    CustomFieldDef(
      id: _str('custom_field_values.field_id'),
      key: 'aux_text',
      label: 'Aux Text',
      type: CustomFieldType.text,
    ),
    CustomFieldDef(
      id: _auxNumberFieldId,
      key: 'aux_number',
      label: 'Aux Number',
      type: CustomFieldType.number,
    ),
  ];

  List<Venue> auxVenues() => [
    Venue(id: _str('programs.venue_id'), name: 'Aux Venue'),
  ];

  List<Dance> auxDances() => [
    for (final id in {
      _str('dance_links.target_dance_id'),
      _str('program_slots.dance_id'),
    })
      Dance(
        id: id,
        title: 'Aux Dance',
        createdAt: DateTime.utc(2030),
        updatedAt: DateTime.utc(2030),
      ),
  ];

  Choreographer choreographer() => Choreographer(
    id: _str('choreographers.id'),
    name: _str('choreographers.name'),
    website: _str('choreographers.website'),
    notes: _str('choreographers.notes'),
    email: _str('choreographers.email'),
    location: _str('choreographers.location'),
    deceased: _flag('choreographers.deceased'),
  );

  PublishedSource publishedSource() => PublishedSource(
    id: _str('published_sources.id'),
    title: _str('published_sources.title'),
    author: _str('published_sources.author'),
    year: _int('published_sources.year'),
    url: _str('published_sources.url'),
    notes: _str('published_sources.notes'),
  );

  Tag tag() => Tag(
    id: _str('tags.id'),
    name: _str('tags.name'),
    color: _int('tags.color'),
  );

  DifficultyLevel difficultyLevel() => DifficultyLevel(
    id: _str('difficulty_levels.id'),
    label: _str('difficulty_levels.label'),
    position: _int('difficulty_levels.position'),
  );

  CustomFieldDef customFieldDef() => CustomFieldDef(
    id: _str('custom_field_defs.id'),
    key: _str('custom_field_defs.key'),
    label: _str('custom_field_defs.label'),
    type: CustomFieldType.values.byName(_str('custom_field_defs.type')),
    choices: [_str('custom_field_defs.choices_json')],
    showInList: _flag('custom_field_defs.show_in_list'),
    searchable: _flag('custom_field_defs.searchable'),
    shareable: _flag('custom_field_defs.shareable'),
  );

  Dance dance() => Dance(
    id: _str('dances.id'),
    title: _str('dances.title'),
    authorIds: [_str('dance_authors.choreographer_id')],
    form: DanceForm.values.byName(_str('dances.form')),
    formation: Formation(
      FormationShape.values.byName(_str('dances.formation_shape')),
      detail: _str('dances.formation_detail'),
    ),
    progression: Progression.values.byName(_str('dances.progression')),
    phraseStructure: _str('dances.phrase_structure'),
    // The seed rides in `note`, which is free text, so the figure stays valid
    // under the taxonomy while still varying the encoded `figures_json`.
    // `testFigure` is required rather than `Figure` because a fixture built
    // from variables cannot be checked by reading the source — see the figure
    // fixture ratchet in `package:compendium_core/testing.dart`.
    figures: [
      testFigure(
        move: 'swing',
        params: const {'who': 'partners'},
        note: _str('dances.figures_json'),
      ),
    ],
    hook: _str('dances.hook'),
    callingNotes: _str('dances.calling_notes'),
    walkthrough: _str('dances.walkthrough'),
    status: DanceStatus.values.byName(_str('dances.status')),
    difficultyLevelId: _str('dances.level_id'),
    mixedLevel: _flag('dances.mixed_level'),
    mixer: _flag('dances.mixer'),
    rating: _int('dances.rating'),
    tunes: [_str('dances.tunes_json')],
    customFields: [
      CustomFieldValue(
        fieldId: _str('custom_field_values.field_id'),
        value: _str('custom_field_values.value_text'),
      ),
      CustomFieldValue(
        fieldId: _auxNumberFieldId,
        value: _int('custom_field_values.value_num'),
      ),
    ],
    tagIds: [_str('dance_tags.tag_id')],
    links: [
      DanceLink(
        id: _str('dance_links.id'),
        kind: LinkKind.values.byName(_str('dance_links.kind')),
        url: _str('dance_links.url'),
        label: _str('dance_links.label'),
      ),
      // A second link, because the model forbids one record from carrying both
      // a url and a targetDanceId, and allows `transitive` only on a
      // related-dance link.
      DanceLink(
        id: _auxLinkId,
        kind: LinkKind.relatedDance,
        targetDanceId: _str('dance_links.target_dance_id'),
        transitive: _flag('dance_links.transitive'),
      ),
    ],
    sourceCitations: [
      SourceCitation(
        sourceId: _str('dance_sources.source_id'),
        page: _str('dance_sources.page'),
        number: _str('dance_sources.number'),
      ),
    ],
    provenance: Provenance(
      source: ProvenanceSource.values.byName(_str('provenance.source')),
      externalId: _str('provenance.external_id'),
      importedAt: _date('provenance.imported_at'),
      permission: _str('provenance.permission'),
      license: _str('provenance.license'),
      sourceVersion: _str('provenance.source_version'),
    ),
    composedOn: PartialDate.parse(_str('dances.composed_on')),
    revisedOn: PartialDate.parse(_str('dances.revised_on')),
    createdAt: _date('dances.created_at'),
    updatedAt: _date('dances.updated_at'),
    deletedAt: _date('dances.deleted_at'),
  );

  Program program() => Program(
    id: _str('programs.id'),
    title: _str('programs.title'),
    eventDate: _date('programs.event_date'),
    venue: _str('programs.venue'),
    venueId: _str('programs.venue_id'),
    band: _str('programs.band'),
    caller: _str('programs.caller'),
    dancerLevel: _str('programs.dancer_level'),
    notes: _str('programs.notes'),
    status: ProgramStatus.values.byName(_str('programs.status')),
    hideAlternates: _flag('programs.hide_alternates'),
    slots: [
      ProgramSlot(
        id: _str('program_slots.id'),
        position: _int('program_slots.position'),
        danceId: _str('program_slots.dance_id'),
        text: _str('program_slots.text'),
        isPurgedDance: false,
        isAlt: _flag('program_slots.is_alt'),
        guestCaller: _str('program_slots.guest_caller'),
        walkthroughMinutes: _int('program_slots.walkthrough_minutes'),
        danceMinutes: _int('program_slots.dance_minutes'),
        performedAt: _date('program_slots.performed_at'),
      ),
      // A purged slot must have no danceId and some text, so it cannot be the
      // slot that seeds `dance_id`. Its position stays clear of the first
      // slot's two values, which `Program` would otherwise reorder around.
      ProgramSlot(
        id: _auxSlotId,
        position: 5,
        text: 'aux slot text',
        isPurgedDance: _flag('program_slots.is_purged_dance'),
      ),
    ],
    provenance: Provenance(
      source: ProvenanceSource.values.byName(_str('program_provenance.source')),
      externalId: _str('program_provenance.external_id'),
      importedAt: _date('program_provenance.imported_at'),
      permission: _str('program_provenance.permission'),
      license: _str('program_provenance.license'),
      sourceVersion: _str('program_provenance.source_version'),
    ),
    createdAt: _date('programs.created_at'),
    updatedAt: _date('programs.updated_at'),
    deletedAt: _date('programs.deleted_at'),
  );

  Venue venue() => Venue(
    id: _str('venues.id'),
    name: _str('venues.name'),
    address1: _str('venues.address1'),
    address2: _str('venues.address2'),
    city: _str('venues.city'),
    stateProv: _str('venues.state_prov'),
    country: _str('venues.country'),
    postalCode: _str('venues.postal_code'),
    plus4: _str('venues.plus4'),
    website: _str('venues.website'),
    sponsor: _str('venues.sponsor'),
    eventName: _str('venues.event_name'),
    time: _str('venues.time'),
    genericSchedule: _str('venues.generic_schedule'),
    price: _str('venues.price'),
    notes: _str('venues.notes'),
    contact1Name: _str('venues.contact1_name'),
    contact1Phone: _str('venues.contact1_phone'),
    contact1Email: _str('venues.contact1_email'),
    contact2Name: _str('venues.contact2_name'),
    contact2Phone: _str('venues.contact2_phone'),
    contact2Email: _str('venues.contact2_email'),
    provenance: Provenance(
      source: ProvenanceSource.values.byName(_str('venue_provenance.source')),
      externalId: _str('venue_provenance.external_id'),
      importedAt: _date('venue_provenance.imported_at'),
      permission: _str('venue_provenance.permission'),
      license: _str('venue_provenance.license'),
      sourceVersion: _str('venue_provenance.source_version'),
    ),
  );
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

/// The seeded entities as a whole archive, plus the auxiliary records the
/// foreign-key columns point at, so the archive is internally consistent.
CompendiumArchive _sampleArchive() {
  final fixture = _Fixture(null);
  return CompendiumArchive(
    exportedAt: _now,
    dances: [fixture.dance()],
    programs: [fixture.program()],
    choreographers: [fixture.choreographer(), ...fixture.auxChoreographers()],
    publishedSources: [
      fixture.publishedSource(),
      ...fixture.auxPublishedSources(),
    ],
    customFields: [
      fixture.customFieldDef(),
      ...fixture.auxCustomFieldDefs(),
      // Not an auxiliary: the record the 'withholds a non-shareable custom
      // field definition entirely' contract needs present in a real archive.
      CustomFieldDef(
        id: 'private',
        key: 'private',
        label: 'Private',
        type: CustomFieldType.text,
        shareable: false,
      ),
    ],
    difficultyLevels: [
      fixture.difficultyLevel(),
      ...fixture.auxDifficultyLevels(),
    ],
    tags: [fixture.tag(), ...fixture.auxTags()],
    venues: [fixture.venue(), ...fixture.auxVenues()],
  );
}
