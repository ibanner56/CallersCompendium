import 'package:flutter/widgets.dart';

import 'package:compendium_app/l10n/app_localizations.dart';

/// Localizations wiring for widget tests that render l10n-dependent widgets
/// (the AppShell nav labels, the Settings screen, the Language & region
/// section). Mirrors what `main.dart` installs on the real `MaterialApp`, so a
/// test's `MaterialApp` can resolve `AppLocalizations.of(context)` without
/// wiring the delegates by hand.
///
/// Usage:
/// ```dart
/// MaterialApp(
///   localizationsDelegates: testLocalizationsDelegates,
///   supportedLocales: testSupportedLocales,
///   home: ...,
/// );
/// ```
const List<LocalizationsDelegate<dynamic>> testLocalizationsDelegates =
    AppLocalizations.localizationsDelegates;

/// The locales the app ships translations for (English only, for now).
const List<Locale> testSupportedLocales = AppLocalizations.supportedLocales;
