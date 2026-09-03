/// Pure-Dart domain core for Caller's Compendium.
///
/// Contains the domain model, figure taxonomy, dialect engine, and import
/// parsers. This package must remain free of Flutter dependencies so the
/// domain layer stays portable and independently testable (ADR-001).
library;

export 'src/analysis/half_calling_stats.dart';
export 'src/analysis/matrix_column_config.dart';
export 'src/analysis/program_matrix.dart';
export 'src/diagnostics/crash_log_record.dart';
export 'src/diagnostics/crash_redactor.dart';
export 'src/dialect/canonicalize.dart';
export 'src/dialect/dialect.dart';
export 'src/dialect/renderer.dart';
export 'src/dialect/substitution.dart' show Substitutor;
export 'src/export/dance_text.dart';
export 'src/export/export_labels.dart';
export 'src/export/program_text.dart';
export 'src/imports/author_tokenizer.dart';
export 'src/imports/callers_companion_mapping.dart';
export 'src/imports/callers_companion_programs.dart';
export 'src/imports/callers_companion_related_dances.dart';
export 'src/imports/callers_companion_usr_adapter.dart';
export 'src/imports/callers_companion_usr_archive.dart';
export 'src/imports/callers_companion_usr_import.dart';
export 'src/imports/callersbox_adapter.dart';
export 'src/imports/callersbox_figure_dialect.dart';
export 'src/imports/compendium_archive_import.dart';
export 'src/imports/callersbox_search.dart';
export 'src/imports/callers_companion_text_adapter.dart';
export 'src/imports/dedupe.dart';
export 'src/imports/contradb_adapter.dart';
export 'src/imports/contradb_figure_dialect.dart';
export 'src/imports/contradb_html_adapter.dart';
export 'src/imports/contradb_program.dart';
export 'src/imports/contradb_program_index.dart';
export 'src/imports/contradb_search.dart';
export 'src/imports/figure_diff.dart';
export 'src/imports/figure_parser.dart';
export 'src/imports/figure_front_end_fan_out.dart';
export 'src/imports/figure_text_scrub.dart';
export 'src/imports/free_text_entry.dart';
export 'src/imports/fmp/fmp_reader.dart';
export 'src/imports/generic_json_adapter.dart';
export 'src/imports/import_error.dart';
export 'src/imports/import_pipeline.dart';
export 'src/imports/published_collection.dart';
export 'src/imports/insert_call_shorthands.dart';
export 'src/imports/program_import_marker.dart';
export 'src/imports/program_slot_note.dart';
export 'src/imports/raw_record.dart';
export 'src/imports/reparse_custom_figures.dart';
export 'src/imports/shorthand_mappings.dart';
export 'src/imports/share_metadata_import.dart';
export 'src/imports/source_adapter.dart';
export 'src/imports/structured_draft.dart';
export 'src/imports/venue_dedupe.dart';
export 'src/model/choreographer.dart';
export 'src/model/collection_import_event.dart';
export 'src/model/custom_field.dart';
export 'src/model/dance.dart';
export 'src/model/dance_link.dart';
export 'src/model/enums.dart';
export 'src/model/figure.dart';
export 'src/model/formation.dart';
export 'src/model/partial_date.dart';
export 'src/model/phrase_structure.dart';
export 'src/model/program.dart';
export 'src/model/provenance.dart';
export 'src/model/published_source.dart';
export 'src/model/source_citation.dart';
export 'src/model/tag.dart';
export 'src/model/venue.dart';
export 'src/privacy/data_classification.dart';
export 'src/privacy/field_registry.dart';
export 'src/privacy/settings_registry.dart';
export 'src/search/search_sort.dart';
export 'src/search/title_sort_key.dart';
export 'src/search/filter.dart';
export 'src/storage/calling_history_scope.dart'
    show normalizeCallingHistoryCaller;
