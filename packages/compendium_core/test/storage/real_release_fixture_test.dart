// Opens databases that a REAL release wrote, migrates them to head, and reads
// the data back.
//
// Every other migration test builds its starting file from a drift schema
// snapshot (`GeneratedHelper`), which carries structure only and is seeded by
// the test with just the rows that test asserts on. That cannot notice an
// `onUpgrade` step that destroys or mangles what a shipped database holds:
// `UPDATE dances SET figures_json = '[]'` at the top of `onUpgrade` leaves all
// of them green. These fixtures are the only files here with rows, FTS content,
// links, provenance and the settings markers a real startup wrote.
//
// What is asserted is every value the generator seeds to something other than a
// default, in the tables a user sees content from (dances, figures and their
// params, links, citations, provenance, tags, authors, venue, sources, custom
// fields, the program and its slots, the `ui.*` settings), the default
// difficulty levels and the file's integrity. Columns left at their defaults
// are not read, nor are the bookkeeping timestamps of the tag, author, venue,
// source, custom-field, difficulty-level and settings rows. Derived values that
// the open legitimately rebuilds are not compared: the FTS tables,
// `canonical_text`, `dance_figures` and the `__*_done` repair markers (deleting
// all of them, or blanking `dance_figures.params_json`, before the open leaves
// the migration's result identical). Search is only checked to work.
//
// Each fixture is produced by its own generator under
// `tool/fixture_generators/`, run against the release's tag (recipe in its
// header): `generate_release_fixture.dart` for v40, `generate_v41_fixture.dart`
// for v41. Their digests are in `docs/design/storage.md`.
//
// A second fixture, `v41.sqlite`, comes from `v0.10.0-beta`, the last release
// before head, by its own generator
// (`generate_v41_fixture.dart`). The floor fixture proves the schema
// steps from the floor keep a v0.8 database's rows; it cannot hold what only
// v0.9 and v0.10 could write (the figures and params of contra taxonomy v38 and
// v39, pass by and pass through as separate moves, English and square dances,
// program pay, container titles), so it cannot show that today's taxonomy and
// migrations still read those. The v41 fixture's assertions read every value
// its generator seeds, and check the figures whose meaning a later taxonomy
// changed (pass by, pass through, long lines, the new params) as today's
// taxonomy resolves them.
//
// The floor fixture's file name is derived from [kMinSupportedSchemaVersion],
// so raising the floor fails the existence guard until a fixture for the new
// floor has been captured from that release's tag. At a floor of 41 the
// existing `v41.sqlite` is that fixture: do not re-capture it with the v40
// generator, which would drop its v0.9 and v0.10 data. The floor test picks the
// assertions for the floor's fixture ([_floorMigratesAndKeepsItsData]), and
// fails by name for a floor with none.

import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import '../figures_support.dart';
import '../test_package_root.dart';

/// The floor fixture's test: the assertions written for the rows its own
/// generator seeds. A floor with no assertions yet fails here by name, rather
/// than against another fixture's rows.
Future<void> _floorMigratesAndKeepsItsData(Directory dir, int floor) async {
  switch (floor) {
    case 40:
      await _migratesAndKeepsItsData(dir, await _fixture(40), stampedAt: 40);
    case 41:
      await _v41MigratesAndKeepsItsData(dir, await _fixture(41));
    default:
      fail(
        'no assertions for a v$floor floor fixture: write them for the rows '
        "its generator seeds, as for v40 and v41",
      );
  }
}

/// Where the checked-in fixture for [schemaVersion] lives.
Future<File> _fixture(int schemaVersion) async => File(
  p.join(
    await packageRootPath(),
    'test',
    'storage',
    'fixtures',
    'v$schemaVersion.sqlite',
  ),
);

String _moveAndParams(Figure f) => '${f.move} ${jsonEncode(f.params)}';

/// The instant every row of the generator's seed is stamped with.
final _seededAt = DateTime.utc(2026, 8, 1, 12);

