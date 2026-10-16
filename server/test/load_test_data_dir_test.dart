import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// `tool/load_test.dart` runs migrations and inserts fixture stores and blobs
// with fixed IDs into whatever `--data-dir` it is given. It must therefore
// accept only a directory that does not exist yet or is empty: a populated one
// is either a live deployment's data or the previous run's, whose fixture
// stores would answer 409.
void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('load-test-dir-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<ProcessResult> loadTest(String dataDirectory) =>
      Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/load_test.dart',
        '--duration=1',
        '--concurrency=1',
        '--scenario=store-get',
        '--stores=2',
        '--data-dir=$dataDirectory',
      ]);

  List<String> listing(Directory directory) =>
      directory
          .listSync(recursive: true)
          .map((entry) => p.relative(entry.path, from: directory.path))
          .toList()
        ..sort();

  test(
    'refuses a directory that already holds an Athenaeum database',
    () async {
      final live = Directory(p.join(scratch.path, 'live'))..createSync();
      File(p.join(live.path, 'athenaeum.sqlite')).writeAsStringSync('not a db');
      final before = listing(live);

      final result = await loadTest(live.path);

      expect(result.exitCode, 2, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, contains('--data-dir'));
      expect(result.stderr, contains('new, empty directory'));
      expect(
        listing(live),
        before,
        reason: 'a refused run must not touch the directory',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('refuses any other non-empty directory', () async {
    File(p.join(scratch.path, 'notes.txt')).writeAsStringSync('mine');

    final result = await loadTest(scratch.path);

    expect(result.exitCode, 2, reason: '${result.stdout}${result.stderr}');
    expect(listing(scratch), ['notes.txt']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'accepts a new directory once, then refuses it on a second run',
    () async {
      final fresh = Directory(p.join(scratch.path, 'fresh'));

      final first = await loadTest(fresh.path);
      expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
      expect(File(p.join(fresh.path, 'athenaeum.sqlite')).existsSync(), isTrue);

      final second = await loadTest(fresh.path);
      expect(second.exitCode, 2, reason: '${second.stdout}${second.stderr}');
      expect(second.stderr, isNot(contains('Unhandled exception')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('accepts an existing empty directory', () async {
    final result = await loadTest(scratch.path);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
