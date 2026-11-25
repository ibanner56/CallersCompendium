import 'dart:convert';
import 'dart:io';

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

const _cardText = 'A1 (8) Neighbor balance & swing\n(8) Long lines';

final Uint8List _photoBytes = Uint8List.fromList(List.filled(64, 7));

/// A recognizer that reads every picture as [_cardText] and records what it
/// was given.
class _FakeRecognizer implements TextRecognitionService {
  _FakeRecognizer({this.languages = const ['en']});

  final List<String> languages;
  final recognized = <Uint8List>[];

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
    return _cardText;
  }
}

/// A camera that answers [take] and records the byte cap it was given.
class _FakeCamera implements PhotoCaptureService {
  _FakeCamera(this.take);

  final Future<Uint8List?> Function() take;
  final caps = <int>[];

  @override
  Future<Uint8List?> takePhoto({required int maxBytes}) {
    caps.add(maxBytes);
    return take();
  }
}

/// A photo file whose read fails, as when the camera's file vanishes.
class _UnreadableXFile extends XFile {
  _UnreadableXFile(super.path);

  @override
  Future<Uint8List> readAsBytes() =>
      Future.error(const FileSystemException('read failed'));
}

final _takePhoto = find.byKey(const ValueKey('figure-text-sheet-take-photo'));
final _fromImage = find.byKey(const ValueKey('figure-text-sheet-from-image'));
final _field = find.byKey(const ValueKey('figure-text-sheet-field'));

