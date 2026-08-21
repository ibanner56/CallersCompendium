/// Classification of every value stored in the `settings` key/value table,
/// keyed by the settings key string.
///
/// Lives here rather than in the app package so the catalogue has a single
/// source of truth and a single generated document, even though the keys are
/// *declared* in `app/lib`. The coverage ratchet runs on the app side
/// (`app/test/data/settings_classification_test.dart`), where the declarations
/// are, and fails when a key has no entry here.
///
/// `settings.value_json` is classified `deviceLocal` at the column level so a
/// blanket sync of the table cannot happen by accident. These per-key entries
/// are what actually decide whether a given preference travels.
library;

import 'data_classification.dart';

/// A working preference or piece of user-authored configuration. Travels: it
/// describes how the user likes to work, which is the same on any device they
/// own.
const _preference = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.appUser,
  egress: EgressClass.shareable,
);

/// State belonging to this installation rather than to the user. Never
/// transmitted, because it is meaningless or actively wrong elsewhere — not
/// because it is sensitive.
const _installState = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.deviceScoped,
  note:
      'Belongs to this installation, not the user. Applying it on another '
      'device would be wrong rather than merely useless.',
);

/// Classification for every settings key. See the file doc comment.
final Map<String, DataClassification> settingsClassifications = {
  // -- User-authored content ------------------------------------------------
  'custom_dialects': _preference,
  'custom_themes': _preference,
  'shorthand_mappings': _preference,
  'walkthrough_snippets': _preference,
  'formation_color_overrides': _preference,
  'default_move_param_overrides': _preference,
  'default_dance_figures_template': _preference,

  // -- Appearance and accessibility ----------------------------------------
  'active_custom_theme': _preference,
  'colour_dance_theme': _preference,
  'theme_mode': _preference,
  'reduce_motion': _preference,
  'set_list_color_coding': _preference,

  // -- Dialect and rendering ------------------------------------------------
  'active_dialect': _preference,
  'active_dialect_ref': _preference,
  'verbose_figure_rendering': _preference,
  'decimal_turns': _preference,
  'free_text_entry': _preference,
  'aggressive_beats_update': _preference,

  // -- Regional -------------------------------------------------------------
  'app_locale': _preference,
  'date_format': _preference,
  'date_format_custom': _preference,
  'first_day_of_week': _preference,

  // -- Collection and editing defaults --------------------------------------
  'default_collection_sort': _preference,
  'default_program_sort': _preference,
  'last_used_collection_sort': _preference,
  'last_used_collection_sort_direction': _preference,
  'last_used_program_sort': _preference,
  'last_used_program_sort_direction': _preference,
  'default_dance_detail_rendering': _preference,
  'default_dance_form': _preference,
  'default_dance_formation_shape': _preference,
  'default_dance_phrase_structure': _preference,
  'default_dance_progression': _preference,
  'sort_ignore_articles': _preference,
  'confirm_before_delete': _preference,
  'soft_delete_retention_days': _preference,
  'venue_entity_mode': _preference,
  'collection_tile_visible_fields': _preference,
  // Whether the programming matrix flags a same-figure repeat between
  // strictly-adjacent dances by exact beat overlap (on, the default) or by
  // merely sharing a named phrase (off, the original #582 behaviour) —
  // issue #962. A working preference, same as every other display/behaviour
  // toggle above.
  'matrix_exact_beat_collision': _preference,
  // The app-wide program-matrix column configuration (issue #935): hidden /
  // reordered / renamed built-in columns plus user-defined parameterized and
  // compound columns, as one JSON blob. A working preference — it describes how
  // the user likes their matrix laid out, which is the same on any device they
  // own — so it is `_preference` like every other authored-config blob above
  // (custom_themes, default_move_param_overrides). It contains only column ids,
  // label overrides, and move/param tokens the user chose; no personal data and
  // nothing device-specific, so it travels in local backups (validated on
  // restore by backup_settings_schema.dart).
  'program_matrix_columns': _preference,

  // -- Programs and performance --------------------------------------------
  'default_program_band': const DataClassification(
    term: DpvTerm.name,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A performer name the user pre-fills onto new programs — most often '
        'their own band. Personal data, shareable for the same reason as '
        'programs.band.',
  ),
  'default_program_caller': const DataClassification(
    term: DpvTerm.name,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A performer name the user pre-fills onto new programs — most often '
        'themselves. Personal data, shareable for the same reason as '
        'programs.caller.',
  ),
  'auto_size_perform_cards': _preference,
  'auto_commit_program_changes': _preference,
  'perform_canonical_view': _preference,
  'perform_stage_mode': _preference,
  'perform_text_scale': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceScoped,
    note:
        'Tuned to the screen it was set on. A scale chosen for a phone held at '
        "arm's length is wrong on a laptop driving a projector.",
  ),
  'require_performed_for_history': _preference,
  'track_history_for_all_callers': _preference,

  // -- Installation state ---------------------------------------------------
  'window_frame': _installState,
  'last_backup_at': _installState,
  'seed.initialCollection.completed': _installState,
  // Records that the one-time custom-field sharing disclosure was shown on
  // this device. A boolean latch; contains no personal data.
  'custom_fields.sharing.disclosed': _installState,
  'update_auto_check': _installState,
  'update_beta_channel': _installState,
  'update_dismissed_version': _installState,
  'backup_reminder_cadence': _preference,
};

