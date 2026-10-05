import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Pins [syncBookkeepingTables], the set the app uses to ignore the sync
/// engine's own writes when deciding whether to schedule a pass. It is derived
/// from the registry, so a registry change that adds or drops a bookkeeping
/// table must be a deliberate edit here too.
void main() {
  test('the sync bookkeeping tables are exactly the six registry tables', () {
    expect(syncBookkeepingTables, {
      'baseline_state',
      'baseline_entries',
      'id_aliases',
      'pending_deletions',
      'published_records',
      'review_queue',
    });
  });

  test('content and settings tables are never bookkeeping', () {
    expect(syncBookkeepingTables, isNot(contains('dances')));
    expect(syncBookkeepingTables, isNot(contains('settings')));
  });
}
