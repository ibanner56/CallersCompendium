import 'package:compendium_app/src/data/incoming_file_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for [IncomingFileChannel], the single native→Dart seam that
/// carries shared files (#298) and shared URLs (#343 / #428) to the app.
///
/// On iOS the fix for #428 delivers drained App-Group payloads through exactly
/// this channel — cold-start via the `getInitialUrl` pull and warm delivery via
/// the `urlShared` method call — so these tests pin the delivery contract the
/// native drain depends on, and the fail-closed handling of blank/absent
/// payloads (junk is dropped, never surfaced to the import pipeline).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const MethodChannel platformChannel = MethodChannel(
    IncomingFileChannel.channelName,
  );
  const StandardMethodCodec codec = StandardMethodCodec();

  /// Simulates the native side invoking [method] with [arguments] on the
  /// channel, exactly as `IncomingFilesPlugin` does when it drains a shared URL.
  Future<void> sendFromNative(String method, Object? arguments) {
    return messenger.handlePlatformMessage(
      IncomingFileChannel.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  group('warm delivery (urlShared / fileOpened)', () {
    test('a shared URL is surfaced on the urls stream', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final urls = <String>[];
      final sub = channel.urls.listen(urls.add);
      addTearDown(sub.cancel);

      await sendFromNative('urlShared', 'https://contradb.com/programs/33');
      await pumpEventQueue();

      expect(urls, <String>['https://contradb.com/programs/33']);
    });

    test('an opened file path is surfaced on the files stream', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final files = <String>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      await sendFromNative('fileOpened', '/tmp/incoming/bundle.json');
      await pumpEventQueue();

      expect(files, <String>['/tmp/incoming/bundle.json']);
    });

    test('multiple drained URLs are each delivered in order', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final urls = <String>[];
      final sub = channel.urls.listen(urls.add);
      addTearDown(sub.cancel);

      await sendFromNative('urlShared', 'https://contradb.com/programs/1');
      await sendFromNative('urlShared', 'https://contradb.com/programs/2');
      await pumpEventQueue();

      expect(urls, <String>[
        'https://contradb.com/programs/1',
        'https://contradb.com/programs/2',
      ]);
    });

    test('blank or non-string payloads are dropped (fail closed)', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final urls = <String>[];
      final files = <String>[];
      final urlSub = channel.urls.listen(urls.add);
      final fileSub = channel.files.listen(files.add);
      addTearDown(urlSub.cancel);
      addTearDown(fileSub.cancel);

      await sendFromNative('urlShared', '');
      await sendFromNative('urlShared', null);
      await sendFromNative('urlShared', 42);
      await sendFromNative('fileOpened', '');
      await pumpEventQueue();

      expect(urls, isEmpty);
      expect(files, isEmpty);
    });
  });

  group('cold-start pulls (getInitialUrl / getInitialFile)', () {
    test(
      'getInitialUrl returns the URL the app was launched to import',
      () async {
        messenger.setMockMethodCallHandler(platformChannel, (call) async {
          return call.method == 'getInitialUrl'
              ? 'https://contradb.com/programs/7'
              : null;
        });

        final channel = IncomingFileChannel();
        addTearDown(channel.dispose);

        expect(await channel.initialUrl(), 'https://contradb.com/programs/7');
      },
    );

    test('getInitialUrl treats an empty native result as no URL', () async {
      messenger.setMockMethodCallHandler(platformChannel, (call) async => '');

      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);

      expect(await channel.initialUrl(), isNull);
    });

    test('a missing native implementation resolves to no URL', () async {
      // No mock handler registered → MissingPluginException, swallowed so the
      // app never fails to start over intake.
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);

      expect(await channel.initialUrl(), isNull);
      expect(await channel.initialFile(), isNull);
    });
  });
}