/// Opens a copy of [source] with the current build, runs the real startup
/// migration, and asserts what must survive it.
///
/// [stampedAt] is the schema version the fixture's release wrote; it is
/// asserted on the untouched copy so a fixture swapped for a different capture
/// cannot pass under the wrong name.
Future<void> _migratesAndKeepsItsData(
  Directory dir,
  File source, {
  required int stampedAt,
}) async {
  expect(
    source.existsSync(),
    isTrue,
    reason:
        'missing ${p.basename(source.path)}: the fixture for schema version '
        '$stampedAt must stay in the repository (see '
        'tool/fixture_generators/generate_release_fixture.dart to capture one)',
  );
  final path = p.join(dir.path, p.basename(source.path));
  await source.copy(path);

  final pre = sqlite3.sqlite3.open(path);
  expect(
    pre.select('PRAGMA user_version').first.columnAt(0),
    stampedAt,
    reason:
        'the fixture must be stamped with the release schema it is named for',
  );
  expect(
    pre.select('SELECT count(*) FROM dances').first.columnAt(0),
    4,
    reason: 'the fixture holds rows to migrate',
  );
  // The release's own startup wrote its one-shot repair markers. This is a
  // check on the fixture, not on the migration: opening a database re-creates
  // any missing marker (deleting them all before the open left this test green),
  // so their presence *after* migration would prove nothing.
  expect(
    pre
        .select(
          'SELECT count(*) FROM settings '
          "WHERE key = '__purge_corruption_repair_done__'",
        )
        .first
        .columnAt(0),
    1,
    reason: 'the fixture must come from a real startup, with its markers',
  );
  pre.close();

  final db = CompendiumDatabase(NativeDatabase(File(path)));
  final repos = CompendiumRepositories(db, contraTaxonomy);
  await repos.ensureMigrated();

  // --- dances, relations and figures ---------------------------------------
  final chase = (await repos.dances.getById('d-chase'))!;
  expect(chase.title, 'Chase the Squirrel');
  expect(chase.authorIds, ['c-gaudet']);
  expect(chase.tagIds.toSet(), {'t-beginner', 't-gender-free'});
  expect(chase.hook, 'Squirrel hook with café — diacritics');
  expect(chase.callingNotes, 'Teach the swing carefully.');
  expect(chase.walkthrough, 'Walk it twice.');
  expect(chase.rating, 4);
  expect(chase.createdAt, _seededAt);
  expect(chase.updatedAt, _seededAt);
  expect(tunesOf(chase), ['Rakish Paddy', "Cuckoo's Nest"]);
  final figures = figuresOf(chase);
  expect(figures, hasLength(4));
  expect(figures.map((f) => f.move).toList(), [
    'balance',
    'swing',
    'circle',
    'meanwhile',
  ]);
  // Params are what a figure *means* (who swings, for how long): a migration
  // that kept the moves but mangled their params would still pass a count.
  expect(figures[0].params, {'who': 'neighbors'});
  expect(figures[1].params, {'who': 'neighbors', 'beats': 8});
  expect(figures[2].params, {'direction': 'left', 'beats': 8});
  expect(figures[3].params['beats'], 8);
  final nested = (figures[3].params['figures'] as List<Object?>).cast<Figure>();
  expect(nested.map((f) => (f.move, f.params['who'])), [
    ('swing', 'partners'),
    ('balance', 'partners'),
  ]);
  expect(chase.customFields.map((f) => (f.fieldId, f.value)), [
    ('cf-energy', 'high'),
  ]);
  expect(chase.links.map((l) => l.id).toSet(), {'l-1', 'l-2'});
  final video = chase.links.singleWhere((l) => l.id == 'l-1');
  expect(video.kind, LinkKind.video);
  expect(video.url, 'https://example.org/v');
  expect(video.label, 'Demo');
  final related = chase.links.singleWhere((l) => l.id == 'l-2');
  expect(related.kind, LinkKind.relatedDance);
  expect(related.targetDanceId, 'd-plain');
  expect(related.transitive, isTrue);
  expect(chase.sourceCitations.single.sourceId, 'ps-1');
  expect(chase.sourceCitations.single.page, '12');
  expect(chase.sourceCitations.single.number, 'A1');
  final provenance = chase.provenance!;
  expect(provenance.source, ProvenanceSource.callersbox);
  expect(provenance.externalId, 'cb-4242');
  expect(provenance.permission, 'full');
  expect(provenance.license, 'CC-BY');
  expect(provenance.sourceVersion, '2026-07');
  expect(provenance.importedAt, _seededAt);

  expect(
    figuresOf((await repos.dances.getById('d-fts'))!).map(_moveAndParams),
    ['robins_chain {"who":"neighbors"}'],
  );
  expect((await repos.dances.getById('d-fts'))!.title, 'Résumé Reel');
  expect((await repos.dances.getById('d-fts'))!.hook, 'hey for four');
  final plain = (await repos.dances.getById('d-plain'))!;
  expect(plain.title, 'Plain Dance');
  for (final dance in [plain, (await repos.dances.getById('d-fts'))!]) {
    expect(dance.createdAt, _seededAt);
    expect(dance.updatedAt, _seededAt);
  }

  // The tombstone survives as a tombstone: still there, still deleted.
  expect(await repos.dances.getById('d-gone'), isNull);
  expect(await repos.dances.isDeletedById('d-gone'), isTrue);
  final gone = (await repos.dances.getById('d-gone', includeDeleted: true))!;
  expect(gone.title, 'Deleted Dance');
  expect(gone.createdAt, _seededAt);
  expect(gone.updatedAt, _seededAt);
  expect(gone.deletedAt, _seededAt);
  expect(figuresOf(gone).map(_moveAndParams), ['swing {"who":"partners"}']);

  // --- the rest of the library ---------------------------------------------
  final beginner = (await repos.tags.getById('t-beginner'))!;
  expect(beginner.name, 'Beginner');
  expect(beginner.color, 0xFF336699);
  expect((await repos.tags.getById('t-gender-free'))!.name, 'Gender-free');
  expect((await repos.tags.getById('t-gender-free'))!.color, isNull);
  final author = (await repos.choreographers.getById('c-gaudet'))!;
  expect(author.name, 'Gaudet, Ted');
  expect(author.notes, 'Café notes');
  expect(author.website, 'https://example.org/ted');
  expect(author.location, 'Boston');
  final old = (await repos.choreographers.getById('c-old'))!;
  expect(old.name, 'Old Timer');
  expect(old.deceased, isTrue);
  final venue = (await repos.venues.getById('v-grange'))!;
  expect(venue.name, 'Grange Hall');
  expect(venue.city, 'Lexington');
  expect(venue.stateProv, 'MA');
  expect(venue.contact1Name, 'Pat Booker');
  expect(venue.contact1Email, 'pat@example.org');
  final published = (await repos.publishedSources.getById('ps-1'))!;
  expect(published.title, 'Zesty Contras');
  expect(published.author, 'Larry Jennings');
  expect(published.year, 1983);
  final energy = (await repos.customFieldDefs.getById('cf-energy'))!;
  expect(energy.key, 'energy');
  expect(energy.label, 'Energy');
  expect(energy.showInList, isTrue);
  expect(energy.type, CustomFieldType.choice);
  expect(energy.choices, ['low', 'medium', 'high']);
  expect((await repos.difficultyLevels.listAll()).map((l) => (l.id, l.label)), [
    ('difficulty-beginner', 'Beginner'),
    ('difficulty-intermediate', 'Intermediate'),
    ('difficulty-advanced', 'Advanced'),
  ]);

  // --- full-text search -----------------------------------------------------
  expect(await repos.dances.searchText('squirrel'), contains('d-chase'));
  // Diacritic folding: "Résumé" is found by "resume", and "café" by "cafe".
  expect(await repos.dances.searchText('resume'), ['d-fts']);
  expect(await repos.dances.searchText('cafe'), contains('d-chase'));
  expect(
    await repos.dances.searchText('deleted'),
    isEmpty,
    reason: 'a soft-deleted dance must not be searchable',
  );

  // --- program --------------------------------------------------------------
  final program = (await repos.programs.getById('p-spring'))!;
  expect(program.title, 'Spring Dance 2026');
  expect(program.createdAt, _seededAt);
  expect(program.updatedAt, _seededAt);
  expect(program.venueId, 'v-grange');
  expect(program.venue, 'Grange Hall');
  expect(program.dancerLevel, 'mixed');
  expect(program.notes, 'bring snacks');
  expect(program.eventDate, DateTime.utc(2026, 3, 15));
  expect(program.caller, 'Alex Caller');
  expect(program.band, 'The Reelers');
  expect(
    program.slots.map((s) => (s.id, s.position, s.danceId, s.text, s.isAlt)),
    [
      ('s-1', 0, 'd-chase', null, false),
      ('s-2', 1, null, 'Break / waltz', false),
      ('s-3', 2, 'd-plain', null, true),
    ],
  );
  expect(program.slots[0].walkthroughMinutes, 5);
  expect(program.slots[0].danceMinutes, 12);
  expect(program.slots[2].guestCaller, 'Sam');

  // --- settings --------------------------------------------------------------
  expect(await repos.settings.get('ui.theme'), 'dark');
  expect(await repos.settings.get('ui.sort'), {'by': 'title', 'asc': true});
  await db.close();

  // --- the file itself ------------------------------------------------------
  final raw = sqlite3.sqlite3.open(path);
  addTearDown(raw.close);
  expect(
    raw.select('PRAGMA user_version').first.columnAt(0),
    kCompendiumSchemaVersion,
    reason: 'a supported database must migrate all the way to head',
  );
  expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  expect(raw.select('PRAGMA integrity_check').first.columnAt(0), 'ok');
  expect(
    raw.select('SELECT count(*) FROM dances').first.columnAt(0),
    4,
    reason: 'migration must not add or drop dances',
  );
  expect(
    raw.select('SELECT count(*) FROM dance_fts').first.columnAt(0),
    greaterThan(0),
    reason: 'the search index must be populated after migration',
  );
}

