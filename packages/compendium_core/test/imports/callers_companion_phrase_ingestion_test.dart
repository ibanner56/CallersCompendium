import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fmp_fixture_builder.dart';

/// Corpus regression for issue #559: choreography is ingested from the CC
/// `Phrase` table and routed through the shared free-text **fan-out**, end to
/// end through the real `.USR` adapter/importer path (not just
/// `extractCcUsrArchive`). The critical wiring this guards is that the joined
/// Phrase body survives the adapter's `discover → fetch → parse` JSON payload
/// round-trip — if it did not, `parse` would re-derive an EMPTY body from the
/// per-dance column map and silently drop every figure.
///
/// The fixture is a hand-built `.fmp12` byte image shaped like the real
/// `CallersCompanion2.USR` schema (the real 20 MB file is git-ignored and never
/// in CI): a `Dance` table plus a separate `Phrase` table keyed by
/// `zk_Dance_ID` + `PhraseNumber`, including a `PhraseText_GenderSwap_LR`
/// variant that must be ignored. Provenance mirrors
/// `callers_companion_usr_archive_test.dart`; the values are illustrative.
Uint8List _ccUsrWithPhrases() => buildFmp12Fixture([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
    rows: [
      MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
      MapEntry(11, {1: '7', 2: 'Petronella', 3: 'Trad'}),
    ],
  ),
  FmpFixtureTable(
    index: 2,
    name: 'Phrase',
    columnNames: [
      'zk_Dance_ID',
      'PhraseNumber',
      'PhraseText',
      'PhraseText_GenderSwap_LR',
    ],
    rows: [
      // Dance 4: a cleanly-structuring line, a compound-beat line (#560), and an
      // out-of-coverage line — supplied out of section order to exercise the
      // A1→A2→B1 ordering.
      MapEntry(102, {1: '4', 2: 'B1', 3: '(8) hey for four'}),
      MapEntry(100, {
        1: '4',
        2: 'A1',
        3: '(16) neighbors balance and swing',
        4: 'GENDER SWAPPED - must be ignored',
      }),
      MapEntry(101, {1: '4', 2: 'A2', 3: '(4,12) neighbors balance and swing'}),
      // Dance 7: two structured-friendly lines.
      MapEntry(103, {1: '7', 2: 'A1', 3: '(8) circle left 3 places'}),
      MapEntry(104, {1: '7', 2: 'B1', 3: '(8) partner do si do'}),
    ],
  ),
]);

