import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Runs the REAL PBKDF2 cost. No other sync suite does: they lower
/// [syncIdentityKdfIterations], so this file is where the production value is
/// pinned. It must never assign the override.
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
}
