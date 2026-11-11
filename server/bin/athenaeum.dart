import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('data-dir', defaultsTo: './data')
    ..addOption('pepper')
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '33333')
    ..addFlag('break-glass', negatable: false)
    ..addOption('break-glass-device-id')
    ..addOption('break-glass-blob')
    ..addOption('break-glass-epoch');
  final options = parser.parse(arguments);
  final pepper = options['pepper'] as String?;
  final config = AthenaeumConfig.fromEnvironment(
    dataDirectory: options['data-dir'] as String,
    pepper: pepper ?? Platform.environment['ATHENAEUM_PEPPER'],
    host: options['host'] as String,
    port: int.parse(options['port'] as String),
  );
  if (options['break-glass'] as bool) {
    final read = _breakGlassRead(
      deviceId: options['break-glass-device-id'] as String?,
      blobHash: options['break-glass-blob'] as String?,
      epoch: options['break-glass-epoch'] as String?,
    );
    if (read == null) {
      exitCode = 2;
      return;
    }
    exitCode = runBreakGlass(
      config,
      read: read,
      syncIdLine: stdin.readLineSync(),
      output: stdout,
      errors: stderr,
    );
    await stdout.flush();
    return;
  }
  final app = AthenaeumApp(config: config);
  final server = await shelf_io.serve(app.handler, config.host, config.port);
  final sweeper = AthenaeumSweepController(app.store)..start();
  stdout.writeln(
    'Athenaeum listening on ${server.address.address}:${server.port}',
  );
  late StreamSubscription<ProcessSignal> shutdownSubscription;
  shutdownSubscription = ProcessSignal.sigterm.watch().listen((_) async {
    final sweepStopped = sweeper.stop();
    await server.close(force: true);
    await sweepStopped;
    app.store.close();
    await shutdownSubscription.cancel();
    exit(0);
  });
}

/// What `--break-glass` is asked to read: exactly one of a manifest
/// (`--break-glass-device-id`) or a blob (`--break-glass-blob`). Null, after
/// saying why on stderr, when the options do not name exactly one valid item;
/// that is checked before the sync ID is read, so nothing is recorded.
BreakGlassRead? _breakGlassRead({
  required String? deviceId,
  required String? blobHash,
  required String? epoch,
}) {
  final hasDevice = deviceId != null && deviceId.isNotEmpty;
  final hasBlob = blobHash != null && blobHash.isNotEmpty;
  if (hasDevice == hasBlob) {
    stderr.writeln(
      'exactly one of --break-glass-device-id or --break-glass-blob is required',
    );
    return null;
  }
  try {
    return hasDevice
        ? BreakGlassRead.manifest(deviceId: deviceId, epoch: epoch)
        : BreakGlassRead.blob(hash: blobHash!, epoch: epoch);
  } on FormatException catch (error) {
    stderr.writeln('break-glass option rejected: ${error.message}');
    return null;
  }
}
