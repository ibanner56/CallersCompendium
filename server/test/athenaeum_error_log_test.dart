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

    final process = await Process.start(_shellExecutable(), [
      _deploymentScriptPath(),
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

/// `sh` for running the deployment script.
///
/// Windows shells such as PowerShell often don't have Git's `usr\bin` on the
/// PATH that Dart resolves against, so a bare `sh` fails to start even though
/// Git for Windows is installed; fall back to its known install locations.
String _shellExecutable() {
  if (!Platform.isWindows) return 'sh';
  for (final variable in [
    'ProgramFiles',
    'ProgramFiles(x86)',
    'LocalAppData',
  ]) {
    final base = Platform.environment[variable];
    if (base == null) continue;
    for (final relative in [
      r'Git\bin\sh.exe',
      r'Git\usr\bin\sh.exe',
      r'Programs\Git\bin\sh.exe',
    ]) {
      final candidate = File('$base\\$relative');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return 'sh';
}

String _deploymentScriptPath() {
  const relativePath = 'deploy/athenaeum-error-log';
  final packageRelative = File(relativePath);
  if (packageRelative.existsSync()) return packageRelative.path;
  final repositoryRelative = File('server/$relativePath');
  if (repositoryRelative.existsSync()) return repositoryRelative.path;
  throw StateError('could not locate $relativePath');
}
