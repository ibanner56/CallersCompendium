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

  /// Label for the progression concept: used as a filter section heading and the figure-row progression-marker tooltip.
  ///
  /// In en, this message translates to:
  /// **'Progression'**
  String get commonProgression;

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
