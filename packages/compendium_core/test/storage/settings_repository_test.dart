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

  test('keeps colliding normalized object keys and records them', () async {
    // §4.1: "a user's edit is never rejected to satisfy a normalisation
    // rule". Until #1348 this threw [ShareableJsonKeyCollision] out of `set`
    // and the save simply failed — while the one-time pass, handed the
    // identical condition, had always skipped the value and recorded it.
    final value = {'café': 'first', 'café': 'second'};

    await repo.set('custom_dialects', value);

    expect(
      await repo.get('custom_dialects'),
      value,
      reason:
          'both entries survive; normalizing key by key would drop whichever '
          'was written second, which is the silent loss §4.1 skips to avoid',
    );
    final skip = await db
        .customSelect(
          'SELECT table_name, column_name, record_id FROM normalisation_skips',
        )
        .getSingle();
    expect(skip.data, {
      'table_name': 'settings',
      'column_name': 'value_json',
      'record_id': 'custom_dialects',
    });
  });

  test('a kept colliding value is still sanitised', () async {
    // §4.1 carves out COMPOSITION, not §4.6's sanitiser — which binds every
    // write path with no carve-out at all. Storing the caller's object verbatim
    // would let a normalisation collision persist a zero-width space under a
    // rule that says nothing about invisible characters.
    await repo.set('custom_dialects', {'café': 'a​b', 'café': 'c​d'});

    expect(await repo.get('custom_dialects'), {'café': 'ab', 'café': 'cd'});
    expect(
      (await db.customSelect('SELECT 1 FROM normalisation_skips').get()),
      hasLength(1),
    );
  });

  test('two keys that collide under the sanitiser alone still raise', () async {
    // Not a normalisation collision: no sanitised form of this object keeps
    // both entries, so there is nothing for §4.1's carve-out to store.
    // Raised before the write is scheduled, so the closure form is required:
    // `set` is not `async`, and a synchronous throw never becomes a Future.
    expect(
      () => repo.set('custom_dialects', {'ab': 1, 'a​b': 2}),
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
