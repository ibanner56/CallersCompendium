import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../data/show_program_pay_scope.dart';
import '../export/csv_export.dart';
import '../export/programs_csv.dart';
import 'export_guard.dart';

/// Exports programs as a CSV spreadsheet (#2333) and asks how to deliver it.
///
/// [programIds] are the programs in the Programs list's current view, in its
/// order: archived programs are among them only while **Show archived** is on.
/// Deleted programs are never exported.
///
/// While **Show pay** is off ([ShowProgramPayScope], #2355) the file has no
/// pay columns and the dialog says why, so the caller can turn it back on
/// (maintainer decision on #2333).
///
/// Everything read from [context] is resolved before the first await, as in
/// `exportDancesCsv`; the share sheet anchors to [origin], or to the centre of
/// the screen without one. Loading and building run under [guardExport], and
/// delivery under the [CsvExportDelivery]'s own guards.
Future<void> exportProgramsCsv(
  BuildContext context, {
  required List<String> programIds,
  CsvExportDelivery delivery = const CsvExportDelivery(),
  Rect? origin,
  required String source,
  DateTime Function() now = DateTime.now,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final repos = RepositoriesScope.of(context);
  final includePay = ShowProgramPayScope.of(context);
  final size = MediaQuery.sizeOf(context);
  final anchor =
      origin ??
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 1,
        height: 1,
      );

  return guardExport(messenger, l10n.exportCsvError, () async {
    final byId = {
      for (final p in await repos.programs.getByIds(programIds)) p.id: p,
    };
    final programs = [for (final id in programIds) ?byId[id]];
    final danceIds = {
      for (final program in programs)
        for (final slot in program.slots) ?slot.danceId,
    };
    final dances = {
      for (final d in await repos.dances.getByIds(
        danceIds,
        includeDeleted: true,
      ))
        d.id: d,
    };
    final venues = {for (final v in await repos.venues.listAll()) v.id: v};
    final csv = buildProgramsCsv(
      programs,
      l10n: l10n,
      danceFor: (id) => dances[id],
      venuesById: venues,
      includePay: includePay,
    );
    if (!context.mounted) return;
    await delivery.deliver(
      context,
      csv: csv,
      fileName: programsCsvFileName(l10n.csvProgramsFileStem, now()),
      subject: l10n.csvProgramsFileStem,
      sharePositionOrigin: anchor,
      source: source,
      notice: includePay ? null : l10n.exportCsvPayHiddenNotice,
    );
  }, source: source);
}
