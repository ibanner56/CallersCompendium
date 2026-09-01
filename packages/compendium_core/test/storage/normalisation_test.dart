import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show DriftSqlType, Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

Future<String> _preFixNormalisationScope(CompendiumDatabase db) async {
  final columns = <String>[];
  for (final table in db.allTables) {
    final primaryKeys = table.$primaryKey.map((column) => column.name).toSet();
    for (final column in table.$columns) {
      final classification =
          fieldClassifications['${table.actualTableName}.${column.name}'];
      if (column.type != DriftSqlType.string ||
          classification?.egress != EgressClass.shareable ||
          classification!.isIdentity ||
          primaryKeys.contains(column.name)) {
        continue;
      }
      columns.add('${table.actualTableName}.${column.name}');
    }
  }
  columns.sort();
  return jsonEncode(columns);
}

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('backfill normalizes duplicate non-unique text independently', () async {
    const decomposed = 'cafe\u0301';
    await db.customStatement(
      'INSERT INTO published_sources (id, title) VALUES (?, ?)',
      ['source-1', decomposed],
    );
    await db.customStatement(
      'INSERT INTO published_sources (id, title) VALUES (?, ?)',
      ['source-2', decomposed],
    );

    await repos.ensureMigrated();

    final rows = await db
        .customSelect('SELECT title FROM published_sources ORDER BY id')
        .get();
    expect(
      [for (final row in rows) row.read<String>('title')],
      ['café', 'café'],
    );
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
    );
  });

  test('backfill leaves identity columns untouched', () async {
    await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
      'id\u0301',
      'tag',
    ]);
    await repos.ensureMigrated();

    final row = await db
        .customSelect('SELECT id FROM tags LIMIT 1')
        .getSingle();
    expect(row.read<String>('id'), 'id\u0301');
  });

  test(
    'corrected normalization reruns when the pre-fix scope marker is present',
    () async {
      final oldUpdatedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      await repos.dances.create(
        sampleDance(
          id: 'd1',
          title: 'Original',
          createdAt: oldUpdatedAt,
          updatedAt: oldUpdatedAt,
        ),
      );
      final before = await db
          .customSelect(
            'SELECT updated_at, existence_at, deleted_at FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
        'e\u200B\u0301',
        'd1',
      ]);

      await db.customStatement(
        'INSERT INTO settings (key, value_json) VALUES (?, ?)',
        [
          shareableTextNormalisationScopeKey,
          await _preFixNormalisationScope(db),
        ],
      );

      await repos.ensureMigrated();

      final row = await db
          .customSelect(
            'SELECT title, updated_at, existence_at, deleted_at '
            'FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(row.read<String>('title'), 'é');
      expect(row.data['updated_at'], before.data['updated_at']);
      expect(row.data['existence_at'], before.data['existence_at']);
      expect(row.data['deleted_at'], before.data['deleted_at']);

      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [
              const Variable<String>(shareableTextNormalisationScopeKey),
            ],
          )
          .getSingle();
      expect(
        marker.read<String>('value_json'),
        isNot(await _preFixNormalisationScope(db)),
      );
      expect(marker.read<String>('value_json'), contains('"version":2'));
    },
  );

  test('backfill repairs tombstoned shareable settings', () async {
    await db.customStatement(
      'INSERT INTO settings (key, value_json, deleted_at) VALUES (?, ?, ?)',
      ['custom_dialects', '{"café":"value"}', '2026-01-01T00:00:00.000Z'],
    );

    await repos.ensureMigrated();

    final row = await db
        .customSelect(
          'SELECT value_json, deleted_at FROM settings WHERE key = ?',
          variables: [const Variable<String>('custom_dialects')],
        )
        .getSingle();
    expect(row.read<String>('value_json'), '{"café":"value"}');
    expect(row.read<String>('deleted_at'), isNotNull);
  });

  test('backfill preserves settings with colliding normalized keys', () async {
    final raw = jsonEncode({'café': 'first', 'cafe\u0301': 'second'});
    await db.customStatement(
      'INSERT INTO settings (key, value_json) VALUES (?, ?)',
      ['custom_dialects', raw],
    );

    await repos.ensureMigrated();

    final row = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ?',
          variables: [const Variable<String>('custom_dialects')],
        )
        .getSingle();
    expect(row.read<String>('value_json'), raw);
    final skip = await db
        .customSelect(
          'SELECT table_name, column_name, record_id '
          'FROM normalisation_skips WHERE table_name = ? AND record_id = ?',
          variables: [
            const Variable<String>('settings'),
            const Variable<String>('custom_dialects'),
          ],
        )
        .getSingle();
    expect(skip.data, {
      'table_name': 'settings',
      'column_name': 'value_json',
      'record_id': 'custom_dialects',
    });
  });

  test('re-derives skipped natural-key targets from live values', () async {
    await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
      't1',
      'cafe\u0301',
    ]);
    await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
      't2',
      'café',
    ]);

    await repos.ensureMigrated();

    final skipped = await db
        .customSelect(
          'SELECT table_name, column_name, record_id FROM normalisation_skips '
          'ORDER BY record_id',
        )
        .get();
    expect(
      [for (final row in skipped) row.data],
      [
        {'table_name': 'tags', 'column_name': 'name', 'record_id': 't1'},
        {'table_name': 'tags', 'column_name': 'name', 'record_id': 't2'},
      ],
    );
    final unchanged = await db
        .customSelect('SELECT id, name FROM tags ORDER BY id')
        .get();
    expect(
      [for (final row in unchanged) row.data],
      [
        {'id': 't1', 'name': 'cafe\u0301'},
        {'id': 't2', 'name': 'café'},
      ],
    );

    await db.customStatement('UPDATE tags SET name = ? WHERE id = ?', [
      'resume\u0301',
      't1',
    ]);
    await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

    final rows = await db
        .customSelect('SELECT id, name FROM tags ORDER BY id')
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {'id': 't1', 'name': 'resumé'},
        {'id': 't2', 'name': 'café'},
      ],
    );
  });

  test(
    'retries derived rebuild after a committed normalization rewrite',
    () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
        'cafe\u0301',
        'd1',
      ]);
      for (final key in [
        inversePairNormalisationDoneKey,
        starPromenadeHandRemovalDoneKey,
        gripSingleFileCanonicalInclusionDoneKey,
        promenadeTurnCircleWordingCanonicalRebuildDoneKey,
        compactDosidoSeesawCanonicalRebuildDoneKey,
        chainHandBackfillDoneKey,
      ]) {
        await repos.settings.set(key, 'done');
      }
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
      final failing = _FailingOnceNormalisationRepositories(db, contraTaxonomy);

      await expectLater(failing.ensureMigrated(), throwsA(isA<StateError>()));
      final marker = await db
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ?',
            variables: [const Variable<String>(derivedRebuildRequiredKey)],
          )
          .get();
      expect(marker, isNotEmpty);

      await failing.ensureMigrated();
      final cleared = await db
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ?',
            variables: [const Variable<String>(derivedRebuildRequiredKey)],
          )
          .get();
      expect(cleared, isEmpty);

      final indexed = await db
          .customSelect(
            'SELECT title FROM dance_fts WHERE dance_id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(indexed.read<String>('title'), contains('café'));
    },
  );

  test('notifies dance watchers when normalization rewrites a dance', () async {
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
      'cafe\u0301',
      'd1',
    ]);
    await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
    for (final key in [
      inversePairNormalisationDoneKey,
      starPromenadeHandRemovalDoneKey,
      gripSingleFileCanonicalInclusionDoneKey,
      promenadeTurnCircleWordingCanonicalRebuildDoneKey,
      compactDosidoSeesawCanonicalRebuildDoneKey,
      chainHandBackfillDoneKey,
    ]) {
      await repos.settings.set(key, 'done');
    }
    final seen = <String>[];
    final subscription = db
        .customSelect(
          'SELECT title FROM dances WHERE id = ?',
          variables: [const Variable<String>('d1')],
          readsFrom: {db.dances},
        )
        .watch()
        .listen((rows) {
          if (rows.isNotEmpty) seen.add(rows.single.read<String>('title'));
        });
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repos.ensureMigrated();
    await pumpEventQueue();

    expect(seen.last, 'café');
  });

  test(
    'clears the rebuild marker after a successful normalization backfill',
    () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
        'cafe\u0301',
        'd1',
      ]);
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
      for (final key in [
        inversePairNormalisationDoneKey,
        starPromenadeHandRemovalDoneKey,
        gripSingleFileCanonicalInclusionDoneKey,
        promenadeTurnCircleWordingCanonicalRebuildDoneKey,
        compactDosidoSeesawCanonicalRebuildDoneKey,
        chainHandBackfillDoneKey,
      ]) {
        await repos.settings.set(key, 'done');
      }

      await repos.ensureMigrated();

      final marker = await db
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ?',
            variables: [const Variable<String>(derivedRebuildRequiredKey)],
          )
          .get();
      expect(marker, isEmpty);
    },
  );
}

class _FailingOnceNormalisationRepositories extends CompendiumRepositories {
  _FailingOnceNormalisationRepositories(super.db, super.taxonomy);

  var _failed = false;

  @override
  Future<void> runDerivedRebuild({DerivedRebuildProgressCallback? onProgress}) {
    if (!_failed) {
      _failed = true;
      throw StateError('injected rebuild failure');
    }

    return super.runDerivedRebuild(onProgress: onProgress);
  }
}
