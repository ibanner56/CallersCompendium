import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diagnostics/error_log.dart';

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