export 'src/storage/shareable_text.dart';
export 'src/search/filter_compiler.dart';
export 'src/search/fts_query.dart';
export 'src/search/search_enrichment.dart';
export 'src/serialization/archive_codec.dart';
export 'src/serialization/archive_service.dart';
export 'src/serialization/compendium_archive.dart';
export 'src/serialization/figure_codec.dart';
export 'src/sync/canonical_json.dart';
export 'src/sync/sync_record_kind.dart';
export 'src/sync/sync_codec.dart';
export 'src/sync/sync_id.dart'
    show
        SyncId,
        deriveSyncIdKey,
        decodeSyncCredential,
        encodeSyncCredential,
        estimateSyncIdStrengthBits,
        generateSyncId,
        isValidSyncId,
        normalizeSyncId,
        syncIdMaxCodePoints,
        syncIdMaxWordCodePoints,
        syncIdStrengthWarningBits,
        syncIdWordCount,
        validateSyncId;
export 'src/sync/server/sync_id_server.dart';
export 'src/sync/wire_mapping.dart';
export 'src/snippet/snippet_library.dart';
export 'src/snippet/snippet_signature.dart';
export 'src/snippet/walkthrough_assembler.dart';
export 'src/storage/database.dart'
    show
        CompendiumDatabase,
        derivedRebuildRequiredKey,
        inversePairNormalisationDoneKey,
        purgeCorruptionRepairDoneKey,
        sectionRuleVersionKey,
        starPromenadeHandRemovalDoneKey,
        gripSingleFileCanonicalInclusionDoneKey,
        chainHandBackfillDoneKey,
        promenadeTurnCircleWordingCanonicalRebuildDoneKey,
        compactDosidoSeesawCanonicalRebuildDoneKey,
        shareableTextNormalisationScopeKey,
        kSectionRuleVersion,
        kCompendiumSchemaVersion,
        kMinSupportedSchemaVersion;
// Only the pure pieces of `existence.dart` are public: the rule itself, the
// tick it is pinned to, and the unix-seconds conversion, all of which the tests
// exercise directly.
//
// The SQL writers (`applyUpsertExistence`, `stampExistenceTransition`,
// `adoptTombstonedNaturalKey`, `seedExistenceIfMissing`) are deliberately NOT
// exported. They take a [CompendiumDatabase] and mutate rows in place, so
// exporting them would offer callers a way around the repository layer — and
// "all access through repositories" is the storage design's central rule
// (docs/design/storage.md), not a convention. Every existence stamp has to go
// through the repository that also maintains the row's other invariants, so
// keep these internal to `lib/src/storage/`.
export 'src/storage/existence.dart'
    show existenceStampTick, nextExistenceStamp, unixSeconds;
export 'src/storage/repositories/choreographer_repository.dart';
export 'src/storage/repositories/collection_import_event_repository.dart';
export 'src/storage/repositories/custom_field_repository.dart'
    show
        CustomFieldDefRepository,
        decodeCustomFieldValue,
        encodeCustomFieldValue;
export 'src/storage/repositories/dance_repository.dart';
export 'src/storage/repositories/program_repository.dart';
export 'src/storage/repositories/published_source_repository.dart';
export 'src/storage/repositories/repositories.dart';
export 'src/storage/repositories/settings_repository.dart';
export 'src/storage/repositories/sync_local_repository.dart';
export 'src/storage/repositories/tag_repository.dart';
export 'src/storage/repositories/venue_repository.dart';
export 'src/taxonomy/contra_taxonomy.dart';
export 'src/taxonomy/gate_facing.dart';
export 'src/taxonomy/move_def.dart';
export 'src/taxonomy/offerable_dancer_sets.dart';
export 'src/taxonomy/param_types.dart';
export 'src/taxonomy/taxonomy.dart';
export 'src/util/argb.dart';
export 'src/util/colour_name_seed.dart';
export 'src/util/inline_emphasis.dart';
export 'src/util/text_sanitizer.dart';
export 'src/util/uuid.dart';
export 'src/validation/validation.dart';
