import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/update/artifact_downloader.dart';
import 'package:compendium_app/src/update/update_config.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

UpdateArtifact _artifact({
  int size = 0,
  String url =
      'https://release-assets.githubusercontent.com/CallersCompendium-0.2.0-macos-universal.dmg',
  String sha256 = 'abcd',
}) => UpdateArtifact(
  platform: UpdatePlatform.macos,
  arch: UpdateArch.universal,
  url: url,
  sha256: sha256,
  size: size,
);

/// A streaming [MockClient] that emits [chunks] as the response body with the
/// given [statusCode] and reported [contentLength].
MockClient _streamingClient(
  List<List<int>> chunks, {
  int statusCode = 200,
  int? contentLength,
}) {
  return MockClient.streaming((request, bodyStream) async {
    return http.StreamedResponse(
      Stream.fromIterable(chunks),
      statusCode,
      contentLength: contentLength,
    );
  });
}

void main() {
  late Directory tempDir;
  late File dest;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('downloader_test_');
    dest = File('${tempDir.path}/artifact.dmg');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('streams bytes to the destination and reports progress', () async {
    final chunks = [
      utf8.encode('AAAA'),
      utf8.encode('BBBB'),
      utf8.encode('CC'),
    ];
    const total = 10;
    final client = _streamingClient(chunks, contentLength: total);
    final progress = <DownloadProgress>[];

    final outcome = await downloadArtifact(
      _artifact(size: total),
      destination: dest,
      client: client,
      onProgress: progress.add,
    );

    expect(outcome.kind, DownloadResultKind.success);
    expect(outcome.file, isNotNull);
    expect(await dest.readAsString(), 'AAAABBBBCC');
    // One progress event per chunk, monotonically increasing to the total.
    expect(progress.map((p) => p.bytesReceived).toList(), [4, 8, 10]);
    expect(progress.last.fraction, 1.0);
  });

  test('cancelling mid-stream aborts and deletes the partial file', () async {
    final chunks = [
      utf8.encode('AAAA'),
      utf8.encode('BBBB'),
      utf8.encode('CCCC'),
    ];
    final client = _streamingClient(chunks, contentLength: 12);
    final token = DownloadCancelToken();
    var progressCalls = 0;

    final outcome = await downloadArtifact(
      _artifact(size: 12),
      destination: dest,
      client: client,
      cancelToken: token,
      onProgress: (_) {
        progressCalls++;
        // Cancel after the first chunk; the next chunk's check aborts.
        if (progressCalls == 1) token.cancel();
      },
    );

    expect(outcome.kind, DownloadResultKind.cancelled);
    expect(await dest.exists(), isFalse);
  });

  test('a pre-cancelled token never starts the download', () async {
    final client = _streamingClient([utf8.encode('AAAA')], contentLength: 4);
    final token = DownloadCancelToken()..cancel();

    final outcome = await downloadArtifact(
      _artifact(size: 4),
      destination: dest,
      client: client,
      cancelToken: token,
    );

    expect(outcome.kind, DownloadResultKind.cancelled);
    expect(await dest.exists(), isFalse);
  });

  test('a non-2xx status is a network error and leaves no file', () async {
    final client = _streamingClient([utf8.encode('nope')], statusCode: 500);

    final outcome = await downloadArtifact(
      _artifact(size: 4),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.networkError);
    expect(outcome.message, contains('500'));
    expect(await dest.exists(), isFalse);
  });

  test('a transport failure is a network error and leaves no file', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      throw const SocketExceptionLike('offline');
    });

    final outcome = await downloadArtifact(
      _artifact(size: 4),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.networkError);
    expect(await dest.exists(), isFalse);
  });

  test('a byte-count short of the manifest size is a sizeMismatch', () async {
    // Manifest promises 100 bytes; the stream delivers only 8.
    final client = _streamingClient([
      utf8.encode('AAAA'),
      utf8.encode('BBBB'),
    ], contentLength: 8);

    final outcome = await downloadArtifact(
      _artifact(size: 100),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.sizeMismatch);
    expect(await dest.exists(), isFalse);
  });

  test(
    'a non-https / off-allowlist URL is refused before any request',
    () async {
      final outcome = await downloadArtifact(
        _artifact(url: 'ftp://github.com/x.dmg'),
        destination: dest,
      );
      expect(outcome.kind, DownloadResultKind.refusedHost);
      expect(await dest.exists(), isFalse);
    },
  );

  test('succeeds when the manifest declares no size (size == 0)', () async {
    final client = _streamingClient([utf8.encode('AB')], contentLength: 2);
    final outcome = await downloadArtifact(
      _artifact(size: 0),
      destination: dest,
      client: client,
    );
    expect(outcome.kind, DownloadResultKind.success);
    expect(await dest.readAsString(), 'AB');
  });

  test(
    'a body larger than the manifest size aborts as a sizeMismatch',
    () async {
      // Manifest promises 4 bytes; the stream delivers 8. The cap aborts before
      // the over-budget chunk is written, and the partial file is deleted so an
      // oversized body can never fill the disk or reach sha256 verification.
      final client = _streamingClient([
        utf8.encode('AAAA'),
        utf8.encode('BBBB'),
      ], contentLength: null);

      final outcome = await downloadArtifact(
        _artifact(size: 4),
        destination: dest,
        client: client,
      );

      expect(outcome.kind, DownloadResultKind.sizeMismatch);
      expect(await dest.exists(), isFalse);
    },
  );

  test(
    'a cleartext http artifact url is rejected before any request',
    () async {
      var requested = false;
      final client = MockClient.streaming((request, bodyStream) async {
        requested = true;
        return http.StreamedResponse(Stream.fromIterable(<List<int>>[]), 200);
      });

      final outcome = await downloadArtifact(
        _artifact(url: 'http://github.com/x.dmg'),
        destination: dest,
        client: client,
      );

      expect(outcome.kind, DownloadResultKind.refusedHost);
      expect(outcome.message, contains('host is not allowed'));
      expect(requested, isFalse);
      expect(await dest.exists(), isFalse);
    },
  );

  test(
    'an off-allowlist https artifact url is refused before any request',
    () async {
      var requested = false;
      final client = MockClient.streaming((request, bodyStream) async {
        requested = true;
        return http.StreamedResponse(Stream.fromIterable(<List<int>>[]), 200);
      });

      final outcome = await downloadArtifact(
        _artifact(url: 'https://evil.example.com/x.dmg'),
        destination: dest,
        client: client,
      );

      expect(outcome.kind, DownloadResultKind.refusedHost);
      expect(requested, isFalse);
      expect(await dest.exists(), isFalse);
    },
  );

  test('a lookalike subdomain of an allowlisted host is refused', () async {
    var requested = false;
    final client = MockClient.streaming((request, bodyStream) async {
      requested = true;
      return http.StreamedResponse(Stream.fromIterable(<List<int>>[]), 200);
    });

    final outcome = await downloadArtifact(
      // Not an exact host match — the allowlist has no subdomain wildcard.
      _artifact(url: 'https://github.com.evil.example/x.dmg'),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.refusedHost);
    expect(requested, isFalse);
  });

  test(
    'an allowlisted host with userinfo or a non-443 port is refused',
    () async {
      final withUserinfo = await downloadArtifact(
        _artifact(url: 'https://user:pass@github.com/x.dmg'),
        destination: dest,
      );
      expect(withUserinfo.kind, DownloadResultKind.refusedHost);

      final withPort = await downloadArtifact(
        _artifact(url: 'https://github.com:8443/x.dmg'),
        destination: dest,
      );
      expect(withPort.kind, DownloadResultKind.refusedHost);
      expect(await dest.exists(), isFalse);
    },
  );

  test(
    'follows an https -> https redirect and streams the final body',
    () async {
      const start = 'https://github.com/o/r/releases/download/v1/a.dmg';
      const target = 'https://objects.githubusercontent.com/a.dmg';
      final client = MockClient.streaming((request, bodyStream) async {
        if (request.url.toString() == start) {
          return http.StreamedResponse(
            Stream.fromIterable(<List<int>>[]),
            302,
            headers: const {'location': target},
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('OK')]),
          200,
          contentLength: 2,
        );
      });

      final outcome = await downloadArtifact(
        _artifact(url: start, size: 2),
        destination: dest,
        client: client,
      );

      expect(outcome.kind, DownloadResultKind.success);
      expect(await dest.readAsString(), 'OK');
    },
  );

  test('refuses a redirect to an off-allowlist / cleartext host', () async {
    const start = 'https://github.com/o/r/releases/download/v1/a.dmg';
    var reachedHttp = false;
    final client = MockClient.streaming((request, bodyStream) async {
      if (request.url.isScheme('http')) reachedHttp = true;
      if (request.url.toString() == start) {
        return http.StreamedResponse(
          Stream.fromIterable(<List<int>>[]),
          302,
          headers: const {'location': 'http://evil.example.com/a.dmg'},
        );
      }
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('EVIL')]),
        200,
        contentLength: 4,
      );
    });

    final outcome = await downloadArtifact(
      _artifact(url: start, size: 4),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.refusedHost);
    expect(outcome.message, contains('host'));
    expect(reachedHttp, isFalse);
    expect(await dest.exists(), isFalse);
  });

  test('refuses a redirect to an off-allowlist https host', () async {
    const start = 'https://github.com/o/r/releases/download/v1/a.dmg';
    var reachedEvil = false;
    final client = MockClient.streaming((request, bodyStream) async {
      if (request.url.host == 'evil.example.com') reachedEvil = true;
      if (request.url.toString() == start) {
        return http.StreamedResponse(
          Stream.fromIterable(<List<int>>[]),
          302,
          headers: const {'location': 'https://evil.example.com/a.dmg'},
        );
      }
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('EVIL')]),
        200,
        contentLength: 4,
      );
    });

    final outcome = await downloadArtifact(
      _artifact(url: start, size: 4),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.refusedHost);
    expect(reachedEvil, isFalse);
    expect(await dest.exists(), isFalse);
  });

  test('gives up after too many redirects', () async {
    // An endless https redirect chain (all on an allowlisted host) must
    // terminate, not loop forever.
    var hops = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      hops++;
      return http.StreamedResponse(
        Stream.fromIterable(<List<int>>[]),
        302,
        headers: {
          'location':
              'https://release-assets.githubusercontent.com/hop$hops.dmg',
        },
      );
    });

    final outcome = await downloadArtifact(
      _artifact(
        url: 'https://release-assets.githubusercontent.com/hop0.dmg',
        size: 2,
      ),
      destination: dest,
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.networkError);
    expect(outcome.message, contains('redirect'));
    expect(await dest.exists(), isFalse);
  });

  test('a destination colliding with an existing directory is refused before '
      'any bytes are written', () async {
    // A directory already sits at the destination path: the pre-write
    // existence check (not following links) must fail closed rather than
    // discovering the collision only at flush/close time.
    final collide = Directory('${tempDir.path}/collide')..createSync();

    final client = _streamingClient([utf8.encode('AB')], contentLength: 2);
    final outcome = await downloadArtifact(
      _artifact(size: 2),
      destination: File(collide.path),
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.networkError);
    expect(outcome.message, contains('already exists'));
    // The pre-existing directory must be left untouched, not deleted.
    expect(await collide.exists(), isTrue);
  });

  test('a pre-planted symlink at the destination path is refused, never '
      'followed or deleted (CWE-59)', () async {
    // Simulate a local attacker who pre-plants a symlink at the predictable
    // destination path, pointing at a file outside the download directory.
    final secretDir = Directory('${tempDir.path}/outside')..createSync();
    final secret = File('${secretDir.path}/secret.txt')
      ..writeAsStringSync('do-not-touch');
    final link = Link(dest.path)..createSync(secret.path);

    final client = _streamingClient([utf8.encode('AB')], contentLength: 2);
    final outcome = await downloadArtifact(
      _artifact(size: 2),
      destination: File(dest.path),
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.networkError);
    expect(outcome.message, contains('already exists'));
    // The symlink must still exist, unmolested, and its target must be
    // completely untouched — the write never followed it.
    expect(await link.exists(), isTrue);
    expect(await secret.readAsString(), 'do-not-touch');
  });

  test('a pre-planted symlink whose target does NOT exist is still refused '
      '(dangling-symlink residual gap, CWE-59)', () async {
    // A dangling symlink at the destination path: an exclusive create
    // alone can (depending on platform/FS) proceed through a symlink whose
    // target doesn't exist yet, creating the target through the link. The
    // explicit non-following existence check must refuse regardless of
    // whether the symlink's target currently exists.
    final missingTarget = File('${tempDir.path}/outside/does-not-exist');
    final link = Link(dest.path)..createSync(missingTarget.path);

    final client = _streamingClient([utf8.encode('AB')], contentLength: 2);
    final outcome = await downloadArtifact(
      _artifact(size: 2),
      destination: File(dest.path),
      client: client,
    );

    expect(outcome.kind, DownloadResultKind.networkError);
    expect(outcome.message, contains('already exists'));
    // The dangling symlink must still exist, unmolested, and its target
    // must still not exist — the write never followed/created through it.
    expect(await link.exists(), isTrue);
    expect(await missingTarget.exists(), isFalse);
  });

  test(
    'a fresh destination is created exclusively and cleaned up on failure',
    () async {
      final client = _streamingClient([
        utf8.encode('AAAA'),
        utf8.encode('BBBB'),
      ], contentLength: 100);

      final outcome = await downloadArtifact(
        _artifact(size: 100),
        destination: dest,
        client: client,
      );

      expect(outcome.kind, DownloadResultKind.sizeMismatch);
      // The file this call created for its exclusive-create is cleaned up on
      // a non-success outcome — never left behind for a retry to collide
      // with.
      expect(await dest.exists(), isFalse);
    },
  );

  group('sink lifecycle', () {
    test('a flush failure still closes the sink, reports networkError and '
        'deletes the partial file', () async {
      final sink = _FakeSink(flushError: StateError('disk full'));
      final file = _SinkFile(dest, sink);

      final outcome = await downloadArtifact(
        _artifact(size: 4),
        destination: file,
        client: _streamingClient([utf8.encode('AAAA')], contentLength: 4),
      );

      expect(outcome.kind, DownloadResultKind.networkError);
      expect(outcome.message, contains('could not finish writing'));
      expect(sink.closeCalls, 1, reason: 'the handle must be released');
      expect(dest.existsSync(), isFalse);
    });

    test('a flush failure after a failed transfer keeps the original outcome '
        'and still closes the sink', () async {
      final sink = _FakeSink(flushError: StateError('disk full'));
      final file = _SinkFile(dest, sink);

      // Manifest promises 100 bytes, stream delivers 4: sizeMismatch.
      final outcome = await downloadArtifact(
        _artifact(size: 100),
        destination: file,
        client: _streamingClient([utf8.encode('AAAA')], contentLength: 100),
      );

      expect(outcome.kind, DownloadResultKind.sizeMismatch);
      expect(sink.closeCalls, 1);
      expect(dest.existsSync(), isFalse);
    });

    test('a close failure while recovering from a flush failure is swallowed '
        'and does not mask the flush failure', () async {
      final sink = _FakeSink(
        flushError: StateError('disk full'),
        closeError: StateError('close boom'),
      );
      final file = _SinkFile(dest, sink);

      final outcome = await downloadArtifact(
        _artifact(size: 4),
        destination: file,
        client: _streamingClient([utf8.encode('AAAA')], contentLength: 4),
      );

      expect(outcome.kind, DownloadResultKind.networkError);
      expect(outcome.message, contains('disk full'));
      expect(
        sink.closeCalls,
        1,
        reason: 'close is attempted once, not retried',
      );
      expect(dest.existsSync(), isFalse);
    });
  });

  group('write backpressure', () {
    const half = kDownloadWriteHighWaterBytes ~/ 2;
    List<int> bytes(int n) => List<int>.filled(n, 0x41);

    // A client whose body is [body], with a known length so the size check
    // matches.
    MockClient bodyClient(StreamController<List<int>> body, int length) =>
        MockClient.streaming(
          (request, _) async =>
              http.StreamedResponse(body.stream, 200, contentLength: length),
        );

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    // Waits until the engine has subscribed to [body] (it first creates the
    // destination file), so `isPaused` is about the subscription.
    Future<void> listening(StreamController<List<int>> body) async {
      while (!body.hasListener) {
        await pump();
      }
    }

    test('pauses the response while a flush is outstanding and resumes when '
        'it completes', () async {
      final flushGate = Completer<void>();
      final sink = _FakeSink(flushGate: flushGate);
      final body = StreamController<List<int>>();
      const total = half * 2 + 10;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _SinkFile(dest, sink),
        client: bodyClient(body, total),
      );
      await listening(body);

      body.add(bytes(half));
      await pump();
      expect(body.isPaused, isFalse, reason: 'below the high-water mark');

      body.add(bytes(half));
      await pump();
      expect(sink.flushCalls, 1);
      expect(body.isPaused, isTrue, reason: 'flush outstanding: reads paced');

      flushGate.complete();
      await pump();
      expect(body.isPaused, isFalse, reason: 'flush done: reading resumes');

      body.add(bytes(10));
      await body.close();
      final outcome = await result;
      expect(outcome.kind, DownloadResultKind.success);
      expect(sink.addedBytes, total);
    });

    test('bytes handed to the sink between flushes stay bounded', () async {
      final sink = _FakeSink();
      final body = StreamController<List<int>>();
      const chunks = 40;
      const total = half * chunks;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _SinkFile(dest, sink),
        client: bodyClient(body, total),
      );
      await listening(body);
      for (var i = 0; i < chunks; i++) {
        body.add(bytes(half));
        await pump();
      }
      await body.close();

      expect((await result).kind, DownloadResultKind.success);
      // One flush per high-water's worth of data (plus the final flush).
      expect(sink.flushCalls, chunks ~/ 2 + 1);
      expect(sink.maxUnflushedBytes, lessThanOrEqualTo(2 * half));
    });

    test('a flush failure mid-stream fails the download, closes the sink and '
        'deletes the file', () async {
      final sink = _FakeSink(flushError: StateError('disk full'));
      final body = StreamController<List<int>>();
      const total = half * 4;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _SinkFile(dest, sink),
        client: bodyClient(body, total),
      );
      await listening(body);
      body.add(bytes(half));
      body.add(bytes(half));
      await pump();

      final outcome = await result;
      expect(outcome.kind, DownloadResultKind.networkError);
      expect(outcome.message, contains('disk full'));
      expect(sink.closeCalls, 1);
      expect(dest.existsSync(), isFalse);
    });

    test('cancelling while reads are paced deletes the partial file and '
        'closes the sink', () async {
      final flushGate = Completer<void>();
      final sink = _FakeSink(flushGate: flushGate);
      final body = StreamController<List<int>>();
      final token = DownloadCancelToken();
      const total = half * 4;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _SinkFile(dest, sink),
        client: bodyClient(body, total),
        cancelToken: token,
      );
      await listening(body);
      body.add(bytes(half));
      body.add(bytes(half));
      await pump();
      expect(body.isPaused, isTrue);

      token.cancel();
      body.add(bytes(half)); // observed once reading resumes
      flushGate.complete();

      final outcome = await result;
      expect(outcome.kind, DownloadResultKind.cancelled);
      expect(sink.closeCalls, 1);
      expect(dest.existsSync(), isFalse);
    });

    test(
      'cancelling while a flush never settles still resolves promptly',
      () async {
        final flushGate = Completer<void>(); // never completed
        final sink = _FakeSink(flushGate: flushGate);
        final body = StreamController<List<int>>();
        final token = DownloadCancelToken();
        const total = half * 4;

        final result = downloadArtifact(
          _artifact(size: total),
          destination: _SinkFile(dest, sink),
          client: bodyClient(body, total),
          cancelToken: token,
        );
        await listening(body);
        body.add(bytes(half));
        body.add(bytes(half));
        await pump();
        expect(body.isPaused, isTrue);

        token.cancel();
        final outcome = await result.timeout(
          kDownloadCancelPollInterval * 10,
          onTimeout: () => fail('cancel hung behind a stuck flush'),
        );
        expect(outcome.kind, DownloadResultKind.cancelled);
        // A real IOSink cannot be closed while its flush is outstanding, so
        // the close waits for a flush that never settles (see the real-IOSink
        // tests below); the file is still deleted.
        expect(sink.closeCalls, 0);
        expect(dest.existsSync(), isFalse);
      },
    );

    // The fakes above accept close() during a flush; dart:io's IOSink does
    // not (it throws "StreamSink is bound to a stream" synchronously), so
    // these two drive a real IOSink over a consumer whose writes are gated.
    test('cancelling during a flush on a real IOSink reports cancelled and '
        'closes the sink once the flush settles', () async {
      final consumer = _GatedConsumer();
      final body = StreamController<List<int>>();
      final token = DownloadCancelToken();
      const total = half * 4;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _SinkFile(dest, IOSink(consumer)),
        client: bodyClient(body, total),
        cancelToken: token,
      );
      await listening(body);
      body.add(bytes(half));
      body.add(bytes(half));
      await pump();
      expect(body.isPaused, isTrue, reason: 'flush outstanding');

      token.cancel();
      final outcome = await result.timeout(
        kDownloadCancelPollInterval * 10,
        onTimeout: () => fail('cancel hung behind a stuck flush'),
      );
      expect(outcome.kind, DownloadResultKind.cancelled);
      expect(dest.existsSync(), isFalse);
      expect(consumer.closeCalls, 0, reason: 'cannot close mid-flush');

      consumer.gate.complete();
      for (var i = 0; i < 20 && !consumer.closed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(consumer.closeCalls, 1, reason: 'handle released after flush');
    });

    test('the deferred cleanup never deletes a file that replaced the '
        'cancelled one at the same path', () async {
      final consumer = _GatedConsumer();
      final body = StreamController<List<int>>();
      final token = DownloadCancelToken();
      const total = half * 4;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _SinkFile(dest, IOSink(consumer)),
        client: bodyClient(body, total),
        cancelToken: token,
      );
      await listening(body);
      body.add(bytes(half));
      body.add(bytes(half));
      await pump();
      expect(body.isPaused, isTrue, reason: 'flush outstanding');

      token.cancel();
      expect((await result).kind, DownloadResultKind.cancelled);
      expect(dest.existsSync(), isFalse);

      // A new Save As download now owns the same path.
      dest.writeAsStringSync('replacement');
      consumer.gate.complete();
      for (var i = 0; i < 20 && !consumer.closed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(consumer.closed, isTrue);
      expect(dest.existsSync(), isTrue, reason: 'replacement was deleted');
      expect(dest.readAsStringSync(), 'replacement');
    });

    test('a cancelled download deletes its file only after the sink has '
        'closed (an open handle blocks the delete on Windows)', () async {
      final consumer = _GatedConsumer()..gate.complete();
      final body = StreamController<List<int>>();
      final token = DownloadCancelToken();
      const total = half * 4;

      final result = downloadArtifact(
        _artifact(size: total),
        destination: _WindowsLikeFile(dest, IOSink(consumer), consumer),
        client: bodyClient(body, total),
        cancelToken: token,
      );
      await listening(body);
      body.add(bytes(half ~/ 2));
      await pump();
      token.cancel();
      body.add(bytes(half ~/ 2)); // onData observes the cancel

      expect((await result).kind, DownloadResultKind.cancelled);
      for (var i = 0; i < 20 && dest.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(consumer.closeCalls, 1);
      expect(dest.existsSync(), isFalse, reason: 'partial file left behind');
    });
  });
}

