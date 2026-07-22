import 'package:flutter/widgets.dart';

/// Key used to persist the user's chosen app-interface locale.
///
/// Stored as a BCP-47 language tag (e.g. `en`). Absent, empty, or an
/// unrecognized value ⇒ follow the system locale (represented as a `null`
/// [Locale] in [LocaleScope]).
const String kLocaleKey = 'app_locale';

/// Upper bound on a stored locale tag we're willing to parse. Real BCP-47 tags
/// are short; anything longer is malformed/hostile and is rejected outright so
/// a corrupted or attacker-supplied settings value can never drive unbounded
/// work (OWASP: validate untrusted persisted input).
const int _kMaxLocaleTagLength = 35;

/// Resolves a persisted settings value into a supported [Locale], or `null` to
/// follow the system locale.
///
/// **Security (OWASP):** the stored value is untrusted. This never constructs
/// an arbitrary [Locale] from the raw string — it only ever returns a locale
/// that is actually present in [supported]. A non-string, empty, over-long, or
/// unrecognized tag all resolve to `null` (system default) without throwing, so
/// a malformed or malicious persisted value can never crash startup or select
/// an unsupported locale.
///
/// Matching is tolerant of separator (`-`/`_`) and case differences. Resolution
/// is deliberately **not order-dependent** when several supported translations
/// share a language: it prefers an exact tag, then the single most specific
/// supported locale whose script/region subtags are all compatible with the
/// stored tag (so `zh-Hant-TW` resolves to `zh-Hant`, never `zh-Hans`). If two
/// compatible locales are equally specific (e.g. `zh-Hant` and `zh-TW` for
/// stored `zh-Hant-TW`) the match is ambiguous and is not resolved here. A bare
/// language-only fallback is taken only when it is unambiguous — a
/// language-only supported locale exists, or the language has exactly one
/// supported variant — otherwise it falls back to the system locale rather than
/// guessing. Structurally malformed tags (empty subtags from
/// leading/trailing/doubled separators like `en--US`, or subtags with
/// non-alphanumeric characters) are rejected outright.
Locale? localeFromStored(Object? stored, Iterable<Locale> supported) {
  if (stored is! String) return null;
  final tag = stored.trim();
  if (tag.isEmpty || tag.length > _kMaxLocaleTagLength) return null;

  final normalized = tag.replaceAll('_', '-').toLowerCase();
  // Validate BCP-47 subtag structure before any fallback. Splitting on `-`
  // must yield only non-empty, alphanumeric subtags; an empty subtag means a
  // leading/trailing/doubled separator (e.g. `en--US`, `-en`, `en-`), which is
  // malformed input, not a region we should silently strip.
  final parts = normalized.split('-');
  final validSubtag = RegExp(r'^[a-z0-9]+$');
  if (parts.any((p) => !validSubtag.hasMatch(p))) return null;
  final language = parts.first;
  final storedSubtags = parts.skip(1).toSet();

  final supportedList = supported.toList();

  // 1. Exact full-tag match against a supported locale.
  for (final locale in supportedList) {
    if (localeToTag(locale).toLowerCase() == normalized) return locale;
  }

  // Restrict to supported locales that share the language; nothing else can
  // match.
  final sameLanguage = supportedList
      .where((l) => l.languageCode.toLowerCase() == language)
      .toList();
  if (sameLanguage.isEmpty) return null;

  // 2. Script/region-compatible match: among same-language locales, keep only
  //    those whose every carried subtag also appears in the stored tag, and
  //    prefer the most specific (highest subtag count). This is independent of
  //    the order `supported` is declared in. An equal-specificity tie (e.g.
  //    stored `zh-Hant-TW` with both `zh-Hant` and `zh-TW` supported) is
  //    genuinely ambiguous, so it is NOT resolved here — it falls through to the
  //    documented language-only/system fallback rather than picking arbitrarily.
  Locale? best;
  var bestScore = -1;
  var bestTied = false;
  for (final locale in sameLanguage) {
    final subtags = <String>[
      if (locale.scriptCode?.isNotEmpty ?? false)
        locale.scriptCode!.toLowerCase(),
      if (locale.countryCode?.isNotEmpty ?? false)
        locale.countryCode!.toLowerCase(),
    ];
    if (!subtags.every(storedSubtags.contains)) continue;
    if (subtags.length > bestScore) {
      bestScore = subtags.length;
      best = locale;
      bestTied = false;
    } else if (subtags.length == bestScore) {
      bestTied = true;
    }
  }
  if (best != null && !bestTied) return best;

  // 3. Language-only fallback, but only when unambiguous: a bare language-only
  //    locale exists, or the language has a single supported variant. When
  //    multiple script/region variants exist and none is compatible, guessing
  //    would be arbitrary — fall back to the system locale instead.
  final languageOnly = sameLanguage.where(
    (l) => (l.scriptCode?.isEmpty ?? true) && (l.countryCode?.isEmpty ?? true),
  );
  if (languageOnly.isNotEmpty) return languageOnly.first;
  if (sameLanguage.length == 1) return sameLanguage.first;
  return null;
}

