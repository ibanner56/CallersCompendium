import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// N2-6 (b): the retention purge's orphan GC erases only *bare* reference rows.
/// A tag, author or source that holds a detail survives as a **Not used** row.
void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late PublishedSourceRepository sources;
  late TagRepository tags;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    sources = PublishedSourceRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() => db.close());

  Future<void> purgeOnly(Dance dance) async {
    await dances.create(dance);
    await dances.softDelete(dance.id, at: DateTime.utc(2026, 2));
    await dances.purgeDeleted(now: DateTime.utc(2026, 6));
    expect(await dances.getById(dance.id, includeDeleted: true), isNull);
  }

  group('a tag', () {
    test('with a colour survives the purge', () async {
      // ignore: unused_result
      await tags.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFFAA3300));
      await purgeOnly(sampleDance(id: 'd1', tagIds: const ['t1']));
      expect([for (final t in await tags.listAll()) t.id], ['t1']);
    });

    test('with no colour is still erased', () async {
      // ignore: unused_result
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      await purgeOnly(sampleDance(id: 'd1', tagIds: const ['t1']));
      expect(await tags.listAll(), isEmpty);
    });
  });

  group('an author', () {
    final withDetail = <String, Choreographer Function()>{
      'website': () =>
          Choreographer(id: 'c1', name: 'A', website: 'https://a.example'),
      'notes': () => Choreographer(id: 'c1', name: 'A', notes: 'Calls well'),
      'email': () => Choreographer(id: 'c1', name: 'A', email: 'a@a.example'),
      'location': () => Choreographer(id: 'c1', name: 'A', location: 'Ghent'),
      'deceased mark': () => Choreographer(id: 'c1', name: 'A', deceased: true),
    };
    for (final entry in withDetail.entries) {
      test('with only a ${entry.key} survives the purge', () async {
        // ignore: unused_result
        await choreographers.upsert(entry.value());
        await purgeOnly(sampleDance(id: 'd1', authorIds: const ['c1']));
        expect([for (final c in await choreographers.listAll()) c.id], ['c1']);
      });
    }

    test('with no details is still erased', () async {
      // ignore: unused_result
      await choreographers.upsert(Choreographer(id: 'c1', name: 'A'));
      await purgeOnly(sampleDance(id: 'd1', authorIds: const ['c1']));
      expect(await choreographers.listAll(), isEmpty);
    });

    test('with only whitespace in a text field is still erased', () async {
      await db.customStatement(
        "INSERT INTO choreographers (id, name, website, notes, email, "
        "location, deceased) VALUES ('c1', 'A', '  ', '', ' ', '', 0)",
      );
      await db.customStatement(
        "INSERT INTO choreographers (id, name, website, notes, email, "
        "location, deceased) VALUES ('c2', 'B', char(9), char(10), "
        "char(13, 10), ' ' || char(9) || ' ', 0)",
      );
      await purgeOnly(sampleDance(id: 'd1', authorIds: const ['c1', 'c2']));
      expect(await choreographers.listAll(), isEmpty);
    });
  });

  test('a source with only tab or newline text is still erased', () async {
    await db.customStatement(
      "INSERT INTO published_sources (id, title, author, url, notes) "
      "VALUES ('s1', 'T', char(9), char(10), char(13, 10))",
    );
    await purgeOnly(
      sampleDance(
        id: 'd1',
        sourceCitations: [SourceCitation(sourceId: 's1')],
      ),
    );
    expect(await sources.listAll(), isEmpty);
  });

  group('a source', () {
    final withDetail = <String, PublishedSource Function()>{
      'author': () => PublishedSource(id: 's1', title: 'T', author: 'Pat'),
      'year': () => PublishedSource(id: 's1', title: 'T', year: 1998),
      'URL': () =>
          PublishedSource(id: 's1', title: 'T', url: 'https://t.example'),
      'notes': () => PublishedSource(id: 's1', title: 'T', notes: 'p. 4'),
    };
    for (final entry in withDetail.entries) {
      test('with only a ${entry.key} survives the purge', () async {
        await sources.upsert(entry.value());
        await purgeOnly(
          sampleDance(
            id: 'd1',
            sourceCitations: [SourceCitation(sourceId: 's1')],
          ),
        );
        expect([for (final s in await sources.listAll()) s.id], ['s1']);
      });
    }

    test('with no details is still erased', () async {
      await sources.upsert(PublishedSource(id: 's1', title: 'T'));
      await purgeOnly(
        sampleDance(
          id: 'd1',
          sourceCitations: [SourceCitation(sourceId: 's1')],
        ),
      );
      expect(await sources.listAll(), isEmpty);
    });
  });

  test('one purge spares the detailed row and erases the bare one', () async {
    // ignore: unused_result
    await tags.upsert(Tag(id: 't1', name: 'coloured', color: 0xFF112233));
    // ignore: unused_result
    await tags.upsert(Tag(id: 't2', name: 'bare'));
    await purgeOnly(sampleDance(id: 'd1', tagIds: const ['t1', 't2']));
    expect([for (final t in await tags.listAll()) t.id], ['t1']);
  });
}
