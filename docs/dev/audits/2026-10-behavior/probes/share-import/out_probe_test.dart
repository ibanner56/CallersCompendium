// Throwaway audit probe: share a dance that has a related-dance link and a
// performed program, import into a fresh DB, observe what survives.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'storage/test_database.dart';

Dance _d(String id, String title, {List<DanceLink> links = const [], int? rating}) => Dance(
  id: id,
  title: title,
  links: links,
  rating: rating,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

CompendiumArchiveImporter _importer(CompendiumDatabase db) {
  final repos = CompendiumRepositories(db, contraTaxonomy);
  return CompendiumArchiveImporter(
    ImportPipeline(DanceRepository(db, contraTaxonomy), ChoreographerRepository(db)),
    ProgramRepository(db),
    VenueRepository(db),
    repositories: repos,
    difficultyLevels: DifficultyLevelRepository(db),
  );
}

void main() {
  test('dance with relatedDance link shared alone', () async {
    final a = _d('sender-a', 'Alpha', rating: 2, links: [
      DanceLink(id: 'link-1', kind: LinkKind.relatedDance, targetDanceId: 'sender-b'),
      DanceLink(id: 'link-2', kind: LinkKind.video, url: 'https://example.com/v'),
    ]);
    final json = encodeArchive(
      CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [a]),
      mode: ArchiveSerializationMode.share,
    );
    final db = openTestDatabase();
    final importer = _importer(db);
    final decoded = decodeArchive(json);
    Object? err;
    CompendiumArchiveImportResult? res;
    try {
      res = await importer.import(json, decoded.archive, now: DateTime.utc(2026, 2));
    } catch (e) {
      err = e;
    }
    print('ERR: $err');
    final all = await DanceRepository(db, contraTaxonomy).listAll();
    print('dances after import: ${all.map((d) => '${d.title} rating=${d.rating} links=${d.links.map((l) => '${l.kind.name}:${l.targetDanceId ?? l.url}').toList()}')}');
    print('records: ${res?.danceSession.records.map((r) => "${r.action} err=${r.error?.message}").toList()}');
  });

  test('performed program shared feeds recipient last-called', () async {
    final a = _d('sender-a', 'Alpha');
    final p = Program(
      id: 'sender-p',
      title: 'Last Saturday',
      eventDate: DateTime.utc(2026, 10, 24),
      status: ProgramStatus.performed,
      payMinorUnits: 25000,
      payCurrency: 'USD',
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'sender-a', performedAt: DateTime.utc(2026, 10, 24, 20)),
      ],
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 24),
    );
    final json = encodeArchive(
      CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [a], programs: [p]),
      mode: ArchiveSerializationMode.share,
    );
    final db = openTestDatabase();
    final importer = _importer(db);
    await importer.import(json, decodeArchive(json).archive, now: DateTime.utc(2026, 10, 27));
    final progs = ProgramRepository(db);
    final counts = await progs.programDerivedCounts();
    print('lastCalled: ${counts.lastCalled}');
    final imported = await progs.listAll();
    print('imported program pay=${imported.single.payMinorUnits} status=${imported.single.status}');
  });

  test('program bundle with both linked dances', () async {
    final a = _d('sender-a', 'Alpha', links: [
      DanceLink(id: 'link-1', kind: LinkKind.relatedDance, targetDanceId: 'sender-b'),
    ]);
    final b = _d('sender-b', 'Beta');
    final p = Program(
      id: 'sender-p', title: 'Eve', status: ProgramStatus.draft,
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'sender-a'),
        ProgramSlot(id: 's2', position: 1, danceId: 'sender-b'),
      ],
      createdAt: DateTime.utc(2026, 10, 1), updatedAt: DateTime.utc(2026, 10, 24),
    );
    final json = encodeArchive(
      CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [a, b], programs: [p]),
      mode: ArchiveSerializationMode.share,
    );
    final db = openTestDatabase();
    final res = await _importer(db).import(json, decodeArchive(json).archive, now: DateTime.utc(2026, 10, 27));
    final all = await DanceRepository(db, contraTaxonomy).listAll();
    print('BOTH dances: ${all.map((d) => d.title).toList()}');
    print('BOTH records: ${res.danceSession.records.map((r) => "${r.action} err=${r.error?.message}").toList()}');
    final progs = await ProgramRepository(db).listAll();
    print('BOTH slots: ${progs.single.slots.map((s) => s.danceId ?? s.text).toList()}');
  });

  test('link id collision on round trip', () async {
    final db = openTestDatabase();
    final repo = DanceRepository(db, contraTaxonomy);
    await repo.create(_d('mine-d', 'Original', links: [
      DanceLink(id: 'L1', kind: LinkKind.video, url: 'https://example.com/v'),
    ]));
    // A friend received it, retitled it, and sends it back.
    final back = _d('friend-d', 'Original (friend edit)', links: [
      DanceLink(id: 'L1', kind: LinkKind.video, url: 'https://example.com/v'),
    ]);
    final json = encodeArchive(
      CompendiumArchive(exportedAt: DateTime.utc(2026), dances: [back]),
      mode: ArchiveSerializationMode.share,
    );
    final res = await _importer(db).import(json, decodeArchive(json).archive, now: DateTime.utc(2026, 10, 27));
    print('COLLIDE records: ${res.danceSession.records.map((r) => "${r.action} err=${r.error?.message}").toList()}');
    print('COLLIDE dances: ${(await repo.listAll()).map((d) => d.title).toList()}');
  });
}
