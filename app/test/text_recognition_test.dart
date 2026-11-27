import 'dart:io';
import 'dart:ui' as ui;

import 'package:compendium_app/src/data/photo_capture.dart';
import 'package:compendium_app/src/data/text_recognition.dart';
import 'package:compendium_app/src/widgets/figure_text_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'support/l10n_harness.dart';
import 'support/picker_channels.dart';

/// A recognizer that answers from fixed values and records what it was asked.
class _FakeRecognizer implements TextRecognitionService {
  _FakeRecognizer({this.languages = const ['en']});

  final List<String> languages;
  final recognized = <Uint8List>[];
  final askedLanguages = <List<String>>[];

  @override
  Future<TextRecognitionAvailability> availability(List<String> asked) async =>
      TextRecognitionAvailability(
        languages: [
          for (final l in asked)
            if (languages.contains(l)) l,
        ],
      );

  @override
  Future<String> recognize(
    Uint8List bytes, {
    required List<String> languages,
  }) async {
    recognized.add(bytes);
    askedLanguages.add(languages);
    return _cardText;
  }
}

/// A recognizer whose language query fails with an error the channel does
/// not map.
class _ThrowingAvailability extends _FakeRecognizer {
  @override
  Future<TextRecognitionAvailability> availability(List<String> asked) =>
      Future.error(StateError('engine gone'));
}

const _cardText = 'A1 (8) Neighbor balance & swing\n(8) Long lines';

/// A tiny valid PNG (1×1), standing in for a photo of a typed card: the fake
/// recognizer supplies the card's text.
final Uint8List _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<void> _pumpSheet(
  WidgetTester tester, {
  TextRecognitionService? service,
  bool withScope = true,
  Future<PickedRecognitionImage?> Function()? pick,
  Locale locale = const Locale('en'),
}) async {
  final sheet = FigureTextSheet(
    read: (_) => const FigureTextReading(lines: []),
    dropsPhraseLabels: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: withScope
            ? TextRecognitionScope(
                service: service,
                pickImage:
                    pick ?? () async => (name: 'card.png', bytes: _pngBytes),
                child: sheet,
              )
            : sheet,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('figure-text-sheet-field')))
    .controller!
    .text;

