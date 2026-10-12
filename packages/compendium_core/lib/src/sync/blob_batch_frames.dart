import 'dart:typed_data';

/// The media type of a `POST /v1/blobs/batch` response body (sync spec §5.2).
const String syncBlobBatchMediaType =
    'application/vnd.callers-compendium.blob-batch';

/// The most hashes one `POST /v1/blobs/batch` request may name (spec §5.4).
const int syncBlobBatchMaxHashes = 200;

/// The most blob bytes one `POST /v1/blobs/batch` response carries, before
/// framing and compression (spec §5.4). A blob is never larger than 1 MB, so
/// the first blob a response names always fits.
const int syncBlobBatchMaxBlobBytes = 2 * 1024 * 1024;

/// Bytes of framing a response adds per requested hash, at most: a status
/// byte, the 32-byte hash and a 4-byte length.
const int syncBlobBatchFrameOverhead = 1 + 32 + 4;

/// The most decoded bytes a conforming batch response can occupy: every blob
/// byte it may carry, plus a frame for every hash it may name.
const int syncBlobBatchMaxResponseBytes =
    syncBlobBatchMaxBlobBytes +
    syncBlobBatchMaxHashes * syncBlobBatchFrameOverhead;

/// What one frame of a batch response says about the hash it names.
enum SyncBlobBatchFrameStatus {
  /// The blob's bytes follow, prefixed by their length.
  blob(0),

  /// The store cannot serve this hash in its current epoch: the same answer a
  /// `GET /v1/blobs/{hash}` gives with `404`.
  missing(1),

  /// The response reached its byte cap before this blob; ask again.
  notSent(2);

  const SyncBlobBatchFrameStatus(this.code);

  /// The byte that encodes this status on the wire.
  final int code;

  static SyncBlobBatchFrameStatus? fromCode(int code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// One decoded frame: the status for [hash] and, for
/// [SyncBlobBatchFrameStatus.blob], its bytes.
final class SyncBlobBatchFrame {
  const SyncBlobBatchFrame(this.status, this.hash, [this.body]);

  final SyncBlobBatchFrameStatus status;

  /// The lowercase hex SHA-256 the frame names.
  final String hash;

  /// The blob's bytes; null unless [status] is [SyncBlobBatchFrameStatus.blob].
  final Uint8List? body;
}

/// Encodes the head of one frame: its status, its hash and, for a blob, the
/// big-endian length of the bytes that follow it.
///
/// The server writes a blob's bytes straight after this head, so it never
/// copies a blob into a larger buffer to frame it.
Uint8List encodeSyncBlobBatchFrameHead(
  SyncBlobBatchFrameStatus status,
  String hash, {
  int? length,
}) {
  final hasLength = status == SyncBlobBatchFrameStatus.blob;
  if (hasLength != (length != null)) {
    throw ArgumentError.value(length, 'length', 'required only for a blob');
  }
  final head = Uint8List(hasLength ? 37 : 33);
  head[0] = status.code;
  head.setAll(1, _hashBytes(hash));
  if (hasLength) {
    head.buffer.asByteData().setUint32(33, length!);
  }
  return head;
}

/// Thrown when a batch response is not a well-formed frame sequence.
final class SyncBlobBatchFormatException implements Exception {
  const SyncBlobBatchFormatException(this.message);

  final String message;

  @override
  String toString() => 'SyncBlobBatchFormatException: $message';
}

/// Reads a batch response incrementally, one frame at a time, as it arrives.
///
/// Frames are checked against [expectedHashes] in order: a conforming server
/// answers every requested hash exactly once, in the order requested. A frame
/// naming anything else, an unknown status, or a blob longer than
/// [maxBlobBytes] is a [SyncBlobBatchFormatException]. Every complete frame is
/// handed to the caller before the next is checked, so frames that arrived
/// before a broken stream, or before a malformed frame, are not lost with it.
final class SyncBlobBatchFrameReader {
  SyncBlobBatchFrameReader(
    List<String> expectedHashes, {
    required this.maxBlobBytes,
  }) : _expected = List.unmodifiable(expectedHashes);

  final List<String> _expected;
  final int maxBlobBytes;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  var _next = 0;

  /// Bytes the frame being read needs before it can be checked further.
  var _needed = 33;

  /// Whether every requested hash has been answered.
  bool get isComplete => _next == _expected.length;

  /// Consumes [chunk], handing each frame it completes to [onFrame] in order.
  ///
  /// A frame is handed on before the next is checked, so when a later frame
  /// in the same chunk is malformed, the ones before it have still arrived.
  /// Bytes are buffered until the frame they belong to is complete, and only
  /// then gathered, so a large blob arriving in many small chunks is copied
  /// once rather than once per chunk.
  void add(List<int> chunk, void Function(SyncBlobBatchFrame frame) onFrame) {
    _pending.add(chunk);
    if (_pending.length < _needed) return;
    final buffer = _pending.takeBytes();
    var offset = 0;
    try {
      while (true) {
        final available = buffer.length - offset;
        if (available < 33) {
          _needed = 33;
          break;
        }
        if (_next >= _expected.length) {
          throw const SyncBlobBatchFormatException('frame after the last hash');
        }
        final status = SyncBlobBatchFrameStatus.fromCode(buffer[offset]);
        if (status == null) {
          throw const SyncBlobBatchFormatException('unknown frame status');
        }
        final hash = _hashHex(buffer, offset + 1);
        if (hash != _expected[_next]) {
          throw const SyncBlobBatchFormatException('frame out of order');
        }
        if (status != SyncBlobBatchFrameStatus.blob) {
          offset += 33;
          _next++;
          onFrame(SyncBlobBatchFrame(status, hash));
          continue;
        }
        if (available < 37) {
          _needed = 37;
          break;
        }
        final length = ByteData.sublistView(
          buffer,
          offset + 33,
          offset + 37,
        ).getUint32(0);
        if (length > maxBlobBytes) {
          throw const SyncBlobBatchFormatException('blob exceeds size limit');
        }
        if (available < 37 + length) {
          _needed = 37 + length;
          break;
        }
        final body = Uint8List.fromList(
          Uint8List.sublistView(buffer, offset + 37, offset + 37 + length),
        );
        offset += 37 + length;
        _next++;
        onFrame(SyncBlobBatchFrame(status, hash, body));
      }
    } finally {
      if (offset < buffer.length) {
        _pending.add(Uint8List.sublistView(buffer, offset));
      }
    }
  }

  /// Checks that the stream ended between frames.
  ///
  /// It is not an error for the stream to end before every hash is answered:
  /// the caller decides what an unanswered hash means. A stream that ends
  /// part-way through a frame is.
  void close() {
    if (_pending.isNotEmpty) {
      throw const SyncBlobBatchFormatException('stream ended inside a frame');
    }
  }
}

final _hashPattern = RegExp(r'^[0-9a-f]{64}$');

Uint8List _hashBytes(String hash) {
  if (!_hashPattern.hasMatch(hash)) {
    throw ArgumentError.value(hash, 'hash', 'not a lowercase SHA-256 hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < 64; i += 2)
      int.parse(hash.substring(i, i + 2), radix: 16),
  ]);
}

String _hashHex(Uint8List bytes, int offset) {
  const digits = '0123456789abcdef';
  final buffer = StringBuffer();
  for (var i = offset; i < offset + 32; i++) {
    buffer
      ..write(digits[bytes[i] >> 4])
      ..write(digits[bytes[i] & 0x0f]);
  }
  return buffer.toString();
}
