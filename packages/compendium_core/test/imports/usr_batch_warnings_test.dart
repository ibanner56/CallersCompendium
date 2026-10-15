import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fake_adapter.dart';
import 'support/fmp_fixture_builder.dart';

/// Batch-level warnings: concerns about a whole file (an incomplete `.USR`, an
/// archive from a newer app version) rather than one record.

Uint8List _usrBytes({int dances = 40}) => buildFmp12FixtureMultiSector([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
    rows: [
      for (var i = 1; i <= dances; i++)
        MapEntry(1000 + i, {1: '$i', 2: 'Dance number $i', 3: 'Alice Smith'}),
    ],
  ),
  FmpFixtureTable(
    index: 2,
    name: 'Set',
    columnNames: ['zk_Set_ID', 'Name'],
    rows: [
      MapEntry(1, {1: '1', 2: 'Evening'}),
    ],
  ),
  FmpFixtureTable(
    index: 3,
    name: 'SetItem',
    columnNames: ['zk_Set_ID', 'zk_Dance_ID'],
    rows: [
      MapEntry(1, {1: '1', 2: '1'}),
    ],
  ),
  FmpFixtureTable(
    index: 4,
    name: 'Dance_Related',
    columnNames: ['zk_Dance1_ID', 'zk_Dance2_ID'],
    rows: const [],
  ),
], options: const FmpMultiSectorOptions(sectorBudget: 300));

FmpDatabase _db(List<FmpTable> tables) => FmpDatabase(
  versionNum: 12,
  creator: 'Pro 12.0',
  tables: tables,
  warnings: const [],
);

FmpTable _dance(List<FmpRecord> rows) =>
    FmpTable(1, 'Dance', [FmpColumn(1, 'zk_Dance_ID')], rows);

