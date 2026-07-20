import 'dart:io';

import 'package:compendium_app/src/widgets/program_export_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('writeBundleFile', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cc_bundle_writer_test');
    });

    tearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'creates the target directory when it does not exist yet, then writes '
      'the bundle (regression: sandboxed macOS temp dir is absent)',
      () async {
        // Mirror the sandboxed-macOS failure: the provider hands back a
        // directory path that does not exist on disk. Writing straight into it
        // (without creating it) throws PathNotFoundException, which surfaced as
        // "Couldn't share this program".
        final missing = Directory('${root.path}/nested/does-not-exist');
        expect(missing.existsSync(), isFalse);

        final xfile = await writeBundleFile(
          '{"schemaVersion":1}',
          'my-program.json',
          getDir: () async => missing,
        );

        expect(missing.existsSync(), isTrue);
        final written = File(xfile.path);
        expect(written.existsSync(), isTrue);
        expect(written.parent.path, missing.path);
        expect(written.path.endsWith('my-program.json'), isTrue);
        expect(await written.readAsString(), '{"schemaVersion":1}');
        expect(xfile.mimeType, 'application/json');
      },
    );

    test('writes into an already-existing directory', () async {
      final xfile = await writeBundleFile(
        '{"schemaVersion":1}',
        'program.json',
        getDir: () async => root,
      );

      expect(File(xfile.path).existsSync(), isTrue);
      expect(await File(xfile.path).readAsString(), '{"schemaVersion":1}');
    });
  });
}