/// A [StreamConsumer] behind a real dart:io [IOSink]: each write batch
/// completes only once [gate] completes, standing in for a stalled disk.
class _GatedConsumer implements StreamConsumer<List<int>> {
  final gate = Completer<void>();
  int closeCalls = 0;

  /// Whether a [close] has finished; releasing a real handle is itself
  /// asynchronous I/O, so it lags the call.
  bool closed = false;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
    await gate.future;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    closed = true;
  }
}

/// An [IOSink] test double: records calls and lets a test fail or gate
/// `flush()` / fail `close()`. Anything unused by the downloader is unsupported.
class _FakeSink implements IOSink {
  _FakeSink({this.flushError, this.closeError, this.flushGate});

  final Object? flushError;
  final Object? closeError;
  final Completer<void>? flushGate;

  int closeCalls = 0;
  int flushCalls = 0;
  int addedBytes = 0;
  int maxUnflushedBytes = 0;
  int _unflushed = 0;

  @override
  void add(List<int> data) {
    addedBytes += data.length;
    _unflushed += data.length;
    if (_unflushed > maxUnflushedBytes) maxUnflushedBytes = _unflushed;
  }

  @override
  Future<void> flush() async {
    flushCalls++;
    if (flushError != null) throw flushError!;
    await flushGate?.future;
    _unflushed = 0;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeError != null) throw closeError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeSink.${invocation.memberName}');
}

/// A [File] that behaves as [_inner] except that `openWrite()` returns [_sink].
/// Only the members `downloadArtifact` uses are forwarded.
class _SinkFile implements File {
  _SinkFile(this._inner, this._sink);

  final File _inner;
  final IOSink _sink;

  @override
  String get path => _inner.path;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _inner.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<bool> exists() => _inner.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _inner.delete(recursive: recursive);

  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_SinkFile.${invocation.memberName}');
}

/// A stand-in transport error (avoids importing `dart:io`'s `SocketException`
/// so the test stays platform-agnostic); the engine's `on Object` handling
/// treats any thrown error as a network failure.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionLike: $message';
}

/// A [_SinkFile] with Windows delete semantics: deleting fails while the
/// file's write handle ([consumer]) is still open.
class _WindowsLikeFile extends _SinkFile {
  _WindowsLikeFile(super.inner, super.sink, this.consumer);

  final _GatedConsumer consumer;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (!consumer.closed) {
      throw FileSystemException('file is open in another process', path);
    }
    return super.delete(recursive: recursive);
  }
}
