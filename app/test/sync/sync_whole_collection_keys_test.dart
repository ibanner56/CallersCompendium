import 'package:compendium_app/src/data/backup_document.dart'
    show kMaxCustomDialects;
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the merge routes exactly the keys the app stores whole collections '
      'under', () {
    // The merge sends a changed/changed conflict on these keys to the user
    // instead of last-writer-wins, because one value is a whole set. The set
    // lives in core, the keys beside the app controllers that own them; a
    // renamed or added collection key that missed core would silently fall
    // back to discarding one device's whole set.
    expect(syncWholeCollectionSettingKeys, {
      kCustomDialectsKey,
      kCustomThemesKey,
      kShorthandMappingsKey,
      kWalkthroughSnippetsKey,
    });
  });

  test('a combined dialect list is held to the same limit backups keep', () {
    // Combine both refuses a dialect list longer than core's limit; a longer
    // one would be cut short the next time a backup restores it.
    expect(syncMaxCustomDialects, kMaxCustomDialects);
    expect(syncCollectionLimit('custom_dialects'), kMaxCustomDialects);
  });
}
