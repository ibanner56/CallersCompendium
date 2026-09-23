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

  test('restore reset clears the normalization marker and skips', () async {
    await repos.settings.set(shareableTextNormalisationScopeKey, 'stale');
    await db.customStatement(
      'INSERT INTO normalisation_skips '
      '(table_name, column_name, record_id) VALUES (?, ?, ?)',
      ['tags', 'name', 'stale-tag'],
    );

    await repos.resetNormalisationStateForRestore();

    expect(
      await repos.settings.contains(shareableTextNormalisationScopeKey),
      isFalse,
    );
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
    );
  });

  test(
    'restore reset lets the next migration normalize restored text',
    () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      await repos.ensureMigrated();
      await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
        'cafe\u0301',
        'd1',
      ]);

      await repos.resetNormalisationStateForRestore();
      await repos.ensureMigrated();

      final row = await db
          .customSelect(
            'SELECT title FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(row.read<String>('title'), 'café');
    },
  );

  test(
    'a failed transaction after migration clears the migration memo',
    () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      await repos.ensureMigrated();
      await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
        'cafe\u0301',
        'd1',
      ]);
      await repos.resetNormalisationStateForRestore();

      await expectLater(
        repos.transaction(() async {
          await repos.ensureMigrated();
          throw StateError('simulate outer transaction rollback');
        }, resetMigrationOnFailure: true),
        throwsA(isA<StateError>()),
      );

      final rolledBack = await db
          .customSelect(
            'SELECT title FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(rolledBack.read<String>('title'), 'cafe\u0301');

      await repos.ensureMigrated();
      final retried = await db
          .customSelect(
            'SELECT title FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(retried.read<String>('title'), 'café');
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

  test('backfill skips colliding normalized difficulty labels', () async {
    const first = 'difficulty-custom-1';
    const second = 'difficulty-custom-2';
    await db.customStatement(
      'INSERT INTO difficulty_levels (id, label, position) VALUES (?, ?, ?)',
      [first, 'cafe\u0301', 100],
    );
    await db.customStatement(
      'INSERT INTO difficulty_levels (id, label, position) VALUES (?, ?, ?)',
      [second, 'café', 101],
    );

    await repos.ensureMigrated();

    final rows = await db
        .customSelect(
          'SELECT id, label FROM difficulty_levels WHERE id IN (?, ?) '
          'ORDER BY id',
          variables: [
            const Variable<String>(first),
            const Variable<String>(second),
          ],
        )
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {'id': first, 'label': 'cafe\u0301'},
        {'id': second, 'label': 'café'},
      ],
    );
    final skips = await db
        .customSelect(
          'SELECT table_name, column_name, record_id '
          'FROM normalisation_skips WHERE table_name = ? '
          'AND column_name = ? ORDER BY record_id',
          variables: [
            const Variable<String>('difficulty_levels'),
            const Variable<String>('label'),
          ],
        )
        .get();
    expect(
      [for (final row in skips) row.data],
      [
        {
          'table_name': 'difficulty_levels',
          'column_name': 'label',
          'record_id': first,
        },
        {
          'table_name': 'difficulty_levels',
          'column_name': 'label',
          'record_id': second,
        },
      ],
    );
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

    // Both entries are discharged, not just t1's (#1346 finding 1). t1's row
    // was written to its target; t2 was never rewritten — 'café' is already its
    // own target — but it was recorded only because t1 derived the same string,
    // and t1 no longer does. sync-spec.md §4.1 (`:582`-`:586`) clears an entry
    // "once its row is written", which a row already holding its target
    // satisfies; leaving it would keep the whole library re-scanned on every
    // launch for a collision that no longer exists.
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
    );
  });

  test('a completed pass with no recorded rows performs no scan', () async {
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await repos.ensureMigrated();
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
      reason: 'precondition: a healthy library records nothing',
    );

    // Written raw, so the write path's normalization does not reach it. Only a
    // scan would repair it.
    await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
      'café',
      'd1',
    ]);

    await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

    final row = await db
        .customSelect(
          'SELECT title FROM dances WHERE id = ?',
          variables: [const Variable<String>('d1')],
        )
        .getSingle();
    // The early return is the assertion: an unchanged marker and an empty skip
    // table mean the pass is done, so the value is left exactly as the raw
    // write left it. Asserting the *absence* of a repair is what makes this
    // test able to fail — a scan that ran anyway would normalize it.
    expect(row.read<String>('title'), 'café');
  });

  test('a retry re-attempts only the recorded rows, not the library', () async {
    // Two tags deriving one target: both are recorded, and they stay recorded
    // because neither can take the target while the other holds its own bytes.
    await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
      't1',
      'café',
    ]);
    await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
      't2',
      'café',
    ]);
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await repos.ensureMigrated();
    expect(
      (await db.customSelect('SELECT 1 FROM normalisation_skips').get()).length,
      2,
      reason: 'precondition: the colliding pair is recorded',
    );

    // An un-normalized value on a DIFFERENT in-scope column, written raw so
    // nothing has judged it. A full scan repairs this; a retry bounded by the
    // recorded rows never looks at it.
    await db.customStatement(
      'INSERT INTO published_sources (id, title) VALUES (?, ?)',
      ['s1', 'café'],
    );

    await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

    final source = await db
        .customSelect(
          'SELECT title FROM published_sources WHERE id = ?',
          variables: [const Variable<String>('s1')],
        )
        .getSingle();
    // THE assertion of this test, and the one a clearing-only fix would fail:
    // the value is still decomposed, so the second `ensureMigrated()` did not
    // re-scan the library.
    //
    // Leaving it un-normalized is correct rather than a defect being frozen in.
    // sync-spec.md §4.1 (`:661`-`:668`) states the invariant the bounded retry
    // rests on — *every un-normalized in-scope row is recorded*, because the
    // initial pass records what it skips, the write-path carve-out records what
    // it cannot normalize, and the two events that introduce unjudged rows (a
    // restore, and a change to the in-scope set) both re-run the full scan. A
    // raw SQL insert is outside all three, so it is a probe, not a state the
    // product can reach.
    expect(source.read<String>('title'), 'café');
    // And the retry did do its own job: the pair is still blocked, so both
    // entries survive.
    expect(
      (await db.customSelect('SELECT 1 FROM normalisation_skips').get()).length,
      2,
    );
  });

  test('an entry on a column no longer in scope is discharged', () async {
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await repos.ensureMigrated();
    // `choreographers.email` is `deviceLocal` (field_registry.dart), so the
    // pass never visits it and nothing it does can ever write this row to a
    // target. An entry like this is what a column reclassified out of
    // `shareable` leaves behind: the row still exists, so retire-missing does
    // not remove it either.
    await db.customStatement(
      'INSERT INTO choreographers (id, name, email) VALUES (?, ?, ?)',
      ['c1', 'Someone', 'café@example.test'],
    );
    await db.customStatement(
      'INSERT INTO normalisation_skips '
      '(table_name, column_name, record_id) VALUES (?, ?, ?)',
      ['choreographers', 'email', 'c1'],
    );

    await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
      reason:
          'an entry the pass can never discharge would pin the early return '
          'open forever, which is finding 1 in miniature',
    );
    // Dropping the entry does not normalize the row: the column is out of
    // scope, so leaving its value alone is the correct behaviour, and the
    // marker-inequality rule re-judges it from scratch if it ever returns.
    final choreographer = await db
        .customSelect(
          'SELECT email FROM choreographers WHERE id = ?',
          variables: [const Variable<String>('c1')],
        )
        .getSingle();
    expect(choreographer.read<String>('email'), 'café@example.test');
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
        taxonomyV33CanonicalRebuildDoneKey,
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

  test('backfill skips rows whose JSON column cannot be normalised', () async {
    // The pass runs once over a healthy library first, which writes every
    // one-time sweep marker. That is deliberate, not setup noise: a fresh
    // database runs sweeps that `decodeFigures` every dance
    // (`_normaliseTaxonomyV35FiguresIfNeeded`, the CallersBox roll-away repair)
    // and a section-label rebuild that loads every dance. Any of those raises on
    // the malformed row below *before* the normalisation pass is reached, so a
    // test that skipped this step would be red on unfixed code for a reason that
    // has nothing to do with the guard it claims to exercise.
    await repos.dances.create(sampleDance(id: 'd1', title: 'Malformed'));
    await repos.dances.create(sampleDance(id: 'd2', title: 'Colliding'));
    await db.customStatement(
      'INSERT INTO custom_field_defs (id, key, label, type, choices_json) '
      'VALUES (?, ?, ?, ?, ?)',
      ['cf1', 'mood', 'Mood', 'choice', '["ok"]'],
    );
    await repos.ensureMigrated();

    // Both values are unreachable through the repository write path, which
    // canonicalizes figures before storing them (dance_repository.dart), so they
    // are written the only way they can exist: raw.
    const malformed = '[{"kind":';
    final colliding = jsonEncode([
      {'café': 'first', 'café': 'second'},
    ]);
    await db.customStatement(
      'UPDATE dances SET figures_json = ? WHERE id = ?',
      [malformed, 'd1'],
    );
    await db.customStatement(
      'UPDATE dances SET figures_json = ? WHERE id = ?',
      [colliding, 'd2'],
    );
    // Positive control: a JSON column that CAN be normalised must still be
    // rewritten. It is on `custom_field_defs` rather than on a dance because a
    // dance rewrite sets the derived-rebuild flag, and that rebuild loads every
    // dance — including the malformed one — which is a separate failure path
    // this test is not about.
    await db.customStatement(
      'UPDATE custom_field_defs SET choices_json = ? WHERE id = ?',
      ['["café"]', 'cf1'],
    );

    await repos.resetNormalisationStateForRestore();
    await repos.ensureMigrated();

    final dances = await db
        .customSelect('SELECT id, figures_json FROM dances ORDER BY id')
        .get();
    expect(
      [for (final row in dances) row.data],
      [
        {'id': 'd1', 'figures_json': malformed},
        {'id': 'd2', 'figures_json': colliding},
      ],
    );
    final choices = await db
        .customSelect(
          'SELECT choices_json FROM custom_field_defs WHERE id = ?',
          variables: [const Variable<String>('cf1')],
        )
        .getSingle();
    expect(choices.read<String>('choices_json'), '["café"]');

    final skips = await db
        .customSelect(
          'SELECT table_name, column_name, record_id FROM normalisation_skips '
          'ORDER BY record_id',
        )
        .get();
    expect(
      [for (final row in skips) row.data],
      [
        {
          'table_name': 'dances',
          'column_name': 'figures_json',
          'record_id': 'd1',
        },
        {
          'table_name': 'dances',
          'column_name': 'figures_json',
          'record_id': 'd2',
        },
      ],
    );
    expect(
      await repos.settings.contains(shareableTextNormalisationScopeKey),
      isTrue,
    );
  });

  // `1e999` is legal JSON syntax. `jsonDecode` accepts it and yields
  // `double.infinity`; `jsonEncode` then refuses it with
  // JsonUnsupportedObjectError. So a value can pass the "is it JSON?" test and
  // still fail to round-trip, which is why catching FormatException and the key
  // collision alone did not make the pass total.
  test(
    'backfill skips a JSON column that decodes but cannot re-encode',
    () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Infinity'));
      await repos.ensureMigrated();

      const unencodable = '[{"move":"swing","params":{"beats":1e999}}]';
      await db.customStatement(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        [unencodable, 'd1'],
      );

      await repos.resetNormalisationStateForRestore();
      await repos.ensureMigrated();

      final row = await db
          .customSelect(
            'SELECT figures_json FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(row.read<String>('figures_json'), unencodable);
      final skip = await db
          .customSelect(
            'SELECT table_name, column_name, record_id FROM normalisation_skips',
          )
          .getSingle();
      expect(skip.data, {
        'table_name': 'dances',
        'column_name': 'figures_json',
        'record_id': 'd1',
      });
    },
  );

  test('backfill skips a settings value that cannot be re-encoded', () async {
    await db.customStatement(
      'INSERT INTO settings (key, value_json) VALUES (?, ?)',
      ['custom_dialects', '{"a":1e999}'],
    );

    await repos.ensureMigrated();

    final row = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ?',
          variables: [const Variable<String>('custom_dialects')],
        )
        .getSingle();
    expect(row.read<String>('value_json'), '{"a":1e999}');
    final skip = await db
        .customSelect(
          'SELECT record_id FROM normalisation_skips WHERE table_name = ?',
          variables: [const Variable<String>('settings')],
        )
        .getSingle();
    expect(skip.read<String>('record_id'), 'custom_dialects');
  });

  test('backfill skips a settings value that is not JSON at all', () async {
    await db.customStatement(
      'INSERT INTO settings (key, value_json) VALUES (?, ?)',
      ['custom_dialects', '{"a":'],
    );

    await repos.ensureMigrated();

    final row = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ?',
          variables: [const Variable<String>('custom_dialects')],
        )
        .getSingle();
    expect(row.read<String>('value_json'), '{"a":');
    final skip = await db
        .customSelect(
          'SELECT record_id FROM normalisation_skips WHERE table_name = ?',
          variables: [const Variable<String>('settings')],
        )
        .getSingle();
    expect(skip.read<String>('record_id'), 'custom_dialects');
  });

  group('the completion marker covers the settings classifications', () {
    const key = 'normalisation_test_key';
    const shareable = DataClassification(
      term: DpvTerm.nonPersonal,
      subject: DataSubject.appUser,
      egress: EgressClass.shareable,
    );

    tearDown(() => settingsClassifications.remove(key));

    test('reclassifying a key to shareable re-runs the pass', () async {
      // Stored raw under a key that is classified as nothing, so the settings
      // write path does not normalize it and the scan does not judge it.
      await db.customStatement(
        'INSERT INTO settings (key, value_json) VALUES (?, ?)',
        [key, '{"a":"café"}'],
      );
      await repos.ensureMigrated();
      final beforeMarker = await repos.settings.get(
        shareableTextNormalisationScopeKey,
      );
      final stored = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [const Variable<String>(key)],
          )
          .getSingle();
      expect(
        stored.read<String>('value_json'),
        '{"a":"café"}',
        reason: 'precondition: an unclassified key is out of scope',
      );

      // The reclassification an editor of settings_registry.dart makes. It
      // touches no schema, bumps no version and runs no migration step — which
      // is exactly why the marker has to notice it by comparison.
      settingsClassifications[key] = shareable;

      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      final after = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [const Variable<String>(key)],
          )
          .getSingle();
      expect(after.read<String>('value_json'), '{"a":"café"}');
      expect(
        await repos.settings.get(shareableTextNormalisationScopeKey),
        isNot(beforeMarker),
        reason: 'the recorded set must have changed, by inequality',
      );
    });

    test('an unchanged classification set still takes the early return', () async {
      // The opposite error sync-spec.md §4.1 (`:690`-`:693`) warns of: a live
      // set built from live settings KEYS rather than from the classification
      // entries differs on every open — a key like `editor_draft:<id>` appears
      // and vanishes as the user works — and re-runs the whole pass at every
      // launch. That failure is invisible in a test that only checks values get
      // normalized, because re-scanning normalizes them correctly too.
      //
      // So this asserts the absence of a scan, the same way
      // 'a completed pass with no recorded rows performs no scan' does, but
      // across a change that moves live keys without moving classifications.
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      await repos.ensureMigrated();
      // A runtime-built key arriving between opens, as an editor autosave does.
      // It is `deviceScoped`, so it never enters the fingerprint.
      await repos.settings.set('editor_draft:d1', {'note': 'draft'});
      await db.customStatement('UPDATE dances SET title = ? WHERE id = ?', [
        'café',
        'd1',
      ]);

      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      final row = await db
          .customSelect(
            'SELECT title FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(row.read<String>('title'), 'café');
    });
  });

  group('the derived rebuild follows any rewrite', () {
    test('a choreographer-only repair refreshes the search index', () async {
      await db.customStatement(
        'INSERT INTO choreographers (id, name) VALUES (?, ?)',
        ['c1', 'José'],
      );
      await repos.dances.create(
        sampleDance(id: 'd1', title: 'Credited', authorIds: const ['c1']),
      );
      // The dance's index row was built from the raw name, exactly as a
      // pre-#1119 library holds it.
      final before = await db
          .customSelect(
            'SELECT authors FROM dance_fts WHERE dance_id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      expect(before.read<String>('authors'), 'José');

      await repos.ensureMigrated();

      final name = await db
          .customSelect(
            'SELECT name FROM choreographers WHERE id = ?',
            variables: [const Variable<String>('c1')],
          )
          .getSingle();
      expect(name.read<String>('name'), 'José');
      final indexed = await db
          .customSelect(
            'SELECT authors FROM dance_fts WHERE dance_id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle();
      // The whole of finding 3: `choreographers.name` reaches `dance_fts`
      // through `authors` (dance_repository.dart `_resolveAuthorNames`), and no
      // `dances` row was rewritten, so the old dance-only condition set no flag
      // and left this holding the decomposed name.
      expect(indexed.read<String>('authors'), 'José');
    });

    test('a pass that rewrites nothing performs no rebuild', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Healthy'));
      await repos.ensureMigrated();

      // Everything is already normalized and every sweep marker is written, so
      // the second open owes nothing. sync-spec.md §4.1 (`:1012`-`:1014`): a
      // pass that wrote nothing "MUST NOT" rebuild.
      final counting = _CountingRepositories(db, contraTaxonomy);
      await counting.ensureMigrated();

      expect(counting.rebuildAttempts, 0);
    });
  });

  group('the one-time derived-index repair', () {
    test('runs exactly once for an install that completed the pass', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      await repos.ensureMigrated();
      // The state a pre-fix install upgrades from: the pass completed under the
      // dance-only rebuild condition, so its marker is present and the repair
      // marker is not.
      await db.customStatement('DELETE FROM settings WHERE key = ?', [
        normalisationDerivedIndexRepairDoneKey,
      ]);
      expect(
        await repos.settings.contains(shareableTextNormalisationScopeKey),
        isTrue,
        reason: 'precondition: the pass completed under the old code',
      );

      final first = _CountingRepositories(db, contraTaxonomy);
      await first.ensureMigrated();
      expect(first.rebuildAttempts, 1);

      final second = _CountingRepositories(db, contraTaxonomy);
      await second.ensureMigrated();
      expect(
        second.rebuildAttempts,
        0,
        reason: 'the done marker must stop it running again',
      );
    });

    test('a database that never ran the pass pays no rebuild', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
      // Settle every OTHER sweep first. A fresh database runs several of them
      // and each may rebuild, so counting on a first open would measure the
      // whole migration rather than this gate — and would read as 1 whatever
      // this sweep did.
      await repos.ensureMigrated();
      // Now remove both markers, which is the state of a database that has
      // never completed the normalization pass: nothing it wrote can have been
      // missed by the old dance-only rebuild condition.
      await db.customStatement('DELETE FROM settings WHERE key IN (?, ?)', [
        shareableTextNormalisationScopeKey,
        normalisationDerivedIndexRepairDoneKey,
      ]);

      final counting = _CountingRepositories(db, contraTaxonomy);
      await counting.ensureMigrated();

      // The pass re-runs (its marker is gone) and finds a healthy library, so
      // it rewrites nothing and owes nothing; this sweep is not owed either,
      // because there is no pre-fix completed pass to have missed a rewrite.
      // Forcing a whole-library rebuild here would be pure cost.
      expect(counting.rebuildAttempts, 0);
      expect(
        await counting.settings.contains(
          normalisationDerivedIndexRepairDoneKey,
        ),
        isTrue,
        reason: 'the sweep is retired all the same, so it never re-evaluates',
      );
    });

    test(
      'a fresh database with an unreadable dance row is retired, not made owing',
      () async {
        // Copilot review of #1370. Deferring is only correct when something is
        // owed. On a database that never completed the pre-fix pass, deferring
        // left the done marker absent while the pass went on to write the scope
        // marker — and the scope marker is precisely what the next open reads to
        // decide whether a repair is owed. One un-normalisable dance row was
        // therefore enough to manufacture a debt that had never been incurred,
        // and the install eventually paid a whole-library rebuild for an index
        // that was never stale.
        await repos.dances.create(sampleDance(id: 'd1', title: 'Malformed'));
        await repos.dances.create(sampleDance(id: 'd2', title: 'Healthy'));
        await repos.ensureMigrated();
        // Never completed the pass: BOTH markers gone. Every other sweep is
        // already settled, so any rebuild counted below is this sweep's.
        await db.customStatement('DELETE FROM settings WHERE key IN (?, ?)', [
          shareableTextNormalisationScopeKey,
          normalisationDerivedIndexRepairDoneKey,
        ]);
        await db.customStatement(
          'UPDATE dances SET figures_json = ? WHERE id = ?',
          ['[{"kind":', 'd1'],
        );

        final first = _CountingRepositories(db, contraTaxonomy);
        await first.ensureMigrated();

        expect(first.rebuildAttempts, 0);
        expect(
          await first.settings.contains(normalisationDerivedIndexRepairDoneKey),
          isTrue,
          reason:
              'nothing is owed, so the sweep must retire even though a dance '
              'row blocks the rebuild — an absent marker here is read as a '
              'debt on the next open',
        );

        // The cost the absent marker used to impose, asserted where it lands:
        // once the row becomes readable there must still be no rebuild, because
        // this database never had a stale index to repair.
        await db.customStatement(
          'UPDATE dances SET figures_json = ? WHERE id = ?',
          ['[]', 'd1'],
        );
        await db.customStatement('DELETE FROM normalisation_skips');
        final later = _CountingRepositories(db, contraTaxonomy);
        await later.ensureMigrated();

        expect(later.rebuildAttempts, 0);
      },
    );
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

/// Counts [CompendiumRepositories.runDerivedRebuild] calls without interfering
/// with the real rebuild.
///
/// A subclass rather than SQL-text matching in a `QueryInterceptor`, for the
/// reason [CompendiumRepositories]'s own test seams document: a count that
/// silently becomes zero because the query no longer looks like that turns a
/// ceiling assertion into an assertion about nothing. Rename or re-signature
/// the method this overrides and the test stops compiling instead.
class _CountingRepositories extends CompendiumRepositories {
  _CountingRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    rebuildAttempts++;
    await super.runDerivedRebuild(onProgress: onProgress);
  }
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
