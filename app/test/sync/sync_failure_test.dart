import 'dart:io';

import 'package:compendium_app/src/sync/sync_failure.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('syncFailureCauseForError', () {
    // Each of these is what the user's remedy turns on: a dropped connection
    // and an app bug must not read alike.
    for (final (name, error, cause) in <(String, Object, SyncFailureCause)>[
      (
        'a refused connection',
        const SocketException('refused'),
        SyncFailureCause.unreachable,
      ),
      (
        'an HTTP client error',
        http.ClientException('connection closed'),
        SyncFailureCause.unreachable,
      ),
      (
        'a failed TLS handshake',
        const HandshakeException('bad certificate'),
        SyncFailureCause.unreachable,
      ),
      (
        'the transport deadline',
        const SyncTransportException('sync request timed out'),
        SyncFailureCause.timedOut,
      ),
      (
        'an oversized response',
        const SyncEndpointException('sync response exceeds size limit'),
        SyncFailureCause.unexpectedResponse,
      ),
      (
        'a worker throw classified before it crossed the isolate',
        SyncWorkerFailure('text only', SyncFailureCause.timedOut),
        SyncFailureCause.timedOut,
      ),
      ('anything else', StateError('bug'), SyncFailureCause.internal),
    ]) {
      test('classifies $name', () {
        expect(syncFailureCauseForError(error), cause);
      });
    }
  });

  group('syncFailureCauseForResponse', () {
    for (final (kind, cause) in <(SyncResponseKind, SyncFailureCause)>[
      (SyncResponseKind.serverError, SyncFailureCause.serverError),
      (SyncResponseKind.rateLimited, SyncFailureCause.rateLimited),
      (SyncResponseKind.quotaExhausted, SyncFailureCause.storeFull),
      (SyncResponseKind.payloadTooLarge, SyncFailureCause.tooLarge),
      (SyncResponseKind.rejected, SyncFailureCause.rejected),
      (SyncResponseKind.invalidSyncId, SyncFailureCause.accessDenied),
      (SyncResponseKind.redirectRefused, SyncFailureCause.unexpectedResponse),
    ]) {
      test('maps ${kind.name} to ${cause.name}', () {
        expect(syncFailureCauseForResponse(kind), cause);
      });
    }
  });

  test('a failure survives the isolate encoding intact', () {
    const failure = SyncFailure(
      SyncFailureCause.storeFull,
      step: SyncFailureStep.upload,
      statusCode: 507,
    );
    final decoded = SyncFailure.decode(failure.encode());
    expect(decoded.cause, failure.cause);
    expect(decoded.step, failure.step);
    expect(decoded.statusCode, failure.statusCode);
  });

  test('a malformed encoding is refused rather than guessed at', () {
    expect(
      () => SyncFailure.decode({'cause': 3}),
      throwsA(isA<FormatException>()),
    );
  });
}
