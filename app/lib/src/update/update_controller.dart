/// App-layer controller that owns the update-check preferences and the latest
/// check result, backed by the free-form [SettingsRepository] (F2 — the same
/// store every other setting uses). Mirrors [CustomThemesController]: a
/// [ChangeNotifier] loaded once at bootstrap, mutated from Settings, and
/// exposed to the tree via an `UpdateScope`.
///
/// The pure comparison/parse/selection logic lives in the `update/` model
/// files; this controller only holds state, persists prefs, and calls
/// [UpdateService]. Honors the ADR-002 §5 privacy contract: auto-check is
/// opt-in (default off), the banner is gated by a stored dismissed version, and
/// every failure is a silent no-op.
library;

import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app_metadata.dart';
import 'artifact_downloader.dart';
import 'artifact_handoff.dart';
import 'artifact_verifier.dart';
import 'current_platform.dart';
import 'semver.dart';
import 'update_config.dart';
import 'update_manifest.dart';
import 'update_service.dart';

/// The state of the manual "Check for updates" action, surfaced as inline
/// status text in Settings (never an error dialog — ADR-002 §5).
enum UpdateCheckStatus {
  /// No check has run yet this session.
  idle,

  /// A check is in flight.
  checking,

  /// A check completed and found no newer version — this also covers a silent
  /// failure (offline/404/malformed), which the privacy contract makes
  /// indistinguishable from "up to date" by design.
  noUpdate,

  /// A check found a strictly-newer version (the banner is now eligible).
  updateAvailable,
}

/// The state of the desktop assisted-download flow (ADR-002 "Stage 1.5"):
/// download → mandatory sha256 verify → OS-handoff. Surfaced by the banner and
/// Settings so the user sees progress and — unlike the silent check — a clear
/// error on failure.
enum AssistedDownloadStatus {
  /// No download has been started (or a terminal state was cleared by a fresh
  /// check).
  idle,

  /// The artifact is streaming to a temp file.
  downloading,

  /// The download finished and its sha256 is being verified.
  verifying,

  /// Verification passed; the verified file is being handed to the OS installer.
  handingOff,

  /// The OS-handoff succeeded — the user finishes installing from here. On
  /// macOS the installer was launched; on Windows/Linux it was revealed in the
  /// file manager for the user to run (see [UpdateController.handoffResult]).
  completed,

  /// The download, verification, or handoff failed. [UpdateController.downloadError]
  /// holds a user-facing message; a verification failure has already deleted the
  /// file.
  failed,

  /// The user cancelled an in-flight download.
  cancelled,
}

