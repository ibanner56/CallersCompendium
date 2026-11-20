import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

/// Import undo after a sync pass has published the import (#2266).
///
/// `docs/design/sync-spec.md` §3.1 lets a record be hard-deleted only where it
/// can never have been published, and says an import's undo window lasts as
/// long as the user leaves the screen open, so a pass can land inside it. The
/// danger is the "absent from baseline, present remotely → download" path
/// (§6.3): a record erased locally after a peer holds it comes straight back on
/// the next pass.
///
/// Each test runs the whole sequence the issue names, on two real databases
/// syncing through an in-memory store with real coordinators: import, a pass
/// that publishes the imported records (the pass inside the undo window), undo,
/// then the passes after it. These are characterization tests of enforcement
/// that already exists: they pass on the code as it stood before they were
/// written. Each marker check they depend on was removed in turn to show they
/// can fail: the dance, program and venue `hardDelete` checks and the pass's
/// own marker write are caught here. The choreographer's own marker check is
/// NOT: in this scenario the published dance survives as a tombstone, whose
/// credit row downgrades the choreographer's erase to a tombstone regardless,
/// so that branch is pinned by `choreographer_repository_test.dart` instead.
/// The coordinator's marker race is tested in `sync_coordinator_test.dart`.
void main() {
  // Two databases in one isolate is the point of these tests.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  late InMemorySyncServer server;
  late InMemorySyncDevice a;
  late InMemorySyncDevice b;

  setUp(() {
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
  });

  tearDown(() {
    a.dispose();
    b.dispose();
  });

  final importedAt = DateTime.utc(2026, 7, 15);

  String Function() ids(String prefix) {
    var n = 0;
    return () => '$prefix-${++n}';
  }

  /// A one-dance archive crediting one author the receiving device does not
  /// have, so the import creates a choreographer.
  String danceByNewAuthor() => encodeArchive(
    CompendiumArchive(
      exportedAt: importedAt,
      dances: [
        Dance(
          id: 'src-dance',
          title: 'Undo Reel',
          authorIds: const ['src-author'],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      choreographers: [Choreographer(id: 'src-author', name: 'Ada Author')],
    ),
  );

  /// A program at a venue, with the one dance it plays.
  CompendiumArchive programAtVenue() => CompendiumArchive(
    exportedAt: importedAt,
    dances: [
      Dance(
        id: 'src-dance',
        title: 'Venue Reel',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ],
    programs: [
      Program(
        id: 'src-program',
        title: 'Spring Fling',
        venueId: 'src-venue',
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 'src-slot', position: 0, danceId: 'src-dance')],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
      ),
    ],
    venues: [
      Venue(id: 'src-venue', name: 'Guiding Star Grange'),
      // Named by no program: undo erases it, unless a pass has published it.
      Venue(id: 'src-spare-venue', name: 'Town Hall'),
    ],
  );

  /// Whether [id] is a tombstone: a row exists, and no live view shows it.
  /// Choreographers and venues expose rows only through `listAll`.
  Future<bool> authorTombstoned(InMemorySyncDevice d, String id) async =>
      (await d.repositories.choreographers.listAll(
        includeDeleted: true,
      )).any((c) => c.id == id) &&
      !(await d.repositories.choreographers.listAll()).any((c) => c.id == id);

  Future<bool> venueTombstoned(InMemorySyncDevice d, String id) async =>
      (await d.repositories.venues.listAll(
        includeDeleted: true,
      )).any((v) => v.id == id) &&
      !(await d.repositories.venues.listAll()).any((v) => v.id == id);

  Future<bool> authorExists(InMemorySyncDevice d, String id) async =>
      (await d.repositories.choreographers.listAll(
        includeDeleted: true,
      )).any((c) => c.id == id);

  Future<bool> venueExists(InMemorySyncDevice d, String id) async =>
      (await d.repositories.venues.listAll(
        includeDeleted: true,
      )).any((v) => v.id == id);

  Future<ImportSession> importDance(InMemorySyncDevice device) async {
    final pipeline = ImportPipeline(
      device.repositories.dances,
      device.repositories.choreographers,
    );
    final batch = await pipeline.plan(
      GenericJsonAdapter(),
      ImportRequest(payload: danceByNewAuthor()),
    );
    return pipeline.commit(batch, now: importedAt, newId: ids('import'));
  }

  group('a dance and the choreographer its import created', () {
    test('undo after a pass published them leaves neither live on any device, '
        'and the next passes do not bring them back', () async {
      final pipeline = ImportPipeline(
        a.repositories.dances,
        a.repositories.choreographers,
      );
      final batch = await pipeline.plan(
        GenericJsonAdapter(),
        ImportRequest(payload: danceByNewAuthor()),
      );
      final session = await pipeline.commit(
        batch,
        now: importedAt,
        newId: ids('import'),
      );
      // The test is vacuous unless the import made both kinds of record.
      expect(session.insertedDanceIds, hasLength(1));
      expect(session.createdChoreographerIds, hasLength(1));
      final danceId = session.insertedDanceIds.single;
      final authorId = session.createdChoreographerIds.single;

      // The pass inside the undo window: it publishes both.
      await a.sync();
      await b.sync();
      expect(
        await b.repositories.dances.getById(danceId),
        isNotNull,
        reason: 'control: the pass really did publish the dance',
      );
      expect(
        await b.repositories.choreographers.getById(authorId),
        isNotNull,
        reason: 'control: the pass really did publish the choreographer',
      );

      await pipeline.undo(session);

      // Not erased: a peer holds them, so deletion evidence must stay. (For the
      // choreographer this holds because its tombstoned dance still credits it;
      // see the file header.)
      final dance = await a.repositories.dances.getById(
        danceId,
        includeDeleted: true,
      );
      expect(dance?.deletedAt, isNotNull, reason: 'tombstoned, not erased');
      expect(
        await authorTombstoned(a, authorId),
        isTrue,
        reason: 'tombstoned, not erased',
      );

      // The passes after the undo: the publisher's own, then the peer's.
      await a.sync();
      await a.sync();
      await b.sync();
      await a.sync();

      for (final (name, device) in [('A', a), ('B', b)]) {
        expect(
          await device.repositories.dances.getById(danceId),
          isNull,
          reason: 'the dance must stay undone on $name',
        );
        expect(await device.repositories.dances.listAll(), isEmpty);
        expect(
          await device.repositories.choreographers.getById(authorId),
          isNull,
          reason: 'the choreographer must stay undone on $name',
        );
        expect(await device.repositories.choreographers.listAll(), isEmpty);
      }
    });

    test('control: with no pass before the undo the rows are erased, not '
        'tombstoned', () async {
      final session = await importDance(a);
      final danceId = session.insertedDanceIds.single;
      final authorId = session.createdChoreographerIds.single;

      await ImportPipeline(
        a.repositories.dances,
        a.repositories.choreographers,
      ).undo(session);

      expect(
        await a.repositories.dances.getById(danceId, includeDeleted: true),
        isNull,
      );
      expect(await authorExists(a, authorId), isFalse);
      // Nothing was ever published, so nothing is left to publish either.
      await a.sync();
      await b.sync();
      expect(await b.repositories.dances.listAll(), isEmpty);
      expect(await b.repositories.choreographers.listAll(), isEmpty);
    });
  });

  group('a program and the venue its archive import created', () {
    Future<(CompendiumArchiveImporter, CompendiumArchiveImportResult)> import(
      InMemorySyncDevice device,
    ) async {
      final importer = CompendiumArchiveImporter(
        ImportPipeline(
          device.repositories.dances,
          device.repositories.choreographers,
        ),
        device.repositories.programs,
        device.repositories.venues,
        repositories: device.repositories,
      );
      final archive = programAtVenue();
      final result = await importer.import(
        encodeArchive(archive),
        archive,
        now: importedAt,
        newId: ids('import'),
        newSlotId: ids('slot'),
      );
      return (importer, result);
    }

    test('undo after a pass published them tombstones the program and dance, '
        'keeps the venue the tombstoned program still names, and the next '
        'passes change none of it', () async {
      final (importer, result) = await import(a);
      expect(result.insertedVenueIds, hasLength(2));
      expect(result.insertedProgramIds, hasLength(1));
      expect(result.danceSession.insertedDanceIds, hasLength(1));
      final venues = await a.repositories.venues.listAll();
      final venueId = venues
          .singleWhere((v) => v.name == 'Guiding Star Grange')
          .id;
      final spareId = venues.singleWhere((v) => v.name == 'Town Hall').id;
      final programId = result.insertedProgramIds.single;
      final danceId = result.danceSession.insertedDanceIds.single;

      await a.sync();
      await b.sync();
      expect(
        await b.repositories.venues.getById(venueId),
        isNotNull,
        reason: 'control: the pass really did publish the venue',
      );
      expect(await b.repositories.programs.getById(programId), isNotNull);
      expect(
        await b.repositories.venues.getById(spareId),
        isNotNull,
        reason: 'control: the pass published the venue no program names too',
      );

      await importer.undo(result);

      // A published program, dance and unreferenced venue are tombstoned, never erased.
      expect(
        (await a.repositories.programs.getById(
          programId,
          includeDeleted: true,
        ))?.deletedAt,
        isNotNull,
        reason: 'tombstoned, not erased',
      );
      expect(
        (await a.repositories.dances.getById(
          danceId,
          includeDeleted: true,
        ))?.deletedAt,
        isNotNull,
        reason: 'tombstoned, not erased',
      );
      // The venue is neither erased nor tombstoned: `VenueRepository.hardDelete`
      // keeps a venue that any surviving program row, a tombstoned one included,
      // still names (sync-spec §3.1, #1357), and the published program survives
      // as a tombstone. That is the retention rule, not a resurrection: nothing
      // was erased for a peer to send back.
      expect(await venueExists(a, venueId), isTrue);
      expect(await venueTombstoned(a, venueId), isFalse);
      // The venue no program names has nothing to retain it, so it is the one
      // `VenueRepository.hardDelete` meets as a published, unreferenced row.
      expect(
        await venueTombstoned(a, spareId),
        isTrue,
        reason: 'a published venue is tombstoned, not erased',
      );

      await a.sync();
      await a.sync();
      await b.sync();
      await a.sync();

      for (final (name, device) in [('A', a), ('B', b)]) {
        expect(
          await device.repositories.programs.getById(programId),
          isNull,
          reason: 'the program must stay undone on $name',
        );
        expect(await device.repositories.programs.listAll(), isEmpty);
        expect(
          await device.repositories.dances.getById(danceId),
          isNull,
          reason: 'the dance must stay undone on $name',
        );
        expect(await device.repositories.dances.listAll(), isEmpty);
        expect(
          await venueExists(device, venueId),
          isTrue,
          reason: 'the retained venue must be the same on $name',
        );
        expect(await venueTombstoned(device, venueId), isFalse);
        expect(
          await device.repositories.venues.getById(spareId),
          isNull,
          reason: 'the spare venue must stay undone on $name',
        );
      }
    });

    test('control: with no pass before the undo the venue is erased, not '
        'tombstoned', () async {
      final (importer, result) = await import(a);
      expect(result.insertedVenueIds, hasLength(2));

      await importer.undo(result);

      for (final id in result.insertedVenueIds) {
        expect(await venueExists(a, id), isFalse, reason: 'erased: $id');
      }
      // Nothing was ever published, so nothing is left to publish either.
      await a.sync();
      await b.sync();
      expect(await b.repositories.venues.listAll(), isEmpty);
    });
  });
}
