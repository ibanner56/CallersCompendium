import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../utils/safe_name.dart';
import '../utils/slot_dance_title.dart';
import '../widgets/program_status_labels.dart';
import 'export_labels_l10n.dart';
import 'share_sanitization.dart';

/// The programs as a CSV spreadsheet (#2333): a header row, then one row per
/// program, in the order given (the Programs list's own order).
///
/// Columns: title, event date, status, venue, caller, band, dancer level, pay
/// amount, pay currency, notes, number of dances, and the dances in order, one
/// title per line with alternates marked.
///
/// While the caller hides pay (**Show pay** off, #2355), pass [includePay]
/// `false`: the file then has **no pay columns at all**, not empty ones that
/// would read as "no pay recorded" (maintainer decision on #2333).
///
/// The file follows the share rules except for pay (ruling 2, maintainer,
/// feature triage, 2026-11-22), so each program goes through
/// [sanitizeProgramForCsv], which differs from the share files'
/// [sanitizeProgramForShare] only by keeping pay:
///
/// * the venue is its name only, through [resolveSanitizedVenueLabelParts]:
///   never its street address, and there is no contacts column, so the
///   per-export contact dialog never applies;
/// * the Perform dialect and the archived state are left out (the view the
///   user exports, archived programs included or not, is their choice).
///
/// Event dates are ISO calendar dates (`YYYY-MM-DD`), read from the stored
/// date's own year, month and day as every screen shows it, so a spreadsheet
/// in any locale reads them as dates and no time zone moves them. Pay is a
/// plain decimal with a `.` ([formatPayMinorUnits]). The separator and
/// encoding never follow the region ([encodeCsv]).
///
/// [danceFor] finds a slot's dance, deleted ones included; a slot whose dance
/// is gone reads as the app's "Deleted dance". The dances listed are the
/// program's output ([Program.outputGrouped]), so alternates the program hides
/// are left out, as in its set list and PDF; break and note slots are not
/// dances and are not listed. The number of dances counts the main dances, not
/// the alternates.
String buildProgramsCsv(
  Iterable<Program> programs, {
  required AppLocalizations l10n,
  required Dance? Function(String danceId) danceFor,
  Map<String, Venue> venuesById = const {},
  bool includePay = true,
}) => encodeCsv(
  buildProgramsCsvRows(
    programs,
    l10n: l10n,
    danceFor: danceFor,
    venuesById: venuesById,
    includePay: includePay,
  ),
);

/// The header and one row per program that [buildProgramsCsv] encodes: plain
/// strings, so [encodeCsv] can run on another isolate while everything that
/// needs [l10n] (which cannot cross an isolate) has already been resolved here.
List<List<String>> buildProgramsCsvRows(
  Iterable<Program> programs, {
  required AppLocalizations l10n,
  required Dance? Function(String danceId) danceFor,
  Map<String, Venue> venuesById = const {},
  bool includePay = true,
}) {
  String titleOf(String danceId) => switch (danceFor(danceId)) {
    final dance? => slotDanceTitle(l10n, dance),
    null => l10n.programsBlankedDanceTitle,
  };
  // The set list's own "Alternate:" label, with the language's separator.
  final alternate = programExportLabels(
    l10n,
  ).labelled(l10n.exportIncludeFiguresAlternate);

  final rows = <List<String>>[
    [
      l10n.csvColumnTitle,
      l10n.csvColumnEventDate,
      l10n.csvColumnStatus,
      l10n.csvColumnVenue,
      l10n.csvColumnCaller,
      l10n.csvColumnBand,
      l10n.csvColumnDancerLevel,
      if (includePay) ...[l10n.csvColumnPayAmount, l10n.csvColumnPayCurrency],
      l10n.csvColumnNotes,
      l10n.csvColumnDanceCount,
      l10n.csvColumnDances,
    ],
  ];
  for (final raw in programs) {
    final program = sanitizeProgramForCsv(raw);
    final lines = <String>[];
    var count = 0;
    for (final group in program.outputGrouped) {
      // A leading or orphaned alternate is kept as its group's primary
      // ([Program.grouped]); it is still an alternate, as the set list marks
      // it, so it is marked and not counted.
      for (final slot in [group.primary, ...group.alternates]) {
        final id = slot.danceId;
        if (id == null) continue;
        if (slot.isAlt) {
          lines.add('$alternate${titleOf(id)}');
        } else {
          lines.add(titleOf(id));
          count++;
        }
      }
    }
    final pay = program.payMinorUnits;
    final currency = program.payCurrency;
    rows.add([
      program.title.trim(),
      switch (program.eventDate) {
        final date? => isoDate(date),
        null => '',
      },
      programStatusLabel(l10n, program.status),
      resolveSanitizedVenueLabelParts(
            program.venueId,
            program.venue,
            venuesById,
          ) ??
          '',
      program.caller?.trim() ?? '',
      program.band?.trim() ?? '',
      program.dancerLevel?.trim() ?? '',
      if (includePay) ...[
        pay != null && currency != null
            ? formatPayMinorUnits(pay, currency)
            : '',
        pay != null && currency != null ? currency : '',
      ],
      program.notes.trim(),
      count.toString(),
      lines.join('\n'),
    ]);
  }
  return rows;
}

/// The file name for a programs CSV exported on [date]:
/// `<stem>_yyyy-MM-dd.csv`, path-safe. [stem] is the localized word for
/// programs.
String programsCsvFileName(String stem, DateTime date) =>
    '${shareFileBaseName(stem, fallback: 'programs', eventDate: date)}'
    '.$csvExtension';