void main() {
  group('CcUsrArchive.warningCodes', () {
    test('a complete file carries no truncation code', () {
      final archive = readCcUsrArchive(_usrBytes());
      expect(archive.dances, hasLength(40));
      expect(archive.warningCodes, isNot(contains('usr_file_truncated')));
    });

    test('a file cut in half carries usr_file_truncated', () {
      final full = _usrBytes();
      final half = Uint8List.sublistView(full, 0, full.length ~/ 2);
      final archive = readCcUsrArchive(half);
      expect(archive.warningCodes, contains('usr_file_truncated'));
      expect(archive.dances.length, lessThan(40));
      // The prose stays for logs and existing callers.
      expect(archive.warnings.any((w) => w.contains('ends early')), isTrue);
    });

    test(
      'a cut inside or right after the header carries usr_file_truncated',
      () {
        final full = _usrBytes();
        // 1024 bytes passes the header check; 4096 is the header sector alone.
        for (final length in [1024, 2000, 4096, 4096 + 100]) {
          final archive = readCcUsrArchive(
            Uint8List.sublistView(full, 0, length),
          );
          expect(
            archive.warningCodes,
            contains('usr_file_truncated'),
            reason: 'cut at $length bytes',
          );
          expect(archive.dances, isEmpty);
        }
      },
    );

    test('codes are distinct and withoutDances keeps them', () {
      final archive = extractCcUsrArchive(
        _db([
          _dance(const []),
          FmpTable(2, 'Phrase', [FmpColumn(1, 'Unrelated')], const []),
        ]),
      );
      expect(
        archive.warningCodes.toSet(),
        hasLength(archive.warningCodes.length),
      );
      expect(archive.withoutDances().warningCodes, archive.warningCodes);
    });

    test('Phrase columns that cannot be resolved: figures_from_dance_rows', () {
      final archive = extractCcUsrArchive(
        _db([
          _dance(const []),
          FmpTable(2, 'Phrase', [FmpColumn(1, 'Unrelated')], const []),
        ]),
      );
      expect(archive.warningCodes, contains('usr_figures_from_dance_rows'));
    });

    test('orphaned Phrase groups: phrase_groups_orphaned', () {
      final archive = extractCcUsrArchive(
        _db([
          _dance([
            FmpRecord(1, {1: '1'}),
          ]),
          FmpTable(
            2,
            'Phrase',
            [
              FmpColumn(1, 'zk_Dance_ID'),
              FmpColumn(2, 'PhraseNumber'),
              FmpColumn(3, 'PhraseText'),
            ],
            [
              FmpRecord(1, {1: '99', 2: '1', 3: 'balance'}),
            ],
          ),
        ]),
      );
      expect(archive.warningCodes, contains('usr_phrase_groups_orphaned'));
    });

    test('a missing Set table: sets_skipped', () {
      final archive = extractCcUsrArchive(_db([_dance(const [])]));
      expect(archive.warningCodes, contains('usr_sets_skipped'));
    });

    test('over-long figure lines: lines_dropped', () {
      final archive = extractCcUsrArchive(
        _db([
          _dance([
            FmpRecord(1, {1: '1'}),
          ]),
          FmpTable(
            2,
            'Phrase',
            [
              FmpColumn(1, 'zk_Dance_ID'),
              FmpColumn(2, 'PhraseNumber'),
              FmpColumn(3, 'PhraseText'),
            ],
            [
              FmpRecord(1, {1: '1', 2: '1', 3: 'x' * 5000}),
            ],
          ),
        ]),
        limits: const FmpReadLimits(maxBodyLineLength: 100),
      );
      expect(archive.warningCodes, contains('usr_lines_dropped'));
    });

    test('skipped Dance_Related rows: related_rows_skipped', () {
      final archive = extractCcUsrArchive(
        _db([
          _dance(const []),
          FmpTable(
            2,
            'Dance_Related',
            [FmpColumn(1, 'zk_Dance1_ID'), FmpColumn(2, 'zk_Dance2_ID')],
            [
              FmpRecord(1, {1: '4', 2: '4'}),
            ],
          ),
        ]),
      );
      expect(archive.warningCodes, contains('usr_related_rows_skipped'));
    });

    test('every code is in CcUsrWarningCodes.all', () {
      expect(CcUsrWarningCodes.all, hasLength(6));
    });
  });

  group('batch warnings through plan', () {
    late CompendiumDatabase db;
    late ImportPipeline pipeline;

    setUp(() {
      db = openTestDatabase();
      pipeline = ImportPipeline(
        DanceRepository(db, contraTaxonomy),
        ChoreographerRepository(db),
      );
    });

    tearDown(() => db.close());

    test('a truncated .USR plans with a usr_file_truncated warning', () async {
      final full = _usrBytes();
      final half = Uint8List.sublistView(full, 0, full.length ~/ 2);
      final batch = await pipeline.plan(
        CallersCompanionUsrAdapter(),
        ImportRequest(options: {'bytes': half}),
      );
      expect(batch.warnings.map((w) => w.code), contains('usr_file_truncated'));
      expect(batch.warnings.first.severity, ImportIssueSeverity.warning);
    });

    test('a complete .USR plans with no truncation warning', () async {
      final batch = await pipeline.plan(
        CallersCompanionUsrAdapter(),
        ImportRequest(options: {'bytes': _usrBytes()}),
      );
      expect(batch.plannedCount, 40);
      expect(
        batch.warnings.map((w) => w.code),
        isNot(contains('usr_file_truncated')),
      );
    });

    test('an adapter without batch warnings yields an empty list', () async {
      final batch = await pipeline.plan(
        FakeSourceAdapter([
          {'id': '1', 'title': 'Plain'},
        ]),
        const ImportRequest(),
      );
      expect(batch.warnings, isEmpty);
    });
  });

  group('GenericJsonAdapter newer-schema warning', () {
    String payload(int version) => encodeArchive(
      CompendiumArchive(
        schemaVersion: version,
        exportedAt: DateTime.utc(2026),
        dances: [
          Dance(
            id: 'd1',
            title: 'Newer Dance',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );

    test('an archive from this version carries no batch warning', () async {
      final adapter = GenericJsonAdapter();
      await adapter.discover(
        ImportRequest(payload: payload(archiveSchemaVersion)),
      );
      expect(adapter.batchWarnings, isEmpty);
    });

    test('a newer archive carries one archive_newer_schema warning and no '
        'per-row archive_read_warning for that cause', () async {
      final adapter = GenericJsonAdapter();
      final found = await adapter.discover(
        ImportRequest(payload: payload(archiveSchemaVersion + 1)),
      );
      expect(adapter.batchWarnings.map((w) => w.code), [
        'archive_newer_schema',
      ]);
      expect(
        adapter.batchWarnings.single.severity,
        ImportIssueSeverity.warning,
      );

      final draft = adapter.parse(await adapter.fetch(found.single));
      expect(
        draft.issues.where((i) => i.code == 'archive_read_warning'),
        isEmpty,
      );
    });

    test('discover resets the warning for the next file', () async {
      final adapter = GenericJsonAdapter();
      await adapter.discover(
        ImportRequest(payload: payload(archiveSchemaVersion + 1)),
      );
      await adapter.discover(
        ImportRequest(payload: payload(archiveSchemaVersion)),
      );
      expect(adapter.batchWarnings, isEmpty);
    });
  });
}
