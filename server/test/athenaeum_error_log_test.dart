import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('redacts request targets from Apache error messages', () async {
    final output = File(
      '${Directory.systemTemp.createTempSync('athenaeum-error-log-test-').path}/'
      'error.log',
    );
    addTearDown(() async {
      await output.parent.delete(recursive: true);
    });

    final process = await Process.start('sh', [
      'server/deploy/athenaeum-error-log',
      output.path,
    ]);
    process.stdin
      ..writeln(
        '[Fri Sep 11 14:00:00.000000 2026] [proxy:error] [pid 123] '
        'denied /v1/manifests/device-secret',
      )
      ..writeln('unstructured /v1/blobs/secret-hash');
    await process.stdin.close();

    expect(await process.exitCode, 0);
    expect(
      await output.readAsString(),
      '[Fri Sep 11 14:00:00.000000 2026] [proxy:error] [pid 123] '
      '[message redacted]\n'
      '[redacted Apache error]\n',
    );
  });
}