/// The instant every row of the v41 generator's seed is stamped with.
final _v41SeededAt = DateTime.utc(2026, 11, 20, 12);

/// [_migratesAndKeepsItsData] for `v41.sqlite`, written by `v0.10.0-beta` from
/// `generate_v41_fixture.dart`'s seed: what only v0.9.x and v0.10.0
/// could write, read back with today's code.
Future<void> _v41MigratesAndKeepsItsData(Directory dir, File source) async {
  expect(
    source.existsSync(),
    isTrue,
    reason:
        'missing v41.sqlite: capture it from v0.10.0-beta with '
        'tool/fixture_generators/generate_v41_fixture.dart',
  );
  final path = p.join(dir.path, p.basename(source.path));
  await source.copy(path);

  final pre = sqlite3.sqlite3.open(path);
  expect(pre.select('PRAGMA user_version').first.columnAt(0), 41);
  expect(pre.select('SELECT count(*) FROM dances').first.columnAt(0), 3);
  expect(
    pre
        .select(
          'SELECT count(*) FROM settings '
          "WHERE key = '__taxonomy_v39_canonical_rebuild_done__'",
        )
        .first
        .columnAt(0),
    1,
    reason: 'the fixture must come from a real v0.10.0 startup',
  );
  pre.close();

  final db = CompendiumDatabase(NativeDatabase(File(path)));
  final repos = CompendiumRepositories(db, contraTaxonomy);
  await repos.ensureMigrated();
  final tax = contraTaxonomy;

  // --- the v0.9/v0.10 figures ----------------------------------------------
  final dance = (await repos.dances.getById('d-v10'))!;
  expect(dance.title, 'Eights and Passes');
  expect(dance.authorIds, ['c-kaynor']);
  expect(dance.form, DanceForm.contra);
  expect(dance.createdAt, _v41SeededAt);
  expect(dance.updatedAt, _v41SeededAt);
  final figures = figuresOf(dance);
  expect(figures, hasLength(14));
  // As stored: the release's own ids and params, unchanged by the open.
  expect(figures.take(13).map(_moveAndParams).toList(), [
    'long_lines {"beats":8}',
    'forward_and_back {"formation":"linesOfThree","goBack":false,"beats":4}',
    'figure_8 {"who":"ones","where":"below","lead":"onesRole1",'
        '"fraction":"other","amount":1.5,"double":true,"beats":24}',
    'poussette {"who":"role2s","whom":"partners","fraction":"other",'
        '"amount":1.25,"direction":"counterclockwise"}',
    'hey_for_three {"who":"threesRole1","whom":"foursRole2",'
        '"shoulder":"left","beats":16}',
    'starburst {"direction":"clockwise","travel":2,"who":"role2s",'
        '"whom":"partners"}',
    'trade_the_wave {"sides":"neighbors","center":"role2s",'
        '"centerHand":"left","axis":"along","balance":true,"beats":8}',
    'pass_by {"who":"partners","shoulder":"left"}',
    'pass_by {}',
    'pass_through {"where":"across"}',
    'pass_through {}',
    'circle {"direction":"right","places":"unspecified"}',
    'circular_hey {"who":"thirdCorners","who2":"opposites","changes":3}',
  ]);
  // Every figure is valid for today's taxonomy: no param it carries became
  // unknown or out of range.
  for (final f in figures.take(13)) {
    expect(
      tax
          .validateFigure(f)
          .where((i) => i.severity == ValidationSeverity.error)
          .map((i) => i.code),
      isEmpty,
      reason: '${f.move} must still validate',
    );
  }
  // What each figure means today: the move it resolves to, and the params it
  // has once aliases' pins and defaults apply. Pass by and pass through were
  // two moves at v0.10; taxonomy v40 made them one, told apart by `passType`,
  // and each stored figure must keep what it meant.
  (String, Object?) meaning(Figure f, String key) =>
      (tax.resolve(f.move)!.id, tax.effectiveParams(f)[key]);
  expect(meaning(figures[0], 'formation'), ('forward_and_back', 'longLines'));
  expect(meaning(figures[1], 'formation'), (
    'forward_and_back',
    'linesOfThree',
  ));
  expect(tax.effectiveParams(figures[2])['amount'], 1.5);
  expect(tax.effectiveParams(figures[2])['double'], isTrue);
  expect(tax.effectiveParams(figures[3])['amount'], 1.25);
  expect(meaning(figures[4], 'who'), ('hey_for_three', 'threesRole1'));
  expect(meaning(figures[5], 'travel'), ('starburst', 2));
  expect(meaning(figures[6], 'centerHand'), ('trade_the_wave', 'left'));
  for (final (i, passType, who, where, shoulder) in [
    (7, 'by', 'partners', 'unspecified', 'left'),
    (8, 'by', 'neighbors', 'unspecified', 'right'),
    (9, 'through', 'unspecified', 'across', 'right'),
    (10, 'through', 'unspecified', 'along', 'right'),
  ]) {
    final f = figures[i];
    final effective = tax.effectiveParams(f);
    expect(
      (
        tax.resolve(f.move)!.id,
        effective['passType'],
        effective['who'],
        effective['where'],
        effective['shoulder'],
      ),
      ('pass_through', passType, who, where, shoulder),
      reason: 'figure $i (${f.move}) must mean what it meant at v0.10',
    );
    expect(tax.resolvedMoveId(f), f.move);
  }
  expect(tax.effectiveParams(figures[11])['places'], 'unspecified');
  expect(meaning(figures[12], 'who2'), ('circular_hey', 'opposites'));
  final meanwhile = figures[13];
  expect(meanwhile.move, meanwhileMove);
  expect(meanwhile.params['beats'], 8);
  expect(meanwhile.params[containerTitleKey], 'Flutterwheel');
  final sides = (meanwhile.params['figures'] as List<Object?>).cast<Figure>();
  expect(sides.map((f) => f.move), [sequenceMove, 'swing']);
  expect(sides[1].params, {'who': 'twos'});
  expect(sides[0].params[containerTitleKey], 'Ones go');
  expect(sides[0].params['beats'], 8);
  expect(
    (sides[0].params['figures'] as List<Object?>).cast<Figure>().map(
      _moveAndParams,
    ),
    ['balance {"who":"ones"}', 'swing {"who":"ones"}'],
  );

  // --- English and square dances --------------------------------------------
  final ecd = (await repos.dances.getById('d-ecd'))!;
  expect(ecd.title, 'Hole in the Wall');
  expect(ecd.form, DanceForm.ecd);
  // Head's ECD migration is opt-in: an English dance stored before it keeps
  // its contra shape and moves, and reads as proper.
  expect(ecd.formation.shape, FormationShape.dupleProper);
  expect(ecd.formation.improper, isFalse);
  expect(ecd.phraseStructure.raw, '4*8*3');
  expect(ecd.callingNotes, 'Waltz time, 3/4.');
  expect(ecd.composedOn, PartialDate(1695));
  expect(figuresOf(ecd).map(_moveAndParams), [
    'pass_through {"where":"along"}',
    'long_lines {"beats":8}',
  ]);
  final square = (await repos.dances.getById('d-square'))!;
  expect(square.title, 'Grand Square Thing');
  expect(square.form, DanceForm.square);
  expect(square.formation.shape, FormationShape.other);
  expect(square.formation.detail, 'square set');
  expect(square.progression, Progression.none);
  expect(square.mixer, isTrue);
  expect(figuresOf(square).map(_moveAndParams), [
    'forward_and_back {"formation":"headCouples"}',
  ]);

  // --- program with pay -----------------------------------------------------
  final gig = (await repos.programs.getById('p-gig'))!;
  expect(gig.title, 'Greenfield Gig');
  expect(gig.eventDate, DateTime.utc(2026, 11, 14));
  expect(gig.venue, 'Town Hall');
  expect(gig.venueId, 'v-hall');
  expect(gig.caller, 'Alex Caller');
  expect(gig.band, 'Hot Pickles');
  expect(gig.status, ProgramStatus.performed);
  expect(gig.hideAlternates, isTrue);
  expect(gig.dialectName, 'Gender-free (larks/robins)');
  expect(gig.payMinorUnits, 25050);
  expect(gig.payCurrency, 'USD');
  expect(gig.createdAt, _v41SeededAt);
  expect(gig.updatedAt, _v41SeededAt);
  expect(gig.slots.map((s) => (s.id, s.position, s.danceId, s.isAlt)), [
    ('g-1', 0, 'd-v10', false),
    ('g-2', 1, 'd-ecd', true),
  ]);
  expect(gig.slots[0].performedAt, DateTime.utc(2026, 11, 14, 20));
  expect(gig.slots[1].performedAt, isNull);

  // --- venue, author, glossary ----------------------------------------------
  final hall = (await repos.venues.getById('v-hall'))!;
  expect(
    (
      hall.name,
      hall.address1,
      hall.city,
      hall.stateProv,
      hall.country,
      hall.sponsor,
      hall.price,
      hall.contact2Name,
      hall.contact2Phone,
    ),
    (
      'Town Hall',
      '1 Main St',
      'Greenfield',
      'MA',
      'US',
      'Friends of Contra',
      r'$12',
      'Robin Hood',
      '555-0100',
    ),
  );
  expect((await repos.choreographers.getById('c-kaynor'))!.name, 'Kaynor, Bob');
  final compound = (await repos.userGlossary.getById('ug-compound'))!;
  expect(compound.kind, UserGlossaryEntryKind.compound);
  expect(compound.name, 'Pass and eight');
  expect(compound.definition, 'A pass by then a long figure 8.');
  expect(compound.keywords, ['passeight']);
  expect(compound.createdAt, _v41SeededAt);
  // Decoded by today's taxonomy, which refuses a template figure it cannot
  // validate: the pass by and the figure 8's amount must still be valid.
  final definition = decodeCompoundDefinition(compound.payload, tax);
  expect(definition, isNotNull);
  expect(definition!.figures.map(_moveAndParams), [
    'pass_by {"who":"neighbors"}',
    'figure_8 {"fraction":"other","amount":2}',
  ]);
  expect(
    definition.bindings.map((b) => (b.figureIndex, b.slotKey, b.paramKey)),
    [(0, 'who', 'who')],
  );
  expect(definition.params.map((p) => (p.key, p.kind)), [
    ('who', ParamKind.dancerSet),
  ]);
  expect(
    (await repos.figureNotes.get('pass_by'))?.notes,
    'Watch the shoulder.',
  );

  expect(await repos.dances.searchText('passes'), ['d-v10']);
  await db.close();

  final raw = sqlite3.sqlite3.open(path);
  addTearDown(raw.close);
  expect(
    raw.select('PRAGMA user_version').first.columnAt(0),
    kCompendiumSchemaVersion,
  );
  expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  expect(raw.select('PRAGMA integrity_check').first.columnAt(0), 'ok');
  expect(raw.select('SELECT count(*) FROM dances').first.columnAt(0), 3);
}

