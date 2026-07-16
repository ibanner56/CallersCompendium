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

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../app_metadata.dart';
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

/// Owns update prefs + the latest check result.
class UpdateController extends ChangeNotifier {
  UpdateController(
    this._settings, {
    UpdateService? service,
    SemVer? currentVersion,
    UpdatePlatform? platform,
    UpdateArch? arch,
  }) : _service = service ?? UpdateService(),
       currentVersion =
           currentVersion ??
           (SemVer.tryParse(kAppVersion) ??
               const SemVer(major: 0, minor: 0, patch: 0)),
       _platform = platform ?? currentUpdatePlatform(),
       _arch = arch ?? currentUpdateArch();

  final SettingsRepository _settings;
  final UpdateService _service;

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

    final result = await _service.check(
      channel: channel,
      currentVersion: currentVersion,
      platform: _platform,
      arch: _arch,
    );

    _available = result;
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
