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
  String get navSearch => 'Search';

  @override
  String navSearchTooltip(String hint) {
    return 'Search ($hint)';
  }

  @override
  String get appBootstrapPreparing => 'Preparing your collection';

  @override
  String get appBootstrapRebuildingIndex => 'Rebuilding search index';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return 'Rebuilding search index… $percent%';
  }

  @override
  String get appBootstrapError => 'Could not prepare the collection.';

  @override
  String get migrationDowngradeMessage =>
      'This data was created by a newer version of Caller’s Compendium — please update the app.';

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return 'Caller’s Compendium didn’t start because it couldn’t create an automatic backup before upgrading your saved data. ${cause}Free up space (or fix the backups folder), then reopen the app — or reopen and choose to continue without a backup.';
  }

  @override
  String get migrationSnapshotCauseDiskFull =>
      'Your device appears to be low on storage space.';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      'The automatic backups folder could not be written to.';

  @override
  String get migrationSnapshotConsentTitle => 'Couldn’t back up your data';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return 'Before upgrading your saved data to a new format, Caller’s Compendium makes an automatic backup so a failed upgrade can be undone. That backup couldn’t be created this time.$cause\n\nIf you continue without a backup and the upgrade is interrupted, some of your dances or programs could be lost. You can quit, free up space (or fix the backups folder), and reopen the app to try again.';
  }

  @override
  String get migrationSnapshotConsentQuit => 'Quit';

  @override
  String get migrationSnapshotConsentProceed => 'Proceed without a backup';

  @override
  String get migrationBelowFloorHeadline =>
      'This data is from a version too old to open';

  @override
  String migrationBelowFloorBody(String bridgeTag) {
    return 'Your data can be recovered. Install $bridgeTag, open the app once to let it update your data, then install this version again.\n\nIf you prefer to start fresh, use the options below — your current data will be lost.';
  }

  @override
  String get migrationBelowFloorBackUpAndReset => 'Back Up + Reset';

  @override
  String get migrationBelowFloorResetOnly => 'Reset Only';

  @override
  String get migrationBelowFloorBackupFailedTitle => 'Backup failed';

  @override
  String get migrationBelowFloorBackupFailedBody =>
      'The backup could not be written, so your data has not been reset.';

  @override
  String get migrationBelowFloorResetConfirmTitle => 'Reset app data?';

  @override
  String get migrationBelowFloorResetConfirmBody =>
      'A backup has been saved. Resetting will replace your current data with a fresh, empty database.';

  @override
  String migrationBelowFloorBackupSavedAt(String backupPath) {
    return 'Backup saved to: $backupPath';
  }

  @override
  String migrationBelowFloorDiagnosticLogSavedAt(String logPath) {
    return 'Diagnostic log saved to: $logPath';
  }

  @override
  String get migrationBelowFloorResetOnlyConfirmBody =>
      'No backup will be made. Resetting will permanently delete all your current data and replace it with a fresh, empty database. This cannot be undone.';

  @override
  String get migrationBelowFloorWipeFailedTitle => 'Reset failed';

  @override
  String get migrationBelowFloorWipeFailedBody =>
      'The database file could not be deleted. Your data has not been changed. Try closing other apps that may be using the file, then try again.';

  @override
  String get confirmDeleteTitle => 'Delete?';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '“$itemLabel” will be deleted. You can undo this.';
  }

  @override
  String get colorEditHexLabel => 'Hex';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsGeneralTitle => 'General';

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsDialectTitle => 'Dialect';

  @override
  String get settingsDefaultsTitle => 'Defaults';

  @override
  String get settingsUpdatesTitle => 'Updates';

  @override
  String get settingsDiagnosticsTitle => 'Diagnostics';

  @override
  String get settingsAboutTitle => 'About';

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
  String get settingsDateFormatCustom => 'Custom…';

  @override
  String get settingsDateFormatCustomPatternLabel => 'Custom date pattern';

  @override
  String get settingsDateFormatCustomPatternHint => 'MM.DD.YY';

  @override
  String get settingsDateFormatCustomLegend =>
      'Tokens: yyyy or yy = year, MM = month (MMM = short name, MMMM = full name), d or dd = day. Separators: - / . , or space.';

  @override
  String get settingsDateFormatCustomInvalid =>
      'Unrecognized pattern — using the system default until it\'s corrected.';

  @override
  String get settingsFirstDayOfWeekTitle => 'First day of week';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Which day the week starts on in the app\'s own date views, such as the Programs list\'s this-week strip.';

  @override
  String get settingsFirstDayOfWeekSunday => 'Sunday';

  @override
  String get settingsFirstDayOfWeekMonday => 'Monday';

  @override
  String get settingsFirstDayOfWeekSaturday => 'Saturday';

  @override
  String get settingsAppLanguageTitle => 'App language';

  @override
  String get settingsAppLanguageSubtitle =>
      'Choose the language of the app\'s interface.';

  @override
  String get settingsAboutHelpHeader => 'Help';

  @override
  String get settingsAboutUserGuideTitle => 'User guide';

  @override
  String get settingsAboutUserGuideSubtitle =>
      'Read the built-in guides — getting started, dialects, imports, and more. Works offline.';

  @override
  String get settingsAboutLicenseHeader => 'License';

  @override
  String get settingsAboutLicenseBody =>
      'Caller\'s Compendium is free software, licensed under the GNU Affero General Public License, version 3 (AGPL-3.0). You are free to use, study, share, and modify it under that license. Because the AGPL requires it, the complete corresponding source code is offered to everyone who uses the app.';

  @override
  String get settingsAboutViewSourceTitle => 'View source on GitHub';

  @override
  String get settingsAboutFontsHeader => 'Fonts';

  @override
  String get settingsAboutFontsBody =>
      'This app bundles the following typefaces under the SIL Open Font License 1.1. Their full license texts are available under “View licenses” below.';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — display & headings';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — body, UI & Perform';

  @override
  String get settingsAboutFontRobotoSubtitle =>
      'SIL Open Font License 1.1 · © The Roboto Project Authors — fallback';

  @override
  String get settingsAboutThemesHeader => 'Themes';

  @override
  String get settingsAboutThemesBody =>
      'Several optional color themes are inspired by popular code-editor palettes — One Dark, Dracula, Nord, Tokyo Night, Gruvbox, and Catppuccin among them — re-derived and contrast-tuned for this app. Theme names are used only to credit that inspiration.';

  @override
  String get settingsAboutDanceDataHeader => 'Dance data';

  @override
  String get settingsAboutDanceDataBody =>
      'Dance data draws on The Caller’s Box (Chris Page & Michael Dyck), whose collection is published under the Creative Commons Attribution-NonCommercial license (CC BY-NC), with gratitude.';

  @override
  String get settingsAboutLicensesHeader => 'Licenses';

  @override
  String get settingsAboutViewLicensesTitle => 'View licenses';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'Full open-source license texts, including the bundled fonts.';

  @override
  String get settingsAboutLegalese =>
      '© The Caller’s Compendium contributors. Licensed under AGPL-3.0.';

  @override
  String settingsAboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String settingsAboutVersionLine(
    String appName,
    String version,
    String license,
  ) {
    return '$appName · Version $version · $license';
  }

  @override
  String get settingsUpdatesHeader => 'Updates';

  @override
  String get settingsUpdatesCheckNowTitle => 'Check for updates';

  @override
  String settingsUpdatesStatusIdle(String version) {
    return 'You\'re on version $version.';
  }

  @override
  String get settingsUpdatesStatusChecking => 'Checking…';

  @override
  String settingsUpdatesStatusNoUpdate(String version) {
    return 'No update found. You\'re on version $version.';
  }

  @override
  String settingsUpdatesStatusAvailable(String version) {
    return 'Version $version is available. See the banner to view it.';
  }

  @override
  String get settingsUpdatesChannelHeader => 'Channel';

  @override
  String get settingsUpdatesBetaTitle => 'Beta channel';

  @override
  String get settingsUpdatesBetaSubtitle =>
      'Receive pre-release beta updates. Off means stable releases only.';

  @override
  String get settingsUpdatesAutoHeader => 'Automatic checks';

  @override
  String get settingsUpdatesAutoTitle => 'Check automatically';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'Check for a newer version in the background when the app starts. Off by default.';

  @override
  String get settingsUpdatesPrivacyNote =>
      'The update check downloads a small version file over HTTPS and nothing else — no data about you, your device, or your usage is ever sent. Nothing is downloaded or installed automatically: you choose when to download an update, it is verified before it opens, and your system installer completes the install.';

  @override
  String get settingsUpdatesDownloadingTitle => 'Downloading update';

  @override
  String get settingsUpdatesDownloadingIndeterminate => 'Downloading…';

  @override
  String settingsUpdatesDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get settingsUpdatesVerifyingTitle => 'Verifying download';

  @override
  String get settingsUpdatesVerifyingSubtitle =>
      'Checking the sha256 integrity of the download…';

  @override
  String get settingsUpdatesHandoffTitle => 'Preparing the installer';

  @override
  String get settingsUpdatesHandoffSubtitle =>
      'Handing the verified update to your system…';

  @override
  String get settingsUpdatesCompletedTitle => 'Update downloaded';

  @override
  String get settingsUpdatesCompletedSubtitle =>
      'Follow your system installer to finish updating.';

  @override
  String get settingsUpdatesCompletedSubtitleRevealed =>
      'Verified and revealed in your file manager — run the installer to finish updating.';

  @override
  String get settingsUpdatesDownloadTitle => 'Download & install update';

  @override
  String get settingsUpdatesDownloadError =>
      'The update could not be downloaded.';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'Download version $version, verify it, then open your installer. The app never replaces itself in place.';
  }

  @override
  String get settingsDialectHeader => 'Dialects';

  @override
  String get settingsDialectNewButton => 'New dialect';

  @override
  String get settingsDialectNewDefaultName => 'My dialect';

  @override
  String get settingsDialectCreateConfirm => 'Create';

  @override
  String get settingsDialectDuplicateFrom => 'Duplicate from…';

  @override
  String get settingsDialectRenameTitle => 'Rename dialect';

  @override
  String get settingsDialectRename => 'Rename';

  @override
  String get settingsDialectEditTerms => 'Edit terms';

  @override
  String get settingsDialectDuplicateToCustomize => 'Duplicate to customize';

  @override
  String get settingsDialectDeleteTitle => 'Delete dialect?';

  @override
  String settingsDialectDeleteConfirmBody(String name) {
    return '“$name” will be permanently removed.';
  }

  @override
  String get settingsDialectActionsTooltip => 'Dialect actions';

  @override
  String get settingsDialectPresetBadge => 'Preset';

  @override
  String get settingsDialectNameLabel => 'Name';

  @override
  String get settingsAppearanceThemeHeader => 'Theme';

  @override
  String get settingsAppearanceCustomThemesHeader => 'Custom themes';

  @override
  String get settingsAppearanceEasterEggsHeader => 'Easter eggs';

  @override
  String get settingsAppearanceSetListsHeader => 'Set lists';

  @override
  String get settingsAppearanceFormationColoursHeader => 'Formation colours';

  @override
  String get settingsAppearanceColourDanceTitle =>
      'Colour-named dances tint the theme';

  @override
  String get settingsAppearanceColourDanceSubtitle =>
      'A playful surprise: when you open a dance whose title names a colour — like Baby Rose or Blue Boy — its view is tinted that colour. Off by default, and it steps aside when a high-contrast theme is active so readability always wins.';

  @override
  String get settingsAppearanceSetListColorTitle => 'Colour-code set-list rows';

  @override
  String get settingsAppearanceSetListColorSubtitle =>
      'Tint each dance row by its formation family (contra, mixer, square, …) — dances marked as mixers always get the mixer tint, regardless of formation. The formation is always shown as text too, so rows stay readable without colour.';

  @override
  String get settingsAppearanceFormationColoursTitle =>
      'Formation label colours';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      'Highlight individual formations in your own colours — e.g. Becket (CW) in yellow, Becket (CCW) in pink — on dance cards, dance detail, and the Perform header.';

  @override
  String get settingsAppearanceSelectedBadge => 'Selected';

  @override
  String get settingsAppearancePreviewHeading => 'Aa Preview';

  @override
  String get settingsAppearancePreviewBody => 'Body text sample';

  @override
  String get settingsAppearanceNewThemeButton => 'New custom theme';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'My theme';

  @override
  String get settingsAppearanceCustomThemesEmpty =>
      'Copy the current theme and tune any color. Custom themes are saved on this device.';

  @override
  String get settingsAppearanceDeleteThemeTitle => 'Delete theme?';

  @override
  String settingsAppearanceDeleteThemeBody(String name) {
    return '“$name” will be permanently removed.';
  }

  @override
  String settingsAppearanceCustomThemeSemantic(String name) {
    return 'Custom theme $name';
  }

  @override
  String get settingsAppearanceThemeActionsTooltip => 'Theme actions';

  @override
  String get settingsDefaultsProgramHeader => 'Program defaults';

  @override
  String get settingsDefaultsCallerLabel => 'Default caller';

  @override
  String get settingsDefaultsPrefilledHelper =>
      'Prefilled into new programs; editable per program.';

  @override
  String get settingsDefaultsBandLabel => 'Default band';

  @override
  String get settingsDefaultsDisplayHeader => 'Display defaults';

  @override
  String get settingsDefaultsSortTitle => 'Collection sort order';

  @override
  String get settingsDefaultsSortSubtitle =>
      'How the Collection is sorted when you open it. You can still change the sort while browsing.';

  @override
  String get settingsDefaultsCanonicalTitle =>
      'Open dance details in canonical terms';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'When on, a dance opens showing canonical role and move names instead of your active dialect. You can still switch views on the dance while it is open.';

  @override
  String get settingsDefaultsCollectionCardHeader => 'Collection card fields';

  @override
  String get settingsDefaultsCollectionCardSubtitle =>
      'Choose which details appear on each dance row. All fields are shown by default.';

  @override
  String get settingsDefaultsCollectionCardAuthors => 'Authors';

  @override
  String get settingsDefaultsCollectionCardCalledCount => 'Times called';

  @override
  String get settingsDefaultsCollectionCardFormation => 'Formation';

  @override
  String get settingsDefaultsCollectionCardStatus => 'Status';

  @override
  String get settingsDefaultsCollectionCardLevel => 'Level';

  @override
  String get settingsDefaultsCollectionCardRating => 'Rating';

  @override
  String get settingsDefaultsCollectionCardTags => 'Tags';

  @override
  String get settingsDefaultsCollectionCardCustomFields => 'Custom fields';

  @override
  String get settingsDefaultsAuthoringHeader => 'Dance-authoring defaults';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'Free-text entry';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'When on, adding a new figure lets you type it as one line (e.g. \"neighbor balance & swing\") instead of building it field by field. The line is parsed into figure(s); anything unrecognized is kept as a custom figure you can fix later. Editing an existing figure always uses the full editor.';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateTitle =>
      'Aggressively recompute figure beats';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle =>
      'When on, changing a figure\'s move or a param that affects timing recalculates its beat count immediately — even overwriting a beat count you typed in by hand. When off (default), a beat count you\'ve edited is never changed automatically.';

  @override
  String get settingsDefaultsFigureShorthandsTitle => 'Figure shorthands';

  @override
  String get settingsDefaultsFigureShorthandsEmptySubtitle =>
      'Map short tokens to one or more figures you can insert during free-text entry.';

  @override
  String settingsDefaultsFigureShorthandsCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shorthands defined.',
      one: '1 shorthand defined.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsFormTitle => 'Form';

  @override
  String get settingsDefaultsFormSubtitle =>
      'The dance form a new dance starts as. You can still change it per dance.';

  @override
  String get settingsDefaultsFormationTitle => 'Formation';

  @override
  String get settingsDefaultsFormationSubtitle =>
      'The formation a new dance starts in. You can still change it per dance.';

  @override
  String get settingsDefaultsProgressionTitle => 'Progression';

  @override
  String get settingsDefaultsProgressionSubtitle =>
      'The progression a new dance starts with. You can still change it per dance.';

  @override
  String get settingsDefaultsPhraseLabel => 'Default phrase structure';

  @override
  String get settingsDefaultsPhraseHelper =>
      'Seeded into new dances. Blank = standard 4×16 (A1 A2 B1 B2); else e.g. 6*8*2.';

  @override
  String get settingsDefaultsStartingFiguresTitle => 'Starting figures';

  @override
  String get settingsDefaultsStartingFiguresSubtitle =>
      'The figures a new dance starts with. Defaults to a single stand still (8 beats); clear it for a blank new dance. Editable per dance.';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'Move defaults';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'Preferred parameter values applied when you insert a move while entering a dance. These override that move\'s built-in defaults; you can still change any parameter on the figure afterward. Unset moves and parameters use the built-in defaults.';

  @override
  String get settingsDefaultsAddMoveButton => 'Add move default';

  @override
  String get settingsDefaultsRemoveMoveTooltip => 'Remove';

  @override
  String get settingsDefaultsMoveGone =>
      'This move is no longer in the taxonomy.';

  @override
  String get settingsDefaultsMoveNoParams =>
      'This move has no parameters to default.';

  @override
  String get settingsFormationColoursTitle => 'Formation colours';

  @override
  String get settingsFormationColoursIntro =>
      'Give a formation its own colour to highlight its label on dance cards, dance detail, and the Perform header. Only the formations you customise are highlighted; the rest show their label as usual. The formation is always shown as text too, so labels stay readable without colour.';

  @override
  String get settingsFormationColoursListHeader => 'Formations';

  @override
  String get settingsFormationColoursCustom => 'Custom colour';

  @override
  String get settingsFormationColoursFamilyDefault => 'Family default';

  @override
  String settingsFormationColoursResetTooltip(String label) {
    return 'Reset $label to the family default';
  }

  @override
  String get settingsAppearanceTagColoursHeader => 'Tag colours';

  @override
  String get settingsAppearanceTagColoursTitle => 'Tag colours';

  @override
  String get settingsAppearanceTagColoursSubtitle =>
      'Give a tag its own colour to make it stand out on dance cards and dance detail. The tag\'s name is always shown too, so tags stay readable without colour.';

  @override
  String get settingsTagColoursTitle => 'Tag colours';

  @override
  String get settingsTagColoursIntro =>
      'Give a tag its own colour to make it stand out wherever it appears. Only the tags you colour change; the rest look exactly as they do now. The tag\'s name is always shown too, so tags stay readable without colour.';

  @override
  String get settingsTagColoursListHeader => 'Tags';

  @override
  String get settingsTagColoursEmpty =>
      'You haven\'t created any tags yet. Add a tag to a dance and it will appear here.';

  @override
  String get settingsTagColoursCustom => 'Custom colour';

  @override
  String get settingsTagColoursNoColour => 'No colour';

  @override
  String settingsTagColoursResetTooltip(String label) {
    return 'Remove $label\'s colour';
  }

  @override
  String get settingsTagColoursSaveError =>
      'Couldn\'t save that colour. Please try again.';

  @override
  String get settingsTagColoursLoadError => 'Couldn\'t load your tags.';

  @override
  String get settingsGeneralLibraryHeader => 'Library';

  @override
  String get settingsGeneralSortIgnoreArticlesTitle =>
      'Ignore leading articles when sorting';

  @override
  String get settingsGeneralSortIgnoreArticlesSubtitle =>
      'When on, the dance list alphabetizes titles ignoring a leading “the”, “a”, or “an” — so “The Nice Combination” files under N. Turn off to sort by the literal title.';

  @override
  String get settingsGeneralVenuesHeader => 'Venues';

  @override
  String get settingsGeneralVenueEntityModeTitle =>
      'Use reusable venue records';

  @override
  String get settingsGeneralVenueEntityModeSubtitle =>
      'Turn venues into reusable records with address, contacts, and schedule that many programs can share and you edit in one place. When off, a program’s venue is a simple free-text field. Switching is lossless — your typed venue and any linked record are both kept.';

  @override
  String get settingsGeneralManageVenuesTitle => 'Manage venues';

  @override
  String get settingsGeneralManageVenuesSubtitle =>
      'Browse, edit, and delete your reusable venue records.';

  @override
  String get settingsGeneralPerformanceHeader => 'Performance';

  @override
  String get settingsGeneralAutoSizePerformTitle => 'Auto-size Perform cards';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      'Scale each card so the full dance or slot fits the screen without scrolling. Turn off to set the size yourself with A- / A+.';

  @override
  String get settingsGeneralCallingHistoryHeader => 'Calling history';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      'Require “mark performed” for calling history';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'When on, a dance’s calling history lists only programs whose slot for that dance was marked performed. When off, a program appears as soon as it contains the dance.';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'Track calling history for all callers';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'When off and a default caller is set, calling history and counts include programs led by that caller plus any programs with no caller recorded (treated as your own). When on — or when no default caller is set — every program that contains the dance is tracked.';

  @override
  String get settingsGeneralAccessibilityHeader => 'Accessibility';

  @override
  String get settingsGeneralReduceMotionTitle => 'Reduce motion';

  @override
  String get settingsGeneralReduceMotionSubtitle =>
      'Dampen or skip non-essential animations, such as animated scrolling when moving between search results or figures.';

  @override
  String get settingsGeneralVerboseFiguresTitle =>
      'Always show verbose figure text';

  @override
  String get settingsGeneralVerboseFiguresSubtitle =>
      'Show the full spoken-style figure wording on screen in the dance view, not only to screen readers. Turn off for the terse notation.';

  @override
  String get settingsGeneralDecimalTurnsTitle => 'Show turns as decimals';

  @override
  String get settingsGeneralDecimalTurnsSubtitle =>
      'Show turn and rotation amounts as decimals (0.75) instead of fractions (¾). Screen-reader wording is unaffected.';

  @override
  String get settingsGeneralConfirmBeforeDeleteTitle => 'Confirm before delete';

  @override
  String get settingsGeneralConfirmBeforeDeleteSubtitle =>
      'Ask for confirmation before deleting a dance or program. Deletes can still be undone; this just adds an explicit prompt first.';

  @override
  String get settingsGeneralDeletedItemsHeader => 'Deleted items';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle =>
      'Keep deleted dances for';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      'Deleted dances are kept for this long before being permanently removed on app launch. Never keeps them until you purge manually.';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days days';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => 'Never';

  @override
  String get settingsGeneralImportHeader => 'Import';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Bring dances into your collection from a Caller\'s Compendium JSON file. You review every dance and confirm before anything is added.';

  @override
  String get settingsGeneralImportEllipsisAction => 'Import…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle =>
      'Re-check custom figures';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'Re-parse imported dances whose figures were kept as custom only because they could not be recognised at import time. Improved parsing upgrades them in place — your tags, ratings, and notes are preserved. You preview and confirm before anything changes.';

  @override
  String get settingsGeneralReparseCustomFiguresAction => 'Re-check…';

  @override
  String get settingsGeneralBackupRestoreHeader => 'Backup & restore';

  @override
  String get backupExported => 'Backup exported.';

  @override
  String get backupExportFailed => 'Couldn\'t export a backup.';

  @override
  String get backupRestoreIntegrityFailed =>
      'This backup failed its integrity check, so it may be corrupt or was changed after it was exported. The restore was cancelled and your data is unchanged.';

  @override
  String get backupRestoreIncompatibleVersion =>
      'This backup contains items this version of the app can\'t read (it may be from a newer version), so the restore was cancelled. Your data is unchanged.';

  @override
  String get backupRestoreInvalidFile =>
      'Couldn\'t restore: the file isn\'t a valid backup. Your data is unchanged.';

  @override
  String backupRestoreSkippedProblems(int count) {
    return 'Backup restored with $count problem(s) skipped.';
  }

  @override
  String get backupRestored => 'Backup restored.';

  @override
  String get backupRestoreFailed => 'Couldn\'t restore the backup.';

  @override
  String get backupRestoreSettingsFailed =>
      'Your dances and programs were restored, but applying your saved settings failed. Your restored content is safe — you can retry applying settings.';

  @override
  String get backupRestoreSettingsRetryAction => 'Retry settings';

  @override
  String get backupRestoreSettingsRetried => 'Settings applied.';

  @override
  String get backupExportTitle => 'Export a backup';

  @override
  String get backupExportSubtitle =>
      'Save your entire collection, programs, custom fields, dialects, themes, and settings to a single JSON file you can keep safe or move to another device.';

  @override
  String get backupExportAction => 'Export';

  @override
  String get backupRestoreTitle => 'Restore from a backup';

  @override
  String get backupRestoreSubtitle =>
      'Replace everything currently in the app with the contents of a backup file. This cannot be undone.';

  @override
  String get backupRestoreAction => 'Restore';

  @override
  String get backupReminderTitle => 'Backup reminder';

  @override
  String get backupLastBackupNever => 'Last backup: never';

  @override
  String backupLastBackupDate(String date) {
    return 'Last backup: $date';
  }

  @override
  String get backupReminderOff => 'Off';

  @override
  String get backupReminderWeekly => 'Weekly';

  @override
  String get backupReminderMonthly => 'Monthly';

  @override
  String get backupOverdueHint =>
      'It\'s been a while since your last backup — consider exporting one now.';

  @override
  String get backupRestoreDialogBody =>
      'Restoring replaces everything currently in the app — your collection, programs, dialects, themes, and settings — with the backup\'s contents. This cannot be undone.';

  @override
  String get backupChooseFileAction => 'Choose file…';

  @override
  String get backupPasteJsonLabel => 'Or paste backup JSON';

  @override
  String get backupReplaceAllDataAction => 'Replace all data';

  @override
  String get diagnosticsNoDiagnosticsToExport => 'No diagnostics to export.';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      'Couldn\'t prepare a safe (scrubbed) export, so nothing was saved. Please try again, or use full detail deliberately.';

  @override
  String get diagnosticsLogExported => 'Diagnostics log exported.';

  @override
  String get diagnosticsExportCancelled => 'Export cancelled.';

  @override
  String get diagnosticsExportFailed => 'Couldn\'t export the diagnostics log.';

  @override
  String get diagnosticsClearLogTitle => 'Clear diagnostics log?';

  @override
  String get diagnosticsClearLogBody =>
      'This permanently deletes the local crash log from this device. This cannot be undone.';

  @override
  String get diagnosticsClearAction => 'Clear';

  @override
  String get diagnosticsLogCleared => 'Diagnostics log cleared.';

  @override
  String get diagnosticsHeader => 'Diagnostics';

  @override
  String get diagnosticsIntro =>
      'When something goes wrong, the app records a technical note to a local log on this device to help diagnose the problem. It is never sent anywhere — there is no telemetry. You can export it to attach to a bug report, or clear it at any time.';

  @override
  String get diagnosticsRecentEntriesHeader => 'Recent entries';

  @override
  String get diagnosticsReadFailedTitle => 'Couldn\'t read the diagnostics log';

  @override
  String get diagnosticsReadFailedSubtitle =>
      'The local log may be inaccessible on this device. You can still try to export or clear it.';

  @override
  String get diagnosticsEmptyTitle => 'No errors recorded';

  @override
  String get diagnosticsEmptySubtitle =>
      'Nothing has been captured on this device.';

  @override
  String get diagnosticsExportHeader => 'Export';

  @override
  String get diagnosticsFullDetailTitle =>
      'Include full detail (may contain your content)';

  @override
  String get diagnosticsFullDetailSubtitle =>
      'Off by default. When off, the export removes your content, file paths, emails, and phone numbers.';

  @override
  String get diagnosticsExportShareLogTitle => 'Export / share log';

  @override
  String get diagnosticsExportShareFullSubtitle =>
      'Shares the full, unredacted log.';

  @override
  String get diagnosticsExportShareScrubbedSubtitle =>
      'Shares a scrubbed copy safe to attach to a bug report.';

  @override
  String get diagnosticsClearLogRowTitle => 'Clear log';

  @override
  String get diagnosticsClearLogRowSubtitle =>
      'Delete the local crash log from this device.';

  @override
  String get crashFallbackTitle => 'Something went wrong here';

  @override
  String get crashFallbackBody =>
      'This part of the app hit an unexpected error and recovered. The details were saved to a local diagnostics log (Settings ▸ Diagnostics) that never leaves your device.';

  @override
  String get crashFallbackCopied => 'Copied';

  @override
  String get crashFallbackCopyDetails => 'Copy details';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonDuplicate => 'Duplicate';

  @override
  String commonDuplicateTitleSuffix(String title) {
    return '$title (copy)';
  }

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonCouldntOpenLink => 'Couldn\'t open link';

  @override
  String get commonProgression => 'Progression';

  @override
  String get commonDanceFormContra => 'Contra';

  @override
  String get commonDanceFormEcd => 'English (ECD)';

  @override
  String get commonDanceFormSquare => 'Square';

  @override
  String get commonProgressionNone => 'No progression';

  @override
  String get commonProgressionSingle => 'Single';

  @override
  String get commonProgressionDouble => 'Double';

  @override
  String get commonProgressionTriple => 'Triple';

  @override
  String get commonProgressionQuadruple => 'Quadruple';

  @override
  String get commonProgressionOther => 'Other';

  @override
  String get commonDanceStatusActive => 'Active';

  @override
  String get commonDanceStatusDeprecated => 'Deprecated';

  @override
  String get commonDanceStatusBroken => 'Broken';

  @override
  String get commonDanceLevelBeginner => 'Beginner';

  @override
  String get commonDanceLevelIntermediate => 'Intermediate';

  @override
  String get commonDanceLevelAdvanced => 'Advanced';

  @override
  String get commonFormationDupleImproper => 'Duple improper';

  @override
  String get commonFormationBecketCw => 'Becket (CW)';

  @override
  String get commonFormationBecketCcw => 'Becket (CCW)';

  @override
  String get commonFormationDupleProper => 'Duple proper';

  @override
  String get commonFormationDupleIndecent => 'Duple indecent';

  @override
  String get commonFormationTripleMinor => 'Triple minor';

  @override
  String get commonFormationThreeFaceThree => 'Three-face-three';

  @override
  String get commonFormationFourFaceFour => 'Four-face-four';

  @override
  String get commonFormationCircleMixer => 'Circle mixer';

  @override
  String get commonFormationSicilianCircle => 'Sicilian circle';

  @override
  String get commonFormationScatterMixer => 'Scatter mixer';

  @override
  String get commonFormationLongways => 'Longways';

  @override
  String get commonFormationTriplet => 'Triplet';

  @override
  String get commonFormationGrid => 'Grid';

  @override
  String get commonFormationOther => 'Other';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonMixedLevel => 'Mixed level';

  @override
  String get commonMixer => 'Mixer';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'Show dances tagged “$tagName”';
  }

  @override
  String commonDeletedSnack(String title) {
    return '\"$title\" deleted.';
  }

  @override
  String get importGapMessage =>
      'Couldn\'t parse this call — kept verbatim as a custom figure.';

  @override
  String get importGapDialogTitle => 'Unrecognized figure';

  @override
  String get importGapSemanticLabel =>
      'Unrecognized figure. Couldn\'t parse this call — kept verbatim as a custom figure.';

  @override
  String get collectionScreenTitle => 'Collection';

  @override
  String get collectionNewDance => 'New dance';

  @override
  String get collectionSearchTooltip => 'Search (Ctrl/Cmd-K)';

  @override
  String get collectionSelectDancesTooltip => 'Select dances';

  @override
  String get collectionManageCustomFieldsTooltip => 'Manage custom fields';

  @override
  String get collectionRecentlyDeletedTooltip => 'Recently deleted';

  @override
  String collectionSortByTooltip(String sortLabel) {
    return 'Sort by ($sortLabel)';
  }

  @override
  String get collectionSortRelevance => 'Best match';

  @override
  String get collectionSortTitle => 'Title';

  @override
  String get collectionSortAuthor => 'Author';

  @override
  String get collectionSortRecentlyAdded => 'Recently added';

  @override
  String get collectionSortLastCalled => 'Last called';

  @override
  String get collectionSortAscendingTooltip => 'Ascending (tap for descending)';

  @override
  String get collectionSortDescendingTooltip =>
      'Descending (tap for ascending)';

  @override
  String get collectionGroupByCategoryTooltip => 'Group by category';

  @override
  String collectionGroupByCategoryActiveTooltip(String tag) {
    return 'Grouped by $tag';
  }

  @override
  String get collectionGroupByNone => 'No grouping';

  @override
  String get collectionGroupByHeader => 'Category';

  @override
  String get collectionGroupOther => 'Other';

  @override
  String collectionGroupSectionSemantics(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dances',
      one: '1 dance',
    );
    return '$label, $_temp0';
  }

  @override
  String get collectionExitSelectionTooltip => 'Exit selection';

  @override
  String collectionSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get collectionAddTags => 'Add tags';

  @override
  String get collectionRemoveTags => 'Remove tags';

  @override
  String get collectionSetLevel => 'Set level';

  @override
  String get collectionSearchFieldLabel => 'Search dances';

  @override
  String get collectionSearchFieldHint =>
      'Search titles, authors, figures, notes…';

  @override
  String get collectionClearSearchTooltip => 'Clear search and filters';

  @override
  String get collectionLoadError => 'Could not load the collection.';

  @override
  String collectionDuplicatedSnack(String title) {
    return 'Duplicated as \"$title\".';
  }

  @override
  String get collectionEmpty =>
      'Your collection is empty. Add or import a dance to get started — or turn on Online search above to import from an online source.';

  @override
  String get collectionFiltersTitle => 'Filters';

  @override
  String collectionFiltersActive(int count) {
    return 'Filters ($count active)';
  }

  @override
  String get collectionByPhraseTitle => 'By phrase';

  @override
  String collectionByPhraseActive(int count) {
    return 'By phrase ($count active)';
  }

  @override
  String get collectionAdvancedTitle => 'Advanced';

  @override
  String get collectionUseAdvancedQuery => 'Use advanced query';

  @override
  String get collectionUseAdvancedQuerySubtitle =>
      'Combine figures and sequences with all / any / none groups.';

  @override
  String collectionDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dances',
      one: '1 dance',
    );
    return '$_temp0';
  }

  @override
  String get collectionSearchError =>
      'Something went wrong running the search.';

  @override
  String get collectionNoResults => 'No dances match your search.';

  @override
  String get collectionBatchNoChanges => 'No changes';

  @override
  String collectionBatchTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tagged $count dances',
      one: 'Tagged 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Removed tags from $count dances',
      one: 'Removed tags from 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Set level on $count dances',
      one: 'Set level on 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cleared level on $count dances',
      one: 'Cleared level on 1 dance',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchMore => 'More batch actions';

  @override
  String get collectionSetRating => 'Set rating';

  @override
  String get collectionAddTunes => 'Add tunes';

  @override
  String get collectionClearTunes => 'Clear tunes';

  @override
  String get collectionEditCustomField => 'Edit custom field';

  @override
  String collectionBatchRatingSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Set rating on $count dances',
      one: 'Set rating on 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchRatingCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cleared rating on $count dances',
      one: 'Cleared rating on 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added tunes to $count dances',
      one: 'Added tunes to 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cleared tunes from $count dances',
      one: 'Cleared tunes from 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated field on $count dances',
      one: 'Updated field on 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cleared field on $count dances',
      one: 'Cleared field on 1 dance',
    );
    return '$_temp0';
  }

  @override
  String collectionSelectDanceLabel(String title) {
    return 'Select $title';
  }

  @override
  String collectionCalledBadge(int count) {
    return 'called ×$count';
  }

  @override
  String collectionCalledBadgeSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'called $count times',
      one: 'called 1 time',
    );
    return '$_temp0';
  }

  @override
  String collectionRatingSemantic(int rating) {
    return 'Rating: $rating of 5 stars';
  }

  @override
  String collectionRowActionsSemantic(String title) {
    return 'Actions for $title';
  }

  @override
  String get collectionSplitEmptyTitle => 'Select a dance';

  @override
  String get collectionSplitEmptySubtitle =>
      'Choose a dance from the list to view its details.';

  @override
  String get collectionFacetType => 'Type';

  @override
  String get collectionFacetFormation => 'Formation';

  @override
  String get collectionFacetStatus => 'Status';

  @override
  String get collectionFacetLevel => 'Level';

  @override
  String get collectionFacetMinRating => 'Minimum rating';

  @override
  String collectionFacetMinRatingChip(int min) {
    return '≥$min★';
  }

  @override
  String get collectionFacetTags => 'Tags';

  @override
  String get collectionFacetSource => 'Source';

  @override
  String get collectionFacetAuthor => 'Author';

  @override
  String get collectionFacetNone =>
      'No filters available for this collection yet.';

  @override
  String get collectionFacetClear => 'Clear filters';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return 'Remove $name';
  }

  @override
  String get collectionFacetAuthorSearchHint => 'Search authors…';

  @override
  String get collectionFacetOpContains => 'contains';

  @override
  String get collectionFacetOpEquals => 'equals';

  @override
  String collectionFacetTextHint(String label) {
    return 'Filter by $label…';
  }

  @override
  String get collectionFacetNumOpEq => '=';

  @override
  String get collectionFacetNumOpLt => '<';

  @override
  String get collectionFacetNumOpGt => '>';

  @override
  String get collectionFacetNumOpBetween => 'between';

  @override
  String get collectionFacetNumFrom => 'From';

  @override
  String get collectionFacetNumValue => 'Value';

  @override
  String get collectionFacetNumTo => 'To';

  @override
  String get collectionByPhraseOrdinalFirst => 'first phrase';

  @override
  String get collectionByPhraseOrdinalSecond => 'second phrase';

  @override
  String get collectionByPhraseOrdinalThird => 'third phrase';

  @override
  String get collectionByPhraseOrdinalFourth => 'fourth phrase';

  @override
  String collectionByPhraseOrdinalN(int number) {
    return 'phrase $number';
  }

  @override
  String collectionByPhraseCaption(String ordinal, String label) {
    return '$ordinal (usually $label)';
  }

  @override
  String collectionByPhraseFieldMatch(String caption) {
    return '$caption, figures match';
  }

  @override
  String collectionByPhraseFieldExclude(String caption) {
    return '$caption, but do not match';
  }

  @override
  String collectionByPhraseRemoveMove(String move, String field) {
    return 'Remove $move from $field';
  }

  @override
  String get collectionQueryMatchLabel => 'Match';

  @override
  String get collectionQueryGroupAll => 'All of';

  @override
  String get collectionQueryGroupAny => 'Any of';

  @override
  String get collectionQueryGroupNone => 'None of';

  @override
  String get collectionQueryTheseConditions => 'these conditions';

  @override
  String get collectionQueryRemoveGroup => 'Remove group';

  @override
  String get collectionQueryEmptyGroup => 'No conditions yet — add one below.';

  @override
  String get collectionQueryAddCondition => 'Add a condition';

  @override
  String get collectionQueryHasFigure => 'Has figure';

  @override
  String get collectionQuerySequenceThen => 'Sequence (then)';

  @override
  String get collectionQueryConditionGroup => 'Condition group';

  @override
  String get collectionQueryAddButton => 'Add';

  @override
  String get collectionQueryRemoveFigure => 'Remove figure';

  @override
  String get collectionQueryThenFirst => 'First';

  @override
  String get collectionQueryThenConnector => 'then';

  @override
  String get collectionQueryThenLater => 'Later';

  @override
  String get collectionQueryRemoveSequence => 'Remove sequence';

  @override
  String get collectionQueryGroupFigures => 'Group figures';

  @override
  String get collectionQueryFigureGroupMatch => 'Figure group match';

  @override
  String get collectionQueryOfTheseFigures => 'of these figures';

  @override
  String get collectionQuerySingleFigure => 'Single figure';

  @override
  String get collectionQueryAddFigure => 'Add figure';

  @override
  String get collectionQueryRemoveFigureGroup => 'Remove figure group';

  @override
  String get collectionQueryMoveLabel => 'Move';

  @override
  String get collectionQueryMoveHint => 'e.g. swing';

  @override
  String get collectionQuerySectionLabel => 'Section';

  @override
  String get collectionQueryAnySection => 'Any section';

  @override
  String collectionQueryAnyParam(String param) {
    return 'Any $param';
  }

  @override
  String get collectionBatchLevelUnspecified => 'Unspecified (clear)';

  @override
  String get collectionBatchLevelConfirm => 'Set';

  @override
  String get collectionBatchTagEmptyAdd => 'No tags yet. Create one below.';

  @override
  String get collectionBatchTagEmptyRemove =>
      'The selected dances have no tags to remove.';

  @override
  String get collectionCreateTagLabel => 'Create a tag';

  @override
  String get collectionCreateTagButton => 'Create tag';

  @override
  String get collectionCreateTagError => 'Could not create tag. Try again.';

  @override
  String get collectionBatchTagAddConfirm => 'Add';

  @override
  String get collectionBatchTagRemoveConfirm => 'Remove';

  @override
  String collectionBatchRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchRatingUnrated => 'Unrated (clear)';

  @override
  String get collectionBatchRatingConfirm => 'Set';

  @override
  String get collectionBatchTunesFieldLabel => 'Add a tune';

  @override
  String get collectionBatchTunesAddButton => 'Add tune to list';

  @override
  String get collectionBatchTunesEmpty =>
      'Type a tune name and add it to the list.';

  @override
  String collectionBatchTunesRemove(String tune) {
    return 'Remove $tune from list';
  }

  @override
  String get collectionBatchTunesConfirm => 'Add';

  @override
  String get collectionBatchClearTunesConfirmTitle => 'Clear tunes?';

  @override
  String get collectionBatchClearTunesConfirmBody =>
      'This removes all tunes from the selected dances. You can undo it afterwards.';

  @override
  String get collectionBatchClearTunesConfirmButton => 'Clear tunes';

  @override
  String get collectionBatchCustomFieldKeyLabel => 'Field';

  @override
  String get collectionBatchCustomFieldClearOption => 'Clear this field';

  @override
  String get collectionBatchCustomFieldEmpty =>
      'No custom fields are defined yet.';

  @override
  String get collectionBatchCustomFieldNumberInvalid => 'Enter a number';

  @override
  String get collectionBatchCustomFieldConfirm => 'Apply';

  @override
  String get danceFiguresEmpty => 'No figures yet.';

  @override
  String danceFigureBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats beats',
      one: '1 beat',
    );
    return '$_temp0';
  }

  @override
  String get danceFigureProgressionSemantic => 'progression';

  @override
  String danceFigureNote(String note) {
    return 'note: $note';
  }

  @override
  String get danceScreenTitle => 'Dance';

  @override
  String get danceNotFound => 'Dance not found.';

  @override
  String get danceEditFab => 'Edit';

  @override
  String get danceDuplicateTooltip => 'Duplicate dance';

  @override
  String get danceDeleteTooltip => 'Delete dance';

  @override
  String get danceMoreActions => 'More actions';

  @override
  String get danceSectionFigures => 'Figures';

  @override
  String get danceSectionCallingNotes => 'Calling notes';

  @override
  String get danceSectionWalkthrough => 'Walkthrough';

  @override
  String get danceSectionTunes => 'Tunes';

  @override
  String get danceSectionLinks => 'Links';

  @override
  String get danceMissingRelated => '(missing dance)';

  @override
  String get danceSectionPublishedSources => 'Published sources';

  @override
  String get danceSectionCustomFields => 'Custom fields';

  @override
  String get danceSectionCallingHistory => 'Calling history';

  @override
  String get danceCallingHistoryEmpty => 'Not yet included in any program.';

  @override
  String get danceShowCanonicalTerms => 'Show canonical terms';

  @override
  String get danceCanonicalToggleLabel => 'Canonical';

  @override
  String danceProvenanceVia(String source) {
    return 'via $source';
  }

  @override
  String get danceProvenanceSourceManual => 'manual entry';

  @override
  String get danceProvenanceSourceJson => 'JSON import';

  @override
  String get danceLinkKindVideo => 'video';

  @override
  String get danceLinkKindSource => 'source link';

  @override
  String get danceLinkKindLink => 'link';

  @override
  String danceOpenLinkSemantic(String kind, String display) {
    return 'Open $kind: $display';
  }

  @override
  String danceOpenProgramSemantic(String title, String details) {
    return 'Open program: $title, $details';
  }

  @override
  String danceHalfStatsFirstHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Called $count times in the first half',
      one: 'Called 1 time in the first half',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSecondHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times in the second half',
      one: '1 time in the second half',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'opened the first half $count times',
      one: 'opened the first half 1 time',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'closed the evening (last dance of the second half) $count times',
      one: 'closed the evening (last dance of the second half) 1 time',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSemanticLabel(String description) {
    return 'Half breakdown: $description';
  }

  @override
  String get danceSourceUnknown => '(unknown source)';

  @override
  String danceSourcePage(String page) {
    return 'p. $page';
  }

  @override
  String danceSourceNumber(String number) {
    return 'no. $number';
  }

  @override
  String danceOpenSourceLinkSemantic(String title) {
    return 'Open source link: $title';
  }

  @override
  String danceSourceSemanticPrefix(String title) {
    return 'Source: $title';
  }

  @override
  String danceOpenDanceCrossRefSemantic(String title) {
    return 'Open dance: $title';
  }

  @override
  String get commonAddToProgram => 'Add to program';

  @override
  String get programsEmptyTitle => 'No programs yet';

  @override
  String get programsAddToProgramEmptyBody =>
      'Create a program to start building a set list.';

  @override
  String get programsCreateWithDance => 'Create a new program with this dance';

  @override
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  ) {
    return 'Add \"$danceTitle\" to $programTitle, $details';
  }

  @override
  String programsAddedToProgramSnack(String danceTitle, String programTitle) {
    return 'Added \"$danceTitle\" to $programTitle.';
  }

  @override
  String get programsNewProgram => 'New program';

  @override
  String programsCreatedProgramSnack(String programTitle, String danceTitle) {
    return 'Created \"$programTitle\" with \"$danceTitle\".';
  }

  @override
  String get dancePerformTooltip => 'Perform this dance';

  @override
  String get commonSwitchDialectTooltip => 'Switch dialect';

  @override
  String get programsStatusDraft => 'Draft';

  @override
  String get programsStatusFinalized => 'Finalized';

  @override
  String get programsStatusPerformed => 'Performed';

  @override
  String get programsNoLongerExists => 'This program no longer exists.';

  @override
  String get programsFallbackTitle => 'Program';

  @override
  String get programsUntitledDanceFallback => 'dance';

  @override
  String programsAddedDanceSnack(String title) {
    return 'Added \"$title\".';
  }

  @override
  String programsAddedDanceAnnounce(String title) {
    return 'Added $title to program.';
  }

  @override
  String get programsAddedNoteAnnounce => 'Added note to program.';

  @override
  String get programsAddedBreakAnnounce => 'Added break to program.';

  @override
  String get programsMarkedAllPerformed => 'Marked all dances performed.';

  @override
  String programsSavedSnack(String title) {
    return '\"$title\" saved.';
  }

  @override
  String get programsSaveError => 'Could not save the program.';

  @override
  String programsDuplicatedSnack(String title) {
    return 'Duplicated as \"$title\".';
  }

  @override
  String programsDeletedSnack(String title) {
    return '\"$title\" deleted.';
  }

  @override
  String get programsDiscardTitle => 'Discard changes?';

  @override
  String get programsDiscardBody => 'You have unsaved changes to this program.';

  @override
  String get programsKeepEditing => 'Keep editing';

  @override
  String get programsDiscard => 'Discard';

  @override
  String get programsDraftTitle => 'Unsaved draft';

  @override
  String get programsDraftBody =>
      'You have an unsaved draft for this program. Would you like to restore it?';

  @override
  String get programsDraftRestore => 'Restore';

  @override
  String get programsDraftDiscard => 'Discard';

  @override
  String get programsBuildProgram => 'Build program';

  @override
  String get programsBuildTab => 'Build';

  @override
  String get programsMatrixTab => 'Matrix';

  @override
  String get programsPerformTooltip => 'Perform this program';

  @override
  String get programsMarkAllPerformedTooltip => 'Mark all performed';

  @override
  String get programsSaveDirty => 'Save *';

  @override
  String get commonSave => 'Save';

  @override
  String get programsLoading => 'Loading program';

  @override
  String get programsLoadError => 'Could not load the program.';

  @override
  String get programsDeletedDanceFallback => '(deleted dance)';

  @override
  String get programsSlotsLabel => 'Slots';

  @override
  String get programsAddDanceButton => 'Add dance';

  @override
  String get programsAddNoteBreakButton => 'Add note / break';

  @override
  String get programsInsertBreakButton => 'Insert break';

  @override
  String get programsAddADanceSheetTitle => 'Add a dance';

  @override
  String get commonClose => 'Close';

  @override
  String get programsNoDateSet => 'No date set';

  @override
  String get programsTitleLabel => 'Title';

  @override
  String get programsTitleHint => 'e.g. Friday Night Contra';

  @override
  String get programsTitleRequired => 'A title is required.';

  @override
  String get programsEventDateLabel => 'Event date';

  @override
  String get programsSetDate => 'Set date';

  @override
  String get programsChangeDate => 'Change';

  @override
  String get programsClearEventDate => 'Clear event date';

  @override
  String get programsVenueLabel => 'Venue';

  @override
  String get programsVenueHint => 'e.g. Grange Hall';

  @override
  String programsVenueLinkedHint(String venueName) {
    return 'Also linked to saved venue: $venueName. Turn on reusable venues in Settings to view or change it.';
  }

  @override
  String get programsVenueLinkedHintFallbackName => 'a saved venue';

  @override
  String programsVenueLegacyTextHint(String venueText) {
    return 'Previously entered venue: “$venueText”. Link a saved venue below to use reusable details — your typed venue is kept.';
  }

  @override
  String get programsBandLabel => 'Band';

  @override
  String get programsBandHint => 'e.g. The Fiddleheads';

  @override
  String get programsCallerLabel => 'Caller';

  @override
  String get programsCallerHint => 'Host caller for the event';

  @override
  String get programsDancerLevelLabel => 'Dancer level';

  @override
  String get programsDancerLevelHint => 'e.g. All welcome, Experienced';

  @override
  String get programsNotesLabel => 'Notes';

  @override
  String get programsStatusFieldLabel => 'Status';

  @override
  String get programsHideAlternatesTitle => 'Hide alternates in set list';

  @override
  String get programsHideAlternatesSubtitle =>
      'Omits ALT slots from the summary, PDF, and exported set list. The builder still shows every slot.';

  @override
  String programsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '1 warning',
    );
    return '$_temp0';
  }

  @override
  String get programsAddNoteBreakDialogTitle => 'Add note or break';

  @override
  String get programsFreeTextLabel => 'Text';

  @override
  String get programsFreeTextHint => 'e.g. Break, waltz, announcement';

  @override
  String get commonAdd => 'Add';

  @override
  String get programsTitle => 'Programs';

  @override
  String get programsSortTitle => 'Title';

  @override
  String get programsSortRecentlyUpdated => 'Recently updated';

  @override
  String get programsSortEventDate => 'Event date';

  @override
  String programsSortByTooltip(String label) {
    return 'Sort by ($label)';
  }

  @override
  String get programsListLoadError => 'Could not load your programs.';

  @override
  String get programsListEmptyBody =>
      'Build set lists for your events here. Create your first program to get started.';

  @override
  String programsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programs',
      one: '1 program',
    );
    return '$_temp0';
  }

  @override
  String get programsSummaryTitle => 'Program';

  @override
  String get programsEditProgram => 'Edit program';

  @override
  String get programsSummaryUnavailable =>
      'This program is no longer available.';

  @override
  String get programsPerformDisabledTooltip =>
      'Add at least one slot to perform this program';

  @override
  String programsSummaryBand(String band) {
    return 'Band: $band';
  }

  @override
  String programsSummaryCaller(String caller) {
    return 'Caller: $caller';
  }

  @override
  String programsSummaryLevel(String level) {
    return 'Level: $level';
  }

  @override
  String programsSetListHeader(int count) {
    return 'Set list ($count)';
  }

  @override
  String get programsSummaryEmptySetList =>
      'No slots yet — open the builder to add dances.';

  @override
  String programsSummaryGuest(String caller) {
    return 'Guest: $caller';
  }

  @override
  String programsPlannedMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get programsAltBadge => 'Alt';

  @override
  String get programsDanceUnavailable => 'Dance unavailable';

  @override
  String programsSummaryNote(String note) {
    return 'Note: $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return 'Alternate: $title';
  }

  @override
  String get programsPerformed => 'Performed';

  @override
  String programsSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '1 slot',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'Note';

  @override
  String get programsSlotEditorEmpty =>
      'No slots yet. Add a dance or a note to get started.';

  @override
  String get programsSlotMoved => 'Slot moved.';

  @override
  String get programsSlotMovedUp => 'Slot moved up.';

  @override
  String get programsSlotMovedDown => 'Slot moved down.';

  @override
  String programsSlotCutBanner(String name) {
    return '\"$name\" is cut — tap Paste to place it.';
  }

  @override
  String get programsPasteBeforeFirst => 'Paste before first slot';

  @override
  String programsPasteAfter(String title) {
    return 'Paste after $title';
  }

  @override
  String get programsPasteHere => 'Paste here';

  @override
  String get programsMarkedPrimary => 'Marked as primary.';

  @override
  String get programsMarkedAlternate => 'Marked as alternate.';

  @override
  String get programsMarkedPerformed => 'Marked performed.';

  @override
  String get programsPerformedCleared => 'Performed mark cleared.';

  @override
  String programsRemovedSlot(String name) {
    return 'Removed $name.';
  }

  @override
  String get programsAltOrdinal => 'ALT';

  @override
  String programsDragToReorder(String title) {
    return 'Drag to reorder $title';
  }

  @override
  String programsMoveSlotUp(String title) {
    return 'Move $title up';
  }

  @override
  String programsMoveSlotDown(String title) {
    return 'Move $title down';
  }

  @override
  String programsCutSlot(String title) {
    return 'Cut $title';
  }

  @override
  String programsMoreActionsForSlot(String title) {
    return 'More actions for $title';
  }

  @override
  String get programsEditSlotMenu => 'Edit slot';

  @override
  String get programsMakePrimaryMenu => 'Make primary';

  @override
  String get programsMarkAlternateMenu => 'Mark as alternate';

  @override
  String get programsClearPerformedMenu => 'Clear performed';

  @override
  String get programsMarkPerformedMenu => 'Mark performed';

  @override
  String get programsRemoveSlotMenu => 'Remove slot';

  @override
  String get programsSlotTextRequiredError => 'Enter some text for this slot.';

  @override
  String get programsWholeNumberError => 'Enter a whole number ≥ 0.';

  @override
  String get programsEditDanceSlotTitle => 'Edit dance slot';

  @override
  String get programsEditNoteTitle => 'Edit note';

  @override
  String get programsCallerNoteLabel => 'Caller note (optional)';

  @override
  String get programsCallerNoteHint => 'e.g. teach the hey first';

  @override
  String get programsGuestCallerLabel => 'Guest caller (optional)';

  @override
  String get programsPlannedMinutesLabel => 'Planned minutes (optional)';

  @override
  String get programsAlternateDanceTitle => 'Alternate dance';

  @override
  String get programsAlternateDanceSubtitle =>
      'Renders indented under the slot above it.';

  @override
  String get commonDone => 'Done';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    String _temp0 = intl.Intl.pluralLogic(
      moveCount,
      locale: localeName,
      other: '$moveCount moves',
      one: '1 move',
    );
    return 'Programming matrix: $danceCount dances by $_temp0';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count free-text slots',
      one: '1 free-text slot',
    );
    return '$_temp0 (breaks, notes) omitted — the matrix shows dances only.';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'Move: $label';
  }

  @override
  String programsMatrixHideColumnSemantic(String label) {
    return 'Hide $label column';
  }

  @override
  String get programsMatrixShowAllColumnsSemantic => 'Show all columns';

  @override
  String programsMatrixRowHeaderSemantic(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': 'Alternate dance: $title, first half',
      'second': 'Alternate dance: $title, second half',
      'other': 'Alternate dance: $title',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': 'Dance: $title, first half',
      'second': 'Dance: $title, second half',
      'other': 'Dance: $title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixHalfShort(String half) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '1st',
      'other': '2nd',
    });
    return '$_temp0';
  }

  @override
  String get programsMatrixFormationColumnHeader => 'Formation';

  @override
  String programsMatrixFormationSemantic(String dance, String label) {
    return '$dance, formation: $label';
  }

  @override
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String collision,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(collision, {
      'yes': ', repeats in the same phrase as an adjacent dance',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(debut, {
      'yes': ', introduced here',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(first, {
      'yes': ', dance\'s first figure',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(present, {
      'no': 'not present',
      'other': 'present$_temp0$_temp1$_temp2',
    });
    return '$dance, $move: $_temp3';
  }

  @override
  String programsMatrixChipQualifiedTitle(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '$title (alternate dance, first half)',
      'second': '$title (alternate dance, second half)',
      'other': '$title (alternate dance)',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': '$title (first half)',
      'second': '$title (second half)',
      'other': '$title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixMoveUsedInSemantic(String label, int count, int total) {
    return 'Move: $label, used in $count of $total dances';
  }

  @override
  String programsMatrixNOfTotal(int count, int total) {
    return '$count of $total';
  }

  @override
  String get programsMatrixNoComparableMoves =>
      'None of these dances have structured figures yet, so there are no moves to compare.';

  @override
  String get programsMatrixRepeatedMovesHeader => 'Repeated moves';

  @override
  String get programsMatrixRepeatedMovesSubtitle =>
      'Moves shared across two or more dances, most-repeated first.';

  @override
  String get programsMatrixNoRepeatsNote =>
      'No moves repeat across these dances — every move below is used by a single dance.';

  @override
  String get programsMatrixUsedOnceHeader => 'Used once';

  @override
  String get programsMatrixLegendIntroduced => 'Introduced here';

  @override
  String get programsMatrixLegendFirstFigure => 'Dance\'s first figure';

  @override
  String get programsMatrixLegendPresent => 'Present';

  @override
  String get programsMatrixLegendCollision => 'Same phrase as adjacent dance';

  @override
  String get programsMatrixEmptyTitle => 'No structured figures yet';

  @override
  String get programsMatrixEmptyBody =>
      'The matrix fills in automatically as the program’s dances gain structured figures.';

  @override
  String get performTitle => 'Perform';

  @override
  String get performExitTooltip => 'Exit performance view';

  @override
  String get performExitTitle => 'Exit Perform?';

  @override
  String get performExitBody =>
      'Leave the performance view? Your place and the running clock are kept, so you can resume where you left off.';

  @override
  String get performExitCancel => 'Keep performing';

  @override
  String get performExitConfirm => 'Exit';

  @override
  String get performTapTempo => 'Tap tempo';

  @override
  String performBpmReadout(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get performTapToSetTempo => 'Tap to set tempo';

  @override
  String performBpmSemantic(int bpm) {
    return '$bpm beats per minute';
  }

  @override
  String get performNoTempoSemantic =>
      'No tempo set yet. Tap the target to set a tempo.';

  @override
  String get performRecordBeatHint => 'record a beat';

  @override
  String get performTapRefineHint =>
      'Keep tapping to refine · Reset to start over';

  @override
  String get performTapTwiceHint => 'Tap at least twice in time with the beat';

  @override
  String get performResetTempo => 'Reset';

  @override
  String get performUntitledSlot => 'Untitled slot';

  @override
  String performMarkedPerformedAnnounce(String label) {
    return 'Marked $label performed';
  }

  @override
  String get performClearedPerformedAnnounce => 'Cleared performed mark';

  @override
  String performMovedToPosition(String label, int position) {
    return 'Moved $label to position $position';
  }

  @override
  String get performDanceFallback => 'dance';

  @override
  String performInsertedAnnounce(String title) {
    return 'Inserted $title';
  }

  @override
  String get performAddedNoteAnnounce => 'Added note';

  @override
  String get performInsertADance => 'Insert a dance';

  @override
  String get performAdjustProgram => 'Adjust program';

  @override
  String get performCurrentSlotSection => 'Current slot';

  @override
  String get performPerformedTapToClear => 'Performed — tap to clear';

  @override
  String get performReorderSection => 'Reorder remaining slots';

  @override
  String get performNoLaterSlots => 'No later slots to reorder.';

  @override
  String get performInsertDanceFromSearch => 'Insert dance from search';

  @override
  String get performAdHocNoteLabel => 'Ad-hoc note / break';

  @override
  String get performAdHocNoteHint => 'e.g. Waltz, announcements';

  @override
  String get performAddNote => 'Add note';

  @override
  String performAlternatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alternates',
      one: '1 alternate',
    );
    return '$_temp0';
  }

  @override
  String performMoveLabelUp(String label) {
    return 'Move \"$label\" up';
  }

  @override
  String performMoveLabelDown(String label) {
    return 'Move \"$label\" down';
  }

  @override
  String performSlotPosition(int current, int total) {
    return 'Slot $current of $total';
  }

  @override
  String performShowingSlot(String label) {
    return 'Showing $label';
  }

  @override
  String get performAdjustmentUndone => 'Adjustment undone';

  @override
  String get performProgramAdjustedSnack => 'Program adjusted.';

  @override
  String get performProgramAdjustedAnnounce => 'Program adjusted';

  @override
  String get performNoSlots => 'This program has no slots.';

  @override
  String get performJumpToSlot => 'Jump to slot';

  @override
  String get performShowAlternate => 'Show alternate';

  @override
  String get performPreviousSlot => 'Previous slot';

  @override
  String get performNextSlot => 'Next slot';

  @override
  String get performResumeTimers => 'Resume timers';

  @override
  String get performPauseTimers => 'Pause timers';

  @override
  String performTimingSemantic(
    String programTime,
    String slotTime,
    String hasPlanned,
    int planned,
    String over,
    String paused,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$planned minutes',
      one: '1 minute',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': ', planned $_temp0',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(over, {
      'yes': ', over planned',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(paused, {
      'yes': ', paused',
      'other': '',
    });
    return 'Program time $programTime, slot time $slotTime$_temp1$_temp2$_temp3';
  }

  @override
  String performPlannedMin(int planned) {
    return 'planned $planned min';
  }

  @override
  String get performOverSuffix => ' over';

  @override
  String get performCallingNotes => 'Calling notes';

  @override
  String get performWalkthrough => 'Walkthrough';

  @override
  String get performShowWalkthrough => 'Show walkthrough';

  @override
  String get performWalkthroughEmpty => 'No walkthrough for this dance.';

  @override
  String get performNoFigures => 'No figures yet.';

  @override
  String get performDecreaseTextSize => 'Decrease text size';

  @override
  String get performIncreaseTextSize => 'Increase text size';

  @override
  String get performShowCanonicalTerms => 'Show canonical terms';

  @override
  String get performMoreActions => 'More actions';

  @override
  String get performAutoSizeMenuLabel => 'Auto-size text to screen';

  @override
  String get performAutoSizeOnTooltip =>
      'Auto-size on — tap for manual text size';

  @override
  String get performAutoSizeOffTooltip =>
      'Auto-size off — tap to fit text to screen';

  @override
  String get performStageThemeOnTooltip =>
      'Stage theme on — tap to use app theme';

  @override
  String get performStageThemeOffTooltip =>
      'Stage theme off — tap for dark stage';

  @override
  String get performProgression => 'Progression';

  @override
  String performFigureSemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    int beats,
    String hasNote,
    String note,
  ) {
    String _temp0 = intl.Intl.selectLogic(importGap, {
      'yes': ', $importGapText',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(progression, {
      'yes': ', progression',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats beats',
      one: '1 beat',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': ', note: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1, $_temp2$_temp3';
  }

  @override
  String get programsSelectTitle => 'Select a program';

  @override
  String get programsSelectBody =>
      'Choose a program from the list, or create a new one.';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonChange => 'Change';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get exportTooltip => 'Export';

  @override
  String get exportShareDanceText => 'Share dance (text)';

  @override
  String get exportCopyDance => 'Copy dance';

  @override
  String get exportPrintPdf => 'Export / print PDF';

  @override
  String get exportDanceCopied => 'Dance copied to clipboard.';

  @override
  String get exportShareDanceError => 'Couldn\'t share this dance';

  @override
  String get exportDanceError => 'Couldn\'t export this dance';

  @override
  String get exportShareSetListText => 'Share set list (text)';

  @override
  String get exportShareProgramBundle => 'Share (program + dances)';

  @override
  String get exportCopySetList => 'Copy set list';

  @override
  String get exportSetListCopied => 'Set list copied to clipboard.';

  @override
  String get exportShareSetListError => 'Couldn\'t share this set list';

  @override
  String get exportShareProgramError => 'Couldn\'t share this program';

  @override
  String get exportSetListError => 'Couldn\'t export this set list';

  @override
  String get exportMatrixPdfTooltip => 'Export or print matrix as PDF';

  @override
  String get exportMatrixPdfFilename => 'Programming matrix';

  @override
  String get exportLabelFormation => 'Formation';

  @override
  String get exportLabelLevel => 'Level';

  @override
  String get exportLabelMixer => 'Mixer';

  @override
  String get exportLabelStatus => 'Status';

  @override
  String get exportLabelPhrase => 'Phrase';

  @override
  String get exportLabelFigures => 'Figures';

  @override
  String get exportLabelCallingNotes => 'Calling notes';

  @override
  String get exportLabelWalkthrough => 'Walkthrough';

  @override
  String exportBeatsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beats',
      one: '1 beat',
    );
    return '$_temp0';
  }

  @override
  String get exportLevelMixedOnly => 'Mixed';

  @override
  String exportLevelWithMixed(String level) {
    return '$level (mixed)';
  }

  @override
  String get exportLabelBand => 'Band';

  @override
  String get exportLabelCaller => 'Caller';

  @override
  String get exportLabelNotes => 'Notes';

  @override
  String get exportLabelAlt => 'ALT';

  @override
  String get exportLabelGuest => 'guest';

  @override
  String get exportLabelPerformed => 'performed';

  @override
  String get exportUnknownDanceLabel => 'Untitled dance';

  @override
  String exportMinutesLabel(int count) {
    return '$count min';
  }

  @override
  String get exportLabelVenue => 'Venue';

  @override
  String get exportLabelTime => 'Time';

  @override
  String get exportLabelSchedule => 'Schedule';

  @override
  String get exportLabelPrice => 'Price';

  @override
  String get exportLabelSponsor => 'Sponsor';

  @override
  String get exportMatrixDefaultTitle => 'Programming matrix';

  @override
  String get exportMatrixDanceColumn => 'Dance';

  @override
  String get exportMatrixFormationColumn => 'Formation';

  @override
  String get exportMatrixEmptyState =>
      'No structured figures yet — the matrix fills in automatically as the program’s dances gain structured figures.';

  @override
  String get exportMatrixLegendDebut => 'Introduced here';

  @override
  String get exportMatrixLegendFirst => 'Dance\'s first figure';

  @override
  String get exportMatrixLegendPresent => 'Present';

  @override
  String get exportMatrixLegendCollision => 'Same phrase as adjacent dance';

  @override
  String exportMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count free-text slots (breaks, notes) omitted — the matrix shows dances only.',
      one:
          '1 free-text slot (breaks, notes) omitted — the matrix shows dances only.',
    );
    return '$_temp0';
  }

  @override
  String get exportVenueContactTitle =>
      'Include venue contact details in this export?';

  @override
  String get exportVenueContactBody =>
      'These are personal contact details for the venue. They\'re left out of this export unless you choose to include them.';

  @override
  String get exportVenueContactConfirm => 'Continue';

  @override
  String get exportVenueContact1Name => 'Contact 1 name';

  @override
  String get exportVenueContact1Phone => 'Contact 1 phone';

  @override
  String get exportVenueContact1Email => 'Contact 1 email';

  @override
  String get exportVenueContact2Name => 'Contact 2 name';

  @override
  String get exportVenueContact2Phone => 'Contact 2 phone';

  @override
  String get exportVenueContact2Email => 'Contact 2 email';

  @override
  String get onlineSearchToggleTitle => 'Online search';

  @override
  String get onlineSearchToggleSubtitle =>
      'Search online and import dances directly (requires internet). Local filters do not apply.';

  @override
  String onlineSearchFieldLabel(String source) {
    return 'Search $source';
  }

  @override
  String get onlineSearchFieldHint => 'Search online dances by title…';

  @override
  String onlineResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count online results',
      one: '1 online result',
    );
    return '$_temp0';
  }

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'Type a title or add by-phrase figures to search $source.';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'Type a title to search $source.';
  }

  @override
  String onlineNoResults(String source) {
    return 'No dances on $source match your search.';
  }

  @override
  String onlineLoadError(String source) {
    return 'Couldn\'t load that dance from $source.';
  }

  @override
  String get onlineImportError => 'Couldn\'t import that dance.';

  @override
  String onlineSearchFailed(String source) {
    return 'Couldn\'t search $source. Please try again.';
  }

  @override
  String onlineImportCreated(String title) {
    return 'Imported \"$title\".';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '\"$title\" is already in your collection.';
  }

  @override
  String onlineImportVariationDialogBody(String existingTitle) {
    return 'This dance\'s title and caller match \"$existingTitle\", but its figures are different. How do you want to import it?';
  }

  @override
  String get onlineImportVariationDialogActionVariation =>
      'Import as a variation';

  @override
  String get onlineImportVariationDialogActionLink =>
      'Same dance (update existing)';

  @override
  String onlineImportVariationDialogLinkWarning(String existingTitle) {
    return 'Your version of \"$existingTitle\" will be replaced by the online record — including its figures, notes, tags, rating, and custom fields. It keeps its place in your programs and its calling history.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogTitle =>
      'You already have this dance';

  @override
  String onlineImportCrossSourceDuplicateDialogBody(String existingTitle) {
    return 'Your collection already has \"$existingTitle\" from a different source. Both versions have the same sequence of moves.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogActionDuplicate =>
      'Import a second copy';

  @override
  String get onlineAttributionCallersBox => 'From The Caller\'s Box (online)';

  @override
  String get onlineAttributionContraDb => 'From ContraDB (online)';

  @override
  String get importDances => 'Import dances';

  @override
  String get importAction => 'Import';

  @override
  String get importProgramTooltip => 'Import program';

  @override
  String get importFromTitleList => 'From title list';

  @override
  String get importFromContraDb => 'From ContraDB';

  @override
  String get importProgramTitleLabel => 'Program title';

  @override
  String get importProgramCreateError => 'Couldn\'t save the imported program.';

  @override
  String importProgramCommitted(
    String title,
    int slots,
    int linked,
    int notes,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      slots,
      locale: localeName,
      other: '$slots slots',
      one: '1 slot',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes',
      one: '1 note',
    );
    return 'Imported \"$title\" — $_temp0 ($linked linked, $_temp1).';
  }

  @override
  String get importContraDbTitle => 'Import from ContraDB';

  @override
  String get importContraDbPasteUrl => 'Paste URL';

  @override
  String get importContraDbSearchByName => 'Search by name';

  @override
  String get importContraDbUrlLabel => 'ContraDB program URL';

  @override
  String get importContraDbUrlHint => 'e.g. https://contradb.com/programs/33';

  @override
  String get importContraDbFetching => 'Fetching…';

  @override
  String get importContraDbFetch => 'Fetch program';

  @override
  String get importContraDbSearchLabel => 'Search ContraDB programs';

  @override
  String get importContraDbSearchHint => 'Type part of a program name';

  @override
  String get importContraDbListError =>
      'Could not load the ContraDB program list.';

  @override
  String get importContraDbSearchPrompt =>
      'Type part of a program name to search ContraDB.';

  @override
  String get importContraDbNoMatches => 'No matching programs.';

  @override
  String get importContraDbMarkerImported => 'Imported';

  @override
  String importContraDbMarkerImportedTooltip(String date) {
    return 'Imported on $date';
  }

  @override
  String get importContraDbMarkerImportedTooltipNoDate =>
      'Already imported from ContraDB';

  @override
  String get importContraDbMarkerPossible => 'Possibly imported';

  @override
  String get importContraDbMarkerPossibleTooltip =>
      'A program with this title already exists';

  @override
  String importContraDbFetchError(String error) {
    return 'Couldn\'t fetch that program.\n$error';
  }

  @override
  String get importContraDbFetchGenericError => 'Couldn\'t fetch that program.';

  @override
  String get importContraDbPastePrompt =>
      'Paste a ContraDB program URL above and tap \"Fetch program\".';

  @override
  String get importContraDbEmptyProgram =>
      'No dances or notes found on that program page.';

  @override
  String get importContraDbResolveError =>
      'Couldn\'t import the ContraDB program.';

  @override
  String importContraDbActivityCount(int activities, int dances, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      activities,
      locale: localeName,
      other: '$activities activities',
      one: '1 activity',
    );
    String _temp1 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances dances',
      one: '1 dance',
    );
    String _temp2 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes',
      one: '1 note',
    );
    return '$_temp0 ($_temp1, $_temp2)';
  }

  @override
  String get importContraDbDanceFallback => 'ContraDB dance';

  @override
  String get importEventDateNone => 'No date set';

  @override
  String get importEventDateLabel => 'Event date';

  @override
  String get importEventDateSet => 'Set date';

  @override
  String get importEventDateClear => 'Clear event date';

  @override
  String get importEventDateDetected =>
      'Date detected from title — check it before importing.';

  @override
  String get importTitleListTitle => 'Import from title list';

  @override
  String get importCollectionLoadError => 'Could not load your collection.';

  @override
  String get importTitleListDancesLabel => 'Dance titles (one per line)';

  @override
  String get importTitleListDancesHint =>
      'Paste one dance title per line.\nUnrecognised lines are kept as notes.';

  @override
  String get importTitleListEmptyHint =>
      'Paste a list of dance titles above to preview the program.';

  @override
  String get importResolving => 'Searching…';

  @override
  String get importResolveOnline => 'Resolve unmatched online';

  @override
  String get importPlaintextImportedOnline => 'Imported from Caller\'s Box';

  @override
  String get importPlaintextLinked => 'Linked to dance';

  @override
  String get importPlaintextAmbiguous => 'Multiple matches — added as note';

  @override
  String get importPlaintextUnmatched => 'No match — added as note';

  @override
  String get importPlaintextSearchError =>
      'Couldn\'t search The Caller\'s Box.';

  @override
  String importPlaintextSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '1 slot',
    );
    return '$_temp0';
  }

  @override
  String importPlaintextResolvedNone(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining titles kept as notes',
      one: '$remaining title kept as a note',
    );
    return 'No confident Caller\'s Box matches found — $_temp0.';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked titles',
      one: '$linked title',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '; $remaining still notes.',
      one: '; $remaining still a note.',
      zero: '.',
    );
    return 'Linked $_temp0 from The Caller\'s Box$_temp1';
  }

  @override
  String get importReviewClose => 'Close import';

  @override
  String get importReviewSourceLabel => 'Source';

  @override
  String importReviewFromSource(String source) {
    return 'Import from $source.';
  }

  @override
  String importReviewDancesFromSource(String source) {
    return 'Import dances from $source.';
  }

  @override
  String get importSourceLabelGenericJson => 'a Caller\'s Compendium JSON file';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'a Caller\'s Companion .USR file';

  @override
  String get importSourceLabelTitleList => 'a list of titles';

  @override
  String get importReviewTitleListSubtitle =>
      'Paste one dance title per line. Every title is listed for review — the ones you already have are shown but never re-imported, and nothing is added to your collection until you confirm.';

  @override
  String get importReviewPasteTitles => 'Dance titles, one per line';

  @override
  String importReviewTitleListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titles',
      one: '1 title',
      zero: 'No titles yet',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count repeated titles ignored',
      one: '1 repeated title ignored',
    );
    return '$_temp0';
  }

  @override
  String importTitleListTooManyTitles(int count, int max) {
    return 'That\'s $count titles. Import up to $max at a time.';
  }

  @override
  String get importTitleListTextTooLong =>
      'That paste is too long to read as a list of titles. Try pasting a shorter list.';

  @override
  String importReviewTitleListProgress(int done, int total) {
    return 'Searching $done of $total…';
  }

  @override
  String importReviewTitleListPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pasted titles',
      one: '1 pasted title',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListToImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to import',
      one: '1 to import',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count already in your collection',
      one: '1 already in your collection',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListNotFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count not found',
      one: '1 not found',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwnedBy(String authors) {
    return 'You already have this, by $authors.';
  }

  @override
  String get importReviewTitleListOwnedUnknownAuthor =>
      'You already have this dance.';

  @override
  String importReviewTitleListOwnedMany(int count) {
    return 'You have $count dances with this title.';
  }

  @override
  String get importTitleListReasonNoResults =>
      'The Caller\'s Box has no dance by this name.';

  @override
  String get importTitleListReasonNoExactMatch =>
      'Only near matches — nothing titled exactly this.';

  @override
  String get importTitleListReasonMultipleExactMatches =>
      'Several dances share this exact title, so it isn\'t clear which you meant.';

  @override
  String get importTitleListReasonFetchError =>
      'Couldn\'t reach The Caller\'s Box for this title.';

  @override
  String get importTitleListReasonLineTooLong =>
      'Too long to be a dance title, so it wasn\'t searched.';

  @override
  String get importReviewTitleListNothingToImport =>
      'Nothing here to import — every title is either already in your collection or couldn\'t be found.';

  @override
  String importReviewSummaryAlreadyOwned(int count) {
    return 'Already in your collection: $count';
  }

  @override
  String importReviewSummaryNotFound(int count) {
    return 'Not found: $count';
  }

  @override
  String get importErrorFileTooLarge => 'That file is too large to import.';

  @override
  String get archiveIntakeRejectedTooLarge =>
      'That file is too large to import.';

  @override
  String get archiveIntakeRejectedUnreadable =>
      'Couldn\'t read the shared file.';

  @override
  String get archiveIntakeRejectedEmpty => 'That file is empty.';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'That file isn\'t a Caller\'s Compendium share file.';

  @override
  String get archiveIntakeRejectedNewerVersion =>
      'That file was made by a newer version of the app. Please update to import it.';

  @override
  String get archiveIntakeRejectedNoContent =>
      'That file didn\'t contain any dances or programs.';

  @override
  String get importErrorInsecureScheme =>
      'Imports must use a secure https:// URL.';

  @override
  String get importErrorBlockedHost =>
      'That URL points to a network location that cannot be imported from.';

  @override
  String get importErrorInvalidUrl =>
      'That doesn\'t look like a valid http(s) URL.';

  @override
  String get importErrorTooManyRedirects =>
      'That URL redirected too many times.';

  @override
  String get importErrorResponseTooLarge =>
      'That response was too large to import.';

  @override
  String get importErrorEmptyUrl => 'Enter a URL to import from.';

  @override
  String importErrorTimeout(int seconds) {
    return 'The request timed out after ${seconds}s. Check the URL and your connection, then try again.';
  }

  @override
  String get importErrorUnreachable =>
      'Couldn\'t reach that URL. Check the URL and your connection, then try again.';

  @override
  String importErrorHttpStatus(int status) {
    return 'The server responded with HTTP $status.';
  }

  @override
  String get importErrorEmptyResponse => 'The URL returned an empty response.';

  @override
  String get importErrorCallersBoxEmptyInput =>
      'Enter a Caller\'s Box dance URL or id to import from.';

  @override
  String get importErrorCallersBoxInvalidUrl =>
      'That doesn\'t look like a Caller\'s Box dance URL or a numeric id.';

  @override
  String get importErrorCallersBoxMissingId =>
      'That Caller\'s Box URL is missing a dance id (…dance.php?id=N).';

  @override
  String get importErrorCallersBoxUnsupportedHost =>
      'That link isn\'t a supported Caller\'s Box link. Paste a link from ibiblio.org or www.ibiblio.org under /contradance/thecallersbox/, or enter the dance\'s numeric id.';

  @override
  String get importErrorCallersBoxEmptySearch =>
      'Enter a title or by-phrase figures to search The Caller\'s Box.';

  @override
  String importErrorSearchTimeout(int seconds) {
    return 'The search timed out after ${seconds}s. Check your connection, then try again.';
  }

  @override
  String get importErrorCallersBoxUnreachable =>
      'Couldn\'t reach The Caller\'s Box. Check your connection, then try again.';

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Box responded with HTTP $status.';
  }

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Box returned an empty page.';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Box returned no importable dance.';

  @override
  String get importErrorCallersBoxImportFailed =>
      'The Caller\'s Box dance couldn\'t be imported.';

  @override
  String get importErrorContraDbEmptyTitle =>
      'Enter a title to search ContraDB.';

  @override
  String get importErrorContraDbEmptyDanceInput =>
      'Enter a ContraDB dance URL or id to import from.';

  @override
  String get importErrorContraDbInvalidDanceUrl =>
      'That doesn\'t look like a ContraDB dance URL or a numeric id.';

  @override
  String get importErrorContraDbMissingDanceId =>
      'That ContraDB URL is missing a dance id (…/dances/N).';

  @override
  String get importErrorContraDbEmptyProgramInput =>
      'Enter a ContraDB program URL or id to import from.';

  @override
  String get importErrorContraDbInvalidProgramUrl =>
      'That doesn\'t look like a ContraDB program URL or a numeric id.';

  @override
  String get importErrorContraDbMissingProgramId =>
      'That ContraDB URL is missing a program id (…/programs/N).';

  @override
  String get importErrorContraDbInvalidProgramLink =>
      'That doesn\'t look like a ContraDB program link.';

  @override
  String get importErrorContraDbUnsupportedHost =>
      'That link isn\'t from a supported ContraDB host. Paste a link from contradb.com or www.contradb.com, or enter the dance\'s or program\'s numeric id.';

  @override
  String get importErrorContraDbUnreachable =>
      'Couldn\'t reach ContraDB. Check your connection, then try again.';

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDB responded with HTTP $status.';
  }

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDB returned an empty response.';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDB returned no importable dance.';

  @override
  String get importErrorContraDbImportFailed =>
      'The ContraDB dance couldn\'t be imported.';

  @override
  String get importIssueGeneric => 'This item was imported with a note.';

  @override
  String get importIssueProgramEmptySlot =>
      'Skipped an empty slot in a program.';

  @override
  String get importIssueProgramUnresolvedDance =>
      'A program referenced a dance that wasn\'t imported; kept the slot as a text placeholder.';

  @override
  String get importIssueProgramUnresolvedVenue =>
      'A program referenced a venue that wasn\'t imported; kept the program without a venue link.';

  @override
  String get importIssueArchiveReadError =>
      'An entry in the shared file couldn\'t be read and was skipped.';

  @override
  String get importIssueArchiveReadWarning =>
      'The shared file reported a warning while decoding.';

  @override
  String get importIssueDirectionUnmapped =>
      'A Becket direction wasn\'t recognized; defaulted to clockwise.';

  @override
  String get importIssueFormationUnclassified =>
      'A formation couldn\'t be recognized; kept as a detail on “other”.';

  @override
  String get importIssuePhraseStructureUnreadable =>
      'A phrase structure couldn\'t be read; a default structure was used.';

  @override
  String get importIssueProgressionUnmapped =>
      'A progression wasn\'t recognized; recorded as “other”.';

  @override
  String get importIssueMetadataOnlyStub =>
      'This dance is available as metadata only (no figures); imported as a stub.';

  @override
  String importIssueDateAssumedMdy(String field) {
    return 'An ambiguous $field date was read as month/day (US ordering); check it if the source used day-first ordering.';
  }

  @override
  String importIssueDateReducedPrecision(int year, String field) {
    return 'Only the year $year could be read from the $field date; no month or day was present.';
  }

  @override
  String get importIssueMissingTitle =>
      'The dance had no title; a placeholder title was used. Edit it before committing.';

  @override
  String get importIssueProgramUnparsedDate =>
      'An event date couldn\'t be read; left unset.';

  @override
  String get importIssueRatingOutOfRange =>
      'A rating was outside the 1–5 scale; left unrated.';

  @override
  String get importIssueUnmappedFormation =>
      'A formation wasn\'t recognized; preserved as free-text detail.';

  @override
  String get importIssueUnmappedLevel =>
      'A level wasn\'t recognized; left unspecified.';

  @override
  String get importIssueUnmappedProgression =>
      'A progression wasn\'t recognized; defaulted to single.';

  @override
  String get importIssueUnmappedType =>
      'A dance type wasn\'t recognized; imported as a contra and preserved in the notes.';

  @override
  String importIssueUnparsedDate(String field) {
    return 'The $field date couldn\'t be read; left unset.';
  }

  @override
  String get importIssueUnparsedRating =>
      'A rating couldn\'t be read; left unrated.';

  @override
  String get importIssueFiguresUnreadable =>
      'The figures couldn\'t be read; no figures were imported.';

  @override
  String get importIssueBeatsUnreadable =>
      'A beat count couldn\'t be read; used 0.';

  @override
  String get importIssueNoFiguresTable =>
      'The page had no figures; imported as a metadata-only stub.';

  @override
  String get importIssueMoveFallback =>
      'A figure couldn\'t be matched to a known move; imported as custom.';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'Figure $position couldn\'t be matched to a known move; imported as custom.';
  }

  @override
  String get importIssueParamUnmapped =>
      'A figure parameter couldn\'t be mapped; a taxonomy default was used.';

  @override
  String importIssueParamValueUnmapped(String param) {
    return 'The $param parameter couldn\'t be converted; a taxonomy default was used.';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'A figure had $provided parameter values but only $mapped are mapped; the extras were ignored.';
  }

  @override
  String get importIssueRelatedDanceUnresolved =>
      'A related-dance link pointed at a dance that wasn\'t imported; the link was skipped.';

  @override
  String get importDateFieldComposed => 'composed';

  @override
  String get importDateFieldRevised => 'revised';

  @override
  String get importRecordErrorDiscover => 'This record couldn\'t be found.';

  @override
  String get importRecordErrorFetch => 'This record couldn\'t be fetched.';

  @override
  String get importRecordErrorParse => 'This record couldn\'t be read.';

  @override
  String get importRecordErrorDedupe => 'This record couldn\'t be processed.';

  @override
  String get importRecordErrorCommit => 'This record couldn\'t be saved.';

  @override
  String get importReviewUsrSubtitle =>
      'Choose the Caller\'s Companion .USR file to migrate its dances and program history. Nothing is added to your collection until you review and confirm.';

  @override
  String get importReviewChooseUsr => 'Choose .USR file…';

  @override
  String importReviewFileReady(int bytes) {
    return 'File ready ($bytes bytes).';
  }

  @override
  String get importReviewGenericSubtitle =>
      'Choose a file, paste its contents, or fetch it from a URL. Nothing is added to your collection until you review and confirm.';

  @override
  String get importReviewChooseFile => 'Choose file…';

  @override
  String get importReviewUrlLabel => 'Dance URL or id';

  @override
  String get importReviewUrlLabelGeneric => 'Import from URL';

  @override
  String get importReviewUrlHint =>
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · or · 1';

  @override
  String get importReviewUrlHintGeneric => 'https://…';

  @override
  String get importReviewFetch => 'Fetch';

  @override
  String get importReviewPasteJson => 'Or paste JSON';

  @override
  String get importReviewReviewButton => 'Review import';

  @override
  String importReviewWillImport(int importable, int total) {
    return '$importable of $total will be imported';
  }

  @override
  String importReviewWillImportPrograms(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programs',
      one: '1 program',
    );
    return 'Also includes $_temp0.';
  }

  @override
  String get importReviewCouldNotRead => 'Couldn\'t read the import';

  @override
  String get importReviewNoDancesTitle => 'No dances found';

  @override
  String get importReviewNoDancesBody =>
      'The file did not contain any dances to import.';

  @override
  String get importReviewTryAnother => 'Try another file';

  @override
  String get importReviewImported => 'Imported';

  @override
  String importReviewStructured(int structured, int total) {
    return '$structured/$total structured';
  }

  @override
  String get importReviewCustom => 'Custom';

  @override
  String get importReviewOptionNewDance => 'New dance';

  @override
  String get importReviewOptionSkip => 'Skip';

  @override
  String importReviewOptionReimport(String title) {
    return 'Re-import onto \"$title\"';
  }

  @override
  String get importReviewOptionDuplicate => 'Import as a new (duplicate) dance';

  @override
  String get importReviewPossibleMatch =>
      'Possible match — choose how to import:';

  @override
  String importReviewOptionLink(String title, int percent) {
    return 'Link to \"$title\" ($percent% match)';
  }

  @override
  String importReviewOverwriteWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count existing dances will be overwritten',
      one: '1 existing dance will be overwritten',
    );
    return '$_temp0';
  }

  @override
  String importReviewWarningPrefix(String message) {
    return 'Warning: $message';
  }

  @override
  String get importReviewComplete => 'Import complete';

  @override
  String sharedImportSoftCapWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This import contains $count items — more than expected for a normal share.',
      one:
          'This import contains 1 item — more than expected for a normal share.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count items.',
      one: 'Imported 1 item.',
      zero: 'Import complete.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportProgramsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This share contains $count programs and no dances.',
      one: 'This share contains 1 program and no dances.',
    );
    return '$_temp0';
  }

  @override
  String importReviewSummaryCreated(int count) {
    return 'Created: $count';
  }

  @override
  String importReviewSummaryReimported(int count) {
    return 'Re-imported: $count';
  }

  @override
  String importReviewSummaryLinked(int count) {
    return 'Linked: $count';
  }

  @override
  String importReviewSummaryDuplicated(int count) {
    return 'Duplicated: $count';
  }

  @override
  String importReviewSummaryVariation(int count) {
    return 'Imported as a variation: $count';
  }

  @override
  String importReviewSummarySkipped(int count) {
    return 'Skipped: $count';
  }

  @override
  String importReviewSummaryPrograms(int count) {
    return 'Programs: $count';
  }

  @override
  String importReviewProgramsUpdated(int count) {
    return '$count updated (re-imported)';
  }

  @override
  String importReviewProgramNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count program note(s):',
      one: '$count program note(s):',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count record(s) failed to import:',
      one: '$count record(s) failed to import:',
    );
    return '$_temp0';
  }

  @override
  String importReviewBatchErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count record(s) couldn\'t be read (the rest can still be imported):',
      one:
          '$count record(s) couldn\'t be read (the rest can still be imported):',
    );
    return '$_temp0';
  }

  @override
  String get importReviewUntitledProgram => 'Untitled program';

  @override
  String get importReviewUndoWithPrograms =>
      'Undo (removes the imported dances and programs)';

  @override
  String get importReviewUndone => 'Import undone.';

  @override
  String get importReviewEditError => 'Couldn\'t import that dance to edit.';

  @override
  String get importReviewImportError => 'Couldn\'t complete the import.';

  @override
  String importReviewVariationTitle(String title) {
    return 'Variation of \"$title\"?';
  }

  @override
  String importReviewVariationBody(String title) {
    return 'This dance\'s title and caller match \"$title\", but its figures are different. Review how they differ, then choose how to import it.';
  }

  @override
  String importReviewOptionVariation(String title) {
    return 'Import as a variation of \"$title\"';
  }

  @override
  String importReviewOptionSameDance(String title) {
    return 'Same dance as \"$title\" (link/update)';
  }

  @override
  String importReviewOptionLinkBack(String title) {
    return 'Also link back to \"$title\" as a related dance';
  }

  @override
  String get importReviewVariationAdded => 'Added';

  @override
  String get importReviewVariationRemoved => 'Removed';

  @override
  String importReviewVariationMoreDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more differences not shown',
      one: '1 more difference not shown',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorDetailsSection => 'Details';

  @override
  String get danceEditorTitleRequiredLabel => 'Title *';

  @override
  String get danceEditorTitleRequired => 'Title is required';

  @override
  String get danceEditorAuthorsLabel => 'Authors';

  @override
  String get danceEditorFormationLabel => 'Formation';

  @override
  String get danceEditorFormationDetailLabel => 'Formation detail (optional)';

  @override
  String get danceEditorPhraseStructureLabel => 'Phrase structure';

  @override
  String get danceEditorPhraseStructureHint =>
      'Blank = standard A1 A2 B1 B2; else e.g. 6*8*2';

  @override
  String get danceEditorFiguresSection => 'Figures';

  @override
  String get danceEditorFiguresHelp =>
      'Type a move (e.g. \"sw\" → swing) and press Enter to add it with default params; unmatched text becomes a custom figure.';

  @override
  String get danceEditorNotesSection => 'Notes';

  @override
  String get danceEditorCallingNotesLabel => 'Calling notes';

  @override
  String get danceEditorHookLabel => 'Hook';

  @override
  String get danceEditorHookHint => 'One-line \"why call this\"';

  @override
  String get danceEditorWalkthroughLabel => 'Walkthrough';

  @override
  String get danceEditorWalkthroughHelper =>
      'Step-by-step description of the dance and its transitions';

  @override
  String get danceEditorAddWalkthroughStep => 'Add walkthrough step';

  @override
  String get danceEditorWalkthroughStepLabel => 'Walkthrough step (optional)';

  @override
  String get danceEditorWalkthroughStepHelper =>
      'Saved as your default for this figure and reused wherever it appears.';

  @override
  String get danceEditorSnippetDivergenceTitle => 'Update your saved snippet?';

  @override
  String get danceEditorSnippetDivergenceBody =>
      'This differs from the walkthrough snippet you saved for this figure. Use the new text everywhere, or just in this dance?';

  @override
  String get danceEditorSnippetUseEverywhere => 'Use everywhere';

  @override
  String get danceEditorSnippetJustThisDance => 'Just this dance';

  @override
  String get danceEditorFillWalkthroughFromSnippets => 'Fill from snippets';

  @override
  String get danceEditorFillWalkthroughReplaceTitle => 'Replace walkthrough?';

  @override
  String get danceEditorFillWalkthroughReplaceBody =>
      'This replaces the current walkthrough with text assembled from your figure snippets.';

  @override
  String get danceEditorFillWalkthroughReplaceConfirm => 'Replace';

  @override
  String get danceEditorFillWalkthroughEmpty =>
      'None of these figures have a saved walkthrough snippet yet.';

  @override
  String get settingsWalkthroughSnippetsTitle => 'Walkthrough snippets';

  @override
  String get settingsWalkthroughSnippetsSubtitle =>
      'Your saved per-figure step descriptions';

  @override
  String get settingsWalkthroughSnippetsHeader => 'Saved walkthrough snippets';

  @override
  String get settingsWalkthroughSnippetsDescription =>
      'These per-figure step descriptions pre-fill walkthroughs when you edit a dance. Editing one here updates the default used everywhere.';

  @override
  String get settingsWalkthroughSnippetsEmpty =>
      'No saved snippets yet. Add walkthrough step descriptions while editing a dance\'s figures.';

  @override
  String settingsWalkthroughSnippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
    );
    return '$_temp0';
  }

  @override
  String get settingsWalkthroughSnippetDeleteTitle => 'Delete snippet?';

  @override
  String get settingsWalkthroughSnippetDeleteBody =>
      'This removes the saved default for this figure. Dances keep any walkthrough text you already wrote.';

  @override
  String get settingsWalkthroughSnippetEditTitle => 'Edit snippet';

  @override
  String get danceEditorMoreDetailsTitle => 'More details';

  @override
  String get danceEditorStatusLabel => 'Status';

  @override
  String get danceEditorMixedLevelSubtitle => 'Spans the difficulty scale';

  @override
  String get danceEditorMixerSubtitle =>
      'Dancers change partners each time through';

  @override
  String get danceEditorComposedLabel => 'Composed';

  @override
  String get danceEditorComposedHelper =>
      'When the dance was composed (year, or add month/day)';

  @override
  String get danceEditorRevisedLabel => 'Revised';

  @override
  String get danceEditorRevisedHelper =>
      'When the dance was last revised by its author';

  @override
  String get danceEditorTagsLabel => 'Tags';

  @override
  String get danceEditorTunesLabel => 'Tunes';

  @override
  String get danceEditorLinksLabel => 'Links';

  @override
  String get danceEditorPublishedSourcesLabel => 'Published sources';

  @override
  String get danceEditorRelatedDancesLabel => 'Related dances';

  @override
  String get danceEditorCustomFieldsLabel => 'Custom fields';

  @override
  String get danceEditorRatingLabel => 'Rating';

  @override
  String get danceEditorRatingUnrated => 'unrated';

  @override
  String danceEditorRatingValue(int rating, int max) {
    return '$rating of $max stars';
  }

  @override
  String danceEditorSetRatingTooltip(int rating, int max) {
    return 'Set rating to $rating of $max stars';
  }

  @override
  String get danceEditorClearRating => 'Clear rating';

  @override
  String get danceEditorLevelLabel => 'Level';

  @override
  String get danceEditorLevelUnspecified => 'Unspecified';

  @override
  String get danceEditorYearLabel => 'Year';

  @override
  String get danceEditorYearHint => 'e.g. 1989';

  @override
  String get danceEditorYearRangeError => '1–9999';

  @override
  String get danceEditorMonthLabel => 'Month';

  @override
  String get danceEditorDayLabel => 'Day';

  @override
  String get danceEditorMonthJan => 'Jan';

  @override
  String get danceEditorMonthFeb => 'Feb';

  @override
  String get danceEditorMonthMar => 'Mar';

  @override
  String get danceEditorMonthApr => 'Apr';

  @override
  String get danceEditorMonthMay => 'May';

  @override
  String get danceEditorMonthJun => 'Jun';

  @override
  String get danceEditorMonthJul => 'Jul';

  @override
  String get danceEditorMonthAug => 'Aug';

  @override
  String get danceEditorMonthSep => 'Sep';

  @override
  String get danceEditorMonthOct => 'Oct';

  @override
  String get danceEditorMonthNov => 'Nov';

  @override
  String get danceEditorMonthDec => 'Dec';

  @override
  String get monthFullJanuary => 'January';

  @override
  String get monthFullFebruary => 'February';

  @override
  String get monthFullMarch => 'March';

  @override
  String get monthFullApril => 'April';

  @override
  String get monthFullMay => 'May';

  @override
  String get monthFullJune => 'June';

  @override
  String get monthFullJuly => 'July';

  @override
  String get monthFullAugust => 'August';

  @override
  String get monthFullSeptember => 'September';

  @override
  String get monthFullOctober => 'October';

  @override
  String get monthFullNovember => 'November';

  @override
  String get monthFullDecember => 'December';

  @override
  String get danceEditorAddTuneHint => 'Add a suggested tune…';

  @override
  String get danceEditorAddTuneTooltip => 'Add tune';

  @override
  String get danceEditorWarningsTitle => 'Warnings';

  @override
  String validationPhraseBeatMismatch(int actual, int expected) {
    return 'The figures total $actual beats; the phrase structure expects $expected.';
  }

  @override
  String get validationPhraseInvalid => 'That phrase structure isn\'t valid.';

  @override
  String validationOrphanedAlt(int position) {
    return 'The alternate at position $position has no preceding primary slot.';
  }

  @override
  String validationOrphanedAltNamed(int position, String text) {
    return 'The alternate at position $position (“$text”) has no preceding primary slot.';
  }

  @override
  String validationEmptySubstitution(String term) {
    return 'The substitution for “$term” is empty.';
  }

  @override
  String validationDialectCollision(
    String source,
    String existing,
    String substitution,
  ) {
    return '“$source” and “$existing” both map to “$substitution” — reversal would be ambiguous.';
  }

  @override
  String get validationGeneric => 'This item has a validation issue.';

  @override
  String danceEditorDiscouragedTermSemantic(String term) {
    return 'Discouraged term: $term';
  }

  @override
  String danceEditorDiscouragedTermText(String term) {
    return 'Discouraged: $term';
  }

  @override
  String get danceEditorLinkKindSource => 'Source';

  @override
  String get danceEditorLinkKindVideo => 'Video';

  @override
  String get danceEditorLinkKindOther => 'Other';

  @override
  String get danceEditorUrlLabel => 'URL';

  @override
  String get danceEditorLabelOptional => 'Label (optional)';

  @override
  String get danceEditorRemoveLinkTooltip => 'Remove link';

  @override
  String get danceEditorAddLink => 'Add link';

  @override
  String get danceEditorMissingDance => '(missing dance)';

  @override
  String get danceEditorNoteOptionalLabel => 'Note (optional)';

  @override
  String get danceEditorRemoveRelatedDanceTooltip => 'Remove related dance';

  @override
  String get danceEditorAddRelatedDance => 'Add related dance';

  @override
  String get danceEditorRelatedDanceLabel => 'Related dance';

  @override
  String get danceEditorTypeToSearchHint => 'Type to search…';

  @override
  String danceEditorEditItemTooltip(String item) {
    return 'Edit $item';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint => 'Type to add or create…';

  @override
  String danceEditorCreateQuotedName(String name) {
    return 'Create \"$name\"';
  }

  @override
  String get danceEditorUnknownSource => '(unknown source)';

  @override
  String get danceEditorPageOptionalLabel => 'Page (optional)';

  @override
  String get danceEditorNumberOptionalLabel => 'Number (optional)';

  @override
  String get danceEditorCiteSourceHint =>
      'Cite a source: type to add or create…';

  @override
  String get danceEditorSaveError => 'Couldn\'t save the dance.';

  @override
  String get danceEditorFallbackDanceTitle => 'Dance';

  @override
  String get danceEditorUnsavedDraftTitle => 'Unsaved draft';

  @override
  String get danceEditorUnsavedDraftMessage =>
      'You have an unsaved draft for this dance. Would you like to restore it?';

  @override
  String get danceEditorDiscard => 'Discard';

  @override
  String get danceEditorRestore => 'Restore';

  @override
  String get danceEditorDiscardChangesTitle => 'Discard changes?';

  @override
  String get danceEditorDiscardChangesMessage =>
      'You have unsaved changes to this dance.';

  @override
  String get danceEditorKeepEditing => 'Keep editing';

  @override
  String get danceEditorNewDanceTitle => 'New dance';

  @override
  String get danceEditorEditDanceTitle => 'Edit dance';

  @override
  String get danceEditorRedoLabel => 'Redo';

  @override
  String get danceEditorUndoShortcutTooltip => 'Undo (Ctrl+Z)';

  @override
  String get danceEditorRedoShortcutTooltip => 'Redo (Ctrl+Shift+Z)';

  @override
  String get danceEditorDeleteDanceTooltip => 'Delete dance';

  @override
  String get danceEditorLoadError => 'Could not load the dance.';

  @override
  String get danceEditorChoreographerDetailsTitle => 'Choreographer details';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'These details are shared across every dance credited to this author. Email and location are private — stored only on this device and never shared or exported.';

  @override
  String get danceEditorNameRequiredLabel => 'Name *';

  @override
  String get danceEditorNameRequired => 'Name is required';

  @override
  String get danceEditorWebsiteLabel => 'Website';

  @override
  String get danceEditorEmailPrivateLabel => 'Email (private)';

  @override
  String get danceEditorLocationPrivateLabel => 'Location (private)';

  @override
  String get danceEditorNotesLabel => 'Notes';

  @override
  String get danceEditorDeceasedLabel => 'Deceased';

  @override
  String get danceEditorSourceDetailsTitle => 'Source details';

  @override
  String get danceEditorSourceDetailsIntro =>
      'These details are shared across every dance that cites this source. Editing them here updates the source everywhere it is referenced.';

  @override
  String get danceEditorSourceAuthorEditorLabel => 'Author / editor';

  @override
  String get danceEditorEnterWholeNumber => 'Enter a whole number';

  @override
  String get danceEditorEnterPositiveYear => 'Enter a positive year';

  @override
  String danceEditorAddedFigureChooseMove(int count) {
    return 'Added figure $count. Choose a move.';
  }

  @override
  String danceEditorFigurePastedAnnouncement(int position) {
    return 'Figure pasted at position $position.';
  }

  @override
  String danceEditorFigureMovedAnnouncement(int position, int total) {
    return 'Moved to position $position of $total.';
  }

  @override
  String danceEditorEditingFigureAnnouncement(int position, String name) {
    return 'Editing figure $position, $name.';
  }

  @override
  String danceEditorCollapsedFigureAnnouncement(int position) {
    return 'Collapsed figure $position.';
  }

  @override
  String get danceEditorTypeFigureAnnouncement =>
      'Type a figure and press Enter to add it.';

  @override
  String danceEditorFreeTextFiguresAddedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count figures. Type another, or press Escape to finish.',
      one: 'Added 1 figure. Type another, or press Escape to finish.',
    );
    return '$_temp0';
  }

  @override
  String danceEditorDeletedFigureAnnouncement(int position) {
    return 'Deleted figure $position. Undo available.';
  }

  @override
  String danceEditorDuplicatedFigureAnnouncement(int position) {
    return 'Duplicated figure $position.';
  }

  @override
  String get danceEditorAddFirstFigure => 'Add first figure';

  @override
  String danceEditorCutBanner(String figure) {
    return '\"$figure\" is cut — tap Paste to place it.';
  }

  @override
  String get danceEditorPasteBeforeFirstFigure => 'Paste before first figure';

  @override
  String danceEditorPasteAfterFigure(String figure) {
    return 'Paste after $figure';
  }

  @override
  String get danceEditorAddFigure => 'Add figure';

  @override
  String get danceEditorPasteAtEndOfFigureList => 'Paste at end of figure list';

  @override
  String get danceEditorTypeFigureLabel => 'Type a figure';

  @override
  String get danceEditorTypeFigureHelper =>
      'e.g. \"neighbor balance & swing\" or \"16 circle left 3/4\". Enter adds it; unrecognized text is kept as a custom figure.';

  @override
  String get danceEditorPasteHere => 'Paste here';

  @override
  String get danceEditorEmptyFigureName => 'Empty figure';

  @override
  String get danceEditorCustomFigureName => 'Custom figure';

  @override
  String get danceEditorEmptyFigureSummary => '(empty — choose a move)';

  @override
  String get danceEditorEmptyFigureSemantic => 'empty figure, choose a move';

  @override
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
  ) {
    String _temp0 = intl.Intl.selectLogic(importGap, {
      'yes': ', $importGapText',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(progression, {
      'yes': ', progression',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats beats',
      one: '1 beat',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': ', $_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': ', note: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1$_temp3$_temp4. Figure $position of $total.';
  }

  @override
  String get danceEditorActivateToEditHint => 'Activate to edit';

  @override
  String danceEditorDragToReorderFigure(String figure) {
    return 'Drag to reorder $figure';
  }

  @override
  String danceEditorFigureActionsTooltip(String figure) {
    return 'Actions for $figure';
  }

  @override
  String get danceEditorMoveUp => 'Move up';

  @override
  String get danceEditorMoveDown => 'Move down';

  @override
  String get danceEditorCut => 'Cut';

  @override
  String get danceEditorClearProgression => 'Clear progression';

  @override
  String get danceEditorMarkProgression => 'Mark progression';

  @override
  String get danceEditorGroupWithNext => 'Group with next as meanwhile';

  @override
  String danceEditorMeanwhileGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Meanwhile ($count sides)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorMeanwhileGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count concurrent figures',
      one: '1 concurrent figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats shared beats',
      one: '1 shared beat',
    );
    return 'Meanwhile group, $_temp0, $_temp1.';
  }

  @override
  String danceEditorMeanwhileSideLabel(int number) {
    return 'Side $number';
  }

  @override
  String danceEditorMeanwhileSideSemantic(int number, int total) {
    return 'Side $number of $total.';
  }

  @override
  String get danceEditorAddMeanwhileSide => 'Add side';

  @override
  String get danceEditorRemoveMeanwhileSide => 'Remove this side';

  @override
  String danceEditorMeanwhileSidesCapReached(int max) {
    return 'Maximum of $max concurrent figures.';
  }

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return 'Unrecognized move \"$move\" — not in this version\'s taxonomy. Shown read-only so its data is preserved; it will edit normally again if the move becomes known. You can still reorder or delete it.';
  }

  @override
  String get danceEditorFewerOptions => 'Fewer options';

  @override
  String danceEditorMoreOptions(int count) {
    return 'More options ($count)';
  }

  @override
  String get danceEditorAddNote => 'Add note';

  @override
  String get danceEditorBoldTooltip => 'Bold (*text*)';

  @override
  String get danceEditorUnderlineTooltip => 'Underline (_text_)';

  @override
  String get danceEditorCustomFigureTextLabel => 'Custom figure text';

  @override
  String get danceEditorLingoStylingHelper =>
      'Move names dotted·underline, role terms underlined, discouraged terms struck through';

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return 'Total: $total / $expected beats';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return 'Over by $beats beats';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return 'Under by $beats beats';
  }

  @override
  String get danceEditorLessTooltip => 'Less';

  @override
  String get danceEditorParamNotStated => 'not stated';

  @override
  String get danceEditorParamClearTooltip => 'Clear (not stated)';

  @override
  String get danceEditorMoreTooltip => 'More';

  @override
  String danceEditorTurnCount(num count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted turns',
      one: '$formatted turn',
    );
    return '$_temp0';
  }

  @override
  String get commonBack => 'Back';

  @override
  String get commonRemove => 'Remove';

  @override
  String updateBannerDownloading(String appName, String version) {
    return 'Downloading $appName $version…';
  }

  @override
  String updateBannerDownloadingPct(String appName, String version, int pct) {
    return 'Downloading $appName $version… $pct%';
  }

  @override
  String updateBannerVerifying(String appName, String version) {
    return 'Verifying $appName $version…';
  }

  @override
  String get updateBannerPreparingInstaller => 'Preparing the installer…';

  @override
  String updateBannerCompletedRevealed(String appName, String version) {
    return '$appName $version downloaded and verified — we revealed the installer in your file manager. Run it to finish updating.';
  }

  @override
  String updateBannerCompletedManual(String appName, String version) {
    return '$appName $version downloaded — follow the installer to finish updating.';
  }

  @override
  String get updateBannerDownloadFailed =>
      'The update could not be downloaded.';

  @override
  String updateBannerAvailable(String appName, String version) {
    return 'A newer version of $appName ($version) is available.';
  }

  @override
  String get updateBannerViewRelease => 'View release';

  @override
  String get updateBannerDismiss => 'Dismiss';

  @override
  String get updateBannerDownloadInstall => 'Download & install';

  @override
  String get commandPaletteBarrierLabel => 'Global search';

  @override
  String get commandPaletteSearchHint => 'Search dances and programs…';

  @override
  String get commandPaletteProgramSubtitle => 'Program';

  @override
  String get commandPaletteEmptyInitial => 'Nothing to search yet.';

  @override
  String get commandPaletteNoMatches => 'No matches for that search.';

  @override
  String get commandPaletteGroupDances => 'Dances';

  @override
  String get commandPaletteGroupPrograms => 'Programs';

  @override
  String get collectionPickerSearchLabel => 'Find a dance to add';

  @override
  String collectionPickerFilters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filters ($count active)',
      zero: 'Filters',
    );
    return '$_temp0';
  }

  @override
  String collectionPickerByPhrase(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'By phrase ($count active)',
      zero: 'By phrase',
    );
    return '$_temp0';
  }

  @override
  String get collectionPickerAdvanced => 'Advanced';

  @override
  String get collectionPickerUseAdvancedQuery => 'Use advanced query';

  @override
  String get collectionPickerAdvancedQueryHelp =>
      'Combine figures and sequences with all / any / none groups.';

  @override
  String collectionPickerAddSemantic(String title) {
    return 'Add $title to program';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return 'Add $title';
  }

  @override
  String collectionPickerAddedTooltip(String title) {
    return 'Added $title';
  }

  @override
  String collectionPickerInProgramSemantic(String title) {
    return '$title is already in the program';
  }

  @override
  String collectionPickerInProgramCountSemantic(String title, int count) {
    return '$title is in the program $count times';
  }

  @override
  String get userGuideTitle => 'User guide';

  @override
  String userGuideMissing(String label) {
    return 'The \"$label\" guide isn\'t available yet.';
  }

  @override
  String get userGuideLoadError => 'The user guide could not be loaded.';

  @override
  String get userGuideOpenOnline => 'Open the guide online';

  @override
  String get shorthandMappingsTitle => 'Figure shorthands';

  @override
  String get shorthandMappingsIntro =>
      'Shorthands let you type a short token during free-text entry and have it expand to one or more figures you have set up here.';

  @override
  String get shorthandMappingsNew => 'New shorthand';

  @override
  String get shorthandMappingsEmpty => 'No shorthands yet.';

  @override
  String get shorthandMappingsDeleteTitle => 'Delete shorthand?';

  @override
  String shorthandMappingsDeleteBody(String token) {
    return '“$token” will be permanently removed.';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'Shorthand actions';

  @override
  String get shorthandEditorTitleNew => 'New shorthand';

  @override
  String get shorthandEditorTitleEdit => 'Edit shorthand';

  @override
  String get shorthandEditorTokenLabel => 'Shorthand';

  @override
  String get shorthandEditorTokenHelper =>
      'Type this exact line during free-text entry to insert the figures below. Matched case-insensitively.';

  @override
  String get shorthandEditorExpandsTo => 'Expands to';

  @override
  String get shorthandEditorExpandsToHelp =>
      'The figure(s) this shorthand inserts, in order. Built exactly like a normal figure, so parameters and validation are the same.';

  @override
  String get shorthandEditorErrorEmpty => 'Enter a shorthand token.';

  @override
  String shorthandEditorErrorTooLong(int max) {
    return 'Shorthand is too long (max $max characters).';
  }

  @override
  String shorthandEditorErrorDuplicate(String token) {
    return 'Another shorthand already uses \"$token\" (shorthands are matched case-insensitively).';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'Add at least one figure for this shorthand to expand to.';

  @override
  String get importShorthandSeedTitle => 'Seed figure shorthands';

  @override
  String get importShorthandSeedIntro =>
      'Your Caller\'s Companion file\'s call buttons can become figure shorthands. Pick the ones you want; each expands to the figures shown. Nothing is added until you confirm, and your existing shorthands are never overwritten.';

  @override
  String get importShorthandSeedAvailableHeader => 'From your call buttons';

  @override
  String get importShorthandSeedUsePrimary => 'Primary';

  @override
  String get importShorthandSeedUseAlt => 'Alternate';

  @override
  String get importShorthandSeedConflictHeader => 'Already defined — skipped';

  @override
  String importShorthandSeedConflictNote(String token) {
    return 'A shorthand named “$token” already exists, so this button was left as-is.';
  }

  @override
  String get importShorthandSeedSkip => 'Skip';

  @override
  String importShorthandSeedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seed $count shorthands',
      one: 'Seed 1 shorthand',
      zero: 'Seed shorthands',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seeded $count shorthands',
      one: 'Seeded 1 shorthand',
    );
    return '$_temp0';
  }

  @override
  String get themeEditorTitle => 'Edit theme';

  @override
  String get themeEditorNameLabel => 'Theme name';

  @override
  String get themeEditorContrastAllPass =>
      'All checked pairs pass WCAG AA contrast.';

  @override
  String themeEditorContrastFailing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count contrast pairs below WCAG AA. You can still save, but some text may be hard to read.',
      one:
          '1 contrast pair below WCAG AA. You can still save, but some text may be hard to read.',
    );
    return '$_temp0';
  }

  @override
  String themeEditorRatioPass(String ratio) {
    return '$ratio:1 AA';
  }

  @override
  String themeEditorRatioFail(String ratio) {
    return '$ratio:1 fail';
  }

  @override
  String get themeEditorPreviewHeading => 'Aa Preview';

  @override
  String get themeEditorBodySample => 'Body text sample';

  @override
  String get themeEditorSwatchPrimary => 'Primary';

  @override
  String get themeEditorSwatchSecondary => 'Secondary';

  @override
  String get themeEditorSwatchTertiary => 'Tertiary';

  @override
  String get themeEditorSwatchError => 'Error';

  @override
  String get reparseConfirmTitle => 'Upgrade custom figures?';

  @override
  String reparseConfirmBody(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figures',
      one: '1 figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dances',
      one: '1 dance',
    );
    return 'This will re-parse $_temp0 in $_temp1. Your tags, ratings, notes, and everything else on each dance are kept exactly as they are. This only replaces figures that now recognise a known move.';
  }

  @override
  String get reparseConfirmUpgrade => 'Upgrade';

  @override
  String get reparseFailed => 'Could not upgrade figures. Please try again.';

  @override
  String get reparseNothingUpgradedSnack => 'Nothing to upgrade.';

  @override
  String reparseUpgradedSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dances',
      one: '1 dance',
    );
    return 'Upgraded custom figures in $_temp0.';
  }

  @override
  String get reparseScreenTitle => 'Re-check custom figures';

  @override
  String reparseIntro(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figures',
      one: '1 figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dances',
      one: '1 dance',
    );
    return 'Improved figure parsing can upgrade $_temp0 in $_temp1. Review below, then confirm — nothing changes until you do, and all your tags, ratings, and notes are preserved.';
  }

  @override
  String reparsePreviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figures',
      one: '1 figure',
    );
    return '$_temp0 to upgrade';
  }

  @override
  String reparseUpgradeButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dances',
      one: '1 dance',
    );
    return 'Upgrade $_temp0';
  }

  @override
  String get reparseEmptyTitle => 'Nothing to upgrade';

  @override
  String get reparseEmptyBody =>
      'None of your custom figures from imports can be recognised as a known move right now. Check back after a future update improves figure parsing.';

  @override
  String get reparseErrorTitle => 'Could not check your figures';

  @override
  String get reparseErrorBody =>
      'Something went wrong while scanning your collection. Nothing was changed. You can try again.';

  @override
  String get customFieldsDeleteTitle => 'Delete custom field';

  @override
  String customFieldsDeleteBody(String label) {
    return 'Delete \"$label\"? This cannot be undone.';
  }

  @override
  String customFieldsDeleteInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dances',
      one: '1 dance',
    );
    return 'Can\'t delete \"$label\": still used by $_temp0. Remove the value from all dances first.';
  }

  @override
  String customFieldsDeleteInUseUnknown(String label) {
    return 'Can\'t delete \"$label\": still used by some dances. Remove the value from all dances first.';
  }

  @override
  String get customFieldsTitle => 'Custom fields';

  @override
  String get customFieldsNewField => 'New field';

  @override
  String get customFieldsLoadError => 'Could not load custom fields.';

  @override
  String get customFieldsEmpty => 'No custom fields yet.\nTap + to define one.';

  @override
  String get customFieldsFlagInList => 'In list';

  @override
  String get customFieldsSearchable => 'Searchable';

  @override
  String get customFieldsTypeText => 'Text';

  @override
  String get customFieldsTypeNumber => 'Number';

  @override
  String get customFieldsTypeBoolean => 'Boolean';

  @override
  String get customFieldsTypeChoice => 'Choice';

  @override
  String get customFieldsValidatorMinChoice => 'Add at least one choice';

  @override
  String customFieldsRemoveValueError(String value) {
    return 'Can\'t remove \"$value\": it\'s set on at least one dance.';
  }

  @override
  String get customFieldsEditorNewTitle => 'New custom field';

  @override
  String get customFieldsEditorEditTitle => 'Edit custom field';

  @override
  String get customFieldsLabelLabel => 'Label *';

  @override
  String get customFieldsLabelRequired => 'Label is required';

  @override
  String get customFieldsKeyLabel => 'Key *';

  @override
  String get customFieldsKeyHelper =>
      'Stable machine key (letters, digits, underscores; must start with a letter or underscore)';

  @override
  String get customFieldsKeyLocked =>
      'Key is locked — field is in use on dances';

  @override
  String get customFieldsKeyRequired => 'Key is required';

  @override
  String get customFieldsKeyInvalid =>
      'Key must start with a letter or underscore and contain only letters, digits, and underscores';

  @override
  String get customFieldsTypeFieldLabel => 'Type';

  @override
  String get customFieldsTypeLocked =>
      'Type is locked — field has values on dances';

  @override
  String get customFieldsShowInList => 'Show in list';

  @override
  String get customFieldsShowInListSubtitle =>
      'Display this field value in the dance list tile';

  @override
  String get customFieldsSearchableSubtitle =>
      'Expose this field as a filter in the search panel';

  @override
  String get customFieldsChoicesLabel => 'Choices *';

  @override
  String get customFieldsChoiceInUseTooltip => 'In use — cannot remove';

  @override
  String get customFieldsNewChoiceHint => 'New choice…';

  @override
  String get customFieldsAddChoiceTooltip => 'Add choice';

  @override
  String get customFieldsChoiceDuplicate => 'That option already exists.';

  @override
  String get customFieldsChoiceEmpty => 'Enter an option.';

  @override
  String customFieldsAddOptionTooltip(String label) {
    return 'Add an option to $label';
  }

  @override
  String customFieldsAddOptionTitle(String label) {
    return 'Add an option to $label';
  }

  @override
  String get customFieldsShareable => 'Include in sharing';

  @override
  String get customFieldsShareableSubtitle =>
      'This field\'s values travel with your collection when you export or share it';

  @override
  String get customFieldsSharingNoticeTitle =>
      'Custom fields travel with your collection';

  @override
  String get customFieldsSharingNoticeBody =>
      'The contents of any custom field you create are included when you export or share your collection. To keep a field private, turn off \"Include in sharing\" in that field\'s settings.';

  @override
  String get customFieldsSharingNoticeOk => 'Got it';

  @override
  String dialectEditorTitle(String name) {
    return 'Edit $name';
  }

  @override
  String get dialectEditorSectionRoleTerms => 'Role terms';

  @override
  String get dialectEditorSectionMoveSubs => 'Move substitutions';

  @override
  String get dialectEditorSectionDancerSubs => 'Dancer substitutions';

  @override
  String get dialectEditorSectionDiscouraged => 'Discouraged terms';

  @override
  String get dialectEditorSectionPreview => 'Preview';

  @override
  String get dialectEditorRole1 => 'Role 1';

  @override
  String get dialectEditorRole2 => 'Role 2';

  @override
  String get dialectEditorRolesHelp =>
      'Leave a role blank to use the canonical term. Plural is derived when omitted.';

  @override
  String get dialectEditorSingular => 'Singular';

  @override
  String get dialectEditorPlural => 'Plural';

  @override
  String get dialectEditorMoveSubsAdd => 'Add move substitutions';

  @override
  String dialectEditorMoveSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count move substitutions',
      one: '1 move substitution',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorMoveSubHint => 'substitution (use %S for handedness)';

  @override
  String get dialectEditorAddMove => 'Add a move…';

  @override
  String get dialectEditorDancerSubsAdd => 'Add dancer substitutions';

  @override
  String dialectEditorDancerSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dancer substitutions',
      one: '1 dancer substitution',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorDancerSubHint => 'substitution';

  @override
  String get dialectEditorAddDancerTerm => 'Add a dancer term…';

  @override
  String get dialectEditorDiscouragedHelp =>
      'Terms the entry editor flags (struck through) — never blocked.';

  @override
  String get dialectEditorDiscouragedEmpty => 'No discouraged terms.';

  @override
  String get dialectEditorAddTermLabel => 'Add a term';

  @override
  String get dialectEditorAddTermTooltip => 'Add term';

  @override
  String get dialectEditorRestoreDefaults => 'Restore defaults';

  @override
  String get dialectEditorPreviewHelp =>
      'Sample figures rendered with this dialect. Updates as you edit.';

  @override
  String get recentlyDeletedTitle => 'Recently Deleted';

  @override
  String get recentlyDeletedDeleteTitle => 'Delete permanently?';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '\"$title\" will be deleted immediately and cannot be recovered.';
  }

  @override
  String get recentlyDeletedDeleteConfirm => 'Delete permanently';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '\"$title\" permanently deleted.';
  }

  @override
  String get recentlyDeletedRestore => 'Restore';

  @override
  String get recentlyDeletedPurgeKept => 'Kept until you delete it';

  @override
  String recentlyDeletedPurgeCountdown(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return 'Auto-deleted in $_temp0';
  }

  @override
  String get recentlyDeletedPurgeScheduled => 'Scheduled for deletion';

  @override
  String get recentlyDeletedLoadingDances => 'Loading recently deleted dances';

  @override
  String get recentlyDeletedLoadingPrograms =>
      'Loading recently deleted programs';

  @override
  String get recentlyDeletedEmptyDancesKept =>
      'Nothing in the trash. Deleted dances are kept here until you remove them.';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'Nothing in the trash. Deleted dances appear here for $days days before being removed.';
  }

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'Nothing in the trash. Deleted programs appear here for $days days before being removed.';
  }

  @override
  String recentlyDeletedRestoredDance(String title) {
    return '\"$title\" restored to your collection.';
  }

  @override
  String recentlyDeletedRestoredProgram(String title) {
    return '\"$title\" restored.';
  }

  @override
  String get venueNew => 'New venue';

  @override
  String get venueLoadError => 'Could not load venues.';

  @override
  String get venueManagerTitle => 'Venues';

  @override
  String get venueManagerSearchHint => 'Search venues…';

  @override
  String get venueManagerClearSearchTooltip => 'Clear search';

  @override
  String get venueManagerEmpty =>
      'No venues yet. Add one with the button below, or from a program when reusable venues are turned on.';

  @override
  String get venueManagerNoMatches => 'No venues match your search.';

  @override
  String get venueManagerDeleteTitle => 'Delete venue?';

  @override
  String venueManagerDeleteBody(String name) {
    return 'Permanently delete “$name”? This can’t be undone.';
  }

  @override
  String venueManagerDeletedSnack(String name) {
    return 'Deleted “$name”';
  }

  @override
  String venueManagerDeleteBlocked(String name) {
    return 'Can’t delete “$name” while it’s still linked to a program. Change or remove its venue on those programs first.';
  }

  @override
  String venueManagerDeleteTooltip(String name) {
    return 'Delete $name';
  }

  @override
  String get venueEditTitle => 'Edit venue';

  @override
  String get venueEditorSharedNote =>
      'A venue is shared across every program held here, so edits to its address, contacts, or schedule show up on all of them.';

  @override
  String get venueEditorNameLabel => 'Name *';

  @override
  String get venueEditorNameRequired => 'Name is required';

  @override
  String get venueEditorWebsiteLabel => 'Website';

  @override
  String get venueEditorSponsorLabel => 'Sponsor / hosting organization';

  @override
  String get venueEditorAddressSection => 'Address';

  @override
  String get venueEditorAddress1Label => 'Address line 1';

  @override
  String get venueEditorAddress2Label => 'Address line 2';

  @override
  String get venueEditorCityLabel => 'City';

  @override
  String get venueEditorStateLabel => 'State / province';

  @override
  String get venueEditorCountryLabel => 'Country';

  @override
  String get venueEditorPostalLabel => 'Postal / ZIP code';

  @override
  String get venueEditorPlus4Label => 'ZIP+4';

  @override
  String get venueEditorScheduleSection => 'Schedule';

  @override
  String get venueEditorEventNameLabel => 'Event name';

  @override
  String get venueEditorTimeLabel => 'Time';

  @override
  String get venueEditorScheduleLabel => 'Schedule (e.g. “2nd Saturdays”)';

  @override
  String get venueEditorPriceLabel => 'Price';

  @override
  String get venueEditorContactsSection => 'Contacts';

  @override
  String get venueEditorContact1NameLabel => 'Contact 1 name';

  @override
  String get venueEditorContact1PhoneLabel => 'Contact 1 phone';

  @override
  String get venueEditorContact1EmailLabel => 'Contact 1 email';

  @override
  String get venueEditorContact2NameLabel => 'Contact 2 name';

  @override
  String get venueEditorContact2PhoneLabel => 'Contact 2 phone';

  @override
  String get venueEditorContact2EmailLabel => 'Contact 2 email';

  @override
  String get venueEditorNotesSection => 'Notes';

  @override
  String get venuePickerLoading => 'Loading venues…';

  @override
  String get venuePickerUnlinkTooltip => 'Unlink venue';

  @override
  String get venuePickerUnresolvedTitle => 'Linked venue not found';

  @override
  String get venuePickerUnresolvedSubtitle => 'It may have been deleted.';

  @override
  String get venuePickerClearLinkTooltip => 'Clear link';

  @override
  String get venuePickerSearchHint => 'Search or add a venue…';

  @override
  String get venuePickerChangeHint => 'Change venue…';

  @override
  String venuePickerCreateOption(String name) {
    return 'Add new venue “$name”';
  }
}
