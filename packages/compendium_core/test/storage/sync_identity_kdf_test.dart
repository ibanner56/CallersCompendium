import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Pins the production PBKDF2 count. The sync-heavy suites that mark identities
/// used (`sync_storage_test.dart`, `sync_coordinator_test.dart`) lower
/// [syncIdentityKdfIterations]; this file sets no suite-wide override, so its
/// first test derives at the real 600,000. Its mismatch test lowers the
/// override for that one test only and restores it. (`sync_isolate_test.dart`
/// also runs the real derivation, because its pass runs in a spawned isolate.)
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('the production default is 600,000 iterations', () async {
    expect(syncIdentityKdfIterations, 600000);

    await CompendiumSyncStorage(repositories).markSyncUsed('sync-a');

    final marker = await repositories.settings.get(syncLastUsedFingerprintKey);
    final entry = ((marker! as List).single as Map).cast<String, Object?>();
    expect(entry['algorithm'], 'pbkdf2-sha256');
    expect(entry['iterations'], 600000);
  });

  test('a marker written at another iteration count is skipped, not '
      'validated', () async {
    final production = syncIdentityKdfIterations;
    addTearDown(() => syncIdentityKdfIterations = production);

    syncIdentityKdfIterations = 1000;
    await CompendiumSyncStorage(repositories).markSyncUsed('sync-a');

    // Back at the production count the lowered marker no longer matches.
    syncIdentityKdfIterations = production;
    final snapshot = await CompendiumSyncStorage(
      repositories,
    ).snapshot(syncId: 'sync-a');
    expect(snapshot.previouslyUsed, isFalse);
  });

  test('the derivation loop runs the overridden count', () async {
    final production = syncIdentityKdfIterations;
    addTearDown(() => syncIdentityKdfIterations = production);
    syncIdentityKdfIterations = 1000;

    // An independent PBKDF2-HMAC-SHA256 (one 32-byte block) at 1000 rounds. A
    // marker seeded with it only validates if the loop ran exactly 1000
    // rounds; a loop still bound to 600,000 derives different bytes.
    const syncId = 'alpha-beta-gamma-delta';
    final salt = List<int>.generate(16, (i) => i + 1);
    final hmac = Hmac(sha256, utf8.encode(normalizeSyncId(syncId)));
    var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final derived = List<int>.from(block);
    for (var round = 1; round < 1000; round++) {
      block = hmac.convert(block).bytes;
      for (var k = 0; k < derived.length; k++) {
        derived[k] ^= block[k];
      }
    }
    String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
    await repositories.settings.set(syncLastUsedFingerprintKey, [
      {
        'algorithm': 'pbkdf2-sha256',
        'iterations': 1000,
        'salt': b64(salt),
        'verifier': b64(derived),
      },
    ]);

    final snapshot = await CompendiumSyncStorage(
      repositories,
    ).snapshot(syncId: syncId);
    expect(snapshot.previouslyUsed, isTrue);
  });
}
