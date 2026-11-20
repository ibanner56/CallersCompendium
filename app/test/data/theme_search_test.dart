import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/app_theme_labels_l10n.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/theme_search.dart';

void main() {
  group('ThemeSearchEntry.matches', () {
    final entry = ThemeSearchEntry(
      names: ['Rosé Pine Dawn'],
      terms: ['Light', 'purple, violet', 'muted'],
    );

    test('a name matches anywhere inside it', () {
      expect(entry.matches('pine'), isTrue);
      expect(entry.matches('ine da'), isTrue);
      expect(entry.matches('dusk'), isFalse);
    });

    test('case and accents are folded both ways', () {
      expect(entry.matches('ROSE'), isTrue);
      expect(entry.matches('rosé'), isTrue);
      expect(
        ThemeSearchEntry(names: ['Rose'], terms: const []).matches('rosé'),
        isTrue,
      );
    });

    test('a term matches only from its start', () {
      expect(entry.matches('viol'), isTrue);
      expect(entry.matches('mut'), isTrue);
      // "urple" sits inside "purple" but does not start it.
      expect(entry.matches('urple'), isFalse);
    });

    test('a comma-separated term is several words', () {
      expect(entry.matches('violet'), isTrue);
    });

    test('every word of the query must be found', () {
      expect(entry.matches('light purple'), isTrue);
      expect(entry.matches('dark purple'), isFalse);
    });

    test('punctuation and spacing in the query are set aside', () {
      expect(entry.matches('  rosé-pine,  '), isTrue);
      expect(
        ThemeSearchEntry(
          names: ['Synthwave ’84'],
          terms: const [],
        ).matches("synthwave '84"),
        isTrue,
      );
    });

    test('a query with no words matches everything', () {
      expect(entry.matches(''), isTrue);
      expect(entry.matches(' , '), isTrue);
    });
  });

  test('themeQueryIsEmpty sees through spacing and punctuation', () {
    expect(themeQueryIsEmpty(''), isTrue);
    expect(themeQueryIsEmpty('   '), isTrue);
    expect(themeQueryIsEmpty(' - , '), isTrue);
    expect(themeQueryIsEmpty('a'), isFalse);
    expect(themeQueryIsEmpty('青'), isFalse);
  });

  group('theme keywords', () {
    test('every built-in theme has at least one keyword', () {
      for (final s in AppThemeSelection.values) {
        expect(s.keywords, isNotEmpty, reason: s.name);
      }
    });

    test('every keyword finds at least one theme', () {
      final used = {for (final s in AppThemeSelection.values) ...s.keywords};
      expect(used, containsAll(AppThemeKeyword.values));
    });

    for (final locale in AppLocalizations.supportedLocales) {
      test('${locale.toLanguageTag()}: every keyword resolves to its own '
          'non-blank words', () {
        final l10n = lookupAppLocalizations(locale);
        final firstWords = <String>{};
        for (final keyword in AppThemeKeyword.values) {
          final terms = appThemeKeywordTerms(l10n, keyword);
          expect(terms, isNotEmpty, reason: keyword.name);
          for (final term in terms) {
            expect(term.trim(), term, reason: keyword.name);
            expect(term, isNotEmpty, reason: keyword.name);
          }
          // Two keywords wired to the same string would share a first word.
          expect(
            firstWords.add(terms.first),
            isTrue,
            reason: '${keyword.name} repeats another keyword\'s words',
          );
        }
      });
    }

    test('keywords are translated, not English', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      for (final keyword in AppThemeKeyword.values) {
        expect(
          appThemeKeywordTerms(ja, keyword),
          isNot(appThemeKeywordTerms(en, keyword)),
          reason: keyword.name,
        );
      }
    });

    test('the English color words find the themes that read as that color', () {
      final en = lookupAppLocalizations(const Locale('en'));
      bool tagged(AppThemeSelection s, String word) => [
        for (final k in s.keywords) ...appThemeKeywordTerms(en, k),
      ].contains(word);
      expect(tagged(AppThemeSelection.dracula, 'purple'), isTrue);
      expect(tagged(AppThemeSelection.pinkAsHeck, 'pink'), isTrue);
      expect(tagged(AppThemeSelection.everforestDark, 'green'), isTrue);
      expect(tagged(AppThemeSelection.nord, 'blue'), isTrue);
      expect(tagged(AppThemeSelection.gruvboxDark, 'warm'), isTrue);
      expect(tagged(AppThemeSelection.system, 'automatic'), isTrue);
      expect(tagged(AppThemeSelection.highContrast, 'accessible'), isTrue);
      expect(tagged(AppThemeSelection.gruvboxDark, 'purple'), isFalse);
    });
  });
}
