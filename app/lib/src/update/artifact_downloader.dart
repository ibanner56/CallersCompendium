/// The assisted-download engine (ADR-002 "Stage 1.5"): streams an
/// [UpdateArtifact] from its `url` to a local temp file using the **same
/// injected `http.Client` seam** as `update_fetcher.dart`, reporting progress
/// and honoring a cooperative cancel signal.
///
/// This is pure, Flutter-free logic (only `dart:io`/`dart:async`/`package:http`)
/// so it is unit-testable with a `MockClient` and a caller-provided destination
/// — no `path_provider`, no widgets (ADR-001 / ADR-002 §8). Unlike the silent
/// update *check*, a download failure is **surfaced**, not swallowed: on any
/// failure (network, stall, cancel, or a byte-count mismatch against the
/// manifest's `size`) the partial temp file is deleted and a typed
/// [DownloadOutcome] is returned so the caller can show a clear error.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'update_config.dart';
import 'update_manifest.dart';

/// A cooperative cancel signal for an in-flight [downloadArtifact]. The engine
/// checks [isCancelled] as each chunk arrives and aborts (deleting the partial
/// file) the moment it is set, so a user "Cancel" resolves promptly.
class DownloadCancelToken {
  bool _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() => _cancelled = true;
}

/// A progress snapshot emitted while streaming. [totalBytes] is the best-known
/// size (the response `Content-Length`, falling back to the manifest `size`);
/// it is `0` only when neither is known, in which case [fraction] is `null`.
class DownloadProgress {
  const DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
  });

  final int bytesReceived;
  final int totalBytes;

  /// The completed fraction in `[0, 1]`, or `null` when the total is unknown.
  double? get fraction {
    if (totalBytes <= 0) return null;
    final f = bytesReceived / totalBytes;
    if (f < 0) return 0;
    if (f > 1) return 1;
    return f;
  }
}

/// Why a download ended.
enum DownloadResultKind {
  /// The full artifact was written and its byte count matched the manifest.
  success,

  /// The caller cancelled via a [DownloadCancelToken].
  cancelled,

  /// A transport failure or stall (offline, DNS/TLS, non-2xx, idle timeout).
  networkError,

  /// The download completed but its byte count disagreed with the manifest
  /// `size` — treated as an integrity failure, not a success.
  sizeMismatch,
}

/// The typed result of [downloadArtifact]. On [DownloadResultKind.success],
/// [file] is the written temp file; otherwise [file] is `null` (the partial
/// file has been deleted) and [message] carries a short, non-user-facing reason
/// for tests/logging.
class DownloadOutcome {
  const DownloadOutcome._(this.kind, {this.file, this.message});

  factory DownloadOutcome.success(File file) =>
      DownloadOutcome._(DownloadResultKind.success, file: file);

  factory DownloadOutcome.cancelled() =>
      const DownloadOutcome._(DownloadResultKind.cancelled);

  factory DownloadOutcome.networkError(String message) =>
      DownloadOutcome._(DownloadResultKind.networkError, message: message);

  factory DownloadOutcome.sizeMismatch(String message) =>
      DownloadOutcome._(DownloadResultKind.sizeMismatch, message: message);

  final DownloadResultKind kind;
  final File? file;
  final String? message;

  bool get isSuccess => kind == DownloadResultKind.success;
}

/// The injectable download seam. The [UpdateController] depends on this typedef
/// (default [downloadArtifact]) so tests substitute a fake that returns canned
/// outcomes/progress without a real network call.
typedef ArtifactDownloader =
    Future<DownloadOutcome> Function(
      UpdateArtifact artifact, {
      required File destination,
      http.Client? client,
      void Function(DownloadProgress)? onProgress,
      DownloadCancelToken? cancelToken,
    });