void main() {
  final adapter = CallersCompanionUsrAdapter();

  group('adapter path (discover → fetch → parse)', () {
    Future<Dance> danceFor(String externalId) async {
      final discovered = await adapter.discover(
        ImportRequest(options: {'bytes': _ccUsrWithPhrases()}),
      );
      final record = discovered.firstWhere((d) => d.externalId == externalId);
      final raw = await adapter.fetch(record);
      return adapter.parse(raw).dance;
    }

    test('discovers every dance in the file', () async {
      final discovered = await adapter.discover(
        ImportRequest(options: {'bytes': _ccUsrWithPhrases()}),
      );
      expect(discovered.map((d) => d.externalId), containsAll(['4', '7']));
      expect(discovered, hasLength(2));
    });

    test('threads the joined Phrase body through to figures — one figure per '
        'Phrase line, 0 dropped', () async {
      final dance = await danceFor('4');

      // Three Phrase lines (A1, A2, B1) → three figures. If the body had not
      // been threaded through the payload, this would be zero.
      expect(dance.figures, hasLength(3));
      expect(dance.title, 'Simplicity Swing');
    });

    test('routes body lines through the fan-out: a covered line structures', () {
      // "(16) neighbors balance and swing" → the fan-out (ContraDB > TCB > CC)
      // structures it as a swing with a balance prefix; the leading (16) is the
      // beat count.
      return danceFor('4').then((dance) {
        final swing = dance.figures.first;
        expect(swing.isCustom, isFalse);
        expect(swing.move, 'swing');
        expect(swing.params['who'], 'neighbors');
        expect(swing.params['prefix'], 'balance');
        expect(swing.beats, 16);
      });
    });

    test('a compound-beat line structures AND carries its summed beats (#560); '
        'an out-of-coverage line is an importGap custom (never dropped)', () async {
      final dance = await danceFor('4');

      // A2 "(4,12) neighbors balance and swing" structures to a swing via the
      // fan-out (the acceptance target), so the line is ingested — NOT dropped.
      // The COMPOUND beat prefix "(4,12)" (= 16 total) is parsed by the robust
      // beat split (#560): the line structures as a SINGLE swing, so the total
      // (16) rides on that lone figure.
      final compound = dance.figures[1];
      expect(compound.isCustom, isFalse);
      expect(compound.move, 'swing');
      expect(compound.params['who'], 'neighbors');
      expect(compound.beats, 16);

      // B1 "(8) hey for four" is out of the recognised cut → importGap custom,
      // stored verbatim (parse-never-fails, still not dropped).
      final hey = dance.figures[2];
      expect(hey.isCustom, isTrue);
      expect(hey.customOrigin, CustomOrigin.importGap);
      expect(hey.params['text'], 'hey for four');
    });

    test('every dance in the file carries figures', () async {
      final four = await danceFor('4');
      final seven = await danceFor('7');
      expect(four.figures, isNotEmpty);
      expect(seven.figures, hasLength(2));
      expect(seven.figures.every((f) => f.beats == 8), isTrue);
    });
  });

  group('full importer commit (pipeline path)', () {
    late CompendiumDatabase db;
    late DanceRepository dances;
    late ChoreographerRepository choreographers;
    late ProgramRepository programs;
    late VenueRepository venues;
    late ImportPipeline pipeline;
    late CallersCompanionUsrImporter importer;

    setUp(() {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
      choreographers = ChoreographerRepository(db);
      programs = ProgramRepository(db);
      venues = VenueRepository(db);
      pipeline = ImportPipeline(dances, choreographers);
      importer = CallersCompanionUsrImporter(
        pipeline,
        programs,
        venues,
        dances,
      );
    });

    tearDown(() => db.close());

    test(
      'committed dances carry the Phrase figures; undo reverts them',
      () async {
        var n = 0;
        final result = await importer.import(
          _ccUsrWithPhrases(),
          now: DateTime.utc(2026, 7, 15),
          venueEntityMode: false,
          newId: () => 'dance-${++n}',
          newSlotId: () => 'slot-${++n}',
        );

        expect(result.danceSession.committedCount, 2);
        final committed = await dances.listAll();
        expect(committed, hasLength(2));

        final byExternal = {
          for (final d in committed) d.provenance!.externalId!: d,
        };
        final four = byExternal['4']!;
        // The full pipeline path (plan → adapter.discover/fetch/parse → commit)
        // persisted the choreography, not just metadata: a structured swing, a
        // second swing from the compound-beat line whose "(4,12)" prefix sums to
        // 16 beats (#560), and one importGap custom — 3 figures, 0 Phrase lines
        // dropped.
        expect(four.figures, hasLength(3));
        expect(four.figures.first.move, 'swing');
        expect(four.figures[1].move, 'swing');
        expect(four.figures[1].beats, 16);
        expect(
          four.figures.where((f) => f.customOrigin == CustomOrigin.importGap),
          hasLength(1),
        );

        await importer.undo(result);
        expect(await dances.listAll(), isEmpty);
      },
    );
  });

  // OWASP hardening (#561) at the adapter boundary: an over-structured Phrase
  // table must fail closed with the friendly "too large" ImportError (surfaced
  // by discover), never OOM or a raw resource-limit throw-through. The
  // sanitization + join-degradation guards are proven hermetically against
  // hand-built FmpDatabase fixtures in callers_companion_usr_archive_test.dart
  // (the byte fixture's SCSU text encoding can't faithfully carry raw
  // control/bidi bytes, so those live at the archive layer).
  group('OWASP hardening — adapter fail-closed (#561)', () {
    // A fixture whose Phrase table has more rows than the injected cap.
    Uint8List ccUsrWithManyPhrases() => buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['zk_Dance_ID', 'Name'],
        rows: [
          MapEntry(10, {1: '4', 2: 'Simplicity Swing'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Phrase',
        columnNames: ['zk_Dance_ID', 'PhraseNumber', 'PhraseText'],
        rows: [
          for (var i = 0; i < 4; i++)
            MapEntry(100 + i, {1: '4', 2: 'A$i', 3: '(8) circle left'}),
        ],
      ),
    ]);

    test('an over-structured Phrase table fails closed with the friendly '
        '"too large" error', () async {
      final adapter = CallersCompanionUsrAdapter(
        limits: const FmpReadLimits(maxPhraseRows: 2),
      );
      await expectLater(
        adapter.discover(
          ImportRequest(options: {'bytes': ccUsrWithManyPhrases()}),
        ),
        throwsA(
          isA<ImportError>().having(
            (e) => e.message,
            'message',
            'That file is too large to import.',
          ),
        ),
      );
    });

    test('the same file imports cleanly under the default limits', () async {
      final adapter = CallersCompanionUsrAdapter();
      final discovered = await adapter.discover(
        ImportRequest(options: {'bytes': ccUsrWithManyPhrases()}),
      );
      expect(discovered, hasLength(1));
      expect(discovered.single.externalId, '4');
    });
  });
}
