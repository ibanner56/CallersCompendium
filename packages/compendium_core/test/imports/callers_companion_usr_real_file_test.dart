import 'dart:io';

import 'package:compendium_core/src/imports/callers_companion_programs.dart';
import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

/// End-to-end validation of the CC `.USR` path against a **real** Caller's
/// Companion database.
///
/// The real `CallersCompanion2.USR` (~20 MB, FileMaker Pro 12) is **not**
/// redistributed in the repo (it is a proprietary Claris/CC binary), so this
/// suite is **skipped unless** a copy is present, git-ignored, at
/// `test/imports/support/fmp_local/CallersCompanion2.USR`. CI therefore never
/// runs it; the hermetic fixtures in the sibling tests cover the same logic on
/// every run. Locally it is the ground-truth check that the reader + CC schema
/// layer parse a genuine CC file and that the CC field-value foreign keys
/// (`zk_Set_ID`/`zk_Dance_ID`) actually link sets, items and dances.
///
/// Observed structure of this sample (for reference): version 12, 22 tables,
/// 40 dances, 205 authors, 1 set, 7 set items. Its dances carry only metadata
/// (name/author/level/rating/type/formation/notes) — none have A1..B2 figure
/// notation — so the figure→`custom` path is exercised only by the synthetic
/// fixtures, not this file.
void main() {
  final fixture = File('test/imports/support/fmp_local/CallersCompanion2.USR');

  group('Caller\'s Companion real .USR (local-only)', () {
    test(
      'reader recovers the expected CC table and field names',
      () {
        final db = readFmp12(fixture.readAsBytesSync());
        expect(db.versionNum, 12);

        // Table names are read from the file's catalog, not fabricated.
        expect(
          db.tables.map((t) => t.name),
          containsAll(<String>[
            'Dance',
            'Author',
            'Set',
            'SetItem',
            'Venue',
            'Term',
            'Dance_Related',
            'Phrase',
          ]),
        );

        List<String> cols(String table) =>
            db.tableNamed(table)!.columns.map((c) => c.name).toList();

        // Every Dance field the mapper keys off is present under its real name.
        expect(
          cols('Dance'),
          containsAll(<String>[
            'Name',
            'Author1',
            'Author2',
            'Type',
            'SubType',
            'Formation',
            'ContraForm',
            'Progression',
            'Level',
            'Music',
            'Credits',
            'DateComposed',
            'DateRevised',
            'Rating',
            'A1',
            'A2',
            'B1',
            'B2',
            'C1',
            'C2',
            'UserDefined_1',
            'UserDefined_1_Name',
          ]),
        );

        // Set is identified by Date/Location (there is deliberately NO title
        // column — the program title is derived from Location downstream).
        final setCols = cols('Set');
        expect(
          setCols,
          containsAll(<String>[
            'zk_Set_ID',
            'Date',
            'Location',
            'Notes',
            'Band',
            'DancerLevel',
            'Caller',
          ]),
        );
        expect(
          setCols.any((c) => c.toLowerCase() == 'title'),
          isFalse,
          reason: 'CC Sets have no Title column',
        );

        expect(
          cols('SetItem'),
          containsAll(<String>[
            'zk_Set_ID',
            'zk_Dance_ID',
            'Order',
            'Break',
            'AlternateDance',
            'Caller',
            'Time',
          ]),
        );
      },
      skip: fixture.existsSync() ? false : 'no local CC .USR fixture present',
    );

    late CcUsrArchive archive;

    setUp(() {
      if (!fixture.existsSync()) return;
      archive = readCcUsrArchive(fixture.readAsBytesSync());
    });

    test(
      'reads the real dances/sets/items and links by CC field-value ids',
      () {
        // Dances are keyed by CC zk_Dance_ID (small ints), not the FileMaker
        // record ids (which are in the thousands).
        expect(archive.dances, hasLength(40));
        final byId = {for (final d in archive.dances) d.recordId: d};
        expect(byId['1']?.record.name, 'Balance to my Lou');
        expect(byId['4']?.record.name, 'Baby Rose, The');

        expect(archive.sets, hasLength(1));
        final set = archive.sets.single;
        expect(set.items, hasLength(7));
        // The item that references CC dance id 4 must exist and point at it.
        expect(
          set.items.any((i) => i.danceRecordId == '4'),
          isTrue,
          reason: 'a set item should reference CC dance id 4 (Baby Rose)',
        );

        // No stale "guessed column" warnings — the schema is confirmed.
        expect(archive.warnings.any((w) => w.contains('guessed')), isFalse);
      },
      skip: fixture.existsSync() ? false : 'no local CC .USR fixture present',
    );

    test(
      'buildCcPrograms resolves the real set items to imported dances',
      () {
        // Simulate the post-commit dance-id map keyed by CC dance id.
        final danceIds = {
          for (final d in archive.dances)
            d.recordId: 'compendium-${d.recordId}',
        };
        final result = buildCcPrograms(archive, danceIdByCcRowId: danceIds);

        expect(result.programs, hasLength(1));
        final program = result.programs.single;
        // The single set's title derives from its Location.
        expect(program.title, 'Example Set');

        final resolved = program.slots.where((s) => s.danceId != null).length;
        // Every set item whose CC dance id exists among the 40 dances should
        // resolve to a real dance rather than a placeholder — proving the
        // field-value linkage works on real data (the old record-id keying
        // resolved none).
        expect(resolved, greaterThan(0));
        final baby = danceIds['4'];
        expect(
          program.slots.any((s) => s.danceId == baby),
          isTrue,
          reason: 'the Baby Rose slot (CC dance id 4) should resolve',
        );
      },
      skip: fixture.existsSync() ? false : 'no local CC .USR fixture present',
    );
  });
}
