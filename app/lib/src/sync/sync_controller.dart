import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../screens/settings/settings_keys.dart';
import 'sync_coordinator.dart';
import 'sync_network.dart';

/// How long before the 30-day disuse reap (spec §7.3) the status surface starts
/// warning that the store is approaching expiry (spec §6.14 item 4).
const Duration kSyncExpiryWarningAfter = Duration(days: 21);

/// The delay between a local change and the automatic pass it triggers.
const Duration kSyncChangeDebounce = Duration(seconds: 30);

/// What a trigger request did.
enum SyncGateOutcome {
  /// The coordinator ran a pass; see [SyncController.lastResult].
  ran,

  /// Device Sync is off. Nothing was constructed or requested.
  disabled,

  /// Sync is on but no store has been paired yet, so there is nothing to sync.
  notPaired,

  /// *Sync only on WiFi* is on and the connection is metered. An automatic
  /// trigger is dropped; a manual one is routed to the setting.
  suppressedMetered,

  /// There is no connection. The pass runs at the next trigger.
  suppressedOffline,
}

/// Owns the Device Sync settings, the §6.12 trigger policy and the state the
/// status surface shows.
///
/// A suppressed pass is never recorded as a completed one: no last-success time
/// is written and no state is latched, so the next trigger runs it without the
/// user doing anything.
class SyncController extends ChangeNotifier {
  SyncController({
    required this._settings,
    required this._coordinator,
    required this._reconfigure,
    this._classifier = const ConnectivityPlusNetworkClassifier(),
    DateTime Function()? now,
    this._debounce = kSyncChangeDebounce,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final SettingsRepository _settings;
  final SyncCoordinator? Function() _coordinator;
  final Future<void> Function() _reconfigure;
  final SyncNetworkClassifier _classifier;
  final DateTime Function() _now;
  final Duration _debounce;

  bool _enabled = false;
  bool _paired = false;
  bool _wifiOnly = true;
  bool _excludeImports = false;
  DateTime? _lastSuccessAt;
  SyncPassResult? _lastResult;
  bool _running = false;
  DateTime? _quietUntil;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// Bumped when a manual attempt on a metered connection is routed to the
  /// *Sync only on WiFi* setting; the settings section listens and surfaces it.
  final ValueNotifier<int> wifiSettingRequests = ValueNotifier<int>(0);

  bool get enabled => _enabled;
  bool get paired => _paired;
  bool get wifiOnly => _wifiOnly;
  bool get excludeImports => _excludeImports;
  DateTime? get lastSuccessAt => _lastSuccessAt;
  SyncPassResult? get lastResult => _lastResult;
  bool get running => _running;

  /// Whether the status surface should warn that the store is approaching the
  /// disuse expiry.
  bool get expiryApproaching {
    final last = _lastSuccessAt;
    if (!_enabled || !_paired || last == null) return false;
    return _now().difference(last) >= kSyncExpiryWarningAfter;
  }

  /// Reads the persisted state. Absent keys mean the documented defaults: sync
  /// off, WiFi-only on, import exclusion off.
  Future<void> load() async {
    _enabled = await _settings.get(kSyncEnabledKey) == true;
    final wifi = await _settings.get(kSyncWifiOnlyKey);
    _wifiOnly = wifi is bool ? wifi : true;
    _excludeImports = await _settings.get(kSyncExcludeImportsKey) == true;
    final id = await _settings.get(kSyncIdKey);
    _paired = id is String && normalizeSyncId(id).isNotEmpty;
    final last = await _settings.get(kSyncLastSuccessAtKey);
    _lastSuccessAt = last is String ? DateTime.tryParse(last)?.toUtc() : null;
    _notify();
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    await _settings.set(kSyncEnabledKey, value);
    if (!value) _debounceTimer?.cancel();
    _notify();
    await _reconfigure();
  }

  Future<void> setWifiOnly(bool value) async {
    if (value == _wifiOnly) return;
    _wifiOnly = value;
    await _settings.set(kSyncWifiOnlyKey, value);
    _notify();
  }

  /// Runs the app-start trigger (spec §6.12).
  Future<SyncGateOutcome> onAppStart() => trigger(SyncTrigger.appStart);

  /// Tells the controller a local write happened. Schedules one debounced
  /// automatic pass; repeated changes inside the window share it.
  void notifyLocalChange() {
    if (_disposed || !_enabled) return;
    final quiet = _quietUntil;
    if (_running || (quiet != null && _now().isBefore(quiet))) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(trigger(SyncTrigger.debouncedChange));
    });
  }

  /// A manual "Sync now".
  Future<SyncGateOutcome> syncNow() => trigger(SyncTrigger.manual);

  /// The one entry every §6.12 trigger goes through.
  Future<SyncGateOutcome> trigger(SyncTrigger trigger) async {
    if (_disposed || !_enabled) return SyncGateOutcome.disabled;
    final coordinator = _coordinator();
    if (coordinator == null) return SyncGateOutcome.notPaired;

    final network = await _classifier.current();
    if (network == SyncNetworkKind.offline) {
      return SyncGateOutcome.suppressedOffline;
    }
    if (_wifiOnly && network == SyncNetworkKind.metered) {
      if (trigger == SyncTrigger.manual) wifiSettingRequests.value++;
      return SyncGateOutcome.suppressedMetered;
    }

    _running = true;
    _notify();
    try {
      final result = await coordinator.trigger(trigger);
      _lastResult = result;
      if (result.status == SyncPassStatus.completed) {
        final at = _now();
        _lastSuccessAt = at;
        await _settings.set(kSyncLastSuccessAtKey, at.toIso8601String());
      }
      return SyncGateOutcome.ran;
    } finally {
      _running = false;
      // The pass's own applied rows and its status write reach the change
      // stream after it returns; they are not user edits.
      _quietUntil = _now().add(const Duration(seconds: 2));
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    wifiSettingRequests.dispose();
    super.dispose();
  }
}
