import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fmp_fixture_builder.dart';

/// #1974: the `.USR` columns a beta tester's library keeps its notes, sources
/// and set flags in, which the import used to drop.
void main() {
  group('mapping', () {
    final adapter = CallersCompanionUsrAdapter();
    StructuredDraft parse(Map<String, String> columns) => adapter.parse(
      RawRecord(
        source: ProvenanceSource.callersCompanion,
        externalId: '7',
        sourceVersion: CallersCompanionUsrAdapter.sourceVersion,
        payload: jsonEncode({
          'rowId': '7',
          'columns': {'Name': 'D', ...columns},
        }),
        contentType: 'application/json',
      ),
    );

    test('the notes columns land in the calling notes, in order', () {
      final dance = parse({
        'CallingNotes': 'Avoid clapping.',
        'Music': 'Soldier\'s Joy',
        'Progression': 'Quadruple',
        'ProgressionOther': 'Ls CCW, Rs 2xCCW',
        'NotesOther': 'Also called Fox Hollow Fancy',
        'From': 'George Marshall',
      }).dance;
      expect(
        dance.callingNotes,
        'Avoid clapping.\n'
        "Music: Soldier's Joy\n"
        'Progression: Ls CCW, Rs 2xCCW\n'
        'Other notes: Also called Fox Hollow Fancy\n'
        'Source: George Marshall',
      );
      expect(dance.progression, Progression.quadruple);
    });

    test('ProgressionOther alone is still the progression, not a note', () {
      final dance = parse({'ProgressionOther': 'Double'}).dance;
      expect(dance.progression, Progression.double);
      expect(dance.callingNotes, isNot(contains('Progression:')));
    });

    test('source, Caller\'s Box and video links', () {
      final links = parse({
        'SourceURL': 'https://example.org/dance',
        'CallersBox_id': '1234',
        'VideoURL': 'https://youtu.be/abc',
        'VideoURL3': 'http://vimeo.com/1',
      }).dance.links;
      expect(
        [for (final l in links) (l.kind, l.url, l.label)],
        [
          (LinkKind.source, 'https://example.org/dance', null),
          (
            LinkKind.source,
            'https://ibiblio.org/contradance/thecallersbox/dance.php?id=1234',
            "The Caller's Box",
          ),
          (LinkKind.video, 'https://youtu.be/abc', null),
          (LinkKind.video, 'http://vimeo.com/1', null),
        ],
      );
    });

    test('a link that is not a web address is dropped', () {
      for (final url in [
        'http://', // CC's empty placeholder, on most dances.
        'javascript:alert(1)',
        'www.example.org',
        'https://example.org/a b',
        'https://example.org/\u202Eevil',
      ]) {
        expect(parse({'SourceURL': url}).dance.links, isEmpty, reason: url);
      }
      expect(parse({'CallersBox_id': '12a'}).dance.links, isEmpty);
    });

    test('a URL the file repeats is linked once', () {
      const box =
          'https://ibiblio.org/contradance/thecallersbox/dance.php?id=12';
      final links = parse({
        'SourceURL': box,
        'CallersBox_id': '12',
        'VideoURL': 'https://youtu.be/a',
        'VideoURL2': 'https://youtu.be/a',
      }).dance.links;
      expect(
        [for (final l in links) (l.kind, l.url, l.label)],
        [
          (LinkKind.source, box, "The Caller's Box"),
          (LinkKind.video, 'https://youtu.be/a', null),
        ],
      );
    });

    test('a Reference is a citation with its page', () {
      final citation = parse({
        'Reference': 'Zesty Contras',
        'PageNumber': '42',
      }).dance.sourceCitations.single;
      expect(ccPublishedSourceTitleOf(citation.sourceId), 'Zesty Contras');
      expect(citation.page, '42');
    });
  });

  group('published sources at commit', () {
    late CompendiumDatabase db;
    late DanceRepository dances;
    late PublishedSourceRepository sources;
    late CallersCompanionUsrImporter importer;
    var n = 0;
    String nextId() => 'id-${++n}';
    final now = DateTime.utc(2026, 7, 15);

    setUp(() {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
      sources = PublishedSourceRepository(db);
      importer = CallersCompanionUsrImporter(
        ImportPipeline(dances, ChoreographerRepository(db)),
        ProgramRepository(db),
        VenueRepository(db),
        CustomFieldDefRepository(db),
        publishedSources: sources,
      );
    });
    tearDown(() => db.close());

    Uint8List usr(List<Map<int, String>> rows) => buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['zk_Dance_ID', 'Name', 'Reference', 'PageNumber'],
        rows: [for (final (i, row) in rows.indexed) MapEntry(10 + i, row)],
      ),
    ]);

    Future<CcUsrImportResult> import(Uint8List bytes) =>
        importer.import(bytes, now: now, venueEntityMode: false, newId: nextId);

    Future<List<({PublishedSource source, bool deleted})>> allSources() =>
        sources.listAllWithDeleted();

    test(
      'creates one source for the dances citing a title; undo removes it',
      () async {
        final result = await import(
          usr([
            {1: '4', 2: 'A', 3: 'Zesty Contras', 4: '12'},
            {1: '7', 2: 'B', 3: 'Zesty Contras', 4: '30'},
          ]),
        );
        final created = await allSources();
        expect(created.map((s) => s.source.title), ['Zesty Contras']);
        final id = created.single.source.id;
        expect(result.insertedPublishedSourceIds, [id]);
        final pages = [
          for (final d in await dances.listAll())
            for (final c in d.sourceCitations)
              if (c.sourceId == id) c.page,
        ];
        expect(pages, unorderedEquals(['12', '30']));

        await importer.undo(result);
        expect(await allSources(), isEmpty);
      },
    );

    test('reuses a live source with the same title and nothing else', () async {
      await sources.upsert(
        PublishedSource(id: 'mine', title: 'Zesty Contras'),
        at: now,
      );
      final result = await import(
        usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
        ]),
      );
      expect(result.insertedPublishedSourceIds, isEmpty);
      expect(result.restoredPublishedSourceIds, isEmpty);
      expect(
        (await dances.listAll()).single.sourceCitations.single.sourceId,
        'mine',
      );
      await importer.undo(result);
      expect((await allSources()).map((s) => (s.source.id, s.deleted)), [
        ('mine', false),
      ]);
    });

    test(
      'a source matches by title, whatever else the user filled in',
      () async {
        await sources.upsert(
          PublishedSource(id: 'mine', title: 'Zesty Contras', author: 'Gene'),
          at: now,
        );
        final result = await import(
          usr([
            {1: '4', 2: 'A', 3: 'zesty contras'},
          ]),
        );
        expect(result.insertedPublishedSourceIds, isEmpty);
        expect(
          (await dances.listAll()).single.sourceCitations.single.sourceId,
          'mine',
        );
        await importer.undo(result);
        expect((await allSources()).map((s) => (s.source.id, s.deleted)), [
          ('mine', false),
        ]);
      },
    );

    test('a live source beats a deleted one, and an exact title a case '
        'variant', () async {
      for (final (id, title) in [
        ('a', 'zesty contras'),
        ('b', 'Zesty Contras'),
        ('c', 'Zesty Contras'),
      ]) {
        await sources.upsert(
          PublishedSource(id: id, title: title),
          at: now,
        );
      }
      await sources.delete('b', at: now);
      await import(
        usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
        ]),
      );
      expect(
        (await dances.listAll()).single.sourceCitations.single.sourceId,
        'c',
      );
    });

    test('case variants in one file share one source', () async {
      final result = await import(
        usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
          {1: '7', 2: 'B', 3: 'ZESTY CONTRAS'},
        ]),
      );
      expect(result.insertedPublishedSourceIds, hasLength(1));
      expect(await allSources(), hasLength(1));
    });

    test('re-importing the file reuses the source and cites it once', () async {
      final bytes = usr([
        {1: '4', 2: 'A', 3: 'Zesty Contras', 4: '12'},
      ]);
      await import(bytes);
      final again = await import(bytes);
      expect(again.insertedPublishedSourceIds, isEmpty);
      expect(await allSources(), hasLength(1));
      expect(
        (await dances.listAll()).single.sourceCitations.map((c) => c.page),
        ['12'],
      );
    });

    test('undo keeps a source a dance of the user\'s now cites', () async {
      final result = await import(
        usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
        ]),
      );
      final id = result.insertedPublishedSourceIds.single;
      await dances.create(
        Dance(
          id: 'mine',
          title: 'Mine',
          sourceCitations: [SourceCitation(sourceId: id, page: '3')],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await importer.undo(result);
      expect((await allSources()).map((s) => (s.source.id, s.deleted)), [
        (id, false),
      ]);
      expect(
        (await dances.getById('mine'))!.sourceCitations.single.sourceId,
        id,
      );
    });

    test('the per-row Edit commit resolves the source too', () async {
      final batch = await importer.plan(
        usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
        ]),
      );
      await importer.commitDances(batch, now: now, newId: nextId);
      final id = (await allSources()).single.source.id;
      expect(
        (await dances.listAll()).single.sourceCitations.single.sourceId,
        id,
      );
    });

    test('restores a deleted source rather than duplicating it; undo deletes '
        'it again', () async {
      await sources.upsert(
        PublishedSource(id: 'gone', title: 'Zesty Contras'),
        at: now,
      );
      await sources.delete('gone', at: now);
      final result = await import(
        usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
        ]),
      );
      expect(result.restoredPublishedSourceIds, ['gone']);
      expect((await allSources()).map((s) => (s.source.id, s.deleted)), [
        ('gone', false),
      ]);
      await importer.undo(result);
      expect((await allSources()).map((s) => (s.source.id, s.deleted)), [
        ('gone', true),
      ]);
    });

    test('a source only a skipped dance cites is not kept', () async {
      final batch = await importer.plan(
        usr([
          {1: '4', 2: 'A'},
          {1: '7', 2: 'B', 3: 'Zesty Contras'},
        ]),
      );
      final result = await importer.commit(
        ImportBatchResult(
          records: [
            batch.records[0],
            ImportRecordPlan(
              draft: batch.records[1].draft,
              verdict: DedupeVerdict.ambiguous(const []),
            ),
          ],
        ),
        CcUsrArchive(dances: const [], sets: const [], warnings: const []),
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );
      expect(result.danceSession.committedCount, 1);
      expect(result.insertedPublishedSourceIds, isEmpty);
      expect(await allSources(), isEmpty);
    });

    test('a failed commit removes the source it created', () async {
      final failing = CallersCompanionUsrImporter(
        ImportPipeline(dances, ChoreographerRepository(db)),
        _FailingProgramRepository(db),
        VenueRepository(db),
        CustomFieldDefRepository(db),
        publishedSources: sources,
      );
      final bytes = buildFmp12Fixture([
        FmpFixtureTable(
          index: 1,
          name: 'Dance',
          columnNames: ['zk_Dance_ID', 'Name', 'Reference'],
          rows: [
            MapEntry(10, {1: '4', 2: 'A', 3: 'Zesty Contras'}),
          ],
        ),
        FmpFixtureTable(
          index: 2,
          name: 'Set',
          columnNames: ['zk_Set_ID', 'Location'],
          rows: [
            MapEntry(20, {1: '1', 2: 'Hall'}),
          ],
        ),
      ]);
      await expectLater(
        failing.import(bytes, now: now, venueEntityMode: false, newId: nextId),
        throwsA(isA<StateError>()),
      );
      expect(await dances.listAll(includeDeleted: true), isEmpty);
      expect(await allSources(), isEmpty);
    });
    test(
      'a failure reading back an earlier dance removes the source',
      () async {
        final throwing = CallersCompanionUsrImporter(
          ImportPipeline(
            _ThrowingGetDances(db, contraTaxonomy),
            ChoreographerRepository(db),
          ),
          ProgramRepository(db),
          VenueRepository(db),
          CustomFieldDefRepository(db),
          publishedSources: sources,
        );
        final bytes = usr([
          {1: '4', 2: 'A', 3: 'Zesty Contras'},
        ]);
        await expectLater(
          throwing.commit(
            await throwing.plan(bytes),
            CcUsrArchive(dances: const [], sets: const [], warnings: const []),
            now: now,
            venueEntityMode: false,
            newId: nextId,
            earlierDanceIds: const {'99': 'boom'},
          ),
          throwsA(isA<StateError>()),
        );
        expect(await dances.listAll(includeDeleted: true), isEmpty);
        expect(await allSources(), isEmpty);
      },
    );
  });

  group('set flags', () {
    CcUsrArchive archive(
      List<Map<int, String>> items, {
      Map<int, String> set = const {},
    }) => extractCcUsrArchive(
      FmpDatabase(
        versionNum: 12,
        creator: 'test',
        warnings: const [],
        tables: [
          FmpTable(
            1,
            'Dance',
            [FmpColumn(1, 'zk_Dance_ID'), FmpColumn(2, 'Name')],
            [
              for (final id in ['1', '2', '3', '4'])
                FmpRecord(int.parse(id), {1: id, 2: 'Dance $id'}),
            ],
          ),
          FmpTable(
            2,
            'Set',
            [
              FmpColumn(1, 'zk_Set_ID'),
              FmpColumn(2, 'Location'),
              FmpColumn(3, 'SetList_HideALT'),
            ],
            [
              FmpRecord(20, {1: '1', 2: 'Hall', ...set}),
            ],
          ),
          FmpTable(
            3,
            'SetItem',
            [
              FmpColumn(1, 'zk_Set_ID'),
              FmpColumn(2, 'zk_Dance_ID'),
              FmpColumn(3, 'Order'),
              FmpColumn(4, 'Break'),
              FmpColumn(5, 'AlternateDance'),
            ],
            [
              for (final (i, item) in items.indexed)
                FmpRecord(30 + i, {1: '1', 3: '${i + 1}', ...item}),
            ],
          ),
        ],
      ),
    );

    List<String> slotsOf(CcUsrArchive a) {
      final program = buildCcPrograms(
        a,
        danceIdByCcRowId: {
          for (final id in ['1', '2', '3', '4']) id: 'd$id',
        },
      ).programs.single;
      return [for (final s in program.slots) s.danceId ?? '"${s.text}"'];
    }

    test('Break puts a break slot after its dance', () {
      // CC's own tooltip: "a break occurs after this dance".
      expect(
        slotsOf(
          archive([
            {2: '1'},
            {2: '2', 4: '1'},
            {2: '3'},
          ]),
        ),
        ['d1', 'd2', '"Break"', 'd3'],
      );
    });

    test('the break comes after the dance\'s alternates', () {
      final a = archive([
        {2: '1', 4: '1'},
        {2: '2', 5: '1'},
        {2: '3'},
      ]);
      final slots = buildCcPrograms(
        a,
        danceIdByCcRowId: {'1': 'd1', '2': 'd2', '3': 'd3'},
      ).programs.single.slots;
      expect(
        [for (final s in slots) (s.danceId ?? s.text, s.isAlt)],
        [('d1', false), ('d2', true), ('Break', false), ('d3', false)],
      );
    });

    test('a break on the last dance closes the program', () {
      expect(
        slotsOf(
          archive([
            {2: '1'},
            {2: '2', 4: '1'},
          ]),
        ),
        ['d1', 'd2', '"Break"'],
      );
    });

    test('a set that already has its break slot there gets no second one', () {
      final a = extractCcUsrArchive(
        FmpDatabase(
          versionNum: 12,
          creator: 'test',
          warnings: const [],
          tables: [
            FmpTable(
              1,
              'Dance',
              [FmpColumn(1, 'zk_Dance_ID'), FmpColumn(2, 'Name')],
              [
                FmpRecord(1, {1: '1', 2: 'A'}),
                FmpRecord(2, {1: '2', 2: 'B'}),
              ],
            ),
            FmpTable(
              2,
              'Set',
              [FmpColumn(1, 'zk_Set_ID')],
              [
                FmpRecord(20, {1: '1'}),
              ],
            ),
            FmpTable(
              3,
              'SetItem',
              [
                FmpColumn(1, 'zk_Set_ID'),
                FmpColumn(2, 'zk_Dance_ID'),
                FmpColumn(3, 'Order'),
                FmpColumn(4, 'Break'),
                FmpColumn(5, 'BreakText'),
              ],
              [
                FmpRecord(30, {1: '1', 2: '1', 3: '1', 4: '1'}),
                FmpRecord(31, {1: '1', 3: '2', 5: 'break'}),
                FmpRecord(32, {1: '1', 2: '2', 3: '3'}),
              ],
            ),
          ],
        ),
      );
      expect(slotsOf(a), ['d1', '"break"', 'd2']);
    });

    test('a slot without a dance flagged Break is the break, not "1"', () {
      expect(
        slotsOf(
          archive([
            {2: '1'},
            {4: '1'},
            {2: '2'},
          ]),
        ),
        ['d1', '"Break"', 'd2'],
      );
    });

    test('SetList_HideALT hides the program\'s alternates', () {
      Program programOf(Map<int, String> set) => buildCcPrograms(
        archive([
          {2: '1'},
        ], set: set),
        danceIdByCcRowId: const {'1': 'd1'},
      ).programs.single;
      expect(programOf({3: '1'}).hideAlternates, isTrue);
      expect(programOf(const {}).hideAlternates, isFalse);
    });
  });
}

class _FailingProgramRepository extends ProgramRepository {
  _FailingProgramRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) async =>
      throw StateError('simulated program persist failure');
}

/// Reads back every dance but the one id an earlier Edit names, which throws.
class _ThrowingGetDances extends DanceRepository {
  _ThrowingGetDances(super.db, super.taxonomy);

  @override
  Future<Dance?> getById(
    String id, {
    bool includeDeleted = false,
    bool includeDeletedAuthors = false,
  }) {
    if (id == 'boom') throw StateError('simulated read failure');
    return super.getById(
      id,
      includeDeleted: includeDeleted,
      includeDeletedAuthors: includeDeletedAuthors,
    );
  }
}
