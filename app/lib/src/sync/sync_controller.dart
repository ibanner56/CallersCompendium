import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/error_log.dart';
import '../screens/settings/settings_keys.dart';
import 'sync_coordinator.dart';
import 'sync_http_client.dart';
import 'sync_network.dart';

/// The subset of [SyncHttpClient] pairing needs: an explicit create-or-connect
/// probe issued before any sync identity is persisted (spec §6.2, §6.14.5).
/// A record, not a class, so tests can supply plain closures without a fake
/// implementing the full transport surface.
class SyncPairingProbe {
  const SyncPairingProbe({
    required this.getStore,
    required this.createStore,
    this.close,
  });

  /// `GET /v1/store`. Never issues a creation request (spec §6.2 step 2).
  final Future<SyncStoreResult> Function({required bool previouslyUsed})
  getStore;

  /// `POST /v1/store`, issued only after the user explicitly chose "create".
  final Future<SyncHttpResponse> Function() createStore;

  final void Function()? close;
}

/// Builds the probe for one candidate sync ID. Defaults to a live
/// [SyncHttpClient]; tests inject a fake.
typedef SyncPairingProbeFactory = SyncPairingProbe Function(String syncId);

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
    this.endpoint,
    this._pairingProbeFactory,
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
  final SyncPairingProbeFactory? _pairingProbeFactory;

  /// The release-configured sync endpoint, or null when the build has not
  /// opted into one — pairing is unreachable without it.
  final Uri? endpoint;

  /// Builds the probe for a pairing attempt, or null when pairing is
  /// unreachable (no configured endpoint and no test factory).
  SyncPairingProbe? probeFor(String syncId) {
    final factory = _pairingProbeFactory;
    if (factory != null) return factory(syncId);
    final endpoint = this.endpoint;
    if (endpoint == null) return null;
    final client = SyncHttpClient(endpoint: endpoint, syncId: syncId);
    return SyncPairingProbe(
      getStore: client.getStore,
      createStore: client.createStore,
      close: client.close,
    );
  }

  bool _enabled = false;
  bool _paired = false;
  bool _wifiOnly = true;
  bool _excludeImports = false;
  DateTime? _lastSuccessAt;
  SyncPassResult? _lastResult;
  int _inFlight = 0;
  bool _dirty = false;
  int _pendingSelfWrites = 0;
  bool _replacementPending = false;
  Timer? _debounceTimer;
  StreamSubscription<SyncReplacementRequiredEvent>? _replacementSubscription;
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
  bool get running => _inFlight > 0;

  /// Whether a previously used collection is missing and awaiting the user's
  /// explanation-then-confirm decision (spec §6.3 step 1, §6.14 item 6).
  bool get replacementPending => _replacementPending;

  /// Whether the status surface should warn that the store is approaching the
  /// disuse expiry.
  bool get expiryApproaching {
    final last = _lastSuccessAt;
    if (!_enabled || !_paired || last == null) return false;
    return _now().difference(last) >= kSyncExpiryWarningAfter;
  }

  /// Marks that the next settings-only change notification for one write this
  /// controller is about to make is its own bookkeeping, not a user edit.
  /// Precise per-write, rather than a time window: a real preference change
  /// made in the instant after a pass records its success must still be
  /// observed, and this cannot mistake it for that recording.
  void _expectSelfWrite() => _pendingSelfWrites++;

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
    // A disable's own bookkeeping write is never observed: once `_enabled` is
    // false, `notifyLocalChange` returns before it ever inspects
    // `_pendingSelfWrites`, so an expectation queued here would sit forever
    // and swallow the first genuine settings-only edit after the next enable.
    // Resetting on every transition — rather than only skipping the disable
    // side — also clears anything a prior leak already left behind, so the
    // counter can never carry state across an enable/disable cycle.
    _pendingSelfWrites = 0;
    if (value) _expectSelfWrite();
    await _settings.set(kSyncEnabledKey, value);
    if (!value) _debounceTimer?.cancel();
    _notify();
    await _reconfigure();
  }

  Future<void> setWifiOnly(bool value) async {
    if (value == _wifiOnly) return;
    _wifiOnly = value;
    _expectSelfWrite();
    await _settings.set(kSyncWifiOnlyKey, value);
    _notify();
  }

  /// Sets the per-device upload-budget toggle for imported dances (spec
  /// §6.1). Takes effect on the next pass — [CompendiumSyncStorage.snapshot]
  /// reads it live, so this needs no reconfiguration.
  Future<void> setExcludeImports(bool value) async {
    if (value == _excludeImports) return;
    _excludeImports = value;
    _expectSelfWrite();
    await _settings.set(kSyncExcludeImportsKey, value);
    _notify();
  }

  /// Runs the app-start trigger (spec §6.12).
  Future<SyncGateOutcome> onAppStart() => trigger(SyncTrigger.appStart);

  /// Tells the controller a local write happened. Schedules one debounced
  /// automatic pass; repeated changes inside the window share it.
  ///
  /// A change that lands while a pass is running was not in that pass's
  /// snapshot, so it is remembered and one follow-up pass is scheduled when the
  /// last running pass ends. [settingsOnly] marks a write that touched only the
  /// settings table; those are ignored inside the short window that follows the
  /// controller's own bookkeeping writes, because a pass that records its own
  /// success would otherwise re-trigger itself forever.
  void notifyLocalChange({bool settingsOnly = false}) {
    if (_disposed || !_enabled) return;
    if (settingsOnly && _pendingSelfWrites > 0) {
      _pendingSelfWrites--;
      return;
    }
    if (_inFlight > 0) {
      _dirty = true;
      return;
    }
    _scheduleDebounced();
  }

  void _scheduleDebounced() {
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

    _inFlight++;
    _notify();
    try {
      SyncPassResult result;
      try {
        result = await coordinator.trigger(trigger);
      } on Object catch (error, stack) {
        // The worker isolate reports its own failure as a thrown `StateError`
        // (see sync_isolate.dart), and `_scheduleDebounced` awaits `trigger`
        // via `unawaited`, so an uncaught error here would become an
        // unhandled async error rather than a status the user ever sees.
        // Recording it as a failed pass keeps every trigger path — including
        // the debounced one — returning normally.
        //
        // Type only, as the coordinator's own `_watch` does: the text of a
        // worker or transport failure can carry the request URI, and the
        // diagnostics redactor deliberately keeps HTTPS URLs, so the message
        // would put the sync endpoint into an exported diagnostic bundle.
        logCaughtErrorTypeOnly(error, stack, source: 'sync_controller.trigger');
        result = SyncPassResult(
          SyncPassStatus.failed,
          message:
              'sync pass threw ${error.runtimeType}', // i18n-ignore: internal status
        );
      }
      await _recordResult(result);
      return SyncGateOutcome.ran;
    } finally {
      _inFlight--;
      if (_inFlight == 0 && _dirty) {
        _dirty = false;
        if (_enabled && !_disposed) _scheduleDebounced();
      }
      _notify();
    }
  }

  /// Records a pass result and, on success, persists the last-success time as
  /// the controller's own bookkeeping write (spec §6.14 item 4's clock).
  Future<void> _recordResult(SyncPassResult result) async {
    _lastResult = result;
    if (result.status == SyncPassStatus.completed) {
      final at = _now();
      _lastSuccessAt = at;
      _expectSelfWrite();
      await _settings.set(kSyncLastSuccessAtKey, at.toIso8601String());
    }
  }

  /// Attaches to the live coordinator's replacement-required stream so the
  /// status surface can show the §6.14 item 6 explanation. Called by the app
  /// whenever the coordinator is (re)built or torn down; a coordinator swap
  /// (e.g. after reconfiguration) re-subscribes rather than leaking the old
  /// stream.
  void attachCoordinator(SyncCoordinator? coordinator) {
    unawaited(_replacementSubscription?.cancel());
    _replacementSubscription = coordinator?.replacementRequired.listen((_) {
      _replacementPending = true;
      _notify();
    });
  }

  /// Confirms replacement of a previously used, now-missing collection
  /// exactly once (spec §6.14 item 6): the coordinator's own single-flight
  /// guard makes a double tap here issue only one `POST`.
  Future<SyncPassResult?> confirmReplacement() async {
    final coordinator = _coordinator();
    if (coordinator == null) return null;
    _inFlight++;
    _notify();
    try {
      final result = await coordinator.confirmReplacement();
      await _recordResult(result);
      // Only a genuinely completed confirmation resolves the decision. A
      // failure (e.g. a 500 from `POST /v1/store`) leaves the coordinator's
      // own replacement-pending state untouched — it never emits a fresh
      // `replacementRequired` event to bring this back — so clearing the
      // flag here on any other status would hide a decision that is still
      // open and unrecoverable without a full re-trigger.
      if (result.status == SyncPassStatus.completed) {
        _replacementPending = false;
      }
      return result;
    } finally {
      _inFlight--;
      _notify();
    }
  }

  /// Cancels replacement. Issues no network call and leaves the decision
  /// available for a later manual sync (spec §6.14 item 6).
  void declineReplacement() {
    _coordinator()?.declineReplacement();
    _replacementPending = false;
    _notify();
  }

  /// Persists a sync ID chosen by the create-or-connect pairing flow, after
  /// the caller has already validated it against the store (spec §6.2,
  /// §6.14 item 5), and asks the app to build the coordinator.
  ///
  /// Also runs the resulting fresh-attach pass to completion (subject to the
  /// usual §6.12 gating) so [lastResult] carries the real W8 duplicate count
  /// by the time this returns — `reconfigure` alone only awaits the
  /// coordinator's construction, not the app-start pass it schedules
  /// unawaited, which would otherwise leave the caller reading a stale or
  /// empty result.
  Future<void> completePairing(String syncId) async {
    _expectSelfWrite();
    await _settings.set(kSyncIdKey, syncId);
    _paired = true;
    _notify();
    await _reconfigure();
    await trigger(SyncTrigger.appStart);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    unawaited(_replacementSubscription?.cancel());
    wifiSettingRequests.dispose();
    super.dispose();
  }
}
