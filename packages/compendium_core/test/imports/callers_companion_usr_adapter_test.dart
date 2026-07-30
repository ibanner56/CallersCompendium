import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'support/fmp_fixture_builder.dart';

/// Tests for [CallersCompanionUsrAdapter]. The reader/archive layers are tested
/// elsewhere; here we cover the adapter's own contract: byte intake (options
/// vs base64), the discover→fetch locator round-trip, the JSON parse path
/// (including that it reuses the shared mapping + scrub), and that malformed
/// input degrades to [ImportError] rather than throwing raw.
void main() {
  final adapter = CallersCompanionUsrAdapter();

  test('reports the Caller\'s Companion provenance source', () {
    expect(adapter.source, ProvenanceSource.callersCompanion);
  });

  group('byte intake / discover', () {
    test('non-FileMaker bytes in options degrade to an ImportError', () async {
      final request = ImportRequest(
        options: {'bytes': Uint8List.fromList(List<int>.filled(64, 0x41))},
      );
      await expectLater(
        adapter.discover(request),
        throwsA(
          isA<ImportError>().having(
            (e) => e.stage,
            'stage',
            ImportStage.discover,
          ),
        ),
      );
    });

    test('invalid base64 payload degrades to an ImportError', () async {
      const request = ImportRequest(payload: 'not valid base64 !!!');
      await expectLater(adapter.discover(request), throwsA(isA<ImportError>()));
    });

    test('a missing file degrades to an ImportError', () async {
      const request = ImportRequest();
      await expectLater(adapter.discover(request), throwsA(isA<ImportError>()));
    });

    test('an over-structured .USR fails closed with a friendly too-large '
        'ImportError', () async {
      // A valid two-table container, read under a limit of one table, must be
      // rejected with a user-safe "too large" message (OWASP A04/A05: fail
      // closed on untrusted, over-structured input) — not a raw exception.
      final bytes = buildFmp12Fixture([
        FmpFixtureTable(
          index: 1,
          name: 'Dance',
          columnNames: ['Name'],
          rows: [
            MapEntry(1, {1: 'Simplicity Swing'}),
          ],
        ),
        FmpFixtureTable(
          index: 2,
          name: 'Set',
          columnNames: ['Title'],
          rows: [
            MapEntry(1, {1: 'Friday Contra'}),
          ],
        ),
      ]);
      final limited = CallersCompanionUsrAdapter(
        limits: const FmpReadLimits(maxTables: 1),
      );
      await expectLater(
        limited.discover(ImportRequest(options: {'bytes': bytes})),
        throwsA(
          isA<ImportError>()
              .having((e) => e.stage, 'stage', ImportStage.discover)
              .having(
                (e) => e.message,
                'message',
                'That file is too large to import.',
              ),
        ),
      );
    });
  });

  group('fetch', () {
    test('serialises the row id + verbatim columns as JSON', () async {
      const discovered = DiscoveredRecord(
        source: ProvenanceSource.callersCompanion,
        externalId: '7',
        locator: {
          'rowId': '7',
          'columns': {'Name': 'Simplicity Swing', 'Rating': '3'},
        },
      );
      final raw = await adapter.fetch(discovered);

      expect(raw.externalId, '7');
      expect(raw.contentType, 'application/json');
      expect(raw.sourceVersion, CallersCompanionUsrAdapter.sourceVersion);

      final decoded = jsonDecode(raw.payload) as Map<String, dynamic>;
      expect(decoded['rowId'], '7');
      expect((decoded['columns'] as Map)['Name'], 'Simplicity Swing');
    });

    test('a locator missing its columns degrades to an ImportError', () async {
      const discovered = DiscoveredRecord(
        source: ProvenanceSource.callersCompanion,
        externalId: '7',
        locator: {'rowId': '7'},
      );
      await expectLater(adapter.fetch(discovered), throwsA(isA<ImportError>()));
    });
  });

  group('parse', () {
    RawRecord rawFor(Map<String, String> columns) => RawRecord(
      source: ProvenanceSource.callersCompanion,
      externalId: '7',
      sourceVersion: CallersCompanionUsrAdapter.sourceVersion,
      payload: jsonEncode({'rowId': '7', 'columns': columns}),
      contentType: 'application/json',
    );

    test('maps a dance and scrubs figure free-text via the shared parser', () {
      final draft = adapter.parse(
        rawFor({
          'Name': 'Simplicity Swing',
          'Type': 'Contra',
          'A1': '(8) gypsy your partner',
        }),
      );

      expect(draft.dance.title, 'Simplicity Swing');
      // "gypsy" is scrubbed to "shoulder round", which the shared parser then
      // recognises as a structured shoulder_round move (proof the scrub ran).
      final fig = draft.dance.figures.single;
      expect(fig.move, 'shoulder_round');
      expect(fig.params['who'], 'partners');
      expect(fig.toString().toLowerCase(), isNot(contains('gypsy')));
    });

    test('an out-of-range rating is dropped with a warning issue', () {
      final draft = adapter.parse(rawFor({'Name': 'X', 'Rating': '7'}));
      expect(draft.dance.rating, isNull);
      expect(
        draft.issues.any((i) => i.code == 'cc_rating_out_of_range'),
        isTrue,
      );
    });

    test('a valid rating is carried onto the dance', () {
      final draft = adapter.parse(rawFor({'Name': 'X', 'Rating': '4'}));
      expect(draft.dance.rating, 4);
    });

    test('malformed payload JSON degrades to an ImportError', () {
      final raw = RawRecord(
        source: ProvenanceSource.callersCompanion,
        payload: 'this is not json',
        contentType: 'application/json',
      );
      expect(() => adapter.parse(raw), throwsA(isA<ImportError>()));
    });

    test('a payload without a columns object degrades to an ImportError', () {
      final raw = RawRecord(
        source: ProvenanceSource.callersCompanion,
        payload: jsonEncode({'rowId': '7'}),
        contentType: 'application/json',
      );
      expect(() => adapter.parse(raw), throwsA(isA<ImportError>()));
    });

    test(
      'a legacy payload with an over-structured A1..C2 body fails closed with '
      'the friendly ImportError, not a raw resource-limit exception',
      () {
        // Legacy payload (no threaded `body`), so parse re-derives the body from
        // A1..C2 — which is now bounded by the CC caps. An over-structured A1
        // must surface the same user-safe "too large" message discover uses,
        // never leak a raw FmpResourceLimitException out of parse.
        final limited = CallersCompanionUsrAdapter(
          limits: const FmpReadLimits(maxFiguresPerDance: 3),
        );
        final raw = RawRecord(
          source: ProvenanceSource.callersCompanion,
          externalId: '7',
          sourceVersion: CallersCompanionUsrAdapter.sourceVersion,
          payload: jsonEncode({
            'rowId': '7',
            'columns': {
              'Name': 'X',
              'A1': List.generate(20, (i) => 'circle $i').join('\n'),
            },
          }),
          contentType: 'application/json',
        );
        expect(
          () => limited.parse(raw),
          throwsA(
            isA<ImportError>()
                .having((e) => e.stage, 'stage', ImportStage.parse)
                .having(
                  (e) => e.message,
                  'message',
                  'That file is too large to import.',
                ),
          ),
        );
      },
    );
  });
}