/// The BCP-47 language tag persisted for [locale], or the empty string for
/// `null` (follow the system locale). The empty string is a benign sentinel:
/// [localeFromStored] resolves it back to `null`.
String localeToTag(Locale? locale) {
  if (locale == null) return '';
  final buffer = StringBuffer(locale.languageCode);
  if (locale.scriptCode != null && locale.scriptCode!.isNotEmpty) {
    buffer.write('-${locale.scriptCode}');
  }
  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
    buffer.write('-${locale.countryCode}');
  }
  return buffer.toString();
}

/// The endonym (native name) shown for [locale] in the language selector.
///
/// Language names are proper nouns that read best in their own language rather
/// than being re-translated per UI locale, so they live here rather than in the
/// ARB.
///
/// Script/region variants that share a language (e.g. Simplified vs Traditional
/// Chinese, Brazilian vs European Portuguese) must stay distinguishable, so an
/// exact full-tag endonym is preferred first. Failing that, the language-only
/// endonym is qualified with the distinguishing script/region subtag so two
/// variants never collapse to the same label. Unknown locales fall back to the
/// BCP-47 tag, so a newly dropped-in `app_<locale>.arb` still shows something
/// sensible with no code change.
String nativeLanguageName(Locale locale) {
  const fullTagNames = <String, String>{
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
    'pt-BR': 'Português (Brasil)',
    'pt-PT': 'Português (Portugal)',
    'en-GB': 'English (UK)',
    'en-US': 'English (US)',
  };
  const languageNames = <String, String>{
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
    'nl': 'Nederlands',
    'sv': 'Svenska',
    'da': 'Dansk',
    'nb': 'Norsk bokmål',
    'fi': 'Suomi',
    'pl': 'Polski',
    'cs': 'Čeština',
    'ja': '日本語',
    'zh': '中文',
  };

  final tag = localeToTag(locale);
  // 1. Exact full-tag endonym (keeps variants distinct).
  final lowerTag = tag.toLowerCase();
  for (final entry in fullTagNames.entries) {
    if (entry.key.toLowerCase() == lowerTag) return entry.value;
  }
  // 2. Language-only endonym, qualified by *all* distinguishing subtags when
  //    the locale carries a script and/or region so variants never collide
  //    (e.g. `de-Latn-DE` vs `de-Latn-CH` -> "Deutsch (Latn-DE)" vs
  //    "Deutsch (Latn-CH)").
  final base = languageNames[locale.languageCode.toLowerCase()];
  if (base != null) {
    final subtags = <String>[
      if (locale.scriptCode?.isNotEmpty ?? false) locale.scriptCode!,
      if (locale.countryCode?.isNotEmpty ?? false) locale.countryCode!,
    ];
    return subtags.isEmpty ? base : '$base (${subtags.join('-')})';
  }
  // 3. Unknown language: the raw tag is the most honest label.
  return tag;
}

/// Exposes the user's chosen app locale as a live [ValueNotifier] to the widget
/// tree, mirroring [DateFormatScope]/[AppThemeScope]. A `null` value means
/// "follow the system locale".
///
/// Descendants that call [LocaleScope.of] rebuild when the locale changes; use
/// [LocaleScope.notifierOf] to *change* it (e.g. from the Settings screen).
/// Changing the notifier drives `MaterialApp.locale` (wired in `main.dart`), so
/// the whole app re-renders in the selected language live.
class LocaleScope extends InheritedNotifier<ValueNotifier<Locale?>> {
  const LocaleScope({
    super.key,
    required ValueNotifier<Locale?> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The active locale override, or `null` to follow the system locale.
  /// Registers a rebuild dependency. Also returns `null` when there is no
  /// [LocaleScope] ancestor, which is treated identically ("no override").
  static Locale? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    return scope?.notifier?.value;
  }

  /// Returns the underlying notifier so callers can change the locale. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<Locale?> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LocaleScope>();
    if (scope == null) {
      throw FlutterError(
        'LocaleScope.notifierOf() called with a context that has no '
        'LocaleScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