Future<void> _pumpSheet(
  WidgetTester tester, {
  required TextRecognitionService recognizer,
  PhotoCaptureService? camera,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: PhotoCaptureScope(
          service: camera,
          child: TextRecognitionScope(
            service: recognizer,
            pickImage: () async => null,
            child: FigureTextSheet(
              read: (_) => const FigureTextReading(lines: []),
              dropsPhraseLabels: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sheet', () {
    testWidgets('a photo of a card fills the text box with its lines', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      final camera = _FakeCamera(() async => _photoBytes);
      await _pumpSheet(tester, recognizer: recognizer, camera: camera);
      await tester.enterText(_field, 'typed before');
      await tester.tap(_takePhoto);
      await tester.pumpAndSettle();
      expect(_fieldText(tester), _cardText);
      expect(recognizer.recognized.single, _photoBytes);
      expect(camera.caps.single, kMaxRecognitionImageBytes);
      expect(_fromImage, findsOneWidget);
    });

    testWidgets('cancelling the camera leaves the box as it was', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      await _pumpSheet(
        tester,
        recognizer: recognizer,
        camera: _FakeCamera(() async => null),
      );
      await tester.enterText(_field, 'typed before');
      await tester.tap(_takePhoto);
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'typed before');
      expect(recognizer.recognized, isEmpty);
      expect(
        find.byKey(const ValueKey('figure-text-sheet-image-error')),
        findsNothing,
      );
    });

    testWidgets('an over-size photo is refused with the size message', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      await _pumpSheet(
        tester,
        recognizer: recognizer,
        camera: _FakeCamera(
          () async =>
              throw const PhotoCaptureException(PhotoCaptureFailure.tooLarge),
        ),
      );
      await tester.tap(_takePhoto);
      await tester.pumpAndSettle();
      expect(recognizer.recognized, isEmpty);
      expect(find.textContaining('larger than 25 MB'), findsOneWidget);
    });

    testWidgets('a camera error shows that reading failed', (tester) async {
      final recognizer = _FakeRecognizer();
      await _pumpSheet(
        tester,
        recognizer: recognizer,
        camera: _FakeCamera(() async => throw StateError('camera gone')),
      );
      await tester.tap(_takePhoto);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("The picture's text couldn't be read."), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(_takePhoto).onPressed, isNotNull);
    });

    testWidgets('with camera access off, it says how to turn it on', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      await _pumpSheet(
        tester,
        recognizer: recognizer,
        camera: _FakeCamera(
          () async => throw const PhotoCaptureException(
            PhotoCaptureFailure.accessDenied,
          ),
        ),
      );
      await tester.tap(_takePhoto);
      await tester.pumpAndSettle();
      expect(recognizer.recognized, isEmpty);
      expect(
        find.text(
          "Camera access is off for Caller's Compendium. To take a photo, "
          'turn it on in the Settings app.',
        ),
        findsOneWidget,
      );
    });

    for (final (platform, offered) in [
      (TargetPlatform.iOS, true),
      (TargetPlatform.macOS, false),
    ]) {
      testWidgets('with no camera supplied, ${platform.name} '
          '${offered ? 'offers' : 'does not offer'} Take a photo', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              body: TextRecognitionScope(
                service: _FakeRecognizer(),
                pickImage: () async => null,
                child: FigureTextSheet(
                  read: (_) => const FigureTextReading(lines: []),
                  dropsPhraseLabels: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_takePhoto, offered ? findsOneWidget : findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('without a camera, only From an image… is offered', (
      tester,
    ) async {
      await _pumpSheet(tester, recognizer: _FakeRecognizer());
      expect(_takePhoto, findsNothing);
      expect(_fromImage, findsOneWidget);
    });

    testWidgets('when the device reads no wanted language, Take a photo is '
        'off too', (tester) async {
      await _pumpSheet(
        tester,
        recognizer: _FakeRecognizer(languages: const []),
        camera: _FakeCamera(() async => _photoBytes),
      );
      expect(tester.widget<ButtonStyleButton>(_takePhoto).onPressed, isNull);
      expect(tester.widget<ButtonStyleButton>(_fromImage).onPressed, isNull);
    });
  });

  test('only iOS gets a camera', () {
    for (final platform in TargetPlatform.values) {
      expect(
        photoCaptureServiceFor(platform, isWeb: false) != null,
        platform == TargetPlatform.iOS,
        reason: platform.name,
      );
    }
    expect(photoCaptureServiceFor(TargetPlatform.iOS, isWeb: true), isNull);
  });

  group('the captured file', () {
    /// A fresh folder standing in for the app's temporary folder, holding
    /// a photo file named as the camera plugin names them.
    Future<(Directory, File)> photoIn({List<int>? bytes}) async {
      final temp = await Directory.systemTemp.createTemp('camera-temp');
      addTearDown(() => temp.delete(recursive: true));
      final file = File(p.join(temp.path, 'image_picker_1234ABCD.jpg'));
      await file.writeAsBytes(bytes ?? _photoBytes);
      return (temp, file);
    }

    test('is read, then deleted', () async {
      final (temp, photo) = await photoIn();
      final camera = SystemCameraPhotoCapture(
        capture: () async => XFile(photo.path),
        temporaryDirectory: temp,
      );
      expect(await camera.takePhoto(maxBytes: 1024), _photoBytes);
      expect(photo.existsSync(), isFalse);
    });

    test('is deleted when it is over the cap, unread', () async {
      final (temp, photo) = await photoIn(bytes: List.filled(2048, 1));
      final camera = SystemCameraPhotoCapture(
        capture: () async => XFile(photo.path),
        temporaryDirectory: temp,
      );
      await expectLater(
        camera.takePhoto(maxBytes: 1024),
        throwsA(
          isA<PhotoCaptureException>().having(
            (e) => e.reason,
            'reason',
            PhotoCaptureFailure.tooLarge,
          ),
        ),
      );
      expect(photo.existsSync(), isFalse);
    });

    test('is deleted when reading it fails', () async {
      final (temp, photo) = await photoIn();
      final camera = SystemCameraPhotoCapture(
        capture: () async => _UnreadableXFile(photo.path),
        temporaryDirectory: temp,
      );
      await expectLater(
        camera.takePhoto(maxBytes: 1024),
        throwsA(isA<FileSystemException>()),
      );
      expect(photo.existsSync(), isFalse);
    });

    for (final code in ['camera_access_denied', 'camera_access_restricted']) {
      test('$code reads as camera access off', () async {
        final camera = SystemCameraPhotoCapture(
          capture: () async => throw PlatformException(code: code),
        );
        await expectLater(
          camera.takePhoto(maxBytes: 1024),
          throwsA(
            isA<PhotoCaptureException>().having(
              (e) => e.reason,
              'reason',
              PhotoCaptureFailure.accessDenied,
            ),
          ),
        );
      });
    }

    test('another camera error is passed on as it is', () async {
      final camera = SystemCameraPhotoCapture(
        capture: () async =>
            throw PlatformException(code: 'no_available_camera'),
      );
      await expectLater(
        camera.takePhoto(maxBytes: 1024),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a cancelled camera returns null and deletes nothing', () async {
      final (temp, earlier) = await photoIn();
      final camera = SystemCameraPhotoCapture(
        capture: () async => null,
        temporaryDirectory: temp,
      );
      expect(await camera.takePhoto(maxBytes: 1024), isNull);
      expect(earlier.existsSync(), isTrue);
    });

    test('by default it is looked for in the system temporary folder '
        '(NSTemporaryDirectory on iOS)', () async {
      final photo = File(
        p.join(
          Directory.systemTemp.path,
          'image_picker_${DateTime.now().microsecondsSinceEpoch}.jpg',
        ),
      );
      await photo.writeAsBytes(_photoBytes);
      addTearDown(() async {
        if (photo.existsSync()) await photo.delete();
      });
      await SystemCameraPhotoCapture(
        capture: () async => XFile(photo.path),
      ).takePhoto(maxBytes: 1024);
      expect(photo.existsSync(), isFalse);
    });

    test('a temporary folder reached through a link still matches', () async {
      final (temp, photo) = await photoIn();
      final links = await Directory.systemTemp.createTemp('camera-link');
      addTearDown(() => links.delete(recursive: true));
      final link = await Link(p.join(links.path, 'tmp')).create(temp.path);
      await SystemCameraPhotoCapture(
        capture: () async => XFile(p.join(link.path, p.basename(photo.path))),
        temporaryDirectory: Directory(link.path),
      ).takePhoto(maxBytes: 1024);
      expect(photo.existsSync(), isFalse);
    });

    group('only the camera plugin\'s own files are deleted', () {
      test('not a file of another name in the temporary folder', () async {
        final temp = await Directory.systemTemp.createTemp('camera-temp');
        addTearDown(() => temp.delete(recursive: true));
        final other = File(p.join(temp.path, 'notes.jpg'));
        await other.writeAsBytes(_photoBytes);
        await deleteCapturedPhoto(other.path, temporaryDirectory: temp);
        expect(other.existsSync(), isTrue);
      });

      test('not a camera-named file in a subfolder', () async {
        final temp = await Directory.systemTemp.createTemp('camera-temp');
        addTearDown(() => temp.delete(recursive: true));
        final nested = File(p.join(temp.path, 'kept', 'image_picker_1.jpg'));
        await nested.create(recursive: true);
        await deleteCapturedPhoto(nested.path, temporaryDirectory: temp);
        expect(nested.existsSync(), isTrue);
      });

      test('not a camera-named file outside the temporary folder', () async {
        final temp = await Directory.systemTemp.createTemp('camera-temp');
        final elsewhere = await Directory.systemTemp.createTemp('camera-else');
        addTearDown(() => temp.delete(recursive: true));
        addTearDown(() => elsewhere.delete(recursive: true));
        final outside = File(p.join(elsewhere.path, 'image_picker_1.jpg'));
        await outside.writeAsBytes(_photoBytes);
        await deleteCapturedPhoto(outside.path, temporaryDirectory: temp);
        expect(outside.existsSync(), isTrue);
      });

      test('not through a link in the temporary folder to a file outside '
          'it', () async {
        final temp = await Directory.systemTemp.createTemp('camera-temp');
        final elsewhere = await Directory.systemTemp.createTemp('camera-else');
        addTearDown(() => temp.delete(recursive: true));
        addTearDown(() => elsewhere.delete(recursive: true));
        final target = File(p.join(elsewhere.path, 'image_picker_1.jpg'));
        await target.writeAsBytes(_photoBytes);
        final link = await Link(
          p.join(temp.path, 'image_picker_2.jpg'),
        ).create(target.path);
        await deleteCapturedPhoto(link.path, temporaryDirectory: temp);
        expect(target.existsSync(), isTrue);
      });

      test('a missing file is no error', () async {
        final temp = await Directory.systemTemp.createTemp('camera-temp');
        addTearDown(() => temp.delete(recursive: true));
        await deleteCapturedPhoto(
          p.join(temp.path, 'image_picker_gone.jpg'),
          temporaryDirectory: temp,
        );
        await deleteCapturedPhoto('', temporaryDirectory: temp);
      });
    });
  });

  group('platform declarations', () {
    test('no Android manifest declares the CAMERA permission: photos are '
        'taken through the system camera app', () {
      final manifests = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == 'AndroidManifest.xml')
          .toList();
      expect(manifests, isNotEmpty);
      for (final manifest in manifests) {
        expect(
          manifest.readAsStringSync(),
          isNot(contains('android.permission.CAMERA')),
          reason: manifest.path,
        );
      }
    });

    test('no Android plugin the app links declares the CAMERA permission '
        'either, since its manifest is merged into the app', () {
      // Written by `flutter pub get`; fail rather than pass when it is absent.
      final dependencies = File('.flutter-plugins-dependencies');
      expect(dependencies.existsSync(), isTrue);
      final plugins =
          (jsonDecode(dependencies.readAsStringSync())
                  as Map<String, dynamic>)['plugins']['android']
              as List<dynamic>;
      final manifests = [
        for (final plugin in plugins.cast<Map<String, dynamic>>())
          File(
            p.join(
              plugin['path'] as String,
              'android',
              'src',
              'main',
              'AndroidManifest.xml',
            ),
          ),
      ].where((f) => f.existsSync()).toList();
      expect(
        manifests.map((f) => f.path),
        contains(contains('image_picker_android')),
      );
      for (final manifest in manifests) {
        expect(
          manifest.readAsStringSync(),
          isNot(contains('android.permission.CAMERA')),
          reason: manifest.path,
        );
      }
    });

    for (final key in [
      'NSCameraUsageDescription',
      // Never asked for (the camera path needs no library access), but the
      // camera plugin links the Photos API, so App Store review requires it.
      'NSPhotoLibraryUsageDescription',
    ]) {
      test('iOS has a $key purpose string', () {
        final plist = File('ios/Runner/Info.plist').readAsStringSync();
        final match = RegExp(
          '<key>$key</key>\\s*<string>([^<]+)</string>',
        ).firstMatch(plist);
        expect(match, isNotNull);
        expect(match!.group(1)!.trim(), isNotEmpty);
      });
    }

    test('every other iOS language translates both purpose strings', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final languages = RegExp(r'<string>([^<]+)</string>')
          .allMatches(
            RegExp(
              r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
              dotAll: true,
            ).firstMatch(plist)!.group(1)!,
          )
          .map((m) => m.group(1)!)
          .where((language) => language != 'en')
          .toList();
      expect(languages, containsAll(['da', 'de', 'fr', 'ja', 'nl']));

      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final resources = RegExp(
        r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{.*?files = \((.*?)\);',
        dotAll: true,
      ).firstMatch(project)!.group(1)!;
      final group = RegExp(
        r'(\w+) /\* InfoPlist.strings \*/ = \{\s*isa = PBXVariantGroup;'
        r'\s*children = \((.*?)\);',
        dotAll: true,
      ).firstMatch(project);
      expect(group, isNotNull);
      final buildFile = RegExp(
        r'(\w+) /\* InfoPlist.strings in Resources \*/ = \{isa = PBXBuildFile; '
        'fileRef = ${group!.group(1)} ',
      ).firstMatch(project);
      expect(buildFile, isNotNull);
      expect(resources, contains('${buildFile!.group(1)} /*'));

      for (final language in languages) {
        final child = RegExp(
          '(\\w+) /\\* $language \\*/,',
        ).firstMatch(group.group(2)!);
        expect(child, isNotNull, reason: language);
        expect(
          project,
          contains(
            '${child!.group(1)} /* $language */ = {isa = PBXFileReference; '
            'lastKnownFileType = text.plist.strings; name = $language; '
            'path = $language.lproj/InfoPlist.strings;',
          ),
          reason: language,
        );
        final strings = File(
          'ios/Runner/$language.lproj/InfoPlist.strings',
        ).readAsStringSync();
        for (final key in [
          'NSCameraUsageDescription',
          'NSPhotoLibraryUsageDescription',
        ]) {
          final match = RegExp(
            '^"$key" = "([^"\\n]+)";\$',
            multiLine: true,
          ).firstMatch(strings);
          expect(match, isNotNull, reason: '$language $key');
          final english = RegExp(
            '<key>$key</key>\\s*<string>([^<]+)</string>',
          ).firstMatch(plist)!.group(1);
          expect(
            match!.group(1),
            isNot(english),
            reason: '$language $key is still English',
          );
        }
      }
    });
  });
}
