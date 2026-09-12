import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

import 'sync_coordinator.dart';
import 'sync_http_client.dart';

/// Coordinates an interruption test at the first successful inbound write.
///
/// This is a test seam, not a production sync state. The worker sends a
/// release port after it has written a record inside the transaction, allowing
/// a test to terminate the worker while the transaction is still open.
final class SyncIsolateApplyControl {
  SyncIsolateApplyControl() {
    _subscription = _events.listen((message) {
      if (message is! SendPort) return;
      _releasePort = message;
      if (!_applyStarted.isCompleted) _applyStarted.complete();
    });
  }

  final ReceivePort _events = ReceivePort();
  final Completer<void> _applyStarted = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  SendPort? _releasePort;

  SendPort get _eventPort => _events.sendPort;

  Future<void> get applyStarted => _applyStarted.future;

  void release() {
    final releasePort = _releasePort;
    if (releasePort == null) {
      throw StateError('the sync isolate is not paused in apply');
    }
    releasePort.send(null);
    _releasePort = null;
  }

  Future<void> close() async {
    await _subscription.cancel();
    _events.close();
  }
}

/// Raised when a caller terminates a sync worker before it returns a result.
final class SyncIsolateInterrupted implements Exception {
  const SyncIsolateInterrupted();

  @override
  String toString() => 'Sync isolate terminated before returning a result';
}

/// A running pass that the caller can terminate at an isolate boundary.
final class IsolatedSyncPassHandle {
  const IsolatedSyncPassHandle._(this.result, this._kill);

  final Future<SyncPassResult> result;
  final void Function() _kill;

  /// Terminates the worker. Its open database transaction is then recovered by
  /// SQLite as either the pre-pass or post-apply state when reopened.
  void kill() => _kill();
}

/// Runs a sync pass in a controllable isolate that owns its database and HTTP
/// resources.
///
/// The main isolate passes only strings across the boundary. The worker opens
/// the same SQLite file independently, so the transaction enclosing inbound
/// apply belongs to the isolate that the caller can terminate without leaving
/// partially applied rows in the caller.
final class IsolatedSyncPassOperation {
  const IsolatedSyncPassOperation({
    required this.databasePath,
    required this.endpoint,
    required this.syncId,
    required this.deviceId,
    this.beforeTerminalAcknowledgement,
  });

  final String databasePath;
  final Uri endpoint;
  final String syncId;
  final String deviceId;
  final Future<void> Function()? beforeTerminalAcknowledgement;

  Future<SyncPassResult> call() async {
    final handle = await start();
    return handle.result;
  }

  Future<IsolatedSyncPassHandle> start({
    SyncIsolateApplyControl? applyControl,
  }) async {
    final resultPort = ReceivePort();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    final result = Completer<SyncPassResult>();
    var finished = false;
    var terminalMessageReceived = false;

    late final StreamSubscription<dynamic> resultSubscription;
    late final StreamSubscription<dynamic> exitSubscription;
    late final StreamSubscription<dynamic> errorSubscription;

    void closePorts() {
      resultPort.close();
      exitPort.close();
      errorPort.close();
      unawaited(resultSubscription.cancel());
      unawaited(exitSubscription.cancel());
      unawaited(errorSubscription.cancel());
    }

    void completeResult(SyncPassResult value) {
      if (finished) return;
      finished = true;
      result.complete(value);
      closePorts();
    }

    void completeError(Object error, [StackTrace? stack]) {
      if (finished) return;
      finished = true;
      result.completeError(error, stack ?? StackTrace.current);
      closePorts();
    }

    resultSubscription = resultPort.listen((message) async {
      if (message is! Map<Object?, Object?>) {
        completeError(
          const FormatException('sync isolate returned a malformed message'),
        );
        return;
      }
      final acknowledgement = message['ack'];
      if (acknowledgement is! SendPort) {
        completeError(
          const FormatException(
            'sync isolate terminal message omitted its acknowledgement port',
          ),
        );
        return;
      }
      final beforeAcknowledgement = beforeTerminalAcknowledgement;
      if (beforeAcknowledgement != null) await beforeAcknowledgement();
      terminalMessageReceived = true;
      acknowledgement.send(null);
      switch (message['type']) {
        case 'result':
          final encoded = message['result'];
          if (encoded is! Map<Object?, Object?>) {
            completeError(
              const FormatException('sync isolate returned a malformed result'),
            );
            return;
          }
          try {
            completeResult(_decodeResult(Map<String, Object?>.from(encoded)));
            // diagnostics: silent — malformed terminal results are surfaced to the caller.
          } on Object catch (error, stack) {
            completeError(error, stack);
          }
        case 'error':
          final messageText = message['message'];
          completeError(
            StateError(
              messageText is String
                  ? messageText
                  : 'sync isolate failed without an error message',
            ),
          );
      }
    });
    exitSubscription = exitPort.listen((_) {
      if (!terminalMessageReceived) {
        completeError(const SyncIsolateInterrupted());
      }
    });
    errorSubscription = errorPort.listen((message) {
      final values = message is List<Object?> ? message : const <Object?>[];
      final error = values.isNotEmpty ? values.first : null;
      final stack = values.length > 1 ? values[1] : null;
      completeError(
        StateError(error is String ? error : 'sync isolate failed'),
        stack is String ? StackTrace.fromString(stack) : null,
      );
    });

    final isolate = await Isolate.spawn<_SyncPassRequest>(
      _runSyncPassWorker,
      _SyncPassRequest(
        databasePath: databasePath,
        endpoint: endpoint.toString(),
        syncId: syncId,
        deviceId: deviceId,
        resultPort: resultPort.sendPort,
        applyControlPort: applyControl?._eventPort,
      ),
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );

    return IsolatedSyncPassHandle._(result.future, () {
      if (!finished) isolate.kill(priority: Isolate.immediate);
    });
  }
}

