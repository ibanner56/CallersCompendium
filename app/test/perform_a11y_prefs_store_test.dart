import 'package:compendium_app/src/screens/perform_a11y_prefs.dart';
import 'package:compendium_app/src/screens/perform_card.dart'
    show kPerformDefaultScale, kPerformMinScale;
import 'package:compendium_app/src/screens/settings_screen.dart'
    show kPerformCanonicalViewKey, kPerformStageModeKey, kPerformTextScaleKey;
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

void main() {
  group('PerformA11yPrefsStore', () {
    test('load returns defaults when the store is empty', () async {
      final store = PerformA11yPrefsStore(openTestRepositories().settings);
      expect(await store.load(), PerformA11yPrefs.defaults);
    });

    test('load restores persisted valid values', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kPerformTextScaleKey, 2.4);
      await repos.settings.set(kPerformStageModeKey, false);
      await repos.settings.set(kPerformCanonicalViewKey, true);

      final prefs = await PerformA11yPrefsStore(repos.settings).load();

      expect(prefs.textScale, 2.4);
      expect(prefs.stageMode, isFalse);
      expect(prefs.canonicalView, isTrue);
    });

    test('save methods round-trip through the store', () async {
      final repos = openTestRepositories();
      final store = PerformA11yPrefsStore(repos.settings);

      await store.saveTextScale(2.6);
      await store.saveStageMode(false);
      await store.saveCanonicalView(true);

      final prefs = await store.load();
      expect(prefs.textScale, 2.6);
      expect(prefs.stageMode, isFalse);
      expect(prefs.canonicalView, isTrue);
    });

    test('load coerces an integer text scale to a double', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kPerformTextScaleKey, 3);

      final prefs = await PerformA11yPrefsStore(repos.settings).load();

      expect(prefs.textScale, 3.0);
    });

    test(
      'load rejects a below-minimum text scale and uses the default',
      () async {
        final repos = openTestRepositories();
        await repos.settings.set(kPerformTextScaleKey, kPerformMinScale - 0.5);

        final prefs = await PerformA11yPrefsStore(repos.settings).load();

        expect(prefs.textScale, kPerformDefaultScale);
      },
    );

    test(
      'load rejects a non-numeric text scale and uses the default',
      () async {
        final repos = openTestRepositories();
        await repos.settings.set(kPerformTextScaleKey, 'huge');

        final prefs = await PerformA11yPrefsStore(repos.settings).load();

        expect(prefs.textScale, kPerformDefaultScale);
      },
    );

    test('load rejects non-bool toggle values and uses defaults', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kPerformStageModeKey, 1);
      await repos.settings.set(kPerformCanonicalViewKey, 'yes');

      final prefs = await PerformA11yPrefsStore(repos.settings).load();

      expect(prefs.stageMode, PerformA11yPrefs.defaults.stageMode);
      expect(prefs.canonicalView, PerformA11yPrefs.defaults.canonicalView);
    });
  });
}
