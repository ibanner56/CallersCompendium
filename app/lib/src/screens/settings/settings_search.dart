import 'package:flutter/foundation.dart';

import '../../../l10n/app_localizations.dart';
import 'settings_section.dart';

/// One row of [settingsSearchIndex]: a setting the user can find by name.
///
/// [label] is the row's own title, resolved from the ARB at search time so the
/// index needs no rebuild when the UI language changes. [keywords] are extra
/// lowercase English terms a user might type for this setting ("dark mode" for
/// the theme gallery); they supplement the localized label, which is what the
/// app actually shows.
@immutable
class SettingsSearchEntry {
  const SettingsSearchEntry(
    this.id,
    this.section,
    this.label, {
    this.keywords = const [],
  });

  /// Stable identifier for keys, tests and the index's own coverage check.
  final String id;

  /// The section that shows this setting.
  final SettingsSection section;

  /// The row's localized title.
  final String Function(AppLocalizations l10n) label;

  /// Extra lowercase English search terms.
  final List<String> keywords;
}

/// Every setting row Settings shows, for [searchSettings].
///
/// The index duplicates each row's title on purpose: the sections are
/// independent widgets that build only when selected (and, on the narrow
/// layout, not at all once a section page is pushed), so there is nothing
/// mounted to scan. Keeping it exhaustive is a test obligation —
/// `settings_search_test.dart` fails when a section has no entries.
///
/// Order is section order, then source order within a section, which is also
/// the order results appear in.
final List<SettingsSearchEntry> settingsSearchIndex = [
  // General
  SettingsSearchEntry(
    'general.sortIgnoreArticles',
    SettingsSection.general,
    (l) => l.settingsGeneralSortIgnoreArticlesTitle,
    keywords: ['sorting', 'alphabetical', 'articles'],
  ),
  SettingsSearchEntry(
    'general.capitalizeFigures',
    SettingsSection.general,
    (l) => l.settingsGeneralCapitalizeFiguresTitle,
    keywords: ['uppercase', 'capitalization'],
  ),
  SettingsSearchEntry(
    'general.tags',
    SettingsSection.general,
    (l) => l.settingsGeneralLibraryTagsTitle,
    keywords: ['labels', 'categories'],
  ),
  SettingsSearchEntry(
    'general.authors',
    SettingsSection.general,
    (l) => l.settingsGeneralLibraryAuthorsTitle,
    keywords: ['choreographers', 'creators'],
  ),
  SettingsSearchEntry(
    'general.sources',
    SettingsSection.general,
    (l) => l.settingsGeneralLibrarySourcesTitle,
    keywords: ['publications', 'citations'],
  ),
  SettingsSearchEntry(
    'general.reduceMotion',
    SettingsSection.general,
    (l) => l.settingsGeneralReduceMotionTitle,
    keywords: ['animations', 'motion', 'accessibility'],
  ),
  SettingsSearchEntry(
    'general.verboseFigures',
    SettingsSection.general,
    (l) => l.settingsGeneralVerboseFiguresTitle,
    keywords: ['spoken text', 'wording'],
  ),
  SettingsSearchEntry(
    'general.decimalTurns',
    SettingsSection.general,
    (l) => l.settingsGeneralDecimalTurnsTitle,
    keywords: ['fractions', 'turns', 'rotation'],
  ),
  SettingsSearchEntry(
    'general.confirmBeforeDelete',
    SettingsSection.general,
    (l) => l.settingsGeneralConfirmBeforeDeleteTitle,
    keywords: ['delete prompt', 'confirmation'],
  ),
  SettingsSearchEntry(
    'general.deletedItemsRetention',
    SettingsSection.general,
    (l) => l.settingsGeneralSoftDeleteRetentionTitle,
    keywords: ['trash', 'purge', 'days kept'],
  ),
  SettingsSearchEntry(
    'general.importDances',
    SettingsSection.general,
    (l) => l.importDances,
    keywords: ['import', 'bring in', 'json'],
  ),
  SettingsSearchEntry(
    'general.importEllipsis',
    SettingsSection.general,
    (l) => l.settingsGeneralImportEllipsisAction,
    keywords: ['import', 'add dances'],
  ),
  SettingsSearchEntry(
    'general.publishedCollections',
    SettingsSection.general,
    (l) => l.publishedCollectionsTitle,
    keywords: ['catalog', 'collections', 'download'],
  ),
  SettingsSearchEntry(
    'general.reparseCustomFigures',
    SettingsSection.general,
    (l) => l.settingsGeneralReparseCustomFiguresTitle,
    keywords: ['reparse', 'unrecognized figures', 'upgrade'],
  ),
  SettingsSearchEntry(
    'general.exportBackup',
    SettingsSection.general,
    (l) => l.backupExportTitle,
    keywords: ['save', 'backup file'],
  ),
  SettingsSearchEntry(
    'general.restoreBackup',
    SettingsSection.general,
    (l) => l.backupRestoreTitle,
    keywords: ['restore', 'replace data', 'load backup'],
  ),
  SettingsSearchEntry(
    'general.backupReminder',
    SettingsSection.general,
    (l) => l.backupReminderTitle,
    keywords: ['reminder', 'cadence'],
  ),

  // Appearance
  SettingsSearchEntry(
    'appearance.theme',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceThemeHeader,
    keywords: ['theme', 'colour', 'dark mode', 'light'],
  ),
  SettingsSearchEntry(
    'appearance.customThemes',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceCustomThemesHeader,
    keywords: ['custom theme', 'my themes'],
  ),
  SettingsSearchEntry(
    'appearance.newTheme',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceNewThemeButton,
    keywords: ['new theme', 'create theme'],
  ),
  SettingsSearchEntry(
    'appearance.colourDance',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceColourDanceTitle,
    keywords: ['colour dance', 'tint', 'accent'],
  ),
  SettingsSearchEntry(
    'appearance.setListColourCoding',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceSetListColorTitle,
    keywords: ['set list colours', 'colour coding'],
  ),
  SettingsSearchEntry(
    'appearance.formationColours',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceFormationColoursTitle,
    keywords: ['formation colours', 'stage colours'],
  ),
  SettingsSearchEntry(
    'appearance.tagColours',
    SettingsSection.appearance,
    (l) => l.settingsAppearanceTagColoursTitle,
    keywords: ['tag colours', 'labels'],
  ),

  // Dialect
  SettingsSearchEntry(
    'dialect.new',
    SettingsSection.dialect,
    (l) => l.settingsDialectNewButton,
    keywords: ['create dialect', 'terminology'],
  ),
  SettingsSearchEntry(
    'dialect.duplicateFrom',
    SettingsSection.dialect,
    (l) => l.settingsDialectDuplicateFrom,
    keywords: ['copy dialect', 'duplicate preset'],
  ),

  // Language & region
  SettingsSearchEntry(
    'regional.appLanguage',
    SettingsSection.regional,
    (l) => l.settingsAppLanguageTitle,
    keywords: ['language', 'locale', 'translation'],
  ),
  SettingsSearchEntry(
    'regional.dateFormat',
    SettingsSection.regional,
    (l) => l.settingsDateFormatTitle,
    keywords: ['date format', 'dmy', 'iso'],
  ),
  SettingsSearchEntry(
    'regional.customDatePattern',
    SettingsSection.regional,
    (l) => l.settingsDateFormatCustomPatternLabel,
    keywords: ['pattern', 'format string', 'custom date'],
  ),
  SettingsSearchEntry(
    'regional.firstDayOfWeek',
    SettingsSection.regional,
    (l) => l.settingsFirstDayOfWeekTitle,
    keywords: ['week start', 'monday', 'calendar'],
  ),

  // Updates
  SettingsSearchEntry(
    'updates.retirement',
    SettingsSection.updates,
    (l) => l.settingsUpdatesRetirementTitle,
    keywords: ['end of support', 'retired'],
  ),
  SettingsSearchEntry(
    'updates.checkNow',
    SettingsSection.updates,
    (l) => l.settingsUpdatesCheckNowTitle,
    keywords: ['check for updates', 'refresh'],
  ),
  SettingsSearchEntry(
    'updates.portable',
    SettingsSection.updates,
    (l) => l.settingsUpdatesPortableTitle,
    keywords: ['portable', 'zip', 'download release'],
  ),
  SettingsSearchEntry(
    'updates.download',
    SettingsSection.updates,
    (l) => l.settingsUpdatesDownloadTitle,
    keywords: ['download', 'install', 'update'],
  ),
  SettingsSearchEntry(
    'updates.betaChannel',
    SettingsSection.updates,
    (l) => l.settingsUpdatesBetaTitle,
    keywords: ['beta', 'prerelease', 'channel'],
  ),
  SettingsSearchEntry(
    'updates.automaticChecks',
    SettingsSection.updates,
    (l) => l.settingsUpdatesAutoTitle,
    keywords: ['automatic', 'background check'],
  ),

  // Diagnostics
  SettingsSearchEntry(
    'diagnostics.fullDetail',
    SettingsSection.diagnostics,
    (l) => l.diagnosticsFullDetailTitle,
    keywords: ['unredacted', 'raw log', 'privacy'],
  ),
  SettingsSearchEntry(
    'diagnostics.shareLog',
    SettingsSection.diagnostics,
    (l) => l.diagnosticsExportShareLogTitle,
    keywords: ['export', 'share', 'save log'],
  ),
  SettingsSearchEntry(
    'diagnostics.clearLog',
    SettingsSection.diagnostics,
    (l) => l.diagnosticsClearLogRowTitle,
    keywords: ['clear', 'delete log', 'reset'],
  ),

  // Experimental
  SettingsSearchEntry(
    'experimental.showGlossary',
    SettingsSection.experimental,
    (l) => l.settingsExperimentalShowGlossaryTitle,
    keywords: ['glossary', 'definitions', 'navigation'],
  ),
  SettingsSearchEntry(
    'experimental.showCustomFigures',
    SettingsSection.experimental,
    (l) => l.settingsExperimentalShowCustomFiguresTitle,
    keywords: ['custom figures', 'own figures'],
  ),
  SettingsSearchEntry(
    'experimental.manageCustomFigures',
    SettingsSection.experimental,
    (l) => l.settingsExperimentalCustomFiguresManageTitle,
    keywords: ['edit figures', 'manage figures'],
  ),

  // About
  SettingsSearchEntry(
    'about.userGuide',
    SettingsSection.about,
    (l) => l.settingsAboutUserGuideTitle,
    keywords: ['help', 'manual', 'guide'],
  ),
  SettingsSearchEntry(
    'about.viewSource',
    SettingsSection.about,
    (l) => l.settingsAboutViewSourceTitle,
    keywords: ['source code', 'repository', 'github'],
  ),
  SettingsSearchEntry(
    'about.viewLicenses',
    SettingsSection.about,
    (l) => l.settingsAboutViewLicensesTitle,
    keywords: ['licenses', 'credits', 'acknowledgements'],
  ),

  // Program
  SettingsSearchEntry(
    'program.venueEntityMode',
    SettingsSection.program,
    (l) => l.settingsGeneralVenueEntityModeTitle,
    keywords: ['venues', 'venue records', 'reusable'],
  ),
  SettingsSearchEntry(
    'program.manageVenues',
    SettingsSection.program,
    (l) => l.settingsGeneralManageVenuesTitle,
    keywords: ['venues', 'edit venues', 'venue list'],
  ),
  SettingsSearchEntry(
    'program.matrixExactCollision',
    SettingsSection.program,
    (l) => l.settingsGeneralMatrixExactCollisionTitle,
    keywords: ['collision', 'beat overlap', 'matrix'],
  ),
  SettingsSearchEntry(
    'program.autoCommit',
    SettingsSection.program,
    (l) => l.settingsProgramAutoCommitTitle,
    keywords: ['autosave', 'auto-save', 'save'],
  ),
  SettingsSearchEntry(
    'program.matrixColumns',
    SettingsSection.program,
    (l) => l.settingsMatrixColumnsHeader,
    keywords: ['columns', 'matrix', 'configure'],
  ),
  SettingsSearchEntry(
    'program.sharingTitle',
    SettingsSection.program,
    (l) => l.settingsSharingTitleTitle,
    keywords: ['share', 'title'],
  ),
  SettingsSearchEntry(
    'program.sharingCallerBand',
    SettingsSection.program,
    (l) => l.settingsSharingCallerBandTitle,
    keywords: ['share', 'caller', 'band'],
  ),
  SettingsSearchEntry(
    'program.sharingDateVenue',
    SettingsSection.program,
    (l) => l.settingsSharingDateVenueTitle,
    keywords: ['share', 'date', 'venue'],
  ),
  SettingsSearchEntry(
    'program.autoSizePerform',
    SettingsSection.program,
    (l) => l.settingsGeneralAutoSizePerformTitle,
    keywords: ['perform', 'cards', 'auto size'],
  ),
  SettingsSearchEntry(
    'program.performTimer',
    SettingsSection.program,
    (l) => l.settingsShowIndividualPerformTimerTitle,
    keywords: ['timer', 'stopwatch', 'perform'],
  ),
  SettingsSearchEntry(
    'program.callerNotesInPerform',
    SettingsSection.program,
    (l) => l.settingsShowProgramSlotCallerNotesTitle,
    keywords: ['caller notes', 'notes', 'perform'],
  ),
  SettingsSearchEntry(
    'program.requirePerformedForHistory',
    SettingsSection.program,
    (l) => l.settingsGeneralRequirePerformedForHistoryTitle,
    keywords: ['performed', 'calling history'],
  ),
  SettingsSearchEntry(
    'program.showPerformedToggles',
    SettingsSection.program,
    (l) => l.settingsGeneralShowPerformedTogglesTitle,
    keywords: ['performed', 'toggles'],
  ),
  SettingsSearchEntry(
    'program.markAllSetsStatus',
    SettingsSection.program,
    (l) => l.settingsGeneralMarkAllSetsStatusTitle,
    keywords: ['mark all', 'bulk', 'status'],
  ),
  SettingsSearchEntry(
    'program.requireEventDateForHistory',
    SettingsSection.program,
    (l) => l.settingsGeneralRequireEventDateForHistoryTitle,
    keywords: ['event date', 'history'],
  ),
  SettingsSearchEntry(
    'program.trackHistoryForAllCallers',
    SettingsSection.program,
    (l) => l.settingsGeneralTrackHistoryForAllCallersTitle,
    keywords: ['history', 'callers', 'track'],
  ),
  SettingsSearchEntry(
    'program.venueCallCount',
    SettingsSection.program,
    (l) => l.settingsProgramVenueCallCountTitle,
    keywords: ['venue count', 'repeats', 'history'],
  ),
  SettingsSearchEntry(
    'program.recencyRequireEventDate',
    SettingsSection.program,
    (l) => l.settingsRecencyRequireEventDateTitle,
    keywords: ['recency', 'dated programs'],
  ),
  SettingsSearchEntry(
    'program.recencyRequirePerformed',
    SettingsSection.program,
    (l) => l.settingsRecencyRequirePerformedTitle,
    keywords: ['recency', 'performed'],
  ),
  SettingsSearchEntry(
    'program.historyOrderIgnoreUndated',
    SettingsSection.program,
    (l) => l.settingsHistoryOrderIgnoreUndatedTitle,
    keywords: ['history order', 'undated', 'last called'],
  ),
  SettingsSearchEntry(
    'program.historyOrderIgnoreUnperformed',
    SettingsSection.program,
    (l) => l.settingsHistoryOrderIgnoreUnperformedTitle,
    keywords: ['history order', 'performed', 'last called'],
  ),

  // Defaults
  SettingsSearchEntry(
    'defaults.collectionSort',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsSortTitle,
    keywords: ['sort', 'ordering', 'default sort'],
  ),
  SettingsSearchEntry(
    'defaults.programSort',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsProgramSortTitle,
    keywords: ['sort', 'program order'],
  ),
  SettingsSearchEntry(
    'defaults.collectionCardFields',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardHeader,
    keywords: ['card', 'tile', 'list fields', 'display'],
  ),
  SettingsSearchEntry(
    'defaults.cardAuthors',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardAuthors,
  ),
  SettingsSearchEntry(
    'defaults.cardCalledCount',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardCalledCount,
    keywords: ['times called', 'plays', 'popularity'],
  ),
  SettingsSearchEntry(
    'defaults.cardFormation',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardFormation,
  ),
  SettingsSearchEntry(
    'defaults.cardStatus',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardStatus,
  ),
  SettingsSearchEntry(
    'defaults.cardLevel',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardLevel,
  ),
  SettingsSearchEntry(
    'defaults.cardRating',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardRating,
    keywords: ['stars', 'rating'],
  ),
  SettingsSearchEntry(
    'defaults.cardTags',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardTags,
  ),
  SettingsSearchEntry(
    'defaults.cardCustomFields',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionCardCustomFields,
    keywords: ['custom', 'extra fields', 'user fields'],
  ),
  SettingsSearchEntry(
    'defaults.shareFields',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsHeader,
    keywords: ['share', 'shared fields', 'cdef'],
  ),
  SettingsSearchEntry(
    'defaults.shareAuthors',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsAuthors,
  ),
  SettingsSearchEntry(
    'defaults.shareFormation',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsFormation,
  ),
  SettingsSearchEntry(
    'defaults.shareLevel',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsLevel,
  ),
  SettingsSearchEntry(
    'defaults.shareMixer',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsMixer,
  ),
  SettingsSearchEntry(
    'defaults.shareStatus',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsStatus,
  ),
  SettingsSearchEntry(
    'defaults.sharePhrase',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsPhraseStructure,
    keywords: ['phrase structure', 'phrasing'],
  ),
  SettingsSearchEntry(
    'defaults.shareCallingNotes',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsCallingNotes,
    keywords: ['notes', 'calling'],
  ),
  SettingsSearchEntry(
    'defaults.shareWalkthrough',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsWalkthrough,
    keywords: ['teach', 'walk-through'],
  ),
  SettingsSearchEntry(
    'defaults.shareTunes',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsTunes,
    keywords: ['tune', 'music', 'recording'],
  ),
  SettingsSearchEntry(
    'defaults.shareHook',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsHook,
    keywords: ['tagline'],
  ),
  SettingsSearchEntry(
    'defaults.shareSources',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsShareFieldsSources,
    keywords: ['attribution', 'credit'],
  ),
  SettingsSearchEntry(
    'defaults.collectionFilters',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCollectionFiltersHeader,
    keywords: ['facets', 'filters', 'filter panel'],
  ),
  SettingsSearchEntry(
    'defaults.program',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsProgramHeader,
    keywords: ['program defaults', 'caller', 'band'],
  ),
  SettingsSearchEntry(
    'defaults.caller',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsCallerLabel,
    keywords: ['caller', 'prefill'],
  ),
  SettingsSearchEntry(
    'defaults.band',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsBandLabel,
    keywords: ['band', 'prefill'],
  ),
  SettingsSearchEntry(
    'defaults.import',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsImportHeader,
    keywords: ['import tags', 'tags'],
  ),
  SettingsSearchEntry(
    'defaults.authoring',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsAuthoringHeader,
    keywords: ['authoring', 'editor defaults'],
  ),
  SettingsSearchEntry(
    'defaults.difficultyLevel',
    SettingsSection.defaults,
    (l) => l.danceEditorLevelLabel,
    keywords: ['difficulty', 'skill', 'levels'],
  ),
  SettingsSearchEntry(
    'defaults.form',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsFormTitle,
  ),
  SettingsSearchEntry(
    'defaults.formation',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsFormationTitle,
  ),
  SettingsSearchEntry(
    'defaults.progression',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsProgressionTitle,
  ),
  SettingsSearchEntry(
    'defaults.phrase',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsPhraseLabel,
    keywords: ['phrase structure', 'phrasing'],
  ),
  SettingsSearchEntry(
    'defaults.startingFigures',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsStartingFiguresTitle,
    keywords: ['template', 'first figures', 'new dance'],
  ),
  SettingsSearchEntry(
    'defaults.meanwhile',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsMeanwhileTitle,
    keywords: ['sides'],
  ),
  SettingsSearchEntry(
    'defaults.modifier',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsModifierTitle,
  ),
  SettingsSearchEntry(
    'defaults.moveDefaults',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsMoveDefaultsTitle,
    keywords: ['move', 'per-move', 'move parameters'],
  ),
  SettingsSearchEntry(
    'defaults.aggressiveBeats',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsAggressiveBeatsUpdateTitle,
    keywords: ['beats', 'recompute', 'aggressive'],
  ),
  SettingsSearchEntry(
    'defaults.startingProgram',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsStartingProgramTitle,
    keywords: ['template', 'program template'],
  ),
  SettingsSearchEntry(
    'defaults.startingProgramText',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsStartingProgramTextLabel,
    keywords: ['program template', 'text'],
  ),
  SettingsSearchEntry(
    'defaults.addMove',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsAddMoveButton,
    keywords: ['new move', 'add move'],
  ),
  SettingsSearchEntry(
    'defaults.userFigures',
    SettingsSection.defaults,
    (l) => l.settingsDefaultsUserFiguresTitle,
    keywords: ['custom figures', 'user figures'],
  ),
];

/// The settings whose title, section name or synonym contains [query], in
/// index order. Empty for a blank query, which shows the normal section
/// navigation instead.
List<SettingsSearchEntry> searchSettings(
  AppLocalizations l10n, {
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return [
    for (final entry in settingsSearchIndex)
      if (entry.label(l10n).toLowerCase().contains(q) ||
          settingsSectionLabelOf(
            l10n,
            entry.section,
          ).toLowerCase().contains(q) ||
          entry.keywords.any((keyword) => keyword.contains(q)))
        entry,
  ];
}
