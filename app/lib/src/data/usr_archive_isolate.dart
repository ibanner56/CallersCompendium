import 'dart:isolate';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';

/// Runs [work] over [bytes] on a short-lived background isolate and returns its
/// result, so a CPU-heavy parse of a file-sized buffer doesn't stall the UI.
///
/// [bytes] is handed over as a [TransferableTypedData]: one copy into the
/// transfer, none on the way in (the worker takes ownership of that memory) and
/// none on the way out ([Isolate.run] returns by exit). The caller's [bytes] is
/// left untouched and still usable. [work] must be a top-level or static
/// function, or a closure that captures nothing that cannot cross an isolate
/// boundary.
///
/// Anything [work] throws is rethrown here, as the same type when it can cross
/// the boundary (the reader's exceptions are plain classes holding a string).
Future<R> runOnIsolateWithBytes<R>(
  Uint8List bytes,
  R Function(Uint8List bytes) work,
) {
  final transfer = TransferableTypedData.fromList([bytes]);
  return Isolate.run(() => work(transfer.materialize().asUint8List()));
}

/// A [CcUsrArchiveReader] that parses a Caller's Companion `.USR` on a
/// background isolate. A library-sized file (~20,000 dances) takes seconds to
/// read; on the UI isolate that freezes the app for the duration.
///
/// Throws exactly what [readCcUsrArchive] throws ([FmpFormatException],
/// [FmpResourceLimitException]), so the adapter's error mapping is unchanged.
Future<CcUsrArchive> readCcUsrArchiveInIsolate(
  Uint8List bytes,
  FmpReadLimits limits,
) => runOnIsolateWithBytes(
  bytes,
  (data) => readCcUsrArchive(data, limits: limits),
);
