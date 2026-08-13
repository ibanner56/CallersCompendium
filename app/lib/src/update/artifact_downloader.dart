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

  /// The artifact URL — or a redirect hop on the way to it — targeted a host
  /// that is not on [kAllowedArtifactHosts] (or used a non-https scheme,
  /// userinfo, or a non-443 port). Refused before any bytes are written
  /// (issue #431).
  refusedHost,
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

  factory DownloadOutcome.refusedHost(String message) =>
      DownloadOutcome._(DownloadResultKind.refusedHost, message: message);

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
/// the body is still arriving. The `url` — and **every redirect hop** — must be
/// an https URL whose host is on [kAllowedArtifactHosts] (with no userinfo and
/// only the default 443 port); redirects are followed manually so an
/// `https→http` downgrade or an off-allowlist / userinfo / non-443 hop is
/// refused ([DownloadResultKind.refusedHost]) rather than silently followed
/// (defense-in-depth alongside the manifest signature+parse checks and the
/// sha256 gate). An **idle timeout** ([kUpdateDownloadTimeout]) guards a stalled
/// connection without capping a legitimately long transfer, and the transfer is
/// aborted the moment it would exceed the manifest's declared `size` (or
/// [kMaxArtifactDownloadBytes] when the artifact is unsized) so an oversized
/// body cannot fill the disk. After the stream ends, the written byte count is
/// validated against the manifest `size`; a mismatch is a
/// [DownloadResultKind.sizeMismatch]. Every non-success path deletes the
/// partial file — but only one this call itself created — so no truncated
/// artifact is ever handed to verification.
///
/// [destination] is refused if anything already sits at that path — checked
/// **without following a symlink** — before any byte is written (issue #626):
/// a pre-existing file, directory, or symlink (dangling or not) fails the
/// download closed rather than being written through. A `create(exclusive:
/// true)` immediately follows as defense-in-depth against a TOCTOU race
/// between the check and the create. Together these close a local
/// symlink/predictable-path attack (CWE-59/377). Callers should additionally
/// route [destination] through an unpredictable directory (e.g.
/// `Directory.createTemp`) so neither guard here is the sole line of defense.
Future<DownloadOutcome> downloadArtifact(
  UpdateArtifact artifact, {
  required File destination,
  http.Client? client,
  void Function(DownloadProgress)? onProgress,
  DownloadCancelToken? cancelToken,
}) async {
  final uri = Uri.tryParse(artifact.url);
  if (uri == null || !isAllowedArtifactHost(uri)) {
    return DownloadOutcome.refusedHost(
      'artifact URL host is not allowed "${artifact.url}"',
    );
  }

  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  IOSink? sink;
  var received = 0;
  var succeeded = false;
  var sinkClosed = false;
  // Only ever delete a file this call itself created — never a pre-existing
  // entity found at [destination] (see the `create(exclusive: true)` call
  // below), so a symlink an attacker pre-planted at a predictable path is
  // never touched, let alone followed.
  var createdDestination = false;

  try {
    if (cancelToken != null && cancelToken.isCancelled) {
      return DownloadOutcome.cancelled();
    }

    final http.StreamedResponse response;
    try {
      response = await _sendFollowingHttpsRedirects(
        effectiveClient,
        uri,
      ).timeout(kUpdateDownloadTimeout);
    } on TimeoutException {
      // diagnostics: silent — returns DownloadOutcome to the update-layer
      // caller, not UI.
      return DownloadOutcome.networkError('connection timed out');
    } on _RedirectException catch (e) {
      // diagnostics: silent — redirect policy violation; returns DownloadOutcome to update-layer caller, not UI.
      return e.refusedHost
          ? DownloadOutcome.refusedHost(e.message)
          : DownloadOutcome.networkError(e.message);
    } on Object catch (e) {
      // diagnostics: silent — HTTP request failed (network/redirect error); returns DownloadOutcome to update-layer caller, not UI.
      return DownloadOutcome.networkError(e.toString());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return DownloadOutcome.networkError('HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? artifact.size;
    // The most bytes we are willing to write for this artifact: the manifest's
    // (positive) declared size when known, else an absolute backstop so an
    // unsized artifact from a misbehaving host cannot stream unbounded bytes to
    // disk (OWASP A08 / resource exhaustion).
    final maxBytes = artifact.size > 0
        ? artifact.size
        : kMaxArtifactDownloadBytes;

    // Refuse if anything already sits at [destination] — checked WITHOUT
    // following a symlink (`FileSystemEntity.type(..., followLinks: false)`).
    // This closes a residual gap in relying on `create(exclusive: true)`
    // alone: an exclusive create can still race with, or (per platform/FS
    // nuance) proceed through, a pre-existing symlink whose *target* does not
    // (yet) exist, creating the target through the link. Rejecting any
    // existing entity at the raw path — file, directory, or link, dangling or
    // not — means we never open, never write, and never delete a pre-existing
    // entity (the cleanup in `finally` below only ever removes a file *this
    // call* created).
    final existingType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (existingType != FileSystemEntityType.notFound) {
      return DownloadOutcome.networkError(
        'refusing to write: something already exists at the destination path',
      );
    }

    // Create the destination **exclusively** (`O_EXCL`-equivalent) as
    // defense-in-depth on top of the check above: this fails closed if
    // anything appears at [destination] between the check and this call
    // (TOCTOU), instead of writing through it. That defeats a local symlink
    // attack (CWE-59) where an attacker pre-plants a symlink at a predictable
    // path to redirect the write at a target of their choosing: `openWrite()`
    // alone would happily follow it. Callers additionally pair this with an
    // unpredictable destination path (see
    // `UpdateController.startAssistedDownload`), so neither guard here is the
    // sole line of defense.
    try {
      await destination.create(exclusive: true);
      createdDestination = true;
    } on Object catch (e) {
      // diagnostics: silent — destination file creation failed; returns DownloadOutcome to update-layer caller, not UI.
      return DownloadOutcome.networkError(
        'could not create destination file securely: $e',
      );
    }
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
        // Abort the moment the transfer would exceed its budget, before writing
        // the over-budget chunk, so a body larger than the manifest promises
        // (or an unsized body past the absolute backstop) never fills the disk
        // and never reaches sha256 verification as a "complete" file.
        if (received + chunk.length > maxBytes) {
          done.complete(
            artifact.size > 0
                ? DownloadOutcome.sizeMismatch(
                    'exceeded expected ${artifact.size} bytes',
                  )
                : DownloadOutcome.networkError(
                    'download exceeded the maximum of $maxBytes bytes',
                  ),
          );
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
        // diagnostics: silent — returns DownloadOutcome to the update-layer
        // caller, not UI.
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
      // diagnostics: silent — sink flush/close failed; returns DownloadOutcome to update-layer caller, not UI.
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
        // diagnostics: silent — ignore; the download's real outcome (success
        // or failure) is already determined above.
      }
    }
    if (!succeeded && createdDestination) {
      try {
        if (await destination.exists()) await destination.delete();
      } on Object {
        // diagnostics: silent — best-effort cleanup; never mask the real
        // outcome with a delete error.
      }
    }
    if (ownClient) effectiveClient.close();
  }
}

/// Whether [status] is an HTTP redirect [_sendFollowingHttpsRedirects] follows.
bool _isRedirectStatus(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;

/// Sends a streamed `GET` for [uri], following redirects **manually**
/// (`followRedirects = false`) so every hop is re-validated against
/// [isAllowedArtifactHost] — an https URL on [kAllowedArtifactHosts] with no
/// userinfo and only the default 443 port. This closes the downgrade/exfil hole
/// that the `package:http` default (`followRedirects = true`) would otherwise
/// leave open — an artifact URL that 30x-redirects to `http://…`, to an
/// off-allowlist host, or via a userinfo/port trick is refused rather than
/// silently followed — while still allowing the legitimate
/// `github.com → release-assets.githubusercontent.com` redirect GitHub uses to
/// serve release assets. The hop count is capped at [kMaxArtifactRedirects].
/// Returns the final, non-redirect [http.StreamedResponse] for the caller to
/// stream.
Future<http.StreamedResponse> _sendFollowingHttpsRedirects(
  http.Client client,
  Uri uri,
) async {
  var current = uri;
  for (var hops = 0; ; hops++) {
    final request = http.Request('GET', current)..followRedirects = false;
    final response = await client.send(request);
    if (!_isRedirectStatus(response.statusCode)) return response;

    // A redirect: discard its (small) body so the connection is freed, then
    // validate the next hop before re-issuing.
    await response.stream.drain<void>();
    if (hops >= kMaxArtifactRedirects) {
      throw const _RedirectException('too many redirects');
    }
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw const _RedirectException('redirect without a location');
    }
    final next = current.resolve(location);
    if (!isAllowedArtifactHost(next)) {
      throw const _RedirectException(
        'refused redirect to a disallowed host',
        refusedHost: true,
      );
    }
    current = next;
  }
}

/// Signals a redirect that [_sendFollowingHttpsRedirects] refused (an
/// off-allowlist/non-https hop, a missing `Location`, or exceeding
/// [kMaxArtifactRedirects]). Surfaced by [downloadArtifact] as a
/// [DownloadResultKind.refusedHost] when [refusedHost] is set (a host-policy
/// refusal) and otherwise a [DownloadResultKind.networkError]; [message] is for
/// tests/logging, not the UI.
class _RedirectException implements Exception {
  const _RedirectException(this.message, {this.refusedHost = false});
  final String message;
  final bool refusedHost;
  @override
  String toString() => 'RedirectException: $message';
}
