import 'package:compendium_core/compendium_core.dart'
    show csvMimeType, encodeCsv;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../data/backup_document.dart'
    show BackupCodecRunner, defaultBackupCodecRunner;
import '../theme/app_motion.dart';
import '../widgets/export_guard.dart';
import 'share_file.dart';

/// [encodeCsv] over [rows] on a worker isolate, so a library-sized sheet is
/// not quoted and joined on the UI isolate. [rows] must be plain strings:
/// everything that needs `AppLocalizations`, which cannot cross an isolate, is
/// resolved before the call. Whatever the encoder throws is rethrown here, for
/// the caller's `guardExport`. [runner] is the same seam the backup codec uses,
/// so widget tests can run it inline.
Future<String> encodeCsvOffUiIsolate(
  List<List<String>> rows, {
  BackupCodecRunner? runner,
}) => (runner ?? defaultBackupCodecRunner)(() => encodeCsv(rows));

/// How the user chose to deliver a CSV spreadsheet export.
enum CsvExportChoice { save, share }

/// Opens the CSV delivery choice dialog.
typedef CsvChoicePicker =
    Future<CsvExportChoice?> Function(BuildContext context, {String? notice});

/// Shows the CSV delivery choice: **Save**, **Share** and **Cancel**. Where
/// the share sheet cannot carry files ([isBundleShareUnsupported], Linux) the
/// Share button reads **Save as…** and saves through the system dialog, as the
/// JSON export's does. Dismissing the dialog returns `null`, which callers
/// treat as Cancel.
///
/// [notice], when given, is shown under the message: the programs CSV uses it
/// to say that pay is left out because **Show pay** is off (#2333).
Future<CsvExportChoice?> showCsvExportChoiceDialog(
  BuildContext context, {
  String? notice,
}) => showDialog<CsvExportChoice>(
  context: context,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.exportCsvDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.exportCsvDialogMessage),
          if (notice != null) ...[
            const SizedBox(height: 12),
            Text(notice, key: const ValueKey('csv-export-notice')),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('csv-export-save'),
          onPressed: () => Navigator.of(context).pop(CsvExportChoice.save),
          child: Text(l10n.exportJsonSave),
        ),
        TextButton(
          key: const ValueKey('csv-export-share'),
          onPressed: () => Navigator.of(context).pop(CsvExportChoice.share),
          child: Text(
            isBundleShareUnsupported()
                ? l10n.exportJsonSaveAs
                : l10n.exportJsonShare,
          ),
        ),
        TextButton(
          key: const ValueKey('csv-export-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exportJsonCancel),
        ),
      ],
    );
  },
  animationStyle: AppMotion.styleFor(context),
);

/// Saves a CSV through the native Save As (desktop) or document-save (mobile)
/// dialog, typed as CSV. A `null` result means the user cancelled.
Future<JsonSaveResult?> saveCsvFile(String csv, String fileName) =>
    saveJsonBundle(
      csv,
      fileName,
      acceptedTypeGroups: [csvTypeGroup()],
      mobileMimeTypes: const [csvMimeType],
      stageFile: writeCsvTempFile,
    );

/// Delivers a CSV spreadsheet export (#2332) through the user's choice
/// of Save or Share, with its snackbars. The counterpart of
/// `JsonExportDelivery` for spreadsheets; every field is a test seam that
/// defaults to the production behaviour.
class CsvExportDelivery {
  const CsvExportDelivery({
    this.choicePicker,
    this.saveInvoker,
    this.shareInvoker,
    this.fileWriter,
  });

  final CsvChoicePicker? choicePicker;

  /// Overrides Save, and Share where [isBundleShareUnsupported] turns it into
  /// Save As.
  final Future<JsonSaveResult?> Function(String csv, String fileName)?
  saveInvoker;
  final Future<void> Function(ShareParams params)? shareInvoker;

  /// Stages the file for the share sheet.
  final BundleFileWriter? fileWriter;

  /// Asks how to deliver [csv], then saves or shares it as [fileName].
  /// [notice] is passed to the choice dialog ([showCsvExportChoiceDialog]).
  ///
  /// Each branch runs under [guardExport] with its own failure message, so a
  /// failure is logged and shown rather than escaping. [source] tags the
  /// diagnostic-log entries. Does nothing if the user cancels or [context] is
  /// unmounted by then.
  Future<void> deliver(
    BuildContext context, {
    required String csv,
    required String fileName,
    required String subject,
    required Rect? sharePositionOrigin,
    required String source,
    String? notice,
  }) async {
    final choice = await (choicePicker ?? showCsvExportChoiceDialog)(
      context,
      notice: notice,
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final save = saveInvoker ?? saveCsvFile;

    switch (choice) {
      case CsvExportChoice.save:
        await guardExport(messenger, l10n.exportCsvSaveError, () async {
          final result = await save(csv, fileName);
          if (result == null) return;
          _announceSaved(messenger, l10n, result);
        }, source: source);
      case CsvExportChoice.share:
        await guardExport(messenger, l10n.exportCsvShareError, () async {
          final result = await shareOrSaveBundleFile(
            json: csv,
            fileName: fileName,
            subject: subject,
            origin: sharePositionOrigin,
            shareInvoker: shareInvoker,
            bundleFileWriter: fileWriter ?? writeCsvTempFile,
            saveInvoker: save,
          );
          final saved = result?.saved;
          if (saved != null) _announceSaved(messenger, l10n, saved);
        }, source: source);
    }
  }
}

void _announceSaved(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  JsonSaveResult result,
) {
  final message = result.fileName == null
      ? l10n.exportCsvSavedGeneric
      : result.path.isEmpty
      ? l10n.exportJsonSaved(result.fileName!)
      : l10n.exportJsonSavedTo(result.fileName!, result.path);
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
