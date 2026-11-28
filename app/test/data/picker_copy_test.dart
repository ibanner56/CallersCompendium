import 'dart:io';

import 'package:compendium_app/src/data/picker_copy.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The copy a system file picker makes of a file chosen for import or
/// restore is deleted once read; the user's own file never is.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cc_picker_copy_test');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  File fileAt(List<String> parts) {
    final file = File(p.joinAll([temp.path, ...parts]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('Title,Pay\nContra night,100\n');
    return file;
  }

  const uuid = '0f8fad5b-d9cb-469f-a165-70867728950e';

  group('readPickedFile', () {
    test('on Android, deletes the file selector copy once read', () async {
      final copy = fileAt([uuid, 'programs.csv']);
      final text = await readPickedFile(
        XFile(copy.path),
        (f) => f.readAsString(),
        platform: TargetPlatform.android,
        temporaryDirectory: () async => temp,
      );
      expect(text, startsWith('Title,Pay'));
      expect(copy.existsSync(), isFalse);
    });

    test('on iOS, deletes the document picker copy once read', () async {
      final copy = fileAt(['org.example.app-Inbox', 'backup.json']);
      await readPickedFile(
        XFile(copy.path),
        (f) => f.readAsString(),
        platform: TargetPlatform.iOS,
        temporaryDirectory: () async => temp,
      );
      expect(copy.existsSync(), isFalse);
    });

    test('deletes the copy when the read fails too', () async {
      final copy = fileAt([uuid, 'too-big.csv']);
      await expectLater(
        readPickedFile<String>(
          XFile(copy.path),
          (_) async => throw const FormatException('too large'),
          platform: TargetPlatform.android,
          temporaryDirectory: () async => temp,
        ),
        throwsFormatException,
      );
      expect(copy.existsSync(), isFalse);
    });

    test(
      'on a computer, the chosen file is the user\'s own and is kept',
      () async {
        for (final platform in [
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        ]) {
          final own = fileAt([uuid, 'programs.csv']);
          await readPickedFile(
            XFile(own.path),
            (f) => f.readAsString(),
            platform: platform,
            temporaryDirectory: () async => temp,
          );
          expect(own.existsSync(), isTrue, reason: '$platform');
        }
      },
    );

    test('with no temporary folder, the read still returns', () async {
      final copy = fileAt([uuid, 'programs.csv']);
      final text = await readPickedFile(
        XFile(copy.path),
        (f) => f.readAsString(),
        platform: TargetPlatform.android,
        temporaryDirectory: () async =>
            throw const FileSystemException('no folder'),
      );
      expect(text, startsWith('Title,Pay'));
    });
  });

  group('deleteIosDocumentPickerCopy', () {
    test(
      'leaves any file that is not in an -Inbox folder directly in tmp',
      () async {
        final kept = [
          fileAt(['backup.json']),
          fileAt(['Documents', 'backup.json']),
          fileAt(['Inbox', 'backup.json']),
          fileAt(['a', 'org.example.app-Inbox', 'backup.json']),
        ];
        final elsewhere = await Directory.systemTemp.createTemp('cc_elsewhere');
        addTearDown(() => elsewhere.delete(recursive: true));
        final outside = File(
          p.join(elsewhere.path, 'org.example.app-Inbox', 'backup.json'),
        )..createSync(recursive: true);

        for (final file in [...kept, outside]) {
          await deleteIosDocumentPickerCopy(
            file.path,
            temporaryDirectory: temp,
          );
          expect(file.existsSync(), isTrue, reason: file.path);
        }
      },
    );

    test('a missing file or an empty path is not an error', () async {
      await deleteIosDocumentPickerCopy('', temporaryDirectory: temp);
      await deleteIosDocumentPickerCopy(
        p.join(temp.path, 'x-Inbox', 'gone.json'),
        temporaryDirectory: temp,
      );
    });
  });
}
