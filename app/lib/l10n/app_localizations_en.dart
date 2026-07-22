// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Caller\'s Compendium';

  @override
  String get navCollection => 'Collection';

  @override
  String get navPrograms => 'Programs';

  @override
  String get navSettings => 'Settings';

  @override
  String get navGuide => 'Guide';

  @override
  String get navGuideTooltip => 'User guide';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get commonSystemDefault => 'System default';

  @override
  String get commonComingSoon => 'Coming soon';

  @override
  String get settingsLanguageRegionTitle => 'Language & region';

  @override
  String get settingsRegionalFormatsHeader => 'Formats';

  @override
  String get settingsRegionalLanguageHeader => 'Language';

  @override
  String get settingsDateFormatTitle => 'Date format';

  @override
  String settingsDateFormatSubtitle(String example) {
    return 'How program event dates appear. Example: $example';
  }

  @override
  String get settingsDateFormatYmd => 'Year-month-day (2026-07-15)';

  @override
  String get settingsDateFormatDmy => 'Day/month/year (15/07/2026)';

  @override
  String get settingsDateFormatMdy => 'Month/day/year (07/15/2026)';

  @override
  String get settingsFirstDayOfWeekTitle => 'First day of week';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Which day the week starts on in the app\'s date views. Coming in a future update.';

  @override
  String get settingsAppLanguageTitle => 'App language';

  @override
  String get settingsAppLanguageSubtitle =>
      'Choose the language of the app\'s interface.';
}