/// Default [ArtifactDownloader]: streams [artifact] from its `url` into
/// [destination], calling [onProgress] as bytes arrive and aborting when
/// [cancelToken] is set.
///
/// Uses `client.send` (streamed) rather than a buffered `get` so a large
/// artifact never fully materializes in memory and progress/cancel work while
/// the body is still arriving. An **idle timeout** ([kUpdateDownloadTimeout])
/// guards a stalled connection without capping a legitimately long transfer.
/// After the stream ends, the written byte count is validated against the
/// manifest `size`; a mismatch is a [DownloadResultKind.sizeMismatch]. Every
/// non-success path deletes the partial file so no truncated artifact is ever
/// handed to verification.
Future<DownloadOutcome> downloadArtifact(
  UpdateArtifact artifact, {
  required File destination,
  http.Client? client,
  void Function(DownloadProgress)? onProgress,
  DownloadCancelToken? cancelToken,
}) async {
  final uri = Uri.tryParse(artifact.url);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return DownloadOutcome.networkError(
      'invalid artifact URL "${artifact.url}"',
    );
  }

  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  IOSink? sink;
  var received = 0;
  var succeeded = false;
  var sinkClosed = false;

  try {
    if (cancelToken != null && cancelToken.isCancelled) {
      return DownloadOutcome.cancelled();
    }

    final http.StreamedResponse response;
    try {
      response = await effectiveClient
          .send(http.Request('GET', uri))
          .timeout(kUpdateDownloadTimeout);
    } on TimeoutException {
      return DownloadOutcome.networkError('connection timed out');
    } on Object catch (e) {
      return DownloadOutcome.networkError(e.toString());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return DownloadOutcome.networkError('HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? artifact.size;
    sink = destination.openWrite();

    final done = Completer<DownloadOutcome>();
    late StreamSubscription<List<int>> sub;
    Timer? idle;

    void bumpIdle() {
      idle?.cancel();
      idle = Timer(kUpdateDownloadTimeout, () {
        if (!done.isCompleted) {
          done.complete(DownloadOutcome.networkError('download stalled'));
        }
      });
    }

    bumpIdle();
    sub = response.stream.listen(
      (chunk) {
        if (done.isCompleted) return;
        if (cancelToken != null && cancelToken.isCancelled) {
          done.complete(DownloadOutcome.cancelled());
          return;
        }
        sink!.add(chunk);
        received += chunk.length;
        bumpIdle();
        onProgress?.call(
          DownloadProgress(bytesReceived: received, totalBytes: total),
        );
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.complete(DownloadOutcome.networkError(e.toString()));
        }
      },
      onDone: () {
        if (done.isCompleted) return;
        if (artifact.size > 0 && received != artifact.size) {
          done.complete(
            DownloadOutcome.sizeMismatch(
              'expected ${artifact.size} bytes, received $received',
            ),
          );
        } else {
          done.complete(DownloadOutcome.success(destination));
        }
      },
      cancelOnError: true,
    );

    final outcome = await done.future;
    idle?.cancel();
    await sub.cancel();

    // Flush + close the file BEFORE deciding success. A flush/close failure
    // (disk full, permission, etc.) means the on-disk bytes are incomplete, so
    // an otherwise-successful transfer must be downgraded to a failure — never
    // hand a partial/corrupt file to sha256 verification or the OS handoff.
    // (A non-success outcome already deletes the file below, so its kind is
    // preserved even if the close also fails.)
    sinkClosed = true;
    try {
      await sink.flush();
      await sink.close();
    } on Object catch (e) {
      succeeded = false;
      if (outcome.isSuccess) {
        return DownloadOutcome.networkError(
          'could not finish writing file: $e',
        );
      }
      return outcome;
    }

    succeeded = outcome.isSuccess;
    return outcome;
  } finally {
    if (sink != null && !sinkClosed) {
      try {
        await sink.close();
      } on Object {
        // ignore
      }
    }
    if (!succeeded) {
      try {
        if (await destination.exists()) await destination.delete();
      } on Object {
        // Best-effort cleanup; never mask the real outcome with a delete error.
      }
    }
    if (ownClient) effectiveClient.close();
  }
}
