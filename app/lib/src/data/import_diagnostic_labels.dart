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
  'cc_related_dance_unresolved',
};

/// Localized message for an [ImportIssue] surfaced in the import review.
String importIssueMessage(AppLocalizations l10n, ImportIssue issue) {
  final localized = _localizedImportIssue(l10n, issue);
  if (localized != null) return localized;
  // Unmapped code: generic, non-leaking fallback. The diagnostic English is
  // appended only in debug builds to aid development — never in release
  // (CWE-209).
  return kDebugMode
      ? '${l10n.importIssueGeneric} [${issue.code}: ${issue.message}]'
      : l10n.importIssueGeneric;
}

/// Localized name of the dance date field a date-parsing note concerns, from the
/// safe `composed`/`revised` discriminator carried on the issue. Returns `null`
/// for a missing/unrecognized field so the caller degrades to the generic
/// message rather than mislabeling the field.
String? _dateField(AppLocalizations l10n, Object? field) => switch (field) {
  'composed' => l10n.importDateFieldComposed,
  'revised' => l10n.importDateFieldRevised,
  _ => null,
};

String? _localizedImportIssue(AppLocalizations l10n, ImportIssue issue) {
  final data = issue.data;
  switch (issue.code) {
    case 'archive_program_empty_slot':
    case 'cc_program_empty_slot':
      return l10n.importIssueProgramEmptySlot;
    case 'archive_program_unresolved_dance':
    case 'cc_program_unresolved_dance':
      return l10n.importIssueProgramUnresolvedDance;
    case 'archive_program_unresolved_venue':
      return l10n.importIssueProgramUnresolvedVenue;
    case 'archive_read_error':
      return l10n.importIssueArchiveReadError;
    case 'archive_read_warning':
      return l10n.importIssueArchiveReadWarning;
    case 'callersbox_direction_unmapped':
      return l10n.importIssueDirectionUnmapped;
    case 'callersbox_formation_unclassified':
    case 'contradb_formation_unclassified':
    case 'contradb_html_formation_unclassified':
      return l10n.importIssueFormationUnclassified;
    case 'callersbox_phrase_structure_unreadable':
      return l10n.importIssuePhraseStructureUnreadable;
    case 'callersbox_progression_unmapped':
      return l10n.importIssueProgressionUnmapped;
    case 'callersbox_search_tier':
      return l10n.importIssueMetadataOnlyStub;
    case 'cc_date_assumed_mdy':
      final field = _dateField(l10n, data['field']);
      return field == null ? null : l10n.importIssueDateAssumedMdy(field);
    case 'cc_date_reduced_precision':
      final year = data['year'];
      final field = _dateField(l10n, data['field']);
      // Fall back to the generic message rather than render "year 0" or
      // mislabel the field when the recovered year / field is absent/ill-typed.
      return (year is int && field != null)
          ? l10n.importIssueDateReducedPrecision(year, field)
          : null;
    case 'cc_missing_title':
    case 'contradb_html_missing_title':
      return l10n.importIssueMissingTitle;
    case 'cc_program_unparsed_date':
      return l10n.importIssueProgramUnparsedDate;
    case 'cc_rating_out_of_range':
      return l10n.importIssueRatingOutOfRange;
    case 'cc_unmapped_formation':
      return l10n.importIssueUnmappedFormation;
    case 'cc_unmapped_level':
      return l10n.importIssueUnmappedLevel;
    case 'cc_unmapped_progression':
      return l10n.importIssueUnmappedProgression;
    case 'cc_unmapped_type':
      return l10n.importIssueUnmappedType;
    case 'cc_unparsed_date':
      final field = _dateField(l10n, data['field']);
      return field == null ? null : l10n.importIssueUnparsedDate(field);
    case 'cc_unparsed_rating':
      return l10n.importIssueUnparsedRating;
    case 'contradb_figures_unreadable':
      return l10n.importIssueFiguresUnreadable;
    case 'contradb_html_beats_unreadable':
      return l10n.importIssueBeatsUnreadable;
    case 'contradb_html_no_figures_table':
      return l10n.importIssueNoFiguresTable;
    case 'contradb_move_fallback':
      // Both variants (malformed figure / unknown move) carry the safe 0-based
      // figure index; surface it as a 1-based position. The untrusted source
      // move name is never shown.
      return issue.figureIndex == null
          ? l10n.importIssueMoveFallback
          : l10n.importIssueMoveFallbackAt(issue.figureIndex! + 1);
    case 'contradb_param_unmapped':
      // Two variants share this code: a named-parameter conversion failure
      // (carries a safe taxonomy parameter name) and a positional-count
      // overflow (carries safe counts). The untrusted source move name and raw
      // value are never surfaced.
      if (data['param'] is String) {
        return l10n.importIssueParamValueUnmapped(data['param'] as String);
      }
      if (data['provided'] is int && data['mapped'] is int) {
        return l10n.importIssueParamCountUnmapped(
          data['provided'] as int,
          data['mapped'] as int,
        );
      }
      return l10n.importIssueParamUnmapped;
    case 'cc_related_dance_unresolved':
      return l10n.importIssueRelatedDanceUnresolved;
    default:
      return null;
  }
}

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
