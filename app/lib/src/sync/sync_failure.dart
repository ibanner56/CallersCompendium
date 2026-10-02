// Why a sync pass failed, in terms the status surface can explain.
import 'dart:io';

import 'package:http/http.dart' as http;

import 'sync_http_client.dart';

/// Why a failed pass stopped, grouped by what the user can do about it.
///
/// [SyncResponseKind] and the thrown transport errors distinguish more than
/// this; several of them leave the user with the same remedy, so they share a
/// cause here and the precise status code travels separately in
/// [SyncFailure.statusCode] for the user to quote.
enum SyncFailureCause {
  /// No connection to the server could be made or kept: DNS, refused or
  /// dropped connection, or a TLS handshake that failed.
  unreachable,

  /// A request did not finish within the transport deadline.
  timedOut,

  /// The server answered 5xx: a fault on its side.
  serverError,

  /// The server answered 429 and asked this device to slow down.
  rateLimited,

  /// The server answered 507: the store has used its storage allowance.
  storeFull,

  /// The server answered 413: something this device sent is over its size
  /// limit.
  tooLarge,

  /// The server answered 400, 415 or 422: it refused what this device sent as
  /// invalid, which in practice means app and server versions disagree.
  rejected,

  /// The server answered 401 or 403: it did not accept this device's sync
  /// phrase.
  accessDenied,

  /// The server answered in a way this app cannot use: an unexpected status, a
  /// redirect it will not follow, a malformed or oversized body.
  unexpectedResponse,

  /// A first connection to a store needs what every other device last shared,
  /// and at least one device's list could not be read.
  peerUnavailable,

  /// Something failed inside this app rather than on the network.
  internal,
}

/// Whether a [SyncFailureCause] is one that passes on its own, or one the user
/// has to do something about.
///
/// The split decides how the status surface speaks (a calm "waiting" line
/// against a warning) and whether `SyncController` retries by itself. It is
/// not a judgement about severity: a transient cause that never clears is
/// still escalated, by the 21-day expiry warning (spec §6.14 item 4).
extension SyncFailureCauseTier on SyncFailureCause {
  /// True for a failure that clears without the user: the network, a server
  /// fault, or a request to slow down. Spec §5.3 forbids an automatic retry of
  /// `507` and `422`, which is why [SyncFailureCause.storeFull] and
  /// [SyncFailureCause.rejected] are not here.
  ///
  /// Exhaustive with no `_` arm so a new cause must be placed in a tier.
  bool get isTransient => switch (this) {
    SyncFailureCause.unreachable ||
    SyncFailureCause.timedOut ||
    SyncFailureCause.serverError ||
    SyncFailureCause.rateLimited => true,
    SyncFailureCause.storeFull ||
    SyncFailureCause.tooLarge ||
    SyncFailureCause.rejected ||
    SyncFailureCause.accessDenied ||
    SyncFailureCause.unexpectedResponse ||
    SyncFailureCause.peerUnavailable ||
    SyncFailureCause.internal => false,
  };
}

/// What a failed pass was doing when it stopped.
enum SyncFailureStep {
  /// Looking up the store.
  lookup,

  /// Downloading what other devices shared.
  download,

  /// Uploading this device's records.
  upload,

  /// Publishing this device's list of what it shares.
  publish,

  /// Creating a store to replace a missing one.
  createStore,
}

/// The structured reason a pass ended at `SyncPassStatus.failed`.
///
/// Carried beside `SyncPassResult.message` rather than parsed out of it: the
/// message is an English maintainer diagnostic, and the status surface must
/// never show it (see `syncNoticeText`).
class SyncFailure {
  const SyncFailure(this.cause, {this.step, this.statusCode, this.retryAfter});

  /// The failure a non-success [response] at [step] stands for. [step] is
  /// omitted for a request that is not part of a pass, such as removing a
  /// device.
  factory SyncFailure.fromResponse(
    SyncHttpResponse response, [
    SyncFailureStep? step,
  ]) => SyncFailure(
    syncFailureCauseForResponse(response.kind),
    step: step,
    statusCode: response.statusCode,
  );

