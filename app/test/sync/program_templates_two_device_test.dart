import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

/// Program templates (#2337) across two devices: one settings value per
/// template, so two devices editing *different* templates both keep their
/// edits. Two real databases sync through an in-memory store with real
/// coordinators.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  late InMemorySyncServer server;
  late InMemorySyncDevice a;
  late InMemorySyncDevice b;
  // Every user write is stamped a minute after the last, starting at the real
  // clock, so two devices' edits never tie and each is later than the stamps
  // sync itself writes from the real clock (as in
  // sync_user_merge_two_device_test.dart).
  late DateTime clock;
  DateTime tick() => clock = clock.add(const Duration(minutes: 1));

  Future<void> write(InMemorySyncDevice device, ProgramTemplate template) =>
      device.repositories.settings.set(
        programTemplateKey(template.id),
        encodeProgramTemplate(template),
        at: tick(),
      );

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

  Future<ProgramTemplates> templatesOf(InMemorySyncDevice device) =>
      loadProgramTemplates(
        device.repositories.settings,
        migratedName: 'Starting program',
      );

  /// Runs passes alternately until neither device's templates change.
  Future<void> settle({int maxRounds = 6}) async {
    String? previous;
    for (var round = 0; round < maxRounds; round++) {
      await a.sync();
      await b.sync();
      final state =
          '${server.manifestOf(a.deviceId)?.records} '
          '${server.manifestOf(b.deviceId)?.records} '
          '${await a.repositories.settings.all()} '
          '${await b.repositories.settings.all()}';
      if (state == previous) return;
      previous = state;
    }
    fail('the devices did not settle in $maxRounds rounds');
  }

  test(
    'two devices editing different templates both keep their edits',
    () async {
      await write(a, const ProgramTemplate(id: 'family', name: 'Family'));
      await write(a, const ProgramTemplate(id: 'saturday', name: 'Saturday'));
      await saveProgramTemplateOrder(a.repositories.settings, [
        'family',
        'saturday',
      ]);
      await settle();
      expect(
        [for (final t in (await templatesOf(b)).templates) t.id],
        ['family', 'saturday'],
      );

      // Offline, each device edits a different template.
      await write(
        a,
        const ProgramTemplate(
          id: 'family',
          name: 'Family',
          entries: [ProgramTemplateEntry(text: 'Edited on A')],
        ),
      );
      await write(
        b,
        const ProgramTemplate(
          id: 'saturday',
          name: 'Saturday night',
          entries: [ProgramTemplateEntry(text: 'Edited on B')],
        ),
      );
      await settle();

      for (final device in [a, b]) {
        final templates = await templatesOf(device);
        expect(templates.byId('family')!.entries, const [
          ProgramTemplateEntry(text: 'Edited on A'),
        ], reason: device.deviceId);
        expect(templates.byId('saturday')!.name, 'Saturday night');
        expect(templates.byId('saturday')!.entries, const [
          ProgramTemplateEntry(text: 'Edited on B'),
        ], reason: device.deviceId);
      }
    },
  );

  test('both devices migrating the same Starting program end with one '
      'template, not two', () async {
    await a.repositories.settings.set(
      kDefaultStartingProgramKey,
      encodeStartingProgramTemplate(const [
        ProgramTemplateEntry(text: 'Opener'),
      ]),
    );
    await settle();
    expect(
      await b.repositories.settings.get(kDefaultStartingProgramKey),
      isNotNull,
    );

    await templatesOf(a);
    await templatesOf(b);
    await settle();

    for (final device in [a, b]) {
      final templates = await templatesOf(device);
      expect(
        [for (final t in templates.templates) t.id],
        [kMigratedStartingProgramTemplateId],
        reason: device.deviceId,
      );
    }
  });

  test('a device that migrates late does not overwrite edits a peer made '
      'after migrating', () async {
    await a.repositories.settings.set(
      kDefaultStartingProgramKey,
      encodeStartingProgramTemplate(const [
        ProgramTemplateEntry(text: 'Opener'),
      ]),
    );
    await settle();

    // A migrates, then edits the migrated template, adds a second one and
    // makes Blank the default, and syncs. B has not opened templates yet.
    // A's edits are stamped an hour ago, so B's migration below is later
    // than all of them, as when B is opened after A was edited.
    clock = clock.subtract(const Duration(hours: 1));
    await templatesOf(a);
    await write(
      a,
      const ProgramTemplate(
        id: kMigratedStartingProgramTemplateId,
        name: 'Renamed on A',
        entries: [ProgramTemplateEntry(text: 'Edited on A')],
      ),
    );
    await write(a, const ProgramTemplate(id: 'family', name: 'Family'));
    await a.repositories.settings.set(kProgramTemplateOrderKey, const [
      'family',
      kMigratedStartingProgramTemplateId,
    ], at: tick());
    await a.repositories.settings.set(
      kProgramTemplateDefaultKey,
      kProgramTemplateBlankDefault,
      at: tick(),
    );
    await a.sync();

    // B migrates its own copy before it pulls A's edits.
    await templatesOf(b);
    await settle();

    for (final device in [a, b]) {
      final templates = await templatesOf(device);
      expect(
        [for (final t in templates.templates) t.id],
        ['family', kMigratedStartingProgramTemplateId],
        reason: device.deviceId,
      );
      final migrated = templates.byId(kMigratedStartingProgramTemplateId)!;
      expect(migrated.name, 'Renamed on A', reason: device.deviceId);
      expect(migrated.entries, const [
        ProgramTemplateEntry(text: 'Edited on A'),
      ], reason: device.deviceId);
      expect(templates.defaultId, isNull, reason: device.deviceId);
    }
  });
}
