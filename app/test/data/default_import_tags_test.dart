import 'package:compendium_app/src/data/default_import_tags.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  group('default import tag codec (#1476)', () {
    test('round-trips, dropping blanks and duplicates, keeping order', () {
      final encoded = encodeDefaultImportTagIds(['b', ' ', 'a', 'b', ' a ']);
      expect(tryDecodeDefaultImportTagIds(encoded), ['b', 'a']);
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
        expect(tryDecodeDefaultImportTagIds(bad), isNull, reason: '$bad');
      }
    });

    test('rejects a list longer than the cap', () {
      final tooMany = [for (var i = 0; i <= kMaxDefaultImportTags; i++) 'id$i'];
      expect(
        tryDecodeDefaultImportTagIds(
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
        repos.settings.set(kDefaultImportTagIdsKey, value);

    test('is empty when the setting was never written', () async {
      expect(await resolveDefaultImportTagIds(repos), isEmpty);
    });

    test('returns live tag ids in stored order', () async {
      final a = await repos.tags.upsert(Tag(id: 'a', name: 'A'));
      final b = await repos.tags.upsert(Tag(id: 'b', name: 'B'));
      await store(encodeDefaultImportTagIds([b, a]));
      expect(await resolveDefaultImportTagIds(repos), [b, a]);
    });

    test('drops a deleted tag and an id that never existed', () async {
      final a = await repos.tags.upsert(Tag(id: 'a', name: 'A'));
      final gone = await repos.tags.upsert(Tag(id: 'gone', name: 'Gone'));
      await store(encodeDefaultImportTagIds([gone, 'ghost', a]));
      await repos.tags.delete(gone);
      expect(await resolveDefaultImportTagIds(repos), [a]);
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
