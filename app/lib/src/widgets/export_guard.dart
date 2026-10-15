import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../diagnostics/error_log.dart';
import '../export/share_file.dart';

/// Runs [action], surfacing [failureMessage] as a [SnackBar] if it throws.
///
/// A user who simply cancels a share/print sheet surfaces as a normal
/// (non-throwing) result, so only genuine failures are reported.
///
/// Catches [Object], not just [Exception]: a `StateError`, `TypeError` or
/// `RangeError` from an export builder is an [Error] and would otherwise skip
/// the snackbar, leaving the user with a tap that visibly did nothing. Both
/// export menus share this one clause so they cannot drift apart (#1395).
///
/// [source] tags the diagnostic-log entry, as `<file-stem>.<method>`.
Future<void> guardExport(
  ScaffoldMessengerState messenger,
  String failureMessage,
  Future<void> Function() action, {
  required String source,
}) async {
  try {
    await action();
  } on Object catch (e, st) {
    logCaughtError(e, st, source: source);
    if (kDebugMode) {
      debugPrint('$failureMessage: $e\n$st');
    }
    messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}

/// Confirms a bundle that [shareOrSaveBundleFile] saved to disk (Linux, where
/// the share sheet cannot carry files). A share-sheet delivery or a cancelled
/// Save As shows nothing, as before.
void announceBundleSaved(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  BundleDeliveryResult? result,
) {
  final saved = result?.saved;
  if (saved == null) return;
  final message = saved.fileName == null
      ? l10n.exportJsonSavedGeneric
      : saved.path.isEmpty
      ? l10n.exportJsonSaved(saved.fileName!)
      : l10n.exportJsonSavedTo(saved.fileName!, saved.path);
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