final class _SyncPassRequest {
  const _SyncPassRequest({
    required this.databasePath,
    required this.endpoint,
    required this.syncId,
    required this.deviceId,
    required this.resultPort,
    required this.applyControlPort,
  });

  final String databasePath;
  final String endpoint;
  final String syncId;
  final String deviceId;
  final SendPort resultPort;
  final SendPort? applyControlPort;
}

Future<void> _runSyncPassWorker(_SyncPassRequest request) async {
  final acknowledgementPort = ReceivePort();
  try {
    final applyControlPort = request.applyControlPort;
    final applyEngine = applyControlPort == null
        ? null
        : SyncApplyEngine(
            onAfterWrite: (_) => _pauseAfterWrite(applyControlPort),
          );
    final encoded = await _runSyncPass(
      databasePath: request.databasePath,
      endpoint: request.endpoint,
      syncId: request.syncId,
      deviceId: request.deviceId,
      applyEngine: applyEngine,
    );
    request.resultPort.send({
      'type': 'result',
      'result': encoded,
      'ack': acknowledgementPort.sendPort,
    });
    // diagnostics: silent — worker errors are serialized to the parent isolate.
  } on Object catch (error, stack) {
    request.resultPort.send({
      'type': 'error',
      'message': '$error',
      'stack': '$stack',
      'ack': acknowledgementPort.sendPort,
    });
  }
  await acknowledgementPort.first;
  acknowledgementPort.close();
}

Future<void> _pauseAfterWrite(SendPort parentPort) async {
  final releasePort = ReceivePort();
  parentPort.send(releasePort.sendPort);
  try {
    await releasePort.first;
  } finally {
    releasePort.close();
  }
}

Future<Map<String, Object?>> _runSyncPass({
  required String databasePath,
  required String endpoint,
  required String syncId,
  required String deviceId,
  SyncApplyEngine? applyEngine,
}) async {
  final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
  SyncHttpClient? client;
  SyncCoordinator? coordinator;

  try {
    client = SyncHttpClient(endpoint: Uri.parse(endpoint), syncId: syncId);
    coordinator = SyncCoordinator(
      syncId: syncId,
      deviceId: deviceId,
      store: CompendiumSyncCoordinatorStore(
        CompendiumRepositories(database, contraTaxonomy),
        syncId: syncId,
      ),
      transport: SyncHttpCoordinatorTransport(client),
      applyEngine: applyEngine,
    );
    return _encodeResult(await coordinator.onAppStart());
  } finally {
    if (coordinator != null) {
      await coordinator.dispose();
    } else {
      client?.close();
    }
    await database.close();
  }
}

Map<String, Object?> _encodeResult(SyncPassResult result) => {
  'status': result.status.name,
  'message': result.message,
  'reports': [
    for (final report in result.reports)
      {
        'code': report.code.name,
        'message': report.message,
        'kind': report.kind?.name,
        'recordId': report.recordId,
        'peerId': report.peerId,
      },
  ],
};

SyncPassResult _decodeResult(Map<String, Object?> encoded) {
  final rawStatus = encoded['status'];
  final rawMessage = encoded['message'];
  final rawReports = encoded['reports'];
  if (rawStatus is! String ||
      (rawMessage != null && rawMessage is! String) ||
      rawReports is! List<Object?>) {
    throw const FormatException('sync isolate returned a malformed result');
  }

  final status = SyncPassStatus.values.byName(rawStatus);
  final reports = <SyncReport>[];
  for (final rawReport in rawReports) {
    if (rawReport is! Map<Object?, Object?>) {
      throw const FormatException('sync isolate returned a malformed report');
    }
    final code = rawReport['code'];
    final message = rawReport['message'];
    final kind = rawReport['kind'];
    final recordId = rawReport['recordId'];
    final peerId = rawReport['peerId'];
    if (code is! String ||
        message is! String ||
        (kind != null && kind is! String) ||
        (recordId != null && recordId is! String) ||
        (peerId != null && peerId is! String)) {
      throw const FormatException('sync isolate returned an invalid report');
    }
    final kindName = kind == null ? null : kind as String;
    final recordIdValue = recordId == null ? null : recordId as String;
    final peerIdValue = peerId == null ? null : peerId as String;
    reports.add(
      SyncReport(
        code: SyncReportCode.values.byName(code),
        message: message,
        kind: kindName == null ? null : SyncRecordKind.values.byName(kindName),
        recordId: recordIdValue,
        peerId: peerIdValue,
      ),
    );
  }

  return SyncPassResult(
    status,
    reports: reports,
    message: rawMessage as String?,
  );
}
