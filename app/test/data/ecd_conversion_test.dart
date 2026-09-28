import 'package:compendium_app/src/data/ecd_conversion.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Dance _dance({
  required String id,
  DanceForm form = DanceForm.contra,
  List<String> tagIds = const [],
  DateTime? deletedAt,
}) => Dance(
  id: id,
  title: 'Dance $id',
  form: form,
  tagIds: tagIds,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  deletedAt: deletedAt,
);

void main() {
  group('ecdTagIds', () {
    test('matches a live tag named "ECD" case-insensitively', () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ecd'));
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-other', name: 'Waltz'));

      expect(await ecdTagIds(repos), {'tag-ecd'});
    });

    test('is empty when no tag is named "ECD"', () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-other', name: 'Waltz'));

      expect(await ecdTagIds(repos), isEmpty);
    });

    test('ignores a tombstoned "ECD" tag', () async {
      final repos = openTestRepositories();
      final id = await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
      await repos.tags.delete(id);

      expect(await ecdTagIds(repos), isEmpty);
    });
  });

  group('findEcdConvertCandidates', () {
    test(
      'returns no candidates and skips the query when tagIds is empty',
      () async {
        final repos = openTestRepositories();
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
        await repos.dances.create(_dance(id: 'd1', tagIds: const ['tag-ecd']));

        expect(await findEcdConvertCandidates(repos, const {}), isEmpty);
      },
    );

    test('matches only non-ecd dances carrying a given tag', () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-other', name: 'Waltz'));
      await repos.dances.create(
        _dance(id: 'contra-tagged', tagIds: const ['tag-ecd']),
      );
      await repos.dances.create(
        _dance(
          id: 'square-tagged',
          form: DanceForm.square,
          tagIds: const ['tag-ecd'],
        ),
      );
      await repos.dances.create(
        _dance(
          id: 'already-ecd',
          form: DanceForm.ecd,
          tagIds: const ['tag-ecd'],
        ),
      );
      await repos.dances.create(
        _dance(id: 'untagged', tagIds: const ['tag-other']),
      );

      final candidates = await findEcdConvertCandidates(repos, {'tag-ecd'});
      expect(candidates.toSet(), {'contra-tagged', 'square-tagged'});
    });

    test('excludes a soft-deleted dance', () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
      await repos.dances.create(
        _dance(
          id: 'deleted',
          tagIds: const ['tag-ecd'],
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      expect(await findEcdConvertCandidates(repos, {'tag-ecd'}), isEmpty);
    });
  });

  group('convertDancesToEcd', () {
    test(
      'sets the form and strips only the given tags, keeping the rest',
      () async {
        final repos = openTestRepositories();
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'tag-keep', name: 'Waltz'));
        await repos.dances.create(
          _dance(id: 'd1', tagIds: const ['tag-ecd', 'tag-keep']),
        );

        final converted = await convertDancesToEcd(
          repos,
          const ['d1'],
          const {'tag-ecd'},
          at: DateTime.utc(2026, 6, 1),
        );

        expect(converted, 1);
        final updated = await repos.dances.getById('d1');
        expect(updated!.form, DanceForm.ecd);
        expect(updated.tagIds, ['tag-keep']);
        expect(updated.updatedAt, DateTime.utc(2026, 6, 1));
      },
    );

    test('skips a dance id that no longer exists', () async {
      final repos = openTestRepositories();

      final converted = await convertDancesToEcd(
        repos,
        const ['missing'],
        const {'tag-ecd'},
      );

      expect(converted, 0);
    });
  });
}
