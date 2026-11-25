import 'package:compendium_core/compendium_core.dart'
    show
        EventRuleOrder,
        savedSearchKeyPrefix,
        shownDialectName,
        syncCapabilityKeyPrefix;

import '../../l10n/app_localizations.dart';

/// The name a person knows a synced setting by, for surfaces that must say
/// which setting they mean — the conflict choice above all, where "Setting"
/// alone gives the user nothing to decide with.
///
/// Every key classified `shareable` in the settings registry must have a label
/// here; `sync_setting_labels_test.dart` fails the build when one is added
/// without. Labels reuse the Settings screen's own titles wherever a setting
/// has a row there, so the conflict names the setting exactly as the user
/// would look for it. Returns null for a key this table does not know, which
/// callers render as the generic kind label.
String? syncSettingLabel(AppLocalizations l10n, String key) => switch (key) {
  'active_custom_theme' => l10n.syncSettingActiveCustomTheme,
  'active_dialect' || 'active_dialect_ref' => l10n.syncSettingActiveDialect,
  // Each other dance form's dialects (ADR-006 §9.1, point 1), named with the
  // form: "Dialect in use: English (ECD)".
  'active_dialect_ref_ecd' => l10n.syncConflictFieldValue(
    l10n.syncSettingActiveDialect,
    l10n.commonDanceFormEcd,
  ),
  'active_dialect_ref_square' => l10n.syncConflictFieldValue(
    l10n.syncSettingActiveDialect,
    l10n.commonDanceFormSquare,
  ),
  'custom_dialects_ecd' => l10n.syncConflictFieldValue(
    l10n.settingsDialectHeader,
    l10n.commonDanceFormEcd,
  ),
  'custom_dialects_square' => l10n.syncConflictFieldValue(
    l10n.settingsDialectHeader,
    l10n.commonDanceFormSquare,
  ),
  'aggressive_beats_update' => l10n.settingsDefaultsAggressiveBeatsUpdateTitle,
  'app_locale' => l10n.settingsAppLanguageTitle,
  'auto_commit_program_changes' => l10n.settingsProgramAutoCommitTitle,
  'auto_size_perform_cards' => l10n.settingsGeneralAutoSizePerformTitle,
  'backup_reminder_cadence' => l10n.backupReminderTitle,
  'canonical_discouraged_terms' =>
    l10n.settingsDialectCanonicalDiscouragedTermsTitle,
  'canonical_figure_text' => l10n.settingsDialectCanonicalFigureTextTitle,
  'capitalize_figures' => l10n.settingsGeneralCapitalizeFiguresTitle,
  'collection_hidden_facets' => l10n.settingsDefaultsCollectionFiltersHeader,
  'collection_tile_visible_fields' => l10n.settingsDefaultsCollectionCardHeader,
  'colour_dance_theme' => l10n.settingsAppearanceColourDanceTitle,
  'confirm_before_delete' => l10n.settingsGeneralConfirmBeforeDeleteTitle,
  'confirm_perform_exit' => l10n.settingsConfirmPerformExitTitle,
  'custom_dialects' => l10n.settingsDialectHeader,
  'custom_themes' => l10n.settingsAppearanceCustomThemesHeader,
  'date_format' => l10n.settingsDateFormatTitle,
  'date_format_custom' => l10n.settingsDateFormatCustomPatternLabel,
  'decimal_turns' => l10n.settingsGeneralDecimalTurnsTitle,
  'default_collection_sort' => l10n.settingsDefaultsSortTitle,
  'default_collection_sort_direction' =>
    l10n.syncSettingDefaultCollectionSortDirection,
  'default_dance_detail_rendering' => l10n.settingsDefaultsCanonicalTitle,
  'default_dance_figures_template' => l10n.settingsDefaultsStartingFiguresTitle,
  'default_dance_form' => l10n.settingsDefaultsFormTitle,
  'last_used_dance_form' => l10n.syncConflictFieldValue(
    l10n.settingsDefaultsFormTitle,
    l10n.settingsDefaultsFormLastUsed,
  ),
  'default_dance_formation_shape' => l10n.settingsDefaultsFormationTitle,
  'default_dance_phrase_structure' => l10n.settingsDefaultsPhraseLabel,
  'default_dance_progression' => l10n.settingsDefaultsProgressionTitle,
  'default_import_tag_names' => l10n.settingsDefaultsImportTagsTitle,
  'default_meanwhile_side_figures' => l10n.settingsDefaultsMeanwhileTitle,
  'default_modifier_figures' => l10n.settingsDefaultsModifierTitle,
  'default_move_param_overrides' => l10n.settingsDefaultsMoveDefaultsTitle,
  'default_program_band' => l10n.settingsDefaultsBandLabel,
  'default_program_caller' => l10n.settingsDefaultsCallerLabel,
  'default_program_sort' => l10n.settingsDefaultsProgramSortTitle,
  'default_program_sort_direction' =>
    l10n.syncSettingDefaultProgramSortDirection,
  'default_starting_program' => l10n.settingsDefaultsStartingProgramTitle,
  'first_day_of_week' => l10n.settingsFirstDayOfWeekTitle,
  'formation_color_overrides' => l10n.settingsAppearanceFormationColoursTitle,
  'free_text_entry' => l10n.settingsDefaultsFreeTextEntryTitle,
  'last_used_collection_sort' => l10n.syncSettingLastCollectionSort,
  'last_used_collection_sort_direction' =>
    l10n.syncSettingLastCollectionSortDirection,
  'last_used_program_sort' => l10n.syncSettingLastProgramSort,
  'last_used_program_sort_direction' =>
    l10n.syncSettingLastProgramSortDirection,
  'mark_all_sets_status' => l10n.settingsGeneralMarkAllSetsStatusTitle,
  'matrix_exact_beat_collision' =>
    l10n.settingsGeneralMatrixExactCollisionTitle,
  'share_set_list_include_caller_band' => l10n.settingsSharingCallerBandTitle,
  'share_set_list_include_date_venue' => l10n.settingsSharingDateVenueTitle,
  'share_set_list_include_title' => l10n.settingsSharingTitleTitle,
  'perform_canonical_view' => l10n.performShowCanonicalTerms,
  'perform_stage_mode' => l10n.syncSettingPerformStageTheme,
  'program_dance_share_fields' => l10n.settingsDefaultsShareFieldsHeader,
  'program_matrix_columns' => l10n.settingsMatrixColumnsHeader,
  'program_template_default' => l10n.settingsProgramTemplateDefaultTitle,
  'program_template_order' => l10n.settingsProgramTemplatesTitle,
  'reduce_motion' => l10n.settingsGeneralReduceMotionTitle,
  'recency_require_event_date' => l10n.settingsRecencyRequireEventDateTitle,
  'recency_require_performed' => l10n.settingsRecencyRequirePerformedTitle,
  'history_order_ignore_undated' => l10n.settingsHistoryOrderIgnoreUndatedTitle,
  'history_order_ignore_unperformed' =>
    l10n.settingsHistoryOrderIgnoreUnperformedTitle,
  'require_event_date_for_history' =>
    l10n.settingsGeneralRequireEventDateForHistoryTitle,
  'require_performed_for_history' =>
    l10n.settingsGeneralRequirePerformedForHistoryTitle,
  'show_performed_toggles' => l10n.settingsGeneralShowPerformedTogglesTitle,
  'show_program_pay' => l10n.settingsProgramShowPayTitle,
  'set_list_color_coding' => l10n.settingsAppearanceSetListColorTitle,
  'shorthand_mappings' => l10n.settingsDefaultsFigureShorthandsTitle,
  'compound_shorthands' => l10n.shorthandsCompoundTitle,
  'user_figure_shorthands' => l10n.shorthandsUserFigureSyncLabel,
  'show_glossary' => l10n.settingsExperimentalShowGlossaryTitle,
  'show_custom_figures' => l10n.settingsExperimentalShowCustomFiguresTitle,
  'show_repertoire_dashboard' => l10n.settingsExperimentalShowRepertoireTitle,
  'suggestions_enabled' => l10n.settingsSuggestionsEnabledTitle,
  'suggestion_settings' => l10n.settingsSuggestionsEditorTitle,
  'suggestions_in_perform_swap' => l10n.settingsSuggestionsInPerformSwapTitle,
  'event_rules_enabled' => l10n.settingsExperimentalEventRulesTitle,
  'event_rule_order' => l10n.eventRulesOrderTitle,
  'calling_card_print' => l10n.settingsCallingCardsHeader,
  'show_individual_perform_timer' =>
    l10n.settingsShowIndividualPerformTimerTitle,
  'show_program_slot_caller_notes' =>
    l10n.settingsShowProgramSlotCallerNotesTitle,
  'perform_swap_defaults' => l10n.settingsPerformSwapTitle,
  'soft_delete_retention_days' => l10n.settingsGeneralSoftDeleteRetentionTitle,
  'sort_ignore_articles' => l10n.settingsGeneralSortIgnoreArticlesTitle,
  'theme_mode' => l10n.settingsAppearanceThemeHeader,
  'track_history_for_all_callers' =>
    l10n.settingsGeneralTrackHistoryForAllCallersTitle,
  'undo_prompt_seconds' => l10n.settingsGeneralUndoPromptTitle,
  'calendar_import_window_months' => l10n.calendarWindowTitle,
  'calendar_import_title_filter' => l10n.calendarTitleFilterTitle,
  'venue_call_count' => l10n.settingsProgramVenueCallCountTitle,
  'venue_entity_mode' => l10n.settingsGeneralVenueEntityModeTitle,
  'verbose_figure_rendering' => l10n.settingsGeneralVerboseFiguresTitle,
  'walkthrough_snippets' => l10n.settingsWalkthroughSnippetsTitle,
  // A device's capability record (#709). Only its own device writes it,
  // apart from the tombstone written when it is removed from the store, so a
  // conflict over one is rare; if one is ever shown, it is about the device
  // list.
  final key when key.startsWith(syncCapabilityKeyPrefix) =>
    l10n.settingsSyncDevicesTitle,
  // One saved search per key (#2325): the name of the setting, not the search's
  // own name, which syncSettingValueText shows.
  final key when key.startsWith(savedSearchKeyPrefix) =>
    l10n.syncSavedSearchLabel,
  // One program template per key (#2337), whatever its id.
  final key when key.startsWith('program_template:') =>
    l10n.settingsProgramTemplatesTitle,
  _ => null,
};

