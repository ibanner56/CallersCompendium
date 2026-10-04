import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/export_guard.dart';
import '../widgets/json_export_dialog.dart';
import 'share_file.dart';

export '../widgets/json_export_dialog.dart';
export 'share_file.dart' show BundleDeliveryResult, JsonSaveResult;

/// Opens the JSON delivery choice dialog.
typedef JsonChoicePicker =
    Future<JsonExportChoice?> Function(BuildContext context);

/// Writes raw JSON to the clipboard.
typedef JsonClipboardWriter = Future<void> Function(String json);

/// Delivers a canonical JSON export through its selected destination.
///
/// All fields are optional test seams. Defaults preserve the existing share
/// staging and OS share behavior while adding Save and raw-JSON Copy.
///
/// [deliver] is the one place that turns the user's [JsonExportChoice] into a
/// guarded Save, Copy or Share with its snackbars; the dance and program export
/// surfaces call it instead of keeping their own switch.
class JsonExportDelivery {
  const JsonExportDelivery({
    this.choicePicker,
    this.saveInvoker,
    this.clipboardWriter,
    this.shareInvoker,
    this.bundleFileWriter,
  });

  final JsonChoicePicker? choicePicker;

  /// Overrides the Save As path. Also used by [share] (and by the menus'
  /// `.ccshare` bundle action) where [isBundleShareUnsupported] is true.
  final Future<JsonSaveResult?> Function(String json, String fileName)?
  saveInvoker;
  final JsonClipboardWriter? clipboardWriter;
  final Future<void> Function(ShareParams params)? shareInvoker;
  final BundleFileWriter? bundleFileWriter;

  Future<JsonExportChoice?> choose(BuildContext context) =>
      (choicePicker ?? showJsonExportChoiceDialog)(context);

  Future<JsonSaveResult?> save(String json, String fileName) =>
      (saveInvoker ?? saveJsonBundle)(json, fileName);

  Future<void> copy(String json) => (clipboardWriter ?? _writeClipboard)(json);

  /// Hands the JSON to the share sheet, or to Save As where the platform's
  /// share sheet cannot carry files ([isBundleShareUnsupported]). Returns
  /// `null` when the user cancelled that Save As dialog.
  Future<BundleDeliveryResult?> share({
    required String json,
    required String fileName,
    required String subject,
    required Rect? sharePositionOrigin,
  }) => shareOrSaveBundleFile(
    json: json,
    fileName: fileName,
    subject: subject,
    origin: sharePositionOrigin,
    shareInvoker: shareInvoker,
    bundleFileWriter: bundleFileWriter,
    saveInvoker: saveInvoker ?? saveJsonBundle,
  );

  /// Asks the user how to deliver [json] (Save, Copy or Share), then does it.
  ///
  /// Each branch runs under [guardExport] with its own failure message, so a
  /// throwing seam is logged and surfaced as a snackbar rather than escaping.
  /// [source] tags the diagnostic-log entries (`<file-stem>.<method>`). Does
  /// nothing if the user dismisses the choice or [context] is unmounted by
  /// then.
  Future<void> deliver(
    BuildContext context, {
    required String json,
    required String fileName,
    required String subject,
    required Rect? sharePositionOrigin,
    required String source,
  }) async {
    final choice = await choose(context);
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    switch (choice) {
      case JsonExportChoice.save:
        await guardExport(messenger, l10n.exportJsonSaveError, () async {
          final result = await save(json, fileName);
          if (result == null || !context.mounted) return;
          final message = result.fileName == null
              ? l10n.exportJsonSavedGeneric
              : result.path.isEmpty
              ? l10n.exportJsonSaved(result.fileName!)
              : l10n.exportJsonSavedTo(result.fileName!, result.path);
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }, source: source);
      case JsonExportChoice.copy:
        await guardExport(messenger, l10n.exportJsonCopyError, () async {
          await copy(json);
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.exportJsonCopied)),
            );
          }
        }, source: source);
      case JsonExportChoice.share:
        await guardExport(messenger, l10n.exportJsonShareError, () async {
          final result = await share(
            json: json,
            fileName: fileName,
            subject: subject,
            sharePositionOrigin: sharePositionOrigin,
          );
          announceBundleSaved(messenger, l10n, result);
        }, source: source);
    }
  }
}

Future<void> _writeClipboard(String json) async {
  await Clipboard.setData(ClipboardData(text: json));
}
