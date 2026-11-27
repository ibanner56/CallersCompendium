import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart'
    show EgressClass, classifySettingsKey, fieldClassifications;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show ShareParams;
import 'package:sqlite3/sqlite3.dart' as sql;

import 'package:compendium_app/src/data/recovery_copy.dart';

/// The v39 release fixture: a library written by v0.7.0-beta (schema 39), the
/// version the schema floor of 40 sends to the "data too old to open" screen.
/// Restored from `packages/compendium_core/test/storage/fixtures/v39.sqlite`
/// as it stood at tag v0.10.0-beta, before #2540 retired it from the core
/// suite.
const String _fixture = 'test/fixtures/below_floor_v39.sqlite';

/// A value written into rows the copy must drop. If it survives anywhere in
/// the copy's bytes, a free page kept a deleted row.
const String _marker = 'RECOVERY-COPY-MUST-NOT-CARRY';

void main() {
  late Directory tmp;
  late File source;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('recovery_copy_test');
    source = File(p.join(tmp.path, 'compendium.sqlite'));
    File(_fixture).copySync(source.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Tables the copy must empty: those the registry gives a column it may not
  /// carry (Device Sync bookkeeping, the normalisation repair log).
  Set<String> tablesToEmpty(sql.Database db) {
    final names = {
      for (final row in db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'] as String,
    };
    return {
      for (final entry in fieldClassifications.entries)
        if (entry.value.egress == EgressClass.deviceScoped ||
            entry.value.egress == EgressClass.protocolIdentifier ||
            entry.value.egress == EgressClass.storeAddress)
          entry.key.split('.').first,
    }.intersection(names);
  }

  /// Inserts one row of placeholder values (carrying [_marker] in every text
  /// column) into [table], whatever its columns.
  void seedRow(sql.Database db, String table) {
    final columns = db.select('SELECT name, type FROM pragma_table_info(?)', [
      table,
    ]);
    final names = [for (final c in columns) '"${c['name']}"'];
    final values = <Object?>[
      for (final c in columns)
        switch ((c['type'] as String).toUpperCase()) {
          'INTEGER' || 'INT' => 1,
          'REAL' => 1.0,
          'BLOB' => utf8.encode(_marker),
          _ => _marker,
        },
    ];
    db.execute(
      'INSERT INTO "$table" (${names.join(', ')}) '
      'VALUES (${List.filled(names.length, '?').join(', ')})',
      values,
    );
  }

  void putSetting(sql.Database db, String key, String valueJson) {
    db.execute(
      'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
      [key, valueJson],
    );
  }

  int count(sql.Database db, String table) =>
      db.select('SELECT COUNT(*) AS n FROM "$table"').first['n'] as int;

  Set<String> settingKeys(sql.Database db) => {
    for (final row in db.select('SELECT key FROM settings'))
      row['key'] as String,
  };

  test('keeps the library, drops what may not leave the device, and the '
      'result is a whole schema-39 database', () async {
    // Library and kept-setting counts before anything is seeded.
    const libraryTables = [
      'dances',
      'programs',
      'program_slots',
      'venues',
      'choreographers',
      'tags',
      'custom_field_defs',
      'custom_field_values',
      'dance_links',
      'dance_tags',
      'dance_authors',
      'dance_sources',
      'provenance',
    ];
    final seeded = sql.sqlite3.open(source.path);
    late final Map<String, int> before;
    late final Set<String> emptied;
    try {
      before = {for (final t in libraryTables) t: count(seeded, t)};
      expect(before['dances'], greaterThan(0), reason: 'fixture has dances');

      // Rows the copy must drop.
      putSetting(seeded, 'editor_draft:1', jsonEncode(_marker)); // deviceScoped
      putSetting(seeded, 'sync_endpoint', jsonEncode(_marker)); // deviceScoped
      putSetting(seeded, 'sync_id', jsonEncode(_marker)); // storeAddress
      putSetting(seeded, 'sync_device_id', jsonEncode(_marker)); // protocolId
      // deviceLocal, but kept out of backups (maintainer, 2026-11-22).
      putSetting(seeded, 'calendar_feed_url', jsonEncode(_marker));
      // A key the registry does not know: the rule fails closed.
      putSetting(seeded, 'not.a.registered.key', jsonEncode(_marker));
      emptied = {...tablesToEmpty(seeded), ...kTablesRecoveryCopyEmpties};
      for (final table in emptied) {
        seedRow(seeded, table);
      }
      expect(count(seeded, 'dance_figures'), greaterThan(0));
      expect(count(seeded, 'dance_fts'), greaterThan(0));

      // A table the registry does not know: a retired schema's library
      // content, which the copy keeps.
      seeded.execute('CREATE TABLE retired_library_table (note TEXT)');
      seeded.execute(
        "INSERT INTO retired_library_table (note) VALUES ('kept')",
      );

      // Rows the copy must keep.
      putSetting(seeded, 'reduce_motion', 'true'); // deviceLocal, backed up
      putSetting(seeded, 'saved_search:kept', '{}'); // shareable prefix
    } finally {
      seeded.close();
    }
    expect(
      emptied,
      containsAll(<String>{
        'baseline_state',
        'baseline_entries',
        'id_aliases',
        'pending_deletions',
        'retained_sync_fields',
        'peer_manifests',
        'review_queue',
        'published_records',
        'normalisation_skips',
        'collection_import_events',
      }),
    );
    final sourceBytes = source.readAsBytesSync();

    final copy = await writeRecoveryCopy(
      source: source,
      destination: File(p.join(tmp.path, 'out', 'recovery.sqlite')),
    );

    // The source is only read.
    expect(source.readAsBytesSync(), sourceBytes);

    final db = sql.sqlite3.open(copy.path, mode: sql.OpenMode.readOnly);
    try {
      // A whole database at the version the bridge release migrates from.
      expect(db.select('PRAGMA user_version').first.values.first, 39);
      expect(db.select('PRAGMA integrity_check').first.values.first, 'ok');
      expect(db.select('PRAGMA journal_mode').first.values.first, 'delete');
      // Rebuilt by VACUUM: no free page that could hold a deleted row.
      expect(db.select('PRAGMA freelist_count').first.values.first, 0);

      // The library is untouched.
      for (final table in libraryTables) {
        expect(count(db, table), before[table], reason: table);
      }

      // Every table that may not travel is still there, and empty.
      for (final table in emptied) {
        expect(count(db, table), 0, reason: table);
      }

      // The derived indexes do not travel: the figure index is empty and
      // the full-text tables, internal tables included, are gone, for the
      // bridge release to rebuild.
      expect(count(db, 'dance_figures'), 0);
      final tableNames = {
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name'] as String,
      };
      expect(
        tableNames.where(
          (t) => t.startsWith('dance_fts') || t.startsWith('dance_substring'),
        ),
        isEmpty,
      );

      // A column the registry does not know keeps its table.
      expect(
        db.select('SELECT note FROM retired_library_table').single['note'],
        'kept',
      );

      final keys = settingKeys(db);
      for (final dropped in [
        'editor_draft:1',
        'sync_endpoint',
        'sync_id',
        'sync_device_id',
        'calendar_feed_url',
        'not.a.registered.key',
      ]) {
        expect(keys, isNot(contains(dropped)), reason: dropped);
      }
      expect(keys, containsAll(['reduce_motion', 'saved_search:kept']));
      // Nothing kept that the rule would drop.
      for (final key in keys) {
        expect(keepSettingInRecoveryCopy(key), isTrue, reason: key);
      }
    } finally {
      db.close();
    }

    // VACUUM left no deleted row in a free page.
    expect(
      latin1.decode(copy.readAsBytesSync(), allowInvalid: true),
      isNot(contains(_marker)),
    );
    // A copy shared on its own needs nothing beside it.
    expect(File('${copy.path}-wal').existsSync(), isFalse);
    expect(File('${copy.path}-journal').existsSync(), isFalse);
  });

  test('every table with a device-local column is decided: a backup carries '
      'it, or the copy empties it', () {
    // The tables whose deviceLocal columns a backup carries (choreographers'
    // and venues' private fields, and settings, judged per key). A new table
    // with a deviceLocal column fails here until someone decides whether the
    // recovery copy may carry it.
    const carriedByBackups = {'choreographers', 'venues', 'settings'};
    final deviceLocalTables = {
      for (final entry in fieldClassifications.entries)
        if (entry.value.egress == EgressClass.deviceLocal)
          entry.key.split('.').first,
    };
    expect(
      deviceLocalTables.difference({
        ...carriedByBackups,
        ...kTablesRecoveryCopyEmpties,
      }),
      isEmpty,
    );
  });

  test(
    'the settings rule fails closed on a key the registry does not know',
    () {
      const unknown = 'not.a.registered.key';
      expect(classifySettingsKey(unknown), isNull);
      expect(keepSettingInRecoveryCopy(unknown), isFalse);
    },
  );

  test('the settings rule keeps only what a backup may carry', () {
    expect(keepSettingInRecoveryCopy('reduce_motion'), isTrue); // deviceLocal
    expect(keepSettingInRecoveryCopy('saved_search:x'), isTrue); // shareable
    expect(keepSettingInRecoveryCopy('calendar_feed_url'), isFalse);
    expect(keepSettingInRecoveryCopy('editor_draft:x'), isFalse);
    expect(keepSettingInRecoveryCopy('sync_enabled'), isFalse);
    expect(keepSettingInRecoveryCopy('sync_id'), isFalse);
    expect(keepSettingInRecoveryCopy('sync_device_id'), isFalse);
  });

  test('sharing hands the sheet the scrubbed copy, and only that', () async {
    final seeded = sql.sqlite3.open(source.path);
    try {
      putSetting(seeded, 'editor_draft:1', jsonEncode(_marker));
    } finally {
      seeded.close();
    }
    final shared = <ShareParams>[];
    const origin = Rect.fromLTWH(10, 20, 30, 40);
    final workDir = Directory(p.join(tmp.path, 'work'));

    final copy = await prepareRecoveryCopy(source: source, workDir: workDir);
    await shareRecoveryCopyFile(
      copy,
      origin: origin,
      shareInvoker: (params) async => shared.add(params),
    );

    expect(shared, hasLength(1));
    final params = shared.single;
    expect(params.sharePositionOrigin, origin);
    expect(params.fileNameOverrides, [kRecoveryCopyFileName]);
    expect(params.files, hasLength(1));
    final sharedPath = params.files!.single.path;
    expect(sharedPath, p.join(workDir.path, kRecoveryCopyFileName));
    final db = sql.sqlite3.open(sharedPath, mode: sql.OpenMode.readOnly);
    try {
      expect(settingKeys(db), isNot(contains('editor_draft:1')));
      expect(db.select('PRAGMA user_version').first.values.first, 39);
    } finally {
      db.close();
    }
    // The live database still has its draft: only the copy is scrubbed.
    final live = sql.sqlite3.open(source.path, mode: sql.OpenMode.readOnly);
    try {
      expect(settingKeys(live), contains('editor_draft:1'));
    } finally {
      live.close();
    }
  });

  test('no copy is left when it cannot be made', () async {
    final notADatabase = File(p.join(tmp.path, 'garbage.sqlite'))
      ..writeAsStringSync('this is not a database');

    await expectLater(
      prepareRecoveryCopy(
        source: notADatabase,
        workDir: Directory(p.join(tmp.path, 'work')),
      ),
      throwsA(anything),
    );
    expect(
      File(p.join(tmp.path, 'work', kRecoveryCopyFileName)).existsSync(),
      isFalse,
    );
  });

  test('a copy that fails leaves nothing behind', () async {
    final notADatabase = File(p.join(tmp.path, 'garbage.sqlite'))
      ..writeAsStringSync('this is not a database');
    final destination = File(p.join(tmp.path, 'out', 'recovery.sqlite'));

    await expectLater(
      writeRecoveryCopy(source: notADatabase, destination: destination),
      throwsA(anything),
    );
    expect(destination.existsSync(), isFalse);
  });
}
