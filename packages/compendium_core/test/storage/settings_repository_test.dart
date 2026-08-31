import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = openTestDatabase();
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('round-trips a string value', () async {
    await repo.set('active_dialect', 'larksRobins');
    expect(await repo.get('active_dialect'), 'larksRobins');
  });

  test('round-trips a map value', () async {
    await repo.set('source_urls', {'callersbox': 'https://example.com'});
    expect(await repo.get('source_urls'), {
      'callersbox': 'https://example.com',
    });
  });

  test('normalizes recursively for shareable settings', () async {
    await repo.set('custom_dialects', {
      'cafe\u0301': 'line\u200B\nnext',
      'nested': ['cafe\u0301'],
    });
    expect(await repo.get('custom_dialects'), {
      'café': 'line\nnext',
      'nested': ['café'],
    });
  });

  test('rejects colliding normalized object keys without writing', () async {
    expect(
      () => repo.set('custom_dialects', {
        'café': 'first',
        'cafe\u0301': 'second',
      }),
      throwsA(isA<ShareableJsonKeyCollision>()),
    );
    expect(await repo.get('custom_dialects'), isNull);
  });

  test('returns null for an unset key', () async {
    expect(await repo.get('nope'), isNull);
    expect(await repo.contains('nope'), isFalse);
  });

  test('set overwrites an existing key', () async {
    await repo.set('k', 'first');
    await repo.set('k', 'second');
    expect(await repo.get('k'), 'second');
  });

  test('remove deletes a key', () async {
    await repo.set('k', 'v');
    await repo.remove('k');
    expect(await repo.contains('k'), isFalse);
  });

  test('all returns every key decoded', () async {
    await repo.set('a', 1);
    await repo.set('b', true);
    expect(await repo.all(), {'a': 1, 'b': true});
  });
}
