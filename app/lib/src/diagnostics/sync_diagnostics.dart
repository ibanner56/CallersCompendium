// The Device Sync section of the diagnostics export (Settings ▸ Diagnostics).
//
// Like the rest of the export body it is English by design (see
// docs/dev/localization.md, "permanent exceptions"): it is read by whoever the
// user chooses to send it to, not by the user in their own language.
//
// Built only from structured fields — enum names, counts, a step name and an
// HTTP status — so it is safe in the scrubbed export without passing through
// the redactor. It never includes a title, the sync phrase, the server
// address, a device or record identifier, or a report's message: messages are
// maintainer diagnostics that can carry wire paths. Nothing here is sent
// anywhere; the export leaves the device only through the share sheet the
// user opens.
import 'package:compendium_core/compendium_core.dart'
    show SyncReport, SyncReportCode;

import '../screens/settings/sync_support_codes.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_coordinator.dart' show SyncPassStatus;

/// The section's lines, or null when Device Sync has nothing to say: it is
/// off, or on with no attempt, notice or store reading in this session.
String? syncDiagnosticsSection(SyncController? controller) {
  if (controller == null) return null;
  final result = controller.lastResult;
  final notices = controller.notices;
  final quota = controller.storeQuota;
  if (!controller.enabled &&
      result == null &&
      notices.isEmpty &&
      quota == null) {
    return null;
  }
  final buffer = StringBuffer()
    ..writeln('Device Sync')
    ..writeln('  Enabled: ${controller.enabled ? 'yes' : 'no'}')
    ..writeln('  Connected to a store: ${controller.paired ? 'yes' : 'no'}');
  if (result == null) {
    buffer.writeln('  Last attempt: none this session');
  } else {
    final code = syncPassSupportCode(result);
    buffer.writeln(
      '  Last attempt: ${result.status.name}'
      '${code == null ? '' : ' ($code)'}',
    );
    if (result.status == SyncPassStatus.failed) {
      final failure = result.failure;
      buffer.writeln(
        '    Cause: ${failure?.cause.name ?? 'unknown'}; '
        'step: ${failure?.step?.name ?? 'unknown'}; '
        'HTTP status: ${failure?.statusCode ?? 'none'}',
      );
    }
  }
  if (quota != null) {
    buffer.writeln('  Store usage: ${syncQuotaSupportCode(quota)}');
  }
  if (notices.isEmpty) {
    buffer.writeln('  Notices: none');
  } else {
    buffer.writeln('  Notices:');
    for (final MapEntry(key: code, value: reports) in _byCode(
      notices,
    ).entries) {
      final kinds = <String, int>{};
      for (final report in reports) {
        final kind = report.kind;
        if (kind != null) kinds[kind.name] = (kinds[kind.name] ?? 0) + 1;
      }
      buffer.writeln(
        '    ${code.name}: ${reports.length}'
        '${kinds.isEmpty ? '' : ' (${[for (final MapEntry(:key, :value) in kinds.entries) '$key ×$value'].join(', ')})'}',
      );
    }
  }
  return buffer.toString().trimRight();
}

/// [reports] grouped by code, in [SyncReportCode] declaration order.
Map<SyncReportCode, List<SyncReport>> _byCode(List<SyncReport> reports) => {
  for (final code in SyncReportCode.values)
    if (reports.where((r) => r.code == code).toList() case final matching
        when matching.isNotEmpty)
      code: matching,
};
