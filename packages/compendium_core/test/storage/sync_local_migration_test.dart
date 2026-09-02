import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

void main() {
  test('v31 migration creates sync-local tables without losing data', () async {
    final root = await packageRootPath();
    final source = File(
      p.join(root, 'test', 'storage', 'fixtures', 'v31.sqlite'),
    );
    final dir = await Directory.systemTemp.createTemp('compendium_core_v32_');
    addTearDown(() => dir.delete(recursive: true));
    final target = await source.copy(p.join(dir.path, 'migration.sqlite'));

    final db = CompendiumDatabase(NativeDatabase(target));

    final sentinel = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ?',
          variables: [Variable.withString('v31_sync_migration_sentinel')],
        )
        .get();
    expect(sentinel.single.read<String>('value_json'), '"present"');

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('baseline_state', 'baseline_entries', 'id_aliases', "
          "'pending_deletions', 'review_queue', 'published_records')",
        )
        .get();
    expect(tables, hasLength(6));

    final repository = SyncLocalRepository(db);
    await repository.replaceBaseline(epoch: DateTime.utc(2026, 3, 1));
    await db.close();

    final reopened = CompendiumDatabase(NativeDatabase(target));
    addTearDown(reopened.close);
    final reopenedRepository = SyncLocalRepository(reopened);
    expect(
      (await reopenedRepository.getBaselineState())!.epoch.toUtc(),
      DateTime.utc(2026, 3, 1),
    );
    expect(await reopenedRepository.listBaselineEntries(), isEmpty);
  });
}
