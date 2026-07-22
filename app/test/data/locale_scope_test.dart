import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/locale_scope.dart';

void main() {
  // The app currently ships English only; validation must resolve against
  // whatever the running app actually supports, so tests pin an explicit set.
  const supported = <Locale>[Locale('en')];

  group('localeFromStored (OWASP: validate untrusted persisted input)', () {
    test('resolves an exact supported tag', () {
      expect(localeFromStored('en', supported), const Locale('en'));
    });

    test('is tolerant of case and separator differences', () {
      expect(localeFromStored('EN', supported), const Locale('en'));
      expect(localeFromStored('en_US', supported), const Locale('en'));
      expect(localeFromStored('en-GB', supported), const Locale('en'));
    });

    test('returns null (system) for a supported-language-not-found tag', () {
      expect(localeFromStored('fr', supported), isNull);
      expect(localeFromStored('zz', supported), isNull);
    });

    test('returns null for empty/whitespace and never throws', () {
      expect(localeFromStored('', supported), isNull);
      expect(localeFromStored('   ', supported), isNull);
    });

    test('rejects a non-string persisted value', () {
      expect(localeFromStored(42, supported), isNull);
      expect(localeFromStored(<String>['en'], supported), isNull);
      expect(localeFromStored(null, supported), isNull);
    });

    test('rejects an absurdly long tag outright (bounded work)', () {
      final hostile = 'en-${'x' * 100}';
      expect(localeFromStored(hostile, supported), isNull);
    });

    test('matches a full region tag when the app supports that exact tag', () {
      const withRegion = <Locale>[Locale('en'), Locale('en', 'US')];
      expect(localeFromStored('en-US', withRegion), const Locale('en', 'US'));
    });

    test('rejects a structurally malformed tag even when it shares a '
        'supported language', () {
      // Empty subtags (doubled/leading/trailing separators) are garbage, not
      // a region we should strip down to the supported language `en`.
      expect(localeFromStored('en--US', supported), isNull);
      expect(localeFromStored('en-', supported), isNull);
      expect(localeFromStored('-en', supported), isNull);
      expect(localeFromStored('en__US', supported), isNull);
      // Non-alphanumeric subtags are likewise rejected.
      expect(localeFromStored('en-US!', supported), isNull);
      expect(localeFromStored('en.US', supported), isNull);
    });

    test('resolves script/region variants without order dependence', () {
      const hans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      // A stored `zh-Hant-TW` must resolve to Traditional regardless of which
      // variant is declared first.
      expect(localeFromStored('zh-Hant-TW', [hans, hant]), hant);
      expect(localeFromStored('zh-Hant-TW', [hant, hans]), hant);
      expect(localeFromStored('zh_Hant_TW', [hans, hant]), hant);
      expect(localeFromStored('zh-Hans-CN', [hans, hant]), hans);
    });

    test('falls back to system for an ambiguous language-only tag', () {
      const hans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      // Bare `zh` matches no specific variant and there is no language-only
      // supported locale, so guessing would be arbitrary — fall back to system.
      expect(localeFromStored('zh', [hans, hant]), isNull);
    });

    test('takes a unique same-language variant as the fallback', () {
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      // Only one `zh` variant is supported, so a bare `zh` is unambiguous.
      expect(localeFromStored('zh', const [Locale('en'), hant]), hant);
    });

    test('treats an equal-specificity compatible tie as ambiguous', () {
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      const zhTw = Locale('zh', 'TW');
      // Stored `zh-Hant-TW` is compatible with BOTH `zh-Hant` (score 1, script)
      // and `zh-TW` (score 1, region). Neither is more specific, so the result
      // is order-independent: ambiguous -> system fallback, not a coin flip.
      expect(localeFromStored('zh-Hant-TW', const [hant, zhTw]), isNull);
      expect(localeFromStored('zh-Hant-TW', const [zhTw, hant]), isNull);
    });

    test('prefers a language-only locale over a specific sibling', () {
      const en = Locale('en');
      const enUS = Locale('en', 'US');
      // `en-GB` has no exact match; the bare `en` is the compatible, most
      // sensible fallback rather than the region-specific `en-US`.
      expect(localeFromStored('en-GB', const [en, enUS]), en);
    });
  });

  group('localeToTag', () {
    test('maps null to the empty (follow-system) sentinel', () {
      expect(localeToTag(null), '');
    });

    test('serializes language, script, and region', () {
      expect(localeToTag(const Locale('en')), 'en');
      expect(localeToTag(const Locale('en', 'US')), 'en-US');
      expect(
        localeToTag(
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'CN',
          ),
        ),
        'zh-Hans-CN',
      );
    });

    test('round-trips through localeFromStored', () {
      final tag = localeToTag(const Locale('en'));
      expect(localeFromStored(tag, supported), const Locale('en'));
    });
  });

  group('nativeLanguageName', () {
    test('returns the endonym for known languages', () {
      expect(nativeLanguageName(const Locale('en')), 'English');
      expect(nativeLanguageName(const Locale('fr')), 'Français');
      expect(nativeLanguageName(const Locale('ja')), '日本語');
    });

    test('distinguishes script/region variants that share a language', () {
      const zhHans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      const zhHant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      expect(nativeLanguageName(zhHans), '简体中文');
      expect(nativeLanguageName(zhHant), '繁體中文');
      expect(nativeLanguageName(zhHans), isNot(nativeLanguageName(zhHant)));

      expect(
        nativeLanguageName(const Locale('pt', 'BR')),
        'Português (Brasil)',
      );
      expect(
        nativeLanguageName(const Locale('pt', 'PT')),
        'Português (Portugal)',
      );
    });

    test('qualifies an unmapped variant so it stays distinguishable', () {
      // No explicit full-tag entry: fall back to the language endonym qualified
      // by the distinguishing subtag rather than collapsing both to `Deutsch`.
      final deAt = nativeLanguageName(const Locale('de', 'AT'));
      final deCh = nativeLanguageName(const Locale('de', 'CH'));
      expect(deAt, 'Deutsch (AT)');
      expect(deCh, 'Deutsch (CH)');
      expect(deAt, isNot(deCh));
    });

    test('keeps script AND region when a variant carries both', () {
      // Both a script and a region must appear in the qualifier; discarding the
      // region would collapse these two distinct locales to the same label.
      const deLatnDe = Locale.fromSubtags(
        languageCode: 'de',
        scriptCode: 'Latn',
        countryCode: 'DE',
      );
      const deLatnCh = Locale.fromSubtags(
        languageCode: 'de',
        scriptCode: 'Latn',
        countryCode: 'CH',
      );
      expect(nativeLanguageName(deLatnDe), 'Deutsch (Latn-DE)');
      expect(nativeLanguageName(deLatnCh), 'Deutsch (Latn-CH)');
      expect(nativeLanguageName(deLatnDe), isNot(nativeLanguageName(deLatnCh)));
    });

    test('falls back to the tag for an unmapped language', () {
      expect(nativeLanguageName(const Locale('zz')), 'zz');
    });
  });
}