/// A short, human-readable rendering of a synced setting's value, for telling
/// two versions apart. It names what can be named and counts what cannot:
/// a whole collection is summarised by the names of its entries when they have
/// them, never dumped as data.
String syncSettingValueText(
  AppLocalizations l10n,
  Object? value, {
  String? key,
}) {
  // An active dialect's name, which an older build may still send gendered
  // (ADR-006 §9.1, point 7).
  if (key != null && key.startsWith('active_dialect_ref') && value is String) {
    value = shownDialectName(value);
  }
  // A saved search is one object holding its name and its search; showing the
  // name tells two versions apart, where a count of its parts would not.
  if (key != null && key.startsWith(savedSearchKeyPrefix) && value is Map) {
    final name = value['name'];
    if (name is String && name.trim().isNotEmpty) return _clip(name);
  }
  // The rule picker's order (#2341), as Settings names it.
  // A value this build does not know falls through to its text.
  if (key == 'event_rule_order') {
    if (value == EventRuleOrder.manual.name) return l10n.eventRulesOrderManual;
    if (value == EventRuleOrder.mostUsed.name) {
      return l10n.eventRulesOrderMostUsed;
    }
  }
  switch (value) {
    case null:
      return l10n.syncConflictValueNotSet;
    case true:
      return l10n.syncConflictValueOn;
    case false:
      return l10n.syncConflictValueOff;
    case String text:
      return text.isEmpty ? l10n.syncConflictValueNotSet : _clip(text);
    case num number:
      return number.toString();
    case List<Object?> items:
      return _collectionText(l10n, items);
    case Map<String, Object?> entries:
      final names = _names(entries.values);
      return names.isNotEmpty
          ? _joinNames(l10n, names, entries.length)
          : l10n.syncConflictValueItems(entries.length);
    default:
      return l10n.syncConflictValueItems(1);
  }
}

