import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

/// Localized presentation of the core import diagnostics rendered directly in
/// the import review screen: per-record [ImportError]s and per-draft/per-program
/// [ImportIssue] notes.
///
/// The core adapters keep a stable discriminator on each diagnostic — an
/// [ImportIssue.code] string and an [ImportError.stage] — while their `message`
/// is an internal English diagnostic that is **not** displayed in a localized
/// UI. This mapper turns those discriminators into localized strings at the
/// presentation boundary, mirroring `import_error_labels.dart`.
///
/// Security (CWE-209): the returned strings are generic, user-safe prose. They
/// never echo raw lower-layer/parser text, file paths, or untrusted external
/// values (raw move names, pasted level/type/formation strings, JSON/HTML
/// parser output). Those live only on the diagnostic's `message`/`toString`
/// (logs) — for an unmapped code the raw detail is appended only under
/// [kDebugMode], never in a release build.

/// The [ImportIssue] codes this mapper localizes explicitly. Any other code
/// falls back to [AppLocalizations.importIssueGeneric]. Exposed for the coverage
/// test that guards against a silent English leak.
const Set<String> mappedImportIssueCodes = {
  'archive_program_empty_slot',
  'archive_program_unresolved_dance',
  'archive_program_unresolved_venue',
  'archive_read_error',
  'archive_read_warning',
  'callersbox_direction_unmapped',
  'callersbox_formation_unclassified',
  'callersbox_phrase_structure_unreadable',
  'callersbox_progression_unmapped',
  'callersbox_search_tier',
  'cc_date_assumed_mdy',
  'cc_date_reduced_precision',
  'cc_missing_title',
  'cc_program_empty_slot',
  'cc_program_unparsed_date',
  'cc_program_unresolved_dance',
  'cc_rating_out_of_range',
  'cc_unmapped_formation',
  'cc_unmapped_level',
  'cc_unmapped_progression',
  'cc_unmapped_type',
  'cc_unparsed_date',
  'cc_unparsed_rating',
  'contradb_figures_unreadable',
  'contradb_formation_unclassified',
  'contradb_html_beats_unreadable',
  'contradb_html_formation_unclassified',
  'contradb_html_missing_title',
  'contradb_html_no_figures_table',
  'contradb_move_fallback',
  'contradb_param_unmapped',
};

/// Localized message for an [ImportIssue] surfaced in the import review.
String importIssueMessage(AppLocalizations l10n, ImportIssue issue) {
  final localized = _localizedImportIssue(l10n, issue.code);
  if (localized != null) return localized;
  // Unmapped code: generic, non-leaking fallback. The diagnostic English is
  // appended only in debug builds to aid development — never in release
  // (CWE-209).
  return kDebugMode
      ? '${l10n.importIssueGeneric} [${issue.code}: ${issue.message}]'
      : l10n.importIssueGeneric;
}

String? _localizedImportIssue(
  AppLocalizations l10n,
  String code,
) => switch (code) {
  'archive_program_empty_slot' => l10n.importIssueProgramEmptySlot,
  'archive_program_unresolved_dance' => l10n.importIssueProgramUnresolvedDance,
  'archive_program_unresolved_venue' => l10n.importIssueProgramUnresolvedVenue,
  'archive_read_error' => l10n.importIssueArchiveReadError,
  'archive_read_warning' => l10n.importIssueArchiveReadWarning,
  'callersbox_direction_unmapped' => l10n.importIssueDirectionUnmapped,
  'callersbox_formation_unclassified' => l10n.importIssueFormationUnclassified,
  'callersbox_phrase_structure_unreadable' =>
    l10n.importIssuePhraseStructureUnreadable,
  'callersbox_progression_unmapped' => l10n.importIssueProgressionUnmapped,
  'callersbox_search_tier' => l10n.importIssueMetadataOnlyStub,
  'cc_date_assumed_mdy' => l10n.importIssueDateAssumedMdy,
  'cc_date_reduced_precision' => l10n.importIssueDateReducedPrecision,
  'cc_missing_title' => l10n.importIssueMissingTitle,
  'cc_program_empty_slot' => l10n.importIssueProgramEmptySlot,
  'cc_program_unparsed_date' => l10n.importIssueProgramUnparsedDate,
  'cc_program_unresolved_dance' => l10n.importIssueProgramUnresolvedDance,
  'cc_rating_out_of_range' => l10n.importIssueRatingOutOfRange,
  'cc_unmapped_formation' => l10n.importIssueUnmappedFormation,
  'cc_unmapped_level' => l10n.importIssueUnmappedLevel,
  'cc_unmapped_progression' => l10n.importIssueUnmappedProgression,
  'cc_unmapped_type' => l10n.importIssueUnmappedType,
  'cc_unparsed_date' => l10n.importIssueUnparsedDate,
  'cc_unparsed_rating' => l10n.importIssueUnparsedRating,
  'contradb_figures_unreadable' => l10n.importIssueFiguresUnreadable,
  'contradb_formation_unclassified' => l10n.importIssueFormationUnclassified,
  'contradb_html_beats_unreadable' => l10n.importIssueBeatsUnreadable,
  'contradb_html_formation_unclassified' =>
    l10n.importIssueFormationUnclassified,
  'contradb_html_missing_title' => l10n.importIssueMissingTitle,
  'contradb_html_no_figures_table' => l10n.importIssueNoFiguresTable,
  'contradb_move_fallback' => l10n.importIssueMoveFallback,
  'contradb_param_unmapped' => l10n.importIssueParamUnmapped,
  _ => null,
};

/// Localized message for a per-record [ImportError] surfaced in the import
/// review. Keyed on the [ImportError.stage] discriminator; the raw `message`
/// (which may wrap opaque parser text) is never rendered — it stays on the
/// error for logging only (CWE-209).
String importRecordErrorMessage(AppLocalizations l10n, ImportError error) =>
    switch (error.stage) {
      ImportStage.discover => l10n.importRecordErrorDiscover,
      ImportStage.fetch => l10n.importRecordErrorFetch,
      ImportStage.parse => l10n.importRecordErrorParse,
      ImportStage.dedupe => l10n.importRecordErrorDedupe,
      ImportStage.commit => l10n.importRecordErrorCommit,
    };
