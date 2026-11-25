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

/// Settings keys whose classification is the shared [_preference] one.
///
/// [_preference] carries no `note`: whose preference it is, and that it travels,
/// are the same on every key it covers. The note rule in
/// `data_classification_note_test.dart` exempts exactly these keys. Derived with
/// `identical`, the way `syncBookkeepingTables` is; Dart canonicalises const
/// values, so an entry written inline with the same fields and no note is the
/// same object and is exempt too, which is intended (the same classification has
/// the same reason). A setting leaves the exemption by being given a note or any
/// different field, and never needs the exemption otherwise.
final Set<String> preferenceSettingKeys = {
  for (final entry in settingsClassifications.entries)
    if (identical(entry.value, _preference)) entry.key,
};

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

/// Non-shareable settings that are intentionally retained in user-controlled
/// local backups. They remain excluded from project-operated infrastructure,
/// but unlike [_installState] their egress classification permits that backup
/// route.
const _backupLocalState = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.deviceLocal,
  note:
      'Non-shareable installation state intentionally retained in a '
      'user-controlled local backup, but not sent to project infrastructure.',
);

/// Classification for every settings key. See the file doc comment.
final Map<String, DataClassification> settingsClassifications = {
  // -- User-authored content ------------------------------------------------
  // A dialect's moves and moveWordings may hold `userFigure:<id>` keys, its
  // name and wording for a figure of the user's own (#1023): the opaque id of
  // a glossary entry, a soft reference (sync-spec §6.15) that is inert on a
  // device without the figure.
  'custom_dialects': _preference,
  // Each dance form's own dialects (ADR-006 §9.1, point 1); contra keeps
  // `custom_dialects`. Classified as it is: the user's own wording, which
  // travels to their devices like the contra library.
  'custom_dialects_ecd': _preference,
  'custom_dialects_square': _preference,
  'custom_themes': _preference,
  'shorthand_mappings': _preference,
  'compound_shorthands': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'The user\'s shorthands for their own compound figures (#709): '
        'tokens they chose, a figure\'s id and name, and values. Shareable '
        'like the figure shorthands; held back until every device can read '
        'it (SyncCapabilityPolicy.build).',
  ),
  'user_figure_shorthands': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'The user\'s shorthands for their own new figures (#1023): tokens '
        'they chose, a figure\'s id and name, values and beats. Classified '
        'as compound_shorthands is (the implementer\'s call, following that '
        'precedent): content the user authored for themselves, naming no '
        'one else. Held back until every device can '
        'read the figures themselves (glossary.v2, '
        'SyncCapabilityPolicy.build).',
  ),
  'walkthrough_snippets': _preference,
  'formation_color_overrides': _preference,
  'default_move_param_overrides': _preference,
  'default_dance_figures_template': _preference,
  'default_meanwhile_side_figures': _preference,
  'default_modifier_figures': _preference,

  // -- Appearance and accessibility ----------------------------------------
  'active_custom_theme': _preference,
  'colour_dance_theme': _preference,
  'theme_mode': _preference,
  'reduce_motion': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Screen-bound: an override set against one screen or one device\'s '
        'system Reduce Motion setting is not an answer for another. '
        'deviceLocal, not deviceScoped: it is withheld for what it means on '
        'another screen, not for what it contains, and deviceScoped would '
        'also drop it from the user\'s own backups, which should give it '
        'back on restore. Per-device by the maintainer\'s decision '
        '(settings-sync-scope, 2026-10-29).',
  ),
  'set_list_color_coding': _preference,

  // -- Dialect and rendering ------------------------------------------------
  'active_dialect': _preference,
  'active_dialect_ref': _preference,
  'active_dialect_ref_ecd': _preference,
  'active_dialect_ref_square': _preference,
  'verbose_figure_rendering': _preference,
  'decimal_turns': _preference,
  'capitalize_figures': _preference,
  'show_glossary': _preference,
  'show_custom_figures': _preference,
  'show_repertoire_dashboard': _preference,
  // Experimental Suggestions (#2343): the toggle, and what the builder's
  // Suggested sort looks for; and whether Perform's swap sheet orders by it
  // (#2348).
  'suggestions_enabled': _preference,
  // Experimental Event rules (#2340): the toggle.
  'event_rules_enabled': _preference,
  'suggestions_in_perform_swap': _preference,
  'suggestion_settings': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'The user\'s chosen weights for the program builder\'s Suggested '
        'sort (Off / A little / A lot per factor, the difficulty curve\'s '
        'shape and the venue window), plus a reserved list of preferences '
        'that will hold saved-search ids. How the user likes dances '
        'suggested, the same on every device, so it travels like any '
        'preference. Ranking reads calling history and venues locally and '
        'stores nothing.',
  ),
  'calling_card_print': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'Whether calling cards are offered, the card size, whether they print '
        'several to a page, and the card layout: how the user likes their '
        'cards printed. The card stock is the same whichever device prints, '
        'and printing onto sheets is a habit more than a property of one '
        'printer, so it travels like any preference. The layout can hold free text the user typed for a '
        'text block; like walkthrough_snippets, that is configuration the '
        'user authored for their own use, classified by what the setting is '
        'for rather than by whatever words they choose to print.',
  ),
  'free_text_entry': _preference,
  'aggressive_beats_update': _preference,
  'canonical_figure_text': _preference,
  'canonical_discouraged_terms': _preference,

  // -- Regional -------------------------------------------------------------
  'app_locale': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Screen-bound: a phone and the laptop driving a projector can want '
        'different interface languages, and a synced change would re-render '
        'the other device mid-session. '
        'deviceLocal, not deviceScoped: it is withheld for what it means on '
        'another screen, not for what it contains, and deviceScoped would '
        'also drop it from the user\'s own backups, which should give it '
        'back on restore. Per-device by the maintainer\'s decision '
        '(settings-sync-scope, 2026-10-29).',
  ),
  'date_format': _preference,
  'date_format_custom': _preference,
  'first_day_of_week': _preference,

  // -- Collection and editing defaults --------------------------------------
  'default_collection_sort': _preference,
  'default_program_sort': _preference,
  'default_collection_sort_direction': _preference,
  'default_program_sort_direction': _preference,
  'last_used_collection_sort': _preference,
  'last_used_collection_sort_direction': _preference,
  'last_used_program_sort': _preference,
  'last_used_program_sort_direction': _preference,
  'default_dance_detail_rendering': _preference,
  'default_dance_form': _preference,
  // The form of the last dance the user created, which a new dance starts as
  // while `default_dance_form` is "last used" (ADR-006 §12.2, S2). Synced
  // with that setting, which the maintainer chose to sync (§9.1, point 10),
  // like the `last_used_*_sort` keys above.
  'last_used_dance_form': _preference,
  'default_dance_formation_shape': _preference,
  'default_dance_phrase_structure': _preference,
  'default_dance_progression': _preference,
  'sort_ignore_articles': _preference,
  'confirm_before_delete': _preference,
  // How long the Undo prompt stays on screen (0 = until closed). A reading or
  // motor-access need of the person, not of the screen, so it travels with
  // their other preferences like confirm_before_delete; it holds one small
  // number and nothing personal.
  'undo_prompt_seconds': _preference,
  'soft_delete_retention_days': _preference,
  'venue_entity_mode': _preference,
  'collection_tile_visible_fields': _preference,
  // The set of non-figures Dance fields included when a program/dance is
  // shared, copied, or exported to PDF (issue #1434). A working preference,
  // same shape as its sibling above.
  'program_dance_share_fields': _preference,
  // The filter sections hidden from the Collection Filters panel and the dance
  // picker (issue #1419): a JSON list of opaque section ids — built-in slugs
  // (`status`, `tags`, …) and `cf:<customFieldDefId>`. No labels or values, so
  // nothing personal; a custom-field id is meaningless on a device without that
  // field and is simply ignored there. A working preference like its sibling.
  'collection_hidden_facets': _preference,
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
  // restore by backup_settings_schema.dart). A figure of your own's column id
  // is `userFigure:<id>` (#1023): the opaque id of a glossary entry, a soft
  // reference (sync-spec §6.15) that is inert on a device without the figure.
  'program_matrix_columns': _preference,

  // Device Sync transport values are not ordinary preferences. The sync ID is
  // the address of a shared store and may contain personal information; the
  // device ID is an opaque per-attachment routing identifier.
  'sync_id': const DataClassification(
    term: DpvTerm.unclassifiedPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.storeAddress,
    note:
        'The address of the shared store this device syncs with — in effect a '
        'path on the sync server, which is how the server handles it. It is '
        'not a credential and not a secret: the user is expected to hand it to '
        'another person so the two can sync together. Being user-chosen it may '
        'contain personal information, so it leaves the device over the '
        'network only to the configured sync origin, and is never recoverably '
        'retained or logged by the server or a proxy — not because it is '
        'confidential, but because the operator has no use for it and it names '
        'where a user keeps their library. It is never adopted from a peer, '
        'which would repoint this device at another store. Local persistence '
        'is governed by this settings classification. The status surface can '
        'also show it and copy it to the system clipboard when the user asks, '
        'so the device that holds it can be joined by another without the '
        'phrase having been written down at pairing; that path is '
        'user-initiated and stays on the device.',
  ),
  'sync_device_id': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.protocolIdentifier,
    note:
        'Opaque per-attachment routing identifier, minted anew each time the '
        'device attaches so that the identifier itself never links one '
        'attachment to the next. Synced content and its blob hashes can '
        'still be correlated by the operator; this removes only the '
        'identifier as a link. It must travel in protocol metadata but must '
        'never be adopted from another device or restored from a backup.',
  ),
  'sync_last_used_fingerprint': const DataClassification(
    term: DpvTerm.unclassifiedPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceScoped,
    note:
        'A set of salted, slow verifiers for previously configured store '
        'addresses, used only to recognise one this device has already synced '
        'with after detach. They are salted and slow so the marker cannot be '
        'turned back into the address it stands for, which names where a user '
        'keeps their library; the derived values are never transmitted, '
        'adopted from a peer, or restored from a backup.',
  ),

  'sync_enabled': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Per-installation Device Sync consent. Never synced and never restored from a backup: consent given on one device is not consent on another.',
  ),
  'sync_endpoint': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'The Athenaeum server this installation pairs and syncs with. Never synced, because a synced endpoint would let one device silently redirect another, and never restored from a backup.',
  ),
  'sync_wifi_only': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Per-installation preference to sync only on WiFi. It is a statement about this device\'s connection, so it never syncs or travels in a backup.',
  ),
  'sync_exclude_imports': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Per-installation toggle that trims what this device publishes. It is a statement about this device\'s upload budget, not the library, so it never syncs or travels in a backup.',
  ),
  'sync_last_success_at': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.deviceScoped,
    note:
        'Time of this installation\'s last completed sync pass, used only for the local status surface and expiry warning. Never synced or restored from a backup.',
  ),

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
  'default_import_tag_names': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'User-chosen list of tag names added to dances imported on their own. '
        "The names reference the user's own tags by their natural key, so it "
        'survives tag re-identification on sync and merge restore; names with '
        'no live tag are ignored.',
  ),
  'default_starting_program': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'Legacy user-authored semantic slot template for manually created '
        'programs (the Starting program). No longer written: it is shown as '
        'the first program template and copied into one at the user\'s first '
        'change to their templates (#2337), and left in place so a device on '
        'an older build keeps it. It contains selected dance '
        'references and caller notes, so it travels with the user preference '
        'in local backups.',
  ),
  // Program templates (#2337): the templates' order (a list of template ids)
  // and the default template's id (or `blank`). The templates themselves are
  // the `program_template:` prefix below.
  'program_template_order': _preference,
  'program_template_default': _preference,
  'auto_size_perform_cards': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Screen-bound: whether a Perform card should fit the screen depends '
        'on the screen, like perform_text_scale below. '
        'deviceLocal, not deviceScoped: it is withheld for what it means on '
        'another screen, not for what it contains, and deviceScoped would '
        'also drop it from the user\'s own backups, which should give it '
        'back on restore. Per-device by the maintainer\'s decision '
        '(settings-sync-scope, 2026-10-29).',
  ),
  'show_individual_perform_timer': _preference,
  'confirm_perform_exit': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'Whether leaving Perform asks first. A habit of '
        'the caller rather than a property of the screen, like '
        'confirm_before_delete, so it travels with their other preferences; '
        'unlike auto_size_perform_cards it does not depend on screen size.',
  ),
  'show_program_slot_caller_notes': _preference,
  // Which Keep items start on in Perform's swap sheet (#2346).
  'perform_swap_defaults': _preference,
  'auto_commit_program_changes': _preference,
  'perform_canonical_view': DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'No longer read or written by this version (Perform lost its '
        'canonical toggle). Kept classified and travelling so older-version '
        'peers and backups, which still use it, round-trip it unchanged.',
  ),
  'perform_stage_mode': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Screen-bound: the stage theme is chosen for the lighting a screen '
        'is read under, like perform_text_scale below. '
        'deviceLocal, not deviceScoped: it is withheld for what it means on '
        'another screen, not for what it contains, and deviceScoped would '
        'also drop it from the user\'s own backups, which should give it '
        'back on restore. Per-device by the maintainer\'s decision '
        '(settings-sync-scope, 2026-10-29).',
  ),
  'perform_text_scale': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Tuned to the screen it was set on. A scale chosen for a phone held at '
        "arm's length is wrong on a laptop driving a projector, but it may "
        'travel in a user-controlled local backup.',
  ),
  'mark_all_sets_status': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A behaviour preference: whether Mark all performed also sets the '
        "program's status (GIG-12). It names no person and holds no content, "
        'and it follows the caller rather than the screen, so it travels like '
        'the other calling-history rules beside it.',
  ),
  'share_set_list_include_title': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A behaviour preference: whether a shared or copied set list (the text '
        'export) includes the program title. It names no person and holds no content. It '
        'never governs the .ccshare or JSON bundle, which always carries the '
        'whole program, and it follows the caller rather than the screen, so '
        'it travels like the other sharing preferences.',
  ),
  'share_set_list_include_caller_band': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A behaviour preference: whether a shared or copied set list (the text '
        'export) includes the caller and band. It names no person and holds no content. It '
        'never governs the .ccshare or JSON bundle, which always carries the '
        'whole program, and it follows the caller rather than the screen, so '
        'it travels like the other sharing preferences.',
  ),
  'share_set_list_include_date_venue': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A behaviour preference: whether a shared or copied set list (the text '
        'export) includes the date, the program\'s start, end and lesson '
        'times, and the venue. It names no person and holds no content. It '
        'never governs the .ccshare or JSON bundle, which always carries the '
        'whole program, and it follows the caller rather than the screen, so '
        'it travels like the other sharing preferences.',
  ),
  'require_event_date_for_history': _preference,
  'require_performed_for_history': _preference,
  'recency_require_event_date': _preference,
  'recency_require_performed': _preference,
  'history_order_ignore_undated': _preference,
  'history_order_ignore_unperformed': _preference,
  'show_performed_toggles': _preference,
  'show_program_pay': _preference,
  'track_history_for_all_callers': _preference,
  'venue_call_count': _preference,

  // -- Installation state ---------------------------------------------------
  'window_frame': _installState,
  'last_backup_at': _installState,
  'seed.initialCollection.completed': _backupLocalState,
  // Records that the one-time custom-field sharing disclosure was shown on
  // this device. A boolean latch; contains no personal data.
  'custom_fields.sharing.disclosed': _backupLocalState,
  // Opt-out latch for the on-launch "convert ECD-tagged dances" prompt: set
  // only when the user checks its "don't show this again" box. Same shape as
  // the custom-field disclosure latch above (a UI dismissal flag, no personal
  // data), so it gets the same classification.
  'ecd_convert_prompt_dismissed': _backupLocalState,
  'update_auto_check': _backupLocalState,
  'calendar_feed_url': const DataClassification(
    term: DpvTerm.unclassifiedPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'The address of the online calendar the calendar import reads (#2352). '
        'Withheld for what it contains: a private calendar\'s secret address '
        'embeds an access token. deviceLocal, not deviceScoped: it means the '
        'same on another device. Never synced, so each device configures its '
        'own (one address per device, maintainer decision); kept out of backup '
        'files too, by the maintainer\'s decision (issue draft review, '
        '2026-11-22), so a restore asks for it again (kBackupSettingsDenylist); '
        'redacted from diagnostics (collectSensitiveTerms) and never put into '
        'a message.',
  ),
  'calendar_import_window_months': _preference,
  // The startup calendar run (#2353): per-installation consent to a network
  // fetch, like update_auto_check, and what it does, which goes with it.
  'calendar_import_on_startup': _backupLocalState,
  'calendar_startup_mode': _backupLocalState,
  // This installation's runs: meaningless on another device.
  'calendar_last_result': _installState,
  'calendar_startup_failures': _installState,
  'calendar_import_title_filter': _preference,
  'update_beta_channel': _backupLocalState,
  'update_dismissed_version': _backupLocalState,
  // The end-of-life date the update manifest announced for *this build*. It
  // describes the binary installed here, so on another install (or after a
  // restore onto a different build) it would warn about a version that is not
  // running — device-scoped, and denylisted from backups. The value is a
  // release version and a date from the project's own manifest: nothing
  // personal.
  'update_retirement_notice': _installState,
  // A user preference (off / weekly / monthly), not backup bookkeeping: the
  // reminder itself fires from `last_backup_at`, which is what must stay
  // local. The backup denylist refused this key from G.5 (#167) until the 2026
  // audit (area 2 row 17) found the two disagreeing; maintainer decision to
  // keep this classification and let the cadence travel in backups.
  'backup_reminder_cadence': _preference,
  '__shareable_text_normalisation_scope__': _backupLocalState,
  // One-time migration and repair markers written by
  // `CompendiumRepositories.ensureMigrated` (declared in
  // `packages/compendium_core/lib/src/storage/database.dart`). Each records
  // that *this database* has had a pass run over its rows; on another install
  // the same marker would claim a pass that never ran there, so every one is
  // installation state and is denylisted from backups
  // (`kBackupSettingsDenylist`). The values are `true`, `"done"` or a version
  // token — nothing personal. The first six were classified when they were
  // added (#1169, #1223, #1346); the nine below predate that template and
  // were only caught when the settings ratchet stopped requiring a `k` prefix
  // (2026 external audit, area 2 row 3, maintainer decision to match the
  // siblings).
  '__derived_rebuild_required__': _installState,
  '__purge_corruption_repair_done__': _installState,
  '__section_rule_version__': _installState,
  '__inverse_pair_normalisation_done__': _installState,
  '__star_promenade_hand_removal_done__': _installState,
  '__grip_single_file_canonical_inclusion_done__': _installState,
  '__chain_hand_backfill_done__': _installState,
  '__promenade_turn_circle_wording_canonical_rebuild_done__': _installState,
  '__compact_dosido_seesaw_canonical_rebuild_done__': _installState,
  '__taxonomy_v33_canonical_rebuild_done__': _installState,
  '__taxonomy_v34_canonical_rebuild_done__': _installState,
  '__modifier_container_canonical_rebuild_done__': _installState,
  '__taxonomy_v37_canonical_rebuild_done__': _installState,
  '__taxonomy_v38_canonical_rebuild_done__': _installState,
  '__taxonomy_v39_canonical_rebuild_done__': _installState,
  '__ecd_taxonomy_canonical_rebuild_done__': _installState,
  '__square_taxonomy_canonical_rebuild_done__': _installState,
  '__taxonomy_v35_figure_normalization_done__': _installState,
  '__callersbox_roll_away_role_repair_done__': _installState,
  '__normalisation_derived_index_repair_done__': _installState,
  // Added with its pass (maintainer decision search-index (a), 2026-10-29).
  // Like its siblings it says the pass ran over *this* database's index, which
  // a restore onto another install would make false; its value is `"done"`.
  '__custom_field_index_repair_done__': _installState,
  // Added with its pass (follow-up row 35: a whole-number custom value indexed
  // as "3.0"). Like its siblings it says the pass ran over *this* database's
  // index, which a restore onto another install would make false, so it must
  // not travel or sync; its value is `"done"`.
  '__custom_number_index_repair_done__': _installState,
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
        '(editor_draft:<id>, or editor_draft:new:<editor id> for a dance not '
        'yet saved). Unsaved user-authored choreography text that '
        'must never leave this device by any route, including a local '
        'backup file — see backup_service.dart.',
  ),
  'program_editor_draft:': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceScoped,
    note:
        'Transient program-editor autosave draft, keyed per program '
        '(program_editor_draft:<id>, or program_editor_draft:new:<editor id> '
        'for a program not yet saved). Same rationale as editor_draft:.',
  ),
  // One program template per key (#2337), keyed by the template's id.
  'program_template:': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'A user-authored program template (program_template:<id>): its name '
        'and an ordered list of slots — dance references, caller notes, '
        'breaks and free text, which can contain whatever the caller types, '
        'and slot rules (#2338), each a label the caller types and a '
        'reference to one of their own saved searches (the id of a '
        'saved_search: value). '
        'The user\'s own planning data; it syncs to their devices and travels '
        'in local backups, like the Starting program it replaces.',
  ),
  // Each sync device's capability record (#709): which sync capabilities its
  // build understands, so a device holds back data a peer could not read.
  'sync_capabilities:': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'Sync protocol metadata, keyed per attachment '
        '(sync_capabilities:<deviceId>): the names of the sync capabilities '
        'the device\'s build understands, nothing about the user. Travels so '
        'every device can see what the others can read (#709 capability '
        'gate). The device id in the key is the same protocolIdentifier every '
        'manifest already carries. Never restored from a backup '
        '(backup_service.dart denylists the prefix), since only its own device '
        'may write it, apart from the tombstone written when a device is '
        'removed from the store. Erased, not tombstoned, on detach '
        '(SyncLocalRepository.clearOnDetach), so the device ids of a store '
        'this device has left never reach the next one.',
  ),
  // One saved search per key (#2325): the user's own search, stored under a
  // name. Shareable user configuration, like custom_dialects, behind the
  // savedSearches.v1 sync capability.
  'saved_search:': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'One saved search per key (saved_search:<id>): the user\'s own search '
        'text, filters and sort under a name they chose, with the ids of '
        'their tags, authors, sources, difficulty levels, venue records, '
        'custom fields and figures of their own, and the folded text of a '
        'venue typed by name (text:<venue>). Their own configuration, which '
        'follows them to their other devices. The search text and custom-field '
        'values are free text the user typed, so they can contain a name (an '
        'Author search for a choreographer): the subject is the app user, '
        'whose search it is, as the maintainer classified it, and nothing '
        'else here names anyone. A '
        'deletion is a tombstone that keeps the value until the record is '
        'purged. Held back from peers until every device advertises '
        'savedSearches.v1.',
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