/// Classification for settings keys that are *built at runtime* from a known
/// prefix rather than declared as an exact `const String`, keyed by the
/// literal prefix string.
///
/// Some settings-table keys can't be named as exact [settingsClassifications]
/// entries because they're constructed per-entity — `editor_draft:<danceId>`,
/// `program_editor_draft:<programId>` — so the exact-string map can never hold
/// an entry for them (issue #923). This is the registry's prefix-keyed
/// sibling: [classifySettingsKey] resolves a runtime key against both maps,
/// exact match first, longest matching prefix second.
final Map<String, DataClassification> settingsPrefixClassifications = {
  // Unsaved, in-progress dance/program-editor autosave drafts. Deliberately
  // `deviceScoped`, not `deviceLocal`: `app/lib/src/data/backup_service.dart`
  // excludes both prefixes from backups with the reasoning "must never travel
  // in a backup", and `deviceLocal` explicitly permits travel in a local
  // backup file the user controls — so `deviceLocal` would license the one
  // thing this data must never do. `deviceScoped` (never transmitted by any
  // route) is the classification that actually matches the existing backup
  // exclusion. Maintainer-ruled on issue #923 (2026-08-13 comment).
  'editor_draft:': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceScoped,
    note:
        'Transient dance-editor autosave draft, keyed per dance '
        '(editor_draft:<id>). Unsaved user-authored choreography text that '
        'must never leave this device by any route, including a local '
        'backup file — see backup_service.dart.',
  ),
  'program_editor_draft:': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceScoped,
    note:
        'Transient program-editor autosave draft, keyed per program '
        '(program_editor_draft:<id>). Same rationale as editor_draft:.',
  ),
};

/// Resolves a settings-table [key] to its classification: an exact
/// [settingsClassifications] entry if one exists, otherwise the
/// **longest** matching prefix in [settingsPrefixClassifications] (so a
/// future narrower prefix can't be shadowed by a broader one), otherwise
/// `null`.
DataClassification? classifySettingsKey(String key) {
  final exact = settingsClassifications[key];
  if (exact != null) return exact;

  String? bestPrefix;
  for (final prefix in settingsPrefixClassifications.keys) {
    if (!key.startsWith(prefix)) continue;
    if (bestPrefix == null || prefix.length > bestPrefix.length) {
      bestPrefix = prefix;
    }
  }
  return bestPrefix == null ? null : settingsPrefixClassifications[bestPrefix];
}