void main() {
  late Directory dir;

  setUp(
    () async => dir = await Directory.systemTemp.createTemp('real_fixture_'),
  );
  tearDown(() => dir.delete(recursive: true));

  test('no fixture is left below the schema floor', () async {
    // Raising the floor retires the old floor's fixture along with its steps.
    // A file left behind has no migration path to head, so nothing could ever
    // open it, yet it would look like coverage.
    final fixtures = Directory(
      p.dirname((await _fixture(kMinSupportedSchemaVersion)).path),
    );
    final stale = [
      for (final f in fixtures.listSync().whereType<File>())
        if (RegExp(r'^v(\d+)\.sqlite$').firstMatch(p.basename(f.path))
            case final m?)
          if (int.parse(m.group(1)!) < kMinSupportedSchemaVersion)
            p.basename(f.path),
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'delete the fixtures below the floor (v$kMinSupportedSchemaVersion)',
    );
  });

  group('floor fixture (v$kMinSupportedSchemaVersion)', () {
    test('exists for the current schema floor', () async {
      // Derived from the constant on purpose: raising the floor makes this
      // fail until a database captured from the new floor's release tag is
      // committed under the new name, instead of silently leaving the floor
      // untested.
      final source = await _fixture(kMinSupportedSchemaVersion);
      expect(
        source.existsSync(),
        isTrue,
        reason:
            'the floor version must keep its fixture: capture '
            'test/storage/fixtures/v$kMinSupportedSchemaVersion.sqlite from '
            "the oldest supported release's tag with that release's generator "
            'under tool/fixture_generators/ (at a floor of 41, v41.sqlite is '
            'already there)',
      );
    });

    test('opens, migrates to head and keeps its data', () async {
      await _floorMigratesAndKeepsItsData(dir, kMinSupportedSchemaVersion);
    });
  });

  test('v0.10.0-beta fixture (v41) opens, migrates to head and keeps the '
      'figures, pay and dances only v0.9 and v0.10 could write', () async {
    await _v41MigratesAndKeepsItsData(dir, await _fixture(41));
  });
}
