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
    ..addOption('port', defaultsTo: '33333');
  final options = parser.parse(arguments);
  final pepper = options['pepper'] as String?;
  final config = AthenaeumConfig.fromEnvironment(
    dataDirectory: options['data-dir'] as String,
    pepper: pepper ?? Platform.environment['ATHENAEUM_PEPPER'],
    host: options['host'] as String,
    port: int.parse(options['port'] as String),
  );
  final app = AthenaeumApp(config: config);
  final server = await shelf_io.serve(app.handler, config.host, config.port);
  stdout.writeln(
    'Athenaeum listening on ${server.address.address}:${server.port}',
  );
  late StreamSubscription<ProcessSignal> shutdownSubscription;
  shutdownSubscription = ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    app.store.close();
    await shutdownSubscription.cancel();
    exit(0);
  });
}
