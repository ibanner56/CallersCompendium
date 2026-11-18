// The Settings search index and its matching (Ctrl/Cmd-F on the Settings tab).
// The shell-level routing lives in `desktop_shortcuts_test.dart`; these tests
// pin the index's coverage and the matching rules.
import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/settings/settings_search.dart';
import 'package:compendium_app/src/screens/settings/settings_section.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('settingsSearchIndex', () {
    test('has a unique id per entry', () {
      final ids = settingsSearchIndex.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('covers every Settings section', () {
      for (final section in SettingsSection.values) {
        expect(
          settingsSearchIndex.where((entry) => entry.section == section),
          isNotEmpty,
          reason:
              'SettingsSection.${section.name} has settings but no search '
              'entry, so Ctrl/Cmd-F cannot find them',
        );
      }
    });

    test('every entry resolves to a non-empty title', () {
      for (final entry in settingsSearchIndex) {
        expect(entry.label(l10n).trim(), isNotEmpty, reason: entry.id);
      }
    });
  });

  group('searchSettings', () {
    List<String> idsFor(String query) => [
      for (final entry in searchSettings(l10n, query: query)) entry.id,
    ];

    test('finds a setting by the name shown on its row', () {
      expect(idsFor('Reduce motion'), contains('general.reduceMotion'));
    });

    test('finds a setting by a synonym it does not display', () {
      expect(idsFor('dark mode'), contains('appearance.theme'));
      expect(idsFor('autosave'), contains('program.autoCommit'));
    });

    test('finds settings by their section name', () {
      final diagnostics = idsFor('Diagnostics');
      expect(diagnostics, contains('diagnostics.clearLog'));
      expect(diagnostics, contains('diagnostics.fullDetail'));
    });

    test('is case-insensitive and ignores surrounding spaces', () {
      expect(idsFor('  reduce MOTION '), contains('general.reduceMotion'));
    });

    test('an empty query lists nothing (the normal navigation stays)', () {
      expect(searchSettings(l10n, query: ''), isEmpty);
      expect(searchSettings(l10n, query: '   '), isEmpty);
    });

    test('a query with no match returns nothing', () {
      expect(searchSettings(l10n, query: 'zzzzz-not-a-setting'), isEmpty);
    });
  });
}
