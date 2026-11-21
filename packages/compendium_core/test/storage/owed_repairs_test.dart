// UPGRADE-1: the app's migration preflight snapshots the database when a
// one-time repair is still owed, because those repairs rewrite stored figures
// and text on a file whose `user_version` does not change. It learns what is
// owed from `CompendiumRepositories.oneTimeRepairMarkers` — so that map must
// list every sweep's marker, and must require a value exactly where the
// sweep's own gate compares one, or the preflight silently stops covering a
// repair (or snapshots on every launch).
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'test_database.dart';

const _repositoriesSource = 'lib/src/storage/repositories/repositories.dart';
const _databaseSource = 'lib/src/storage/database.dart';

/// Every top-level `const String <name> = '<value>';` in database.dart, by
/// name. The declaration may wrap after `=`.
Map<String, String> _stringConstants() {
  final source = File(_databaseSource).readAsStringSync();
  return {
    for (final match in RegExp(
      r"const String (\w+)\s*=\s*'([^']*)';",
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };
}

Future<Map<String, String>> _liveMarkers(CompendiumDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT key, value_json FROM settings WHERE deleted_at IS NULL',
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('key'): row.read<String>('value_json'),
  };
}

void main() {
  test('every marker a sweep writes is listed, except the derived-rebuild '
      'flag', () {
    final constants = _stringConstants();
    final source = File(_repositoriesSource).readAsStringSync();
    final written = {
      for (final match in RegExp(
        r'await _writeSweepMarker\(\s*(\w+)',
      ).allMatches(source))
        match.group(1)!,
    };
    // The scan must see the sweeps at all, or the ratchet proves nothing.
    expect(written, contains('chainHandBackfillDoneKey'));
    final writtenKeys = {
      for (final name in written)
        if (name != 'derivedRebuildRequiredKey')
          constants[name] ??
              fail('$name is not a const String in database.dart'),
    };

    final db = openTestDatabase();
    addTearDown(db.close);
    final listed = CompendiumRepositories(
      db,
      contraTaxonomy,
    ).oneTimeRepairMarkers.keys.toSet();
    expect(
      writtenKeys.difference(listed),
      isEmpty,
      reason:
          'A sweep writes a completion marker that oneTimeRepairMarkers does '
          'not list, so the migration preflight would not snapshot before it.',
    );
    expect(listed.difference(writtenKeys), isEmpty);
  });

  test('every `__…_done__` marker declared in database.dart is listed', () {
    final doneKeys = _stringConstants().values
        .where((value) => value.startsWith('__') && value.endsWith('_done__'))
        .toSet();
    expect(doneKeys, isNotEmpty);
    final db = openTestDatabase();
    addTearDown(db.close);
    expect(
      doneKeys.difference(
        CompendiumRepositories(
          db,
          contraTaxonomy,
        ).oneTimeRepairMarkers.keys.toSet(),
      ),
      isEmpty,
    );
  });

  test('a fully migrated database owes nothing, so the preflight does not '
      'snapshot on every open', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await repos.ensureMigrated();
    expect(
      owedOneTimeRepairs(
        expected: repos.oneTimeRepairMarkers,
        live: await _liveMarkers(db),
      ),
      isEmpty,
    );
  });

  test('an absent, tombstoned or stale marker is owed until ensureMigrated '
      'runs the repair', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await repos.ensureMigrated();

    // Absent: a build that ships a new sweep meets a file without its marker.
    await db.customUpdate(
      'DELETE FROM settings WHERE key = ?',
      variables: [Variable<String>(chainHandBackfillDoneKey)],
    );
    // Tombstoned: every sweep's gate filters `deleted_at IS NULL`.
    await SettingsRepository(db).remove(purgeCorruptionRepairDoneKey);
    // Stale: the registry's shareable scope changed since the last pass.
    await db.customUpdate(
      'UPDATE settings SET value_json = ? WHERE key = ?',
      variables: [
        Variable<String>('{}'),
        Variable<String>(shareableTextNormalisationScopeKey),
      ],
    );
    // A tombstoned row must not reach `live`, as the preflight's query
    // filters it; read it the way the preflight does.
    expect(
      owedOneTimeRepairs(
        expected: repos.oneTimeRepairMarkers,
        live: await _liveMarkers(db),
      ),
      unorderedEquals([
        chainHandBackfillDoneKey,
        purgeCorruptionRepairDoneKey,
        shareableTextNormalisationScopeKey,
      ]),
    );

    // A fresh facade, as the next launch would build: `ensureMigrated` is
    // memoized per instance.
    final next = CompendiumRepositories(db, contraTaxonomy);
    await next.ensureMigrated();
    expect(
      owedOneTimeRepairs(
        expected: next.oneTimeRepairMarkers,
        live: await _liveMarkers(db),
      ),
      isEmpty,
    );
  });

  // The key-set ratchets above cannot see a gate that compares a value the map
  // treats as presence-only (the v35 marker was exactly that). So ask each
  // sweep directly: store a value no sweep writes, run `ensureMigrated`, and
  // the sweep ran exactly when it rewrote its marker. "Owed" must agree.
  test(
    'a stale marker value is owed exactly when its sweep would re-run',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();
      final keys = CompendiumRepositories(
        db,
        contraTaxonomy,
      ).oneTimeRepairMarkers.keys.toList();
      const stale = '"__not_a_value_any_sweep_writes__"';

      for (final key in keys) {
        await db.customUpdate(
          'UPDATE settings SET value_json = ? WHERE key = ?',
          variables: [Variable<String>(stale), Variable<String>(key)],
        );
        final repos = CompendiumRepositories(db, contraTaxonomy);
        final owed = owedOneTimeRepairs(
          expected: repos.oneTimeRepairMarkers,
          live: await _liveMarkers(db),
        ).contains(key);
        await repos.ensureMigrated();
        final reran = (await _liveMarkers(db))[key] != stale;
        expect(owed, reran, reason: key);
        // Leave the next key's run with nothing else owed.
        if (!reran) {
          await db.customUpdate(
            'DELETE FROM settings WHERE key = ?',
            variables: [Variable<String>(key)],
          );
          await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();
        }
      }
    },
  );

  test('owedOneTimeRepairs compares values only where one is required', () {
    expect(
      owedOneTimeRepairs(
        expected: {'a': null, 'b': '"1"'},
        live: {'a': 'anything', 'b': '"1"'},
      ),
      isEmpty,
    );
    expect(
      owedOneTimeRepairs(expected: {'a': null, 'b': '"1"'}, live: {'b': '"0"'}),
      ['a', 'b'],
    );
  });
}
