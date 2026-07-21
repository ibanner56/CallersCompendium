import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The application's name. Shown as the window/task-switcher title via MaterialApp.onGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Caller\'s Compendium'**
  String get appTitle;

  /// Bottom/rail navigation label for the dance collection destination.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get navCollection;

  /// Bottom/rail navigation label for the programs destination.
  ///
  /// In en, this message translates to:
  /// **'Programs'**
  String get navPrograms;

  /// Bottom/rail navigation label for the settings destination.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Bottom/rail navigation label for the in-app user guide destination.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get navGuide;

  /// Tooltip for the wide-layout navigation-rail Help button that opens the in-app user guide.
  ///
  /// In en, this message translates to:
  /// **'User guide'**
  String get navGuideTooltip;

  /// Title of the Settings screen (sidebar header on wide layouts, app bar on narrow).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Generic option meaning 'follow the device/platform setting'. Shared by the date-format, first-day-of-week, and app-language controls.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get commonSystemDefault;

  /// Label of the Settings section that groups app-language and regional-format preferences.
  ///
  /// In en, this message translates to:
  /// **'Language & region'**
  String get settingsLanguageRegionTitle;

  /// Header for the group of regional-format controls (date format, first day of week).
  ///
  /// In en, this message translates to:
  /// **'Formats'**
  String get settingsRegionalFormatsHeader;

  /// Header for the app-language group in the Language & region settings section.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsRegionalLanguageHeader;

  /// Title of the control that chooses how program event dates are formatted.
  ///
  /// In en, this message translates to:
  /// **'Date format'**
  String get settingsDateFormatTitle;

  /// Subtitle for the date-format control, showing a live example of today's date in the chosen format.
  ///
  /// In en, this message translates to:
  /// **'How program event dates appear. Example: {example}'**
  String settingsDateFormatSubtitle(String example);

  /// Date-format option: ISO-like year-month-day. The parenthetical is an illustrative sample date.
  ///
  /// In en, this message translates to:
  /// **'Year-month-day (2026-07-15)'**
  String get settingsDateFormatYmd;

  /// Date-format option: day/month/year. The parenthetical is an illustrative sample date.
  ///
  /// In en, this message translates to:
  /// **'Day/month/year (15/07/2026)'**
  String get settingsDateFormatDmy;

  /// Date-format option: month/day/year. The parenthetical is an illustrative sample date.
  ///
  /// In en, this message translates to:
  /// **'Month/day/year (07/15/2026)'**
  String get settingsDateFormatMdy;

  /// Title of the control that chooses which day the week starts on.
  ///
  /// In en, this message translates to:
  /// **'First day of week'**
  String get settingsFirstDayOfWeekTitle;

  /// Subtitle for the first-day-of-week control.
  ///
  /// In en, this message translates to:
  /// **'Choose which day the week starts on.'**
  String get settingsFirstDayOfWeekSubtitle;

  /// First-day-of-week option: the week starts on Sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get settingsFirstDayOfWeekSunday;

  /// First-day-of-week option: the week starts on Monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get settingsFirstDayOfWeekMonday;

  /// First-day-of-week option: the week starts on Saturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get settingsFirstDayOfWeekSaturday;

  /// Caption noting that the platform date picker derives its first day of week from the app's active locale (set by the App language preference), so the first-day-of-week setting cannot override it.
  ///
  /// In en, this message translates to:
  /// **'The system date picker follows the app\'s active language, so this setting doesn\'t change it.'**
  String get settingsFirstDayOfWeekPickerNote;

  /// Title of the control that chooses the language of the app's interface.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsAppLanguageTitle;

  /// Subtitle for the app-language control.
  ///
  /// In en, this message translates to:
  /// **'Choose the language of the app\'s interface.'**
  String get settingsAppLanguageSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
