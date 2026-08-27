import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

Dance _dance(String id) => Dance(
  id: id,
  title: 'Dance $id',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Choreographer _choreographer(String id) => Choreographer(id: id, name: 'C $id');

Program _program(String id, {List<ProgramSlot> slots = const []}) => Program(
  id: id,
  title: 'Program $id',
  slots: slots,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Venue _venue(String id) => Venue(id: id, name: 'Venue $id');

void main() {
  group('compendiumArchiveEntityCount', () {
    test('is zero for an empty archive', () {
      expect(
        compendiumArchiveEntityCount(
          CompendiumArchive(exportedAt: DateTime.utc(2026, 1, 1)),
        ),
        0,
      );
    });

    test('sums dances, choreographers, programs and venues', () {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 1, 1),
        dances: [_dance('d1'), _dance('d2'), _dance('d3')],
        choreographers: [_choreographer('c1'), _choreographer('c2')],
        programs: [_program('p1')],
        venues: [_venue('v1'), _venue('v2'), _venue('v3'), _venue('v4')],
      );
      // 3 dances + 2 choreographers + 1 program + 4 venues.
      expect(compendiumArchiveEntityCount(archive), 10);
    });

    test('does not count program slots separately', () {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 1, 1),
        programs: [
          _program(
            'p1',
            slots: [
              ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
              ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
            ],
          ),
        ],
      );
      // One program, its two slots ride inside it.
      expect(compendiumArchiveEntityCount(archive), 1);
    });

    test('counts committed metadata (sources, custom fields, tags)', () {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 1, 1),
        dances: [_dance('d1')],
        publishedSources: [PublishedSource(id: 'ps1', title: 'Zesty Contras')],
        customFields: [
          CustomFieldDef(
            id: 'cf1',
            key: 'tempo',
            label: 'Tempo',
            type: CustomFieldType.text,
          ),
        ],
        tags: [Tag(id: 't1', name: 'reel')],
      );
      // One dance plus each committed metadata entity.
      expect(compendiumArchiveEntityCount(archive), 4);
    });
  });
}
