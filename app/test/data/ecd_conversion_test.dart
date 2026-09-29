import 'package:compendium_app/src/data/ecd_conversion.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
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

/// Counts every `SELECT` the wrapped executor runs, so a test can prove a
/// code path never touches the database rather than merely returning the
/// same answer an unconditional query would also have produced.
class _CountingSelectInterceptor extends drift.QueryInterceptor {
  int selectCount = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selectCount++;
    return executor.runSelect(statement, args);
  }
}

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
    test('skips the database query entirely when tagIds is empty', () async {
      final counter = _CountingSelectInterceptor();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(counter),
        ),
        contraTaxonomy,
      );
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
      await repos.dances.create(_dance(id: 'd1', tagIds: const ['tag-ecd']));

      // Reset after the setup writes/reads above, so only the call under
      // test is measured.
      counter.selectCount = 0;
      final result = await findEcdConvertCandidates(repos, const {});

      expect(result, isEmpty);
      expect(
        counter.selectCount,
        0,
        reason:
            'an empty tag set must short-circuit before any SELECT runs — '
            'an implementation that instead ran search(OrFilter([])) would '
            'also return an empty list, so only a query count proves this',
      );
    });

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
      'converts every current candidate, stripping the "ECD" tag but '
      'keeping other tags, and leaves an already-ecd dance untouched',
      () async {
        final repos = openTestRepositories();
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'tag-keep', name: 'Waltz'));
        await repos.dances.create(
          _dance(id: 'd1', tagIds: const ['tag-ecd', 'tag-keep']),
        );
        await repos.dances.create(
          _dance(id: 'd2', form: DanceForm.ecd, tagIds: const ['tag-ecd']),
        );

        final converted = await convertDancesToEcd(
          repos,
          at: DateTime.utc(2026, 6, 1),
        );

        expect(converted, 1);
        final updated = await repos.dances.getById('d1');
        expect(updated!.form, DanceForm.ecd);
        expect(updated.tagIds, ['tag-keep']);
        expect(updated.updatedAt, DateTime.utc(2026, 6, 1));
        // Already DanceForm.ecd, so it was never a candidate — untouched.
        final untouched = await repos.dances.getById('d2');
        expect(untouched!.updatedAt, DateTime.utc(2026, 1, 1));
      },
    );

    test('does nothing when nothing currently matches', () async {
      final repos = openTestRepositories();

      expect(await convertDancesToEcd(repos), 0);
    });

    test('re-resolves the candidate set at write time: a dance whose "ECD" tag '
        'was removed after detection is not converted', () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
      await repos.dances.create(_dance(id: 'd1', tagIds: const ['tag-ecd']));

      // Mirrors what the on-launch prompt's pre-dialog detection pass sees.
      final detected = await findEcdConvertCandidates(
        repos,
        await ecdTagIds(repos),
      );
      expect(detected, ['d1']);

      // The tag is removed from the dance (e.g. by a concurrent sync pass)
      // while the dialog is still up, before the user confirms.
      final retagged = (await repos.dances.getById(
        'd1',
      ))!.copyWith(tagIds: const []);
      await repos.dances.update(retagged, localUserEdit: true);

      final converted = await convertDancesToEcd(repos);

      expect(converted, 0);
      expect((await repos.dances.getById('d1'))!.form, DanceForm.contra);
    });
  });
}
