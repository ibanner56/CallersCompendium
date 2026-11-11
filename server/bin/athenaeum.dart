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
    ..addOption(
      'min-free-bytes',
      defaultsTo:
          Platform.environment['ATHENAEUM_MIN_FREE_BYTES'] ??
          '$defaultMinFreeBytes',
      help:
          'Refuse blob and manifest writes with 507 while the data '
          "directory's filesystem has less than this free (0 turns it off).",
    )
    ..addOption(
      'max-large-bodies',
      defaultsTo:
          Platform.environment['ATHENAEUM_MAX_LARGE_BODIES'] ??
          '$defaultMaxLargeBodiesInFlight',
      help: 'Large-body requests handled at once, server-wide; more get 503.',
    )
    ..addOption(
      'max-large-bodies-per-ip',
      defaultsTo:
          Platform.environment['ATHENAEUM_MAX_LARGE_BODIES_PER_IP'] ??
          '$defaultMaxLargeBodiesInFlightPerIp',
      help:
          'Large-body requests one client address may have in flight; '
          'more get 429.',
    )
    ..addFlag('break-glass', negatable: false)
    ..addOption('break-glass-device-id')
    ..addOption('break-glass-blob')
    ..addOption('break-glass-epoch');
  // The three limit options fall back to environment variables of the same
  // meaning, so a deployment can set them in the env file the release deploy
  // keeps, rather than in container arguments it replaces.
  final options = parser.parse(arguments);
  final pepper = options['pepper'] as String?;
  final config = AthenaeumConfig.fromEnvironment(
    dataDirectory: options['data-dir'] as String,
    pepper: pepper ?? Platform.environment['ATHENAEUM_PEPPER'],
    host: options['host'] as String,
    port: int.parse(options['port'] as String),
    minFreeBytes: int.parse(options['min-free-bytes'] as String),
    maxLargeBodiesInFlight: int.parse(options['max-large-bodies'] as String),
    maxLargeBodiesInFlightPerIp: int.parse(
      options['max-large-bodies-per-ip'] as String,
    ),
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
  if (config.minFreeBytes > 0 &&
      statvfsAvailableBytes(config.dataDirectory) == null) {
    // Said once, at startup: the floor admits every write it cannot measure.
    stderr.writeln(
      'Athenaeum cannot read free space on this platform; '
      'the --min-free-bytes floor is not enforced',
    );
  }
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
