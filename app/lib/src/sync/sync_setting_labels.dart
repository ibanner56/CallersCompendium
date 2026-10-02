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
  'aggressive_beats_update' => l10n.settingsDefaultsAggressiveBeatsUpdateTitle,
  'app_locale' => l10n.settingsAppLanguageTitle,
  'auto_commit_program_changes' => l10n.settingsProgramAutoCommitTitle,
  'auto_size_perform_cards' => l10n.settingsGeneralAutoSizePerformTitle,
  'backup_reminder_cadence' => l10n.backupReminderTitle,
  'canonical_discouraged_terms' =>
    l10n.settingsDialectCanonicalDiscouragedTermsTitle,
  'canonical_figure_text' => l10n.settingsDialectCanonicalFigureTextTitle,
  'collection_hidden_facets' => l10n.settingsDefaultsCollectionFiltersHeader,
  'collection_tile_visible_fields' => l10n.settingsDefaultsCollectionCardHeader,
  'colour_dance_theme' => l10n.settingsAppearanceColourDanceTitle,
  'confirm_before_delete' => l10n.settingsGeneralConfirmBeforeDeleteTitle,
  'custom_dialects' => l10n.settingsDialectHeader,
  'custom_themes' => l10n.settingsAppearanceCustomThemesHeader,
  'date_format' => l10n.settingsDateFormatTitle,
  'date_format_custom' => l10n.settingsDateFormatCustomPatternLabel,
  'decimal_turns' => l10n.settingsGeneralDecimalTurnsTitle,
  'default_collection_sort' => l10n.settingsDefaultsSortTitle,
  'default_dance_detail_rendering' => l10n.settingsDefaultsCanonicalTitle,
  'default_dance_figures_template' => l10n.settingsDefaultsStartingFiguresTitle,
  'default_dance_form' => l10n.settingsDefaultsFormTitle,
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
  'matrix_exact_beat_collision' =>
    l10n.settingsGeneralMatrixExactCollisionTitle,
  'perform_canonical_view' => l10n.performShowCanonicalTerms,
  'perform_stage_mode' => l10n.syncSettingPerformStageTheme,
  'program_dance_share_fields' => l10n.settingsDefaultsShareFieldsHeader,
  'program_matrix_columns' => l10n.settingsMatrixColumnsHeader,
  'reduce_motion' => l10n.settingsGeneralReduceMotionTitle,
  'require_performed_for_history' =>
    l10n.settingsGeneralRequirePerformedForHistoryTitle,
  'set_list_color_coding' => l10n.settingsAppearanceSetListColorTitle,
  'shorthand_mappings' => l10n.settingsDefaultsFigureShorthandsTitle,
  'show_individual_perform_timer' =>
    l10n.settingsShowIndividualPerformTimerTitle,
  'show_program_slot_caller_notes' =>
    l10n.settingsShowProgramSlotCallerNotesTitle,
  'soft_delete_retention_days' => l10n.settingsGeneralSoftDeleteRetentionTitle,
  'sort_ignore_articles' => l10n.settingsGeneralSortIgnoreArticlesTitle,
  'theme_mode' => l10n.settingsAppearanceThemeHeader,
  'track_history_for_all_callers' =>
    l10n.settingsGeneralTrackHistoryForAllCallersTitle,
  'venue_call_count' => l10n.settingsProgramVenueCallCountTitle,
  'venue_entity_mode' => l10n.settingsGeneralVenueEntityModeTitle,
  'verbose_figure_rendering' => l10n.settingsGeneralVerboseFiguresTitle,
  'walkthrough_snippets' => l10n.settingsWalkthroughSnippetsTitle,
  _ => null,
};

/// A short, human-readable rendering of a synced setting's value, for telling
/// two versions apart. It names what can be named and counts what cannot:
/// a whole collection is summarised by the names of its entries when they have
/// them, never dumped as data.
String syncSettingValueText(AppLocalizations l10n, Object? value) {
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

/// The display names of a collection's entries, where entries carry one.
List<String> _names(Iterable<Object?> entries) => [
  for (final entry in entries)
    if (entry is Map)
      switch (entry['name'] ?? entry['label'] ?? entry['title']) {
        final String name when name.isNotEmpty => name,
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
