import 'package:compendium_app/src/data/default_import_tags.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  group('default import tag codec (#1476)', () {
    test('round-trips, dropping blanks and duplicates, keeping order', () {
      final encoded = encodeDefaultImportTagNames(['b', ' ', 'a', 'b', ' a ']);
      expect(tryDecodeDefaultImportTagNames(encoded), ['b', 'a']);
    });

    test('rejects anything that is not a JSON list of non-blank strings', () {
      for (final bad in <Object?>[
        null,
        42,
        <String>['a'],
        'nope',
        '{"a":1}',
        '[1]',
        '[""]',
        '["a", null]',
      ]) {
        expect(tryDecodeDefaultImportTagNames(bad), isNull, reason: '$bad');
      }
    });

    test('rejects a list longer than the cap', () {
      final tooMany = [for (var i = 0; i <= kMaxDefaultImportTags; i++) 'id$i'];
      expect(
        tryDecodeDefaultImportTagNames(
          '[${tooMany.map((e) => '"$e"').join(',')}]',
        ),
        isNull,
      );
    });
  });

  group('resolveDefaultImportTagIds', () {
    late CompendiumRepositories repos;

    setUp(() => repos = openTestRepositories());

    Future<void> store(Object value) =>
        repos.settings.set(kDefaultImportTagNamesKey, value);

    test('is empty when the setting was never written', () async {
      expect(await resolveDefaultImportTagIds(repos), isEmpty);
    });

    test('returns the ids of live tags in stored name order', () async {
      final a = await repos.tags.upsert(Tag(id: 'a', name: 'A'));
      final b = await repos.tags.upsert(Tag(id: 'b', name: 'B'));
      await store(encodeDefaultImportTagNames(['B', 'A']));
      expect(await resolveDefaultImportTagIds(repos), [b, a]);
    });

    test('drops a deleted tag and a name that never existed', () async {
      final a = await repos.tags.upsert(Tag(id: 'a', name: 'A'));
      final gone = await repos.tags.upsert(Tag(id: 'gone', name: 'Gone'));
      await store(encodeDefaultImportTagNames(['Gone', 'Ghost', 'A']));
      await repos.tags.delete(gone);
      expect(await resolveDefaultImportTagIds(repos), [a]);
    });

    test('follows a tag that was re-identified under the same name '
        '(sync / merge-restore remap)', () async {
      // The stored value is never rewritten when a tag's id changes, so it
      // must resolve through the name, which both mechanisms preserve.
      final original = await repos.tags.upsert(Tag(id: 'old', name: 'No card'));
      await store(encodeDefaultImportTagNames(['No card']));
      await repos.tags.delete(original, permanent: true);
      final reissued = await repos.tags.upsert(Tag(id: 'new', name: 'No card'));
      expect(reissued, 'new');
      expect(await resolveDefaultImportTagIds(repos), ['new']);
    });

    test(
      'a malformed stored value means no tags rather than an error',
      () async {
        await store('not json');
        expect(await resolveDefaultImportTagIds(repos), isEmpty);
      },
    );
  });
}
