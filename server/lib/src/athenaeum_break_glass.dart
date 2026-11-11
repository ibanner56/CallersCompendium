import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';

import 'athenaeum_config.dart';
import 'athenaeum_store.dart';

/// The operator's `--break-glass` read: one manifest or one blob of one store,
/// written to [output], with its audit written first.
///
/// [read] names what is read; [syncIdLine] is the raw sync ID the operator
/// supplied on stdin. Returns the process exit code: `0` when the bytes were
/// written, `2` for unusable input (nothing is opened or recorded), and `1`
/// for any failure after that, reported to [errors] by error type only so no
/// sync ID, key, or content reaches a terminal log.
///
/// The order is the audit contract (`docs/dev/athenaeum-operations.md`,
/// Operations, Break-glass):
///
/// 1. the `break_glass_access` row and a `break_glass_reads` row naming the
///    requested item are written in one transaction, before the store is
///    looked up; if that fails, nothing is read;
/// 2. the store is looked up; when no epoch was requested, the current one is
///    recorded on the read row, and if that fails nothing is read;
/// 3. only then are the item's bytes read and written to [output].
///
/// `athenaeum.sqlite` is opened read-only ([AthenaeumStore.breakGlass]).
int runBreakGlass(
  AthenaeumConfig config, {
  required BreakGlassRead read,
  required String? syncIdLine,
  required IOSink output,
  required IOSink errors,
}) {
  final syncId = syncIdLine?.trim();
  if (syncId == null || syncId.isEmpty) {
    errors.writeln('break-glass input is empty');
    return 2;
  }
  try {
    validateSyncId(syncId);
    final store = AthenaeumStore.breakGlass(config: config);
    try {
      final readId = store.recordBreakGlassRead(syncId, read);
      final idKey = deriveIncomingSyncIdKey(syncId, config.pepper);
      final current = store.lookup(idKey);
      if (current == null) throw StateError('store not found');
      final epoch = read.epoch ?? current.epoch;
      if (read.epoch == null) store.resolveBreakGlassReadEpoch(readId, epoch);
      final Uint8List? body = switch (read.kind) {
        BreakGlassReadKind.manifest =>
          store.manifest(idKey, epoch, read.deviceId!)?.body,
        BreakGlassReadKind.blob => store.breakGlassBlob(
          idKey,
          epoch,
          read.hash!,
        ),
      };
      if (body == null) throw StateError('${read.kind.name} not found');
      output.add(body);
    } finally {
      store.close();
    }
  } on Object catch (error) {
    errors.writeln('break-glass read failed (${error.runtimeType})');
    return 1;
  }
  return 0;
}
