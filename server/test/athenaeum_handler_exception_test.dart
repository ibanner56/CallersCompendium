import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Unexpected handler faults answer 500 and log only the exception's type.
///
/// shelf's own handler-error log prints `toString()` and a stack, and a
/// `SqliteException` or `FileSystemException` puts store identifiers, device
/// ids and blob paths in that text (sync spec §7.4).
void main() {
  const syncId = 'café-horse-battery-staple';
  const sentinelIdKey =
      'abfdc5f3deadbeefabfdc5f3deadbeefabfdc5f3deadbeefabfdc5f3deadbeef';
  const sentinelDevice = 'device-sentinel-7f3a';

  late Directory dataDirectory;
  late AthenaeumConfig config;
  late _FaultyStore store;
  late AthenaeumApp app;
  late String idKey;
  late String epoch;

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('athenaeum-fault-');
    config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    store = _FaultyStore(config);
    app = AthenaeumApp(config: config, store: store);
    idKey = deriveIncomingSyncIdKey(syncId, config.pepper);
    epoch = store.create(idKey).epoch;
  });

  tearDown(() {
    store.close();
    dataDirectory.deleteSync(recursive: true);
  });

  Request authed(String method, String path, {Object? body}) => Request(
    method,
    Uri.parse('http://127.0.0.1$path'),
    headers: {
      'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
      'content-type': 'application/json',
    },
    body: body == null ? null : utf8.encode(jsonEncode(body)),
  );

  void expectOnlyTypeLogged(List<String> lines, String type) {
    final text = lines.join();
    expect(text, contains(type));
    expect(text, isNot(contains(sentinelIdKey)));
    expect(text, isNot(contains(sentinelDevice)));
    expect(text, isNot(contains('blobs/')));
    expect(text, isNot(contains('Error thrown by handler')));
  }

  test('an unexpected exception in a route answers a JSON 500 and logs '
      'only its type', () async {
    store.touchError = const _LeakyError();
    final (response, stderrLines) = await _captureStderr(
      () => app.call(authed('GET', '/v1/store')),
    );

    expect(response.statusCode, 500);
    expect(response.headers['content-type'], contains('application/json'));
    expect(jsonDecode(await response.readAsString()), {
      'error': 'internal error',
    });
    expectOnlyTypeLogged(stderrLines, '_LeakyError');
  });

  test('a store fault while logging an ordinary 4xx still answers that 4xx '
      'and logs only the fault\'s type', () async {
    // The request authenticates (first lookup), then fails with a 400 whose
    // diagnostic log looks the store up again (second lookup), which faults.
    store.lookupErrorOnCall = 2;
    final (response, stderrLines) = await _captureStderr(
      () => app.call(authed('POST', '/v1/store', body: {'unexpected': true})),
    );

    expect(response.statusCode, 400);
    expect(jsonDecode(await response.readAsString()), {
      'error': 'store creation has no body',
    });
    expectOnlyTypeLogged(stderrLines, '_LeakyError');
  });

  test('a failing heartbeat probe answers a JSON 500 and logs only its '
      'type', () async {
    store.checkHealthError = const _LeakyError();
    final (response, stderrLines) = await _captureStderr(
      () => app.call(Request('GET', Uri.parse('http://127.0.0.1/heartbeat'))),
    );

    expect(response.statusCode, 500);
    expect(jsonDecode(await response.readAsString()), {
      'error': 'internal error',
    });
    expectOnlyTypeLogged(stderrLines, '_LeakyError');
    expect(stderrLines.join(), isNot(contains('.dart')));
  });

  test('a non-file error mid batch stream ends the stream and logs only its '
      'type', () async {
    final first = Uint8List.fromList(utf8.encode('{"first":true}'));
    final firstHash = sha256Hex(first);
    store.putBlob(idKey: idKey, epoch: epoch, hash: firstHash, body: first);
    final second = Uint8List.fromList(utf8.encode('{"second":true}'));
    final secondHash = sha256Hex(second);
    store.putBlob(idKey: idKey, epoch: epoch, hash: secondHash, body: second);
    store.blobRefErrorFor = secondHash;
    final hashes = [firstHash, secondHash];

    final (received, stderrLines) = await _captureStderr(() async {
      final response = await app.call(
        authed('POST', '/v1/blobs/batch', body: {'hashes': hashes}),
      );
      expect(response.statusCode, 200);
      final reader = SyncBlobBatchFrameReader(
        hashes,
        maxBlobBytes: maxBlobBytes,
      );
      final frames = <SyncBlobBatchFrame>[];
      await for (final chunk in response.read()) {
        reader.add(chunk, frames.add);
      }
      reader.close();
      return frames;
    });

    // Headers were sent before the fault: the stream just ends, short of the
    // second hash.
    expect(received.map((frame) => frame.hash), [firstHash]);
    expectOnlyTypeLogged(stderrLines, '_LeakyError');
  });
}

/// An error whose text carries what a real `SqliteException` would.
class _LeakyError implements Exception {
  const _LeakyError();

  @override
  String toString() =>
      '_LeakyError: UPDATE stores SET last_seen = ? WHERE id_key = ?, '
      'parameters: abfdc5f3deadbeefabfdc5f3deadbeefabfdc5f3deadbeefabfdc5f3deadbeef, '
      'device-sentinel-7f3a, blobs/abfdc5f3deadbeef/0/ab/cd';
}

class _FaultyStore extends AthenaeumStore {
  _FaultyStore(AthenaeumConfig config) : super(config: config);

  Object? touchError;
  String? blobRefErrorFor;
  Object? checkHealthError;

  /// Throws a [_LeakyError] from the Nth call to [lookup] (1-based).
  int? lookupErrorOnCall;
  int _lookupCalls = 0;

  @override
  StoreRow? lookup(String idKey) {
    if (++_lookupCalls == lookupErrorOnCall) throw const _LeakyError();
    return super.lookup(idKey);
  }

  @override
  void checkHealth() {
    final error = checkHealthError;
    if (error != null) throw error;
    super.checkHealth();
  }

  @override
  void touch(String idKey) {
    final error = touchError;
    if (error != null) throw error;
    super.touch(idKey);
  }

  @override
  BlobRef? blobRef(String idKey, String epoch, String hash) {
    if (hash == blobRefErrorFor) throw const _LeakyError();
    return super.blobRef(idKey, epoch, hash);
  }
}

/// Runs [body] with `stderr` captured, returning its result and the lines
/// written.
Future<(T, List<String>)> _captureStderr<T>(Future<T> Function() body) async {
  final sink = _CapturingStdout();
  final result = await IOOverrides.runZoned(body, stderr: () => sink);
  return (result, sink.lines);
}

class _CapturingStdout implements Stdout {
  final lines = <String>[];

  @override
  void writeln([Object? object = '']) => lines.add('$object\n');

  @override
  void write(Object? object) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
