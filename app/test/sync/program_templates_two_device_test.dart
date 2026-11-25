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
      loadProgramTemplates(device.repositories.settings);

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

    // Each device makes its first change offline, which copies the Starting
    // program on both.
    await materializeProgramTemplates(a.repositories.settings);
    await materializeProgramTemplates(b.repositories.settings);
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

  test('a device opened late does not overwrite edits a peer made '
      'after migrating', () async {
    await a.repositories.settings.set(
      kDefaultStartingProgramKey,
      encodeStartingProgramTemplate(const [
        ProgramTemplateEntry(text: 'Opener'),
      ]),
    );
    await settle();

    // A edits the migrated template, adds a second one and makes Blank the
    // default, and syncs. A's edits are stamped an hour ago, so anything B
    // wrote below would be later than all of them.
    clock = clock.subtract(const Duration(hours: 1));
    await materializeProgramTemplates(a.repositories.settings);
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

    // B shows its templates before it pulls A's edits.
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
  test('a migrated template deleted on one device stays deleted when '
      'another device opens templates before pulling', () async {
    await a.repositories.settings.set(
      kDefaultStartingProgramKey,
      encodeStartingProgramTemplate(const [
        ProgramTemplateEntry(text: 'Opener'),
      ]),
    );
    await settle();

    await deleteProgramTemplate(
      a.repositories.settings,
      kMigratedStartingProgramTemplateId,
    );
    await a.sync();
    await templatesOf(b);
    await settle();

    for (final device in [a, b]) {
      final templates = await templatesOf(device);
      expect(templates.templates, isEmpty, reason: device.deviceId);
    }
  });

  test('a template that carries event rules reaches a peer only once it '
      'advertises eventRules.v1, while one without rules reaches it at once '
      '(#2342)', () async {
    const build = SyncCapabilityPolicy.build;
    // A build with templates and without event rules: it gates as this one
    // does, but does not advertise eventRules.v1.
    final withoutEventRules = SyncCapabilityPolicy(
      advertised: {...build.advertised}..remove(SyncCapabilities.eventRulesV1),
      gatedRecordKinds: build.gatedRecordKinds,
      gatedSettingKeys: build.gatedSettingKeys,
      gatedSettingKeyPrefixes: build.gatedSettingKeyPrefixes,
      gatedGlossaryEntryKinds: build.gatedGlossaryEntryKinds,
    );
    final olderRepos = openTestRepositories();
    var older = InMemorySyncDevice(
      server,
      deviceId: 'device-older',
      repositories: olderRepos,
      capabilityPolicy: withoutEventRules,
    );
    addTearDown(() => older.dispose());
    Future<void> settleWith(InMemorySyncDevice peer) async {
      for (var round = 0; round < 4; round++) {
        await a.sync();
        await peer.sync();
      }
    }

    // Both attached first, so each is in the other's device list.
    await settleWith(older);

    // Written as the editor writes it: a v3 value.
    await saveProgramTemplate(
      a.repositories.settings,
      const ProgramTemplate(id: 'family', name: 'Family', eventRuleIds: ['r1']),
    );
    await saveProgramTemplate(
      a.repositories.settings,
      const ProgramTemplate(id: 'contra', name: 'Contra'),
    );
    await settleWith(older);
    expect(
      await olderRepos.settings.get(programTemplateKey('contra')),
      isNotNull,
    );
    expect(
      await olderRepos.settings.get(programTemplateKey('family')),
      isNull,
      reason: 'held back from a peer without event rules',
    );

    // The peer updates to a build with event rules, and its capability record
    // is rewritten (SyncCoordinator.ensureCapabilityRecord). That write is
    // stamped after the stored one even within the same second (#2528), so it
    // cannot tie with the old record and be kept out on the other device.
    older.dispose();
    older = InMemorySyncDevice(
      server,
      deviceId: 'device-older',
      repositories: olderRepos,
    );
    await settleWith(older);
    final family = (await templatesOf(older)).byId('family');
    expect(family?.eventRuleIds, ['r1']);
  });
}
