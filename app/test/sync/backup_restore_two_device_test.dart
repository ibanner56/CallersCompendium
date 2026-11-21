import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

/// Restoring an older backup on one syncing device (SYNC-1, sync-spec §6.11).
///
/// A restore stamps what it writes at the backup's creation time, so anything
/// another device changed after the backup wins at the next sync and comes
/// back, as a restored dance already does. Before the fix every record the
/// restore wrote was stamped at restore time and won on every device,
/// silently undoing the other device's later renames, deletions and edits.
///
/// Two real databases sync through an in-memory store with real coordinators.
/// After the restore the restoring device's coordinator is recreated, as the
/// app's sync-writer lifecycle does around `BackupService.restoreFromJson`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  late InMemorySyncServer server;
  late InMemorySyncDevice a;
  late InMemorySyncDevice b;
  // User writes are stamped a minute apart, starting a month ago: the backup
  // is "a month old" and the other device's later edits all predate the
  // restore, which is what a restore that stamps now would outrank.
  late DateTime clock;
  DateTime tick() => clock = clock.add(const Duration(minutes: 1));

  setUp(() {
    final now = DateTime.now().toUtc().subtract(const Duration(days: 30));
    clock = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    server = InMemorySyncServer();
    a = InMemorySyncDevice(
      server,
      deviceId: 'device-a',
      repositories: openTestRepositories(),
    );
    b = InMemorySyncDevice(
      server,
      deviceId: 'device-b',
      repositories: openTestRepositories(),
    );
    addTearDown(() => a.dispose());
    addTearDown(() => b.dispose());
  });

  /// Exports a backup on A dated [at].
  Future<String> backupA(DateTime at) =>
      BackupService(a.repositories).exportToJson(createdAt: at);

  /// Restores [json] on A, then recreates A's coordinator, as the app does.
  Future<void> restoreA(String json) async {
    final outcome = await BackupService(a.repositories).restoreFromJson(json);
    expect(outcome.applied, isTrue, reason: '${outcome.errors}');
    expect(outcome.errors, isEmpty);
    a.dispose();
    a = InMemorySyncDevice(
      server,
      deviceId: 'device-a',
      repositories: a.repositories,
    );
  }

  Future<List<String>> reviews(InMemorySyncDevice device) async => [
    for (final row in await device.repositories.syncLocal.listReviewQueue())
      '${row.reason}: ${row.recordId} / ${row.counterpartId}',
  ];

  /// Runs passes alternately until what both devices publish stops changing.
  Future<void> settle({int maxRounds = 6}) async {
    String? previous;
    for (var round = 0; round < maxRounds; round++) {
      await a.sync();
      await b.sync();
      expect(await reviews(a), isEmpty, reason: 'device A, round $round');
      expect(await reviews(b), isEmpty, reason: 'device B, round $round');
      final state =
          '${server.manifestOf(a.deviceId)!.records} '
          '${server.manifestOf(b.deviceId)!.records}';
      if (state == previous) return;
      previous = state;
    }
    fail('the devices did not settle in $maxRounds rounds: $previous');
  }

  Future<void> syncBoth() async {
    await a.sync();
    await b.sync();
    await a.sync();
  }

  group('backupCreatedAt', () {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    test('is the envelope createdAt', () {
      expect(
        backupCreatedAt(
          BackupDocument(
            createdAt: DateTime.utc(2026, 10, 1),
            core: CompendiumArchive(exportedAt: DateTime.utc(2026, 9, 1)),
          ),
        ),
        DateTime.utc(2026, 10, 1),
      );
    });

    test('falls back to the core exportedAt when createdAt was unreadable', () {
      expect(
        backupCreatedAt(
          BackupDocument(
            createdAt: epoch,
            core: CompendiumArchive(exportedAt: DateTime.utc(2026, 9, 1)),
          ),
        ),
        DateTime.utc(2026, 9, 1),
      );
    });

    test('is the epoch when neither was readable', () {
      expect(
        backupCreatedAt(
          BackupDocument(
            createdAt: epoch,
            core: CompendiumArchive(exportedAt: epoch),
          ),
        ),
        epoch,
      );
    });
  });

  test('reference kinds: renames and deletions made elsewhere after the '
      'backup survive its restore', () async {
    const keep = '00000000-0000-4000-8000-000000000001';
    const gone = '00000000-0000-4000-8000-000000000002';
    const author = '00000000-0000-4000-8000-000000000003';
    const hall = '00000000-0000-4000-8000-000000000004';
    const barn = '00000000-0000-4000-8000-000000000005';
    final ra = a.repositories;
    // ignore: unused_result
    await ra.tags.upsert(
      Tag(id: keep, name: 'Flowing'),
      at: tick(),
      localUserEdit: true,
    );
    // ignore: unused_result
    await ra.tags.upsert(
      Tag(id: gone, name: 'Gentle'),
      at: tick(),
      localUserEdit: true,
    );
    // ignore: unused_result
    await ra.choreographers.upsert(
      Choreographer(id: author, name: 'Alice'),
      at: tick(),
      localUserEdit: true,
    );
    await ra.venues.upsert(
      Venue(id: hall, name: 'Hall'),
      at: tick(),
      localUserEdit: true,
    );
    await ra.venues.upsert(
      Venue(id: barn, name: 'Barn'),
      at: tick(),
      localUserEdit: true,
    );
    await syncBoth();

    final backup = await backupA(tick());

    final rb = b.repositories;
    // ignore: unused_result
    await rb.tags.upsert(
      Tag(id: keep, name: 'Flowy'),
      at: tick(),
      localUserEdit: true,
    );
    await rb.tags.delete(gone, at: tick());
    // ignore: unused_result
    await rb.choreographers.upsert(
      Choreographer(id: author, name: 'Alicia'),
      at: tick(),
      localUserEdit: true,
    );
    await rb.venues.upsert(
      Venue(id: hall, name: 'Grand Hall'),
      at: tick(),
      localUserEdit: true,
    );
    await rb.venues.delete(barn, at: tick());
    await syncBoth();

    await restoreA(backup);
    await settle();

    for (final device in [a, b]) {
      final repos = device.repositories;
      final who = device.deviceId;
      expect(
        {for (final t in await repos.tags.listAll()) t.id: t.name},
        {keep: 'Flowy'},
        reason: who,
      );
      expect(
        {for (final c in await repos.choreographers.listAll()) c.id: c.name},
        {author: 'Alicia'},
        reason: who,
      );
      expect(
        {for (final v in await repos.venues.listAll()) v.id: v.name},
        {hall: 'Grand Hall'},
        reason: who,
      );
    }
  });

  test('settings: changes, additions and removals made elsewhere after the '
      'backup survive its restore', () async {
    final ra = a.repositories;
    await ra.settings.set('decimal_turns', false, at: tick());
    await ra.settings.set('verbose_figure_rendering', true, at: tick());
    await syncBoth();

    final backup = await backupA(tick());

    final rb = b.repositories;
    await rb.settings.set('decimal_turns', true, at: tick());
    await rb.settings.set('capitalize_figures', true, at: tick());
    await rb.settings.remove('verbose_figure_rendering', at: tick());
    await syncBoth();

    await restoreA(backup);
    await settle();

    for (final device in [a, b]) {
      final settings = device.repositories.settings;
      final who = device.deviceId;
      expect(await settings.get('decimal_turns'), isTrue, reason: who);
      expect(await settings.get('capitalize_figures'), isTrue, reason: who);
      expect(
        await settings.contains('verbose_figure_rendering'),
        isFalse,
        reason: who,
      );
    }
  });

  test('a settings retry after a sync pass does not leave this device '
      'diverged', () async {
    // The retry (#608) is offered until the user takes it, so a pass can run
    // against the restored library first. Its baseline then holds B's newer
    // values; the retry must drop it again, or its backup-dated writes read
    // as local changes that B refuses, and A keeps the old values for good.
    final ra = a.repositories;
    await ra.settings.set('decimal_turns', false, at: tick());
    await ra.userGlossary.upsert(
      UserGlossaryEntry(
        id: 'g',
        kindName: 'compound',
        name: 'Term',
        definition: 'old',
        description: 'd',
        keywords: const [],
        createdAt: clock,
      ),
      at: tick(),
    );
    await syncBoth();
    final backup = await backupA(tick());

    final rb = b.repositories;
    await rb.settings.set('decimal_turns', true, at: tick());
    await rb.userGlossary.upsert(
      UserGlossaryEntry(
        id: 'g',
        kindName: 'compound',
        name: 'Term',
        definition: 'new',
        description: 'd',
        keywords: const [],
        createdAt: clock,
      ),
      at: tick(),
    );
    await syncBoth();

    await restoreA(backup);
    await settle();

    final retried = await BackupService(
      ra,
    ).retryApplySettingsFrom(decodeBackup(backup), mode: RestoreMode.replace);
    expect(retried.applied, isTrue);
    expect(retried.settingsFailed, isFalse);
    // The sync-writer lifecycle recreates the coordinator around the retry.
    a.dispose();
    a = InMemorySyncDevice(server, deviceId: 'device-a', repositories: ra);
    await settle();

    for (final device in [a, b]) {
      final repos = device.repositories;
      final who = device.deviceId;
      expect(await repos.settings.get('decimal_turns'), isTrue, reason: who);
      expect(
        [for (final e in await repos.userGlossary.listAll()) e.definition],
        ['new'],
        reason: who,
      );
    }
  });

  test('glossary and figure notes: edits, additions and deletions made '
      'elsewhere after the backup survive its restore', () async {
    UserGlossaryEntry entry(String id, String definition) => UserGlossaryEntry(
      id: id,
      kindName: 'compound',
      name: 'Term $id',
      definition: definition,
      description: 'd',
      keywords: const [],
      createdAt: clock,
    );
    final ra = a.repositories;
    await ra.userGlossary.upsert(entry('edited', 'old'), at: tick());
    await ra.userGlossary.upsert(entry('deleted', 'old'), at: tick());
    await ra.figureNotes.set('swing', 'old swing note', at: tick());
    await ra.figureNotes.set('allemande', 'old allemande note', at: tick());
    await syncBoth();

    final backup = await backupA(tick());

    final rb = b.repositories;
    await rb.userGlossary.upsert(entry('edited', 'new'), at: tick());
    await rb.userGlossary.upsert(entry('added', 'new'), at: tick());
    await rb.userGlossary.delete('deleted', at: tick());
    await rb.figureNotes.set('swing', 'new swing note', at: tick());
    await rb.figureNotes.set('balance', 'new balance note', at: tick());
    await rb.figureNotes.delete('allemande', at: tick());
    await syncBoth();

    await restoreA(backup);
    await settle();

    for (final device in [a, b]) {
      final repos = device.repositories;
      final who = device.deviceId;
      expect(
        {
          for (final e in await repos.userGlossary.listAll())
            e.id: e.definition,
        },
        {'edited': 'new', 'added': 'new'},
        reason: who,
      );
      expect(
        {
          for (final n in await repos.figureNotes.listAll())
            n.figureId: n.notes,
        },
        {'swing': 'new swing note', 'balance': 'new balance note'},
        reason: who,
      );
    }
  });

  test(
    'a restore still wins over what has not changed since the backup',
    () async {
      final ra = a.repositories;
      await ra.settings.set('decimal_turns', false, at: tick());
      // ignore: unused_result
      await ra.tags.upsert(
        Tag(id: '00000000-0000-4000-8000-000000000001', name: 'Flowing'),
        at: tick(),
        localUserEdit: true,
      );
      await syncBoth();
      final backup = await backupA(tick());

      // Changed on A after the backup and never synced: the restore is meant
      // to put these back, and B, which never saw them, keeps the backup's.
      await ra.settings.set('decimal_turns', true, at: tick());
      // ignore: unused_result
      await ra.tags.upsert(
        Tag(id: '00000000-0000-4000-8000-000000000001', name: 'Oops'),
        at: tick(),
        localUserEdit: true,
      );

      await restoreA(backup);
      await settle();

      for (final device in [a, b]) {
        final repos = device.repositories;
        final who = device.deviceId;
        expect(await repos.settings.get('decimal_turns'), isFalse, reason: who);
        expect(
          [for (final t in await repos.tags.listAll()) t.name],
          ['Flowing'],
          reason: who,
        );
      }
    },
  );
}
