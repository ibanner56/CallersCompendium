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

  /// Title of the control that chooses which day the week starts on.
  ///
  /// In en, this message translates to:
  /// **'First day of week'**
  String get settingsFirstDayOfWeekTitle;

  /// Subtitle for the disabled, not-yet-available first-day-of-week row. Describes the future feature without implying it works today.
  ///
  /// In en, this message translates to:
  /// **'Which day the week starts on in the app\'s date views. Coming in a future update.'**
  String get settingsFirstDayOfWeekSubtitle;

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
  /// **'Tint each dance row by its formation family (contra, mixer, square, …). The formation is always shown as text too, so rows stay readable without colour.'**
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

  /// Generic dialog dismiss button that discards the pending action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

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

  /// Container semantics label for the programming matrix, announcing its size (dances by moves).
  ///
  /// In en, this message translates to:
  /// **'Programming matrix: {danceCount} dances by {moveCount} moves'**
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

  /// Screen-reader label for a matrix cell: whether a dance uses a move, and whether that use is the move's program debut and/or the dance's opening figure.
  ///
  /// In en, this message translates to:
  /// **'{dance}, {move}: {present, select, no{not present} other{present{debut, select, yes{, introduced here} other{}}{first, select, yes{, dance\'s first figure} other{}}}}'**
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
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

  /// Confirm button on the venue contact consent dialog; proceeds with the share or PDF export, including only the checked contact fields.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get exportVenueContactConfirm;

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

  /// Per-line status: this title was resolved and imported from The Caller's Box.
  ///
  /// In en, this message translates to:
  /// **'Imported from Caller\'s Box'**
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

  /// Snackbar shown when resolving unmatched title-list lines online fails. The raw exception is logged (debugPrint), never shown, so no internals leak to the UI (CWE-209).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search The Caller\'s Box.'**
  String get importPlaintextSearchError;

  /// Count of slots in the title-list import preview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 slot} other{{count} slots}}'**
  String importPlaintextSlotCount(int count);

  /// Snackbar shown after online resolution when no confident matches were found.
  ///
  /// In en, this message translates to:
  /// **'No confident Caller\'s Box matches found — {remaining, plural, =1{{remaining} title kept as a note} other{{remaining} titles kept as notes}}.'**
  String importPlaintextResolvedNone(int remaining);

  /// Snackbar shown after online resolution when some titles were linked, optionally noting how many remain unmatched.
  ///
  /// In en, this message translates to:
  /// **'Linked {linked, plural, =1{{linked} title} other{{linked} titles}} from The Caller\'s Box{remaining, plural, =0{.} =1{; {remaining} still a note.} other{; {remaining} still notes.}}'**
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
