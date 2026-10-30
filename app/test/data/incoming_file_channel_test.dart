import 'dart:io';

import 'package:compendium_app/src/data/archive_intake_service.dart'
    show kMaxIncomingArchiveBytes;
import 'package:compendium_app/src/data/incoming_file_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

    test('a legacy opened file path is surfaced as unowned', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final files = <IncomingFile>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      await sendFromNative('fileOpened', '/tmp/incoming/bundle.json');
      await pumpEventQueue();

      expect(files, <IncomingFile>[
        const IncomingFile(path: '/tmp/incoming/bundle.json', appOwned: false),
      ]);
    });

    test('a native file map preserves its ownership marker', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final files = <IncomingFile>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      await sendFromNative('fileOpened', <String, Object>{
        'path': '/tmp/incoming/bundle.json',
        'appOwned': true,
      });
      await pumpEventQueue();

      expect(files, <IncomingFile>[
        const IncomingFile(path: '/tmp/incoming/bundle.json', appOwned: true),
      ]);
    });

    test('a native tooLarge rejection is surfaced with no path', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      channel.start();

      final files = <IncomingFile>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      await sendFromNative('fileOpened', <String, Object>{
        'rejected': 'tooLarge',
      });
      await sendFromNative('fileOpened', <String, Object>{
        'rejected': 'somethingElse',
      });
      await pumpEventQueue();

      expect(files, <IncomingFile>[
        const IncomingFile.rejected(IncomingFileRejection.tooLarge),
      ]);
      expect(files.single.path, isEmpty);
      expect(files.single.appOwned, isFalse);
    });

    test(
      'a cold-start tooLarge rejection is returned by initialFile',
      () async {
        messenger.setMockMethodCallHandler(platformChannel, (call) async {
          expect(call.method, 'getInitialFile');
          return <String, Object>{'rejected': 'tooLarge'};
        });

        final file = await IncomingFileChannel().initialFile();

        expect(
          file,
          const IncomingFile.rejected(IncomingFileRejection.tooLarge),
        );
      },
    );

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
      final files = <IncomingFile>[];
      final urlSub = channel.urls.listen(urls.add);
      final fileSub = channel.files.listen(files.add);
      addTearDown(urlSub.cancel);
      addTearDown(fileSub.cancel);

      await sendFromNative('urlShared', '');
      await sendFromNative('urlShared', null);
      await sendFromNative('urlShared', 42);
      await sendFromNative('fileOpened', '');
      await sendFromNative('fileOpened', <String, Object>{
        'path': '/tmp/incoming/bundle.json',
      });
      await sendFromNative('fileOpened', <String, Object>{
        'path': '/tmp/incoming/bundle.json',
        'appOwned': 'true',
      });
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

    test('getInitialFile decodes the native ownership marker', () async {
      messenger.setMockMethodCallHandler(
        platformChannel,
        (call) async => call.method == 'getInitialFile'
            ? <String, Object>{
                'path': '/tmp/incoming/bundle.json',
                'appOwned': true,
              }
            : null,
      );

      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);

      expect(
        await channel.initialFile(),
        const IncomingFile(path: '/tmp/incoming/bundle.json', appOwned: true),
      );
    });

    test('getInitialFile treats a legacy string as unowned', () async {
      messenger.setMockMethodCallHandler(
        platformChannel,
        (call) async => call.method == 'getInitialFile'
            ? '/tmp/incoming/bundle.json'
            : null,
      );

      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);

      expect(
        await channel.initialFile(),
        const IncomingFile(path: '/tmp/incoming/bundle.json', appOwned: false),
      );
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

  // PLAT-3: Windows and Linux have no native side; a desktop launch hands the
  // channel a path from its command line or from a second launch. That path
  // is untrusted (any local process can send one), so only a checked, local
  // .ccshare file gets through, and it is never marked app-owned, which would
  // let intake delete the user's own copy.
  group('desktop opens (openDesktopPath / initialDesktopPath)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('incoming_desktop_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    File shareFile(String name, {int bytes = 16}) =>
        File(p.join(dir.path, name))
          ..writeAsBytesSync(List<int>.filled(bytes, 0x20));

    test('a command-line file is the initial file, unowned', () async {
      final file = shareFile('Contra Night.ccshare');
      final channel = IncomingFileChannel(initialDesktopPath: file.path);
      addTearDown(channel.dispose);

      expect(
        await channel.initialFile(),
        IncomingFile(path: file.path, appOwned: false),
      );
      // Taken once: it is not offered again.
      expect(await channel.initialFile(), isNull);
    });

    test('an open that arrives before the app is ready waits for '
        'initialFile, and later opens go to the files stream', () async {
      final early = shareFile('early.ccshare');
      final late = shareFile('late.ccshare');
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      final files = <IncomingFile>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      channel.openDesktopPath(early.path);
      await channel.desktopOpensSettled;
      expect(files, isEmpty);

      final initial = await channel.initialFile();
      expect(initial, IncomingFile(path: early.path, appOwned: false));
      channel.fileHandled(initial!);

      channel.openDesktopPath(late.path);
      await channel.desktopOpensSettled;
      await pumpEventQueue();
      expect(files, [IncomingFile(path: late.path, appOwned: false)]);
    });

    test('a path the associations never send is dropped, before and after the '
        'app is ready', () async {
      final json = shareFile('backup.json');
      final channel = IncomingFileChannel(initialDesktopPath: json.path);
      addTearDown(channel.dispose);
      final files = <IncomingFile>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      expect(await channel.initialFile(), isNull);

      for (final raw in [
        json.path,
        'relative.ccshare',
        '${shareFile('ok.ccshare').path}\n',
      ]) {
        channel.openDesktopPath(raw);
      }
      await channel.desktopOpensSettled;
      await pumpEventQueue();

      expect(files, isEmpty);
    });

    test(
      'a network-share path arrives as unreadable, so the user is told',
      () async {
        final channel = IncomingFileChannel();
        addTearDown(channel.dispose);
        expect(await channel.initialFile(), isNull);
        final files = <IncomingFile>[];
        final sub = channel.files.listen(files.add);
        addTearDown(sub.cancel);

        channel.openDesktopPath(r'\\attacker\share\x.ccshare');
        await channel.desktopOpensSettled;
        await pumpEventQueue();

        expect(files, [
          const IncomingFile.rejected(IncomingFileRejection.unreadable),
        ]);
      },
    );

    test('opens are coalesced: one in intake at a time, only the latest waits, '
        'and it goes through once the first is handled', () async {
      final a = shareFile('a.ccshare');
      final b = shareFile('b.ccshare');
      final c = shareFile('c.ccshare');
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      expect(await channel.initialFile(), isNull);
      final files = <IncomingFile>[];
      final sub = channel.files.listen(files.add);
      addTearDown(sub.cancel);

      for (final f in [a, b, c]) {
        channel.openDesktopPath(f.path);
      }
      await channel.desktopOpensSettled;
      await pumpEventQueue();
      expect(files.map((f) => f.path), [a.path]);

      // A file intake did not get from a desktop open changes nothing.
      channel.fileHandled(IncomingFile(path: a.path, appOwned: true));
      await pumpEventQueue();
      expect(files.map((f) => f.path), [a.path]);

      channel.fileHandled(files.single);
      await pumpEventQueue();
      expect(files.map((f) => f.path), [a.path, c.path]);

      channel.fileHandled(files.last);
      await pumpEventQueue();
      expect(files, hasLength(2));
    });

    test(
      'the cold-start desktop file also holds later opens until handled',
      () async {
        final first = shareFile('first.ccshare');
        final next = shareFile('next.ccshare');
        final channel = IncomingFileChannel(initialDesktopPath: first.path);
        addTearDown(channel.dispose);
        final files = <IncomingFile>[];
        final sub = channel.files.listen(files.add);
        addTearDown(sub.cancel);

        final initial = await channel.initialFile();
        channel.openDesktopPath(next.path);
        await channel.desktopOpensSettled;
        await pumpEventQueue();
        expect(files, isEmpty);

        channel.fileHandled(initial!);
        await pumpEventQueue();
        expect(files.map((f) => f.path), [next.path]);
      },
    );

    test('a second rejection within the cooldown is dropped', () async {
      final channel = IncomingFileChannel();
      addTearDown(channel.dispose);
      expect(await channel.initialFile(), isNull);
      final files = <IncomingFile>[];
      final sub = channel.files.listen((f) {
        files.add(f);
        channel.fileHandled(f);
      });
      addTearDown(sub.cancel);

      for (var i = 0; i < 5; i++) {
        channel.openDesktopPath(p.join(dir.path, 'missing$i.ccshare'));
      }
      await channel.desktopOpensSettled;
      await pumpEventQueue();

      expect(files, [
        const IncomingFile.rejected(IncomingFileRejection.unreadable),
      ]);
    });

    test('a file over the cap arrives as a tooLarge rejection', () async {
      final big = shareFile('big.ccshare', bytes: kMaxIncomingArchiveBytes + 1);
      final channel = IncomingFileChannel(initialDesktopPath: big.path);
      addTearDown(channel.dispose);

      expect(
        await channel.initialFile(),
        const IncomingFile.rejected(IncomingFileRejection.tooLarge),
      );
    });
  });
}
