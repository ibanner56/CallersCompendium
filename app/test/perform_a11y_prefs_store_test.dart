import 'package:compendium_app/src/screens/perform_a11y_prefs.dart';
import 'package:compendium_app/src/data/perform_text_scale.dart'
    show kPerformDefaultScale, kPerformMinScale;
import 'package:compendium_app/src/screens/settings_screen.dart'
    show kPerformStageModeKey, kPerformTextScaleKey;
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

      final prefs = await PerformA11yPrefsStore(repos.settings).load();

      expect(prefs.textScale, 2.4);
      expect(prefs.stageMode, isFalse);
    });

    test('save methods round-trip through the store', () async {
      final repos = openTestRepositories();
      final store = PerformA11yPrefsStore(repos.settings);

      await store.saveTextScale(2.6);
      await store.saveStageMode(false);

      final prefs = await store.load();
      expect(prefs.textScale, 2.6);
      expect(prefs.stageMode, isFalse);
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

    test('load rejects a non-bool toggle value and uses the default', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kPerformStageModeKey, 1);

      final prefs = await PerformA11yPrefsStore(repos.settings).load();

      expect(prefs.stageMode, PerformA11yPrefs.defaults.stageMode);
    });
  });
}
