import 'dart:typed_data';

import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/dance_code_scanner.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/photo_capture.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dance_links.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// **Scan a dance code** in Import (#2336): a photo from the shared camera
/// service, a QR code found in it, and the code's link opened exactly as a
/// pasted link is (#2335). No network.

/// A decoder that answers [answer] for every picture and records them.
class _FakeDecoder implements DanceCodeDecoder {
  _FakeDecoder(this.answer);

  final Future<String> Function() answer;
  final pictures = <Uint8List>[];

  @override
  Future<String> decode(Uint8List encodedPicture) {
    pictures.add(encodedPicture);
    return answer();
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

final _photo = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
final _scan = find.byKey(const ValueKey('import-scan-dance-code'));

void main() {
  final l10n = AppLocalizationsEn();
  late List<String> fetched;
  setUp(() => fetched = []);

  Future<String> recordingFetcher(String url) async {
    fetched.add(url);
    throw StateError('no network while scanning a dance code');
  }

  Future<CompendiumRepositories> pumpImport(
    WidgetTester tester, {
    PhotoCaptureService? camera,
    DanceCodeDecoder? decoder,
    Future<Uint8List?> Function()? pickPicture,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await tester.pumpWidget(
      MaterialApp(
        // A fresh screen each time, so a second pump starts over.
        key: UniqueKey(),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: PhotoCaptureScope(
            service: camera,
            child: DanceCodeDecoderScope(
              decoder: decoder ?? _FakeDecoder(() async => goodDanceLink()),
              pickPicture:
                  pickPicture ??
                  () => Future.error(StateError('no picker in this test')),
              child: ImportReviewScreen(
                sources: defaultImportSources(),
                fetcher: recordingFetcher,
                onlineService: CallersBoxOnline(jsonFetcher: recordingFetcher),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> scan(WidgetTester tester) async {
    await tester.tap(_scan);
    await tester.pumpAndSettle();
  }

  Future<List<String>> committedTitles(
    WidgetTester tester,
    CompendiumRepositories repos,
  ) async {
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    // Ids are new on every import, so the dances are compared without them.
    return [
      for (final d in await repos.dances.listAll())
        '${d.title} | ${d.formation}',
    ];
  }

  testWidgets('without a camera, Scan a dance code is not offered', (
    tester,
  ) async {
    await pumpImport(tester);
    expect(find.byKey(const ValueKey('import-choose-file')), findsOneWidget);
    expect(_scan, findsNothing);
  });

  testWidgets('a scanned code opens the same review a pasted link does, '
      'and imports the same dance', (tester) async {
    final camera = _FakeCamera(() async => _photo);
    final decoder = _FakeDecoder(() async => goodDanceLink());
    final scanned = await pumpImport(tester, camera: camera, decoder: decoder);

    expect(find.text(l10n.importScanDanceCode), findsOneWidget);
    await scan(tester);

    expect(camera.caps, [kDanceCodePhotoMaxBytes]);
    expect(decoder.pictures, [_photo]);
    expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
    expect(find.text(danceLinkTitle), findsWidgets);
    expect(await scanned.dances.listAll(), isEmpty);
    final fromScan = await committedTitles(tester, scanned);

    // The same link, pasted into a fresh screen.
    final pasted = await pumpImport(tester);
    await tester.enterText(
      find.byKey(const ValueKey('import-url-field')),
      goodDanceLink(),
    );
    await tester.tap(find.byKey(const ValueKey('import-fetch-url')));
    await tester.pumpAndSettle();
    final fromPaste = await committedTitles(tester, pasted);

    expect(fromScan, hasLength(1));
    expect(fromScan.single, startsWith('$danceLinkTitle |'));
    expect(fromScan, fromPaste);
    expect(fetched, isEmpty);
  });

  testWidgets('cancelling the camera leaves the screen as it was', (
    tester,
  ) async {
    final decoder = _FakeDecoder(() async => goodDanceLink());
    await pumpImport(
      tester,
      camera: _FakeCamera(() async => null),
      decoder: decoder,
    );
    await scan(tester);
    expect(decoder.pictures, isEmpty);
    expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
    expect(find.byKey(const ValueKey('import-url-error')), findsNothing);
    expect(tester.widget<ButtonStyleButton>(_scan).onPressed, isNotNull);
  });

  group('a photo that does not open a dance is refused with a message', () {
    Future<void> expectRefused(
      WidgetTester tester,
      DanceCodeDecoder decoder,
      String message,
    ) async {
      final repos = await pumpImport(
        tester,
        camera: _FakeCamera(() async => _photo),
        decoder: decoder,
      );
      await scan(tester);
      expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('import-url-error')),
          matching: find.text(message),
        ),
        findsOneWidget,
      );
      expect(await repos.dances.listAll(), isEmpty);
      expect(fetched, isEmpty);
    }

    DanceCodeDecoder failing(DanceCodeScanFailure failure) =>
        _FakeDecoder(() => Future.error(DanceCodeScanException(failure)));

    testWidgets('no code in the photo', (tester) async {
      await expectRefused(
        tester,
        failing(DanceCodeScanFailure.noCode),
        l10n.importScanNoCode,
      );
    });

    testWidgets('a code too damaged to read', (tester) async {
      await expectRefused(
        tester,
        failing(DanceCodeScanFailure.damagedCode),
        l10n.danceLinkRefusedDamaged,
      );
    });

    testWidgets('a picture that cannot be opened', (tester) async {
      await expectRefused(
        tester,
        failing(DanceCodeScanFailure.unreadablePicture),
        l10n.importScanUnreadable,
      );
    });

    testWidgets('a QR code that is not a dance code is not fetched', (
      tester,
    ) async {
      await expectRefused(
        tester,
        _FakeDecoder(() async => 'https://example.com/dance'),
        l10n.danceLinkRefusedNotADance,
      );
    });

    testWidgets('a dance code cut short', (tester) async {
      await expectRefused(
        tester,
        _FakeDecoder(() async => truncatedDanceLink()),
        l10n.danceLinkRefusedDamaged,
      );
    });

    testWidgets('a dance code from a newer app', (tester) async {
      await expectRefused(
        tester,
        _FakeDecoder(() async => unknownVersionDanceLink()),
        l10n.danceLinkRefusedNewerVersion,
      );
    });

    testWidgets('camera access that is off says how to turn it on', (
      tester,
    ) async {
      final repos = await pumpImport(
        tester,
        camera: _FakeCamera(
          () => Future.error(
            const PhotoCaptureException(PhotoCaptureFailure.accessDenied),
          ),
        ),
      );
      await scan(tester);
      expect(find.text(l10n.importScanCameraOff), findsOneWidget);
      expect(await repos.dances.listAll(), isEmpty);
    });

    testWidgets('a device without a camera app points to a picture', (
      tester,
    ) async {
      await pumpImport(
        tester,
        camera: _FakeCamera(
          () => Future.error(
            const PhotoCaptureException(PhotoCaptureFailure.noCamera),
          ),
        ),
      );
      await scan(tester);
      expect(find.text(l10n.importScanNoCamera), findsOneWidget);
    });

    testWidgets('an unexpected camera error', (tester) async {
      await pumpImport(
        tester,
        camera: _FakeCamera(() => Future.error(StateError('camera broke'))),
      );
      await scan(tester);
      expect(find.text(l10n.importScanUnreadable), findsOneWidget);
    });
  });

  group('Dance code from a picture…', () {
    final picture = find.byKey(const ValueKey('import-dance-code-picture'));

    testWidgets('is offered without a camera, and opens the same review', (
      tester,
    ) async {
      final decoder = _FakeDecoder(() async => goodDanceLink());
      final repos = await pumpImport(
        tester,
        decoder: decoder,
        pickPicture: () async => _photo,
      );
      expect(_scan, findsNothing);
      expect(find.text(l10n.importDanceCodePicture), findsOneWidget);

      await tester.tap(picture);
      await tester.pumpAndSettle();

      expect(decoder.pictures, [_photo]);
      expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
      expect(await committedTitles(tester, repos), hasLength(1));
      expect(fetched, isEmpty);
    });

    testWidgets('a cancelled picker leaves the screen as it was', (
      tester,
    ) async {
      final decoder = _FakeDecoder(() async => goodDanceLink());
      await pumpImport(tester, decoder: decoder, pickPicture: () async => null);
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(decoder.pictures, isEmpty);
      expect(find.byKey(const ValueKey('import-url-error')), findsNothing);
    });

    testWidgets('a picture over the size cap is refused unread', (
      tester,
    ) async {
      final decoder = _FakeDecoder(() async => goodDanceLink());
      await pumpImport(
        tester,
        decoder: decoder,
        pickPicture: () => Future.error(const DanceCodePictureTooLarge()),
      );
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(decoder.pictures, isEmpty);
      expect(find.text(l10n.importScanTooLarge(25)), findsOneWidget);
    });

    testWidgets('a cloud picture the picker cannot read is refused, not '
        'taken for a cancel', (tester) async {
      // file_selector_android completes with an error when the provider
      // reports no size for the chosen file (a cloud file not yet on the
      // phone), or gives no stream for it.
      final decoder = _FakeDecoder(() async => goodDanceLink());
      await pumpImport(
        tester,
        decoder: decoder,
        pickPicture: () => pickDanceCodePicture(
          open: () => Future.error(
            PlatformException(
              code: 'Exception',
              message: 'Failed to read file: content://cloud/picture',
            ),
          ),
          platform: TargetPlatform.android,
        ),
      );
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(decoder.pictures, isEmpty);
      expect(find.text(l10n.importScanUnreadable), findsOneWidget);
    });

    testWidgets('a picture with no code says so', (tester) async {
      await pumpImport(
        tester,
        decoder: _FakeDecoder(
          () => Future.error(
            const DanceCodeScanException(DanceCodeScanFailure.noCode),
          ),
        ),
        pickPicture: () async => _photo,
      );
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(find.text(l10n.importScanNoCode), findsOneWidget);
    });
  });
}
