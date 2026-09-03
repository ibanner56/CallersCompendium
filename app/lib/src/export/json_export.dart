import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/json_export_dialog.dart';
import 'share_file.dart';

export '../widgets/json_export_dialog.dart';
export 'share_file.dart' show JsonSaveResult;

/// Opens the JSON delivery choice dialog.
typedef JsonChoicePicker =
    Future<JsonExportChoice?> Function(BuildContext context);

/// Writes raw JSON to the clipboard.
typedef JsonClipboardWriter = Future<void> Function(String json);

/// Delivers a canonical JSON export through its selected destination.
///
/// All fields are optional test seams. Defaults preserve the existing share
/// staging and OS share behavior while adding Save and raw-JSON Copy.
class JsonExportDelivery {
  const JsonExportDelivery({
    this.choicePicker,
    this.saveInvoker,
    this.clipboardWriter,
    this.shareInvoker,
    this.bundleFileWriter,
  });

  final JsonChoicePicker? choicePicker;
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

  Future<void> share({
    required String json,
    required String fileName,
    required String subject,
    required Rect? sharePositionOrigin,
  }) async {
    final writer = bundleFileWriter ?? writeBundleTempFile;
    final xfile = await writer(json, fileName);
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        files: [xfile],
        fileNameOverrides: [fileName],
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}

Future<void> _writeClipboard(String json) async {
  await Clipboard.setData(ClipboardData(text: json));
}
