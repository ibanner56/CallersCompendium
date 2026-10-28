// A shared file carries each dance link's own id and, for a related-dance
// link, the sender's id for the target dance. Both belong to the sender's
// library, so an import that wrote them as given failed the whole dance: a
// foreign-key error for a related link (the target is imported under a new
// id, or not at all), and a UNIQUE error on `dance_links.id` when a URL link
// comes back to a library that already holds it.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

Dance _dance(
  String id,
  String title, {
  List<DanceLink> links = const [],
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  links: links,
  provenance: provenance,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

DanceLink _related(String id, String targetDanceId) => DanceLink(
  id: id,
  kind: LinkKind.relatedDance,
  targetDanceId: targetDanceId,
);

DanceLink _video(String id) =>
    DanceLink(id: id, kind: LinkKind.video, url: 'https://example.com/v');

String _share(List<Dance> dances, {List<Program> programs = const []}) =>
    encodeArchive(
      CompendiumArchive(
        exportedAt: DateTime.utc(2026),
        dances: dances,
        programs: programs,
      ),
      mode: ArchiveSerializationMode.share,
    );

CompendiumArchiveImporter _importer(CompendiumDatabase db) =>
    CompendiumArchiveImporter(
      ImportPipeline(
        DanceRepository(db, contraTaxonomy),
        ChoreographerRepository(db),
      ),
      ProgramRepository(db),
      VenueRepository(db),
      repositories: CompendiumRepositories(db, contraTaxonomy),
      difficultyLevels: DifficultyLevelRepository(db),
    );

Future<CompendiumArchiveImportResult> _receive(
  CompendiumDatabase db,
  String json,
) => _importer(
  db,
).import(json, decodeArchive(json).archive, now: DateTime.utc(2026, 10, 27));

Dance _titled(List<Dance> dances, String title) =>
    dances.singleWhere((d) => d.title == title);

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('a dance whose related dance is not in the file still imports, '
      'without that link', () async {
    final json = _share([
      _dance(
        'sender-a',
        'Alpha',
        links: [_related('link-1', 'sender-b'), _video('link-2')],
      ),
    ]);

    final result = await _receive(db, json);

    expect([
      for (final r in result.danceSession.records) r.error,
    ], everyElement(isNull));
    final alpha = _titled(await dances.listAll(), 'Alpha');
    expect(alpha.links, hasLength(1));
    expect(alpha.links.single.kind, LinkKind.video);
    expect(alpha.links.single.id, isNot('link-2'));
    expect(
      [for (final issue in result.danceSession.issues) issue.code],
      ['archive_related_dance_unresolved'],
    );
  });

  test('a program carrying both linked dances imports both and links them '
      'by their new ids', () async {
    final json = _share(
      [
        _dance('sender-a', 'Alpha', links: [_related('link-1', 'sender-b')]),
        _dance(
          'sender-b',
          'Beta',
          links: [
            DanceLink(
              id: 'link-2',
              kind: LinkKind.relatedDance,
              targetDanceId: 'sender-a',
              label: 'mirror',
              transitive: true,
            ),
          ],
        ),
      ],
      programs: [
        Program(
          id: 'sender-p',
          title: 'Eve',
          status: ProgramStatus.draft,
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'sender-a'),
            ProgramSlot(id: 's2', position: 1, danceId: 'sender-b'),
          ],
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 24),
        ),
      ],
    );

    final result = await _receive(db, json);

    final all = await dances.listAll();
    final alpha = _titled(all, 'Alpha');
    final beta = _titled(all, 'Beta');
    expect(alpha.id, isNot('sender-a'));
    expect(beta.id, isNot('sender-b'));
    expect([for (final l in alpha.links) l.targetDanceId], [beta.id]);
    expect([for (final l in beta.links) l.targetDanceId], [alpha.id]);
    expect(beta.links.single.label, 'mirror');
    expect(beta.links.single.transitive, isTrue);
    expect({
      for (final l in [...alpha.links, ...beta.links]) l.id,
    }, isNot(anyElement(anyOf('link-1', 'link-2'))));
    expect(result.danceSession.issues, isEmpty);
    final program = (await ProgramRepository(db).listAll()).single;
    expect([for (final s in program.slots) s.danceId], [alpha.id, beta.id]);
  });

  test('a dance with a video link that comes back to a library holding '
      'that link imports as well', () async {
    await dances.create(_dance('mine-d', 'Original', links: [_video('L1')]));
    // A friend received it, retitled it, and sends it back.
    final json = _share([
      _dance('friend-d', 'Original (friend edit)', links: [_video('L1')]),
    ]);

    final result = await _receive(db, json);

    expect([
      for (final r in result.danceSession.records) r.error,
    ], everyElement(isNull));
    final all = await dances.listAll();
    expect([for (final l in _titled(all, 'Original').links) l.id], ['L1']);
    final back = _titled(all, 'Original (friend edit)');
    expect(back.links.single.url, 'https://example.com/v');
    expect(back.links.single.id, isNot('L1'));
  });

  group('a related link resolves to a dance received earlier', () {
    // The review screen commits only the rows the user acts on, rebuilt
    // without the plan's dedupe snapshot; this commits the same way.
    Future<ImportSession> commitActedRows(
      String json,
      bool Function(Dance draft) acted,
    ) async {
      final pipeline = ImportPipeline(
        dances,
        ChoreographerRepository(db),
        difficultyLevels: DifficultyLevelRepository(db),
      );
      final planned = await pipeline.plan(
        GenericJsonAdapter(),
        ImportRequest(payload: json),
      );
      return pipeline.commit(
        ImportBatchResult(
          records: [
            for (final record in planned.records)
              if (acted(record.draft.dance)) record,
          ],
        ),
        now: DateTime.utc(2026, 10, 27),
        newId: uuidV4,
      );
    }

    test('when the file does not carry it', () async {
      await _receive(db, _share([_dance('sender-b', 'Beta')]));
      final beta = _titled(await dances.listAll(), 'Beta');

      final session = await commitActedRows(
        _share([
          _dance('sender-a', 'Alpha', links: [_related('link-1', 'sender-b')]),
        ]),
        (_) => true,
      );

      final alpha = _titled(await dances.listAll(), 'Alpha');
      expect([for (final l in alpha.links) l.targetDanceId], [beta.id]);
      expect(session.issues, isEmpty);
    });

    test('when the file carries it from an online source and its row is '
        'skipped', () async {
      // Under its upstream key, not the sender's id for it.
      final upstream = Provenance(
        source: ProvenanceSource.contradb,
        externalId: '457',
        importedAt: DateTime.utc(2026),
      );
      final betaFromSender = _dance('sender-b', 'Beta', provenance: upstream);
      await _receive(db, _share([betaFromSender]));
      final beta = _titled(await dances.listAll(), 'Beta');

      final session = await commitActedRows(
        _share([
          _dance('sender-a', 'Alpha', links: [_related('link-1', 'sender-b')]),
          betaFromSender,
        ]),
        (draft) => draft.title == 'Alpha',
      );

      final alpha = _titled(await dances.listAll(), 'Alpha');
      expect([for (final l in alpha.links) l.targetDanceId], [beta.id]);
      expect(session.issues, isEmpty);
    });
  });

  test('Undo of a re-import takes back the link it added', () async {
    await _receive(
      db,
      _share([_dance('sender-a', 'Alpha'), _dance('sender-b', 'Beta')]),
    );

    // The sender has since linked the two; both rows re-import.
    final again = await _receive(
      db,
      _share([
        _dance('sender-a', 'Alpha', links: [_related('link-1', 'sender-b')]),
        _dance('sender-b', 'Beta'),
      ]),
    );
    final all = await dances.listAll();
    expect(again.danceSession.updatedDancePriorStates, hasLength(2));
    expect(
      [for (final l in _titled(all, 'Alpha').links) l.targetDanceId],
      [_titled(all, 'Beta').id],
    );

    await _importer(db).undo(again);

    expect(_titled(await dances.listAll(), 'Alpha').links, isEmpty);
  });

  test('Undo removes the links it added along with the dances', () async {
    final json = _share([
      _dance('sender-a', 'Alpha', links: [_related('link-1', 'sender-b')]),
      _dance('sender-b', 'Beta'),
    ]);
    final result = await _receive(db, json);
    expect(await dances.listAll(), hasLength(2));

    await _importer(db).undo(result);

    expect(await dances.listAll(), isEmpty);
    expect(await db.select(db.danceLinks).get(), isEmpty);
  });

  test('the dance-only route links dances from the same file too', () async {
    final pipeline = ImportPipeline(
      dances,
      ChoreographerRepository(db),
      difficultyLevels: DifficultyLevelRepository(db),
    );
    final json = _share([
      _dance('sender-a', 'Alpha', links: [_related('link-1', 'sender-b')]),
      _dance('sender-b', 'Beta', links: [_video('link-2')]),
    ]);

    final batch = await pipeline.plan(
      GenericJsonAdapter(),
      ImportRequest(payload: json),
    );
    final session = await pipeline.commit(
      batch,
      now: DateTime.utc(2026, 10, 27),
      newId: uuidV4,
    );

    expect([for (final r in session.records) r.error], everyElement(isNull));
    final all = await dances.listAll();
    expect(
      [for (final l in _titled(all, 'Alpha').links) l.targetDanceId],
      [_titled(all, 'Beta').id],
    );
  });
}
