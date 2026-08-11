/// Behavioural guard: importing a shared bundle must never overwrite a
/// choreographer record the receiver already holds (issues #853, #887).
///
/// **Why this exists as a test rather than an analysis.** The fact it pins was
/// originally established by *reading* two write paths — `_resolveAuthors`
/// (`import_pipeline.dart`) hits `continue` on a name match and writes nothing,
/// and the only full-record `upsert` from an archive
/// (`archive_service.dart`) belongs to backup restore, which a share bundle
/// cannot reach because `BackupService.restoreFromJson` requires an envelope
/// with a `core` section. A fact established by reading decays the moment
/// either path is edited: turning that one `continue` into an `upsert` would
/// silently start overwriting recipients' records, and nothing would fail.
///
/// So these assert the **behaviour**, not the mechanism. They do not care how
/// the importer decides; they care that a local record survives contact with a
/// bundle that disagrees with it.
///
/// **What makes this more than hypothetical.** Redacting `choreographers.email`
/// / `.location` / `.deceased` from shares (#853) means every shared record now
/// carries `"deceased": false` and no contact fields — the codec emits
/// `deceased` unconditionally, so redaction there is a *default value* rather
/// than an absence. If the import path ever applied incoming choreographer
/// fields, that redaction would flip a recipient's correct `deceased: true` to
/// `false` and blank their contact details: a privacy fix corrupting correct
/// data on someone else's device, which is a worse harm than the leak it fixed.
/// These tests are what stands between that and a silent regression.
library;

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

Dance _dance(String id, String title, {List<String> authorIds = const []}) =>
    Dance(
      id: id,
      title: title,
      authorIds: authorIds,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

String Function() _sequentialIds(String prefix) {
  var n = 0;
  return () => '$prefix-${++n}';
}

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late ProgramRepository programs;
  late VenueRepository venues;
  late CompendiumArchiveImporter importer;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    programs = ProgramRepository(db);
    venues = VenueRepository(db);
    importer = CompendiumArchiveImporter(
      ImportPipeline(dances, choreographers),
      programs,
      venues,
    );
  });

  tearDown(() => db.close());

  final now = DateTime.utc(2026, 7, 18);

  /// A bundle crediting [name], shaped exactly as the share path produces one:
  /// the choreographer has been through `sanitizeChoreographerForShare`, so it
  /// carries `deceased: false` and no email/location.
  CompendiumArchive bundleCrediting(String name) {
    final author = Choreographer(id: 'sender-c1', name: name);
    final dance = _dance(
      'sender-d1',
      'Simplicity Swing',
      authorIds: ['sender-c1'],
    );
    return CompendiumArchive(
      exportedAt: DateTime.utc(2026, 7, 15),
      choreographers: [author],
      dances: [dance],
      programs: [
        Program(
          id: 'sender-p1',
          title: 'Spring Fling',
          slots: [
            ProgramSlot(id: 'sender-sl1', position: 0, danceId: 'sender-d1'),
          ],
          createdAt: DateTime.utc(2026, 4, 1),
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      ],
    );
  }

  Future<void> importBundle(CompendiumArchive archive) => importer.import(
    encodeArchive(archive),
    archive,
    now: now,
    newId: _sequentialIds('new'),
    newSlotId: _sequentialIds('slot'),
  );

  test("importing a bundle does not clear an existing choreographer's deceased "
      'flag', () async {
    // The receiver knows this person has died and has recorded it.
    // ignore: unused_result
    await choreographers.upsert(
      Choreographer(id: 'local-c1', name: 'Ada Caller', deceased: true),
    );

    // A bundle credits the same person. Every shared record says
    // `deceased: false`, because the flag is redacted on the way out and the
    // codec emits it unconditionally.
    await importBundle(bundleCrediting('Ada Caller'));

    final ada = (await choreographers.listAll()).singleWhere(
      (c) => c.name == 'Ada Caller',
    );
    expect(
      ada.id,
      'local-c1',
      reason: 'the incoming author matched the local record, not a new one',
    );
    expect(
      ada.deceased,
      isTrue,
      reason:
          'A shared bundle always carries deceased: false (redacted on '
          'export). If import ever applies incoming choreographer fields, a '
          "recipient's correct record is silently falsified.",
    );
  });

  test("importing a bundle does not clear an existing choreographer's private "
      'contact fields', () async {
    // Same hazard, other fields: email/location are redacted on export, so an
    // import that applied incoming values would blank the local ones.
    // ignore: unused_result
    await choreographers.upsert(
      Choreographer(
        id: 'local-c1',
        name: 'Ada Caller',
        email: 'ada@example.com',
        location: 'Portland, OR',
        website: 'https://ada.example',
      ),
    );

    await importBundle(bundleCrediting('Ada Caller'));

    final ada = (await choreographers.listAll()).singleWhere(
      (c) => c.name == 'Ada Caller',
    );
    expect(ada.email, 'ada@example.com');
    expect(ada.location, 'Portland, OR');
    expect(ada.website, 'https://ada.example');
  });

  test('a choreographer the receiver does not have is created', () async {
    // The complement, so the guard above cannot be satisfied by an importer
    // that simply never touches choreographers at all. Attribution must still
    // survive the transfer.
    await importBundle(bundleCrediting('Bo Newcomer'));

    final all = await choreographers.listAll();
    final bo = all.where((c) => c.name == 'Bo Newcomer');
    expect(bo, hasLength(1), reason: 'the credited author was created');
    // A fresh record takes the model default rather than anything off the wire.
    expect(bo.single.deceased, isFalse);
  });
}
