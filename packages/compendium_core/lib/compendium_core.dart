/// Pure-Dart domain core for Caller's Compendium.
///
/// Contains the domain model, figure taxonomy, dialect engine, and import
/// parsers. This package must remain free of Flutter dependencies so the
/// domain layer stays portable and independently testable (ADR-001).
library;

export 'src/analysis/half_calling_stats.dart';
export 'src/analysis/program_matrix.dart';
export 'src/diagnostics/crash_log_record.dart';
export 'src/diagnostics/crash_redactor.dart';
export 'src/dialect/canonicalize.dart';
export 'src/dialect/dialect.dart';
export 'src/dialect/renderer.dart';
export 'src/dialect/substitution.dart' show Substitutor;
export 'src/export/dance_text.dart';
export 'src/export/program_text.dart';
export 'src/imports/callers_companion_mapping.dart';
export 'src/imports/callers_companion_programs.dart';
export 'src/imports/callers_companion_usr_adapter.dart';
export 'src/imports/callers_companion_usr_archive.dart';
export 'src/imports/callers_companion_usr_import.dart';
export 'src/imports/callersbox_adapter.dart';
export 'src/imports/compendium_archive_import.dart';
export 'src/imports/callersbox_search.dart';
export 'src/imports/callers_companion_text_adapter.dart';
export 'src/imports/dedupe.dart';
export 'src/imports/contradb_adapter.dart';
export 'src/imports/contradb_html_adapter.dart';
export 'src/imports/contradb_program.dart';
export 'src/imports/contradb_program_index.dart';
export 'src/imports/contradb_search.dart';
export 'src/imports/figure_parser.dart';
export 'src/imports/figure_text_scrub.dart';
export 'src/imports/free_text_entry.dart';
export 'src/imports/fmp/fmp_reader.dart';
export 'src/imports/generic_json_adapter.dart';
export 'src/imports/import_error.dart';
export 'src/imports/import_pipeline.dart';
export 'src/imports/raw_record.dart';
export 'src/imports/reparse_custom_figures.dart';
export 'src/imports/shorthand_mappings.dart';
export 'src/imports/source_adapter.dart';
export 'src/imports/structured_draft.dart';
export 'src/model/choreographer.dart';
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
export 'src/search/search_sort.dart';
export 'src/search/title_sort_key.dart';
export 'src/search/filter.dart';
export 'src/search/filter_compiler.dart';
export 'src/search/fts_query.dart';
export 'src/search/search_enrichment.dart';
export 'src/serialization/archive_codec.dart';
export 'src/serialization/archive_service.dart';
export 'src/serialization/compendium_archive.dart';
export 'src/serialization/figure_codec.dart';
export 'src/storage/database.dart'
    show
        CompendiumDatabase,
        derivedRebuildRequiredKey,
        purgeCorruptionRepairDoneKey,
        kCompendiumSchemaVersion;
export 'src/storage/repositories/choreographer_repository.dart';
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
export 'src/storage/repositories/snapshot_repository.dart';
export 'src/storage/repositories/tag_repository.dart';
export 'src/storage/repositories/venue_repository.dart';
export 'src/taxonomy/contra_taxonomy.dart';
export 'src/taxonomy/gate_facing.dart';
export 'src/taxonomy/move_def.dart';
export 'src/taxonomy/param_types.dart';
export 'src/taxonomy/taxonomy.dart';
export 'src/util/colour_name_seed.dart';
export 'src/util/inline_emphasis.dart';
export 'src/util/text_sanitizer.dart';
export 'src/util/uuid.dart';
export 'src/validation/validation.dart';
