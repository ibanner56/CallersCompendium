import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/update/artifact_downloader.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

UpdateArtifact _artifact({
  int size = 0,
  String url =
      'https://example.com/CallersCompendium-0.2.0-macos-universal.dmg',
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

  test('an unparseable/non-http URL is a network error', () async {
    final outcome = await downloadArtifact(
      _artifact(url: 'ftp://example.com/x.dmg'),
      destination: dest,
    );
    expect(outcome.kind, DownloadResultKind.networkError);
  });

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
    'a file flush/close failure downgrades success to a network error',
    () async {
      // Point the destination at an existing *directory*: bytes buffer fine, but
      // flush()/close() fails (EISDIR). A partial/corrupt file must never be
      // reported as a successful download and handed on to sha256 verification.
      final collide = Directory('${tempDir.path}/collide')..createSync();

      final client = _streamingClient([utf8.encode('AB')], contentLength: 2);
      final outcome = await downloadArtifact(
        _artifact(size: 2),
        destination: File(collide.path),
        client: client,
      );

      expect(outcome.kind, DownloadResultKind.networkError);
      expect(outcome.message, contains('could not finish writing'));
    },
  );
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