/// Owns update prefs + the latest check result.
class UpdateController extends ChangeNotifier {
  UpdateController(
    this._settings, {
    UpdateService? service,
    SemVer? currentVersion,
    UpdatePlatform? platform,
    UpdateArch? arch,
    ArtifactDownloader? downloader,
    ArtifactVerifier? verifier,
    ArtifactHandoff? handoff,
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _service = service ?? UpdateService(),
       currentVersion =
           currentVersion ??
           (SemVer.tryParse(kAppVersion) ??
               const SemVer(major: 0, minor: 0, patch: 0)),
       _platform = platform ?? currentUpdatePlatform(),
       _arch = arch ?? currentUpdateArch(),
       _downloader = downloader ?? downloadArtifact,
       _verifier = verifier ?? verifyArtifactSha256,
       _handoff = handoff ?? handoffArtifactToOs,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory;

  final SettingsRepository _settings;
  final UpdateService _service;

  /// The assisted-download seams (ADR-002 "Stage 1.5"), all injectable so the
  /// flow is unit-testable without a real network, disk hash, or OS launch.
  final ArtifactDownloader _downloader;
  final ArtifactVerifier _verifier;
  final ArtifactHandoff _handoff;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  /// The running app version (parsed from [kAppVersion]) that manifest versions
  /// are compared against.
  final SemVer currentVersion;

  final UpdatePlatform _platform;
  final UpdateArch _arch;

  bool _betaChannel = false;
  bool _autoCheck = false;
  SemVer? _dismissedVersion;
  UpdateAvailable? _available;
  UpdateCheckStatus _status = UpdateCheckStatus.idle;

  AssistedDownloadStatus _downloadStatus = AssistedDownloadStatus.idle;
  DownloadProgress? _downloadProgress;
  String? _downloadError;
  HandoffResult? _handoffResult;
  DownloadCancelToken? _cancelToken;
  int _lastNotifiedProgressTick = -1;

  /// Whether the user has opted into the beta channel (default off → stable).
  bool get betaChannel => _betaChannel;

  /// Whether the automatic background check is enabled (default off).
  bool get autoCheck => _autoCheck;

  /// The channel the check fetches, derived from [betaChannel].
  UpdateChannel get channel =>
      _betaChannel ? UpdateChannel.beta : UpdateChannel.stable;

  /// The last version the user dismissed from the banner, or `null`.
  SemVer? get dismissedVersion => _dismissedVersion;

  /// The status of the most recent manual check.
  UpdateCheckStatus get status => _status;

  /// The most recent found update, ungated by the dismissed version — used by
  /// Settings to name the available version even if the banner is suppressed.
  /// The banner itself uses [bannerUpdate], which applies the dismissed gate.
  UpdateAvailable? get foundUpdate => _available;

  /// The update the banner should show, or `null`. Applies the dismissed-version
  /// gate: a found update is shown only while it is **strictly newer** than the
  /// dismissed version, so a dismissed version never reappears until a newer one
  /// is published (ADR-002 §5).
  UpdateAvailable? get bannerUpdate {
    final found = _available;
    if (found == null) return null;
    final dismissed = _dismissedVersion;
    if (dismissed != null && !found.version.isNewerThan(dismissed)) return null;
    return found;
  }

  /// The status of the desktop assisted-download flow.
  AssistedDownloadStatus get downloadStatus => _downloadStatus;

  /// The latest download progress snapshot while [downloadStatus] is
  /// [AssistedDownloadStatus.downloading], else `null`.
  DownloadProgress? get downloadProgress => _downloadProgress;

  /// A user-facing error when [downloadStatus] is
  /// [AssistedDownloadStatus.failed], else `null`.
  String? get downloadError => _downloadError;

  /// How the verified artifact was handed off when [downloadStatus] is
  /// [AssistedDownloadStatus.completed] — [HandoffResult.launched] on macOS,
  /// [HandoffResult.revealed] on Windows/Linux — so the UI can instruct the
  /// user accurately (open vs. run-it-yourself). `null` before completion.
  HandoffResult? get handoffResult => _handoffResult;

  /// Whether an assisted download/verify/handoff is currently in flight (so the
  /// UI shows progress + a cancel affordance and suppresses a second start).
  bool get isDownloadInFlight =>
      _downloadStatus == AssistedDownloadStatus.downloading ||
      _downloadStatus == AssistedDownloadStatus.verifying ||
      _downloadStatus == AssistedDownloadStatus.handingOff;

  /// The artifact the assisted-download flow would fetch, or `null` when the
  /// flow is unavailable: only on **desktop** (ADR-002 "Stage 1.5" is
  /// desktop-only; mobile stays a link) and only when the found update actually
  /// carries an artifact for this platform/arch. The banner/Settings offer
  /// "Download & install" exactly when this is non-null.
  UpdateArtifact? get downloadableArtifact {
    if (!isDesktopUpdatePlatform(_platform)) return null;
    return _available?.artifact;
  }

  /// Whether the "Download & install" affordance should be offered.
  bool get canAssistDownload => downloadableArtifact != null;

  /// Runs the desktop assisted-download flow for the found update's artifact:
  /// stream it to a temp file → **mandatory sha256 verification** → OS-handoff.
  /// A concurrent call is ignored while one is in flight. Never throws — every
  /// failure resolves to [AssistedDownloadStatus.failed] with a user-facing
  /// [downloadError] (a verification mismatch also deletes the file). This is
  /// deliberately **not** a silent no-op like the check: it is a security gate
  /// (ADR-002 §6, "Stage 1.5").
  Future<void> startAssistedDownload() async {
    if (isDownloadInFlight) return;
    final artifact = downloadableArtifact;
    if (artifact == null) return;

    final token = DownloadCancelToken();
    _cancelToken = token;
    _downloadError = null;
    _downloadProgress = null;
    _handoffResult = null;
    _lastNotifiedProgressTick = -1;
    _downloadStatus = AssistedDownloadStatus.downloading;
    notifyListeners();

    final Directory dir;
    try {
      dir = await _temporaryDirectoryProvider();
    } on Object {
      _failDownload('Could not prepare a place to download the update.');
      return;
    }
    final destination = File('${dir.path}/${downloadFileName(artifact.url)}');

    File? downloaded;
    try {
      final outcome = await _downloader(
        artifact,
        destination: destination,
        onProgress: _onDownloadProgress,
        cancelToken: token,
      );

      if (token.isCancelled || outcome.kind == DownloadResultKind.cancelled) {
        _cancelDownloadState(outcome.file);
        return;
      }
      if (!outcome.isSuccess || outcome.file == null) {
        _failDownload(_downloadFailureMessage(outcome.kind));
        return;
      }
      final file = outcome.file!;
      downloaded = file;

      _downloadStatus = AssistedDownloadStatus.verifying;
      _downloadProgress = null;
      notifyListeners();

      final verified = await _verifier(file, artifact.sha256);
      if (token.isCancelled) {
        _cancelDownloadState(file);
        return;
      }
      if (!verified) {
        await _deleteQuietly(file);
        _failDownload(
          'The downloaded update failed its security (sha256) check and was '
          'deleted. Try again, or use "View release" to download it manually.',
        );
        return;
      }

      _downloadStatus = AssistedDownloadStatus.handingOff;
      notifyListeners();

      final handoff = await _handoff(file, _platform);
      if (handoff == HandoffResult.failed) {
        _failDownload(
          'The update was downloaded and verified, but could not be opened '
          'automatically. Use "View release" to finish installing.',
        );
        return;
      }

      _handoffResult = handoff;
      _downloadStatus = AssistedDownloadStatus.completed;
      _downloadProgress = null;
      notifyListeners();
    } on Object {
      // The default seams are written to fail closed (return a result, never
      // throw), but an injected seam or an unforeseen I/O error could throw.
      // Honour this method's "never throws" contract: delete any partial file
      // and surface a loud, actionable error instead of getting stuck in-flight.
      await _deleteQuietly(downloaded ?? destination);
      _failDownload(
        'Something went wrong while installing the update. Try again, or use '
        '"View release" to download it manually.',
      );
    } finally {
      _cancelToken = null;
    }
  }

  /// Requests cancellation of an in-flight assisted download. A no-op when
  /// nothing is running; the flow resolves to [AssistedDownloadStatus.cancelled]
  /// and the partial file is deleted.
  void cancelDownload() => _cancelToken?.cancel();

  /// Clears a terminal download state (completed/failed/cancelled) back to idle
  /// so the affordance re-arms — e.g. after the user reads an error and wants to
  /// retry.
  void resetDownload() {
    if (isDownloadInFlight) return;
    _downloadStatus = AssistedDownloadStatus.idle;
    _downloadProgress = null;
    _downloadError = null;
    _handoffResult = null;
    notifyListeners();
  }

  void _onDownloadProgress(DownloadProgress progress) {
    _downloadProgress = progress;
    // Throttle rebuilds: notify only when the whole-percent (or, when the total
    // is unknown, each ~256 KiB) advances, so a fast stream does not spam the
    // banner/Settings with a rebuild per chunk.
    final fraction = progress.fraction;
    final tick = fraction != null
        ? (fraction * 100).floor()
        : progress.bytesReceived ~/ (256 * 1024);
    if (tick != _lastNotifiedProgressTick) {
      _lastNotifiedProgressTick = tick;
      notifyListeners();
    }
  }

  void _cancelDownloadState(File? file) {
    if (file != null) unawaited(_deleteQuietly(file));
    _downloadStatus = AssistedDownloadStatus.cancelled;
    _downloadProgress = null;
    _downloadError = null;
    _handoffResult = null;
    _cancelToken = null;
    notifyListeners();
  }

  void _failDownload(String message) {
    _downloadStatus = AssistedDownloadStatus.failed;
    _downloadError = message;
    _downloadProgress = null;
    _handoffResult = null;
    _cancelToken = null;
    notifyListeners();
  }

  String _downloadFailureMessage(DownloadResultKind kind) {
    switch (kind) {
      case DownloadResultKind.sizeMismatch:
        return 'The download was incomplete and was deleted. Please try again, '
            'or use "View release".';
      case DownloadResultKind.refusedHost:
        return 'The update download was refused because it pointed at an '
            'unexpected location. Use "View release" to download it manually.';
      case DownloadResultKind.networkError:
      case DownloadResultKind.success:
      case DownloadResultKind.cancelled:
        return 'The update could not be downloaded. Check your connection and '
            'try again, or use "View release".';
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Best-effort cleanup.
    }
  }

  /// Clears a terminal (or idle) download state when a fresh check result comes
  /// in, so a newly-found version re-arms the affordance. Leaves an in-flight
  /// download untouched.
  void _resetDownloadForNewResult() {
    if (isDownloadInFlight) return;
    if (_downloadStatus == AssistedDownloadStatus.idle &&
        _downloadError == null) {
      return;
    }
    _downloadStatus = AssistedDownloadStatus.idle;
    _downloadProgress = null;
    _downloadError = null;
    _handoffResult = null;
  }

  /// Loads the persisted prefs into memory. Defensive: any read failure or
  /// non-bool value falls back to the safe default (off) so startup never
  /// blocks on a settings hiccup.
  Future<void> load() async {
    final beta = await _settings
        .get(kUpdateBetaChannelKey)
        .catchError((_) => null);
    _betaChannel = beta is bool ? beta : false;

    final auto = await _settings
        .get(kUpdateAutoCheckKey)
        .catchError((_) => null);
    _autoCheck = auto is bool ? auto : false;

    final dismissed = await _settings
        .get(kUpdateDismissedVersionKey)
        .catchError((_) => null);
    _dismissedVersion = dismissed is String ? SemVer.tryParse(dismissed) : null;

    notifyListeners();
  }

  /// Runs a check now (the manual "Check for updates" action, always
  /// available). Concurrent presses are ignored while one is in flight. Never
  /// throws — a failure resolves to [UpdateCheckStatus.noUpdate].
  Future<void> checkNow() async {
    if (_status == UpdateCheckStatus.checking) return;
    _status = UpdateCheckStatus.checking;
    notifyListeners();

    final requestedChannel = channel;
    final result = await _service.check(
      channel: requestedChannel,
      currentVersion: currentVersion,
      platform: _platform,
      arch: _arch,
    );

    // The user switched channels while this check was in flight — the result
    // belongs to the old channel, so drop it (setBetaChannel already reset the
    // state for the new channel) to avoid a stale cross-channel banner.
    if (requestedChannel != channel) return;

    _available = result;
    _resetDownloadForNewResult();
    _status = result == null
        ? UpdateCheckStatus.noUpdate
        : UpdateCheckStatus.updateAvailable;
    notifyListeners();
  }

  /// Triggers a check only when the auto-check pref is on (opt-in, default
  /// off). Wired to app bootstrap so a check runs at most once per launch and
  /// only for opted-in users (ADR-002 §5).
  Future<void> maybeAutoCheck() async {
    if (_autoCheck) await checkNow();
  }

  /// Sets the beta opt-in and persists it. Switching channels clears any
  /// pending result/status (it belonged to the other channel) so a stale
  /// cross-channel banner never lingers.
  Future<void> setBetaChannel(bool value) async {
    if (_betaChannel == value) return;
    _betaChannel = value;
    _available = null;
    _status = UpdateCheckStatus.idle;
    _resetDownloadForNewResult();
    notifyListeners();
    await _settings.set(kUpdateBetaChannelKey, value);
  }

  /// Sets the auto-check opt-in and persists it.
  Future<void> setAutoCheck(bool value) async {
    if (_autoCheck == value) return;
    _autoCheck = value;
    notifyListeners();
    await _settings.set(kUpdateAutoCheckKey, value);
  }

  /// Records [version] as dismissed (hiding the banner until a strictly-newer
  /// version appears) and persists it.
  Future<void> dismiss(SemVer version) async {
    _dismissedVersion = version;
    notifyListeners();
    await _settings.set(kUpdateDismissedVersionKey, version.toString());
  }
}