String _collectionText(AppLocalizations l10n, List<Object?> items) {
  if (items.isEmpty) return l10n.syncConflictValueItems(0);
  if (items.every((item) => item is String)) {
    return _joinNames(l10n, items.cast<String>(), items.length);
  }
  final names = _names(items);
  return names.isNotEmpty
      ? _joinNames(l10n, names, items.length)
      : l10n.syncConflictValueItems(items.length);
}

/// The display names of a collection's entries, where entries carry one. A
/// dialect's name (an entry with role terms) is masked when it is gendered,
/// as a device on an older build may still send one (ADR-006 §9.1, point 7).
List<String> _names(Iterable<Object?> entries) => [
  for (final entry in entries)
    if (entry is Map)
      switch (entry['name'] ?? entry['label'] ?? entry['title']) {
        final String name when name.isNotEmpty =>
          entry['roles'] is Map ? shownDialectName(name) : name,
        _ => null,
      },
].whereType<String>().toList();

String _joinNames(AppLocalizations l10n, List<String> names, int total) {
  const shown = 4;
  final head = names.take(shown).map(_clip).join(', ');
  return total > shown
      ? l10n.syncConflictValueNamesAndMore(head, total - shown)
      : head;
}

String _clip(String text) =>
    text.length <= 60 ? text : '${text.substring(0, 57)}…';