  /// The failure a thrown [error] stands for. The step is unknown: a throw
  /// does not say which request was in flight.
  factory SyncFailure.fromError(Object error) =>
      SyncFailure(syncFailureCauseForError(error));

  final SyncFailureCause cause;

  /// Null when the failure was a throw, or did not happen at any one step.
  final SyncFailureStep? step;

  /// The HTTP status the server answered with, when it answered at all.
  final int? statusCode;

  /// How long the server asked this device to wait before trying again
  /// (`Retry-After`, spec §5.3), when it said. The automatic retry never runs
  /// sooner than this (`SyncController`, spec §6.12).
  final Duration? retryAfter;

  /// The isolate-message encoding read back by [SyncFailure.decode].
  Map<String, Object?> encode() => {
    'cause': cause.name,
    'step': step?.name,
    'statusCode': statusCode,
  };

  /// Reads [encode]'s output, or throws [FormatException].
  static SyncFailure decode(Object? encoded) {
    if (encoded is! Map<Object?, Object?>) {
      throw const FormatException('sync isolate returned a malformed failure');
    }
    final cause = encoded['cause'];
    final step = encoded['step'];
    final statusCode = encoded['statusCode'];
    if (cause is! String ||
        (step != null && step is! String) ||
        (statusCode != null && statusCode is! int)) {
      throw const FormatException('sync isolate returned an invalid failure');
    }
    return SyncFailure(
      SyncFailureCause.values.byName(cause),
      step: step == null ? null : SyncFailureStep.values.byName(step as String),
      statusCode: statusCode as int?,
    );
  }
}

/// The cause a non-success response of [kind] stands for.
///
/// Exhaustive with no `_` arm so a new [SyncResponseKind] must be placed here.
SyncFailureCause syncFailureCauseForResponse(SyncResponseKind kind) =>
    switch (kind) {
      SyncResponseKind.serverError => SyncFailureCause.serverError,
      SyncResponseKind.rateLimited => SyncFailureCause.rateLimited,
      SyncResponseKind.quotaExhausted => SyncFailureCause.storeFull,
      SyncResponseKind.payloadTooLarge => SyncFailureCause.tooLarge,
      SyncResponseKind.malformedRequest ||
      SyncResponseKind.unsupportedMediaType ||
      SyncResponseKind.rejected => SyncFailureCause.rejected,
      SyncResponseKind.unauthorized ||
      SyncResponseKind.invalidSyncId => SyncFailureCause.accessDenied,
      // A success kind reaches here only when its body could not be used.
      SyncResponseKind.success ||
      SyncResponseKind.created ||
      SyncResponseKind.notModified ||
      SyncResponseKind.notFound ||
      SyncResponseKind.conflict ||
      SyncResponseKind.redirectRefused ||
      SyncResponseKind.unexpectedStatus => SyncFailureCause.unexpectedResponse,
    };

/// The cause a thrown [error] stands for.
///
/// Reads [SyncWorkerFailure.cause] when the throw crossed the worker isolate,
/// because by then the original error is only a string.
SyncFailureCause syncFailureCauseForError(Object error) => switch (error) {
  SyncWorkerFailure(:final cause) => cause,
  SyncTransportException() => SyncFailureCause.timedOut,
  SyncEndpointException() => SyncFailureCause.unexpectedResponse,
  SocketException() ||
  TlsException() ||
  HttpException() ||
  http.ClientException() => SyncFailureCause.unreachable,
  _ => SyncFailureCause.internal,
};

/// A pass that threw inside the worker isolate, as the parent receives it.
///
/// Implements [StateError]'s role from before: the message is still the
/// worker's `'$error'` text for logs, and [cause] is what the worker
/// classified it as while it still had the original error.
final class SyncWorkerFailure extends StateError {
  SyncWorkerFailure(super.message, this.cause);

  final SyncFailureCause cause;
}
