import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  test(
    'CompendiumRepositories wires every repository to the same db',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);

      // Smoke-test that every repository is live and shares the same
      // underlying connection (a write through one is visible via another).
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: 'chestnut'));
      // ignore: unused_result
      await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'origin',
          label: 'Origin',
          type: CustomFieldType.text,
        ),
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Chase the Squirrel',
          authorIds: const ['c1'],
          tagIds: const ['t1'],
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'New England')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Spring Dance',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await repos.settings.set('active_dialect', 'larksRobins');

      expect((await repos.dances.getById('d1'))!.tagIds, ['t1']);
      expect((await repos.programs.getById('p1'))!.slots.single.danceId, 'd1');
      expect(await repos.settings.get('active_dialect'), 'larksRobins');
    },
  );
}
