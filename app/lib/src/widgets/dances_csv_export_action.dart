import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/canonical_discouraged_terms_scope.dart';
import '../data/repositories_scope.dart';
import '../data/user_figures_scope.dart';
import '../export/csv_export.dart';
import '../export/dances_csv.dart';
import 'export_guard.dart';

/// Exports dances as a CSV spreadsheet (#2332) and asks how to deliver it.
///
/// [danceIds] are the dances to export, as the Collection's selection holds
/// them, including any the current search hides; `null` exports every dance in
/// the collection (Settings ▸ General ▸ Backup & restore). Deleted dances are
/// never exported.
///
/// Everything read from [context] (repositories, dialects, the renderer that
/// knows the user's own figures, and [origin]) is resolved before the first
/// await. [origin] anchors the share sheet (iPad and macOS need one); without
/// it the sheet anchors to the centre of the screen, as the dance screen's
/// compact menu does. Loading
/// and building run under [guardExport], and delivery under the
/// [CsvExportDelivery]'s own guards, so every failure is logged and shown.
Future<void> exportDancesCsv(
  BuildContext context, {
  Iterable<String>? danceIds,
  CsvExportDelivery delivery = const CsvExportDelivery(),
  Rect? origin,
  required String source,
  DateTime Function() now = DateTime.now,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final repos = RepositoriesScope.of(context);
  final dialects =
      ActiveDialectScope.maybeOf(context) ?? DialectsByForm.defaults;
  final renderer = UserFiguresScope.rendererOf(context);
  final canonicalize = CanonicalDiscouragedTermsScope.of(context);
  final ids = danceIds?.toList();
  final size = MediaQuery.sizeOf(context);
  final anchor =
      origin ??
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 1,
        height: 1,
      );

  return guardExport(messenger, l10n.exportCsvError, () async {
    final dances = ids == null
        ? await repos.dances.listAll()
        : await repos.dances.getByIds(ids);
    final lookups = await DancesCsvLookups.load(repos);
    final rows = buildDancesCsvRows(
      dances,
      l10n: l10n,
      dialects: dialects,
      renderer: renderer,
      canonicalizeDiscouragedTerms: canonicalize,
      lookups: lookups,
    );
    final csv = await encodeCsvOffUiIsolate(rows);
    if (!context.mounted) return;
    await delivery.deliver(
      context,
      csv: csv,
      fileName: dancesCsvFileName(l10n.csvDancesFileStem, now()),
      subject: l10n.csvDancesFileStem,
      sharePositionOrigin: anchor,
      source: source,
    );
  }, source: source);
}