final _fromImage = find.byKey(const ValueKey('figure-text-sheet-from-image'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('choosing a picture of a card fills the text box with its '
      'lines, replacing what was typed', (tester) async {
    final recognizer = _FakeRecognizer();
    await _pumpSheet(tester, service: recognizer);
    await tester.enterText(
      find.byKey(const ValueKey('figure-text-sheet-field')),
      'typed before',
    );
    await tester.tap(_fromImage);
    await tester.pumpAndSettle();
    expect(_fieldText(tester), _cardText);
    expect(recognizer.recognized.single, _pngBytes);
    expect(recognizer.askedLanguages.single, ['en']);
  });

  testWidgets('in another UI language, the picture is read in that language '
      'and English', (tester) async {
    final recognizer = _FakeRecognizer(languages: const ['en', 'de']);
    await _pumpSheet(tester, service: recognizer, locale: const Locale('de'));
    expect(
      find.byKey(const ValueKey('figure-text-sheet-image-note')),
      findsNothing,
    );
    await tester.tap(_fromImage);
    await tester.pumpAndSettle();
    expect(recognizer.askedLanguages.single, ['de', 'en']);
  });

  testWidgets('when the device cannot read the UI language, it says so and '
      'reads English', (tester) async {
    final recognizer = _FakeRecognizer(languages: const ['en']);
    await _pumpSheet(tester, service: recognizer, locale: const Locale('ja'));
    expect(
      find.byKey(const ValueKey('figure-text-sheet-image-note')),
      findsOneWidget,
    );
    await tester.tap(_fromImage);
    await tester.pumpAndSettle();
    expect(recognizer.askedLanguages.single, ['en']);
  });

  testWidgets('when the device reads neither the UI language nor English, '
      'the image path explains why, offers no install, and stays off', (
    tester,
  ) async {
    final recognizer = _FakeRecognizer(languages: const []);
    await _pumpSheet(tester, service: recognizer);
    final button = tester.widget<ButtonStyleButton>(_fromImage);
    expect(button.onPressed, isNull);
    expect(
      find.text(
        "This device can't read text from pictures in the app's language or "
        'in English.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Install'), findsNothing);
    expect(find.textContaining('Windows'), findsNothing);
    // The sheet still takes typed text.
    await tester.enterText(
      find.byKey(const ValueKey('figure-text-sheet-field')),
      '(8) Swing',
    );
    expect(_fieldText(tester), '(8) Swing');
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets('on ${platform.name}, From an image… is absent and the sheet '
        'still works', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _pumpSheet(tester, withScope: false);
      expect(_fromImage, findsNothing);
      expect(
        find.byKey(const ValueKey('figure-text-sheet-field')),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  test('iOS, macOS and Windows get the native recognizer; the rest none', () {
    for (final platform in TargetPlatform.values) {
      final service = textRecognitionServiceFor(platform, isWeb: false);
      expect(
        service != null,
        const {
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        }.contains(platform),
        reason: platform.name,
      );
    }
    expect(textRecognitionServiceFor(TargetPlatform.iOS, isWeb: true), isNull);
  });

  group('on Windows, through the native channel', () {
    const channel = MethodChannel(ChannelTextRecognitionService.channelName);

    /// Answers the language query with [installed], standing in for the OCR
    /// languages whose packs are installed.
    void installed(List<String> installed) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'availableLanguages' => [
                for (final l in call.arguments as List<Object?>)
                  if (installed.contains(l)) l,
              ],
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    testWidgets('with no OCR language installed, the image path explains why, '
        'offers nothing to install, and stays off', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      installed(const []);
      await _pumpSheet(tester, withScope: false);
      expect(tester.widget<ButtonStyleButton>(_fromImage).onPressed, isNull);
      expect(
        find.byKey(const ValueKey('figure-text-sheet-image-note')),
        findsOneWidget,
      );
      expect(find.textContaining('Install'), findsNothing);
      expect(find.textContaining('install'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('with English installed, From an image… is offered', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      installed(const ['en']);
      await _pumpSheet(tester, withScope: false);
      expect(tester.widget<ButtonStyleButton>(_fromImage).onPressed, isNotNull);
      expect(
        find.byKey(const ValueKey('figure-text-sheet-image-note')),
        findsNothing,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('an over-size file is refused with a message before '
      'recognition', (tester) async {
    final recognizer = _FakeRecognizer();
    await _pumpSheet(
      tester,
      service: recognizer,
      pick: () async =>
          (name: 'big.png', bytes: Uint8List(kMaxRecognitionImageBytes + 1)),
    );
    await tester.tap(_fromImage);
    await tester.pumpAndSettle();
    expect(recognizer.recognized, isEmpty);
    expect(
      find.byKey(const ValueKey('figure-text-sheet-image-error')),
      findsOneWidget,
    );
    expect(find.textContaining('larger than 25 MB'), findsOneWidget);
    expect(_fieldText(tester), isEmpty);
  });

  testWidgets('a picker or file error shows that reading failed', (
    tester,
  ) async {
    final recognizer = _FakeRecognizer();
    await _pumpSheet(
      tester,
      service: recognizer,
      pick: () async =>
          throw const FileSystemException('iCloud file not downloaded'),
    );
    await tester.tap(_fromImage);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(recognizer.recognized, isEmpty);
    expect(find.text("The picture's text couldn't be read."), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(_fromImage).onPressed, isNotNull);
  });

  testWidgets('a failed language query leaves the image path off, with its '
      'note', (tester) async {
    await _pumpSheet(tester, service: _ThrowingAvailability());
    expect(tester.takeException(), isNull);
    expect(tester.widget<ButtonStyleButton>(_fromImage).onPressed, isNull);
    expect(
      find.byKey(const ValueKey('figure-text-sheet-image-note')),
      findsOneWidget,
    );
  });

  group('caps', () {
    Future<TextRecognitionFailure?> failure(int bytes, {ui.Size? size}) async {
      try {
        await checkRecognitionImage(
          Uint8List(bytes),
          sizeOf: (_) async => size,
        );
        return null;
      } on TextRecognitionException catch (e) {
        return e.reason;
      }
    }

    test('bytes', () async {
      expect(await failure(kMaxRecognitionImageBytes), isNull);
      expect(
        await failure(kMaxRecognitionImageBytes + 1),
        TextRecognitionFailure.tooLarge,
      );
    });

    test('a side', () async {
      const side = kMaxRecognitionImageSide * 1.0;
      expect(await failure(10, size: const ui.Size(side, 10)), isNull);
      expect(
        await failure(10, size: const ui.Size(side + 1, 10)),
        TextRecognitionFailure.tooManyPixels,
      );
      expect(
        await failure(10, size: const ui.Size(10, side + 1)),
        TextRecognitionFailure.tooManyPixels,
      );
    });

    test('pixels in all', () async {
      expect(await failure(10, size: const ui.Size(5000, 10000)), isNull);
      expect(
        await failure(10, size: const ui.Size(5001, 10000)),
        TextRecognitionFailure.tooManyPixels,
      );
    });

    test('the picker refuses an over-size file before reading it', () async {
      final dir = await Directory.systemTemp.createTemp('ocr-big');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/big.png');
      await file.writeAsBytes(Uint8List(kMaxRecognitionImageBytes + 1));
      await expectLater(
        pickRecognitionImage(
          open: () async => XFile(file.path),
          platform: TargetPlatform.macOS,
        ),
        throwsA(
          isA<TextRecognitionException>().having(
            (e) => e.reason,
            'reason',
            TextRecognitionFailure.tooLarge,
          ),
        ),
      );
    });
  });

  group('the picker From an image… opens', () {
    late PickerChannels pickers;
    late Directory temp;
    setUp(() async {
      pickers = PickerChannels.install();
      temp = await Directory.systemTemp.createTemp('ocr-pick');
      addTearDown(() => temp.delete(recursive: true));
    });

    /// A picture at [relative] in [temp], handed back by either picker.
    Future<File> picked(String relative, {List<int>? bytes}) async {
      final file = File(p.join(temp.path, relative));
      await file.create(recursive: true);
      await file.writeAsBytes(bytes ?? _pngBytes);
      pickers.path = file.path;
      return file;
    }

    test('on iPhone and iPad it is the system photo picker, asked for no '
        'more than the picture', () async {
      await picked('image_picker_0A1B.png');
      final image = await pickRecognitionImage(
        platform: TargetPlatform.iOS,
        temporaryDirectory: temp,
      );
      expect(image!.bytes, _pngBytes);
      expect(pickers.fileCalls, isEmpty);
      expect(pickers.photoPicks, hasLength(1));
      final args = pickers.photoPicks.single;
      expect(args['source'], ImageSource.gallery.index);
      // Full metadata is a photo-library lookup, which needs permission.
      expect(args['requestFullMetadata'], isFalse);
      // Scaled as a camera photo is, so a re-encoded HEIC fits the byte cap.
      expect(args['maxWidth'], kCapturedPhotoMaxSide);
      expect(args['maxHeight'], kCapturedPhotoMaxSide);
    });

    test('elsewhere it is the file picker, offering pictures', () async {
      await picked('card.png');
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.android,
      ]) {
        expect(
          (await pickRecognitionImage(platform: platform))!.bytes,
          _pngBytes,
          reason: platform.name,
        );
      }
      expect(pickers.photoPicks, isEmpty);
      expect(pickers.fileCalls, List.filled(4, 'openFile'));
      for (final args in pickers.fileArguments) {
        final groups = args['acceptedTypeGroups'] as List<Object?>;
        final group = groups.single as Map<Object?, Object?>;
        final expected = recognitionImageTypeGroup();
        expect(group['label'], expected.label);
        expect(group['extensions'], expected.extensions);
        expect(group['mimeTypes'], expected.mimeTypes);
      }
    });

    test("on iOS the photo picker's copy is deleted once read", () async {
      final copy = await picked('image_picker_0A1B.png');
      await pickRecognitionImage(
        platform: TargetPlatform.iOS,
        temporaryDirectory: temp,
      );
      expect(copy.existsSync(), isFalse);
    });

    test("on iOS the photo picker's copy is deleted unread when it is too "
        'large', () async {
      final copy = await picked(
        'image_picker_0A1B.png',
        bytes: Uint8List(kMaxRecognitionImageBytes + 1),
      );
      await expectLater(
        pickRecognitionImage(
          platform: TargetPlatform.iOS,
          temporaryDirectory: temp,
        ),
        throwsA(
          isA<TextRecognitionException>().having(
            (e) => e.reason,
            'reason',
            TextRecognitionFailure.tooLarge,
          ),
        ),
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
      await copy.writeAsBytes(_pngBytes);
      addTearDown(() async {
        if (copy.existsSync()) await copy.delete();
      });
      pickers.path = copy.path;
      await pickRecognitionImage(platform: TargetPlatform.iOS);
      expect(copy.existsSync(), isFalse);
    });

    test(
      'on iOS a file that is not the picker\'s copy is left alone',
      () async {
        for (final relative in ['card.png', 'nested/image_picker_0A1B.png']) {
          final file = await picked(relative);
          await pickRecognitionImage(
            platform: TargetPlatform.iOS,
            temporaryDirectory: temp,
          );
          expect(file.existsSync(), isTrue, reason: relative);
        }
      },
    );

    test('off iOS the picked file is left alone, whatever its name', () async {
      final file = await picked('image_picker_0A1B.png');
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        await pickRecognitionImage(
          platform: platform,
          temporaryDirectory: temp,
        );
      }
      expect(file.existsSync(), isTrue);
    });

    test('a cancel reads nothing', () async {
      expect(await pickRecognitionImage(platform: TargetPlatform.iOS), isNull);
      expect(pickers.photoPicks, hasLength(1));
    });
  });

  group('the platform channel', () {
    const channel = MethodChannel(ChannelTextRecognitionService.channelName);
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'availableLanguages' => ['en'],
              'recognize' => _cardText,
              _ => null,
            };
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('reads through the channel with HTTP disabled', () async {
      await HttpOverrides.runZoned(() async {
        final service = ChannelTextRecognitionService();
        final availability = await service.availability(['de', 'en']);
        expect(availability.languages, ['en']);
        expect(
          await service.recognize(_pngBytes, languages: ['en']),
          _cardText,
        );
      }, createHttpClient: (_) => throw StateError('no network'));
      expect(calls.map((c) => c.method), ['availableLanguages', 'recognize']);
      expect(calls.last.arguments, {
        'bytes': _pngBytes,
        'languages': ['en'],
      });
    });

    test('a native error maps to its failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'unreadable');
          });
      await expectLater(
        ChannelTextRecognitionService().recognize(_pngBytes, languages: ['en']),
        throwsA(
          isA<TextRecognitionException>().having(
            (e) => e.reason,
            'reason',
            TextRecognitionFailure.unreadable,
          ),
        ),
      );
    });

    test('no native recognizer reads as no languages', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(
        (await ChannelTextRecognitionService().availability([
          'en',
        ])).isAvailable,
        isFalse,
      );
    });

    test('empty text reads as no text found', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => '  \n');
      await expectLater(
        ChannelTextRecognitionService().recognize(_pngBytes, languages: ['en']),
        throwsA(
          isA<TextRecognitionException>().having(
            (e) => e.reason,
            'reason',
            TextRecognitionFailure.noText,
          ),
        ),
      );
    });
  });

  test('a PNG header gives its size without decoding', () async {
    final size = await encodedImageSize(_pngBytes);
    expect(size, const ui.Size(1, 1));
    expect(await encodedImageSize(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
