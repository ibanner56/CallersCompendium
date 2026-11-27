import 'dart:io';
import 'dart:ui' as ui;

import 'package:compendium_app/src/data/dance_code_scanner.dart';
import 'package:compendium_app/src/data/photo_capture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../support/dance_links.dart';
import '../support/picker_channels.dart';
import '../support/qr_pictures.dart';

/// Finding a dance code in a picture (#2336): the real `zxing2` reader over
/// pictures drawn here. The search runs on this isolate in tests.
void main() {
  final decoder = Zxing2DanceCodeDecoder(
    search: (pixels) async => readQrCode(pixels),
  );

  Future<Object?> outcome(WidgetTester tester, Future<Uint8List> picture) =>
      tester.runAsync(() async {
        try {
          return await decoder.decode(await picture);
        } on DanceCodeScanException catch (e) {
          return e.failure;
        }
      });

  testWidgets('reads the link a dance code holds', (tester) async {
    final link = goodDanceLink();
    expect(await outcome(tester, qrPicture(link)), link);
  });

  testWidgets('reads a code light on dark', (tester) async {
    final link = goodDanceLink();
    expect(await outcome(tester, qrPicture(link, inverted: true)), link);
  });

  testWidgets('reads a small code in a large photo, scaled down first', (
    tester,
  ) async {
    final link = goodDanceLink();
    // 4000 px wide, the code a fifth of it at 12 px a module: halved before
    // the search, so each module is 6 px. (Scaled to 2048 instead, each
    // module would be 6.1 px, and this code then misreads.)
    final picture = qrPicture(
      link,
      module: 12,
      canvas: const ui.Size(4000, 3000),
      offset: const ui.Offset(2500, 1800),
    );
    expect(await outcome(tester, picture), link);
  });

  testWidgets('a picture with no code is noCode', (tester) async {
    expect(await outcome(tester, blankPicture()), DanceCodeScanFailure.noCode);
  });

  testWidgets('bytes that are not a picture are unreadablePicture', (
    tester,
  ) async {
    expect(
      await outcome(tester, Future.value(Uint8List.fromList([1, 2, 3, 4]))),
      DanceCodeScanFailure.unreadablePicture,
    );
    expect(
      await outcome(tester, Future.value(Uint8List(0))),
      DanceCodeScanFailure.unreadablePicture,
    );
  });

  test('the caps: 10,000 pixels a side and 50 million in all', () {
    expect(overScanCaps(10000, 5000), isFalse);
    expect(overScanCaps(10001, 10), isTrue);
    expect(overScanCaps(10, 10001), isTrue);
    expect(overScanCaps(7000, 7000), isFalse);
    expect(overScanCaps(9000, 9000), isTrue);
  });

  testWidgets('a picture over the pixel cap is refused before decoding', (
    tester,
  ) async {
    // Tall and thin: over the side cap, small as a PNG.
    final picture = blankPicture(
      size: const ui.Size(20, kDanceCodeScanMaxSide + 1.0),
    );
    expect(
      await outcome(tester, picture),
      DanceCodeScanFailure.unreadablePicture,
    );
  });

  testWidgets('any QR code is read; deciding it is a dance is the caller\'s', (
    tester,
  ) async {
    expect(
      await outcome(tester, qrPicture('https://example.com/')),
      'https://example.com/',
    );
  });

  group('the photo file a scan takes', () {
    late Directory temp;
    late File photo;
    final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('scan-camera-temp');
      photo = File(p.join(temp.path, 'image_picker_SCAN1.jpg'));
      await photo.writeAsBytes(bytes);
    });
    tearDown(() => temp.delete(recursive: true));

    /// The system camera service over [photo], as on iPhone.
    PhotoCaptureService camera({bool cancel = false}) =>
        SystemCameraPhotoCapture(
          platform: TargetPlatform.iOS,
          capture: () async => cancel ? null : XFile(photo.path),
          temporaryDirectory: temp,
        );

    test('is gone before its code is read, and after', () async {
      bool? existedWhileDecoding;
      final text = await scanDanceCode(
        camera: camera(),
        decoder: _AnswerDecoder(() async {
          existedWhileDecoding = photo.existsSync();
          return 'ccdance://1/x';
        }),
      );
      expect(text, 'ccdance://1/x');
      expect(existedWhileDecoding, isFalse);
      expect(photo.existsSync(), isFalse);
    });

    test('is gone when no code is found', () async {
      await expectLater(
        scanDanceCode(
          camera: camera(),
          decoder: _AnswerDecoder(
            () => Future.error(
              const DanceCodeScanException(DanceCodeScanFailure.noCode),
            ),
          ),
        ),
        throwsA(isA<DanceCodeScanException>()),
      );
      expect(photo.existsSync(), isFalse);
    });

    test('a cancel reads nothing and deletes nothing', () async {
      final decoder = _AnswerDecoder(() async => 'unused');
      expect(
        await scanDanceCode(camera: camera(cancel: true), decoder: decoder),
        isNull,
      );
      expect(decoder.calls, 0);
      expect(photo.existsSync(), isTrue);
    });
  });

  group('a chosen picture', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pick-temp');
    });
    tearDown(() => temp.delete(recursive: true));

    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    Future<File> fileAt(List<String> parts, {List<int>? content}) async {
      final file = File(p.joinAll([temp.path, ...parts]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content ?? bytes);
      return file;
    }

    Future<Uint8List?> pick(File file, TargetPlatform platform) =>
        pickDanceCodePicture(
          open: () async => XFile(file.path),
          platform: platform,
          temporaryDirectory: () async => temp,
        );

    const uuid = '0f8fad5b-d9cb-469f-a165-70867728950e';

    test(
      'on Android, the file selector\'s copy and its folder are deleted',
      () async {
        final copy = await fileAt([uuid, 'code.png']);
        expect(await pick(copy, TargetPlatform.android), bytes);
        expect(copy.existsSync(), isFalse);
        expect(copy.parent.existsSync(), isFalse);
      },
    );

    test('on Android, an over-size copy is deleted unread', () async {
      final copy = await fileAt([
        uuid,
        'big.png',
      ], content: Uint8List(kDanceCodePhotoMaxBytes + 1));
      await expectLater(
        pick(copy, TargetPlatform.android),
        throwsA(isA<DanceCodePictureTooLarge>()),
      );
      expect(copy.existsSync(), isFalse);
    });

    test('on Android, a file outside a copy folder is left alone', () async {
      final mine = await fileAt(['code.png']);
      final nested = await fileAt(['not-a-uuid', 'code.png']);
      final deeper = await fileAt([uuid, 'more', 'code.png']);
      for (final file in [mine, nested, deeper]) {
        expect(await pick(file, TargetPlatform.android), bytes);
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });

    test('on iOS, the document picker\'s Inbox copy is deleted', () async {
      final copy = await fileAt(['is.banner.app-Inbox', 'code.png']);
      expect(await pick(copy, TargetPlatform.iOS), bytes);
      expect(copy.existsSync(), isFalse);
    });

    test('on desktop, the user\'s own file is left alone', () async {
      final copy = await fileAt([uuid, 'code.png']);
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(await pick(copy, platform), bytes);
        expect(copy.existsSync(), isTrue, reason: platform.name);
      }
    });

    test('on iOS, by default the Inbox copy is looked for in the system '
        'temporary folder (NSTemporaryDirectory)', () async {
      final inbox = await Directory(
        p.join(
          Directory.systemTemp.path,
          'scan-test-${DateTime.now().microsecondsSinceEpoch}-Inbox',
        ),
      ).create();
      addTearDown(() => inbox.delete(recursive: true));
      final copy = File(p.join(inbox.path, 'code.png'));
      await copy.writeAsBytes(bytes);
      expect(
        await pickDanceCodePicture(
          open: () async => XFile(copy.path),
          platform: TargetPlatform.iOS,
        ),
        bytes,
      );
      expect(copy.existsSync(), isFalse);
    });

    test('a cancel reads nothing', () async {
      expect(
        await pickDanceCodePicture(
          open: () async => null,
          platform: TargetPlatform.android,
          temporaryDirectory: () async => temp,
        ),
        isNull,
      );
    });
  });

  group('the picker Dance code from a picture opens', () {
    late PickerChannels pickers;
    late Directory temp;
    setUp(() async {
      pickers = PickerChannels.install();
      temp = await Directory.systemTemp.createTemp('code-pick');
      addTearDown(() => temp.delete(recursive: true));
    });

    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    /// A picture at [relative] in [temp], handed back by either picker.
    Future<File> picked(String relative, {List<int>? content}) async {
      final file = File(p.join(temp.path, relative));
      await file.create(recursive: true);
      await file.writeAsBytes(content ?? bytes);
      pickers.path = file.path;
      return file;
    }

    Future<Uint8List?> pick(TargetPlatform platform) => pickDanceCodePicture(
      platform: platform,
      temporaryDirectory: () async => temp,
    );

    test('on iPhone and iPad it is the system photo picker, asked for no '
        'more than the picture', () async {
      await picked('image_picker_0A1B.png');
      expect(await pick(TargetPlatform.iOS), bytes);
      expect(pickers.fileCalls, isEmpty);
      expect(pickers.photoPicks, hasLength(1));
      final args = pickers.photoPicks.single;
      expect(args['source'], ImageSource.gallery.index);
      // Full metadata is a photo-library lookup, which needs permission.
      expect(args['requestFullMetadata'], isFalse);
    });

    test('elsewhere it is the file picker', () async {
      await picked('code.png');
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(await pick(platform), bytes, reason: platform.name);
      }
      expect(pickers.photoPicks, isEmpty);
      expect(pickers.fileCalls, List.filled(4, 'openFile'));
    });

    test("on iOS the photo picker's copy is deleted once read", () async {
      final copy = await picked('image_picker_0A1B.png');
      expect(await pick(TargetPlatform.iOS), bytes);
      expect(copy.existsSync(), isFalse);
    });

    test("on iOS the photo picker's copy is deleted unread when it is too "
        'large', () async {
      final copy = await picked(
        'image_picker_0A1B.png',
        content: Uint8List(kDanceCodePhotoMaxBytes + 1),
      );
      await expectLater(
        pick(TargetPlatform.iOS),
        throwsA(isA<DanceCodePictureTooLarge>()),
      );
      expect(copy.existsSync(), isFalse);
    });

    test('on iOS by default the copy is looked for in the system temporary '
        'folder (NSTemporaryDirectory)', () async {
      final copy = File(
        p.join(
          Directory.systemTemp.path,
          'image_picker_${p.basename(temp.path)}.png',
        ),
      );
      await copy.writeAsBytes(bytes);
      addTearDown(() async {
        if (copy.existsSync()) await copy.delete();
      });
      pickers.path = copy.path;
      expect(await pickDanceCodePicture(platform: TargetPlatform.iOS), bytes);
      expect(copy.existsSync(), isFalse);
    });

    test("on iOS a file that is not the picker's copy is left alone", () async {
      for (final relative in ['code.png', 'nested/image_picker_0A1B.png']) {
        final file = await picked(relative);
        expect(await pick(TargetPlatform.iOS), bytes);
        expect(file.existsSync(), isTrue, reason: relative);
      }
    });

    test('a cancel reads nothing', () async {
      expect(await pick(TargetPlatform.iOS), isNull);
      expect(pickers.photoPicks, hasLength(1));
    });
  });
}

class _AnswerDecoder implements DanceCodeDecoder {
  _AnswerDecoder(this.answer);

  final Future<String> Function() answer;
  var calls = 0;

  @override
  Future<String> decode(Uint8List encodedPicture) {
    calls++;
    return answer();
  }
}
