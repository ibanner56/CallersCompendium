import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

/// Un-archiving a program on one device reaches the other, and neither queues
/// a conflict. A program body leaves `archivedAt` out once it is cleared, and
/// the receiver reads the missing key as cleared (`withOmittedProgramDefaults`)
/// rather than keeping its stored value. Two real databases sync through an
/// in-memory store with real coordinators. The other keys a program or event
/// rule body leaves out are pinned in compendium_core's
/// `sync_cleared_program_fields_test.dart`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  late InMemorySyncServer server;
  late InMemorySyncDevice a;
  late InMemorySyncDevice b;
  // Every user write is stamped a minute after the last, starting at the real
  // clock, so each is later than the stamps sync itself writes from the real
  // clock (as in sync_user_merge_two_device_test.dart).
  late DateTime clock;
  DateTime tick() => clock = clock.add(const Duration(minutes: 1));

  setUp(() {
    final now = DateTime.now().toUtc();
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
    addTearDown(a.dispose);
    addTearDown(b.dispose);
  });

  Future<void> syncBoth() async {
    await a.sync();
    await b.sync();
    await a.sync();
    await b.sync();
  }

  test('un-archiving a program on one device reaches the other', () async {
    final created = tick();
    await a.repositories.programs.create(
      Program(
        id: 'p1',
        title: 'Saturday',
        slots: [ProgramSlot(id: 's1', position: 0, text: 'Opener')],
        createdAt: created,
        updatedAt: created,
      ),
    );
    await syncBoth();
    expect(await a.repositories.programs.archive('p1', at: tick()), isTrue);
    await syncBoth();
    expect(
      (await b.repositories.programs.getById('p1'))!.archivedAt,
      isNotNull,
      reason: 'archiving reaches the other device',
    );

    expect(await a.repositories.programs.unarchive('p1', at: tick()), isTrue);
    await syncBoth();

    final onA = (await a.repositories.programs.getById('p1'))!;
    final onB = (await b.repositories.programs.getById('p1'))!;
    expect(onB.updatedAt, onA.updatedAt, reason: 'B took A\'s newer record');
    expect(onA.archivedAt, isNull);
    expect(onB.archivedAt, isNull);
    expect(await a.repositories.syncLocal.listReviewQueue(), isEmpty);
    expect(await b.repositories.syncLocal.listReviewQueue(), isEmpty);
  });
}
