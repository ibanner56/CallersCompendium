import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The `POST /v1/blobs/batch` frame format (sync spec §5.2).
void main() {
  final first = sha256Hex(utf8.encode('first'));
  final second = sha256Hex(utf8.encode('second'));
  final third = sha256Hex(utf8.encode('third'));

  List<int> blobFrame(String hash, List<int> body) => [
    ...encodeSyncBlobBatchFrameHead(
      SyncBlobBatchFrameStatus.blob,
      hash,
      length: body.length,
    ),
    ...body,
  ];

  List<int> statusFrame(SyncBlobBatchFrameStatus status, String hash) =>
      encodeSyncBlobBatchFrameHead(status, hash);

  List<SyncBlobBatchFrame> readAll(
    List<String> expected,
    List<List<int>> chunks, {
    int maxBlobBytes = 1024,
  }) {
    final reader = SyncBlobBatchFrameReader(
      expected,
      maxBlobBytes: maxBlobBytes,
    );
    final frames = <SyncBlobBatchFrame>[];
    for (final chunk in chunks) {
      reader.add(chunk, frames.add);
    }
    reader.close();
    return frames;
  }

  test('reads blob, missing and not-sent frames in request order', () {
    final bytes = [
      ...blobFrame(first, utf8.encode('one')),
      ...statusFrame(SyncBlobBatchFrameStatus.missing, second),
      ...statusFrame(SyncBlobBatchFrameStatus.notSent, third),
    ];
    final frames = readAll([first, second, third], [bytes]);
    expect(
      [for (final f in frames) f.status],
      [
        SyncBlobBatchFrameStatus.blob,
        SyncBlobBatchFrameStatus.missing,
        SyncBlobBatchFrameStatus.notSent,
      ],
    );
    expect([for (final f in frames) f.hash], [first, second, third]);
    expect(utf8.decode(frames.first.body!), 'one');
    expect(frames[1].body, isNull);
  });

  test('reassembles frames split at every possible byte', () {
    final bytes = [
      ...blobFrame(first, utf8.encode('one')),
      ...blobFrame(second, List<int>.filled(300, 7)),
      ...statusFrame(SyncBlobBatchFrameStatus.missing, third),
    ];
    final frames = readAll(
      [first, second, third],
      [
        for (final byte in bytes) [byte],
      ],
    );
    expect([for (final f in frames) f.hash], [first, second, third]);
    expect(frames[1].body, List<int>.filled(300, 7));
  });

  test('a stream that ends early is not an error, but one that ends inside '
      'a frame is', () {
    final reader = SyncBlobBatchFrameReader([
      first,
      second,
    ], maxBlobBytes: 1024);
    reader.add(blobFrame(first, utf8.encode('one')), (_) {});
    expect(reader.isComplete, isFalse);
    reader.close();

    final cut = SyncBlobBatchFrameReader([first], maxBlobBytes: 1024);
    cut.add(blobFrame(first, utf8.encode('one')).sublist(0, 36), (_) {});
    expect(cut.close, throwsA(isA<SyncBlobBatchFormatException>()));
  });

  for (final (label, bytes) in [
    (
      'a frame out of request order',
      [...statusFrame(SyncBlobBatchFrameStatus.missing, second)],
    ),
    (
      'an unknown status',
      [
        9,
        ...encodeSyncBlobBatchFrameHead(
          SyncBlobBatchFrameStatus.missing,
          first,
        ).sublist(1),
      ],
    ),
    ('a blob over the size cap', blobFrame(first, List<int>.filled(11, 1))),
    (
      'a frame after the last hash',
      [
        ...statusFrame(SyncBlobBatchFrameStatus.missing, first),
        ...statusFrame(SyncBlobBatchFrameStatus.missing, first),
      ],
    ),
  ]) {
    test('rejects $label', () {
      expect(
        () => readAll([first], [bytes], maxBlobBytes: 10),
        throwsA(isA<SyncBlobBatchFormatException>()),
      );
    });
  }

  test('hands on the frames before a malformed one in the same chunk', () {
    final reader = SyncBlobBatchFrameReader([
      first,
      second,
    ], maxBlobBytes: 1024);
    final frames = <SyncBlobBatchFrame>[];
    expect(
      () => reader.add([
        ...blobFrame(first, utf8.encode('one')),
        ...statusFrame(SyncBlobBatchFrameStatus.missing, third),
      ], frames.add),
      throwsA(isA<SyncBlobBatchFormatException>()),
    );
    expect([for (final f in frames) f.hash], [first]);
  });

  test('a frame head names its hash in raw bytes, and a length only for a '
      'blob', () {
    final head = encodeSyncBlobBatchFrameHead(
      SyncBlobBatchFrameStatus.blob,
      first,
      length: 258,
    );
    expect(head, hasLength(37));
    expect(head.first, 0);
    expect(ByteData.sublistView(head, 33).getUint32(0), 258);
    expect(
      encodeSyncBlobBatchFrameHead(SyncBlobBatchFrameStatus.notSent, first),
      hasLength(33),
    );
    expect(
      () => encodeSyncBlobBatchFrameHead(SyncBlobBatchFrameStatus.blob, first),
      throwsArgumentError,
    );
    expect(
      () => encodeSyncBlobBatchFrameHead(
        SyncBlobBatchFrameStatus.missing,
        first.toUpperCase(),
      ),
      throwsArgumentError,
    );
  });
}
