import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/archive_intake_labels.dart';
import 'package:compendium_app/src/data/archive_intake_service.dart';
import 'package:compendium_app/src/data/import_diagnostic_labels.dart';
import 'package:compendium_app/src/data/migration_error_labels.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/data/validation_issue_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The typed `data` each mapped [ValidationIssue] code needs, so the localizer
/// can be exercised for every arm.
ValidationIssue _validationIssue(String code) => ValidationIssue(
  severity: ValidationSeverity.warning,
  code: code,
  message: 'diagnostic english for $code',
  data: switch (code) {
    'phrase_overflow' || 'phrase_underflow' => {'actual': 68, 'expected': 64},
    'orphaned_alt' => {'position': 2, 'text': 'Petronella'},
    'empty_substitution' => {'source': 'gents'},
    'dialect_collision' => {
      'source': 'gents',
      'existing': 'lords',
      'substitution': 'larks',
    },
    _ => const <String, Object?>{},
  },
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('validationIssueMessage', () {
    test('every mapped code resolves to a non-generic, non-empty string', () {
      for (final code in mappedValidationCodes) {
        final msg = validationIssueMessage(l10n, _validationIssue(code));
        expect(msg, isNotEmpty, reason: code);
        expect(msg, isNot(equals(l10n.validationGeneric)), reason: code);
      }
    });

    test('an unknown code falls back to the generic localized message', () {
      final msg = validationIssueMessage(
        l10n,
        const ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'not_a_real_code',
          message: 'x',
        ),
      );
      // In debug (tests run in debug) the raw diagnostic is appended for devs,
      // but the user-facing generic prefix is always present.
      expect(msg, contains(l10n.validationGeneric));
    });

    test('orphaned_alt without text uses the un-named variant', () {
      final msg = validationIssueMessage(
        l10n,
        const ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'orphaned_alt',
          message: 'x',
          data: {'position': 3},
        ),
      );
      expect(msg, l10n.validationOrphanedAlt(3));
    });

    test('a phrase warning missing its beat counts falls back to generic (no '
        '"0 beats")', () {
      final msg = validationIssueMessage(
        l10n,
        const ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'phrase_overflow',
          message: 'figures total 68 beats; structure expects 64',
        ),
      );
      expect(msg, contains(l10n.validationGeneric));
      expect(msg, isNot(contains(l10n.validationPhraseBeatMismatch(0, 0))));
    });
  });

  group('importIssueMessage', () {
    // The complete set of ImportIssue codes produced by compendium_core's
    // adapters (as of this PR). If core adds a code, this list — and the mapper
    // — must grow, or the code will silently render the generic fallback.
    const producedCodes = {
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

    test('every produced code is mapped (no silent English leak)', () {
      expect(mappedImportIssueCodes, equals(producedCodes));
    });

    test('every mapped code resolves to a non-generic, non-empty string', () {
      for (final code in mappedImportIssueCodes) {
        final msg = importIssueMessage(
          l10n,
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: code,
            message: 'diagnostic english for $code',
          ),
        );
        expect(msg, isNotEmpty, reason: code);
        expect(msg, isNot(equals(l10n.importIssueGeneric)), reason: code);
      }
    });
  });

  group('importIssueMessage — safe placeholders (D2/D3, CWE-209)', () {
    // Each of these codes carries our own SAFE structured data alongside an
    // untrusted external echo in `message`. The localized output must surface
    // the safe value and never the untrusted raw text.
    ImportIssue issue(String code, Map<String, Object?> data, {int? figIdx}) =>
        ImportIssue(
          severity: ImportIssueSeverity.info,
          code: code,
          message: 'raw SECRETVALUE "SECRETVALUE" leaked here',
          figureIndex: figIdx,
          data: data,
        );

    test('cc_unparsed_date surfaces the composed/revised field, not the raw '
        'value', () {
      final composed = importIssueMessage(
        l10n,
        issue('cc_unparsed_date', {'field': 'composed'}),
      );
      final revised = importIssueMessage(
        l10n,
        issue('cc_unparsed_date', {'field': 'revised'}),
      );
      expect(composed, contains(l10n.importDateFieldComposed));
      expect(revised, contains(l10n.importDateFieldRevised));
      expect(composed, isNot(contains('SECRETVALUE')));
      expect(revised, isNot(contains('SECRETVALUE')));
    });

    test('cc_date_reduced_precision surfaces the year and field, not the raw '
        'value', () {
      final msg = importIssueMessage(
        l10n,
        issue('cc_date_reduced_precision', {'field': 'revised', 'year': 2004}),
      );
      expect(msg, contains('2004'));
      expect(msg, contains(l10n.importDateFieldRevised));
      expect(msg, isNot(contains('SECRETVALUE')));
    });

    test('cc_date_assumed_mdy surfaces the field, not the raw value', () {
      final msg = importIssueMessage(
        l10n,
        issue('cc_date_assumed_mdy', {'field': 'composed'}),
      );
      expect(msg, contains(l10n.importDateFieldComposed));
      expect(msg, isNot(contains('SECRETVALUE')));
    });

    test('contradb_param_unmapped surfaces the taxonomy parameter name, not '
        'the source move name/value', () {
      final msg = importIssueMessage(
        l10n,
        issue('contradb_param_unmapped', {'param': 'hand'}),
      );
      expect(msg, contains('hand'));
      expect(msg, isNot(contains('SECRETVALUE')));
    });

    test('contradb_param_unmapped surfaces the safe counts', () {
      final msg = importIssueMessage(
        l10n,
        issue('contradb_param_unmapped', {'provided': 4, 'mapped': 2}),
      );
      expect(msg, contains('4'));
      expect(msg, contains('2'));
      expect(msg, isNot(contains('SECRETVALUE')));
    });

    test('contradb_move_fallback surfaces the 1-based figure position', () {
      final msg = importIssueMessage(
        l10n,
        issue('contradb_move_fallback', const {}, figIdx: 2),
      );
      expect(msg, contains('3'));
      expect(msg, isNot(contains('SECRETVALUE')));
    });

    test('cc_date_reduced_precision missing its year falls back to generic (no '
        '"year 0")', () {
      final msg = importIssueMessage(
        l10n,
        issue('cc_date_reduced_precision', {'field': 'revised'}),
      );
      // Falls back to the generic message (in debug the raw diagnostic is
      // appended, but the misleading "year 0" copy is never produced).
      expect(msg, contains(l10n.importIssueGeneric));
      expect(
        msg,
        isNot(
          contains(
            l10n.importIssueDateReducedPrecision(0, l10n.importDateFieldRevised),
          ),
        ),
      );
    });
  });

  group('importRecordErrorMessage (CWE-209)', () {
    test('never surfaces the raw error message, whatever the stage', () {
      for (final stage in ImportStage.values) {
        final error = ImportError(
          stage: stage,
          source: ProvenanceSource.contradb,
          message: 'SECRET /Users/isaac/private/path.json parse blew up',
          externalId: 'ext-42',
        );
        final msg = importRecordErrorMessage(l10n, error);
        expect(msg, isNotEmpty, reason: stage.name);
        expect(msg, isNot(contains('SECRET')), reason: stage.name);
        expect(msg, isNot(contains('/Users/isaac')), reason: stage.name);
        expect(msg, isNot(contains('ext-42')), reason: stage.name);
      }
    });
  });

  group('archiveIntakeRejectionMessage', () {
    test('every reason resolves to a non-empty string', () {
      for (final reason in ArchiveIntakeRejectionReason.values) {
        expect(archiveIntakeRejectionMessage(l10n, reason), isNotEmpty);
      }
    });
  });

  group('migration error labels', () {
    test('downgrade message is non-empty', () {
      expect(databaseDowngradeMessage(l10n), isNotEmpty);
    });

    test('unknown snapshot cause has no trailing sentence', () {
      expect(
        snapshotCauseSentence(l10n, SnapshotFailureCause.unknown),
        isEmpty,
      );
    });

    test('known snapshot causes weave a cause sentence into the message', () {
      for (final cause in [
        SnapshotFailureCause.diskFull,
        SnapshotFailureCause.unwritableBackupsDir,
      ]) {
        final failure = SnapshotFailure(
          fromVersion: 1,
          toVersion: 2,
          cause: cause,
          error: 'raw /path detail',
        );
        final msg = migrationSnapshotAbortedMessage(l10n, failure);
        expect(msg, contains(snapshotCauseSentence(l10n, cause)));
        expect(msg, isNot(contains('/path')));
      }
    });
  });
}
