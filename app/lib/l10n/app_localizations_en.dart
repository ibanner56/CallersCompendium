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
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonProgression => 'Progression';

  @override
  String get commonMixedLevel => 'Mixed level';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'Show dances tagged “$tagName”';
  }

  @override
  String commonDeletedSnack(String title) {
    return '\"$title\" deleted.';
  }

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
    return 'Programming matrix: $danceCount dances by $moveCount moves';
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
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(debut, {
      'yes': ', introduced here',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(first, {
      'yes': ', dance\'s first figure',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(present, {
      'no': 'not present',
      'other': 'present$_temp0$_temp1',
    });
    return '$dance, $move: $_temp2';
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
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total dances',
      one: '1 dance',
    );
    return 'Move: $label, used in $count of $_temp0';
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
  String get programsMatrixEmptyTitle => 'No structured figures yet';

  @override
  String get programsMatrixEmptyBody =>
      'The matrix fills in automatically as the program’s dances gain structured figures.';

  @override
  String get performTitle => 'Perform';

  @override
  String get performExitTooltip => 'Exit performance view';

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
  String get performNoFigures => 'No figures yet.';

  @override
  String get performDecreaseTextSize => 'Decrease text size';

  @override
  String get performIncreaseTextSize => 'Increase text size';

  @override
  String get performShowCanonicalTerms => 'Show canonical terms';

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
}
