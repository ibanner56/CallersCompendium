import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_nl.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('da'),
    Locale('de'),
    Locale('en'),
    Locale('fr'),
    Locale('ja'),
    Locale('nl'),
  ];

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

  /// Label under the wide-layout navigation-rail global-search button.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// Tooltip for the navigation-rail global-search button; {hint} is the platform keyboard shortcut (e.g. the Command-K glyph on Apple platforms or 'Ctrl K' elsewhere), rendered as plain tooltip text.
  ///
  /// In en, this message translates to:
  /// **'Search ({hint})'**
  String navSearchTooltip(String hint);

  /// Accessibility label on the startup loading spinner shown while the collection database is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing your collection'**
  String get appBootstrapPreparing;

  /// Accessibility label on the startup progress indicator shown while the search index is being rebuilt after a migration.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding search index'**
  String get appBootstrapRebuildingIndex;

  /// Startup label under the determinate progress indicator during the post-migration search-index rebuild. '{percent}' is the completion percentage.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding search index… {percent}%'**
  String appBootstrapRebuildingIndexProgress(int percent);

  /// Error message shown on the startup screen when preparing the collection fails; accompanied by a Retry button.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the collection.'**
  String get appBootstrapError;

  /// Terminal startup-screen message shown when the on-disk data was written by a newer app version than the one running (no downgrade path). No Retry is offered.
  ///
  /// In en, this message translates to:
  /// **'This data was created by a newer version of Caller’s Compendium — please update the app.'**
  String get migrationDowngradeMessage;

  /// Terminal startup-screen message shown when a pre-migration backup could not be created and the user declined to proceed without one. {cause} is an optional trailing sentence (already ends with a space) naming the likely cause, or empty when unknown.
  ///
  /// In en, this message translates to:
  /// **'Caller’s Compendium didn’t start because it couldn’t create an automatic backup before upgrading your saved data. {cause}Free up space (or fix the backups folder), then reopen the app — or reopen and choose to continue without a backup.'**
  String migrationSnapshotAbortedMessage(String cause);

  /// Plain-language sentence naming the likely cause of a failed pre-migration backup: the device is low on storage. Embedded into the snapshot-failure copy.
  ///
  /// In en, this message translates to:
  /// **'Your device appears to be low on storage space.'**
  String get migrationSnapshotCauseDiskFull;

  /// Plain-language sentence naming the likely cause of a failed pre-migration backup: the backups folder is not writable. Embedded into the snapshot-failure copy.
  ///
  /// In en, this message translates to:
  /// **'The automatic backups folder could not be written to.'**
  String get migrationSnapshotCauseUnwritableBackupsDir;

  /// Title of the blocking dialog asking whether to upgrade saved data without a recoverable backup after the automatic backup failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t back up your data'**
  String get migrationSnapshotConsentTitle;

  /// Body of the blocking dialog asking whether to upgrade saved data without a recoverable backup. {cause} is an optional block (already prefixed with two newlines) naming the likely cause, or empty when unknown.
  ///
  /// In en, this message translates to:
  /// **'Before upgrading your saved data to a new format, Caller’s Compendium makes an automatic backup so a failed upgrade can be undone. That backup couldn’t be created this time.{cause}\n\nIf you continue without a backup and the upgrade is interrupted, some of your dances or programs could be lost. You can quit, free up space (or fix the backups folder), and reopen the app to try again.'**
  String migrationSnapshotConsentBody(String cause);

  /// Button that safely aborts startup rather than upgrading saved data without a recoverable backup.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get migrationSnapshotConsentQuit;

  /// Button that proceeds with the data upgrade even though no recoverable backup could be made.
  ///
  /// In en, this message translates to:
  /// **'Proceed without a backup'**
  String get migrationSnapshotConsentProceed;

  /// Headline on the below-floor recovery screen shown when the on-disk database was written by a build older than the minimum supported schema version. Terminal, no Retry.
  ///
  /// In en, this message translates to:
  /// **'This data is from a version too old to open'**
  String get migrationBelowFloorHeadline;

  /// Body of the below-floor recovery screen. {bridgeTag} is the release tag of the migration-bridge release (e.g. 'v0.1.0-beta.6').
  ///
  /// In en, this message translates to:
  /// **'Your data can be recovered. Install {bridgeTag}, open the app once to let it update your data, then install this version again.\n\nIf you prefer to start fresh, use the options below — your current data will be lost.'**
  String migrationBelowFloorBody(String bridgeTag);

  /// Button label on the below-floor recovery screen that first writes a backup of the current database, then resets it to a fresh state. The reset is only performed if the backup succeeds.
  ///
  /// In en, this message translates to:
  /// **'Back Up + Reset'**
  String get migrationBelowFloorBackUpAndReset;

  /// Button label on the below-floor recovery screen that resets the database to a fresh state without making a backup first. Unrecoverable.
  ///
  /// In en, this message translates to:
  /// **'Reset Only'**
  String get migrationBelowFloorResetOnly;

  /// Title of the dialog shown when the pre-reset backup fails on the below-floor recovery screen. The reset is NOT performed when this dialog is shown.
  ///
  /// In en, this message translates to:
  /// **'Backup failed'**
  String get migrationBelowFloorBackupFailedTitle;

  /// Body of the dialog shown when the pre-reset backup fails on the below-floor recovery screen. The reset is NOT performed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be written, so your data has not been reset.'**
  String get migrationBelowFloorBackupFailedBody;

  /// Title of the confirmation dialog shown before a reset action on the below-floor recovery screen (both Back Up + Reset and Reset Only). Used after a successful backup to ask the user to confirm the wipe.
  ///
  /// In en, this message translates to:
  /// **'Reset app data?'**
  String get migrationBelowFloorResetConfirmTitle;

  /// Body of the confirmation dialog shown before a Back Up + Reset action once the backup has been written successfully.
  ///
  /// In en, this message translates to:
  /// **'A backup has been saved. Resetting will replace your current data with a fresh, empty database.'**
  String get migrationBelowFloorResetConfirmBody;

  /// Line shown in the Back Up + Reset confirmation dialog to tell the user where the backup file was written.
  ///
  /// In en, this message translates to:
  /// **'Backup saved to: {backupPath}'**
  String migrationBelowFloorBackupSavedAt(String backupPath);

  /// Line shown in the Back Up + Reset confirmation dialog to tell the user where the diagnostic log was written (alongside the backup).
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log saved to: {logPath}'**
  String migrationBelowFloorDiagnosticLogSavedAt(String logPath);

  /// Body of the confirmation dialog shown before a Reset Only action on the below-floor recovery screen. No backup is made. Must make the irreversibility and data loss explicit.
  ///
  /// In en, this message translates to:
  /// **'No backup will be made. Resetting will permanently delete all your current data and replace it with a fresh, empty database. This cannot be undone.'**
  String get migrationBelowFloorResetOnlyConfirmBody;

  /// Title of the error dialog shown when the database file could not be deleted during a reset on the below-floor recovery screen. The database is intact.
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get migrationBelowFloorWipeFailedTitle;

  /// Body of the error dialog shown when the database file could not be deleted. Instructs the user to close any apps locking the file and retry.
  ///
  /// In en, this message translates to:
  /// **'The database file could not be deleted. Your data has not been changed. Try closing other apps that may be using the file, then try again.'**
  String get migrationBelowFloorWipeFailedBody;

  /// Title of the optional confirm-before-delete dialog (shown only when the 'Confirm before delete' setting is on).
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get confirmDeleteTitle;

  /// Body of the confirm-before-delete dialog. {itemLabel} is the untrusted user-entered name of the item being deleted (a dance or program title), rendered as plain text between typographic quotes.
  ///
  /// In en, this message translates to:
  /// **'“{itemLabel}” will be deleted. You can undo this.'**
  String confirmDeleteBody(String itemLabel);

  /// Field label for the hexadecimal colour input in the shared colour-picker dialog.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get colorEditHexLabel;

  /// Title of the Settings screen (sidebar header on wide layouts, app bar on narrow).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings section navigation title (sidebar/app bar) for general app preferences: backup, restore, import, performance.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralTitle;

  /// Settings section navigation title (sidebar/app bar) for visual appearance: theme, colours, easter eggs.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceTitle;

  /// Settings section navigation title (sidebar/app bar) for managing figure-notation dialects.
  ///
  /// In en, this message translates to:
  /// **'Dialect'**
  String get settingsDialectTitle;

  /// Settings section navigation title (sidebar/app bar) for default values applied to new dances (formation, progression, form).
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get settingsDefaultsTitle;

  /// Settings section navigation title (sidebar/app bar) for the app-update controls.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdatesTitle;

  /// Settings section navigation title (sidebar/app bar) for crash logs and diagnostic export.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnosticsTitle;

  /// Settings section navigation title (sidebar/app bar) for app version, license, and help links.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutTitle;

  /// Generic option meaning 'follow the device/platform setting'. Shared by the date-format and app-language controls.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get commonSystemDefault;

  /// Trailing badge on a settings control whose feature is not available yet.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get commonComingSoon;

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

  /// Date-format option that reveals a text field where the user types their own date pattern (issue #584).
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get settingsDateFormatCustom;

  /// Label for the text field where the user enters a custom date pattern.
  ///
  /// In en, this message translates to:
  /// **'Custom date pattern'**
  String get settingsDateFormatCustomPatternLabel;

  /// Placeholder shown in the custom date-pattern field as an example pattern. Keep the literal tokens (letters and separators); do not translate them.
  ///
  /// In en, this message translates to:
  /// **'MM.DD.YY'**
  String get settingsDateFormatCustomPatternHint;

  /// Always-visible legend explaining the allowed custom date-pattern tokens and separators. The literal tokens (yyyy, yy, MM, MMM, MMMM, d, dd) and separators (- / . , space) must not be translated; translate only the surrounding words (Tokens, year, month, short name, full name, day, Separators, or, space).
  ///
  /// In en, this message translates to:
  /// **'Tokens: yyyy or yy = year, MM = month (MMM = short name, MMMM = full name), d or dd = day. Separators: - / . , or space.'**
  String get settingsDateFormatCustomLegend;

  /// Inline warning shown beneath the custom date-pattern field when the entered pattern is empty, contains unknown tokens, or is otherwise unrecognized; the app falls back to the system default until corrected.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized pattern — using the system default until it\'s corrected.'**
  String get settingsDateFormatCustomInvalid;

  /// Title of the control that chooses which day the week starts on.
  ///
  /// In en, this message translates to:
  /// **'First day of week'**
  String get settingsFirstDayOfWeekTitle;

  /// Subtitle for the live first-day-of-week control. Describes what it affects: date views the app draws itself (not the system date picker).
  ///
  /// In en, this message translates to:
  /// **'Which day the week starts on in the app\'s own date views, such as the Programs list\'s this-week strip.'**
  String get settingsFirstDayOfWeekSubtitle;

  /// First-day-of-week option: start the week on Sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get settingsFirstDayOfWeekSunday;

  /// First-day-of-week option: start the week on Monday (ISO-8601).
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get settingsFirstDayOfWeekMonday;

  /// First-day-of-week option: start the week on Saturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get settingsFirstDayOfWeekSaturday;

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

  /// About section header for the help/user-guide group.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsAboutHelpHeader;

  /// Title of the tile (and its full-screen route) that opens the built-in user guide.
  ///
  /// In en, this message translates to:
  /// **'User guide'**
  String get settingsAboutUserGuideTitle;

  /// Subtitle describing the built-in user guide tile.
  ///
  /// In en, this message translates to:
  /// **'Read the built-in guides — getting started, dialects, imports, and more. Works offline.'**
  String get settingsAboutUserGuideSubtitle;

  /// About section header introducing the app's software license notice.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get settingsAboutLicenseHeader;

  /// Explanatory paragraph about the app's AGPL-3.0 license and the corresponding source-code offer. 'Caller's Compendium', 'GNU Affero General Public License', and 'AGPL-3.0' are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'Caller\'s Compendium is free software, licensed under the GNU Affero General Public License, version 3 (AGPL-3.0). You are free to use, study, share, and modify it under that license. Because the AGPL requires it, the complete corresponding source code is offered to everyone who uses the app.'**
  String get settingsAboutLicenseBody;

  /// Title of the tile that opens the app's source-code repository.
  ///
  /// In en, this message translates to:
  /// **'View source on GitHub'**
  String get settingsAboutViewSourceTitle;

  /// About section header for the bundled-typeface attribution group.
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get settingsAboutFontsHeader;

  /// Paragraph introducing the bundled fonts. 'SIL Open Font License 1.1' is a proper noun kept verbatim; “View licenses” refers to the tile of the same name.
  ///
  /// In en, this message translates to:
  /// **'This app bundles the following typefaces under the SIL Open Font License 1.1. Their full license texts are available under “View licenses” below.'**
  String get settingsAboutFontsBody;

  /// Attribution subtitle for the Fraunces typeface: its license, copyright, and role in the app. License name and copyright are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'SIL Open Font License 1.1 · © The Fraunces Project Authors — display & headings'**
  String get settingsAboutFontFrauncesSubtitle;

  /// Attribution subtitle for the Atkinson Hyperlegible typeface: its license, copyright, and role in the app. License name and copyright are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — body, UI & Perform'**
  String get settingsAboutFontAtkinsonSubtitle;

  /// Attribution subtitle for the Roboto typeface: its license, copyright, and role in the app. License name and copyright are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'SIL Open Font License 1.1 · © The Roboto Project Authors — fallback'**
  String get settingsAboutFontRobotoSubtitle;

  /// About section header for the theme-inspiration attribution.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get settingsAboutThemesHeader;

  /// Paragraph crediting the code-editor palettes that inspired the optional themes. The palette names are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'Several optional color themes are inspired by popular code-editor palettes — One Dark, Dracula, Nord, Tokyo Night, Gruvbox, and Catppuccin among them — re-derived and contrast-tuned for this app. Theme names are used only to credit that inspiration.'**
  String get settingsAboutThemesBody;

  /// About section header for the dance-data provenance attribution.
  ///
  /// In en, this message translates to:
  /// **'Dance data'**
  String get settingsAboutDanceDataHeader;

  /// Paragraph crediting The Caller's Box dance-data source. 'The Caller's Box', the author names, and 'CC BY-NC' are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'Dance data draws on The Caller’s Box (Chris Page & Michael Dyck), whose collection is published under the Creative Commons Attribution-NonCommercial license (CC BY-NC), with gratitude.'**
  String get settingsAboutDanceDataBody;

  /// About section header for the full open-source license texts entry.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get settingsAboutLicensesHeader;

  /// Title of the tile that opens the full open-source license texts page.
  ///
  /// In en, this message translates to:
  /// **'View licenses'**
  String get settingsAboutViewLicensesTitle;

  /// Subtitle for the 'View licenses' tile.
  ///
  /// In en, this message translates to:
  /// **'Full open-source license texts, including the bundled fonts.'**
  String get settingsAboutViewLicensesSubtitle;

  /// Legal notice shown on the license page. 'The Caller's Compendium' and 'AGPL-3.0' are proper nouns kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'© The Caller’s Compendium contributors. Licensed under AGPL-3.0.'**
  String get settingsAboutLegalese;

  /// Version line under the app wordmark in the About header.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAboutVersion(String version);

  /// One-line footer at the bottom of the About section combining the app name, version, and license identifier. All three values are proper nouns / identifiers kept verbatim; only the word 'Version' is translatable.
  ///
  /// In en, this message translates to:
  /// **'{appName} · Version {version} · {license}'**
  String settingsAboutVersionLine(
    String appName,
    String version,
    String license,
  );

  /// Updates settings section header.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdatesHeader;

  /// Title of the tile that manually checks for a newer app version.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsUpdatesCheckNowTitle;

  /// Status line before any check has run, stating the current version.
  ///
  /// In en, this message translates to:
  /// **'You\'re on version {version}.'**
  String settingsUpdatesStatusIdle(String version);

  /// Status line while an update check is in progress.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsUpdatesStatusChecking;

  /// Status line after a check that found no newer version.
  ///
  /// In en, this message translates to:
  /// **'No update found. You\'re on version {version}.'**
  String settingsUpdatesStatusNoUpdate(String version);

  /// Status line after a check that found a newer version.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available. See the banner to view it.'**
  String settingsUpdatesStatusAvailable(String version);

  /// Header for the update-channel (stable vs beta) group.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get settingsUpdatesChannelHeader;

  /// Title of the beta-channel opt-in toggle.
  ///
  /// In en, this message translates to:
  /// **'Beta channel'**
  String get settingsUpdatesBetaTitle;

  /// Subtitle explaining the beta-channel toggle.
  ///
  /// In en, this message translates to:
  /// **'Receive pre-release beta updates. Off means stable releases only.'**
  String get settingsUpdatesBetaSubtitle;

  /// Header for the automatic-background-check group.
  ///
  /// In en, this message translates to:
  /// **'Automatic checks'**
  String get settingsUpdatesAutoHeader;

  /// Title of the automatic-background-check toggle.
  ///
  /// In en, this message translates to:
  /// **'Check automatically'**
  String get settingsUpdatesAutoTitle;

  /// Subtitle explaining the automatic-background-check toggle.
  ///
  /// In en, this message translates to:
  /// **'Check for a newer version in the background when the app starts. Off by default.'**
  String get settingsUpdatesAutoSubtitle;

  /// Privacy/behaviour paragraph reassuring the user how the update check and assisted download work.
  ///
  /// In en, this message translates to:
  /// **'The update check downloads a small version file over HTTPS and nothing else — no data about you, your device, or your usage is ever sent. Nothing is downloaded or installed automatically: you choose when to download an update, it is verified before it opens, and your system installer completes the install.'**
  String get settingsUpdatesPrivacyNote;

  /// Title of the assisted-download tile while the update is downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get settingsUpdatesDownloadingTitle;

  /// Progress label while downloading when a percentage is not yet known.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get settingsUpdatesDownloadingIndeterminate;

  /// Progress label while downloading, showing the completed percentage.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String settingsUpdatesDownloadingPercent(int percent);

  /// Title of the assisted-download tile while verifying the downloaded file.
  ///
  /// In en, this message translates to:
  /// **'Verifying download'**
  String get settingsUpdatesVerifyingTitle;

  /// Subtitle shown while verifying the download's sha256 integrity. 'sha256' is a technical term kept verbatim.
  ///
  /// In en, this message translates to:
  /// **'Checking the sha256 integrity of the download…'**
  String get settingsUpdatesVerifyingSubtitle;

  /// Title of the assisted-download tile while handing the verified update to the OS installer.
  ///
  /// In en, this message translates to:
  /// **'Preparing the installer'**
  String get settingsUpdatesHandoffTitle;

  /// Subtitle shown while handing the verified update to the system installer.
  ///
  /// In en, this message translates to:
  /// **'Handing the verified update to your system…'**
  String get settingsUpdatesHandoffSubtitle;

  /// Title of the assisted-download tile after the download completes.
  ///
  /// In en, this message translates to:
  /// **'Update downloaded'**
  String get settingsUpdatesCompletedTitle;

  /// Subtitle shown after the download completes, directing the user to the system installer.
  ///
  /// In en, this message translates to:
  /// **'Follow your system installer to finish updating.'**
  String get settingsUpdatesCompletedSubtitle;

  /// Subtitle shown after the download completes when the verified installer was revealed in the file manager, directing the user to run it.
  ///
  /// In en, this message translates to:
  /// **'Verified and revealed in your file manager — run the installer to finish updating.'**
  String get settingsUpdatesCompletedSubtitleRevealed;

  /// Title of the assisted-download tile in its idle and failed states, offering to download the update.
  ///
  /// In en, this message translates to:
  /// **'Download & install update'**
  String get settingsUpdatesDownloadTitle;

  /// Fallback error message when an assisted download fails without a more specific reason. The raw error is logged, not shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'The update could not be downloaded.'**
  String get settingsUpdatesDownloadError;

  /// Subtitle of the idle assisted-download tile describing the download → verify → install flow.
  ///
  /// In en, this message translates to:
  /// **'Download version {version}, verify it, then open your installer. The app never replaces itself in place.'**
  String settingsUpdatesDownloadSubtitle(String version);

  /// Dialect settings section header for the dialect library.
  ///
  /// In en, this message translates to:
  /// **'Dialects'**
  String get settingsDialectHeader;

  /// Label of the button (and title of the prompt) that creates a new custom dialect.
  ///
  /// In en, this message translates to:
  /// **'New dialect'**
  String get settingsDialectNewButton;

  /// Default name pre-filled when creating a new dialect. Resolves at creation time and is persisted as the dialect's name thereafter.
  ///
  /// In en, this message translates to:
  /// **'My dialect'**
  String get settingsDialectNewDefaultName;

  /// Confirm button of the new-dialect name prompt.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get settingsDialectCreateConfirm;

  /// Label of the button (and title of the chooser dialog) that duplicates an existing dialect.
  ///
  /// In en, this message translates to:
  /// **'Duplicate from…'**
  String get settingsDialectDuplicateFrom;

  /// Title of the rename-dialect prompt.
  ///
  /// In en, this message translates to:
  /// **'Rename dialect'**
  String get settingsDialectRenameTitle;

  /// Rename action: the rename-prompt confirm button and the row menu item.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get settingsDialectRename;

  /// Row menu item that opens the dialect's term editor.
  ///
  /// In en, this message translates to:
  /// **'Edit terms'**
  String get settingsDialectEditTerms;

  /// Row menu item on a read-only preset that duplicates it into an editable custom dialect.
  ///
  /// In en, this message translates to:
  /// **'Duplicate to customize'**
  String get settingsDialectDuplicateToCustomize;

  /// Title of the confirm-delete dialog for a custom dialect.
  ///
  /// In en, this message translates to:
  /// **'Delete dialect?'**
  String get settingsDialectDeleteTitle;

  /// Body of the confirm-delete dialog, quoting the dialect name (untrusted user text, rendered as plain text).
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be permanently removed.'**
  String settingsDialectDeleteConfirmBody(String name);

  /// Tooltip for the per-dialect actions menu button.
  ///
  /// In en, this message translates to:
  /// **'Dialect actions'**
  String get settingsDialectActionsTooltip;

  /// Badge marking a dialect as a shipped, read-only preset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get settingsDialectPresetBadge;

  /// Text-field label in the dialect name prompt.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsDialectNameLabel;

  /// Section header above the built-in theme gallery in Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsAppearanceThemeHeader;

  /// Section header above the user's saved custom themes in Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Custom themes'**
  String get settingsAppearanceCustomThemesHeader;

  /// Section header for playful optional visual features in Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Easter eggs'**
  String get settingsAppearanceEasterEggsHeader;

  /// Section header for set-list appearance options in Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Set lists'**
  String get settingsAppearanceSetListsHeader;

  /// Section header for the formation-colour customisation entry in Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Formation colours'**
  String get settingsAppearanceFormationColoursHeader;

  /// Toggle title: tint a dance's view when its title names a colour.
  ///
  /// In en, this message translates to:
  /// **'Colour-named dances tint the theme'**
  String get settingsAppearanceColourDanceTitle;

  /// Explanation for the colour-named-dances tinting toggle.
  ///
  /// In en, this message translates to:
  /// **'A playful surprise: when you open a dance whose title names a colour — like Baby Rose or Blue Boy — its view is tinted that colour. Off by default, and it steps aside when a high-contrast theme is active so readability always wins.'**
  String get settingsAppearanceColourDanceSubtitle;

  /// Toggle title: tint set-list rows by formation family.
  ///
  /// In en, this message translates to:
  /// **'Colour-code set-list rows'**
  String get settingsAppearanceSetListColorTitle;

  /// Explanation for the set-list colour-coding toggle.
  ///
  /// In en, this message translates to:
  /// **'Tint each dance row by its formation family (contra, mixer, square, …) — dances marked as mixers always get the mixer tint, regardless of formation. The formation is always shown as text too, so rows stay readable without colour.'**
  String get settingsAppearanceSetListColorSubtitle;

  /// List-tile title opening the formation-colour customisation screen.
  ///
  /// In en, this message translates to:
  /// **'Formation label colours'**
  String get settingsAppearanceFormationColoursTitle;

  /// Explanation for the formation-colour customisation entry.
  ///
  /// In en, this message translates to:
  /// **'Highlight individual formations in your own colours — e.g. Becket (CW) in yellow, Becket (CCW) in pink — on dance cards, dance detail, and the Perform header.'**
  String get settingsAppearanceFormationColoursSubtitle;

  /// Label shown on the currently-selected theme card in the gallery.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get settingsAppearanceSelectedBadge;

  /// Sample heading text shown in a theme preview swatch.
  ///
  /// In en, this message translates to:
  /// **'Aa Preview'**
  String get settingsAppearancePreviewHeading;

  /// Sample body text shown in a theme preview swatch.
  ///
  /// In en, this message translates to:
  /// **'Body text sample'**
  String get settingsAppearancePreviewBody;

  /// Button that starts creating a new custom theme from the active theme.
  ///
  /// In en, this message translates to:
  /// **'New custom theme'**
  String get settingsAppearanceNewThemeButton;

  /// Default name a brand-new custom theme is seeded with before the user renames it.
  ///
  /// In en, this message translates to:
  /// **'My theme'**
  String get settingsAppearanceNewThemeDefaultName;

  /// Helper text shown when the user has no saved custom themes yet.
  ///
  /// In en, this message translates to:
  /// **'Copy the current theme and tune any color. Custom themes are saved on this device.'**
  String get settingsAppearanceCustomThemesEmpty;

  /// Title of the confirm-delete dialog for a custom theme.
  ///
  /// In en, this message translates to:
  /// **'Delete theme?'**
  String get settingsAppearanceDeleteThemeTitle;

  /// Body of the confirm-delete dialog for a custom theme.
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be permanently removed.'**
  String settingsAppearanceDeleteThemeBody(String name);

  /// Screen-reader label for a saved custom-theme card.
  ///
  /// In en, this message translates to:
  /// **'Custom theme {name}'**
  String settingsAppearanceCustomThemeSemantic(String name);

  /// Tooltip for the overflow menu (edit/duplicate/delete) on a custom-theme card.
  ///
  /// In en, this message translates to:
  /// **'Theme actions'**
  String get settingsAppearanceThemeActionsTooltip;

  /// Section header for defaults prefilled into new programs.
  ///
  /// In en, this message translates to:
  /// **'Program defaults'**
  String get settingsDefaultsProgramHeader;

  /// Text-field label for the default caller prefilled into new programs.
  ///
  /// In en, this message translates to:
  /// **'Default caller'**
  String get settingsDefaultsCallerLabel;

  /// Helper text under the default caller and band fields.
  ///
  /// In en, this message translates to:
  /// **'Prefilled into new programs; editable per program.'**
  String get settingsDefaultsPrefilledHelper;

  /// Text-field label for the default band prefilled into new programs.
  ///
  /// In en, this message translates to:
  /// **'Default band'**
  String get settingsDefaultsBandLabel;

  /// Section header for display-related default settings.
  ///
  /// In en, this message translates to:
  /// **'Display defaults'**
  String get settingsDefaultsDisplayHeader;

  /// Title of the default Collection sort-order picker.
  ///
  /// In en, this message translates to:
  /// **'Collection sort order'**
  String get settingsDefaultsSortTitle;

  /// Explanation for the default Collection sort-order picker.
  ///
  /// In en, this message translates to:
  /// **'How the Collection is sorted when you open it. You can still change the sort while browsing.'**
  String get settingsDefaultsSortSubtitle;

  /// Toggle title: open dances in canonical terms rather than the active dialect.
  ///
  /// In en, this message translates to:
  /// **'Open dance details in canonical terms'**
  String get settingsDefaultsCanonicalTitle;

  /// Explanation for the canonical-terms default toggle.
  ///
  /// In en, this message translates to:
  /// **'When on, a dance opens showing canonical role and move names instead of your active dialect. You can still switch views on the dance while it is open.'**
  String get settingsDefaultsCanonicalSubtitle;

  /// Section header for the collection-card field-visibility preference (#767).
  ///
  /// In en, this message translates to:
  /// **'Collection card fields'**
  String get settingsDefaultsCollectionCardHeader;

  /// Subtitle describing the collection card field-visibility checkboxes (#767).
  ///
  /// In en, this message translates to:
  /// **'Choose which details appear on each dance row. All fields are shown by default.'**
  String get settingsDefaultsCollectionCardSubtitle;

  /// Label for the Authors field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get settingsDefaultsCollectionCardAuthors;

  /// Label for the 'called ×N' chip field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Times called'**
  String get settingsDefaultsCollectionCardCalledCount;

  /// Label for the Formation chip field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get settingsDefaultsCollectionCardFormation;

  /// Label for the Status chip field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get settingsDefaultsCollectionCardStatus;

  /// Label for the Level/mixed-level chip field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get settingsDefaultsCollectionCardLevel;

  /// Label for the Rating chip field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get settingsDefaultsCollectionCardRating;

  /// Label for the Tags chip field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get settingsDefaultsCollectionCardTags;

  /// Label for the showInList custom-field chips field-visibility toggle (#767).
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get settingsDefaultsCollectionCardCustomFields;

  /// Section header for defaults applied when authoring a new dance.
  ///
  /// In en, this message translates to:
  /// **'Dance-authoring defaults'**
  String get settingsDefaultsAuthoringHeader;

  /// Title of the opt-in setting that lets a new figure be typed as one line instead of built field by field (#419).
  ///
  /// In en, this message translates to:
  /// **'Free-text entry'**
  String get settingsDefaultsFreeTextEntryTitle;

  /// Explanatory subtitle for the free-text-entry setting, describing what turning it on does.
  ///
  /// In en, this message translates to:
  /// **'When on, adding a new figure lets you type it as one line (e.g. \"neighbor balance & swing\") instead of building it field by field. The line is parsed into figure(s); anything unrecognized is kept as a custom figure you can fix later. Editing an existing figure always uses the full editor.'**
  String get settingsDefaultsFreeTextEntrySubtitle;

  /// Title of the opt-in setting that makes the figure editor always recompute a figure's beat count from its move/params, even overriding a manually entered value (issue #689).
  ///
  /// In en, this message translates to:
  /// **'Aggressively recompute figure beats'**
  String get settingsDefaultsAggressiveBeatsUpdateTitle;

  /// Explanatory subtitle for the aggressive-beats-update setting, explicitly warning that a manually entered beat count can be overwritten when the toggle is on (issue #689 guardrail).
  ///
  /// In en, this message translates to:
  /// **'When on, changing a figure\'s move or a param that affects timing recalculates its beat count immediately — even overwriting a beat count you typed in by hand. When off (default), a beat count you\'ve edited is never changed automatically.'**
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle;

  /// Title of the Defaults settings row that opens the figure-shorthand mappings editor (#420).
  ///
  /// In en, this message translates to:
  /// **'Figure shorthands'**
  String get settingsDefaultsFigureShorthandsTitle;

  /// Subtitle for the figure-shorthands row when no shorthands are defined yet, explaining what the feature does.
  ///
  /// In en, this message translates to:
  /// **'Map short tokens to one or more figures you can insert during free-text entry.'**
  String get settingsDefaultsFigureShorthandsEmptySubtitle;

  /// Subtitle for the figure-shorthands row showing how many shorthands the user has defined.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shorthand defined.} other{{count} shorthands defined.}}'**
  String settingsDefaultsFigureShorthandsCountSubtitle(int count);

  /// Title of the default dance-form picker.
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get settingsDefaultsFormTitle;

  /// Explanation for the default dance-form picker.
  ///
  /// In en, this message translates to:
  /// **'The dance form a new dance starts as. You can still change it per dance.'**
  String get settingsDefaultsFormSubtitle;

  /// Title of the default dance-formation picker.
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get settingsDefaultsFormationTitle;

  /// Explanation for the default dance-formation picker.
  ///
  /// In en, this message translates to:
  /// **'The formation a new dance starts in. You can still change it per dance.'**
  String get settingsDefaultsFormationSubtitle;

  /// Title of the default dance-progression picker.
  ///
  /// In en, this message translates to:
  /// **'Progression'**
  String get settingsDefaultsProgressionTitle;

  /// Explanation for the default dance-progression picker.
  ///
  /// In en, this message translates to:
  /// **'The progression a new dance starts with. You can still change it per dance.'**
  String get settingsDefaultsProgressionSubtitle;

  /// Text-field label for the default phrase structure seeded into new dances.
  ///
  /// In en, this message translates to:
  /// **'Default phrase structure'**
  String get settingsDefaultsPhraseLabel;

  /// Helper text for the default phrase-structure field. '4×16', 'A1 A2 B1 B2' and '6*8*2' are notation examples.
  ///
  /// In en, this message translates to:
  /// **'Seeded into new dances. Blank = standard 4×16 (A1 A2 B1 B2); else e.g. 6*8*2.'**
  String get settingsDefaultsPhraseHelper;

  /// Sub-heading for the figures a new dance starts with.
  ///
  /// In en, this message translates to:
  /// **'Starting figures'**
  String get settingsDefaultsStartingFiguresTitle;

  /// Explanation for the starting-figures default.
  ///
  /// In en, this message translates to:
  /// **'The figures a new dance starts with. Defaults to a single stand still (8 beats); clear it for a blank new dance. Editable per dance.'**
  String get settingsDefaultsStartingFiguresSubtitle;

  /// Sub-heading for per-move default parameter overrides.
  ///
  /// In en, this message translates to:
  /// **'Move defaults'**
  String get settingsDefaultsMoveDefaultsTitle;

  /// Explanation for per-move default parameter overrides.
  ///
  /// In en, this message translates to:
  /// **'Preferred parameter values applied when you insert a move while entering a dance. These override that move\'s built-in defaults; you can still change any parameter on the figure afterward. Unset moves and parameters use the built-in defaults.'**
  String get settingsDefaultsMoveDefaultsSubtitle;

  /// Button and dialog title for adding a per-move parameter default.
  ///
  /// In en, this message translates to:
  /// **'Add move default'**
  String get settingsDefaultsAddMoveButton;

  /// Tooltip on the button that removes a per-move default override.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsDefaultsRemoveMoveTooltip;

  /// Shown on a move-default card when the move no longer exists in the taxonomy.
  ///
  /// In en, this message translates to:
  /// **'This move is no longer in the taxonomy.'**
  String get settingsDefaultsMoveGone;

  /// Shown on a move-default card when the move has no parameters to override.
  ///
  /// In en, this message translates to:
  /// **'This move has no parameters to default.'**
  String get settingsDefaultsMoveNoParams;

  /// App-bar title of the per-formation label-colour settings screen.
  ///
  /// In en, this message translates to:
  /// **'Formation colours'**
  String get settingsFormationColoursTitle;

  /// Intro paragraph explaining per-formation label colours.
  ///
  /// In en, this message translates to:
  /// **'Give a formation its own colour to highlight its label on dance cards, dance detail, and the Perform header. Only the formations you customise are highlighted; the rest show their label as usual. The formation is always shown as text too, so labels stay readable without colour.'**
  String get settingsFormationColoursIntro;

  /// Section header above the list of formation shapes.
  ///
  /// In en, this message translates to:
  /// **'Formations'**
  String get settingsFormationColoursListHeader;

  /// Subtitle shown when a formation has a custom label colour set.
  ///
  /// In en, this message translates to:
  /// **'Custom colour'**
  String get settingsFormationColoursCustom;

  /// Subtitle shown when a formation uses its family-default label colour.
  ///
  /// In en, this message translates to:
  /// **'Family default'**
  String get settingsFormationColoursFamilyDefault;

  /// Tooltip on the button that resets one formation's custom colour.
  ///
  /// In en, this message translates to:
  /// **'Reset {label} to the family default'**
  String settingsFormationColoursResetTooltip(String label);

  /// Section header for the tag-colour customisation entry in Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Tag colours'**
  String get settingsAppearanceTagColoursHeader;

  /// List-tile title opening the tag-colour customisation screen.
  ///
  /// In en, this message translates to:
  /// **'Tag colours'**
  String get settingsAppearanceTagColoursTitle;

  /// Explanation for the tag-colour customisation entry.
  ///
  /// In en, this message translates to:
  /// **'Give a tag its own colour to make it stand out on dance cards and dance detail. The tag\'s name is always shown too, so tags stay readable without colour.'**
  String get settingsAppearanceTagColoursSubtitle;

  /// App-bar title of the per-tag colour settings screen.
  ///
  /// In en, this message translates to:
  /// **'Tag colours'**
  String get settingsTagColoursTitle;

  /// Intro paragraph explaining per-tag colours.
  ///
  /// In en, this message translates to:
  /// **'Give a tag its own colour to make it stand out wherever it appears. Only the tags you colour change; the rest look exactly as they do now. The tag\'s name is always shown too, so tags stay readable without colour.'**
  String get settingsTagColoursIntro;

  /// Section header above the list of tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get settingsTagColoursListHeader;

  /// Shown on the tag-colour screen when the collection has no tags.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t created any tags yet. Add a tag to a dance and it will appear here.'**
  String get settingsTagColoursEmpty;

  /// Subtitle shown when a tag has a custom colour set.
  ///
  /// In en, this message translates to:
  /// **'Custom colour'**
  String get settingsTagColoursCustom;

  /// Subtitle shown when a tag has no colour assigned.
  ///
  /// In en, this message translates to:
  /// **'No colour'**
  String get settingsTagColoursNoColour;

  /// Tooltip on the button that clears one tag's colour.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}\'s colour'**
  String settingsTagColoursResetTooltip(String label);

  /// Snack-bar message shown when saving or clearing a tag colour fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that colour. Please try again.'**
  String get settingsTagColoursSaveError;

  /// Shown on the tag-colour screen when the tag list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your tags.'**
  String get settingsTagColoursLoadError;

  /// General settings section header for collection-library preferences.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get settingsGeneralLibraryHeader;

  /// Title of the General settings toggle that sorts dance titles while ignoring leading articles such as 'the', 'a', and 'an'.
  ///
  /// In en, this message translates to:
  /// **'Ignore leading articles when sorting'**
  String get settingsGeneralSortIgnoreArticlesTitle;

  /// Subtitle explaining the ignore-leading-articles sort toggle. Example title and articles are illustrative text.
  ///
  /// In en, this message translates to:
  /// **'When on, the dance list alphabetizes titles ignoring a leading “the”, “a”, or “an” — so “The Nice Combination” files under N. Turn off to sort by the literal title.'**
  String get settingsGeneralSortIgnoreArticlesSubtitle;

  /// General settings section header for venue-related preferences.
  ///
  /// In en, this message translates to:
  /// **'Venues'**
  String get settingsGeneralVenuesHeader;

  /// Title of the General settings toggle that enables reusable venue records for programs.
  ///
  /// In en, this message translates to:
  /// **'Use reusable venue records'**
  String get settingsGeneralVenueEntityModeTitle;

  /// Subtitle explaining what reusable venue records do and that switching modes preserves existing venue data.
  ///
  /// In en, this message translates to:
  /// **'Turn venues into reusable records with address, contacts, and schedule that many programs can share and you edit in one place. When off, a program’s venue is a simple free-text field. Switching is lossless — your typed venue and any linked record are both kept.'**
  String get settingsGeneralVenueEntityModeSubtitle;

  /// Title of the General settings row that opens the reusable venue manager.
  ///
  /// In en, this message translates to:
  /// **'Manage venues'**
  String get settingsGeneralManageVenuesTitle;

  /// Subtitle for the row that opens the reusable venue manager.
  ///
  /// In en, this message translates to:
  /// **'Browse, edit, and delete your reusable venue records.'**
  String get settingsGeneralManageVenuesSubtitle;

  /// General settings section header for performance-mode display preferences.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settingsGeneralPerformanceHeader;

  /// Title of the General settings toggle that automatically sizes Perform screen cards.
  ///
  /// In en, this message translates to:
  /// **'Auto-size Perform cards'**
  String get settingsGeneralAutoSizePerformTitle;

  /// Subtitle explaining the auto-size Perform cards toggle. 'A-' and 'A+' refer to text-size controls.
  ///
  /// In en, this message translates to:
  /// **'Scale each card so the full dance or slot fits the screen without scrolling. Turn off to set the size yourself with A- / A+.'**
  String get settingsGeneralAutoSizePerformSubtitle;

  /// General settings section header for calling-history preferences.
  ///
  /// In en, this message translates to:
  /// **'Calling history'**
  String get settingsGeneralCallingHistoryHeader;

  /// Title of the General settings toggle that limits dance calling history to program slots marked performed.
  ///
  /// In en, this message translates to:
  /// **'Require “mark performed” for calling history'**
  String get settingsGeneralRequirePerformedForHistoryTitle;

  /// Subtitle explaining the require-mark-performed calling history toggle.
  ///
  /// In en, this message translates to:
  /// **'When on, a dance’s calling history lists only programs whose slot for that dance was marked performed. When off, a program appears as soon as it contains the dance.'**
  String get settingsGeneralRequirePerformedForHistorySubtitle;

  /// Title of the General settings toggle that controls whether calling history counts programs from everyone, or only those led by the default caller (plus unattributed programs).
  ///
  /// In en, this message translates to:
  /// **'Track calling history for all callers'**
  String get settingsGeneralTrackHistoryForAllCallersTitle;

  /// Subtitle explaining the track-calling-history-for-all-callers toggle.
  ///
  /// In en, this message translates to:
  /// **'When off and a default caller is set, calling history and counts include programs led by that caller plus any programs with no caller recorded (treated as your own). When on — or when no default caller is set — every program that contains the dance is tracked.'**
  String get settingsGeneralTrackHistoryForAllCallersSubtitle;

  /// General settings section header for accessibility preferences.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsGeneralAccessibilityHeader;

  /// Title of the General settings toggle that reduces non-essential animation.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsGeneralReduceMotionTitle;

  /// Subtitle explaining the reduce-motion toggle.
  ///
  /// In en, this message translates to:
  /// **'Dampen or skip non-essential animations, such as animated scrolling when moving between search results or figures.'**
  String get settingsGeneralReduceMotionSubtitle;

  /// Title of the General settings toggle that shows full spoken-style figure wording visually.
  ///
  /// In en, this message translates to:
  /// **'Always show verbose figure text'**
  String get settingsGeneralVerboseFiguresTitle;

  /// Subtitle explaining the verbose figure text toggle.
  ///
  /// In en, this message translates to:
  /// **'Show the full spoken-style figure wording on screen in the dance view, not only to screen readers. Turn off for the terse notation.'**
  String get settingsGeneralVerboseFiguresSubtitle;

  /// Title of the General settings toggle that renders turn amounts as decimals.
  ///
  /// In en, this message translates to:
  /// **'Show turns as decimals'**
  String get settingsGeneralDecimalTurnsTitle;

  /// Subtitle explaining the decimal turns toggle.
  ///
  /// In en, this message translates to:
  /// **'Show turn and rotation amounts as decimals (0.75) instead of fractions (¾). Screen-reader wording is unaffected.'**
  String get settingsGeneralDecimalTurnsSubtitle;

  /// Title of the General settings toggle that asks before deleting a dance or program.
  ///
  /// In en, this message translates to:
  /// **'Confirm before delete'**
  String get settingsGeneralConfirmBeforeDeleteTitle;

  /// Subtitle explaining the confirm-before-delete toggle.
  ///
  /// In en, this message translates to:
  /// **'Ask for confirmation before deleting a dance or program. Deletes can still be undone; this just adds an explicit prompt first.'**
  String get settingsGeneralConfirmBeforeDeleteSubtitle;

  /// General settings section header for deleted-item retention preferences.
  ///
  /// In en, this message translates to:
  /// **'Deleted items'**
  String get settingsGeneralDeletedItemsHeader;

  /// Title of the General settings row that controls how long deleted dances are retained.
  ///
  /// In en, this message translates to:
  /// **'Keep deleted dances for'**
  String get settingsGeneralSoftDeleteRetentionTitle;

  /// Subtitle explaining the deleted-dance retention duration setting.
  ///
  /// In en, this message translates to:
  /// **'Deleted dances are kept for this long before being permanently removed on app launch. Never keeps them until you purge manually.'**
  String get settingsGeneralSoftDeleteRetentionSubtitle;

  /// Deleted-dance retention dropdown option showing a fixed number of days. Keep 'days' literal for every value to preserve the current English UI.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String settingsGeneralSoftDeleteRetentionDays(int days);

  /// Deleted-dance retention dropdown option meaning never automatically purge deleted dances.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsGeneralSoftDeleteRetentionNever;

  /// General settings section header for import actions.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsGeneralImportHeader;

  /// Subtitle for the Import dances row in General settings. 'Caller's Compendium JSON' is the app's backup/import format name.
  ///
  /// In en, this message translates to:
  /// **'Bring dances into your collection from a Caller\'s Compendium JSON file. You review every dance and confirm before anything is added.'**
  String get settingsGeneralImportDancesSubtitle;

  /// Button label that opens the import-dances flow from General settings; the ellipsis indicates more choices follow.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get settingsGeneralImportEllipsisAction;

  /// Title of the General settings row that re-parses imported custom-only figures.
  ///
  /// In en, this message translates to:
  /// **'Re-check custom figures'**
  String get settingsGeneralReparseCustomFiguresTitle;

  /// Subtitle explaining the re-check custom figures action.
  ///
  /// In en, this message translates to:
  /// **'Re-parse imported dances whose figures were kept as custom only because they could not be recognised at import time. Improved parsing upgrades them in place — your tags, ratings, and notes are preserved. You preview and confirm before anything changes.'**
  String get settingsGeneralReparseCustomFiguresSubtitle;

  /// Button label that opens the re-check custom figures flow; the ellipsis indicates more review follows.
  ///
  /// In en, this message translates to:
  /// **'Re-check…'**
  String get settingsGeneralReparseCustomFiguresAction;

  /// General settings section header for backup and restore actions.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get settingsGeneralBackupRestoreHeader;

  /// Snackbar confirming an unencrypted backup was exported.
  ///
  /// In en, this message translates to:
  /// **'Backup exported.'**
  String get backupExported;

  /// Snackbar shown when backup export fails. The raw exception is logged separately, not shown in the UI.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export a backup.'**
  String get backupExportFailed;

  /// Snackbar shown when a backup is refused because its SHA-256 integrity checksum did not verify (issue #536): the file is corrupt or was altered after export, so the restore does not run and data is unchanged.
  ///
  /// In en, this message translates to:
  /// **'This backup failed its integrity check, so it may be corrupt or was changed after it was exported. The restore was cancelled and your data is unchanged.'**
  String get backupRestoreIntegrityFailed;

  /// Snackbar shown when a valid backup contains data too new for this app version, so restore is refused without changing local data.
  ///
  /// In en, this message translates to:
  /// **'This backup contains items this version of the app can\'t read (it may be from a newer version), so the restore was cancelled. Your data is unchanged.'**
  String get backupRestoreIncompatibleVersion;

  /// Snackbar shown when the selected restore file is not a valid backup. Existing data is unchanged.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore: the file isn\'t a valid backup. Your data is unchanged.'**
  String get backupRestoreInvalidFile;

  /// Snackbar shown after a backup restore succeeds but skips one or more non-fatal problems. Keep the literal 'problem(s)' wording to preserve the current English UI.
  ///
  /// In en, this message translates to:
  /// **'Backup restored with {count} problem(s) skipped.'**
  String backupRestoreSkippedProblems(int count);

  /// Snackbar confirming a backup restore completed without skipped problems.
  ///
  /// In en, this message translates to:
  /// **'Backup restored.'**
  String get backupRestored;

  /// Snackbar shown when backup restore fails unexpectedly. The raw exception is logged separately, not shown in the UI.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the backup.'**
  String get backupRestoreFailed;

  /// Snackbar shown when a backup restore committed the core content (dances/programs) successfully but the separate settings-apply step failed (issue #608). Reassures the user their restored content is intact and points to the retry action. Never contains raw error text.
  ///
  /// In en, this message translates to:
  /// **'Your dances and programs were restored, but applying your saved settings failed. Your restored content is safe — you can retry applying settings.'**
  String get backupRestoreSettingsFailed;

  /// Action button on the settings-restore-failed snackbar that re-applies only the settings portion of the backup. Keep short (a SnackBar action label).
  ///
  /// In en, this message translates to:
  /// **'Retry settings'**
  String get backupRestoreSettingsRetryAction;

  /// Snackbar confirming a successful retry of the settings-apply step after an earlier settings-restore failure.
  ///
  /// In en, this message translates to:
  /// **'Settings applied.'**
  String get backupRestoreSettingsRetried;

  /// Title of the backup export row and export-options dialog.
  ///
  /// In en, this message translates to:
  /// **'Export a backup'**
  String get backupExportTitle;

  /// Subtitle for the General settings row that exports a complete app backup.
  ///
  /// In en, this message translates to:
  /// **'Save your entire collection, programs, custom fields, dialects, themes, and settings to a single JSON file you can keep safe or move to another device.'**
  String get backupExportSubtitle;

  /// Button label that starts exporting a backup. Distinct from exportTooltip, which is a tooltip elsewhere.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get backupExportAction;

  /// Title of the backup restore row and restore dialog.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get backupRestoreTitle;

  /// Subtitle for the General settings row that restores from a backup file.
  ///
  /// In en, this message translates to:
  /// **'Replace everything currently in the app with the contents of a backup file. This cannot be undone.'**
  String get backupRestoreSubtitle;

  /// Button label that starts the restore-from-backup flow.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupRestoreAction;

  /// Title of the General settings row that chooses a backup reminder cadence.
  ///
  /// In en, this message translates to:
  /// **'Backup reminder'**
  String get backupReminderTitle;

  /// Subtitle for the backup reminder row when no successful backup has been recorded.
  ///
  /// In en, this message translates to:
  /// **'Last backup: never'**
  String get backupLastBackupNever;

  /// Subtitle for the backup reminder row showing the localized date of the last successful backup.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date}'**
  String backupLastBackupDate(String date);

  /// Backup reminder cadence option meaning no reminder.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get backupReminderOff;

  /// Backup reminder cadence option meaning once per week.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get backupReminderWeekly;

  /// Backup reminder cadence option meaning once per month.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get backupReminderMonthly;

  /// Gentle hint shown under the backup reminder row when the selected cadence says a backup is overdue.
  ///
  /// In en, this message translates to:
  /// **'It\'s been a while since your last backup — consider exporting one now.'**
  String get backupOverdueHint;

  /// Warning text in the restore-from-backup dialog explaining that restore destructively replaces current app data.
  ///
  /// In en, this message translates to:
  /// **'Restoring replaces everything currently in the app — your collection, programs, dialects, themes, and settings — with the backup\'s contents. This cannot be undone.'**
  String get backupRestoreDialogBody;

  /// Button label in the restore-from-backup dialog that opens a file chooser.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get backupChooseFileAction;

  /// Text field label in the restore-from-backup dialog for pasting raw backup JSON.
  ///
  /// In en, this message translates to:
  /// **'Or paste backup JSON'**
  String get backupPasteJsonLabel;

  /// Destructive confirmation button in the restore-from-backup dialog.
  ///
  /// In en, this message translates to:
  /// **'Replace all data'**
  String get backupReplaceAllDataAction;

  /// Snackbar shown when the user tries to export diagnostics but the local diagnostics log is empty.
  ///
  /// In en, this message translates to:
  /// **'No diagnostics to export.'**
  String get diagnosticsNoDiagnosticsToExport;

  /// Snackbar shown when a scrubbed diagnostics export cannot safely gather redaction terms, so no file is saved.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare a safe (scrubbed) export, so nothing was saved. Please try again, or use full detail deliberately.'**
  String get diagnosticsScrubbedExportUnavailable;

  /// Snackbar confirming the diagnostics log was exported.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics log exported.'**
  String get diagnosticsLogExported;

  /// Snackbar shown when the diagnostics export/share flow is cancelled.
  ///
  /// In en, this message translates to:
  /// **'Export cancelled.'**
  String get diagnosticsExportCancelled;

  /// Snackbar shown when diagnostics log export fails. Details are not shown in the UI.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export the diagnostics log.'**
  String get diagnosticsExportFailed;

  /// Title of the confirmation dialog for clearing the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Clear diagnostics log?'**
  String get diagnosticsClearLogTitle;

  /// Body of the confirmation dialog for clearing the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the local crash log from this device. This cannot be undone.'**
  String get diagnosticsClearLogBody;

  /// Button label that confirms clearing the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get diagnosticsClearAction;

  /// Snackbar confirming the diagnostics log was cleared.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics log cleared.'**
  String get diagnosticsLogCleared;

  /// Settings section header for diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsHeader;

  /// Introductory paragraph explaining the local diagnostics log and that it is never sent automatically.
  ///
  /// In en, this message translates to:
  /// **'When something goes wrong, the app records a technical note to a local log on this device to help diagnose the problem. It is never sent anywhere — there is no telemetry. You can export it to attach to a bug report, or clear it at any time.'**
  String get diagnosticsIntro;

  /// Section header above the recent diagnostics log entries list.
  ///
  /// In en, this message translates to:
  /// **'Recent entries'**
  String get diagnosticsRecentEntriesHeader;

  /// Title shown when the app cannot read the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the diagnostics log'**
  String get diagnosticsReadFailedTitle;

  /// Subtitle shown when the app cannot read the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'The local log may be inaccessible on this device. You can still try to export or clear it.'**
  String get diagnosticsReadFailedSubtitle;

  /// Title shown when the local diagnostics log has no records.
  ///
  /// In en, this message translates to:
  /// **'No errors recorded'**
  String get diagnosticsEmptyTitle;

  /// Subtitle shown when the local diagnostics log has no records.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been captured on this device.'**
  String get diagnosticsEmptySubtitle;

  /// Section header above diagnostics export controls.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get diagnosticsExportHeader;

  /// Title of the diagnostics export toggle that includes full unredacted detail.
  ///
  /// In en, this message translates to:
  /// **'Include full detail (may contain your content)'**
  String get diagnosticsFullDetailTitle;

  /// Subtitle explaining the default scrubbed diagnostics export mode.
  ///
  /// In en, this message translates to:
  /// **'Off by default. When off, the export removes your content, file paths, emails, and phone numbers.'**
  String get diagnosticsFullDetailSubtitle;

  /// Title of the row that exports or shares the diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Export / share log'**
  String get diagnosticsExportShareLogTitle;

  /// Subtitle for the diagnostics export row when full-detail export is enabled.
  ///
  /// In en, this message translates to:
  /// **'Shares the full, unredacted log.'**
  String get diagnosticsExportShareFullSubtitle;

  /// Subtitle for the diagnostics export row when scrubbed export is enabled.
  ///
  /// In en, this message translates to:
  /// **'Shares a scrubbed copy safe to attach to a bug report.'**
  String get diagnosticsExportShareScrubbedSubtitle;

  /// Title of the row that clears the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get diagnosticsClearLogRowTitle;

  /// Subtitle for the row that clears the local diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Delete the local crash log from this device.'**
  String get diagnosticsClearLogRowSubtitle;

  /// Title shown in the friendly crash fallback widget when a subtree fails to build.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong here'**
  String get crashFallbackTitle;

  /// Body text in the friendly crash fallback widget explaining that details were saved locally only.
  ///
  /// In en, this message translates to:
  /// **'This part of the app hit an unexpected error and recovered. The details were saved to a local diagnostics log (Settings ▸ Diagnostics) that never leaves your device.'**
  String get crashFallbackBody;

  /// Button label in the crash fallback widget after copying error details to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get crashFallbackCopied;

  /// Button label in the crash fallback widget for copying error details to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy details'**
  String get crashFallbackCopyDetails;

  /// Generic dialog dismiss button that discards the pending action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic confirm button that proceeds with the current action. Used wherever a dialog needs a neutral forward-motion label that is not specific to any one workflow.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Snackbar action that reverses the action just performed (delete, batch tag/level change).
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// Button that re-attempts a failed load.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Generic destructive action label for removing a single item (row menu, swipe action).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Row action that makes a copy of an item.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get commonDuplicate;

  /// Title given to a duplicated item: the original title followed by a ' (copy)' marker so the copy is visually distinct. {title} is untrusted user-entered text, rendered as plain text. Note: this resolves at duplicate-time and is persisted into user data, so the copy keeps the creation-locale wording thereafter.
  ///
  /// In en, this message translates to:
  /// **'{title} (copy)'**
  String commonDuplicateTitleSuffix(String title);

  /// Affirmative choice for a yes/no filter chip.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// Negative choice for a yes/no filter chip.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// Generic acknowledgement button that dismisses an informational dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Confirm button in the shared colour-picker dialog that applies the chosen colour.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// Snackbar shown when an external http/https link cannot be opened in the browser.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open link'**
  String get commonCouldntOpenLink;

  /// Label for the progression concept: used as a filter section heading and the figure-row progression-marker tooltip.
  ///
  /// In en, this message translates to:
  /// **'Progression'**
  String get commonProgression;

  /// Dance form value: contra dancing. Shown on facet chips, the command palette, and the default-form picker.
  ///
  /// In en, this message translates to:
  /// **'Contra'**
  String get commonDanceFormContra;

  /// Dance form value: English Country Dance (ECD).
  ///
  /// In en, this message translates to:
  /// **'English (ECD)'**
  String get commonDanceFormEcd;

  /// Dance form value: square dancing.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get commonDanceFormSquare;

  /// Progression value: the dance does not progress dancers to new neighbours.
  ///
  /// In en, this message translates to:
  /// **'No progression'**
  String get commonProgressionNone;

  /// Progression value: a single progression.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get commonProgressionSingle;

  /// Progression value: a double progression.
  ///
  /// In en, this message translates to:
  /// **'Double'**
  String get commonProgressionDouble;

  /// Progression value: a triple progression.
  ///
  /// In en, this message translates to:
  /// **'Triple'**
  String get commonProgressionTriple;

  /// Progression value: a quadruple progression.
  ///
  /// In en, this message translates to:
  /// **'Quadruple'**
  String get commonProgressionQuadruple;

  /// Progression value: some other progression not covered by the named options.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get commonProgressionOther;

  /// Dance status value: the dance is active/current.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonDanceStatusActive;

  /// Dance status value: the dance is deprecated (kept but discouraged).
  ///
  /// In en, this message translates to:
  /// **'Deprecated'**
  String get commonDanceStatusDeprecated;

  /// Dance status value: the dance is marked broken/unusable.
  ///
  /// In en, this message translates to:
  /// **'Broken'**
  String get commonDanceStatusBroken;

  /// Dance difficulty value: beginner level.
  ///
  /// In en, this message translates to:
  /// **'Beginner'**
  String get commonDanceLevelBeginner;

  /// Dance difficulty value: intermediate level.
  ///
  /// In en, this message translates to:
  /// **'Intermediate'**
  String get commonDanceLevelIntermediate;

  /// Dance difficulty value: advanced level.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get commonDanceLevelAdvanced;

  /// Formation shape value: duple improper.
  ///
  /// In en, this message translates to:
  /// **'Duple improper'**
  String get commonFormationDupleImproper;

  /// Formation shape value: Becket, clockwise progression (CW).
  ///
  /// In en, this message translates to:
  /// **'Becket (CW)'**
  String get commonFormationBecketCw;

  /// Formation shape value: Becket, counter-clockwise progression (CCW).
  ///
  /// In en, this message translates to:
  /// **'Becket (CCW)'**
  String get commonFormationBecketCcw;

  /// Formation shape value: duple proper.
  ///
  /// In en, this message translates to:
  /// **'Duple proper'**
  String get commonFormationDupleProper;

  /// Formation shape value: duple indecent.
  ///
  /// In en, this message translates to:
  /// **'Duple indecent'**
  String get commonFormationDupleIndecent;

  /// Formation shape value: triple minor.
  ///
  /// In en, this message translates to:
  /// **'Triple minor'**
  String get commonFormationTripleMinor;

  /// Formation shape value: three-face-three.
  ///
  /// In en, this message translates to:
  /// **'Three-face-three'**
  String get commonFormationThreeFaceThree;

  /// Formation shape value: four-face-four.
  ///
  /// In en, this message translates to:
  /// **'Four-face-four'**
  String get commonFormationFourFaceFour;

  /// Formation shape value: circle mixer.
  ///
  /// In en, this message translates to:
  /// **'Circle mixer'**
  String get commonFormationCircleMixer;

  /// Formation shape value: Sicilian circle.
  ///
  /// In en, this message translates to:
  /// **'Sicilian circle'**
  String get commonFormationSicilianCircle;

  /// Formation shape value: scatter mixer.
  ///
  /// In en, this message translates to:
  /// **'Scatter mixer'**
  String get commonFormationScatterMixer;

  /// Formation shape value: longways.
  ///
  /// In en, this message translates to:
  /// **'Longways'**
  String get commonFormationLongways;

  /// Formation shape value: triplet.
  ///
  /// In en, this message translates to:
  /// **'Triplet'**
  String get commonFormationTriplet;

  /// Formation shape value: grid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get commonFormationGrid;

  /// Formation shape value: quadruplet (longways set for four couples).
  ///
  /// In en, this message translates to:
  /// **'Quadruplet'**
  String get commonFormationQuadruplet;

  /// Formation shape value: some other formation not covered by the named shapes.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get commonFormationOther;

  /// A formation shape label followed by its free-text detail. {shape} is a localized formation shape name; {detail} is untrusted free text entered by the user, rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'{shape} — {detail}'**
  String commonFormationWithDetail(String shape, String detail);

  /// Label indicating a dance suits mixed experience levels; used as a filter chip/section and a dance indicator chip.
  ///
  /// In en, this message translates to:
  /// **'Mixed level'**
  String get commonMixedLevel;

  /// Label for a mixer — a dance in which dancers change partners each time through the sequence (a progressive partner-changing dance), NOT an audio or kitchen mixer. Used as a dance editor checkbox label and a dance-detail indicator.
  ///
  /// In en, this message translates to:
  /// **'Mixer'**
  String get commonMixer;

  /// Tooltip on a tag chip that filters the collection to dances carrying that tag.
  ///
  /// In en, this message translates to:
  /// **'Show dances tagged “{tagName}”'**
  String commonShowDancesTaggedTooltip(String tagName);

  /// Snackbar confirming a dance was soft-deleted, quoting its title.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" deleted.'**
  String commonDeletedSnack(String title);

  /// Explanation shown for a figure that an import parser could not map to a structured move and kept verbatim. Shared by the import-gap badge tooltip, its explanation dialog body, and the figure-row Semantics label.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t parse this call — kept verbatim as a custom figure.'**
  String get importGapMessage;

  /// Title of the dialog explaining an unrecognized (import-gap or free-text) custom figure (shown when the badge is tapped).
  ///
  /// In en, this message translates to:
  /// **'Unrecognized figure'**
  String get importGapDialogTitle;

  /// Full Semantics label announced for the import-gap badge itself (screen readers): a short prefix plus the explanation, modelled as one message rather than concatenated fragments.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized figure. Couldn\'t parse this call — kept verbatim as a custom figure.'**
  String get importGapSemanticLabel;

  /// App-bar title of the Collection screen (phone layout).
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get collectionScreenTitle;

  /// Label of the floating action button that creates a new dance.
  ///
  /// In en, this message translates to:
  /// **'New dance'**
  String get collectionNewDance;

  /// Tooltip for the app-bar search button, noting its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Search (Ctrl/Cmd-K)'**
  String get collectionSearchTooltip;

  /// Tooltip for the app-bar button that enters multi-select (batch) mode.
  ///
  /// In en, this message translates to:
  /// **'Select dances'**
  String get collectionSelectDancesTooltip;

  /// Tooltip for the app-bar button that opens custom-field management.
  ///
  /// In en, this message translates to:
  /// **'Manage custom fields'**
  String get collectionManageCustomFieldsTooltip;

  /// Tooltip for the app-bar button that opens the recently-deleted dances view.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted'**
  String get collectionRecentlyDeletedTooltip;

  /// Tooltip for the sort menu button, showing the current sort option.
  ///
  /// In en, this message translates to:
  /// **'Sort by ({sortLabel})'**
  String collectionSortByTooltip(String sortLabel);

  /// Collection sort option: order by full-text search relevance.
  ///
  /// In en, this message translates to:
  /// **'Best match'**
  String get collectionSortRelevance;

  /// Collection sort option: order by dance title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get collectionSortTitle;

  /// Collection sort option: order by author name.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get collectionSortAuthor;

  /// Collection sort option: order by when the dance was added.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get collectionSortRecentlyAdded;

  /// Collection sort option: order by when the dance was last called.
  ///
  /// In en, this message translates to:
  /// **'Last called'**
  String get collectionSortLastCalled;

  /// Tooltip for the sort-direction toggle while ascending; tapping switches to descending.
  ///
  /// In en, this message translates to:
  /// **'Ascending (tap for descending)'**
  String get collectionSortAscendingTooltip;

  /// Tooltip for the sort-direction toggle while descending; tapping switches to ascending.
  ///
  /// In en, this message translates to:
  /// **'Descending (tap for ascending)'**
  String get collectionSortDescendingTooltip;

  /// Tooltip for the Collection app-bar button that groups the list by a chosen tag (category); no category is currently selected.
  ///
  /// In en, this message translates to:
  /// **'Group by category'**
  String get collectionGroupByCategoryTooltip;

  /// Tooltip for the group-by-category button when a category is active; {tag} is the selected tag name.
  ///
  /// In en, this message translates to:
  /// **'Grouped by {tag}'**
  String collectionGroupByCategoryActiveTooltip(String tag);

  /// Menu entry that clears the active category grouping and returns to the flat list.
  ///
  /// In en, this message translates to:
  /// **'No grouping'**
  String get collectionGroupByNone;

  /// Header label at the top of the group-by-category menu, above the list of tags.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get collectionGroupByHeader;

  /// Section header for the group of dances that do NOT carry the selected category tag.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get collectionGroupOther;

  /// Accessibility label announced for a category section header; {label} is the section name and {count} the number of dances in it.
  ///
  /// In en, this message translates to:
  /// **'{label}, {count, plural, =1{1 dance} other{{count} dances}}'**
  String collectionGroupSectionSemantics(String label, int count);

  /// Tooltip for the button that leaves multi-select (batch) mode.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get collectionExitSelectionTooltip;

  /// Live-region title in the selection app bar showing how many dances are selected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String collectionSelectedCount(int count);

  /// Batch action (tooltip and dialog title) for adding tags to the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Add tags'**
  String get collectionAddTags;

  /// Batch action (tooltip and dialog title) for removing tags from the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Remove tags'**
  String get collectionRemoveTags;

  /// Batch action (tooltip and dialog title) for setting the difficulty level on the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Set level'**
  String get collectionSetLevel;

  /// Label of the local collection search field.
  ///
  /// In en, this message translates to:
  /// **'Search dances'**
  String get collectionSearchFieldLabel;

  /// Hint text of the local collection search field, listing what is searched.
  ///
  /// In en, this message translates to:
  /// **'Search titles, authors, figures, notes…'**
  String get collectionSearchFieldHint;

  /// Tooltip for the button that clears the search text and all active filters.
  ///
  /// In en, this message translates to:
  /// **'Clear search and filters'**
  String get collectionClearSearchTooltip;

  /// Message shown when the collection fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load the collection.'**
  String get collectionLoadError;

  /// Snackbar confirming a dance was duplicated, quoting the copy's title.
  ///
  /// In en, this message translates to:
  /// **'Duplicated as \"{title}\".'**
  String collectionDuplicatedSnack(String title);

  /// Empty-state message shown in the results area when the collection has no dances.
  ///
  /// In en, this message translates to:
  /// **'Your collection is empty. Add or import a dance to get started — or turn on Online search above to import from an online source.'**
  String get collectionEmpty;

  /// Title of the facet filters panel when no filters are active.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get collectionFiltersTitle;

  /// Title of the facet filters panel, noting how many filters are active.
  ///
  /// In en, this message translates to:
  /// **'Filters ({count} active)'**
  String collectionFiltersActive(int count);

  /// Title of the by-phrase (Caller's Box style) filter panel when nothing is set.
  ///
  /// In en, this message translates to:
  /// **'By phrase'**
  String get collectionByPhraseTitle;

  /// Title of the by-phrase filter panel, noting how many phrase constraints are active.
  ///
  /// In en, this message translates to:
  /// **'By phrase ({count} active)'**
  String collectionByPhraseActive(int count);

  /// Title of the advanced (online toggle + boolean query builder) filter panel.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get collectionAdvancedTitle;

  /// Toggle that enables the boolean advanced-query builder.
  ///
  /// In en, this message translates to:
  /// **'Use advanced query'**
  String get collectionUseAdvancedQuery;

  /// Subtitle explaining what the advanced-query builder does.
  ///
  /// In en, this message translates to:
  /// **'Combine figures and sequences with all / any / none groups.'**
  String get collectionUseAdvancedQuerySubtitle;

  /// Result count of local dances matching the current query.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dance} other{{count} dances}}'**
  String collectionDanceCount(int count);

  /// Message shown when the local search fails.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong running the search.'**
  String get collectionSearchError;

  /// Empty-state message when the local search returns no dances.
  ///
  /// In en, this message translates to:
  /// **'No dances match your search.'**
  String get collectionNoResults;

  /// Announcement/snackbar when a batch tag or level operation changed nothing.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get collectionBatchNoChanges;

  /// Announcement/snackbar confirming tags were added to the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Tagged 1 dance} other{Tagged {count} dances}}'**
  String collectionBatchTagged(int count);

  /// Announcement/snackbar confirming tags were removed from the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Removed tags from 1 dance} other{Removed tags from {count} dances}}'**
  String collectionBatchUntagged(int count);

  /// Announcement/snackbar confirming a level was set on the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Set level on 1 dance} other{Set level on {count} dances}}'**
  String collectionBatchLevelSet(int count);

  /// Announcement/snackbar confirming the level was cleared on the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Cleared level on 1 dance} other{Cleared level on {count} dances}}'**
  String collectionBatchLevelCleared(int count);

  /// Tooltip for the overflow menu holding the additional batch-edit actions (rating, tunes, custom field).
  ///
  /// In en, this message translates to:
  /// **'More batch actions'**
  String get collectionBatchMore;

  /// Batch action (menu item and dialog title) for setting the star rating on the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Set rating'**
  String get collectionSetRating;

  /// Batch action (menu item and dialog title) for adding tunes to the selected dances (additive; never removes).
  ///
  /// In en, this message translates to:
  /// **'Add tunes'**
  String get collectionAddTunes;

  /// Batch action (menu item) for removing all tunes from the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Clear tunes'**
  String get collectionClearTunes;

  /// Batch action (menu item and dialog title) for setting or clearing one custom field across the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Edit custom field'**
  String get collectionEditCustomField;

  /// Announcement/snackbar confirming a rating was set on the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Set rating on 1 dance} other{Set rating on {count} dances}}'**
  String collectionBatchRatingSet(int count);

  /// Announcement/snackbar confirming the rating was cleared on the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Cleared rating on 1 dance} other{Cleared rating on {count} dances}}'**
  String collectionBatchRatingCleared(int count);

  /// Announcement/snackbar confirming tunes were added to the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added tunes to 1 dance} other{Added tunes to {count} dances}}'**
  String collectionBatchTunesAdded(int count);

  /// Announcement/snackbar confirming tunes were cleared from the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Cleared tunes from 1 dance} other{Cleared tunes from {count} dances}}'**
  String collectionBatchTunesCleared(int count);

  /// Announcement/snackbar confirming a custom field was set on the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated field on 1 dance} other{Updated field on {count} dances}}'**
  String collectionBatchCustomFieldSet(int count);

  /// Announcement/snackbar confirming a custom field was cleared on the given number of dances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Cleared field on 1 dance} other{Cleared field on {count} dances}}'**
  String collectionBatchCustomFieldCleared(int count);

  /// Accessible label for the per-row selection checkbox in batch mode.
  ///
  /// In en, this message translates to:
  /// **'Select {title}'**
  String collectionSelectDanceLabel(String title);

  /// Compact chip on a dance row showing how many times it has been called (× is the multiplication sign).
  ///
  /// In en, this message translates to:
  /// **'called ×{count}'**
  String collectionCalledBadge(int count);

  /// Accessible reading of the called-count chip on a dance row.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{called 1 time} other{called {count} times}}'**
  String collectionCalledBadgeSemantic(int count);

  /// Accessible label for the star-rating chip on a dance row.
  ///
  /// In en, this message translates to:
  /// **'Rating: {rating} of 5 stars'**
  String collectionRatingSemantic(int rating);

  /// Tooltip/label for a dance row's action (overflow) menu button.
  ///
  /// In en, this message translates to:
  /// **'Actions for {title}'**
  String collectionRowActionsSemantic(String title);

  /// Title of the split-pane placeholder shown when no dance is selected.
  ///
  /// In en, this message translates to:
  /// **'Select a dance'**
  String get collectionSplitEmptyTitle;

  /// Subtitle of the split-pane placeholder shown when no dance is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose a dance from the list to view its details.'**
  String get collectionSplitEmptySubtitle;

  /// Filter section heading for the dance form/type facet.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get collectionFacetType;

  /// Filter section heading for the formation facet.
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get collectionFacetFormation;

  /// Filter section heading for the dance status facet.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get collectionFacetStatus;

  /// Filter section heading for the difficulty level facet.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get collectionFacetLevel;

  /// Filter section heading for the minimum star-rating facet.
  ///
  /// In en, this message translates to:
  /// **'Minimum rating'**
  String get collectionFacetMinRating;

  /// Minimum-rating filter chip: at least {min} stars (≥ and ★ are symbols).
  ///
  /// In en, this message translates to:
  /// **'≥{min}★'**
  String collectionFacetMinRatingChip(int min);

  /// Filter section heading for the tags facet.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get collectionFacetTags;

  /// Filter section heading for the cited-source facet.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get collectionFacetSource;

  /// Filter section heading for the author/choreographer facet.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get collectionFacetAuthor;

  /// Message shown when the collection has no facets to filter by.
  ///
  /// In en, this message translates to:
  /// **'No filters available for this collection yet.'**
  String get collectionFacetNone;

  /// Button that clears all active facet filters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get collectionFacetClear;

  /// Tooltip on a selected-author chip that removes it from the author filter.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String collectionFacetRemoveAuthor(String name);

  /// Hint text of the author-filter search field.
  ///
  /// In en, this message translates to:
  /// **'Search authors…'**
  String get collectionFacetAuthorSearchHint;

  /// Text custom-field filter operator: substring match.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get collectionFacetOpContains;

  /// Text custom-field filter operator: exact match.
  ///
  /// In en, this message translates to:
  /// **'equals'**
  String get collectionFacetOpEquals;

  /// Hint text of a text custom-field filter input, naming the field.
  ///
  /// In en, this message translates to:
  /// **'Filter by {label}…'**
  String collectionFacetTextHint(String label);

  /// Number custom-field filter operator: equal to (symbol).
  ///
  /// In en, this message translates to:
  /// **'='**
  String get collectionFacetNumOpEq;

  /// Number custom-field filter operator: less than (symbol).
  ///
  /// In en, this message translates to:
  /// **'<'**
  String get collectionFacetNumOpLt;

  /// Number custom-field filter operator: greater than (symbol).
  ///
  /// In en, this message translates to:
  /// **'>'**
  String get collectionFacetNumOpGt;

  /// Number custom-field filter operator: within an inclusive range.
  ///
  /// In en, this message translates to:
  /// **'between'**
  String get collectionFacetNumOpBetween;

  /// Hint for the lower-bound input of a number 'between' filter.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get collectionFacetNumFrom;

  /// Hint for the single-value input of a number filter (=, <, >).
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get collectionFacetNumValue;

  /// Hint for the upper-bound input of a number 'between' filter.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get collectionFacetNumTo;

  /// Ordinal name of the first dance phrase (usually A1) in the by-phrase panel.
  ///
  /// In en, this message translates to:
  /// **'first phrase'**
  String get collectionByPhraseOrdinalFirst;

  /// Ordinal name of the second dance phrase (usually A2) in the by-phrase panel.
  ///
  /// In en, this message translates to:
  /// **'second phrase'**
  String get collectionByPhraseOrdinalSecond;

  /// Ordinal name of the third dance phrase (usually B1) in the by-phrase panel.
  ///
  /// In en, this message translates to:
  /// **'third phrase'**
  String get collectionByPhraseOrdinalThird;

  /// Ordinal name of the fourth dance phrase (usually B2) in the by-phrase panel.
  ///
  /// In en, this message translates to:
  /// **'fourth phrase'**
  String get collectionByPhraseOrdinalFourth;

  /// Fallback ordinal name for phrases beyond the fourth.
  ///
  /// In en, this message translates to:
  /// **'phrase {number}'**
  String collectionByPhraseOrdinalN(int number);

  /// Caption for a by-phrase row combining the ordinal name and the section label.
  ///
  /// In en, this message translates to:
  /// **'{ordinal} (usually {label})'**
  String collectionByPhraseCaption(String ordinal, String label);

  /// Accessible label for the 'figures match' input of a by-phrase row.
  ///
  /// In en, this message translates to:
  /// **'{caption}, figures match'**
  String collectionByPhraseFieldMatch(String caption);

  /// Accessible label for the 'but do not match' input of a by-phrase row.
  ///
  /// In en, this message translates to:
  /// **'{caption}, but do not match'**
  String collectionByPhraseFieldExclude(String caption);

  /// Tooltip on a chosen-move chip that removes it from a by-phrase input.
  ///
  /// In en, this message translates to:
  /// **'Remove {move} from {field}'**
  String collectionByPhraseRemoveMove(String move, String field);

  /// Accessible label for the advanced-query group match-kind dropdown (all/any/none).
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get collectionQueryMatchLabel;

  /// Advanced-query group match kind: every condition must match.
  ///
  /// In en, this message translates to:
  /// **'All of'**
  String get collectionQueryGroupAll;

  /// Advanced-query group match kind: at least one condition must match.
  ///
  /// In en, this message translates to:
  /// **'Any of'**
  String get collectionQueryGroupAny;

  /// Advanced-query group match kind: no condition may match.
  ///
  /// In en, this message translates to:
  /// **'None of'**
  String get collectionQueryGroupNone;

  /// Text after the match-kind dropdown in an advanced-query group (e.g. 'All of these conditions').
  ///
  /// In en, this message translates to:
  /// **'these conditions'**
  String get collectionQueryTheseConditions;

  /// Tooltip for the button that removes a condition group in the advanced-query builder.
  ///
  /// In en, this message translates to:
  /// **'Remove group'**
  String get collectionQueryRemoveGroup;

  /// Placeholder shown in an advanced-query group that has no conditions yet.
  ///
  /// In en, this message translates to:
  /// **'No conditions yet — add one below.'**
  String get collectionQueryEmptyGroup;

  /// Tooltip for the menu that adds a condition to an advanced-query group.
  ///
  /// In en, this message translates to:
  /// **'Add a condition'**
  String get collectionQueryAddCondition;

  /// Advanced-query condition type / row label: the dance contains a given figure.
  ///
  /// In en, this message translates to:
  /// **'Has figure'**
  String get collectionQueryHasFigure;

  /// Advanced-query 'add' menu item: a two-figure ordered sequence condition.
  ///
  /// In en, this message translates to:
  /// **'Sequence (then)'**
  String get collectionQuerySequenceThen;

  /// Advanced-query 'add' menu item: a nested group of conditions.
  ///
  /// In en, this message translates to:
  /// **'Condition group'**
  String get collectionQueryConditionGroup;

  /// Label of the advanced-query builder's add-condition menu button.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get collectionQueryAddButton;

  /// Tooltip for the button that removes a figure condition in the advanced-query builder.
  ///
  /// In en, this message translates to:
  /// **'Remove figure'**
  String get collectionQueryRemoveFigure;

  /// Label for the earlier figure of a 'then' sequence condition.
  ///
  /// In en, this message translates to:
  /// **'First'**
  String get collectionQueryThenFirst;

  /// Connector between the two figures of a 'then' sequence condition.
  ///
  /// In en, this message translates to:
  /// **'then'**
  String get collectionQueryThenConnector;

  /// Label for the later figure of a 'then' sequence condition.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get collectionQueryThenLater;

  /// Tooltip for the button that removes a 'then' sequence condition.
  ///
  /// In en, this message translates to:
  /// **'Remove sequence'**
  String get collectionQueryRemoveSequence;

  /// Button that wraps a single figure operand in a figure group.
  ///
  /// In en, this message translates to:
  /// **'Group figures'**
  String get collectionQueryGroupFigures;

  /// Accessible label for the match-kind dropdown of a figure group.
  ///
  /// In en, this message translates to:
  /// **'Figure group match'**
  String get collectionQueryFigureGroupMatch;

  /// Text after the match-kind dropdown in a figure group (e.g. 'Any of these figures').
  ///
  /// In en, this message translates to:
  /// **'of these figures'**
  String get collectionQueryOfTheseFigures;

  /// Button that collapses a single-child figure group back to one figure.
  ///
  /// In en, this message translates to:
  /// **'Single figure'**
  String get collectionQuerySingleFigure;

  /// Button that adds another figure to a figure group.
  ///
  /// In en, this message translates to:
  /// **'Add figure'**
  String get collectionQueryAddFigure;

  /// Tooltip for the button that removes a nested figure group.
  ///
  /// In en, this message translates to:
  /// **'Remove figure group'**
  String get collectionQueryRemoveFigureGroup;

  /// Default label of the move type-ahead field.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get collectionQueryMoveLabel;

  /// Default hint of the move type-ahead field, giving an example move.
  ///
  /// In en, this message translates to:
  /// **'e.g. swing'**
  String get collectionQueryMoveHint;

  /// Accessible label for the phrase-section dropdown of a figure condition.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get collectionQuerySectionLabel;

  /// Figure-condition section option meaning the figure may occur in any phrase.
  ///
  /// In en, this message translates to:
  /// **'Any section'**
  String get collectionQueryAnySection;

  /// Figure-parameter dropdown option meaning the parameter is unconstrained.
  ///
  /// In en, this message translates to:
  /// **'Any {param}'**
  String collectionQueryAnyParam(String param);

  /// Batch set-level option that clears (unsets) the level on the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Unspecified (clear)'**
  String get collectionBatchLevelUnspecified;

  /// Confirm button of the batch set-level dialog.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get collectionBatchLevelConfirm;

  /// Empty state in the batch add-tags dialog when no tags exist yet.
  ///
  /// In en, this message translates to:
  /// **'No tags yet. Create one below.'**
  String get collectionBatchTagEmptyAdd;

  /// Empty state in the batch remove-tags dialog when the selection has no tags.
  ///
  /// In en, this message translates to:
  /// **'The selected dances have no tags to remove.'**
  String get collectionBatchTagEmptyRemove;

  /// Label of the new-tag text field in the batch add-tags dialog.
  ///
  /// In en, this message translates to:
  /// **'Create a tag'**
  String get collectionCreateTagLabel;

  /// Tooltip for the button that creates the typed tag in the batch add-tags dialog.
  ///
  /// In en, this message translates to:
  /// **'Create tag'**
  String get collectionCreateTagButton;

  /// Snackbar shown when creating a tag fails.
  ///
  /// In en, this message translates to:
  /// **'Could not create tag. Try again.'**
  String get collectionCreateTagError;

  /// Confirm button of the batch add-tags dialog.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get collectionBatchTagAddConfirm;

  /// Confirm button of the batch remove-tags dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get collectionBatchTagRemoveConfirm;

  /// Text label for a star-rating option in the batch set-rating dialog (paired with the star icon; the label is the accessible name, never the star shape alone).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star} other{{count} stars}}'**
  String collectionBatchRatingStars(int count);

  /// Batch set-rating option that clears (unsets) the rating on the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Unrated (clear)'**
  String get collectionBatchRatingUnrated;

  /// Confirm button of the batch set-rating dialog.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get collectionBatchRatingConfirm;

  /// Label of the text field for typing a tune to add in the batch add-tunes dialog.
  ///
  /// In en, this message translates to:
  /// **'Add a tune'**
  String get collectionBatchTunesFieldLabel;

  /// Tooltip for the button that adds the typed tune to the pending list in the batch add-tunes dialog.
  ///
  /// In en, this message translates to:
  /// **'Add tune to list'**
  String get collectionBatchTunesAddButton;

  /// Empty state in the batch add-tunes dialog before any tune has been added to the list.
  ///
  /// In en, this message translates to:
  /// **'Type a tune name and add it to the list.'**
  String get collectionBatchTunesEmpty;

  /// Tooltip/label for removing a tune from the pending add list in the batch add-tunes dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove {tune} from list'**
  String collectionBatchTunesRemove(String tune);

  /// Confirm button of the batch add-tunes dialog.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get collectionBatchTunesConfirm;

  /// Title of the confirmation dialog for clearing all tunes from the selected dances.
  ///
  /// In en, this message translates to:
  /// **'Clear tunes?'**
  String get collectionBatchClearTunesConfirmTitle;

  /// Body of the confirmation dialog for clearing all tunes from the selected dances.
  ///
  /// In en, this message translates to:
  /// **'This removes all tunes from the selected dances. You can undo it afterwards.'**
  String get collectionBatchClearTunesConfirmBody;

  /// Confirm button of the clear-tunes confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear tunes'**
  String get collectionBatchClearTunesConfirmButton;

  /// Label of the picker for choosing which custom field to edit across the selection.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get collectionBatchCustomFieldKeyLabel;

  /// Toggle in the batch edit-custom-field dialog that clears the chosen field across the selection instead of setting a value.
  ///
  /// In en, this message translates to:
  /// **'Clear this field'**
  String get collectionBatchCustomFieldClearOption;

  /// Empty state in the batch edit-custom-field dialog when no custom field definitions exist.
  ///
  /// In en, this message translates to:
  /// **'No custom fields are defined yet.'**
  String get collectionBatchCustomFieldEmpty;

  /// Validation error when a non-numeric value is entered for a number custom field in the batch edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get collectionBatchCustomFieldNumberInvalid;

  /// Confirm button of the batch edit-custom-field dialog.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get collectionBatchCustomFieldConfirm;

  /// Placeholder shown in the figure table when a dance has no figures.
  ///
  /// In en, this message translates to:
  /// **'No figures yet.'**
  String get danceFiguresEmpty;

  /// Beat count shown at the end of a figure row and in its accessible label.
  ///
  /// In en, this message translates to:
  /// **'{beats, plural, =1{1 beat} other{{beats} beats}}'**
  String danceFigureBeats(int beats);

  /// Word inserted into a figure row's accessible label when the figure carries the progression.
  ///
  /// In en, this message translates to:
  /// **'progression'**
  String get danceFigureProgressionSemantic;

  /// Figure-row note as read into the accessible label.
  ///
  /// In en, this message translates to:
  /// **'note: {note}'**
  String danceFigureNote(String note);

  /// App-bar title of the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Dance'**
  String get danceScreenTitle;

  /// Message shown when the requested dance cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'Dance not found.'**
  String get danceNotFound;

  /// Label of the floating action button that opens the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get danceEditFab;

  /// Tooltip/menu label for the action that duplicates the current dance.
  ///
  /// In en, this message translates to:
  /// **'Duplicate dance'**
  String get danceDuplicateTooltip;

  /// Tooltip/menu label for the action that deletes the current dance.
  ///
  /// In en, this message translates to:
  /// **'Delete dance'**
  String get danceDeleteTooltip;

  /// Tooltip for the dance detail overflow (⋮) menu on narrow layouts.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get danceMoreActions;

  /// Heading of the figures section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Figures'**
  String get danceSectionFigures;

  /// Heading of the calling-notes section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Calling notes'**
  String get danceSectionCallingNotes;

  /// Heading of the walkthrough section on the dance detail screen (issue #370).
  ///
  /// In en, this message translates to:
  /// **'Walkthrough'**
  String get danceSectionWalkthrough;

  /// Heading of the tunes section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Tunes'**
  String get danceSectionTunes;

  /// Heading of the links section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get danceSectionLinks;

  /// Placeholder for a related-dance link whose target has been deleted.
  ///
  /// In en, this message translates to:
  /// **'(missing dance)'**
  String get danceMissingRelated;

  /// Heading of the published-sources section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Published sources'**
  String get danceSectionPublishedSources;

  /// Heading of the custom-fields section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get danceSectionCustomFields;

  /// Heading of the calling-history section on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Calling history'**
  String get danceSectionCallingHistory;

  /// Empty state for the calling-history section when the dance is in no program.
  ///
  /// In en, this message translates to:
  /// **'Not yet included in any program.'**
  String get danceCallingHistoryEmpty;

  /// Shown in the calling-history section when its query fails, instead of the empty state — which would otherwise claim the dance has never been called.
  ///
  /// In en, this message translates to:
  /// **'Could not load the calling history.'**
  String get danceCallingHistoryError;

  /// Accessible label for the toggle that shows canonical (undialected) figure terms.
  ///
  /// In en, this message translates to:
  /// **'Show canonical terms'**
  String get danceShowCanonicalTerms;

  /// Visible label beside the canonical-terms toggle.
  ///
  /// In en, this message translates to:
  /// **'Canonical'**
  String get danceCanonicalToggleLabel;

  /// Provenance line prefix naming where the dance came from.
  ///
  /// In en, this message translates to:
  /// **'via {source}'**
  String danceProvenanceVia(String source);

  /// Provenance source label for a manually entered dance.
  ///
  /// In en, this message translates to:
  /// **'manual entry'**
  String get danceProvenanceSourceManual;

  /// Provenance source label for a dance imported from a JSON file.
  ///
  /// In en, this message translates to:
  /// **'JSON import'**
  String get danceProvenanceSourceJson;

  /// Noun for a video link, used in its 'Open …' accessible label.
  ///
  /// In en, this message translates to:
  /// **'video'**
  String get danceLinkKindVideo;

  /// Noun for a source link, used in its 'Open …' accessible label.
  ///
  /// In en, this message translates to:
  /// **'source link'**
  String get danceLinkKindSource;

  /// Generic noun for a link (related-dance or other), used in its 'Open …' accessible label.
  ///
  /// In en, this message translates to:
  /// **'link'**
  String get danceLinkKindLink;

  /// Accessible label for a launchable link row on the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Open {kind}: {display}'**
  String danceOpenLinkSemantic(String kind, String display);

  /// Accessible label for a calling-history row that opens a program.
  ///
  /// In en, this message translates to:
  /// **'Open program: {title}, {details}'**
  String danceOpenProgramSemantic(String title, String details);

  /// First clause of the half-calling stats: times called in the first half.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Called 1 time in the first half} other{Called {count} times in the first half}}'**
  String danceHalfStatsFirstHalf(int count);

  /// Second clause of the half-calling stats: times called in the second half.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 time in the second half} other{{count} times in the second half}}'**
  String danceHalfStatsSecondHalf(int count);

  /// Optional half-calling stats clause: times the dance opened the first half.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{opened the first half 1 time} other{opened the first half {count} times}}'**
  String danceHalfStatsOpened(int count);

  /// Optional half-calling stats clause: times the dance closed the evening.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{closed the evening (last dance of the second half) 1 time} other{closed the evening (last dance of the second half) {count} times}}'**
  String danceHalfStatsClosed(int count);

  /// Accessible label wrapping the assembled half-calling stats sentence.
  ///
  /// In en, this message translates to:
  /// **'Half breakdown: {description}'**
  String danceHalfStatsSemanticLabel(String description);

  /// Fallback title for a cited source whose record has been purged.
  ///
  /// In en, this message translates to:
  /// **'(unknown source)'**
  String get danceSourceUnknown;

  /// Page locator for a source citation (p. = page).
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String danceSourcePage(String page);

  /// Number locator for a source citation (no. = number).
  ///
  /// In en, this message translates to:
  /// **'no. {number}'**
  String danceSourceNumber(String number);

  /// Accessible label for a cited source row that opens an external URL.
  ///
  /// In en, this message translates to:
  /// **'Open source link: {title}'**
  String danceOpenSourceLinkSemantic(String title);

  /// Prefix of the accessible label for a non-launchable cited source row.
  ///
  /// In en, this message translates to:
  /// **'Source: {title}'**
  String danceSourceSemanticPrefix(String title);

  /// Accessible label for a cross-reference link that opens another dance.
  ///
  /// In en, this message translates to:
  /// **'Open dance: {title}'**
  String danceOpenDanceCrossRefSemantic(String title);

  /// Action label to add the current dance to a program (tooltip, menu item, sheet title, and Perform adjust section).
  ///
  /// In en, this message translates to:
  /// **'Add to program'**
  String get commonAddToProgram;

  /// Title of the empty state shown when the user has no programs, on the Programs list and in the add-to-program sheet.
  ///
  /// In en, this message translates to:
  /// **'No programs yet'**
  String get programsEmptyTitle;

  /// Body of the empty state in the add-to-program sheet, inviting the user to create a program.
  ///
  /// In en, this message translates to:
  /// **'Create a program to start building a set list.'**
  String get programsAddToProgramEmptyBody;

  /// Button in the add-to-program sheet that creates a new program seeded with the current dance.
  ///
  /// In en, this message translates to:
  /// **'Create a new program with this dance'**
  String get programsCreateWithDance;

  /// Accessible label for a program row in the add-to-program sheet.
  ///
  /// In en, this message translates to:
  /// **'Add \"{danceTitle}\" to {programTitle}, {details}'**
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  );

  /// Confirmation snackbar after appending a dance to an existing program.
  ///
  /// In en, this message translates to:
  /// **'Added \"{danceTitle}\" to {programTitle}.'**
  String programsAddedToProgramSnack(String danceTitle, String programTitle);

  /// Label for creating a new program (list button, editor title) and the default title of a newly created program.
  ///
  /// In en, this message translates to:
  /// **'New program'**
  String get programsNewProgram;

  /// Confirmation snackbar after creating a new program seeded with a dance.
  ///
  /// In en, this message translates to:
  /// **'Created \"{programTitle}\" with \"{danceTitle}\".'**
  String programsCreatedProgramSnack(String programTitle, String danceTitle);

  /// Tooltip for the button that opens the single-dance Perform view from the dance detail screen.
  ///
  /// In en, this message translates to:
  /// **'Perform this dance'**
  String get dancePerformTooltip;

  /// Tooltip for the app-bar control that switches the active dialect mid-session, shared by the dance detail and Perform screens.
  ///
  /// In en, this message translates to:
  /// **'Switch dialect'**
  String get commonSwitchDialectTooltip;

  /// Program status label: the program is still a draft (not finalized).
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get programsStatusDraft;

  /// Program status label: the program has been finalized.
  ///
  /// In en, this message translates to:
  /// **'Finalized'**
  String get programsStatusFinalized;

  /// Program status label: the program has been performed.
  ///
  /// In en, this message translates to:
  /// **'Performed'**
  String get programsStatusPerformed;

  /// Error shown in the program editor when the program was deleted and can no longer be loaded.
  ///
  /// In en, this message translates to:
  /// **'This program no longer exists.'**
  String get programsNoLongerExists;

  /// Fallback title used for an untitled program when opening the Perform view from an unsaved draft.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get programsFallbackTitle;

  /// Fallback word used in place of a dance title when the title is unavailable, in add-dance confirmation messages.
  ///
  /// In en, this message translates to:
  /// **'dance'**
  String get programsUntitledDanceFallback;

  /// Snackbar confirming a dance was added to the program being edited.
  ///
  /// In en, this message translates to:
  /// **'Added \"{title}\".'**
  String programsAddedDanceSnack(String title);

  /// Screen-reader announcement when a dance is added to the program being edited.
  ///
  /// In en, this message translates to:
  /// **'Added {title} to program.'**
  String programsAddedDanceAnnounce(String title);

  /// Screen-reader announcement when a free-text note slot is added to the program.
  ///
  /// In en, this message translates to:
  /// **'Added note to program.'**
  String get programsAddedNoteAnnounce;

  /// Screen-reader announcement when a break slot is added to the program.
  ///
  /// In en, this message translates to:
  /// **'Added break to program.'**
  String get programsAddedBreakAnnounce;

  /// Confirmation (snackbar and screen-reader announcement) after marking every dance in the program as performed.
  ///
  /// In en, this message translates to:
  /// **'Marked all dances performed.'**
  String get programsMarkedAllPerformed;

  /// Snackbar confirming the program was saved, quoting its title.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" saved.'**
  String programsSavedSnack(String title);

  /// Snackbar shown when saving the program fails.
  ///
  /// In en, this message translates to:
  /// **'Could not save the program.'**
  String get programsSaveError;

  /// Snackbar confirming a program was duplicated, quoting the copy's title.
  ///
  /// In en, this message translates to:
  /// **'Duplicated as \"{title}\".'**
  String programsDuplicatedSnack(String title);

  /// Snackbar confirming a program was deleted, quoting its title. Paired with an Undo action.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" deleted.'**
  String programsDeletedSnack(String title);

  /// Title of the confirm dialog shown when leaving the program editor with unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get programsDiscardTitle;

  /// Body of the confirm dialog shown when leaving the program editor with unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes to this program.'**
  String get programsDiscardBody;

  /// Button that dismisses the discard-changes dialog and returns to editing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get programsKeepEditing;

  /// Button that confirms discarding unsaved program changes and leaves the editor.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get programsDiscard;

  /// Title of the dialog offering to restore an autosaved program draft from an interrupted prior session.
  ///
  /// In en, this message translates to:
  /// **'Unsaved draft'**
  String get programsDraftTitle;

  /// Body of the dialog offering to restore an autosaved program draft.
  ///
  /// In en, this message translates to:
  /// **'You have an unsaved draft for this program. Would you like to restore it?'**
  String get programsDraftBody;

  /// Button that restores the autosaved program draft into the editor.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get programsDraftRestore;

  /// Button that discards the autosaved program draft and starts from the saved program.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get programsDraftDiscard;

  /// App bar title of the program editor when editing an existing program.
  ///
  /// In en, this message translates to:
  /// **'Build program'**
  String get programsBuildProgram;

  /// Program editor tab label for the slot-building view.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get programsBuildTab;

  /// Program editor tab label for the programming matrix view.
  ///
  /// In en, this message translates to:
  /// **'Matrix'**
  String get programsMatrixTab;

  /// Tooltip for the button that opens the Perform view for the whole program.
  ///
  /// In en, this message translates to:
  /// **'Perform this program'**
  String get programsPerformTooltip;

  /// Tooltip for the app-bar action that marks every dance in the program as performed.
  ///
  /// In en, this message translates to:
  /// **'Mark all performed'**
  String get programsMarkAllPerformedTooltip;

  /// Label of the save button when the program has unsaved changes; the asterisk marks the dirty state.
  ///
  /// In en, this message translates to:
  /// **'Save *'**
  String get programsSaveDirty;

  /// Generic Save button label.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Accessible label for the progress spinner shown while a program loads in the editor.
  ///
  /// In en, this message translates to:
  /// **'Loading program'**
  String get programsLoading;

  /// Message shown in the program editor when the program fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load the program.'**
  String get programsLoadError;

  /// Placeholder row title in the programming matrix for a slot whose referenced dance was deleted.
  ///
  /// In en, this message translates to:
  /// **'(deleted dance)'**
  String get programsDeletedDanceFallback;

  /// Section heading above the list of program slots in the editor.
  ///
  /// In en, this message translates to:
  /// **'Slots'**
  String get programsSlotsLabel;

  /// Button that opens the dance picker to add a dance slot to the program.
  ///
  /// In en, this message translates to:
  /// **'Add dance'**
  String get programsAddDanceButton;

  /// Button that adds a free-text note or break slot to the program.
  ///
  /// In en, this message translates to:
  /// **'Add note / break'**
  String get programsAddNoteBreakButton;

  /// Button that inserts a break slot into the program.
  ///
  /// In en, this message translates to:
  /// **'Insert break'**
  String get programsInsertBreakButton;

  /// Title of the bottom sheet for picking a dance to add to the program.
  ///
  /// In en, this message translates to:
  /// **'Add a dance'**
  String get programsAddADanceSheetTitle;

  /// Generic Close button/tooltip label.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Placeholder shown for the event date field when no date has been chosen.
  ///
  /// In en, this message translates to:
  /// **'No date set'**
  String get programsNoDateSet;

  /// Field label for the program title in the editor.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get programsTitleLabel;

  /// Hint text for the program title field in the editor.
  ///
  /// In en, this message translates to:
  /// **'e.g. Friday Night Contra'**
  String get programsTitleHint;

  /// Validation message shown when the program title field is left empty.
  ///
  /// In en, this message translates to:
  /// **'A title is required.'**
  String get programsTitleRequired;

  /// Field label for the program's event date in the editor.
  ///
  /// In en, this message translates to:
  /// **'Event date'**
  String get programsEventDateLabel;

  /// Button to pick the program's event date when none is set.
  ///
  /// In en, this message translates to:
  /// **'Set date'**
  String get programsSetDate;

  /// Button to change the program's already-set event date.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get programsChangeDate;

  /// Tooltip for the button that clears the program's event date.
  ///
  /// In en, this message translates to:
  /// **'Clear event date'**
  String get programsClearEventDate;

  /// Field label for the program's venue in the editor.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get programsVenueLabel;

  /// Hint text for the program venue field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Grange Hall'**
  String get programsVenueHint;

  /// Shown in the program editor's simple (free-text) venue mode when the program is also linked to a saved venue; explains the link is preserved and how to view it.
  ///
  /// In en, this message translates to:
  /// **'Also linked to saved venue: {venueName}. Turn on reusable venues in Settings to view or change it.'**
  String programsVenueLinkedHint(String venueName);

  /// Fallback name used in programsVenueLinkedHint when the linked venue's display name is unavailable.
  ///
  /// In en, this message translates to:
  /// **'a saved venue'**
  String get programsVenueLinkedHintFallbackName;

  /// Shown in the program editor's enriched (picker) venue mode when the program has legacy free-text but no linked venue yet; invites linking while assuring the typed text is preserved.
  ///
  /// In en, this message translates to:
  /// **'Previously entered venue: “{venueText}”. Link a saved venue below to use reusable details — your typed venue is kept.'**
  String programsVenueLegacyTextHint(String venueText);

  /// Field label for the program's band in the editor.
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get programsBandLabel;

  /// Hint text for the program band field.
  ///
  /// In en, this message translates to:
  /// **'e.g. The Fiddleheads'**
  String get programsBandHint;

  /// Field label for the program's caller in the editor.
  ///
  /// In en, this message translates to:
  /// **'Caller'**
  String get programsCallerLabel;

  /// Hint text for the program caller field.
  ///
  /// In en, this message translates to:
  /// **'Host caller for the event'**
  String get programsCallerHint;

  /// Field label for the program's intended dancer level in the editor.
  ///
  /// In en, this message translates to:
  /// **'Dancer level'**
  String get programsDancerLevelLabel;

  /// Hint text for the program dancer-level field.
  ///
  /// In en, this message translates to:
  /// **'e.g. All welcome, Experienced'**
  String get programsDancerLevelHint;

  /// Field label for the program's free-form notes in the editor.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get programsNotesLabel;

  /// Field label for the program status dropdown in the editor.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get programsStatusFieldLabel;

  /// Title of the toggle that hides alternate (ALT) slots from the exported set list.
  ///
  /// In en, this message translates to:
  /// **'Hide alternates in set list'**
  String get programsHideAlternatesTitle;

  /// Explanatory subtitle for the hide-alternates toggle in the program editor.
  ///
  /// In en, this message translates to:
  /// **'Omits ALT slots from the summary, PDF, and exported set list. The builder still shows every slot.'**
  String get programsHideAlternatesSubtitle;

  /// Count of non-blocking validation warnings shown on the program editor's warnings card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 warning} other{{count} warnings}}'**
  String programsWarningCount(int count);

  /// Title of the dialog for adding a free-text note or break slot to the program.
  ///
  /// In en, this message translates to:
  /// **'Add note or break'**
  String get programsAddNoteBreakDialogTitle;

  /// Field label for the free-text note/break input in the add-note dialog.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get programsFreeTextLabel;

  /// Hint text for the free-text note/break input.
  ///
  /// In en, this message translates to:
  /// **'e.g. Break, waltz, announcement'**
  String get programsFreeTextHint;

  /// Generic Add button label.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// Title of the Programs list screen and its navigation destination.
  ///
  /// In en, this message translates to:
  /// **'Programs'**
  String get programsTitle;

  /// Programs list sort option: order alphabetically by program title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get programsSortTitle;

  /// Programs list sort option: order by most recently updated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get programsSortRecentlyUpdated;

  /// Programs list sort option: order by the program's event date.
  ///
  /// In en, this message translates to:
  /// **'Event date'**
  String get programsSortEventDate;

  /// Tooltip for the Programs list sort menu, showing the active sort option.
  ///
  /// In en, this message translates to:
  /// **'Sort by ({label})'**
  String programsSortByTooltip(String label);

  /// Error message shown when the Programs list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load your programs.'**
  String get programsListLoadError;

  /// Body of the empty state on the Programs list, shown when the user has no programs.
  ///
  /// In en, this message translates to:
  /// **'Build set lists for your events here. Create your first program to get started.'**
  String get programsListEmptyBody;

  /// Count of programs shown above the Programs list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 program} other{{count} programs}}'**
  String programsCount(int count);

  /// App bar title of the read-only program summary screen.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get programsSummaryTitle;

  /// Button that opens the program builder from the summary screen.
  ///
  /// In en, this message translates to:
  /// **'Edit program'**
  String get programsEditProgram;

  /// Message shown on the summary screen when the program can no longer be loaded.
  ///
  /// In en, this message translates to:
  /// **'This program is no longer available.'**
  String get programsSummaryUnavailable;

  /// Tooltip on the disabled Perform action explaining a program needs at least one slot before it can be performed.
  ///
  /// In en, this message translates to:
  /// **'Add at least one slot to perform this program'**
  String get programsPerformDisabledTooltip;

  /// Summary row showing the program's band.
  ///
  /// In en, this message translates to:
  /// **'Band: {band}'**
  String programsSummaryBand(String band);

  /// Summary row showing the program's caller.
  ///
  /// In en, this message translates to:
  /// **'Caller: {caller}'**
  String programsSummaryCaller(String caller);

  /// Summary row showing the program's intended dancer level.
  ///
  /// In en, this message translates to:
  /// **'Level: {level}'**
  String programsSummaryLevel(String level);

  /// Heading of the program's set list, with the number of slots.
  ///
  /// In en, this message translates to:
  /// **'Set list ({count})'**
  String programsSetListHeader(int count);

  /// Empty state shown under the set list heading when a program has no slots.
  ///
  /// In en, this message translates to:
  /// **'No slots yet — open the builder to add dances.'**
  String get programsSummaryEmptySetList;

  /// Secondary metadata on a set-list slot naming a guest caller for that slot.
  ///
  /// In en, this message translates to:
  /// **'Guest: {caller}'**
  String programsSummaryGuest(String caller);

  /// Planned duration in minutes for a program slot (abbreviated).
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String programsPlannedMinutes(int minutes);

  /// Short badge marking an alternate (ALT) slot in a set list.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get programsAltBadge;

  /// Fallback shown for a set-list slot whose referenced dance can no longer be found.
  ///
  /// In en, this message translates to:
  /// **'Dance unavailable'**
  String get programsDanceUnavailable;

  /// Per-slot caller note shown as secondary metadata on a set-list dance row.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String programsSummaryNote(String note);

  /// Accessible prefix identifying an alternate (ALT) dance slot by title in the set list.
  ///
  /// In en, this message translates to:
  /// **'Alternate: {title}'**
  String programsSummaryAlternateSemantic(String title);

  /// Accessible label indicating a set-list slot has been marked performed.
  ///
  /// In en, this message translates to:
  /// **'Performed'**
  String get programsPerformed;

  /// Count of slots in a program, shown on the Programs list tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 slot} other{{count} slots}}'**
  String programsSlotCount(int count);

  /// Fallback title for a free-text program slot that has no text yet.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get programsSlotNoteFallback;

  /// Empty state shown in the program slot list editor when a program has no slots.
  ///
  /// In en, this message translates to:
  /// **'No slots yet. Add a dance or a note to get started.'**
  String get programsSlotEditorEmpty;

  /// Accessibility announcement after a cut slot is pasted into a new position.
  ///
  /// In en, this message translates to:
  /// **'Slot moved.'**
  String get programsSlotMoved;

  /// Accessibility announcement after a slot is moved up one position.
  ///
  /// In en, this message translates to:
  /// **'Slot moved up.'**
  String get programsSlotMovedUp;

  /// Accessibility announcement after a slot is moved down one position.
  ///
  /// In en, this message translates to:
  /// **'Slot moved down.'**
  String get programsSlotMovedDown;

  /// Banner shown while a program slot is cut, prompting the user to paste it.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is cut — tap Paste to place it.'**
  String programsSlotCutBanner(String name);

  /// Accessible label for the paste affordance shown before the first program slot.
  ///
  /// In en, this message translates to:
  /// **'Paste before first slot'**
  String get programsPasteBeforeFirst;

  /// Accessible label for the paste affordance shown after a given program slot.
  ///
  /// In en, this message translates to:
  /// **'Paste after {title}'**
  String programsPasteAfter(String title);

  /// Label for the compact paste button shown between slots during a cut.
  ///
  /// In en, this message translates to:
  /// **'Paste here'**
  String get programsPasteHere;

  /// Accessibility announcement after a slot is changed from alternate to primary.
  ///
  /// In en, this message translates to:
  /// **'Marked as primary.'**
  String get programsMarkedPrimary;

  /// Accessibility announcement after a slot is changed from primary to alternate.
  ///
  /// In en, this message translates to:
  /// **'Marked as alternate.'**
  String get programsMarkedAlternate;

  /// Accessibility announcement after a slot is marked performed.
  ///
  /// In en, this message translates to:
  /// **'Marked performed.'**
  String get programsMarkedPerformed;

  /// Accessibility announcement after a slot's performed mark is cleared.
  ///
  /// In en, this message translates to:
  /// **'Performed mark cleared.'**
  String get programsPerformedCleared;

  /// Accessibility announcement after a slot is removed from the program.
  ///
  /// In en, this message translates to:
  /// **'Removed {name}.'**
  String programsRemovedSlot(String name);

  /// Ordinal marker shown for an alternate slot instead of a running-order number.
  ///
  /// In en, this message translates to:
  /// **'ALT'**
  String get programsAltOrdinal;

  /// Accessible label on the drag handle used to reorder a program slot.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder {title}'**
  String programsDragToReorder(String title);

  /// Tooltip for the button that moves a program slot up one position.
  ///
  /// In en, this message translates to:
  /// **'Move {title} up'**
  String programsMoveSlotUp(String title);

  /// Tooltip for the button that moves a program slot down one position.
  ///
  /// In en, this message translates to:
  /// **'Move {title} down'**
  String programsMoveSlotDown(String title);

  /// Tooltip for the button that cuts a program slot for repositioning.
  ///
  /// In en, this message translates to:
  /// **'Cut {title}'**
  String programsCutSlot(String title);

  /// Tooltip for the overflow menu offering more actions on a program slot.
  ///
  /// In en, this message translates to:
  /// **'More actions for {title}'**
  String programsMoreActionsForSlot(String title);

  /// Overflow menu item to edit a program slot.
  ///
  /// In en, this message translates to:
  /// **'Edit slot'**
  String get programsEditSlotMenu;

  /// Overflow menu item to change an alternate slot into a primary slot.
  ///
  /// In en, this message translates to:
  /// **'Make primary'**
  String get programsMakePrimaryMenu;

  /// Overflow menu item to change a primary slot into an alternate slot.
  ///
  /// In en, this message translates to:
  /// **'Mark as alternate'**
  String get programsMarkAlternateMenu;

  /// Overflow menu item to clear a slot's performed mark.
  ///
  /// In en, this message translates to:
  /// **'Clear performed'**
  String get programsClearPerformedMenu;

  /// Overflow menu item to mark a slot as performed.
  ///
  /// In en, this message translates to:
  /// **'Mark performed'**
  String get programsMarkPerformedMenu;

  /// Overflow menu item to remove a slot from the program.
  ///
  /// In en, this message translates to:
  /// **'Remove slot'**
  String get programsRemoveSlotMenu;

  /// Validation error when a free-text program slot is left empty.
  ///
  /// In en, this message translates to:
  /// **'Enter some text for this slot.'**
  String get programsSlotTextRequiredError;

  /// Validation error when planned minutes is not a whole number of zero or more.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number ≥ 0.'**
  String get programsWholeNumberError;

  /// Title of the dialog for editing a dance program slot.
  ///
  /// In en, this message translates to:
  /// **'Edit dance slot'**
  String get programsEditDanceSlotTitle;

  /// Title of the dialog for editing a free-text (note) program slot.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get programsEditNoteTitle;

  /// Text field label for an optional per-slot caller note on a dance slot.
  ///
  /// In en, this message translates to:
  /// **'Caller note (optional)'**
  String get programsCallerNoteLabel;

  /// Hint text for the optional caller-note field on a dance slot.
  ///
  /// In en, this message translates to:
  /// **'e.g. teach the hey first'**
  String get programsCallerNoteHint;

  /// Text field label for an optional guest caller on a program slot.
  ///
  /// In en, this message translates to:
  /// **'Guest caller (optional)'**
  String get programsGuestCallerLabel;

  /// Text field label for the optional planned minutes on a program slot.
  ///
  /// In en, this message translates to:
  /// **'Planned minutes (optional)'**
  String get programsPlannedMinutesLabel;

  /// Checkbox label marking a program slot as an alternate dance.
  ///
  /// In en, this message translates to:
  /// **'Alternate dance'**
  String get programsAlternateDanceTitle;

  /// Checkbox helper text explaining that an alternate slot is indented under the slot above.
  ///
  /// In en, this message translates to:
  /// **'Renders indented under the slot above it.'**
  String get programsAlternateDanceSubtitle;

  /// Generic confirmation button label for finishing an edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Container semantics label for the programming matrix, announcing its size (dances by moves). moveCount is plural-aware since hiding columns (#669) can bring it down to 1.
  ///
  /// In en, this message translates to:
  /// **'Programming matrix: {danceCount} dances by {moveCount, plural, =1{1 move} other{{moveCount} moves}}'**
  String programsMatrixSemanticLabel(int danceCount, int moveCount);

  /// Caption noting free-text slots (breaks, notes) that are excluded from the dances-only matrix.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 free-text slot} other{{count} free-text slots}} (breaks, notes) omitted — the matrix shows dances only.'**
  String programsMatrixOmittedCaption(int count);

  /// Screen-reader label for a matrix column header identifying a move by name.
  ///
  /// In en, this message translates to:
  /// **'Move: {label}'**
  String programsMatrixMoveHeaderSemantic(String label);

  /// Accessible label/tooltip for the button on a matrix move column header that hides that column from the on-screen matrix (#669). Always focusable/hit-testable, not hover-only.
  ///
  /// In en, this message translates to:
  /// **'Hide {label} column'**
  String programsMatrixHideColumnSemantic(String label);

  /// Accessible label/tooltip for the control (next to the matrix PDF-export button) that restores every column hidden via the per-column hide glyph (#669).
  ///
  /// In en, this message translates to:
  /// **'Show all columns'**
  String get programsMatrixShowAllColumnsSemantic;

  /// Screen-reader label for a matrix row header identifying a dance, whether it is an alternate, and which program half it belongs to.
  ///
  /// In en, this message translates to:
  /// **'{alt, select, yes{{half, select, first{Alternate dance: {title}, first half} second{Alternate dance: {title}, second half} other{Alternate dance: {title}}}} other{{half, select, first{Dance: {title}, first half} second{Dance: {title}, second half} other{Dance: {title}}}}}'**
  String programsMatrixRowHeaderSemantic(String title, String alt, String half);

  /// Short program-half badge label (1st or 2nd half).
  ///
  /// In en, this message translates to:
  /// **'{half, select, first{1st} other{2nd}}'**
  String programsMatrixHalfShort(String half);

  /// Header label for the matrix's pinned formation column (#663), naming what the column shows.
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get programsMatrixFormationColumnHeader;

  /// Screen-reader label pairing a dance with its formation, used by the matrix's pinned formation cell and appended to the compact-view dance chip's identity so formation is announced without folding it into the existing qualified-title message.
  ///
  /// In en, this message translates to:
  /// **'{dance}, formation: {label}'**
  String programsMatrixFormationSemantic(String dance, String label);

  /// Screen-reader label for a matrix cell: whether a dance uses a move, and whether that use collides with a strictly-adjacent dance (same figure in the same phrase), is the move's program debut, and/or the dance's opening figure.
  ///
  /// In en, this message translates to:
  /// **'{dance}, {move}: {present, select, no{not present} other{present{collision, select, yes{, repeats in the same phrase as an adjacent dance} other{}}{debut, select, yes{, introduced here} other{}}{first, select, yes{, dance\'s first figure} other{}}}}'**
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String collision,
    String debut,
    String first,
  );

  /// Dance name with its alternate-dance and program-half qualifiers, used by the compact matrix dance chip's screen-reader label.
  ///
  /// In en, this message translates to:
  /// **'{alt, select, yes{{half, select, first{{title} (alternate dance, first half)} second{{title} (alternate dance, second half)} other{{title} (alternate dance)}}} other{{half, select, first{{title} (first half)} second{{title} (second half)} other{{title}}}}}'**
  String programsMatrixChipQualifiedTitle(
    String title,
    String alt,
    String half,
  );

  /// Screen-reader label for a compact-matrix move header, stating how many of the program's dances use the move.
  ///
  /// In en, this message translates to:
  /// **'Move: {label}, used in {count} of {total} dances'**
  String programsMatrixMoveUsedInSemantic(String label, int count, int total);

  /// Compact count shown next to a move in the compact matrix (uses / total dances).
  ///
  /// In en, this message translates to:
  /// **'{count} of {total}'**
  String programsMatrixNOfTotal(int count, int total);

  /// Compact matrix message when the program's dances carry no comparable structured moves.
  ///
  /// In en, this message translates to:
  /// **'None of these dances have structured figures yet, so there are no moves to compare.'**
  String get programsMatrixNoComparableMoves;

  /// Section header in the compact matrix for moves shared by two or more dances.
  ///
  /// In en, this message translates to:
  /// **'Repeated moves'**
  String get programsMatrixRepeatedMovesHeader;

  /// Subtitle under the compact matrix 'Repeated moves' section header.
  ///
  /// In en, this message translates to:
  /// **'Moves shared across two or more dances, most-repeated first.'**
  String get programsMatrixRepeatedMovesSubtitle;

  /// Compact matrix note shown when no move is shared across dances.
  ///
  /// In en, this message translates to:
  /// **'No moves repeat across these dances — every move below is used by a single dance.'**
  String get programsMatrixNoRepeatsNote;

  /// Section header in the compact matrix for moves used by exactly one dance.
  ///
  /// In en, this message translates to:
  /// **'Used once'**
  String get programsMatrixUsedOnceHeader;

  /// Matrix legend label for the star marker: the move's first appearance in program order.
  ///
  /// In en, this message translates to:
  /// **'Introduced here'**
  String get programsMatrixLegendIntroduced;

  /// Matrix legend label for the flag marker: the move a dance opens with.
  ///
  /// In en, this message translates to:
  /// **'Dance\'s first figure'**
  String get programsMatrixLegendFirstFigure;

  /// Matrix legend label for the check marker: the dance uses the move.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get programsMatrixLegendPresent;

  /// Matrix legend label for the alert marker: the move repeats in the same phrase (A1/A2/B1/B2…) as a strictly-adjacent dance in the program.
  ///
  /// In en, this message translates to:
  /// **'Same phrase as adjacent dance'**
  String get programsMatrixLegendCollision;

  /// Title of the matrix empty state shown when no dance has structured figures.
  ///
  /// In en, this message translates to:
  /// **'No structured figures yet'**
  String get programsMatrixEmptyTitle;

  /// Body of the matrix empty state explaining the matrix populates as dances gain structured figures.
  ///
  /// In en, this message translates to:
  /// **'The matrix fills in automatically as the program’s dances gain structured figures.'**
  String get programsMatrixEmptyBody;

  /// App bar title for the single-dance Perform (large-print performance) view.
  ///
  /// In en, this message translates to:
  /// **'Perform'**
  String get performTitle;

  /// Tooltip on the button that closes the Perform view and returns to the previous screen.
  ///
  /// In en, this message translates to:
  /// **'Exit performance view'**
  String get performExitTooltip;

  /// Title of the confirmation dialog shown before leaving the Perform view, so a stray tap or system back does not drop the caller out mid-program.
  ///
  /// In en, this message translates to:
  /// **'Exit Perform?'**
  String get performExitTitle;

  /// Body text of the exit-confirmation dialog, reassuring the caller that their slot position and elapsed clock are preserved on re-entry.
  ///
  /// In en, this message translates to:
  /// **'Leave the performance view? Your place and the running clock are kept, so you can resume where you left off.'**
  String get performExitBody;

  /// Button that dismisses the exit-confirmation dialog and stays in the Perform view.
  ///
  /// In en, this message translates to:
  /// **'Keep performing'**
  String get performExitCancel;

  /// Button that confirms leaving the Perform view from the exit-confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get performExitConfirm;

  /// Label for the tap-tempo metronome, used both as the toolbar tooltip and the metronome sheet heading.
  ///
  /// In en, this message translates to:
  /// **'Tap tempo'**
  String get performTapTempo;

  /// Numeric tempo readout in the tap-tempo metronome (beats per minute, abbreviated).
  ///
  /// In en, this message translates to:
  /// **'{bpm} BPM'**
  String performBpmReadout(int bpm);

  /// Metronome readout and tap-target label shown before any tempo has been set.
  ///
  /// In en, this message translates to:
  /// **'Tap to set tempo'**
  String get performTapToSetTempo;

  /// Spoken (screen-reader) form of the current tempo in the tap-tempo metronome.
  ///
  /// In en, this message translates to:
  /// **'{bpm} beats per minute'**
  String performBpmSemantic(int bpm);

  /// Screen-reader description of the tap-tempo readout before any tempo is set.
  ///
  /// In en, this message translates to:
  /// **'No tempo set yet. Tap the target to set a tempo.'**
  String get performNoTempoSemantic;

  /// Accessibility tap hint for the tap-tempo target (what happens on tap).
  ///
  /// In en, this message translates to:
  /// **'record a beat'**
  String get performRecordBeatHint;

  /// Helper text under the tap-tempo readout once a tempo is set.
  ///
  /// In en, this message translates to:
  /// **'Keep tapping to refine · Reset to start over'**
  String get performTapRefineHint;

  /// Helper text under the tap-tempo target before enough taps are recorded.
  ///
  /// In en, this message translates to:
  /// **'Tap at least twice in time with the beat'**
  String get performTapTwiceHint;

  /// Button that clears the tapped tempo in the tap-tempo metronome.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get performResetTempo;

  /// Fallback label for a program slot with no dance and no text.
  ///
  /// In en, this message translates to:
  /// **'Untitled slot'**
  String get performUntitledSlot;

  /// Accessibility announcement after marking the current slot performed in the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Marked {label} performed'**
  String performMarkedPerformedAnnounce(String label);

  /// Accessibility announcement after clearing the current slot's performed mark in the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Cleared performed mark'**
  String get performClearedPerformedAnnounce;

  /// Accessibility announcement after reordering a slot in the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Moved {label} to position {position}'**
  String performMovedToPosition(String label, int position);

  /// Generic fallback word for an inserted dance whose title is unavailable, used in an announcement.
  ///
  /// In en, this message translates to:
  /// **'dance'**
  String get performDanceFallback;

  /// Accessibility announcement after inserting a dance into the program from the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Inserted {title}'**
  String performInsertedAnnounce(String title);

  /// Accessibility announcement after adding an ad-hoc note/break in the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Added note'**
  String get performAddedNoteAnnounce;

  /// Heading of the search picker sheet for inserting a dance during Perform mode.
  ///
  /// In en, this message translates to:
  /// **'Insert a dance'**
  String get performInsertADance;

  /// Heading of the Perform-mode adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Adjust program'**
  String get performAdjustProgram;

  /// Section title in the adjust sheet for the currently-performing slot.
  ///
  /// In en, this message translates to:
  /// **'Current slot'**
  String get performCurrentSlotSection;

  /// Toggle button label shown when the current slot is already marked performed.
  ///
  /// In en, this message translates to:
  /// **'Performed — tap to clear'**
  String get performPerformedTapToClear;

  /// Section title in the adjust sheet for reordering the not-yet-performed slots.
  ///
  /// In en, this message translates to:
  /// **'Reorder remaining slots'**
  String get performReorderSection;

  /// Empty state in the adjust sheet when there are fewer than two remaining slots to reorder.
  ///
  /// In en, this message translates to:
  /// **'No later slots to reorder.'**
  String get performNoLaterSlots;

  /// Button that opens the search picker to insert a dance in the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'Insert dance from search'**
  String get performInsertDanceFromSearch;

  /// Text field label for an ad-hoc note or break added during Perform mode.
  ///
  /// In en, this message translates to:
  /// **'Ad-hoc note / break'**
  String get performAdHocNoteLabel;

  /// Hint text for the ad-hoc note / break field in the adjust sheet.
  ///
  /// In en, this message translates to:
  /// **'e.g. Waltz, announcements'**
  String get performAdHocNoteHint;

  /// Button that adds the typed ad-hoc note/break as a new slot.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get performAddNote;

  /// Count of alternate dances under a slot, shown as a reorder-row subtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 alternate} other{{count} alternates}}'**
  String performAlternatesCount(int count);

  /// Tooltip for the button that moves a program slot up in the adjust sheet reorder list.
  ///
  /// In en, this message translates to:
  /// **'Move \"{label}\" up'**
  String performMoveLabelUp(String label);

  /// Tooltip for the button that moves a program slot down in the adjust sheet reorder list.
  ///
  /// In en, this message translates to:
  /// **'Move \"{label}\" down'**
  String performMoveLabelDown(String label);

  /// Position label/announcement for the current program slot during performance.
  ///
  /// In en, this message translates to:
  /// **'Slot {current} of {total}'**
  String performSlotPosition(int current, int total);

  /// Screen-reader announcement when swapping to show a different alternate slot.
  ///
  /// In en, this message translates to:
  /// **'Showing {label}'**
  String performShowingSlot(String label);

  /// Screen-reader announcement after undoing a live program adjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment undone'**
  String get performAdjustmentUndone;

  /// Snackbar message shown after applying a live program adjustment.
  ///
  /// In en, this message translates to:
  /// **'Program adjusted.'**
  String get performProgramAdjustedSnack;

  /// Screen-reader announcement after applying a live program adjustment.
  ///
  /// In en, this message translates to:
  /// **'Program adjusted'**
  String get performProgramAdjustedAnnounce;

  /// Empty-state body shown when a program opened in perform mode has no slots.
  ///
  /// In en, this message translates to:
  /// **'This program has no slots.'**
  String get performNoSlots;

  /// Tooltip for the button that opens the jump-to-slot list in perform mode.
  ///
  /// In en, this message translates to:
  /// **'Jump to slot'**
  String get performJumpToSlot;

  /// Tooltip for the button that swaps in an alternate dance for the current slot.
  ///
  /// In en, this message translates to:
  /// **'Show alternate'**
  String get performShowAlternate;

  /// Tooltip for the button that navigates to the previous program slot.
  ///
  /// In en, this message translates to:
  /// **'Previous slot'**
  String get performPreviousSlot;

  /// Tooltip for the button that navigates to the next program slot.
  ///
  /// In en, this message translates to:
  /// **'Next slot'**
  String get performNextSlot;

  /// Tooltip for the button that resumes the paused performance timers.
  ///
  /// In en, this message translates to:
  /// **'Resume timers'**
  String get performResumeTimers;

  /// Tooltip for the button that pauses the running performance timers.
  ///
  /// In en, this message translates to:
  /// **'Pause timers'**
  String get performPauseTimers;

  /// Screen-reader label for the perform-mode timing line: elapsed program time, elapsed slot time, and optional planned length, over-plan cue, and paused state.
  ///
  /// In en, this message translates to:
  /// **'Program time {programTime}, slot time {slotTime}{hasPlanned, select, yes{, planned {planned, plural, =1{1 minute} other{{planned} minutes}}} other{}}{over, select, yes{, over planned} other{}}{paused, select, yes{, paused} other{}}'**
  String performTimingSemantic(
    String programTime,
    String slotTime,
    String hasPlanned,
    int planned,
    String over,
    String paused,
  );

  /// Visible short label for a slot's planned length in minutes on the perform-mode timing line.
  ///
  /// In en, this message translates to:
  /// **'planned {planned} min'**
  String performPlannedMin(int planned);

  /// Visible suffix (with a leading space) shown after the planned-minutes label when the current slot has run over its planned length.
  ///
  /// In en, this message translates to:
  /// **' over'**
  String get performOverSuffix;

  /// Section title above a dance's calling notes on the perform-mode card.
  ///
  /// In en, this message translates to:
  /// **'Calling notes'**
  String get performCallingNotes;

  /// Title of the perform-mode walkthrough overlay/panel and its section heading.
  ///
  /// In en, this message translates to:
  /// **'Walkthrough'**
  String get performWalkthrough;

  /// Tooltip, overflow-menu label and accessible name for the perform-mode toggle that shows/hides the dedicated walkthrough overlay (issue #370).
  ///
  /// In en, this message translates to:
  /// **'Show walkthrough'**
  String get performShowWalkthrough;

  /// Empty-state text shown in the perform-mode walkthrough overlay when the current dance has no walkthrough written.
  ///
  /// In en, this message translates to:
  /// **'No walkthrough for this dance.'**
  String get performWalkthroughEmpty;

  /// Empty-state text shown on the perform-mode card when a dance has no figures.
  ///
  /// In en, this message translates to:
  /// **'No figures yet.'**
  String get performNoFigures;

  /// Tooltip for the button that decreases the perform-mode card text size.
  ///
  /// In en, this message translates to:
  /// **'Decrease text size'**
  String get performDecreaseTextSize;

  /// Tooltip for the button that increases the perform-mode card text size.
  ///
  /// In en, this message translates to:
  /// **'Increase text size'**
  String get performIncreaseTextSize;

  /// Accessible name/tooltip for the perform-mode toggle that shows canonical (non-dialect) figure terms.
  ///
  /// In en, this message translates to:
  /// **'Show canonical terms'**
  String get performShowCanonicalTerms;

  /// Tooltip/accessible name for the perform-mode AppBar overflow menu button that reveals the secondary actions collapsed on narrow screens (issue #433).
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get performMoreActions;

  /// Label for the perform-mode auto-size toggle when it appears as an item inside the AppBar overflow menu on narrow screens (issue #433).
  ///
  /// In en, this message translates to:
  /// **'Auto-size text to screen'**
  String get performAutoSizeMenuLabel;

  /// Tooltip for the perform-mode auto-size toggle when auto-size is currently on.
  ///
  /// In en, this message translates to:
  /// **'Auto-size on — tap for manual text size'**
  String get performAutoSizeOnTooltip;

  /// Tooltip for the perform-mode auto-size toggle when auto-size is currently off.
  ///
  /// In en, this message translates to:
  /// **'Auto-size off — tap to fit text to screen'**
  String get performAutoSizeOffTooltip;

  /// Tooltip for the perform-mode stage-theme toggle when the dark-stage theme is currently on.
  ///
  /// In en, this message translates to:
  /// **'Stage theme on — tap to use app theme'**
  String get performStageThemeOnTooltip;

  /// Tooltip for the perform-mode stage-theme toggle when the dark-stage theme is currently off.
  ///
  /// In en, this message translates to:
  /// **'Stage theme off — tap for dark stage'**
  String get performStageThemeOffTooltip;

  /// Tooltip on the progression marker icon shown beside a progressing figure on the perform-mode card.
  ///
  /// In en, this message translates to:
  /// **'Progression'**
  String get performProgression;

  /// Screen-reader label for one figure row on the perform-mode card: the figure text, an optional import-gap note, an optional progression marker, the beat count, and an optional caller note.
  ///
  /// In en, this message translates to:
  /// **'{main}{importGap, select, yes{, {importGapText}} other{}}{progression, select, yes{, progression} other{}}, {beats, plural, =1{1 beat} other{{beats} beats}}{hasNote, select, yes{, note: {note}} other{}}'**
  String performFigureSemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    int beats,
    String hasNote,
    String note,
  );

  /// Title of the empty-state shown in the program editor pane when no program is selected (split-pane layout).
  ///
  /// In en, this message translates to:
  /// **'Select a program'**
  String get programsSelectTitle;

  /// Body text of the empty-state shown in the program editor pane when no program is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose a program from the list, or create a new one.'**
  String get programsSelectBody;

  /// Generic label for an Edit action button.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Generic label for a Change action button (e.g. change a chosen value).
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get commonChange;

  /// Generic button to retry an action after an error (distinct from commonRetry 'Retry').
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Tooltip on the share/print (export) popup-menu button for a dance or program.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportTooltip;

  /// Export-menu item: share the dance as a plain-text card via the OS share sheet.
  ///
  /// In en, this message translates to:
  /// **'Share dance (text)'**
  String get exportShareDanceText;

  /// Export-menu item: copy the dance's plain-text card to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy dance'**
  String get exportCopyDance;

  /// Export-menu item: hand a generated PDF to the OS print/save dialog.
  ///
  /// In en, this message translates to:
  /// **'Export / print PDF'**
  String get exportPrintPdf;

  /// Snackbar confirming the dance text was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Dance copied to clipboard.'**
  String get exportDanceCopied;

  /// Snackbar shown when sharing a dance fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this dance'**
  String get exportShareDanceError;

  /// Snackbar shown when exporting/printing a dance PDF fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export this dance'**
  String get exportDanceError;

  /// Program export-menu item: share the set list as plain text.
  ///
  /// In en, this message translates to:
  /// **'Share set list (text)'**
  String get exportShareSetListText;

  /// Program export-menu item: share a bundle file containing the program and its dances.
  ///
  /// In en, this message translates to:
  /// **'Share (program + dances)'**
  String get exportShareProgramBundle;

  /// Program export-menu item: copy the set list text to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy set list'**
  String get exportCopySetList;

  /// Snackbar confirming the set list text was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Set list copied to clipboard.'**
  String get exportSetListCopied;

  /// Program export-menu item: share the program and its dances as a plain .json file, the same content as the .ccshare bundle but in a format any device can open.
  ///
  /// In en, this message translates to:
  /// **'Export as JSON file'**
  String get exportShareProgramJson;

  /// Snackbar shown when sharing a set list fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this set list'**
  String get exportShareSetListError;

  /// Snackbar shown when sharing a program bundle fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this program'**
  String get exportShareProgramError;

  /// Snackbar shown when exporting/printing a set list PDF fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export this set list'**
  String get exportSetListError;

  /// Title of the dialog that asks whether to include full dance-card figures in a set-list text share, copy, or PDF export (issue #853).
  ///
  /// In en, this message translates to:
  /// **'Include figures?'**
  String get exportIncludeFiguresTitle;

  /// Radio-row label in the figures-inclusion dialog: export titles and metadata, no figure cards.
  ///
  /// In en, this message translates to:
  /// **'Set list only'**
  String get exportIncludeFiguresSetListOnly;

  /// Radio-row label in the figures-inclusion dialog: export set list plus a full figure card for each dance, appended after the set list.
  ///
  /// In en, this message translates to:
  /// **'Set list and figures'**
  String get exportIncludeFiguresSetListAndFigures;

  /// Label prepended to a dance's figure card in a set-list-and-figures export when that dance is an alternate (not the primary slot). Used in plain-text and PDF outputs.
  ///
  /// In en, this message translates to:
  /// **'Alternate'**
  String get exportIncludeFiguresAlternate;

  /// Tooltip on the button that exports/prints the program matrix as a PDF.
  ///
  /// In en, this message translates to:
  /// **'Export or print matrix as PDF'**
  String get exportMatrixPdfTooltip;

  /// Fallback filename for the generated program-matrix PDF when the program has no title.
  ///
  /// In en, this message translates to:
  /// **'Programming matrix'**
  String get exportMatrixPdfFilename;

  /// Field label for the formation on an exported dance card (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get exportLabelFormation;

  /// Field label for the difficulty level on an exported dance card or set list (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get exportLabelLevel;

  /// Field label for the mixer line on an exported dance card (plain text and PDF); shown only when the dance is a mixer (Dance.mixer == true). A mixer is a dance in which dancers change partners each time through, NOT an audio or kitchen mixer.
  ///
  /// In en, this message translates to:
  /// **'Mixer'**
  String get exportLabelMixer;

  /// Field label for the status (deprecated/broken) on an exported dance card (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get exportLabelStatus;

  /// Field label for the phrase structure notation on an exported dance card (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Phrase'**
  String get exportLabelPhrase;

  /// Section heading for the figure list on an exported dance card (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Figures'**
  String get exportLabelFigures;

  /// Section heading for the calling notes on an exported dance card (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Calling notes'**
  String get exportLabelCallingNotes;

  /// Section heading for the walkthrough on an exported dance card (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Walkthrough'**
  String get exportLabelWalkthrough;

  /// Beat-count suffix for a figure on an exported dance card, e.g. '16 beats' or '1 beat'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 beat} other{{count} beats}}'**
  String exportBeatsLabel(int count);

  /// Level label on an exported dance card when the dance is marked mixed-level and has no specific level.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get exportLevelMixedOnly;

  /// Level label on an exported dance card combining a specific level with the mixed-level flag, e.g. 'Intermediate (mixed)'.
  ///
  /// In en, this message translates to:
  /// **'{level} (mixed)'**
  String exportLevelWithMixed(String level);

  /// Field label for the band on an exported set list (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get exportLabelBand;

  /// Field label for the caller on an exported set list (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Caller'**
  String get exportLabelCaller;

  /// Section heading for the program notes on an exported set list (plain text and PDF).
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get exportLabelNotes;

  /// Prefix marking an alternate dance slot on an exported set list (plain text and PDF). Short for 'alternate'.
  ///
  /// In en, this message translates to:
  /// **'ALT'**
  String get exportLabelAlt;

  /// Prefix for a guest caller on an exported set-list slot, e.g. 'guest: Pat'.
  ///
  /// In en, this message translates to:
  /// **'guest'**
  String get exportLabelGuest;

  /// Marker shown in brackets after a set-list slot that has been performed, e.g. '[performed]'.
  ///
  /// In en, this message translates to:
  /// **'performed'**
  String get exportLabelPerformed;

  /// Placeholder used on an exported set list when a slot's dance title can't be resolved.
  ///
  /// In en, this message translates to:
  /// **'Untitled dance'**
  String get exportUnknownDanceLabel;

  /// Planned-minutes suffix for a set-list slot on an export, e.g. '5 min'. 'min' abbreviates 'minutes'.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String exportMinutesLabel(int count);

  /// Heading for the venue detail block on an exported set-list PDF.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get exportLabelVenue;

  /// Field label for the venue's event time on an exported set-list PDF.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get exportLabelTime;

  /// Field label for the venue's recurring schedule on an exported set-list PDF.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get exportLabelSchedule;

  /// Field label for the venue's admission price on an exported set-list PDF.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get exportLabelPrice;

  /// Field label for the venue's sponsor on an exported set-list PDF.
  ///
  /// In en, this message translates to:
  /// **'Sponsor'**
  String get exportLabelSponsor;

  /// Fallback document title on the programming-matrix PDF when the program has no title.
  ///
  /// In en, this message translates to:
  /// **'Programming matrix'**
  String get exportMatrixDefaultTitle;

  /// Header for the first (dance-title) column of the programming-matrix PDF table.
  ///
  /// In en, this message translates to:
  /// **'Dance'**
  String get exportMatrixDanceColumn;

  /// Header for the pinned formation column of the programming-matrix PDF table (#663), matching the on-screen matrix's formation column.
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get exportMatrixFormationColumn;

  /// Empty-state line on the programming-matrix PDF when no dances have structured figures yet.
  ///
  /// In en, this message translates to:
  /// **'No structured figures yet — the matrix fills in automatically as the program’s dances gain structured figures.'**
  String get exportMatrixEmptyState;

  /// Legend entry on the programming-matrix PDF for the star marker: the first dance in the program to use a move.
  ///
  /// In en, this message translates to:
  /// **'Introduced here'**
  String get exportMatrixLegendDebut;

  /// Legend entry on the programming-matrix PDF for the triangle marker: a move that is a dance's own first figure.
  ///
  /// In en, this message translates to:
  /// **'Dance\'s first figure'**
  String get exportMatrixLegendFirst;

  /// Legend entry on the programming-matrix PDF for the check marker: a move present in a dance.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get exportMatrixLegendPresent;

  /// Legend entry on the programming-matrix PDF for the alert marker: a move repeating in the same phrase (A1/A2/B1/B2…) as a strictly-adjacent dance.
  ///
  /// In en, this message translates to:
  /// **'Same phrase as adjacent dance'**
  String get exportMatrixLegendCollision;

  /// Caption on the programming-matrix PDF noting how many free-text slots (breaks, notes) were left out because the matrix shows dances only.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 free-text slot (breaks, notes) omitted — the matrix shows dances only.} other{{count} free-text slots (breaks, notes) omitted — the matrix shows dances only.}}'**
  String exportMatrixOmittedCaption(int count);

  /// Title of the pre-export consent dialog that asks whether to include a venue's personal contact fields when sharing a program bundle or exporting a program PDF.
  ///
  /// In en, this message translates to:
  /// **'Include venue contact details in this export?'**
  String get exportVenueContactTitle;

  /// Body text of the venue contact consent dialog, explaining that contact fields are omitted by default from both shares and PDF exports.
  ///
  /// In en, this message translates to:
  /// **'These are personal contact details for the venue. They\'re left out of this export unless you choose to include them.'**
  String get exportVenueContactBody;

  /// Checkbox label for the primary venue contact's name in the export consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact 1 name'**
  String get exportVenueContact1Name;

  /// Checkbox label for the primary venue contact's phone number in the export consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact 1 phone'**
  String get exportVenueContact1Phone;

  /// Checkbox label for the primary venue contact's email in the export consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact 1 email'**
  String get exportVenueContact1Email;

  /// Checkbox label for the secondary venue contact's name in the export consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact 2 name'**
  String get exportVenueContact2Name;

  /// Checkbox label for the secondary venue contact's phone number in the export consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact 2 phone'**
  String get exportVenueContact2Phone;

  /// Checkbox label for the secondary venue contact's email in the export consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact 2 email'**
  String get exportVenueContact2Email;

  /// Title of the switch that turns online dance search on/off in the collection screen.
  ///
  /// In en, this message translates to:
  /// **'Online search'**
  String get onlineSearchToggleTitle;

  /// Subtitle explaining what the online-search switch does.
  ///
  /// In en, this message translates to:
  /// **'Search online and import dances directly (requires internet). Local filters do not apply.'**
  String get onlineSearchToggleSubtitle;

  /// Label for the search field when online search is active.
  ///
  /// In en, this message translates to:
  /// **'Search {source}'**
  String onlineSearchFieldLabel(String source);

  /// Hint text for the online search field.
  ///
  /// In en, this message translates to:
  /// **'Search online dances by title…'**
  String get onlineSearchFieldHint;

  /// Count of online search results shown above the results list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 online result} other{{count} online results}}'**
  String onlineResultCount(int count);

  /// Empty-query hint for online sources that support by-phrase figure criteria.
  ///
  /// In en, this message translates to:
  /// **'Type a title or add by-phrase figures to search {source}.'**
  String onlineSearchHintByPhrase(String source);

  /// Empty-query hint for online sources that only support title search.
  ///
  /// In en, this message translates to:
  /// **'Type a title to search {source}.'**
  String onlineSearchHintTitle(String source);

  /// Shown when an online search returns no matching dances.
  ///
  /// In en, this message translates to:
  /// **'No dances on {source} match your search.'**
  String onlineNoResults(String source);

  /// Snackbar/inline error shown when loading a dance preview from an online source fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load that dance from {source}.'**
  String onlineLoadError(String source);

  /// Snackbar shown when directly importing an online dance fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import that dance.'**
  String get onlineImportError;

  /// Inline error shown when an online search fails unexpectedly. {source} is the online source's proper name (e.g. “The Caller's Box” / “ContraDB”), not translated.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search {source}. Please try again.'**
  String onlineSearchFailed(String source);

  /// Snackbar confirming an online dance was imported. The title is an untrusted external value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Imported \"{title}\".'**
  String onlineImportCreated(String title);

  /// Snackbar shown when the online dance being imported was already in the collection. The title is an untrusted external value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is already in your collection.'**
  String onlineImportAlreadyInCollection(String title);

  /// Body text in the resolution dialog shown when a confident title+author match with differing figures is found during a single-dance online import (issue #797). existingTitle is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'This dance\'s title and caller match \"{existingTitle}\", but its figures are different. How do you want to import it?'**
  String onlineImportVariationDialogBody(String existingTitle);

  /// Button label in the issue #797 resolution dialog: import the incoming dance as a new, distinct dance (variation of the matched one).
  ///
  /// In en, this message translates to:
  /// **'Import as a variation'**
  String get onlineImportVariationDialogActionVariation;

  /// Button label in the issue #797 resolution dialog: treat the incoming dance as the same dance and overwrite the existing record.
  ///
  /// In en, this message translates to:
  /// **'Same dance (update existing)'**
  String get onlineImportVariationDialogActionLink;

  /// Secondary text warning that 'Same dance (link)' is a wholesale replacement. _rebuildWithIdentity (import_pipeline.dart) preserves only id and createdAt from the existing dance; every other field — figures, callingNotes, tagIds, rating, customFields, tunes, links, sourceCitations, hook, title, form, authorIds, provenance — comes from the incoming draft. Note: authorIds is resolved from the incoming record's author names and provenance is the incoming record's provenance (that is the point of linking); neither survives from the existing dance. The dance id is preserved, so ProgramSlot.danceId references stay intact — programs and calling history survive. Used in both the #797 variation dialog (figures DIFFER — the field callers care most about) and the #811 cross-source dialog (figures canonically identical, so replacement is less consequential). existingTitle is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Your version of \"{existingTitle}\" will be replaced by the online record — including its figures, notes, tags, rating, and custom fields. It keeps its place in your programs and its calling history.'**
  String onlineImportVariationDialogLinkWarning(String existingTitle);

  /// Title of the resolution dialog shown when a confident title+author match with identical figures is found from a different source during a single-dance online import (issue #811).
  ///
  /// In en, this message translates to:
  /// **'You already have this dance'**
  String get onlineImportCrossSourceDuplicateDialogTitle;

  /// Body text in the issue #811 resolution dialog for a cross-source duplicate with canonically identical figures (same moves and order; beats and notes may differ). existingTitle is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Your collection already has \"{existingTitle}\" from a different source. Both versions have the same sequence of moves.'**
  String onlineImportCrossSourceDuplicateDialogBody(String existingTitle);

  /// Action button in the cross-source duplicate dialog (#811) that lets the user import the dance anyway, creating a second copy alongside the existing one.
  ///
  /// In en, this message translates to:
  /// **'Import a second copy'**
  String get onlineImportCrossSourceDuplicateDialogActionDuplicate;

  /// Attribution line under an online result row sourced from The Caller's Box.
  ///
  /// In en, this message translates to:
  /// **'From The Caller\'s Box (online)'**
  String get onlineAttributionCallersBox;

  /// Attribution line under an online result row sourced from ContraDB.
  ///
  /// In en, this message translates to:
  /// **'From ContraDB (online)'**
  String get onlineAttributionContraDb;

  /// Tooltip/title for the import-dances action and the import review screen app bar.
  ///
  /// In en, this message translates to:
  /// **'Import dances'**
  String get importDances;

  /// Generic label for the button that commits an import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// Tooltip on the import-program popup-menu button in the programs list.
  ///
  /// In en, this message translates to:
  /// **'Import program'**
  String get importProgramTooltip;

  /// Import-program menu item: import a program from a pasted title list.
  ///
  /// In en, this message translates to:
  /// **'From title list'**
  String get importFromTitleList;

  /// Import-program menu item: import a program from ContraDB.
  ///
  /// In en, this message translates to:
  /// **'From ContraDB'**
  String get importFromContraDb;

  /// Label for the program-title text field in the import screens.
  ///
  /// In en, this message translates to:
  /// **'Program title'**
  String get importProgramTitleLabel;

  /// Snackbar shown when writing an imported program to the collection fails. The raw exception is logged (debugPrint), never shown, so storage internals/paths can't leak to the UI (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the imported program.'**
  String get importProgramCreateError;

  /// Snackbar summarising a committed program import. The title is an untrusted external value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Imported \"{title}\" — {slots, plural, =1{1 slot} other{{slots} slots}} ({linked} linked, {notes, plural, =1{1 note} other{{notes} notes}}).'**
  String importProgramCommitted(String title, int slots, int linked, int notes);

  /// App bar title of the ContraDB program import screen.
  ///
  /// In en, this message translates to:
  /// **'Import from ContraDB'**
  String get importContraDbTitle;

  /// Segmented-button label: enter a ContraDB program by pasting its URL.
  ///
  /// In en, this message translates to:
  /// **'Paste URL'**
  String get importContraDbPasteUrl;

  /// Segmented-button label: find a ContraDB program by searching its name.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get importContraDbSearchByName;

  /// Label for the ContraDB program URL text field.
  ///
  /// In en, this message translates to:
  /// **'ContraDB program URL'**
  String get importContraDbUrlLabel;

  /// Hint for the ContraDB program URL text field.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://contradb.com/programs/33'**
  String get importContraDbUrlHint;

  /// Label on the fetch button while a ContraDB program is being fetched.
  ///
  /// In en, this message translates to:
  /// **'Fetching…'**
  String get importContraDbFetching;

  /// Label on the button that fetches a ContraDB program by URL.
  ///
  /// In en, this message translates to:
  /// **'Fetch program'**
  String get importContraDbFetch;

  /// Label for the ContraDB program search field.
  ///
  /// In en, this message translates to:
  /// **'Search ContraDB programs'**
  String get importContraDbSearchLabel;

  /// Hint for the ContraDB program search field.
  ///
  /// In en, this message translates to:
  /// **'Type part of a program name'**
  String get importContraDbSearchHint;

  /// Error shown when the ContraDB program index fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load the ContraDB program list.'**
  String get importContraDbListError;

  /// Prompt shown in the ContraDB search results area before the user has typed a query.
  ///
  /// In en, this message translates to:
  /// **'Type part of a program name to search ContraDB.'**
  String get importContraDbSearchPrompt;

  /// Shown when a ContraDB program name search returns no matches.
  ///
  /// In en, this message translates to:
  /// **'No matching programs.'**
  String get importContraDbNoMatches;

  /// Firm badge on a ContraDB program search/preview row that was already imported into the local collection (matched by its ContraDB program id). Accompanied by an icon so colour is never the only signal (WCAG 1.4.1).
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importContraDbMarkerImported;

  /// Tooltip/accessibility label for the firm 'Imported' marker on a ContraDB program row, naming when the local copy was imported. {date} is a preformatted, localized date.
  ///
  /// In en, this message translates to:
  /// **'Imported on {date}'**
  String importContraDbMarkerImportedTooltip(String date);

  /// Fallback tooltip/accessibility label for the firm 'Imported' marker when the stored import date is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Already imported from ContraDB'**
  String get importContraDbMarkerImportedTooltipNoDate;

  /// Softer badge on a ContraDB program search/preview row whose title matches an existing local program, but with no ContraDB id linking them (a weaker, title-only 'maybe you imported this' hint). Accompanied by an icon so colour is never the only signal (WCAG 1.4.1).
  ///
  /// In en, this message translates to:
  /// **'Possibly imported'**
  String get importContraDbMarkerPossible;

  /// Tooltip/accessibility label for the softer 'Possibly imported' marker on a ContraDB program row (title-only match).
  ///
  /// In en, this message translates to:
  /// **'A program with this title already exists'**
  String get importContraDbMarkerPossibleTooltip;

  /// Error shown when fetching a ContraDB program fails. {error} is ONLY ever a curated, safe-to-show UrlFetchException.message (e.g. a scheme/redirect/size guard message); unexpected raw exceptions are logged and shown via importContraDbFetchGenericError instead, so no internals leak (CWE-209). Rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t fetch that program.\n{error}'**
  String importContraDbFetchError(String error);

  /// Error shown when fetching a ContraDB program fails with an unexpected (non-curated) exception. The raw exception is logged (debugPrint), never shown, to avoid leaking internals (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t fetch that program.'**
  String get importContraDbFetchGenericError;

  /// Prompt shown in the preview area before a ContraDB program has been fetched.
  ///
  /// In en, this message translates to:
  /// **'Paste a ContraDB program URL above and tap \"Fetch program\".'**
  String get importContraDbPastePrompt;

  /// Shown when a fetched ContraDB program page contains no dances or notes.
  ///
  /// In en, this message translates to:
  /// **'No dances or notes found on that program page.'**
  String get importContraDbEmptyProgram;

  /// Snackbar shown when resolving a ContraDB program's activities before commit fails. The raw exception is logged (debugPrint), never shown, so no internals leak to the UI (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import the ContraDB program.'**
  String get importContraDbResolveError;

  /// Summary of a fetched ContraDB program's activities shown above the preview list.
  ///
  /// In en, this message translates to:
  /// **'{activities, plural, =1{1 activity} other{{activities} activities}} ({dances, plural, =1{1 dance} other{{dances} dances}}, {notes, plural, =1{1 note} other{{notes} notes}})'**
  String importContraDbActivityCount(int activities, int dances, int notes);

  /// Fallback title for a ContraDB activity that is a dance with no title.
  ///
  /// In en, this message translates to:
  /// **'ContraDB dance'**
  String get importContraDbDanceFallback;

  /// Shown in the event-date row when no event date has been set.
  ///
  /// In en, this message translates to:
  /// **'No date set'**
  String get importEventDateNone;

  /// Label for the event-date input row.
  ///
  /// In en, this message translates to:
  /// **'Event date'**
  String get importEventDateLabel;

  /// Button to set the event date when none is set.
  ///
  /// In en, this message translates to:
  /// **'Set date'**
  String get importEventDateSet;

  /// Tooltip on the button that clears the chosen event date.
  ///
  /// In en, this message translates to:
  /// **'Clear event date'**
  String get importEventDateClear;

  /// Hint shown when the event date was auto-detected from the program title.
  ///
  /// In en, this message translates to:
  /// **'Date detected from title — check it before importing.'**
  String get importEventDateDetected;

  /// App bar title of the plaintext (title list) program import screen.
  ///
  /// In en, this message translates to:
  /// **'Import from title list'**
  String get importTitleListTitle;

  /// Error shown when the local collection fails to load in the title-list import screen.
  ///
  /// In en, this message translates to:
  /// **'Could not load your collection.'**
  String get importCollectionLoadError;

  /// Label for the multi-line field where the user pastes dance titles.
  ///
  /// In en, this message translates to:
  /// **'Dance titles (one per line)'**
  String get importTitleListDancesLabel;

  /// Hint for the multi-line dance-titles field.
  ///
  /// In en, this message translates to:
  /// **'Paste one dance title per line.\nUnrecognised lines are kept as notes.'**
  String get importTitleListDancesHint;

  /// Prompt shown before any dance titles have been pasted.
  ///
  /// In en, this message translates to:
  /// **'Paste a list of dance titles above to preview the program.'**
  String get importTitleListEmptyHint;

  /// Label on the resolve-online button while an online search is in flight.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get importResolving;

  /// Button that searches online sources for the unmatched title-list lines.
  ///
  /// In en, this message translates to:
  /// **'Resolve unmatched online'**
  String get importResolveOnline;

  /// Per-line status: this title was resolved and imported from an online source (The Caller's Box or ContraDB). Deliberately does not name which source (issue #943 ruling: no source attribution in this step; the source is still recorded in the imported dance's provenance).
  ///
  /// In en, this message translates to:
  /// **'Imported online'**
  String get importPlaintextImportedOnline;

  /// Per-line status: this title was linked to an existing local dance.
  ///
  /// In en, this message translates to:
  /// **'Linked to dance'**
  String get importPlaintextLinked;

  /// Per-line status: this title had multiple possible matches, so it was kept as a note.
  ///
  /// In en, this message translates to:
  /// **'Multiple matches — added as note'**
  String get importPlaintextAmbiguous;

  /// Per-line status: this title matched nothing, so it was kept as a note.
  ///
  /// In en, this message translates to:
  /// **'No match — added as note'**
  String get importPlaintextUnmatched;

  /// Snackbar shown when resolving unmatched title-list lines online fails. Deliberately does not name a source (issue #943: the resolver tries The Caller's Box then ContraDB). The raw exception is logged (debugPrint), never shown, so no internals leak to the UI (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search online.'**
  String get importPlaintextSearchError;

  /// Count of slots in the title-list import preview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 slot} other{{count} slots}}'**
  String importPlaintextSlotCount(int count);

  /// Snackbar shown after online resolution when no confident matches were found. Deliberately does not name a source (issue #943: tries The Caller's Box then ContraDB).
  ///
  /// In en, this message translates to:
  /// **'No confident online matches found — {remaining, plural, =1{{remaining} title kept as a note} other{{remaining} titles kept as notes}}.'**
  String importPlaintextResolvedNone(int remaining);

  /// Snackbar shown after online resolution when some titles were linked, optionally noting how many remain unmatched. Deliberately does not name a source (issue #943: tries The Caller's Box then ContraDB).
  ///
  /// In en, this message translates to:
  /// **'Linked {linked, plural, =1{{linked} title} other{{linked} titles}} online{remaining, plural, =0{.} =1{; {remaining} still a note.} other{; {remaining} still notes.}}'**
  String importPlaintextResolvedLinked(int linked, int remaining);

  /// Tooltip on the close button of the embedded import review screen.
  ///
  /// In en, this message translates to:
  /// **'Close import'**
  String get importReviewClose;

  /// Label above the import-source dropdown when more than one source is available.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get importReviewSourceLabel;

  /// Heading for a binary (byte) import source such as a Caller's Companion file.
  ///
  /// In en, this message translates to:
  /// **'Import from {source}.'**
  String importReviewFromSource(String source);

  /// Heading for a text/URL import source.
  ///
  /// In en, this message translates to:
  /// **'Import dances from {source}.'**
  String importReviewDancesFromSource(String source);

  /// Name of the generic Caller's Compendium JSON import source, shown in the import-source dropdown and in the 'Import from {source}.' heading.
  ///
  /// In en, this message translates to:
  /// **'a Caller\'s Compendium JSON file'**
  String get importSourceLabelGenericJson;

  /// Name of The Caller's Box online import source (a proper noun), shown in the import-source dropdown and headings.
  ///
  /// In en, this message translates to:
  /// **'The Caller\'s Box'**
  String get importSourceLabelCallersBox;

  /// Name of the ContraDB online import source (a proper noun), shown in the import-source dropdown and headings.
  ///
  /// In en, this message translates to:
  /// **'ContraDB'**
  String get importSourceLabelContraDb;

  /// Name of the Caller's Companion .USR binary import source, shown in the import-source dropdown and headings.
  ///
  /// In en, this message translates to:
  /// **'a Caller\'s Companion .USR file'**
  String get importSourceLabelCallersCompanionUsr;

  /// Name of the pasted-dance-title-list import source (issue #823), shown in the import-source dropdown and in the 'Import dances from {source}.' heading.
  ///
  /// In en, this message translates to:
  /// **'a list of titles'**
  String get importSourceLabelTitleList;

  /// Subtitle on the import input screen when the pasted-title-list source is selected, explaining the one-title-per-line format and that nothing is written before the review step.
  ///
  /// In en, this message translates to:
  /// **'Paste one dance title per line. Every title is listed for review — the ones you already have are shown but never re-imported, and nothing is added to your collection until you confirm.'**
  String get importReviewTitleListSubtitle;

  /// Label on the multi-line paste field when the pasted-title-list import source is selected.
  ///
  /// In en, this message translates to:
  /// **'Dance titles, one per line'**
  String get importReviewPasteTitles;

  /// Live count of distinct titles in the paste field, shown under it before the user continues.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No titles yet} =1{1 title} other{{count} titles}}'**
  String importReviewTitleListCount(int count);

  /// Note shown when the pasted list repeated a title; repeats are folded onto their first occurrence so a dance is never searched or imported twice.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 repeated title ignored} other{{count} repeated titles ignored}}'**
  String importReviewTitleListDuplicates(int count);

  /// Refusal shown when a pasted list holds more distinct titles than the per-import cap. The list is refused outright rather than truncated, so the user never believes a longer list imported in full.
  ///
  /// In en, this message translates to:
  /// **'That\'s {count} titles. Import up to {max} at a time.'**
  String importTitleListTooManyTitles(int count, int max);

  /// Refusal shown when the raw pasted text exceeds the hard character cap, before it is parsed. Deliberately does NOT cite the title-count cap: this path is the raw size limit, which a paste of very long lines can trip with far fewer than the maximum number of titles, so naming that number would misdescribe why the paste was refused.
  ///
  /// In en, this message translates to:
  /// **'That paste is too long to read as a list of titles. Try pasting a shorter list.'**
  String get importTitleListTextTooLong;

  /// Progress line while each unmatched title is looked up online, one at a time.
  ///
  /// In en, this message translates to:
  /// **'Searching {done} of {total}…'**
  String importReviewTitleListProgress(int done, int total);

  /// Heading of the review summary banner, naming how many titles were pasted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pasted title} other{{count} pasted titles}}'**
  String importReviewTitleListPasted(int count);

  /// Heading over a group of candidate rows for one pasted program line that no online source could resolve confidently (more than one dance shared the title). The user picks at most one candidate to import; leaving them all skipped keeps the line as a free-text note.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" — pick one, or leave as a note'**
  String importReviewProgramAmbiguousLine(String title);

  /// Summary/group count of pasted titles that resolved to a dance available to import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 to import} other{{count} to import}}'**
  String importReviewTitleListToImport(int count);

  /// Summary/group count of pasted titles the user already has. Shown as its own group because 'which of these do I already have?' is useful on its own and needs different follow-up from 'not found'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 already in your collection} other{{count} already in your collection}}'**
  String importReviewTitleListOwned(int count);

  /// Summary/group count of pasted titles nothing importable could be found for.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 not found} other{{count} not found}}'**
  String importReviewTitleListNotFound(int count);

  /// Detail under an already-in-collection row naming the matched dance's choreographer(s). The local match is by title alone, so the author is what lets the user tell a real match from a different dance sharing a title.
  ///
  /// In en, this message translates to:
  /// **'You already have this, by {authors}.'**
  String importReviewTitleListOwnedBy(String authors);

  /// Detail under an already-in-collection row when the matched dance has no recorded choreographer.
  ///
  /// In en, this message translates to:
  /// **'You already have this dance.'**
  String get importReviewTitleListOwnedUnknownAuthor;

  /// Detail under an already-in-collection row when several local dances share the pasted title. The count is the useful fact; listing every choreographer would be noise.
  ///
  /// In en, this message translates to:
  /// **'You have {count} dances with this title.'**
  String importReviewTitleListOwnedMany(int count);

  /// Reason under a not-found row: the online search returned nothing.
  ///
  /// In en, this message translates to:
  /// **'The Caller\'s Box has no dance by this name.'**
  String get importTitleListReasonNoResults;

  /// Reason under a not-found row: results came back but none matched the title exactly, and fuzzy matches are never imported unasked.
  ///
  /// In en, this message translates to:
  /// **'Only near matches — nothing titled exactly this.'**
  String get importTitleListReasonNoExactMatch;

  /// Reason under a not-found row: more than one online result has this exact title, so it is genuinely ambiguous.
  ///
  /// In en, this message translates to:
  /// **'Several dances share this exact title, so it isn\'t clear which you meant.'**
  String get importTitleListReasonMultipleExactMatches;

  /// Reason under a not-found row: the search or the per-dance fetch failed. Isolated per title so one failure never aborts the rest of the list. The raw error is logged, never shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach The Caller\'s Box for this title.'**
  String get importTitleListReasonFetchError;

  /// Reason under a not-found row: the pasted line exceeded the per-title length cap, so it was reported rather than turned into a search query.
  ///
  /// In en, this message translates to:
  /// **'Too long to be a dance title, so it wasn\'t searched.'**
  String get importTitleListReasonLineTooLong;

  /// Shown above the review groups when a pasted list produced no importable dance at all, so the informative rows are still presented instead of a dead-end 'no dances found' screen.
  ///
  /// In en, this message translates to:
  /// **'Nothing here to import — every title is either already in your collection or couldn\'t be found.'**
  String get importReviewTitleListNothingToImport;

  /// Import result summary line for a pasted title list: how many titles the user already had. Included so the answer survives the screen closing after a commit.
  ///
  /// In en, this message translates to:
  /// **'Already in your collection: {count}'**
  String importReviewSummaryAlreadyOwned(int count);

  /// Import result summary line for a pasted title list: how many titles nothing importable could be found for.
  ///
  /// In en, this message translates to:
  /// **'Not found: {count}'**
  String importReviewSummaryNotFound(int count);

  /// Error shown when a chosen import file exceeds the maximum allowed size.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to import.'**
  String get importErrorFileTooLarge;

  /// Rejection shown when a shared/AirDropped archive file exceeds the size cap. Generic; never echoes the path or size.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to import.'**
  String get archiveIntakeRejectedTooLarge;

  /// Rejection shown when a shared archive file could not be read from disk at all. Generic; never echoes the path or the underlying OS error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the shared file.'**
  String get archiveIntakeRejectedUnreadable;

  /// Rejection shown when a shared archive file contained no bytes.
  ///
  /// In en, this message translates to:
  /// **'That file is empty.'**
  String get archiveIntakeRejectedEmpty;

  /// Rejection shown when a shared file is not a well-formed Caller's Compendium archive (bad text, non-archive JSON, or an unreadable envelope). Generic; never echoes parser detail.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t a Caller\'s Compendium share file.'**
  String get archiveIntakeRejectedNotArchive;

  /// Rejection shown when a shared archive was written by a newer app version than this build understands.
  ///
  /// In en, this message translates to:
  /// **'That file was made by a newer version of the app. Please update to import it.'**
  String get archiveIntakeRejectedNewerVersion;

  /// Rejection shown when a shared archive decoded successfully but carried neither dances nor programs.
  ///
  /// In en, this message translates to:
  /// **'That file didn\'t contain any dances or programs.'**
  String get archiveIntakeRejectedNoContent;

  /// Error shown when an import URL does not use the https scheme.
  ///
  /// In en, this message translates to:
  /// **'Imports must use a secure https:// URL.'**
  String get importErrorInsecureScheme;

  /// Error shown when an import URL resolves to a blocked or private network location (SSRF guard). Never echoes the URL.
  ///
  /// In en, this message translates to:
  /// **'That URL points to a network location that cannot be imported from.'**
  String get importErrorBlockedHost;

  /// Error shown when the entered import URL is not a valid http/https URL.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid http(s) URL.'**
  String get importErrorInvalidUrl;

  /// Error shown when fetching an import URL exceeded the redirect limit.
  ///
  /// In en, this message translates to:
  /// **'That URL redirected too many times.'**
  String get importErrorTooManyRedirects;

  /// Error shown when a fetched import response exceeded the maximum allowed size.
  ///
  /// In en, this message translates to:
  /// **'That response was too large to import.'**
  String get importErrorResponseTooLarge;

  /// Error shown when the import URL field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a URL to import from.'**
  String get importErrorEmptyUrl;

  /// Error shown when fetching an import URL timed out.
  ///
  /// In en, this message translates to:
  /// **'The request timed out after {seconds}s. Check the URL and your connection, then try again.'**
  String importErrorTimeout(int seconds);

  /// Error shown when an import URL could not be reached. Never echoes the URL.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach that URL. Check the URL and your connection, then try again.'**
  String get importErrorUnreachable;

  /// Error shown when an import URL returned a non-success HTTP status.
  ///
  /// In en, this message translates to:
  /// **'The server responded with HTTP {status}.'**
  String importErrorHttpStatus(int status);

  /// Error shown when an import URL returned an empty body.
  ///
  /// In en, this message translates to:
  /// **'The URL returned an empty response.'**
  String get importErrorEmptyResponse;

  /// Error shown when the Caller's Box dance URL/id field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a Caller\'s Box dance URL or id to import from.'**
  String get importErrorCallersBoxEmptyInput;

  /// Error shown when the Caller's Box input is neither a recognized dance URL nor a numeric id.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a Caller\'s Box dance URL or a numeric id.'**
  String get importErrorCallersBoxInvalidUrl;

  /// Error shown when a Caller's Box URL has no dance id query parameter.
  ///
  /// In en, this message translates to:
  /// **'That Caller\'s Box URL is missing a dance id (…dance.php?id=N).'**
  String get importErrorCallersBoxMissingId;

  /// Error shown when a pasted Caller's Box URL is not on the ibiblio.org mirror under its /contradance/thecallersbox/ path. Names BOTH accepted hostnames literally (the app itself generates the www. form) so a user scanning for their own hostname finds it, AND the path, which is the actionable half whenever the host was right and only the path was wrong. Says 'link' rather than 'host' because either half can be the failure. Never echoes the pasted URL/host.
  ///
  /// In en, this message translates to:
  /// **'That link isn\'t a supported Caller\'s Box link. Paste a link from ibiblio.org or www.ibiblio.org under /contradance/thecallersbox/, or enter the dance\'s numeric id.'**
  String get importErrorCallersBoxUnsupportedHost;

  /// Error shown when a Caller's Box search is attempted with no query.
  ///
  /// In en, this message translates to:
  /// **'Enter a title or by-phrase figures to search The Caller\'s Box.'**
  String get importErrorCallersBoxEmptySearch;

  /// Error shown when an online search (Caller's Box or ContraDB) timed out.
  ///
  /// In en, this message translates to:
  /// **'The search timed out after {seconds}s. Check your connection, then try again.'**
  String importErrorSearchTimeout(int seconds);

  /// Error shown when The Caller's Box could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach The Caller\'s Box. Check your connection, then try again.'**
  String get importErrorCallersBoxUnreachable;

  /// Error shown when The Caller's Box returned a non-success HTTP status.
  ///
  /// In en, this message translates to:
  /// **'The Caller\'s Box responded with HTTP {status}.'**
  String importErrorCallersBoxHttpStatus(int status);

  /// Error shown when a Caller's Box search returned no page content.
  ///
  /// In en, this message translates to:
  /// **'The Caller\'s Box returned an empty page.'**
  String get importErrorCallersBoxEmptyPage;

  /// Error shown when a Caller's Box fetch parsed no importable dance. Generic by design; underlying parse detail is not shown.
  ///
  /// In en, this message translates to:
  /// **'The Caller\'s Box returned no importable dance.'**
  String get importErrorCallersBoxNoDance;

  /// Error shown when committing a Caller's Box dance failed. Generic by design; underlying error detail is not shown.
  ///
  /// In en, this message translates to:
  /// **'The Caller\'s Box dance couldn\'t be imported.'**
  String get importErrorCallersBoxImportFailed;

  /// Error shown when a ContraDB search is attempted with no title.
  ///
  /// In en, this message translates to:
  /// **'Enter a title to search ContraDB.'**
  String get importErrorContraDbEmptyTitle;

  /// Error shown when the ContraDB dance URL/id field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a ContraDB dance URL or id to import from.'**
  String get importErrorContraDbEmptyDanceInput;

  /// Error shown when the ContraDB dance input is neither a recognized dance URL nor a numeric id.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a ContraDB dance URL or a numeric id.'**
  String get importErrorContraDbInvalidDanceUrl;

  /// Error shown when a ContraDB dance URL has no dance id path segment.
  ///
  /// In en, this message translates to:
  /// **'That ContraDB URL is missing a dance id (…/dances/N).'**
  String get importErrorContraDbMissingDanceId;

  /// Error shown when the ContraDB program URL/id field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a ContraDB program URL or id to import from.'**
  String get importErrorContraDbEmptyProgramInput;

  /// Error shown when the ContraDB program input is neither a recognized program URL nor a numeric id.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a ContraDB program URL or a numeric id.'**
  String get importErrorContraDbInvalidProgramUrl;

  /// Error shown when a ContraDB program URL has no program id path segment.
  ///
  /// In en, this message translates to:
  /// **'That ContraDB URL is missing a program id (…/programs/N).'**
  String get importErrorContraDbMissingProgramId;

  /// Error shown when a shared link is not a valid ContraDB program link.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a ContraDB program link.'**
  String get importErrorContraDbInvalidProgramLink;

  /// Error shown when a pasted ContraDB URL's host is not on the ContraDB allowlist. Names BOTH accepted hostnames literally (www.contradb.com is a real source: it 301s to contradb.com) so a user scanning for their own hostname finds it. Says 'host' rather than 'link' because the ContraDB predicate is genuinely host-only -- unlike the Caller's Box one, which also requires a path; do not harmonise the two. Never echoes the pasted URL/host.
  ///
  /// In en, this message translates to:
  /// **'That link isn\'t from a supported ContraDB host. Paste a link from contradb.com or www.contradb.com, or enter the dance\'s or program\'s numeric id.'**
  String get importErrorContraDbUnsupportedHost;

  /// Error shown when ContraDB could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach ContraDB. Check your connection, then try again.'**
  String get importErrorContraDbUnreachable;

  /// Error shown when ContraDB returned a non-success HTTP status.
  ///
  /// In en, this message translates to:
  /// **'ContraDB responded with HTTP {status}.'**
  String importErrorContraDbHttpStatus(int status);

  /// Error shown when ContraDB returned an empty body.
  ///
  /// In en, this message translates to:
  /// **'ContraDB returned an empty response.'**
  String get importErrorContraDbEmptyResponse;

  /// Error shown when a ContraDB fetch parsed no importable dance. Generic by design; underlying parse detail is not shown.
  ///
  /// In en, this message translates to:
  /// **'ContraDB returned no importable dance.'**
  String get importErrorContraDbNoDance;

  /// Error shown when committing a ContraDB dance failed. Generic by design; underlying error detail is not shown.
  ///
  /// In en, this message translates to:
  /// **'The ContraDB dance couldn\'t be imported.'**
  String get importErrorContraDbImportFailed;

  /// Generic fallback for an import note whose specific code has no localized message. Non-leaking; any raw detail appears only in debug builds.
  ///
  /// In en, this message translates to:
  /// **'This item was imported with a note.'**
  String get importIssueGeneric;

  /// Import note: an empty program/set slot was skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped an empty slot in a program.'**
  String get importIssueProgramEmptySlot;

  /// Import note: a program slot pointed at a dance that wasn't part of the import; the slot was preserved as free text.
  ///
  /// In en, this message translates to:
  /// **'A program referenced a dance that wasn\'t imported; kept the slot as a text placeholder.'**
  String get importIssueProgramUnresolvedDance;

  /// Import note: a program pointed at a venue that wasn't part of the import; the program kept no venue link.
  ///
  /// In en, this message translates to:
  /// **'A program referenced a venue that wasn\'t imported; kept the program without a venue link.'**
  String get importIssueProgramUnresolvedVenue;

  /// Import note: an entry in a shared archive failed to decode and was skipped. Generic; the raw decode error is not shown.
  ///
  /// In en, this message translates to:
  /// **'An entry in the shared file couldn\'t be read and was skipped.'**
  String get importIssueArchiveReadError;

  /// Import note: decoding a shared archive produced a non-fatal warning. Generic; the raw warning text is not shown.
  ///
  /// In en, this message translates to:
  /// **'The shared file reported a warning while decoding.'**
  String get importIssueArchiveReadWarning;

  /// Import note: a Becket rotation direction wasn't 'CW' or 'CCW' and was defaulted to clockwise.
  ///
  /// In en, this message translates to:
  /// **'A Becket direction wasn\'t recognized; defaulted to clockwise.'**
  String get importIssueDirectionUnmapped;

  /// Import note: a formation/start-type string couldn't be classified to a known formation and was kept as detail on the 'other' formation.
  ///
  /// In en, this message translates to:
  /// **'A formation couldn\'t be recognized; kept as a detail on “other”.'**
  String get importIssueFormationUnclassified;

  /// Import note: a phrase-structure string couldn't be parsed and a default was substituted.
  ///
  /// In en, this message translates to:
  /// **'A phrase structure couldn\'t be read; a default structure was used.'**
  String get importIssuePhraseStructureUnreadable;

  /// Import note: a progression value wasn't a standard tier and was recorded as 'other'.
  ///
  /// In en, this message translates to:
  /// **'A progression wasn\'t recognized; recorded as “other”.'**
  String get importIssueProgressionUnmapped;

  /// Import note: the source served only metadata (no figures), so the dance was imported as a metadata-only stub.
  ///
  /// In en, this message translates to:
  /// **'This dance is available as metadata only (no figures); imported as a stub.'**
  String get importIssueMetadataOnlyStub;

  /// Import note: an ambiguous numeric date was interpreted month-first (US ordering); the user should verify. {field} is the localized date-field name (composed/revised).
  ///
  /// In en, this message translates to:
  /// **'An ambiguous {field} date was read as month/day (US ordering); check it if the source used day-first ordering.'**
  String importIssueDateAssumedMdy(String field);

  /// Import note: a date had only a year available to parse. {year} is the recovered 4-digit year; {field} is the localized date-field name (composed/revised).
  ///
  /// In en, this message translates to:
  /// **'Only the year {year} could be read from the {field} date; no month or day was present.'**
  String importIssueDateReducedPrecision(int year, String field);

  /// Import note: the source dance had no title, so a placeholder was used and should be edited.
  ///
  /// In en, this message translates to:
  /// **'The dance had no title; a placeholder title was used. Edit it before committing.'**
  String get importIssueMissingTitle;

  /// Import note: a program/set event date couldn't be parsed and was left unset.
  ///
  /// In en, this message translates to:
  /// **'An event date couldn\'t be read; left unset.'**
  String get importIssueProgramUnparsedDate;

  /// Import note: a rating value fell outside 1-5 and was left unrated.
  ///
  /// In en, this message translates to:
  /// **'A rating was outside the 1–5 scale; left unrated.'**
  String get importIssueRatingOutOfRange;

  /// Import note: a formation string wasn't recognized and was preserved as free text.
  ///
  /// In en, this message translates to:
  /// **'A formation wasn\'t recognized; preserved as free-text detail.'**
  String get importIssueUnmappedFormation;

  /// Import note: a difficulty/level string wasn't recognized and was left unspecified.
  ///
  /// In en, this message translates to:
  /// **'A level wasn\'t recognized; left unspecified.'**
  String get importIssueUnmappedLevel;

  /// Import note: a progression string wasn't recognized and defaulted to single progression.
  ///
  /// In en, this message translates to:
  /// **'A progression wasn\'t recognized; defaulted to single.'**
  String get importIssueUnmappedProgression;

  /// Import note: a dance-type string wasn't recognized; the dance was imported as a contra with the original value kept in the notes.
  ///
  /// In en, this message translates to:
  /// **'A dance type wasn\'t recognized; imported as a contra and preserved in the notes.'**
  String get importIssueUnmappedType;

  /// Import note: a date value couldn't be parsed and was left unset. {field} is the localized date-field name (composed/revised).
  ///
  /// In en, this message translates to:
  /// **'The {field} date couldn\'t be read; left unset.'**
  String importIssueUnparsedDate(String field);

  /// Import note: a rating value couldn't be parsed and was left unrated.
  ///
  /// In en, this message translates to:
  /// **'A rating couldn\'t be read; left unrated.'**
  String get importIssueUnparsedRating;

  /// Import note: the figures payload couldn't be read, so the dance was imported without figures.
  ///
  /// In en, this message translates to:
  /// **'The figures couldn\'t be read; no figures were imported.'**
  String get importIssueFiguresUnreadable;

  /// Import note: a beat count couldn't be parsed and 0 was used.
  ///
  /// In en, this message translates to:
  /// **'A beat count couldn\'t be read; used 0.'**
  String get importIssueBeatsUnreadable;

  /// Import note: an imported page had no figures table, so a metadata-only stub was created.
  ///
  /// In en, this message translates to:
  /// **'The page had no figures; imported as a metadata-only stub.'**
  String get importIssueNoFiguresTable;

  /// Import note (no position available): a figure couldn't be mapped to the taxonomy and was imported as a custom figure.
  ///
  /// In en, this message translates to:
  /// **'A figure couldn\'t be matched to a known move; imported as custom.'**
  String get importIssueMoveFallback;

  /// Import note: the figure at the given 1-based position couldn't be mapped to the taxonomy and was imported as a custom figure. {position} is the app's own figure index.
  ///
  /// In en, this message translates to:
  /// **'Figure {position} couldn\'t be matched to a known move; imported as custom.'**
  String importIssueMoveFallbackAt(int position);

  /// Import note (generic fallback): a figure parameter couldn't be mapped and a taxonomy default was used.
  ///
  /// In en, this message translates to:
  /// **'A figure parameter couldn\'t be mapped; a taxonomy default was used.'**
  String get importIssueParamUnmapped;

  /// Import note: a figure's value for the named taxonomy parameter couldn't be converted, so the taxonomy default was used. {param} is a taxonomy parameter name (a safe internal identifier, e.g. “hand”), not untrusted external text.
  ///
  /// In en, this message translates to:
  /// **'The {param} parameter couldn\'t be converted; a taxonomy default was used.'**
  String importIssueParamValueUnmapped(String param);

  /// Import note: a figure supplied more positional parameter values than the taxonomy maps; the surplus was ignored. Both values are the app's own counts.
  ///
  /// In en, this message translates to:
  /// **'A figure had {provided} parameter values but only {mapped} are mapped; the extras were ignored.'**
  String importIssueParamCountUnmapped(int provided, int mapped);

  /// Import note: a Caller's Companion related-dance relationship referenced a dance that wasn't part of this import (not imported this session, or an unresolved/orphan id), so the link was skipped rather than created dangling.
  ///
  /// In en, this message translates to:
  /// **'A related-dance link pointed at a dance that wasn\'t imported; the link was skipped.'**
  String get importIssueRelatedDanceUnresolved;

  /// Lowercase name of the 'composed' dance date field, inserted into import notes such as 'The {field} date couldn't be read'. Matches the danceEditorComposedLabel term.
  ///
  /// In en, this message translates to:
  /// **'composed'**
  String get importDateFieldComposed;

  /// Lowercase name of the 'revised' dance date field, inserted into import notes such as 'The {field} date couldn't be read'. Matches the danceEditorRevisedLabel term.
  ///
  /// In en, this message translates to:
  /// **'revised'**
  String get importDateFieldRevised;

  /// Import review: a per-record error at the discover stage. Generic; raw error detail is not shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'This record couldn\'t be found.'**
  String get importRecordErrorDiscover;

  /// Import review: a per-record error at the fetch stage. Generic; raw error detail is not shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'This record couldn\'t be fetched.'**
  String get importRecordErrorFetch;

  /// Import review: a per-record error at the parse stage. Generic; raw parser detail is not shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'This record couldn\'t be read.'**
  String get importRecordErrorParse;

  /// Import review: a per-record error at the dedupe stage. Generic; raw error detail is not shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'This record couldn\'t be processed.'**
  String get importRecordErrorDedupe;

  /// Import review: a per-record error at the commit stage. Generic; raw error detail is not shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'This record couldn\'t be saved.'**
  String get importRecordErrorCommit;

  /// Explanatory text for the Caller's Companion .USR file import.
  ///
  /// In en, this message translates to:
  /// **'Choose the Caller\'s Companion .USR file to migrate its dances and program history. Nothing is added to your collection until you review and confirm.'**
  String get importReviewUsrSubtitle;

  /// Button to pick a Caller's Companion .USR file.
  ///
  /// In en, this message translates to:
  /// **'Choose .USR file…'**
  String get importReviewChooseUsr;

  /// Confirmation that a binary import file was picked, showing its size.
  ///
  /// In en, this message translates to:
  /// **'File ready ({bytes} bytes).'**
  String importReviewFileReady(int bytes);

  /// Explanatory text for a text/URL import source.
  ///
  /// In en, this message translates to:
  /// **'Choose a file, paste its contents, or fetch it from a URL. Nothing is added to your collection until you review and confirm.'**
  String get importReviewGenericSubtitle;

  /// Button to pick a text import file.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get importReviewChooseFile;

  /// Label for the URL field when the source builds URLs from a dance id.
  ///
  /// In en, this message translates to:
  /// **'Dance URL or id'**
  String get importReviewUrlLabel;

  /// Label for the URL field for a generic URL import source.
  ///
  /// In en, this message translates to:
  /// **'Import from URL'**
  String get importReviewUrlLabelGeneric;

  /// Hint for the URL field showing a full URL or a bare id are both accepted.
  ///
  /// In en, this message translates to:
  /// **'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · or · 1'**
  String get importReviewUrlHint;

  /// Hint for the generic URL import field.
  ///
  /// In en, this message translates to:
  /// **'https://…'**
  String get importReviewUrlHintGeneric;

  /// Button that fetches the import payload from the entered URL.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get importReviewFetch;

  /// Label for the multi-line field where import JSON can be pasted directly.
  ///
  /// In en, this message translates to:
  /// **'Or paste JSON'**
  String get importReviewPasteJson;

  /// Button that plans the import and moves to the review step.
  ///
  /// In en, this message translates to:
  /// **'Review import'**
  String get importReviewReviewButton;

  /// Count summary above the commit button showing how many records will be imported.
  ///
  /// In en, this message translates to:
  /// **'{importable} of {total} will be imported'**
  String importReviewWillImport(int importable, int total);

  /// Secondary summary line shown above the commit button when a shared bundle (share-target or manual pick) carries programs. Appears alongside importReviewWillImport to indicate the programs will be written regardless of how dance rows are dispositioned.
  ///
  /// In en, this message translates to:
  /// **'Also includes {count, plural, =1{1 program} other{{count} programs}}.'**
  String importReviewWillImportPrograms(int count);

  /// Title shown when the import payload could not be parsed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the import'**
  String get importReviewCouldNotRead;

  /// Title shown when the import payload parsed but contained no dances.
  ///
  /// In en, this message translates to:
  /// **'No dances found'**
  String get importReviewNoDancesTitle;

  /// Body text shown when the import payload contained no dances.
  ///
  /// In en, this message translates to:
  /// **'The file did not contain any dances to import.'**
  String get importReviewNoDancesBody;

  /// Button to return to the input step and try a different import file.
  ///
  /// In en, this message translates to:
  /// **'Try another file'**
  String get importReviewTryAnother;

  /// Per-row status shown after a single record has been committed via Edit.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importReviewImported;

  /// Quality chip showing how many of a dance's figures parsed as structured.
  ///
  /// In en, this message translates to:
  /// **'{structured}/{total} structured'**
  String importReviewStructured(int structured, int total);

  /// Quality chip label when a dance's figures are fully custom (unstructured).
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get importReviewCustom;

  /// Per-record option: import this record as a brand-new dance.
  ///
  /// In en, this message translates to:
  /// **'New dance'**
  String get importReviewOptionNewDance;

  /// Per-record option: skip this record (do not import it).
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get importReviewOptionSkip;

  /// Per-record option: re-import onto an existing local dance. The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Re-import onto \"{title}\"'**
  String importReviewOptionReimport(String title);

  /// Per-record option: import this record as a new dance even though a match exists.
  ///
  /// In en, this message translates to:
  /// **'Import as a new (duplicate) dance'**
  String get importReviewOptionDuplicate;

  /// Prompt above the options for a record that ambiguously matches existing dances.
  ///
  /// In en, this message translates to:
  /// **'Possible match — choose how to import:'**
  String get importReviewPossibleMatch;

  /// Per-record option: link to a candidate existing dance with a match percentage. The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Link to \"{title}\" ({percent}% match)'**
  String importReviewOptionLink(String title, int percent);

  /// Pre-commit warning stating how many existing local dances a commit will overwrite.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 existing dance will be overwritten} other{{count} existing dances will be overwritten}}'**
  String importReviewOverwriteWarning(int count);

  /// Screen-reader label that prefixes the overwrite-warning message with 'Warning:'.
  ///
  /// In en, this message translates to:
  /// **'Warning: {message}'**
  String importReviewWarningPrefix(String message);

  /// Title of the dialog shown after an import commit finishes.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importReviewComplete;

  /// Advisory (non-blocking) warning shown on the review screen when a shared bundle carries an unusually large number of entities.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This import contains 1 item — more than expected for a normal share.} other{This import contains {count} items — more than expected for a normal share.}}'**
  String sharedImportSoftCapWarning(int count);

  /// Transient snackbar message shown after a shared bundle is imported, alongside an Undo action.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Import complete.} =1{Imported 1 item.} other{Imported {count} items.}}'**
  String sharedImportComplete(int count);

  /// Shown on the review screen when a shared bundle carries programs but no dances, so the user can still consent to importing the programs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This share contains 1 program and no dances.} other{This share contains {count} programs and no dances.}}'**
  String sharedImportProgramsOnly(int count);

  /// Import result summary line: number of dances created.
  ///
  /// In en, this message translates to:
  /// **'Created: {count}'**
  String importReviewSummaryCreated(int count);

  /// Import result summary line: number of dances re-imported.
  ///
  /// In en, this message translates to:
  /// **'Re-imported: {count}'**
  String importReviewSummaryReimported(int count);

  /// Import result summary line: number of dances linked.
  ///
  /// In en, this message translates to:
  /// **'Linked: {count}'**
  String importReviewSummaryLinked(int count);

  /// Import result summary line: number of dances duplicated.
  ///
  /// In en, this message translates to:
  /// **'Duplicated: {count}'**
  String importReviewSummaryDuplicated(int count);

  /// Import result summary line: number of records imported as a distinct figure-level variation of an existing dance (issue #686).
  ///
  /// In en, this message translates to:
  /// **'Imported as a variation: {count}'**
  String importReviewSummaryVariation(int count);

  /// Import result summary line: number of records skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped: {count}'**
  String importReviewSummarySkipped(int count);

  /// Import result summary line: number of programs imported (Caller's Companion only).
  ///
  /// In en, this message translates to:
  /// **'Programs: {count}'**
  String importReviewSummaryPrograms(int count);

  /// Import result detail: how many imported programs updated an existing one.
  ///
  /// In en, this message translates to:
  /// **'{count} updated (re-imported)'**
  String importReviewProgramsUpdated(int count);

  /// Import result heading listing program-level notes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} program note(s):} other{{count} program note(s):}}'**
  String importReviewProgramNotes(int count);

  /// Import result heading listing records that failed to import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} record(s) failed to import:} other{{count} record(s) failed to import:}}'**
  String importReviewRecordsFailed(int count);

  /// Heading above the list of records that could not be parsed from the import batch.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} record(s) couldn\'t be read (the rest can still be imported):} other{{count} record(s) couldn\'t be read (the rest can still be imported):}}'**
  String importReviewBatchErrors(int count);

  /// Fallback name for an imported program with no title.
  ///
  /// In en, this message translates to:
  /// **'Untitled program'**
  String get importReviewUntitledProgram;

  /// Undo button label when the import created both dances and programs.
  ///
  /// In en, this message translates to:
  /// **'Undo (removes the imported dances and programs)'**
  String get importReviewUndoWithPrograms;

  /// Snackbar confirming the import was undone.
  ///
  /// In en, this message translates to:
  /// **'Import undone.'**
  String get importReviewUndone;

  /// Snackbar shown when committing a single record so it can be edited fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import that dance to edit.'**
  String get importReviewEditError;

  /// Snackbar shown when an import commit (or commit-for-edit) throws. The raw exception is logged (debugPrint), never shown, so storage internals/paths can't leak to the UI (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the import.'**
  String get importReviewImportError;

  /// Heading of the inline figure-diff block shown when a confidently-matched candidate's figures differ from the incoming record (issue #686). The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Variation of \"{title}\"?'**
  String importReviewVariationTitle(String title);

  /// Explanatory body text under the issue #686 variation-diff heading. The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'This dance\'s title and caller match \"{title}\", but its figures are different. Review how they differ, then choose how to import it.'**
  String importReviewVariationBody(String title);

  /// Per-record option: import this record as a new, distinct dance and (optionally) link it back to the matched dance as a related dance (issue #686). The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Import as a variation of \"{title}\"'**
  String importReviewOptionVariation(String title);

  /// Per-record option in the issue #686 variation block: treat this record as the same dance as the matched candidate (equivalent to the ordinary link option). The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Same dance as \"{title}\" (link/update)'**
  String importReviewOptionSameDance(String title);

  /// Checkbox label controlling whether choosing "import as a variation" also creates a symmetric relatedDance link back to the matched dance (issue #686). Defaults on. The title is an untrusted local value rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Also link back to \"{title}\" as a related dance'**
  String importReviewOptionLinkBack(String title);

  /// Section label above the figure lines present in the incoming record but not the matched dance, in the issue #686 inline diff.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get importReviewVariationAdded;

  /// Section label above the figure lines present in the matched dance but not the incoming record, in the issue #686 inline diff.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get importReviewVariationRemoved;

  /// Footer note in the issue #686 inline figure diff when the computed differences exceed the rendered cap (kMaxFigureDiffLines) or the comparison itself was too large to compute in full (kMaxFiguresForDiff).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more difference not shown} other{{count} more differences not shown}}'**
  String importReviewVariationMoreDifferences(int count);

  /// Section heading for the primary dance metadata fields in the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get danceEditorDetailsSection;

  /// Required dance/source title field label; the asterisk marks the field as required.
  ///
  /// In en, this message translates to:
  /// **'Title *'**
  String get danceEditorTitleRequiredLabel;

  /// Validation error shown when a required title field is blank.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get danceEditorTitleRequired;

  /// Field label for the dance author/choreographer picker.
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get danceEditorAuthorsLabel;

  /// Field label for the dance formation picker.
  ///
  /// In en, this message translates to:
  /// **'Formation'**
  String get danceEditorFormationLabel;

  /// Text field label for optional formation details.
  ///
  /// In en, this message translates to:
  /// **'Formation detail (optional)'**
  String get danceEditorFormationDetailLabel;

  /// Text field label for entering the dance phrase structure.
  ///
  /// In en, this message translates to:
  /// **'Phrase structure'**
  String get danceEditorPhraseStructureLabel;

  /// Hint explaining the dance phrase-structure field syntax.
  ///
  /// In en, this message translates to:
  /// **'Blank = standard A1 A2 B1 B2; else e.g. 6*8*2'**
  String get danceEditorPhraseStructureHint;

  /// Section heading for the editable figure list in the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Figures'**
  String get danceEditorFiguresSection;

  /// Helper text above the figure list explaining type-ahead figure entry.
  ///
  /// In en, this message translates to:
  /// **'Type a move (e.g. \"sw\" → swing) and press Enter to add it with default params; unmatched text becomes a custom figure.'**
  String get danceEditorFiguresHelp;

  /// Section heading for the dance notes fields.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get danceEditorNotesSection;

  /// Text field label for caller notes.
  ///
  /// In en, this message translates to:
  /// **'Calling notes'**
  String get danceEditorCallingNotesLabel;

  /// Text field label for the short hook/why-call-this note.
  ///
  /// In en, this message translates to:
  /// **'Hook'**
  String get danceEditorHookLabel;

  /// Hint text for the hook field.
  ///
  /// In en, this message translates to:
  /// **'One-line \"why call this\"'**
  String get danceEditorHookHint;

  /// Text field label for the dedicated per-dance walkthrough (step-by-step description), distinct from the shorter calling notes.
  ///
  /// In en, this message translates to:
  /// **'Walkthrough'**
  String get danceEditorWalkthroughLabel;

  /// Helper text under the walkthrough field explaining what to write there.
  ///
  /// In en, this message translates to:
  /// **'Step-by-step description of the dance and its transitions'**
  String get danceEditorWalkthroughHelper;

  /// Button that reveals the optional per-figure walkthrough step-description field in the figure editor (#411).
  ///
  /// In en, this message translates to:
  /// **'Add walkthrough step'**
  String get danceEditorAddWalkthroughStep;

  /// Label for the per-figure walkthrough step-description text field (#411).
  ///
  /// In en, this message translates to:
  /// **'Walkthrough step (optional)'**
  String get danceEditorWalkthroughStepLabel;

  /// Helper text under the per-figure walkthrough step field explaining learn-on-first-entry (#411).
  ///
  /// In en, this message translates to:
  /// **'Saved as your default for this figure and reused wherever it appears.'**
  String get danceEditorWalkthroughStepHelper;

  /// Title of the prompt shown when a per-figure walkthrough snippet differs from the saved default (#411).
  ///
  /// In en, this message translates to:
  /// **'Update your saved snippet?'**
  String get danceEditorSnippetDivergenceTitle;

  /// Body of the divergence prompt for a per-figure walkthrough snippet (#411).
  ///
  /// In en, this message translates to:
  /// **'This differs from the walkthrough snippet you saved for this figure. Use the new text everywhere, or just in this dance?'**
  String get danceEditorSnippetDivergenceBody;

  /// Choice that updates the global default walkthrough snippet for this figure (#411).
  ///
  /// In en, this message translates to:
  /// **'Use everywhere'**
  String get danceEditorSnippetUseEverywhere;

  /// Choice that keeps a per-figure walkthrough snippet as an override for the current dance only (#411).
  ///
  /// In en, this message translates to:
  /// **'Just this dance'**
  String get danceEditorSnippetJustThisDance;

  /// Button that assembles the walkthrough text from the dance's per-figure snippets (#411).
  ///
  /// In en, this message translates to:
  /// **'Fill from snippets'**
  String get danceEditorFillWalkthroughFromSnippets;

  /// Title of the confirmation shown before overwriting existing walkthrough text with one assembled from snippets (#411).
  ///
  /// In en, this message translates to:
  /// **'Replace walkthrough?'**
  String get danceEditorFillWalkthroughReplaceTitle;

  /// Body of the confirmation before overwriting the walkthrough with an assembled one (#411).
  ///
  /// In en, this message translates to:
  /// **'This replaces the current walkthrough with text assembled from your figure snippets.'**
  String get danceEditorFillWalkthroughReplaceBody;

  /// Confirm button that overwrites the walkthrough with an assembled one (#411).
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get danceEditorFillWalkthroughReplaceConfirm;

  /// Message shown when there are no snippets to assemble a walkthrough from (#411).
  ///
  /// In en, this message translates to:
  /// **'None of these figures have a saved walkthrough snippet yet.'**
  String get danceEditorFillWalkthroughEmpty;

  /// Settings row title opening the personal walkthrough-snippet library editor (#411).
  ///
  /// In en, this message translates to:
  /// **'Walkthrough snippets'**
  String get settingsWalkthroughSnippetsTitle;

  /// Settings row subtitle for the walkthrough-snippet library editor (#411).
  ///
  /// In en, this message translates to:
  /// **'Your saved per-figure step descriptions'**
  String get settingsWalkthroughSnippetsSubtitle;

  /// Header on the walkthrough-snippet library editor screen (#411).
  ///
  /// In en, this message translates to:
  /// **'Saved walkthrough snippets'**
  String get settingsWalkthroughSnippetsHeader;

  /// Explanatory text at the top of the walkthrough-snippet library editor (#411).
  ///
  /// In en, this message translates to:
  /// **'These per-figure step descriptions pre-fill walkthroughs when you edit a dance. Editing one here updates the default used everywhere.'**
  String get settingsWalkthroughSnippetsDescription;

  /// Empty-state text on the walkthrough-snippet library editor when the library is empty (#411).
  ///
  /// In en, this message translates to:
  /// **'No saved snippets yet. Add walkthrough step descriptions while editing a dance\'s figures.'**
  String get settingsWalkthroughSnippetsEmpty;

  /// Count of saved walkthrough snippets (#411).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 snippet} other{{count} snippets}}'**
  String settingsWalkthroughSnippetsCount(int count);

  /// Title of the confirmation before deleting a saved walkthrough snippet (#411).
  ///
  /// In en, this message translates to:
  /// **'Delete snippet?'**
  String get settingsWalkthroughSnippetDeleteTitle;

  /// Body of the confirmation before deleting a saved walkthrough snippet (#411).
  ///
  /// In en, this message translates to:
  /// **'This removes the saved default for this figure. Dances keep any walkthrough text you already wrote.'**
  String get settingsWalkthroughSnippetDeleteBody;

  /// Title of the dialog for editing a saved walkthrough snippet's text (#411).
  ///
  /// In en, this message translates to:
  /// **'Edit snippet'**
  String get settingsWalkthroughSnippetEditTitle;

  /// Expansion tile title for less frequently used dance metadata fields.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get danceEditorMoreDetailsTitle;

  /// Dropdown label for the dance status field.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get danceEditorStatusLabel;

  /// Subtitle explaining the mixed-level checkbox in the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Spans the difficulty scale'**
  String get danceEditorMixedLevelSubtitle;

  /// Subtitle explaining the mixer checkbox in the dance editor: the dance progresses dancers to a new partner each time through the sequence.
  ///
  /// In en, this message translates to:
  /// **'Dancers change partners each time through'**
  String get danceEditorMixerSubtitle;

  /// Label for the partial date when the dance was composed.
  ///
  /// In en, this message translates to:
  /// **'Composed'**
  String get danceEditorComposedLabel;

  /// Helper text for the composed-date field.
  ///
  /// In en, this message translates to:
  /// **'When the dance was composed (year, or add month/day)'**
  String get danceEditorComposedHelper;

  /// Label for the partial date when the dance was last revised.
  ///
  /// In en, this message translates to:
  /// **'Revised'**
  String get danceEditorRevisedLabel;

  /// Helper text for the revised-date field.
  ///
  /// In en, this message translates to:
  /// **'When the dance was last revised by its author'**
  String get danceEditorRevisedHelper;

  /// Field label for the dance tag picker.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get danceEditorTagsLabel;

  /// Field label for suggested tunes.
  ///
  /// In en, this message translates to:
  /// **'Tunes'**
  String get danceEditorTunesLabel;

  /// Field label for URL links attached to a dance.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get danceEditorLinksLabel;

  /// Field label for published sources cited by a dance.
  ///
  /// In en, this message translates to:
  /// **'Published sources'**
  String get danceEditorPublishedSourcesLabel;

  /// Field label for related dance cross-references.
  ///
  /// In en, this message translates to:
  /// **'Related dances'**
  String get danceEditorRelatedDancesLabel;

  /// Field label for custom metadata fields in the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get danceEditorCustomFieldsLabel;

  /// Label and semantics label for the dance rating control.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get danceEditorRatingLabel;

  /// Semantics value announced when a dance has no rating.
  ///
  /// In en, this message translates to:
  /// **'unrated'**
  String get danceEditorRatingUnrated;

  /// Semantics value for a set dance rating.
  ///
  /// In en, this message translates to:
  /// **'{rating} of {max} stars'**
  String danceEditorRatingValue(int rating, int max);

  /// Tooltip and icon semantics label for setting a star rating.
  ///
  /// In en, this message translates to:
  /// **'Set rating to {rating} of {max} stars'**
  String danceEditorSetRatingTooltip(int rating, int max);

  /// Tooltip and icon semantics label for clearing a star rating.
  ///
  /// In en, this message translates to:
  /// **'Clear rating'**
  String get danceEditorClearRating;

  /// Dropdown label for dance difficulty level.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get danceEditorLevelLabel;

  /// Dropdown option meaning no dance level is set.
  ///
  /// In en, this message translates to:
  /// **'Unspecified'**
  String get danceEditorLevelUnspecified;

  /// Partial-date field label for the year component.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get danceEditorYearLabel;

  /// Hint text showing an example year.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1989'**
  String get danceEditorYearHint;

  /// Validation error for a partial-date year outside the supported range.
  ///
  /// In en, this message translates to:
  /// **'1–9999'**
  String get danceEditorYearRangeError;

  /// Partial-date dropdown label for the month component.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get danceEditorMonthLabel;

  /// Partial-date dropdown label for the day component.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get danceEditorDayLabel;

  /// Abbreviated month label "Jan" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get danceEditorMonthJan;

  /// Abbreviated month label "Feb" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get danceEditorMonthFeb;

  /// Abbreviated month label "Mar" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get danceEditorMonthMar;

  /// Abbreviated month label "Apr" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get danceEditorMonthApr;

  /// Abbreviated month label "May" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get danceEditorMonthMay;

  /// Abbreviated month label "Jun" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get danceEditorMonthJun;

  /// Abbreviated month label "Jul" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get danceEditorMonthJul;

  /// Abbreviated month label "Aug" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get danceEditorMonthAug;

  /// Abbreviated month label "Sep" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get danceEditorMonthSep;

  /// Abbreviated month label "Oct" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get danceEditorMonthOct;

  /// Abbreviated month label "Nov" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get danceEditorMonthNov;

  /// Abbreviated month label "Dec" in the partial-date picker.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get danceEditorMonthDec;

  /// Full month name "January", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get monthFullJanuary;

  /// Full month name "February", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get monthFullFebruary;

  /// Full month name "March", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get monthFullMarch;

  /// Full month name "April", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'April'**
  String get monthFullApril;

  /// Full month name "May", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthFullMay;

  /// Full month name "June", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'June'**
  String get monthFullJune;

  /// Full month name "July", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'July'**
  String get monthFullJuly;

  /// Full month name "August", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'August'**
  String get monthFullAugust;

  /// Full month name "September", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get monthFullSeptember;

  /// Full month name "October", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'October'**
  String get monthFullOctober;

  /// Full month name "November", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'November'**
  String get monthFullNovember;

  /// Full month name "December", used to render the MMMM token in a custom date format (issue #632).
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get monthFullDecember;

  /// Hint text for adding a suggested tune to a dance.
  ///
  /// In en, this message translates to:
  /// **'Add a suggested tune…'**
  String get danceEditorAddTuneHint;

  /// Tooltip for the button that adds the typed tune.
  ///
  /// In en, this message translates to:
  /// **'Add tune'**
  String get danceEditorAddTuneTooltip;

  /// Heading for non-blocking validation warnings in the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get danceEditorWarningsTitle;

  /// Warning shown in the dance editor when the figures' total beat count doesn't match the phrase structure (overflow or underflow). Both values are the app's own beat counts.
  ///
  /// In en, this message translates to:
  /// **'The figures total {actual} beats; the phrase structure expects {expected}.'**
  String validationPhraseBeatMismatch(int actual, int expected);

  /// Field error shown under the dance editor's phrase-structure input when the entered text can't be parsed. Generic; the raw parser detail is not shown to users (only in debug builds).
  ///
  /// In en, this message translates to:
  /// **'That phrase structure isn\'t valid.'**
  String get validationPhraseInvalid;

  /// Program-editor warning: an alternate program slot appears with no primary slot before it. {position} is the slot's 1-based position.
  ///
  /// In en, this message translates to:
  /// **'The alternate at position {position} has no preceding primary slot.'**
  String validationOrphanedAlt(int position);

  /// Program-editor warning: an alternate program slot (identified by its user-entered text) appears with no primary slot before it. {text} is user-entered content rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'The alternate at position {position} (“{text}”) has no preceding primary slot.'**
  String validationOrphanedAltNamed(int position, String text);

  /// Dialect-editor validation error: a role/move term maps to an empty substitution. {term} is the user-entered source term rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'The substitution for “{term}” is empty.'**
  String validationEmptySubstitution(String term);

  /// Dialect-editor validation error: two source terms map to the same substitution, so reversing the dialect would be ambiguous. All three values are user-entered dialect terms rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'“{source}” and “{existing}” both map to “{substitution}” — reversal would be ambiguous.'**
  String validationDialectCollision(
    String source,
    String existing,
    String substitution,
  );

  /// Generic fallback shown when a validation finding has no specific localized message. Deliberately non-leaking; specific detail (if any) appears only in debug builds.
  ///
  /// In en, this message translates to:
  /// **'This item has a validation issue.'**
  String get validationGeneric;

  /// Semantics label announcing discouraged lingo terms in a prose field.
  ///
  /// In en, this message translates to:
  /// **'Discouraged term: {term}'**
  String danceEditorDiscouragedTermSemantic(String term);

  /// Visible warning text listing discouraged lingo terms in a prose field.
  ///
  /// In en, this message translates to:
  /// **'Discouraged: {term}'**
  String danceEditorDiscouragedTermText(String term);

  /// Link-kind dropdown option for a source link.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get danceEditorLinkKindSource;

  /// Link-kind dropdown option for a video link.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get danceEditorLinkKindVideo;

  /// Link-kind dropdown option for another kind of URL link.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get danceEditorLinkKindOther;

  /// Text field label for a URL.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get danceEditorUrlLabel;

  /// Text field label for an optional link label.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get danceEditorLabelOptional;

  /// Tooltip for removing a URL link row.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get danceEditorRemoveLinkTooltip;

  /// Button label for adding a URL link row.
  ///
  /// In en, this message translates to:
  /// **'Add link'**
  String get danceEditorAddLink;

  /// Fallback text when a related dance reference points to a missing dance.
  ///
  /// In en, this message translates to:
  /// **'(missing dance)'**
  String get danceEditorMissingDance;

  /// Text field label for an optional note.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get danceEditorNoteOptionalLabel;

  /// Tooltip for removing a related-dance link row.
  ///
  /// In en, this message translates to:
  /// **'Remove related dance'**
  String get danceEditorRemoveRelatedDanceTooltip;

  /// Button label for adding a related-dance link row.
  ///
  /// In en, this message translates to:
  /// **'Add related dance'**
  String get danceEditorAddRelatedDance;

  /// Type-ahead field label for choosing a related dance.
  ///
  /// In en, this message translates to:
  /// **'Related dance'**
  String get danceEditorRelatedDanceLabel;

  /// Hint text for a type-ahead search field.
  ///
  /// In en, this message translates to:
  /// **'Type to search…'**
  String get danceEditorTypeToSearchHint;

  /// Tooltip for editing an existing shared item from a chip.
  ///
  /// In en, this message translates to:
  /// **'Edit {item}'**
  String danceEditorEditItemTooltip(String item);

  /// Hint text for a type-ahead field that can add an existing item or create a new one.
  ///
  /// In en, this message translates to:
  /// **'Type to add or create…'**
  String get danceEditorTypeToAddOrCreateHint;

  /// Type-ahead option label for creating a new item with the typed name/title.
  ///
  /// In en, this message translates to:
  /// **'Create \"{name}\"'**
  String danceEditorCreateQuotedName(String name);

  /// Fallback text when a source citation points to a missing source.
  ///
  /// In en, this message translates to:
  /// **'(unknown source)'**
  String get danceEditorUnknownSource;

  /// Text field label for an optional cited page.
  ///
  /// In en, this message translates to:
  /// **'Page (optional)'**
  String get danceEditorPageOptionalLabel;

  /// Text field label for an optional source number.
  ///
  /// In en, this message translates to:
  /// **'Number (optional)'**
  String get danceEditorNumberOptionalLabel;

  /// Hint text for attaching or creating a published source citation.
  ///
  /// In en, this message translates to:
  /// **'Cite a source: type to add or create…'**
  String get danceEditorCiteSourceHint;

  /// Clean snackbar shown when saving a dance fails; the raw exception is logged instead of shown (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the dance.'**
  String get danceEditorSaveError;

  /// Fallback dance title used when deleting a dance whose original title is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Dance'**
  String get danceEditorFallbackDanceTitle;

  /// Dialog title for a pending autosave draft.
  ///
  /// In en, this message translates to:
  /// **'Unsaved draft'**
  String get danceEditorUnsavedDraftTitle;

  /// Dialog body asking whether to restore a pending autosave draft.
  ///
  /// In en, this message translates to:
  /// **'You have an unsaved draft for this dance. Would you like to restore it?'**
  String get danceEditorUnsavedDraftMessage;

  /// Button label for discarding a draft or unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get danceEditorDiscard;

  /// Button label for restoring an autosave draft.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get danceEditorRestore;

  /// Dialog title asking whether to leave the dirty dance editor.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get danceEditorDiscardChangesTitle;

  /// Dialog body warning that leaving the editor will discard unsaved dance changes.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes to this dance.'**
  String get danceEditorDiscardChangesMessage;

  /// Button label that dismisses the discard-changes dialog and stays in the editor.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get danceEditorKeepEditing;

  /// App-bar title for creating a new dance.
  ///
  /// In en, this message translates to:
  /// **'New dance'**
  String get danceEditorNewDanceTitle;

  /// App-bar title for editing an existing dance.
  ///
  /// In en, this message translates to:
  /// **'Edit dance'**
  String get danceEditorEditDanceTitle;

  /// Semantics label for the redo action.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get danceEditorRedoLabel;

  /// Tooltip for the undo app-bar action including its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Undo (Ctrl+Z)'**
  String get danceEditorUndoShortcutTooltip;

  /// Tooltip for the redo app-bar action including its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Redo (Ctrl+Shift+Z)'**
  String get danceEditorRedoShortcutTooltip;

  /// Tooltip for the app-bar action that deletes the current dance.
  ///
  /// In en, this message translates to:
  /// **'Delete dance'**
  String get danceEditorDeleteDanceTooltip;

  /// Message shown when the dance editor fails to load a dance.
  ///
  /// In en, this message translates to:
  /// **'Could not load the dance.'**
  String get danceEditorLoadError;

  /// Dialog title for editing shared choreographer/contact details.
  ///
  /// In en, this message translates to:
  /// **'Choreographer details'**
  String get danceEditorChoreographerDetailsTitle;

  /// Introductory copy explaining shared and private choreographer details.
  ///
  /// In en, this message translates to:
  /// **'These details are shared across every dance credited to this author. Email, location, and the deceased mark are private — stored only on this device and never shared or exported.'**
  String get danceEditorChoreographerDetailsIntro;

  /// Required name field label; the asterisk marks the field as required.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get danceEditorNameRequiredLabel;

  /// Validation error shown when a required name field is blank.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get danceEditorNameRequired;

  /// Text field label for a website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get danceEditorWebsiteLabel;

  /// Text field label for a private email address.
  ///
  /// In en, this message translates to:
  /// **'Email (private)'**
  String get danceEditorEmailPrivateLabel;

  /// Text field label for a private location.
  ///
  /// In en, this message translates to:
  /// **'Location (private)'**
  String get danceEditorLocationPrivateLabel;

  /// Text field label for notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get danceEditorNotesLabel;

  /// Switch label marking a choreographer as deceased.
  ///
  /// In en, this message translates to:
  /// **'Deceased'**
  String get danceEditorDeceasedLabel;

  /// Dialog title for editing a shared published source.
  ///
  /// In en, this message translates to:
  /// **'Source details'**
  String get danceEditorSourceDetailsTitle;

  /// Introductory copy explaining shared published-source details.
  ///
  /// In en, this message translates to:
  /// **'These details are shared across every dance that cites this source. Editing them here updates the source everywhere it is referenced.'**
  String get danceEditorSourceDetailsIntro;

  /// Text field label for a source author or editor.
  ///
  /// In en, this message translates to:
  /// **'Author / editor'**
  String get danceEditorSourceAuthorEditorLabel;

  /// Validation error shown when a numeric source year is not an integer.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number'**
  String get danceEditorEnterWholeNumber;

  /// Validation error shown when a source year is zero or negative.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive year'**
  String get danceEditorEnterPositiveYear;

  /// Screen-reader announcement after adding a structured figure row.
  ///
  /// In en, this message translates to:
  /// **'Added figure {count}. Choose a move.'**
  String danceEditorAddedFigureChooseMove(int count);

  /// Screen-reader announcement after pasting a cut figure.
  ///
  /// In en, this message translates to:
  /// **'Figure pasted at position {position}.'**
  String danceEditorFigurePastedAnnouncement(int position);

  /// Screen-reader announcement after moving a figure row.
  ///
  /// In en, this message translates to:
  /// **'Moved to position {position} of {total}.'**
  String danceEditorFigureMovedAnnouncement(int position, int total);

  /// Screen-reader announcement when a figure editor is opened.
  ///
  /// In en, this message translates to:
  /// **'Editing figure {position}, {name}.'**
  String danceEditorEditingFigureAnnouncement(int position, String name);

  /// Screen-reader announcement when a figure editor is collapsed.
  ///
  /// In en, this message translates to:
  /// **'Collapsed figure {position}.'**
  String danceEditorCollapsedFigureAnnouncement(int position);

  /// Screen-reader announcement when free-text figure entry opens.
  ///
  /// In en, this message translates to:
  /// **'Type a figure and press Enter to add it.'**
  String get danceEditorTypeFigureAnnouncement;

  /// Screen-reader announcement after adding figure(s) from free-text entry.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 figure. Type another, or press Escape to finish.} other{Added {count} figures. Type another, or press Escape to finish.}}'**
  String danceEditorFreeTextFiguresAddedAnnouncement(int count);

  /// Screen-reader announcement after deleting a figure row.
  ///
  /// In en, this message translates to:
  /// **'Deleted figure {position}. Undo available.'**
  String danceEditorDeletedFigureAnnouncement(int position);

  /// Screen-reader announcement after duplicating a figure row.
  ///
  /// In en, this message translates to:
  /// **'Duplicated figure {position}.'**
  String danceEditorDuplicatedFigureAnnouncement(int position);

  /// Button label for adding the first figure to an empty dance.
  ///
  /// In en, this message translates to:
  /// **'Add first figure'**
  String get danceEditorAddFirstFigure;

  /// Banner text shown while a figure row is cut and awaiting a paste destination.
  ///
  /// In en, this message translates to:
  /// **'\"{figure}\" is cut — tap Paste to place it.'**
  String danceEditorCutBanner(String figure);

  /// Semantics label for pasting a cut figure at the top of the list.
  ///
  /// In en, this message translates to:
  /// **'Paste before first figure'**
  String get danceEditorPasteBeforeFirstFigure;

  /// Semantics label for pasting a cut figure after another figure.
  ///
  /// In en, this message translates to:
  /// **'Paste after {figure}'**
  String danceEditorPasteAfterFigure(String figure);

  /// Button label for adding another figure row.
  ///
  /// In en, this message translates to:
  /// **'Add figure'**
  String get danceEditorAddFigure;

  /// Semantics label for pasting a cut figure at the end of the list.
  ///
  /// In en, this message translates to:
  /// **'Paste at end of figure list'**
  String get danceEditorPasteAtEndOfFigureList;

  /// Text field label for free-text figure entry.
  ///
  /// In en, this message translates to:
  /// **'Type a figure'**
  String get danceEditorTypeFigureLabel;

  /// Helper text for free-text figure entry.
  ///
  /// In en, this message translates to:
  /// **'e.g. \"neighbor balance & swing\" or \"16 circle left 3/4\". Enter adds it; unrecognized text is kept as a custom figure.'**
  String get danceEditorTypeFigureHelper;

  /// Button label for a paste destination in the figure list.
  ///
  /// In en, this message translates to:
  /// **'Paste here'**
  String get danceEditorPasteHere;

  /// Fallback display name for a figure row with no move selected.
  ///
  /// In en, this message translates to:
  /// **'Empty figure'**
  String get danceEditorEmptyFigureName;

  /// Fallback display name for a custom figure with no text.
  ///
  /// In en, this message translates to:
  /// **'Custom figure'**
  String get danceEditorCustomFigureName;

  /// Collapsed-row text for an empty figure draft.
  ///
  /// In en, this message translates to:
  /// **'(empty — choose a move)'**
  String get danceEditorEmptyFigureSummary;

  /// Screen-reader phrase for an empty figure draft.
  ///
  /// In en, this message translates to:
  /// **'empty figure, choose a move'**
  String get danceEditorEmptyFigureSemantic;

  /// Composite screen-reader label for a figure row, including optional import-gap, progression, beats, and note details plus row position.
  ///
  /// In en, this message translates to:
  /// **'{main}{importGap, select, yes{, {importGapText}} other{}}{progression, select, yes{, progression} other{}}{hasMove, select, yes{, {beats, plural, =1{1 beat} other{{beats} beats}}} other{}}{hasNote, select, yes{, note: {note}} other{}}. Figure {position} of {total}.'**
  String danceEditorFigureSummarySemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    String hasMove,
    int beats,
    String hasNote,
    String note,
    int position,
    int total,
  );

  /// Semantics hint for opening a figure row editor.
  ///
  /// In en, this message translates to:
  /// **'Activate to edit'**
  String get danceEditorActivateToEditHint;

  /// Semantics label for the drag handle on a figure row.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder {figure}'**
  String danceEditorDragToReorderFigure(String figure);

  /// Tooltip for the overflow menu on a figure row.
  ///
  /// In en, this message translates to:
  /// **'Actions for {figure}'**
  String danceEditorFigureActionsTooltip(String figure);

  /// Menu item label for moving a figure row upward.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get danceEditorMoveUp;

  /// Menu item label for moving a figure row downward.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get danceEditorMoveDown;

  /// Menu item label for cutting a figure row before pasting it elsewhere.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get danceEditorCut;

  /// Menu item label for clearing a figure progression marker.
  ///
  /// In en, this message translates to:
  /// **'Clear progression'**
  String get danceEditorClearProgression;

  /// Menu item label for marking a figure as carrying the progression.
  ///
  /// In en, this message translates to:
  /// **'Mark progression'**
  String get danceEditorMarkProgression;

  /// Menu item label that groups this figure row with the one immediately after it into a meanwhile (concurrent) group (#593). Hidden when there is no next row or either row is already a meanwhile group.
  ///
  /// In en, this message translates to:
  /// **'Group with next as meanwhile'**
  String get danceEditorGroupWithNext;

  /// Visible heading for a meanwhile group's expanded editor and its display name elsewhere (drag handle, cut banner, duplicate announcement).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Meanwhile ({count} sides)}}'**
  String danceEditorMeanwhileGroupLabel(int count);

  /// Screen-reader label for a meanwhile group's expanded editor region, making explicit that the beat count is SHARED across all sides, not per side.
  ///
  /// In en, this message translates to:
  /// **'Meanwhile group, {count, plural, =1{1 concurrent figure} other{{count} concurrent figures}}, {beats, plural, =1{1 shared beat} other{{beats} shared beats}}.'**
  String danceEditorMeanwhileGroupSemantic(int count, int beats);

  /// Compact heading for one concurrent side within a meanwhile group's editor.
  ///
  /// In en, this message translates to:
  /// **'Side {number}'**
  String danceEditorMeanwhileSideLabel(int number);

  /// Screen-reader label identifying one side's position among the meanwhile group's concurrent sides.
  ///
  /// In en, this message translates to:
  /// **'Side {number} of {total}.'**
  String danceEditorMeanwhileSideSemantic(int number, int total);

  /// Button label that adds another concurrent side to a meanwhile group.
  ///
  /// In en, this message translates to:
  /// **'Add side'**
  String get danceEditorAddMeanwhileSide;

  /// Icon button tooltip/semantics for removing one side from a meanwhile group. Removing down to one side collapses the group back to a plain figure.
  ///
  /// In en, this message translates to:
  /// **'Remove this side'**
  String get danceEditorRemoveMeanwhileSide;

  /// Inline message shown in place of the add-side button once a meanwhile group has reached the maximum allowed number of concurrent sides.
  ///
  /// In en, this message translates to:
  /// **'Maximum of {max} concurrent figures.'**
  String danceEditorMeanwhileSidesCapReached(int max);

  /// Read-only explanation for a figure whose move id is not in the active taxonomy.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized move \"{move}\" — not in this version\'s taxonomy. Shown read-only so its data is preserved; it will edit normally again if the move becomes known. You can still reorder or delete it.'**
  String danceEditorUnrecognizedMoveReadOnly(String move);

  /// Button label that collapses additional figure parameter editors.
  ///
  /// In en, this message translates to:
  /// **'Fewer options'**
  String get danceEditorFewerOptions;

  /// Button label that expands additional figure parameter editors, showing the number hidden.
  ///
  /// In en, this message translates to:
  /// **'More options ({count})'**
  String danceEditorMoreOptions(int count);

  /// Button label for revealing a figure note field.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get danceEditorAddNote;

  /// Tooltip for applying bold markup to selected note/custom text.
  ///
  /// In en, this message translates to:
  /// **'Bold (*text*)'**
  String get danceEditorBoldTooltip;

  /// Tooltip for applying underline markup to selected note/custom text.
  ///
  /// In en, this message translates to:
  /// **'Underline (_text_)'**
  String get danceEditorUnderlineTooltip;

  /// Text field label for editing a custom figure description.
  ///
  /// In en, this message translates to:
  /// **'Custom figure text'**
  String get danceEditorCustomFigureTextLabel;

  /// Helper text explaining lingo-aware styling in a custom figure text field.
  ///
  /// In en, this message translates to:
  /// **'Move names dotted·underline, role terms underlined, discouraged terms struck through'**
  String get danceEditorLingoStylingHelper;

  /// Summary of total figure beats versus the phrase-structure expectation.
  ///
  /// In en, this message translates to:
  /// **'Total: {total} / {expected} beats'**
  String danceEditorBeatTotal(int total, int expected);

  /// Warning text when total figure beats exceed the expected phrase length.
  ///
  /// In en, this message translates to:
  /// **'Over by {beats} beats'**
  String danceEditorOverByBeats(int beats);

  /// Warning text when total figure beats are below the expected phrase length.
  ///
  /// In en, this message translates to:
  /// **'Under by {beats} beats'**
  String danceEditorUnderByBeats(int beats);

  /// Tooltip for decrementing a numeric figure parameter.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get danceEditorLessTooltip;

  /// Shown in the figure parameter editor when the source never stated a value for this parameter, so none may be assumed. Used by the rotation stepper and by the choice dropdowns whose parameter admits the unstated state.
  ///
  /// In en, this message translates to:
  /// **'not stated'**
  String get danceEditorParamNotStated;

  /// Tooltip for the button that clears a figure parameter back to the unstated state.
  ///
  /// In en, this message translates to:
  /// **'Clear (not stated)'**
  String get danceEditorParamClearTooltip;

  /// Tooltip for incrementing a numeric figure parameter.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get danceEditorMoreTooltip;

  /// Rotation amount shown in the figure parameter editor.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{formatted} turn} other{{formatted} turns}}'**
  String danceEditorTurnCount(num count, String formatted);

  /// Generic 'Back' affordance shared across screens.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Generic 'Remove' affordance shared across screens.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Update banner status while the installer is downloading (no percentage yet).
  ///
  /// In en, this message translates to:
  /// **'Downloading {appName} {version}…'**
  String updateBannerDownloading(String appName, String version);

  /// Update banner status while downloading, with completion percentage.
  ///
  /// In en, this message translates to:
  /// **'Downloading {appName} {version}… {pct}%'**
  String updateBannerDownloadingPct(String appName, String version, int pct);

  /// Update banner status while the downloaded installer is being sha256-verified.
  ///
  /// In en, this message translates to:
  /// **'Verifying {appName} {version}…'**
  String updateBannerVerifying(String appName, String version);

  /// Update banner status while handing the verified installer off to the OS.
  ///
  /// In en, this message translates to:
  /// **'Preparing the installer…'**
  String get updateBannerPreparingInstaller;

  /// Update banner status after a successful download+verify when the installer was revealed in the OS file manager.
  ///
  /// In en, this message translates to:
  /// **'{appName} {version} downloaded and verified — we revealed the installer in your file manager. Run it to finish updating.'**
  String updateBannerCompletedRevealed(String appName, String version);

  /// Update banner status after a successful download when the installer was not auto-revealed.
  ///
  /// In en, this message translates to:
  /// **'{appName} {version} downloaded — follow the installer to finish updating.'**
  String updateBannerCompletedManual(String appName, String version);

  /// Fallback update-banner error shown when the assisted download fails and no specific message is available.
  ///
  /// In en, this message translates to:
  /// **'The update could not be downloaded.'**
  String get updateBannerDownloadFailed;

  /// Update banner message when a newer version is available (idle/cancelled state).
  ///
  /// In en, this message translates to:
  /// **'A newer version of {appName} ({version}) is available.'**
  String updateBannerAvailable(String appName, String version);

  /// Update banner action that opens the release notes web page.
  ///
  /// In en, this message translates to:
  /// **'View release'**
  String get updateBannerViewRelease;

  /// Update banner action that dismisses the banner for this version.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get updateBannerDismiss;

  /// Update banner action that starts the assisted download-and-install flow.
  ///
  /// In en, this message translates to:
  /// **'Download & install'**
  String get updateBannerDownloadInstall;

  /// Screen-reader barrier label for the global command-palette dialog.
  ///
  /// In en, this message translates to:
  /// **'Global search'**
  String get commandPaletteBarrierLabel;

  /// Placeholder hint in the command-palette search field.
  ///
  /// In en, this message translates to:
  /// **'Search dances and programs…'**
  String get commandPaletteSearchHint;

  /// Subtitle shown under a program result in the command palette.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get commandPaletteProgramSubtitle;

  /// Command-palette empty state before the user has typed a query.
  ///
  /// In en, this message translates to:
  /// **'Nothing to search yet.'**
  String get commandPaletteEmptyInitial;

  /// Command-palette empty state when a query matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No matches for that search.'**
  String get commandPaletteNoMatches;

  /// Command-palette group header for dance results.
  ///
  /// In en, this message translates to:
  /// **'Dances'**
  String get commandPaletteGroupDances;

  /// Command-palette group header for program results.
  ///
  /// In en, this message translates to:
  /// **'Programs'**
  String get commandPaletteGroupPrograms;

  /// Label for the search field in the collection picker (adding a dance to a program).
  ///
  /// In en, this message translates to:
  /// **'Find a dance to add'**
  String get collectionPickerSearchLabel;

  /// Collection-picker Filters section header; shows the number of active filters when any are set.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Filters} other{Filters ({count} active)}}'**
  String collectionPickerFilters(int count);

  /// Collection-picker By-phrase section header; shows the number of active phrase conditions when any are set.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{By phrase} other{By phrase ({count} active)}}'**
  String collectionPickerByPhrase(int count);

  /// Collection-picker advanced-search section header.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get collectionPickerAdvanced;

  /// Collection-picker toggle enabling the advanced structured query builder.
  ///
  /// In en, this message translates to:
  /// **'Use advanced query'**
  String get collectionPickerUseAdvancedQuery;

  /// Helper text describing the advanced query builder in the collection picker.
  ///
  /// In en, this message translates to:
  /// **'Combine figures and sequences with all / any / none groups.'**
  String get collectionPickerAdvancedQueryHelp;

  /// Screen-reader label for the button that adds a dance to the program.
  ///
  /// In en, this message translates to:
  /// **'Add {title} to program'**
  String collectionPickerAddSemantic(String title);

  /// Tooltip for the button that adds a dance to the program.
  ///
  /// In en, this message translates to:
  /// **'Add {title}'**
  String collectionPickerAddTooltip(String title);

  /// Tooltip for the picker's add button during the brief confirmation that follows a tap, while it shows a check instead of a plus (#796). The button stays active — a dance may legitimately be added to a program more than once — so this reports what just happened rather than disabling the action.
  ///
  /// In en, this message translates to:
  /// **'Added {title}'**
  String collectionPickerAddedTooltip(String title);

  /// Screen-reader label for the persistent in-program marker shown on a picker row when the dance already appears in the program being built (#796). Not a button — it is a status indicator.
  ///
  /// In en, this message translates to:
  /// **'{title} is already in the program'**
  String collectionPickerInProgramSemantic(String title);

  /// Screen-reader label for the persistent in-program marker when the dance appears more than once in the program (#796). Shown alongside the count badge.
  ///
  /// In en, this message translates to:
  /// **'{title} is in the program {count} times'**
  String collectionPickerInProgramCountSemantic(String title, int count);

  /// App-bar title for the user-guide hub.
  ///
  /// In en, this message translates to:
  /// **'User guide'**
  String get userGuideTitle;

  /// Snackbar shown when the user taps an internal guide link whose target guide does not exist yet. {label} is the linked guide's title.
  ///
  /// In en, this message translates to:
  /// **'The \"{label}\" guide isn\'t available yet.'**
  String userGuideMissing(String label);

  /// Message shown when the bundled user-guide content fails to load.
  ///
  /// In en, this message translates to:
  /// **'The user guide could not be loaded.'**
  String get userGuideLoadError;

  /// Action that opens the user guide on the web when local content is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Open the guide online'**
  String get userGuideOpenOnline;

  /// App-bar title for the figure-shorthand mappings manager.
  ///
  /// In en, this message translates to:
  /// **'Figure shorthands'**
  String get shorthandMappingsTitle;

  /// Intro paragraph explaining what figure shorthands do.
  ///
  /// In en, this message translates to:
  /// **'Shorthands let you type a short token during free-text entry and have it expand to one or more figures you have set up here.'**
  String get shorthandMappingsIntro;

  /// Button that creates a new figure-shorthand mapping.
  ///
  /// In en, this message translates to:
  /// **'New shorthand'**
  String get shorthandMappingsNew;

  /// Empty state when the user has no figure-shorthand mappings.
  ///
  /// In en, this message translates to:
  /// **'No shorthands yet.'**
  String get shorthandMappingsEmpty;

  /// Title of the confirm-delete dialog for a figure-shorthand mapping.
  ///
  /// In en, this message translates to:
  /// **'Delete shorthand?'**
  String get shorthandMappingsDeleteTitle;

  /// Body of the confirm-delete dialog; {token} is the user's shorthand token, rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'“{token}” will be permanently removed.'**
  String shorthandMappingsDeleteBody(String token);

  /// Tooltip for the per-row overflow menu in the shorthand manager.
  ///
  /// In en, this message translates to:
  /// **'Shorthand actions'**
  String get shorthandMappingsActionsTooltip;

  /// App-bar title when creating a new figure-shorthand mapping.
  ///
  /// In en, this message translates to:
  /// **'New shorthand'**
  String get shorthandEditorTitleNew;

  /// App-bar title when editing an existing figure-shorthand mapping.
  ///
  /// In en, this message translates to:
  /// **'Edit shorthand'**
  String get shorthandEditorTitleEdit;

  /// Label for the shorthand-token text field.
  ///
  /// In en, this message translates to:
  /// **'Shorthand'**
  String get shorthandEditorTokenLabel;

  /// Helper text under the shorthand-token field.
  ///
  /// In en, this message translates to:
  /// **'Type this exact line during free-text entry to insert the figures below. Matched case-insensitively.'**
  String get shorthandEditorTokenHelper;

  /// Section header for the figures a shorthand expands to.
  ///
  /// In en, this message translates to:
  /// **'Expands to'**
  String get shorthandEditorExpandsTo;

  /// Helper text under the 'Expands to' section header.
  ///
  /// In en, this message translates to:
  /// **'The figure(s) this shorthand inserts, in order. Built exactly like a normal figure, so parameters and validation are the same.'**
  String get shorthandEditorExpandsToHelp;

  /// Validation error when the shorthand token is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a shorthand token.'**
  String get shorthandEditorErrorEmpty;

  /// Validation error when the shorthand token exceeds the maximum length.
  ///
  /// In en, this message translates to:
  /// **'Shorthand is too long (max {max} characters).'**
  String shorthandEditorErrorTooLong(int max);

  /// Validation error when the shorthand token duplicates an existing one; {token} is the user's token, rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Another shorthand already uses \"{token}\" (shorthands are matched case-insensitively).'**
  String shorthandEditorErrorDuplicate(String token);

  /// Validation error when no target figures have been added to a shorthand.
  ///
  /// In en, this message translates to:
  /// **'Add at least one figure for this shorthand to expand to.'**
  String get shorthandEditorErrorNoFigures;

  /// App-bar title for the optional step that seeds figure shorthands from a Caller's Companion file's call buttons.
  ///
  /// In en, this message translates to:
  /// **'Seed figure shorthands'**
  String get importShorthandSeedTitle;

  /// Intro paragraph on the shorthand-seeding step explaining it is opt-in and previewed.
  ///
  /// In en, this message translates to:
  /// **'Your Caller\'s Companion file\'s call buttons can become figure shorthands. Pick the ones you want; each expands to the figures shown. Nothing is added until you confirm, and your existing shorthands are never overwritten.'**
  String get importShorthandSeedIntro;

  /// Section header above the list of seedable shorthand candidates.
  ///
  /// In en, this message translates to:
  /// **'From your call buttons'**
  String get importShorthandSeedAvailableHeader;

  /// Label for the toggle option that seeds a button's primary call.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get importShorthandSeedUsePrimary;

  /// Label for the toggle option that seeds a button's alternate call instead of its primary call.
  ///
  /// In en, this message translates to:
  /// **'Alternate'**
  String get importShorthandSeedUseAlt;

  /// Section header above call buttons whose shorthand token already exists and will not be seeded.
  ///
  /// In en, this message translates to:
  /// **'Already defined — skipped'**
  String get importShorthandSeedConflictHeader;

  /// Explanation shown for a skipped, conflicting shorthand candidate; {token} is the user's token, rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'A shorthand named “{token}” already exists, so this button was left as-is.'**
  String importShorthandSeedConflictNote(String token);

  /// Button that declines seeding any shorthands and closes the step.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get importShorthandSeedSkip;

  /// Confirm button on the shorthand-seeding step; {count} is how many are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Seed shorthands} =1{Seed 1 shorthand} other{Seed {count} shorthands}}'**
  String importShorthandSeedConfirm(int count);

  /// Snackbar shown after shorthands are seeded; {count} is how many were added.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Seeded 1 shorthand} other{Seeded {count} shorthands}}'**
  String importShorthandSeedComplete(int count);

  /// App-bar title for the theme editor.
  ///
  /// In en, this message translates to:
  /// **'Edit theme'**
  String get themeEditorTitle;

  /// Label for the theme-name text field.
  ///
  /// In en, this message translates to:
  /// **'Theme name'**
  String get themeEditorNameLabel;

  /// Status shown when every checked colour pair meets WCAG AA contrast.
  ///
  /// In en, this message translates to:
  /// **'All checked pairs pass WCAG AA contrast.'**
  String get themeEditorContrastAllPass;

  /// Warning shown when one or more colour pairs fall below WCAG AA contrast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contrast pair below WCAG AA. You can still save, but some text may be hard to read.} other{{count} contrast pairs below WCAG AA. You can still save, but some text may be hard to read.}}'**
  String themeEditorContrastFailing(int count);

  /// Contrast-ratio chip when the pair passes WCAG AA; {ratio} is the formatted ratio.
  ///
  /// In en, this message translates to:
  /// **'{ratio}:1 AA'**
  String themeEditorRatioPass(String ratio);

  /// Contrast-ratio chip when the pair fails WCAG AA; {ratio} is the formatted ratio.
  ///
  /// In en, this message translates to:
  /// **'{ratio}:1 fail'**
  String themeEditorRatioFail(String ratio);

  /// Heading of the live theme-preview card ('Aa' is a font specimen).
  ///
  /// In en, this message translates to:
  /// **'Aa Preview'**
  String get themeEditorPreviewHeading;

  /// Sample body-text line in the theme preview.
  ///
  /// In en, this message translates to:
  /// **'Body text sample'**
  String get themeEditorBodySample;

  /// Label for the primary colour swatch.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get themeEditorSwatchPrimary;

  /// Label for the secondary colour swatch.
  ///
  /// In en, this message translates to:
  /// **'Secondary'**
  String get themeEditorSwatchSecondary;

  /// Label for the tertiary colour swatch.
  ///
  /// In en, this message translates to:
  /// **'Tertiary'**
  String get themeEditorSwatchTertiary;

  /// Label for the error colour swatch.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get themeEditorSwatchError;

  /// Title of the confirm dialog before re-parsing custom figures.
  ///
  /// In en, this message translates to:
  /// **'Upgrade custom figures?'**
  String get reparseConfirmTitle;

  /// Body of the confirm dialog before upgrading custom figures.
  ///
  /// In en, this message translates to:
  /// **'This will re-parse {figureCount, plural, =1{1 figure} other{{figureCount} figures}} in {danceCount, plural, =1{1 dance} other{{danceCount} dances}}. Your tags, ratings, notes, and everything else on each dance are kept exactly as they are. This only replaces figures that now recognise a known move.'**
  String reparseConfirmBody(int figureCount, int danceCount);

  /// Confirm-dialog action that performs the custom-figure upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get reparseConfirmUpgrade;

  /// Snackbar shown when the custom-figure upgrade fails.
  ///
  /// In en, this message translates to:
  /// **'Could not upgrade figures. Please try again.'**
  String get reparseFailed;

  /// Snackbar shown when an upgrade run changed nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to upgrade.'**
  String get reparseNothingUpgradedSnack;

  /// Snackbar confirming how many dances had custom figures upgraded.
  ///
  /// In en, this message translates to:
  /// **'Upgraded custom figures in {danceCount, plural, =1{1 dance} other{{danceCount} dances}}.'**
  String reparseUpgradedSnack(int danceCount);

  /// App-bar title for the re-check custom figures screen.
  ///
  /// In en, this message translates to:
  /// **'Re-check custom figures'**
  String get reparseScreenTitle;

  /// Intro paragraph on the re-check custom figures screen.
  ///
  /// In en, this message translates to:
  /// **'Improved figure parsing can upgrade {figureCount, plural, =1{1 figure} other{{figureCount} figures}} in {danceCount, plural, =1{1 dance} other{{danceCount} dances}}. Review below, then confirm — nothing changes until you do, and all your tags, ratings, and notes are preserved.'**
  String reparseIntro(int figureCount, int danceCount);

  /// Per-dance preview label showing how many figures would be upgraded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 figure} other{{count} figures}} to upgrade'**
  String reparsePreviewCount(int count);

  /// Primary button that upgrades custom figures across the affected dances.
  ///
  /// In en, this message translates to:
  /// **'Upgrade {danceCount, plural, =1{1 dance} other{{danceCount} dances}}'**
  String reparseUpgradeButton(int danceCount);

  /// Title of the empty state when no custom figures can be upgraded.
  ///
  /// In en, this message translates to:
  /// **'Nothing to upgrade'**
  String get reparseEmptyTitle;

  /// Body of the empty state when no custom figures can be upgraded.
  ///
  /// In en, this message translates to:
  /// **'None of your custom figures from imports can be recognised as a known move right now. Check back after a future update improves figure parsing.'**
  String get reparseEmptyBody;

  /// Title of the error state when scanning for upgradable figures fails.
  ///
  /// In en, this message translates to:
  /// **'Could not check your figures'**
  String get reparseErrorTitle;

  /// Body of the error state when scanning for upgradable figures fails.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while scanning your collection. Nothing was changed. You can try again.'**
  String get reparseErrorBody;

  /// Title of the confirm-delete dialog for a custom field.
  ///
  /// In en, this message translates to:
  /// **'Delete custom field'**
  String get customFieldsDeleteTitle;

  /// Body of the confirm-delete dialog; {label} is the field's display label, rendered as plain text.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{label}\"? This cannot be undone.'**
  String customFieldsDeleteBody(String label);

  /// Snackbar when deleting a custom field still set on dances (count known). The raw exception is logged (debugPrint), never shown, so storage internals can't leak to the UI (CWE-209). {label} is plain text.
  ///
  /// In en, this message translates to:
  /// **'Can\'t delete \"{label}\": still used by {count, plural, =1{1 dance} other{{count} dances}}. Remove the value from all dances first.'**
  String customFieldsDeleteInUse(String label, int count);

  /// Snackbar when deleting a custom field still set on dances but the exact count is unknown. The raw exception is logged (debugPrint), never shown (CWE-209). {label} is plain text.
  ///
  /// In en, this message translates to:
  /// **'Can\'t delete \"{label}\": still used by some dances. Remove the value from all dances first.'**
  String customFieldsDeleteInUseUnknown(String label);

  /// App-bar title for the custom-fields manager.
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get customFieldsTitle;

  /// Button that creates a new custom field.
  ///
  /// In en, this message translates to:
  /// **'New field'**
  String get customFieldsNewField;

  /// Error shown when the custom-field definitions fail to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load custom fields.'**
  String get customFieldsLoadError;

  /// Empty state when no custom fields are defined.
  ///
  /// In en, this message translates to:
  /// **'No custom fields yet.\nTap + to define one.'**
  String get customFieldsEmpty;

  /// Subtitle chip indicating a custom field is shown in the dance list.
  ///
  /// In en, this message translates to:
  /// **'In list'**
  String get customFieldsFlagInList;

  /// Label/chip indicating a custom field is exposed as a search filter.
  ///
  /// In en, this message translates to:
  /// **'Searchable'**
  String get customFieldsSearchable;

  /// Custom-field type: free text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get customFieldsTypeText;

  /// Custom-field type: number.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get customFieldsTypeNumber;

  /// Custom-field type: yes/no boolean.
  ///
  /// In en, this message translates to:
  /// **'Boolean'**
  String get customFieldsTypeBoolean;

  /// Custom-field type: single choice from a list.
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get customFieldsTypeChoice;

  /// Validation error when a choice-type field has no choices defined.
  ///
  /// In en, this message translates to:
  /// **'Add at least one choice'**
  String get customFieldsValidatorMinChoice;

  /// Inline error when removing a choice value that is still set on a dance; {value} is plain text.
  ///
  /// In en, this message translates to:
  /// **'Can\'t remove \"{value}\": it\'s set on at least one dance.'**
  String customFieldsRemoveValueError(String value);

  /// Editor title when creating a new custom field.
  ///
  /// In en, this message translates to:
  /// **'New custom field'**
  String get customFieldsEditorNewTitle;

  /// Editor title when editing an existing custom field.
  ///
  /// In en, this message translates to:
  /// **'Edit custom field'**
  String get customFieldsEditorEditTitle;

  /// Label for the custom-field display-label input (required).
  ///
  /// In en, this message translates to:
  /// **'Label *'**
  String get customFieldsLabelLabel;

  /// Validation error when the custom-field label is empty.
  ///
  /// In en, this message translates to:
  /// **'Label is required'**
  String get customFieldsLabelRequired;

  /// Label for the custom-field machine-key input (required).
  ///
  /// In en, this message translates to:
  /// **'Key *'**
  String get customFieldsKeyLabel;

  /// Helper text describing the machine-key format.
  ///
  /// In en, this message translates to:
  /// **'Stable machine key (letters, digits, underscores; must start with a letter or underscore)'**
  String get customFieldsKeyHelper;

  /// Helper text when the machine key can't be edited because the field is in use.
  ///
  /// In en, this message translates to:
  /// **'Key is locked — field is in use on dances'**
  String get customFieldsKeyLocked;

  /// Validation error when the machine key is empty.
  ///
  /// In en, this message translates to:
  /// **'Key is required'**
  String get customFieldsKeyRequired;

  /// Validation error when the machine key has invalid characters.
  ///
  /// In en, this message translates to:
  /// **'Key must start with a letter or underscore and contain only letters, digits, and underscores'**
  String get customFieldsKeyInvalid;

  /// Label for the custom-field type picker.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get customFieldsTypeFieldLabel;

  /// Helper text when the field type can't be changed because values exist.
  ///
  /// In en, this message translates to:
  /// **'Type is locked — field has values on dances'**
  String get customFieldsTypeLocked;

  /// Toggle title: show this field's value in the dance list tile.
  ///
  /// In en, this message translates to:
  /// **'Show in list'**
  String get customFieldsShowInList;

  /// Subtitle for the 'Show in list' toggle.
  ///
  /// In en, this message translates to:
  /// **'Display this field value in the dance list tile'**
  String get customFieldsShowInListSubtitle;

  /// Subtitle for the 'Searchable' toggle.
  ///
  /// In en, this message translates to:
  /// **'Expose this field as a filter in the search panel'**
  String get customFieldsSearchableSubtitle;

  /// Section label for the list of choices on a choice-type field (required).
  ///
  /// In en, this message translates to:
  /// **'Choices *'**
  String get customFieldsChoicesLabel;

  /// Tooltip/message for a choice value that is in use and can't be removed.
  ///
  /// In en, this message translates to:
  /// **'In use — cannot remove'**
  String get customFieldsChoiceInUseTooltip;

  /// Placeholder for the input that adds a new choice value.
  ///
  /// In en, this message translates to:
  /// **'New choice…'**
  String get customFieldsNewChoiceHint;

  /// Tooltip for the button that adds a new choice value.
  ///
  /// In en, this message translates to:
  /// **'Add choice'**
  String get customFieldsAddChoiceTooltip;

  /// Inline error when a user tries to add a choice option that already exists.
  ///
  /// In en, this message translates to:
  /// **'That option already exists.'**
  String get customFieldsChoiceDuplicate;

  /// Inline error when a user tries to add an empty choice option.
  ///
  /// In en, this message translates to:
  /// **'Enter an option.'**
  String get customFieldsChoiceEmpty;

  /// Tooltip for the inline button (in the dance editor) that adds a new option to a choice custom field.
  ///
  /// In en, this message translates to:
  /// **'Add an option to {label}'**
  String customFieldsAddOptionTooltip(String label);

  /// Title of the dialog for adding a new option to a choice custom field inline from the dance editor.
  ///
  /// In en, this message translates to:
  /// **'Add an option to {label}'**
  String customFieldsAddOptionTitle(String label);

  /// Label for the 'include in sharing' toggle on the custom field form. When on (the default), this field and its values travel with the collection in exports and transfers.
  ///
  /// In en, this message translates to:
  /// **'Include in sharing'**
  String get customFieldsShareable;

  /// Subtitle for the 'include in sharing' toggle on the custom field form.
  ///
  /// In en, this message translates to:
  /// **'This field\'s values travel with your collection when you export or share it'**
  String get customFieldsShareableSubtitle;

  /// Title of the one-time disclosure dialog shown when a user creates their first custom field, explaining that custom field values are included in exports and shares.
  ///
  /// In en, this message translates to:
  /// **'Custom fields travel with your collection'**
  String get customFieldsSharingNoticeTitle;

  /// Body of the one-time disclosure dialog shown when a user creates their first custom field.
  ///
  /// In en, this message translates to:
  /// **'The contents of any custom field you create are included when you export or share your collection. To keep a field private, turn off \"Include in sharing\" in that field\'s settings.'**
  String get customFieldsSharingNoticeBody;

  /// Dismiss button for the one-time custom field sharing disclosure dialog.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get customFieldsSharingNoticeOk;

  /// App-bar title for the dialect editor; {name} is the dialect name, plain text.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String dialectEditorTitle(String name);

  /// Dialect editor section header: role terms.
  ///
  /// In en, this message translates to:
  /// **'Role terms'**
  String get dialectEditorSectionRoleTerms;

  /// Dialect editor section header: move substitutions.
  ///
  /// In en, this message translates to:
  /// **'Move substitutions'**
  String get dialectEditorSectionMoveSubs;

  /// Dialect editor section header: dancer substitutions.
  ///
  /// In en, this message translates to:
  /// **'Dancer substitutions'**
  String get dialectEditorSectionDancerSubs;

  /// Dialect editor section header: discouraged terms.
  ///
  /// In en, this message translates to:
  /// **'Discouraged terms'**
  String get dialectEditorSectionDiscouraged;

  /// Dialect editor section header: live preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get dialectEditorSectionPreview;

  /// Label for the first dance role in the dialect editor.
  ///
  /// In en, this message translates to:
  /// **'Role 1'**
  String get dialectEditorRole1;

  /// Label for the second dance role in the dialect editor.
  ///
  /// In en, this message translates to:
  /// **'Role 2'**
  String get dialectEditorRole2;

  /// Helper text for the role-terms section of the dialect editor.
  ///
  /// In en, this message translates to:
  /// **'Leave a role blank to use the canonical term. Plural is derived when omitted.'**
  String get dialectEditorRolesHelp;

  /// Label for the singular form of a role term.
  ///
  /// In en, this message translates to:
  /// **'Singular'**
  String get dialectEditorSingular;

  /// Label for the plural form of a role term.
  ///
  /// In en, this message translates to:
  /// **'Plural'**
  String get dialectEditorPlural;

  /// Collapsed header/empty state for the move-substitutions section.
  ///
  /// In en, this message translates to:
  /// **'Add move substitutions'**
  String get dialectEditorMoveSubsAdd;

  /// Header showing how many move substitutions are defined.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 move substitution} other{{count} move substitutions}}'**
  String dialectEditorMoveSubsCount(int count);

  /// Hint for a move-substitution input; %S is a literal handedness token the user types.
  ///
  /// In en, this message translates to:
  /// **'substitution (use %S for handedness)'**
  String get dialectEditorMoveSubHint;

  /// Placeholder for the dropdown that adds a move to substitute.
  ///
  /// In en, this message translates to:
  /// **'Add a move…'**
  String get dialectEditorAddMove;

  /// Collapsed header/empty state for the dancer-substitutions section.
  ///
  /// In en, this message translates to:
  /// **'Add dancer substitutions'**
  String get dialectEditorDancerSubsAdd;

  /// Header showing how many dancer substitutions are defined.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dancer substitution} other{{count} dancer substitutions}}'**
  String dialectEditorDancerSubsCount(int count);

  /// Hint for a dancer-substitution input.
  ///
  /// In en, this message translates to:
  /// **'substitution'**
  String get dialectEditorDancerSubHint;

  /// Placeholder for the dropdown that adds a dancer term to substitute.
  ///
  /// In en, this message translates to:
  /// **'Add a dancer term…'**
  String get dialectEditorAddDancerTerm;

  /// Helper text for the discouraged-terms section.
  ///
  /// In en, this message translates to:
  /// **'Terms the entry editor flags (struck through) — never blocked.'**
  String get dialectEditorDiscouragedHelp;

  /// Empty state for the discouraged-terms section.
  ///
  /// In en, this message translates to:
  /// **'No discouraged terms.'**
  String get dialectEditorDiscouragedEmpty;

  /// Label for the input that adds a discouraged term.
  ///
  /// In en, this message translates to:
  /// **'Add a term'**
  String get dialectEditorAddTermLabel;

  /// Tooltip for the button that adds a discouraged term.
  ///
  /// In en, this message translates to:
  /// **'Add term'**
  String get dialectEditorAddTermTooltip;

  /// Button that restores the default discouraged-terms list.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get dialectEditorRestoreDefaults;

  /// Helper text for the dialect live-preview section.
  ///
  /// In en, this message translates to:
  /// **'Sample figures rendered with this dialect. Updates as you edit.'**
  String get dialectEditorPreviewHelp;

  /// App-bar title for the recently-deleted (trash) screen.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get recentlyDeletedTitle;

  /// Title of the confirm permanent-delete dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get recentlyDeletedDeleteTitle;

  /// Body of the confirm permanent-delete dialog; {title} is the item title, plain text.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be deleted immediately and cannot be recovered.'**
  String recentlyDeletedDeleteBody(String title);

  /// Action/tooltip that permanently deletes a recently-deleted item.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get recentlyDeletedDeleteConfirm;

  /// Snackbar confirming a permanent delete; {title} is the item title, plain text.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" permanently deleted.'**
  String recentlyDeletedDeletedSnack(String title);

  /// Label for the button that restores a recently-deleted item.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get recentlyDeletedRestore;

  /// Sublabel when an item is kept until manually deleted (no retention window).
  ///
  /// In en, this message translates to:
  /// **'Kept until you delete it'**
  String get recentlyDeletedPurgeKept;

  /// Sublabel counting down days until an item is auto-purged.
  ///
  /// In en, this message translates to:
  /// **'Auto-deleted in {days, plural, =1{1 day} other{{days} days}}'**
  String recentlyDeletedPurgeCountdown(int days);

  /// Sublabel when an item is past its retention window and scheduled for purge.
  ///
  /// In en, this message translates to:
  /// **'Scheduled for deletion'**
  String get recentlyDeletedPurgeScheduled;

  /// Loading label for the recently-deleted dances screen.
  ///
  /// In en, this message translates to:
  /// **'Loading recently deleted dances'**
  String get recentlyDeletedLoadingDances;

  /// Loading label for the recently-deleted programs screen.
  ///
  /// In en, this message translates to:
  /// **'Loading recently deleted programs'**
  String get recentlyDeletedLoadingPrograms;

  /// Empty state for recently-deleted dances when there is no retention window.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the trash. Deleted dances are kept here until you remove them.'**
  String get recentlyDeletedEmptyDancesKept;

  /// Empty state for recently-deleted dances with a retention window of {days} days.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the trash. Deleted dances appear here for {days} days before being removed.'**
  String recentlyDeletedEmptyDancesRetention(int days);

  /// Empty state for recently-deleted programs with a retention window of {days} days.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the trash. Deleted programs appear here for {days} days before being removed.'**
  String recentlyDeletedEmptyProgramsRetention(int days);

  /// Snackbar confirming a dance was restored; {title} is plain text.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" restored to your collection.'**
  String recentlyDeletedRestoredDance(String title);

  /// Snackbar confirming a program was restored; {title} is plain text.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" restored.'**
  String recentlyDeletedRestoredProgram(String title);

  /// Label for creating a new venue: the venue manager's add button and the venue editor sheet's title in create mode.
  ///
  /// In en, this message translates to:
  /// **'New venue'**
  String get venueNew;

  /// Error shown when the reusable venue records fail to load (venue manager and venue picker).
  ///
  /// In en, this message translates to:
  /// **'Could not load venues.'**
  String get venueLoadError;

  /// App bar title of the venue manager screen (Settings ▸ Venues).
  ///
  /// In en, this message translates to:
  /// **'Venues'**
  String get venueManagerTitle;

  /// Hint text for the venue manager's search field.
  ///
  /// In en, this message translates to:
  /// **'Search venues…'**
  String get venueManagerSearchHint;

  /// Tooltip for the button that clears the venue manager's search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get venueManagerClearSearchTooltip;

  /// Empty state for the venue manager when no venues exist yet.
  ///
  /// In en, this message translates to:
  /// **'No venues yet. Add one with the button below, or from a program when reusable venues are turned on.'**
  String get venueManagerEmpty;

  /// Shown in the venue manager when a search yields no matching venues.
  ///
  /// In en, this message translates to:
  /// **'No venues match your search.'**
  String get venueManagerNoMatches;

  /// Title of the confirmation dialog for permanently deleting a venue.
  ///
  /// In en, this message translates to:
  /// **'Delete venue?'**
  String get venueManagerDeleteTitle;

  /// Body of the delete-venue confirmation dialog; {name} is the venue's name (plain text, may be user-entered or imported).
  ///
  /// In en, this message translates to:
  /// **'Permanently delete “{name}”? This can’t be undone.'**
  String venueManagerDeleteBody(String name);

  /// Snackbar confirming a venue was deleted; {name} is the venue's name (plain text).
  ///
  /// In en, this message translates to:
  /// **'Deleted “{name}”'**
  String venueManagerDeletedSnack(String name);

  /// Snackbar shown when a venue can't be deleted because a program still links to it; {name} is the venue's name (plain text).
  ///
  /// In en, this message translates to:
  /// **'Can’t delete “{name}” while it’s still linked to a program. Change or remove its venue on those programs first.'**
  String venueManagerDeleteBlocked(String name);

  /// Tooltip for the delete button on a venue row; {name} is the venue's name (plain text).
  ///
  /// In en, this message translates to:
  /// **'Delete {name}'**
  String venueManagerDeleteTooltip(String name);

  /// Title of the venue editor sheet when editing an existing venue.
  ///
  /// In en, this message translates to:
  /// **'Edit venue'**
  String get venueEditTitle;

  /// Explanatory note at the top of the venue editor sheet: a venue record is shared across programs.
  ///
  /// In en, this message translates to:
  /// **'A venue is shared across every program held here, so edits to its address, contacts, or schedule show up on all of them.'**
  String get venueEditorSharedNote;

  /// Required venue name field label; the asterisk marks the field as required.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get venueEditorNameLabel;

  /// Validation error shown when the venue name field is blank.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get venueEditorNameRequired;

  /// Venue website field label.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get venueEditorWebsiteLabel;

  /// Venue sponsor / hosting-organization field label.
  ///
  /// In en, this message translates to:
  /// **'Sponsor / hosting organization'**
  String get venueEditorSponsorLabel;

  /// Section heading for the venue's address fields in the editor.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get venueEditorAddressSection;

  /// Venue address line 1 field label.
  ///
  /// In en, this message translates to:
  /// **'Address line 1'**
  String get venueEditorAddress1Label;

  /// Venue address line 2 field label.
  ///
  /// In en, this message translates to:
  /// **'Address line 2'**
  String get venueEditorAddress2Label;

  /// Venue city field label.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get venueEditorCityLabel;

  /// Venue state or province field label.
  ///
  /// In en, this message translates to:
  /// **'State / province'**
  String get venueEditorStateLabel;

  /// Venue country field label.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get venueEditorCountryLabel;

  /// Venue postal / ZIP code field label.
  ///
  /// In en, this message translates to:
  /// **'Postal / ZIP code'**
  String get venueEditorPostalLabel;

  /// Venue ZIP+4 (US postal add-on) field label.
  ///
  /// In en, this message translates to:
  /// **'ZIP+4'**
  String get venueEditorPlus4Label;

  /// Section heading for the venue's schedule fields in the editor.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get venueEditorScheduleSection;

  /// Venue event-name field label.
  ///
  /// In en, this message translates to:
  /// **'Event name'**
  String get venueEditorEventNameLabel;

  /// Venue time field label.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get venueEditorTimeLabel;

  /// Venue generic-schedule field label, with an example of a recurring schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule (e.g. “2nd Saturdays”)'**
  String get venueEditorScheduleLabel;

  /// Venue price field label.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get venueEditorPriceLabel;

  /// Section heading for the venue's contact fields in the editor.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get venueEditorContactsSection;

  /// Venue first-contact name field label.
  ///
  /// In en, this message translates to:
  /// **'Contact 1 name'**
  String get venueEditorContact1NameLabel;

  /// Venue first-contact phone field label.
  ///
  /// In en, this message translates to:
  /// **'Contact 1 phone'**
  String get venueEditorContact1PhoneLabel;

  /// Venue first-contact email field label.
  ///
  /// In en, this message translates to:
  /// **'Contact 1 email'**
  String get venueEditorContact1EmailLabel;

  /// Venue second-contact name field label.
  ///
  /// In en, this message translates to:
  /// **'Contact 2 name'**
  String get venueEditorContact2NameLabel;

  /// Venue second-contact phone field label.
  ///
  /// In en, this message translates to:
  /// **'Contact 2 phone'**
  String get venueEditorContact2PhoneLabel;

  /// Venue second-contact email field label.
  ///
  /// In en, this message translates to:
  /// **'Contact 2 email'**
  String get venueEditorContact2EmailLabel;

  /// Section heading and field label for the venue's free-form notes in the editor.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get venueEditorNotesSection;

  /// Loading indicator text while the venue picker fetches venues.
  ///
  /// In en, this message translates to:
  /// **'Loading venues…'**
  String get venuePickerLoading;

  /// Tooltip for the button that unlinks the currently selected venue from a program.
  ///
  /// In en, this message translates to:
  /// **'Unlink venue'**
  String get venuePickerUnlinkTooltip;

  /// Title shown in the venue picker when a program's linked venue id no longer resolves.
  ///
  /// In en, this message translates to:
  /// **'Linked venue not found'**
  String get venuePickerUnresolvedTitle;

  /// Subtitle explaining that a program's linked venue could not be found.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted.'**
  String get venuePickerUnresolvedSubtitle;

  /// Tooltip for the button that clears an unresolved venue link from a program.
  ///
  /// In en, this message translates to:
  /// **'Clear link'**
  String get venuePickerClearLinkTooltip;

  /// Hint text for the venue picker's search field when no venue is linked.
  ///
  /// In en, this message translates to:
  /// **'Search or add a venue…'**
  String get venuePickerSearchHint;

  /// Hint text for the venue picker's search field when a venue is already linked.
  ///
  /// In en, this message translates to:
  /// **'Change venue…'**
  String get venuePickerChangeHint;

  /// Inline-create option in the venue picker; {name} is the text the user typed (plain text).
  ///
  /// In en, this message translates to:
  /// **'Add new venue “{name}”'**
  String venuePickerCreateOption(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'da',
    'de',
    'en',
    'fr',
    'ja',
    'nl',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
