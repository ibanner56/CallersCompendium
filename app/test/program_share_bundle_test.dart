import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  figures: [
    Figure(move: 'swing', params: {'beats': 16, 'who': 'partners'}),
  ],
  sourceCitations: const [],
  customFields: const [],
  createdAt: _now,
  updatedAt: _now,
);

ProgramSlot _slot(
  int position, {
  String? danceId,
  String? text,
  bool isAlt = false,
}) => ProgramSlot(
  id: 's$position',
  position: position,
  danceId: danceId,
  text: text,
  isAlt: isAlt,
);

Program _program({
  required List<ProgramSlot> slots,
  String title = 'Friday Contra',
}) => Program(
  id: 'p1',
  title: title,
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

/// Runs every dance in [json] through the full adapter path so we assert on the
/// dances the existing importer would actually commit.
Future<List<Dance>> _importedDances(String json) async {
  final adapter = GenericJsonAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: json));
  final dances = <Dance>[];
  for (final record in discovered) {
    final raw = await adapter.fetch(record);
    final draft = adapter.parse(raw);
    dances.add(draft.dance);
  }
  return dances;
}

void main() {
  group('buildProgramShareBundle', () {
    final catalog = {
      'd1': _dance('d1', 'Rory O\'More'),
      'd2': _dance('d2', 'The Nice Combination'),
      'd3': _dance('d3', 'Chinese New Year'),
    };
    Dance? danceFor(String id) => catalog[id];

    test('embeds every referenced dance, deduped, and preserves the program', () {
      final program = _program(
        slots: [
          _slot(0, danceId: 'd1'),
          _slot(1, text: 'Break'),
          _slot(2, danceId: 'd2'),
          _slot(3, danceId: 'd1'), // repeated id -> deduped
        ],
      );

      final json = buildProgramShareBundle(
        program,
        danceFor: danceFor,
        now: _now,
      );
      final archive = decodeArchive(json).archive;

      expect(archive.dances.map((d) => d.id).toSet(), {'d1', 'd2'});
      expect(archive.dances.length, 2, reason: 'repeated danceId is deduped');
      expect(archive.programs.single.id, 'p1');
      // Slot order (and the note-only slot's text) is preserved by the program.
      expect(archive.programs.single.slots.map((s) => s.position), [
        0,
        1,
        2,
        3,
      ]);
      expect(
        archive.programs.single.slots[1].text,
        'Break',
        reason: 'note-only slot carries its own text',
      );
    });

    test('skips referenced dances that cannot be resolved', () {
      final program = _program(
        slots: [
          _slot(0, danceId: 'd1'),
          _slot(1, danceId: 'missing'),
        ],
      );

      final archive = decodeArchive(
        buildProgramShareBundle(program, danceFor: danceFor),
      ).archive;

      expect(archive.dances.map((d) => d.id), ['d1']);
    });

    test('a note-only program embeds no dances', () {
      final program = _program(
        slots: [
          _slot(0, text: 'Waltz'),
          _slot(1, text: 'Break'),
        ],
      );

      final archive = decodeArchive(
        buildProgramShareBundle(program, danceFor: danceFor),
      ).archive;

      expect(archive.dances, isEmpty);
      expect(archive.programs.single.slots.length, 2);
    });

    test(
      'round-trips through the existing GenericJsonAdapter importer',
      () async {
        final program = _program(
          slots: [
            _slot(0, danceId: 'd1'),
            _slot(1, danceId: 'd2'),
            _slot(2, danceId: 'd3'),
            _slot(3, danceId: 'd2'), // duplicate must not import twice
          ],
        );

        final json = buildProgramShareBundle(
          program,
          danceFor: danceFor,
          now: _now,
        );
        final imported = await _importedDances(json);

        expect(imported.map((d) => d.id).toSet(), {'d1', 'd2', 'd3'});
        expect(imported.length, 3);
        expect(
          imported.firstWhere((d) => d.id == 'd1').title,
          'Rory O\'More',
          reason: 'dance content survives the round-trip',
        );
      },
    );
  });

  group('programShareBundleFileName', () {
    test('sanitizes illegal characters to underscores and keeps .ccshare', () {
      expect(
        programShareBundleFileName('Friday Contra: 3/9 <Town Hall>'),
        'Friday_Contra__3_9__Town_Hall_.ccshare',
      );
    });

    test('preserves safe characters', () {
      expect(
        programShareBundleFileName('spring-fling_2026.v1'),
        'spring-fling_2026.v1.ccshare',
      );
    });

    test('falls back to a stable default for an empty/all-illegal title', () {
      expect(programShareBundleFileName('   '), 'program.ccshare');
      expect(programShareBundleFileName('///'), 'program.ccshare');
    });

    test('does not allow path traversal through the title', () {
      final name = programShareBundleFileName('../../etc/passwd');
      expect(name.contains('/'), isFalse);
      expect(
        name.contains('..'),
        isTrue,
        reason: 'dots are safe; separators are not',
      );
      expect(name, endsWith('.ccshare'));
    });
  });
}
