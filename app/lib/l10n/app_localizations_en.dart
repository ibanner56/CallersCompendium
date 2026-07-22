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
}
