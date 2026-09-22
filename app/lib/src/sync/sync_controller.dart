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

/// Builds the probe for one candidate sync ID against the endpoint chosen in
/// the pairing form. Defaults to a live [SyncHttpClient]; tests inject a fake.
typedef SyncPairingProbeFactory =
    SyncPairingProbe Function(String syncId, Uri endpoint);

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
    required this._syncLocal,
    this._runExclusive = _runDirectly,
    this._pairingProbeFactory,
    this._classifier = const ConnectivityPlusNetworkClassifier(),
    DateTime Function()? now,
    this._debounce = kSyncChangeDebounce,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final SettingsRepository _settings;
  final SyncCoordinator? Function() _coordinator;
  final Future<void> Function() _reconfigure;
  final SyncLocalRepository _syncLocal;

  /// Runs a write that no sync pass may overlap: the app's writer boundary,
  /// which disposes the coordinator (awaiting any pass in flight) first and
  /// reconfigures afterwards.
  final Future<void> Function(Future<void> Function() operation) _runExclusive;

  static Future<void> _runDirectly(Future<void> Function() operation) =>
      operation();
  final SyncNetworkClassifier _classifier;
  final DateTime Function() _now;
  final Duration _debounce;
  final SyncPairingProbeFactory? _pairingProbeFactory;

  /// Builds the probe for a pairing attempt. [endpoint] must already have
  /// passed [validateSyncEndpoint] and [syncId] must be a well-formed ID.
  SyncPairingProbe probeFor(String syncId, Uri endpoint) {
    final factory = _pairingProbeFactory;
    if (factory != null) return factory(syncId, endpoint);
    final client = SyncHttpClient(endpoint: endpoint, syncId: syncId);
    return SyncPairingProbe(
      getStore: client.getStore,
      createStore: client.createStore,
      close: client.close,
    );
  }

  bool _enabled = false;
  bool _paired = false;
  Uri? _endpoint;
  bool _wifiOnly = true;
  bool _excludeImports = false;
  DateTime? _lastSuccessAt;
  SyncPassResult? _lastResult;
  List<SyncReport> _notices = const [];
  int _inFlight = 0;
  bool _dirty = false;
  int _pendingSelfWrites = 0;
  int _pendingSyncAppliedInvalidations = 0;
  bool _replacementPending = false;
  bool _detaching = false;
  Timer? _debounceTimer;
  StreamSubscription<SyncReplacementRequiredEvent>? _replacementSubscription;
  bool _disposed = false;

  /// Bumped when a manual attempt on a metered connection is routed to the
  /// *Sync only on WiFi* setting; the settings section listens and surfaces it.
  final ValueNotifier<int> wifiSettingRequests = ValueNotifier<int>(0);

  bool get enabled => _enabled;
  bool get paired => _paired;

  /// The server chosen at pairing, or null when this device is not paired.
  Uri? get endpoint => _endpoint;
  bool get wifiOnly => _wifiOnly;
  bool get excludeImports => _excludeImports;
  DateTime? get lastSuccessAt => _lastSuccessAt;
  SyncPassResult? get lastResult => _lastResult;

  /// The conditions the most recent pass to raise any had to report, as the
  /// status surface shows them (spec §2 *report*).
  ///
  /// These outlive the pass that raised them, which is what separates a
  /// report from a pass status: an equal-`updatedAt` divergence is re-raised
  /// on every later pass until a human edits one side (spec §6.3, and the
  /// spec's "MUST be reported on that pass and on every subsequent pass"),
  /// so a list that emptied at the end of each pass would show it only for
  /// the instant between two triggers.
  ///
  /// In memory only, and not persisted: this is the same lifetime
  /// [lastResult] already has, and no clause requires a notice to survive a
  /// restart — the conditions that persist are re-raised by the app-start
  /// pass. Persisting them would mean a new stored field carrying record and
  /// peer identifiers, which is a privacy-registry question rather than a
  /// status-surface one.
  List<SyncReport> get notices => _notices;

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

  /// Marks that a table invalidation the controller is about to observe is
  /// the direct result of applying inbound records during the pass currently
  /// running — the isolate boundary's `onAppliedKinds` hook, wired through
  /// `main.dart` — not a local edit.
  ///
  /// The invalidation reaches the main connection's live queries (and hence
  /// this controller's [notifyLocalChange]) before the pass's own
  /// `coordinator.trigger()` call returns, so without this the controller
  /// sees `_inFlight > 0` and schedules a pointless follow-up pass after
  /// every pass that applied anything. Unlike [_expectSelfWrite], this is not
  /// scoped to settings-only writes: applying an inbound record can touch any
  /// table. A genuine local edit landing in the same window still calls
  /// [notifyLocalChange] on its own and is unaffected — each call here
  /// consumes exactly one matching notification, so it cannot swallow an
  /// edit it wasn't meant for.
  void expectSyncAppliedInvalidation() {
    if (_disposed) return;
    _pendingSyncAppliedInvalidations++;
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
    final endpoint = await _settings.get(kSyncEndpointKey);
    _endpoint = endpoint is String ? tryParseSyncEndpoint(endpoint) : null;
    final last = await _settings.get(kSyncLastSuccessAtKey);
    _lastSuccessAt = last is String ? DateTime.tryParse(last)?.toUtc() : null;
    _notify();
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    // Both pending counters are reset on every transition so nothing can
    // carry across an enable/disable cycle: an expectation armed in one
    // session must not swallow the first genuine edit of the next.
    // `notifyLocalChange` does consume a pending expectation while disabled
    // (so the disable's own settings write is accounted for if its event
    // arrives), but an event that never arrives — a coordinator torn down
    // mid-pass — would otherwise leave the counter armed indefinitely.
    _pendingSelfWrites = 0;
    _pendingSyncAppliedInvalidations = 0;
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
    if (_disposed) return;
    // Consumed before the disabled check below: the matching
    // `expectSyncAppliedInvalidation()`/`_expectSelfWrite()` call already
    // happened (possibly while still enabled, or as part of the very
    // `setEnabled` call that disabled this controller), so the invalidation
    // it is paired with must be accounted for regardless of the *current*
    // `_enabled` value. Otherwise a disable landing between the hook firing
    // and its table event reaching here strands the counter, and it wrongly
    // swallows the first genuine edit once sync is re-enabled.
    if (settingsOnly && _pendingSelfWrites > 0) {
      _pendingSelfWrites--;
      return;
    }
    if (_pendingSyncAppliedInvalidations > 0) {
      _pendingSyncAppliedInvalidations--;
      return;
    }
    if (!_enabled) return;
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
    // A pass that finishes while this device is detaching belongs to the
    // store being forgotten; recording it would restore its last-success time.
    if (_detaching) return;
    _lastResult = result;
    if (result.reports.isNotEmpty) {
      // Coalesced here rather than trusted from the engine: `SyncReportSink`
      // deduplicates within one sink, but a fresh attach that continues into
      // a steady-state pass concatenates two sinks' output verbatim, so one
      // result can carry the same condition twice.
      final byKey = <String, SyncReport>{};
      for (final report in result.reports) {
        byKey.putIfAbsent(report.coalescingKey, () => report);
      }
      _notices = List.unmodifiable(byKey.values);
    } else if (result.status == SyncPassStatus.completed) {
      // Only a pass that ran to completion is evidence that a condition is
      // gone. A `failed`, `paused` or `replacementRequired` result never
      // reached the merge, so clearing on it would retract a standing
      // divergence for an unrelated network failure — the same silence this
      // whole surface exists to end.
      _notices = const [];
    }
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

  /// Persists a sync ID and endpoint chosen by the create-or-connect pairing
  /// flow, after the caller has already validated them against the store
  /// (spec §6.2, §6.14 item 5), and asks the app to build the coordinator.
  ///
  /// Each settings write is its own transaction and so its own table-update
  /// event, which is why each is preceded by its own [_expectSelfWrite].
  ///
  /// Also runs the resulting fresh-attach pass to completion (subject to the
  /// usual §6.12 gating) so [lastResult] carries the real W8 duplicate count
  /// by the time this returns — `reconfigure` alone only awaits the
  /// coordinator's construction, not the app-start pass it schedules
  /// unawaited, which would otherwise leave the caller reading a stale or
  /// empty result.
  Future<void> completePairing(String syncId, Uri endpoint) async {
    _expectSelfWrite();
    await _settings.set(kSyncEndpointKey, endpoint.toString());
    _expectSelfWrite();
    await _settings.set(kSyncIdKey, syncId);
    _endpoint = endpoint;
    _paired = true;
    _notify();
    await _reconfigure();
    await trigger(SyncTrigger.appStart);
  }

  /// Stops syncing on this device: forgets the sync ID, the server it was
  /// paired with and the store-scoped local state (spec glossary *detach*,
  /// §6.2 step 3). Purely local — no request is sent, so the store, this
  /// device's manifest and every peer are untouched. Leaves sync enabled, the
  /// device ID, the used-identity verifiers, publication history and
  /// normalisation skips in place, as the spec requires; the next pairing is a
  /// fresh attach.
  ///
  /// The sync ID is erased rather than tombstoned, since a tombstone keeps
  /// the credential on disk, and it goes in the same transaction as the
  /// store-scoped state so a failure leaves the device fully attached.
  Future<void> detach() async {
    if (!_paired || _detaching) return;
    _detaching = true;
    _debounceTimer?.cancel();
    _dirty = false;
    try {
      await _runExclusive(
        () => _syncLocal.transaction((tx) async {
          await tx.clearOnDetach();
          await _settings.remove(kSyncIdKey, permanent: true);
          await _settings.remove(kSyncEndpointKey, permanent: true);
          await _settings.remove(kSyncLastSuccessAtKey, permanent: true);
        }),
      );
    } finally {
      _detaching = false;
    }
    // Only now: while the clear is still pending the device is still attached,
    // and reporting otherwise would offer *Connect* — a pairing completing in
    // that window would have the sync ID it just wrote deleted by this clear.
    _paired = false;
    _endpoint = null;
    _lastSuccessAt = null;
    _lastResult = null;
    _notices = const [];
    _replacementPending = false;
    _notify();
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
