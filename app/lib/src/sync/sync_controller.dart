import 'dart:async';
import 'dart:convert';

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

/// The subset of [SyncHttpClient] the device-management surface needs: the two
/// server-side removals ADR-004 relies on, plus the store read that carries the
/// peer set.
///
/// Deliberately *not* folded into [SyncCoordinatorTransport]: these are owner
/// actions taken from Settings, not steps of a pass, and putting them on the
/// pass seam would oblige every coordinator fake to implement operations no
/// pass ever issues. Shaped like [SyncPairingProbe], for the same reason — a
/// test supplies plain closures rather than a whole transport.
class SyncDeviceAdmin {
  const SyncDeviceAdmin({
    required this.getStore,
    required this.deleteManifest,
    required this.deleteStore,
    this.close,
  });

  /// `GET /v1/store`, read for its `devices` list (spec §5, `devices`).
  final Future<SyncStoreResult> Function({required bool previouslyUsed})
  getStore;

  /// `DELETE /v1/manifests/{deviceId}` — removes one peer (spec §3.3).
  final Future<SyncHttpResponse> Function(String deviceId) deleteManifest;

  /// `DELETE /v1/store` — wipe (spec glossary *wipe*, §5.3).
  final Future<SyncHttpResponse> Function() deleteStore;

  final void Function()? close;
}

/// Builds the device-management client for the store this device is attached
/// to. Defaults to a live [SyncHttpClient]; tests inject a fake.
typedef SyncDeviceAdminFactory =
    SyncDeviceAdmin Function(String syncId, Uri endpoint);

/// What one device-management action did.
enum SyncAdminOutcome {
  /// The server accepted it and any local consequence has been applied.
  done,

  /// This device is not attached to a store, so there was nothing to act on.
  /// Nothing was requested.
  notPaired,

  /// The store itself is gone. For a removal this means the peer's manifest
  /// went with it; for a listing there is nothing to list.
  storeMissing,

  /// Refused before any request: a removal naming this device's own id.
  refused,

  /// The request was made and did not succeed. Nothing local was changed.
  failed,
}

/// The other devices attached to this store, or why they could not be listed.
class SyncDeviceListResult {
  const SyncDeviceListResult({required this.outcome, this.devices = const []});

  final SyncAdminOutcome outcome;

  /// The store's device ids **excluding this device's own** (spec
  /// §5: "A client MUST exclude its own id"). Empty unless [outcome] is
  /// [SyncAdminOutcome.done] — and legitimately empty then, when this is the
  /// only device that has published.
  final List<String> devices;
}

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
    this._deviceAdminFactory,
    this._classifier = const ConnectivityPlusNetworkClassifier(),
    DateTime Function()? now,
    this._debounce = kSyncChangeDebounce,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final SettingsRepository _settings;
  final SyncCoordinator? Function() _coordinator;

  /// Rebuilds the coordinator for the current settings.
  ///
  /// [startPass] is what the app does *after* installing it: normally it kicks
  /// off an app-start pass without awaiting it, which is right for an ordinary
  /// reconfiguration and wrong for pairing. [completePairing] has to observe
  /// exactly one pass to report it, and a pass it did not start is one it
  /// cannot observe — the coordinator queues a concurrent trigger rather than
  /// joining it (`sync_coordinator.dart`, `_queued`), so leaving the automatic
  /// one in place ran two full passes back to back and handed the caller the
  /// second one's outcome to describe the first one with.
  final Future<void> Function({bool startPass}) _reconfigure;
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
  final SyncDeviceAdminFactory? _deviceAdminFactory;

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

  /// Builds a device-management client for the store this device is attached
  /// to, or null when it is not attached. The caller owns [SyncDeviceAdmin.close].
  SyncDeviceAdmin? _deviceAdmin() {
    final syncId = _syncId;
    final endpoint = _endpoint;
    if (syncId == null || endpoint == null) return null;
    final factory = _deviceAdminFactory;
    if (factory != null) return factory(syncId, endpoint);
    final client = SyncHttpClient(endpoint: endpoint, syncId: syncId);
    return SyncDeviceAdmin(
      getStore: client.getStore,
      deleteManifest: client.deleteManifest,
      deleteStore: client.deleteStore,
      close: client.close,
    );
  }

  bool _enabled = false;
  String? _syncId;
  Uri? _endpoint;
  bool _wifiOnly = true;
  bool _excludeImports = false;
  DateTime? _lastSuccessAt;
  SyncPassResult? _lastResult;
  int _mergedDuplicates = 0;
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
  bool get paired => _syncId != null;

  /// The normalized sync ID this device is attached to, or null when it is not
  /// paired. Held so the status surface can show the user the phrase they are
  /// connected with: it is unrecoverable if lost (spec §6.14 item 2), and this
  /// device is the only place it exists. Single source of truth for [paired],
  /// so the two cannot drift.
  String? get syncId => _syncId;

  /// The server chosen at pairing, or null when this device is not paired.
  Uri? get endpoint => _endpoint;
  bool get wifiOnly => _wifiOnly;
  bool get excludeImports => _excludeImports;
  DateTime? get lastSuccessAt => _lastSuccessAt;
  SyncPassResult? get lastResult => _lastResult;

  /// How many duplicate dances the latest fresh attach merged, or 0 when none
  /// has merged any **in this app session**.
  ///
  /// Session-scoped, not attachment-scoped: the latch is in memory, so a
  /// restart loses the count while the device stays attached to the store it
  /// belongs to. User-facing copy must say so rather than promise the count
  /// lasts as long as the connection does.
  ///
  /// ADR-004 names this count as *the* mitigation for silent merge — the merge
  /// itself is irreversible from the user's point of view, and reporting a
  /// count afterwards is the whole remedy — so it cannot be tied to the one
  /// surface that happened to be first. A fresh attach also happens after a
  /// confirmed replacement and on a stale-epoch auto-join, neither of which has
  /// a dialog to put it in, and a pairing pass the §6.12 gate deferred merges
  /// later on a silent automatic pass. Hence a latch on the controller rather
  /// than a read of [lastResult]: it outlives the pass that produced it and is
  /// reachable from the status surface, which is the only place all three
  /// paths share.
  ///
  /// Reading it from any result is safe because only a fresh attach can ever
  /// carry a non-zero count: an ordinary pass calls
  /// `refreshDanceAmbiguityReviews`, which hard-codes `duplicateCount: 0`
  /// (`sync_storage.dart`), so a steady-state pass cannot overwrite this and a
  /// zero can never be mistaken for "a fresh attach found nothing".
  ///
  /// That last point is also its one limitation, stated rather than hidden: a
  /// *later* fresh attach that merges nothing cannot announce itself, so a
  /// stale-epoch auto-join merging zero leaves an earlier count standing until
  /// the device detaches or the app restarts. Resolving it would mean carrying
  /// a fresh-attach flag across the isolate boundary on [SyncPassResult]; the
  /// residue is a stale number on an informational tile, which does not earn
  /// that. The two attaches the user initiates — pairing and a confirmed
  /// replacement — do reset it, because they have an entry point to reset it
  /// from.
  ///
  /// In memory only, and deliberately not persisted, exactly as [notices] is:
  /// it reports something that happened in this session.
  int get mergedDuplicates => _mergedDuplicates;

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
  /// A **completed** pass replaces the set, because it re-examined
  /// everything; a pass that ended any other way merges into it, because it
  /// stopped part-way and its reports are a subset rather than a survey. The
  /// one exception to replacement is [_isSessionSuppressed], for conditions
  /// the engine reports only once per session.
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
    if (!_enabled || !paired || last == null) return false;
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
    final normalized = id is String ? normalizeSyncId(id) : '';
    _syncId = normalized.isEmpty ? null : normalized;
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

    final suppressed = await _connectionGate(
      manual: trigger == SyncTrigger.manual,
    );
    if (suppressed != null) return suppressed;

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

  /// The §6.12 connection gate, shared by [trigger] and [confirmReplacement].
  ///
  /// Returns the outcome that suppressed the attempt, or null when the
  /// connection permits it. [manual] marks an attempt the user just made, which
  /// is routed to the *Sync only on WiFi* setting rather than dropped silently.
  ///
  /// Every caller MUST consult this **before** taking [_inFlight] and notifying:
  /// a suppressed attempt must leave the controller bit-identical, and the
  /// replacement dialog re-shows itself on any notification while the decision
  /// is pending — so a gate that notified first would cover the very setting it
  /// is routing the user to.
  Future<SyncGateOutcome?> _connectionGate({required bool manual}) async {
    final network = await _classifier.current();
    if (network == SyncNetworkKind.offline) {
      return SyncGateOutcome.suppressedOffline;
    }
    if (_wifiOnly && network == SyncNetworkKind.metered) {
      if (manual) wifiSettingRequests.value++;
      return SyncGateOutcome.suppressedMetered;
    }
    return null;
  }

  /// Records a pass result and, on success, persists the last-success time as
  /// the controller's own bookkeeping write (spec §6.14 item 4's clock).
  Future<void> _recordResult(SyncPassResult result) async {
    // A pass that finishes while this device is detaching belongs to the
    // store being forgotten; recording it would restore its last-success time.
    if (_detaching) return;
    _lastResult = result;
    // Latched rather than replaced: see [mergedDuplicates]. A pass that merged
    // nothing says nothing about an earlier attach's count, because every
    // ordinary pass reports zero.
    if (result.duplicateCount > 0) _mergedDuplicates = result.duplicateCount;
    if (result.status == SyncPassStatus.completed) {
      // A completed pass re-examined everything, so what it raises replaces
      // what stood — with one carve-out. A rejected peer record's wire hash
      // enters `SyncPeerManifestCache.rejectedHashes` on the pass that reports
      // it and is skipped on every later pass of the same session, so a silent
      // completed pass is not evidence that record is gone. Those notices are
      // carried forward: they live exactly as long as the suppression that
      // hides them, and both end when the sync session does.
      _notices = _coalesce([
        ...result.reports,
        ..._notices.where(_isSessionSuppressed),
      ]);
    } else if (result.reports.isNotEmpty) {
      // A pass that did not complete stopped part-way, so its reports are
      // whatever had accumulated by then — a subset, never a survey. Merging
      // keeps what it did find without retracting what it never re-checked;
      // replacing here would let a partial failure silently drop a standing
      // divergence, which is the same silence this surface exists to end.
      _notices = _coalesce([..._notices, ...result.reports]);
    }
    if (result.status == SyncPassStatus.completed) {
      final at = _now();
      _lastSuccessAt = at;
      _expectSelfWrite();
      await _settings.set(kSyncLastSuccessAtKey, at.toIso8601String());
    }
  }

  /// Deduplicates by [SyncReport.coalescingKey], keeping the first of each.
  ///
  /// Done here rather than trusted from the engine: `SyncReportSink`
  /// deduplicates within one sink, but a fresh attach that continues into a
  /// steady-state pass concatenates two sinks' output verbatim, so one result
  /// can carry the same condition twice.
  static List<SyncReport> _coalesce(Iterable<SyncReport> reports) {
    final byKey = <String, SyncReport>{};
    for (final report in reports) {
      byKey.putIfAbsent(report.coalescingKey, () => report);
    }
    return List.unmodifiable(byKey.values);
  }

  /// Whether the engine reports this condition only once per sync session, so
  /// a later silent pass says nothing about whether it still holds.
  ///
  /// Exactly one report is suppressed this way: a quarantined record received
  /// from a peer, gated on `SyncPeerManifestCache.rejectedHashes` in
  /// `sync_coordinator.dart`. `sync_coordinator_test.dart` pins that behaviour
  /// — the same still-present record reports on the first pass of a session
  /// and not the second. The local quarantine sweep shares the code but not
  /// the suppression: it has no `peerId` and is recomputed every pass.
  static bool _isSessionSuppressed(SyncReport report) =>
      report.code == SyncReportCode.quarantinedRecord && report.peerId != null;

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
  ///
  /// A confirmation is a manual sync attempt — it fresh-attaches, which is the
  /// largest transfer sync ever makes — so it passes the same §6.12 connection
  /// gate as every other trigger, and reports its outcome the same way. A
  /// suppressed confirmation sends nothing and leaves [replacementPending]
  /// true, so the decision is still there to make on a permitted connection.
  /// Read [lastResult] for what the pass itself did when this returns
  /// [SyncGateOutcome.ran].
  Future<SyncGateOutcome> confirmReplacement() async {
    final coordinator = _coordinator();
    if (coordinator == null) return SyncGateOutcome.notPaired;

    final suppressed = await _connectionGate(manual: true);
    if (suppressed != null) return suppressed;

    // The replacement is itself a fresh attach against a *new* store, so any
    // count standing from the old one is about records that no longer exist
    // there. Cleared only once the gate has let the attempt through: a
    // suppressed confirmation sends nothing, and must leave the controller
    // bit-identical.
    _mergedDuplicates = 0;
    _inFlight++;
    _notify();
    try {
      SyncPassResult result;
      try {
        result = await coordinator.confirmReplacement();
      } on Object catch (error, stack) {
        // The dialog fires this without awaiting it, so an uncaught error here
        // would become an unhandled async error — logged as a crash, with no
        // status the user ever sees — and `finally`'s `_notify` would re-show
        // the dialog with nothing saying the attempt failed. Recording it as a
        // failed pass is what `trigger` does, and for the same reason.
        //
        // Type only, as `trigger` and the coordinator's own `_watch` do: a
        // transport failure's message can carry the request URI, and the
        // diagnostics redactor deliberately keeps HTTPS URLs, so the message
        // would put the sync endpoint into an exported diagnostic bundle.
        logCaughtErrorTypeOnly(
          error,
          stack,
          source: 'sync_controller.confirmReplacement',
        );
        result = SyncPassResult(
          SyncPassStatus.failed,
          message:
              'replacement confirmation threw ${error.runtimeType}', // i18n-ignore: internal status
        );
      }
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
      return SyncGateOutcome.ran;
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
  /// usual §6.12 gating) so [lastResult] and [mergedDuplicates] carry the real
  /// W8 duplicate count by the time this returns — `reconfigure` alone only
  /// awaits the coordinator's construction, not the app-start pass it
  /// schedules unawaited, which would otherwise leave the caller reading a
  /// stale or empty result.
  ///
  /// **Returns what the §6.12 gate did with that pass**, which the pairing
  /// surface needs and must not infer. Because this awaits the pass, it has
  /// already finished, failed, or never started by the time the caller reports
  /// success, so copy claiming a sync is in progress is false in every case;
  /// and a [SyncGateOutcome.suppressedMetered] or
  /// [SyncGateOutcome.suppressedOffline] pass ran nothing at all, which
  /// [lastResult] alone cannot distinguish from an earlier pass's result.
  Future<SyncGateOutcome> completePairing(String syncId, Uri endpoint) async {
    _expectSelfWrite();
    await _settings.set(kSyncEndpointKey, endpoint.toString());
    _expectSelfWrite();
    await _settings.set(kSyncIdKey, syncId);
    _endpoint = endpoint;
    _syncId = normalizeSyncId(syncId);
    // A count belonging to a store this device is leaving must not be reported
    // as this attach's. Cleared before the pass, not after it, so the pass that
    // follows is the only thing that can set it.
    _mergedDuplicates = 0;
    _notify();
    // The automatic app-start pass is suppressed so this method owns the only
    // one. Without that there are two: the app fires an unawaited pass the
    // moment it installs the coordinator, and the coordinator *queues* a
    // trigger that arrives while one is in flight instead of joining it — so
    // the call below ran a second full pass immediately after the largest
    // transfer sync ever makes, and returned its outcome, which the completion
    // dialog then presented as the first pass's.
    await _reconfigure(startPass: false);
    return trigger(SyncTrigger.appStart);
  }

  /// Stops syncing on this device: forgets the sync ID, the server it was
  /// paired with and the store-scoped local state (spec glossary *detach*,
  /// §6.2 step 3). Purely local — no request is sent, so the store, this
  /// device's manifest and every peer are untouched. Leaves sync enabled, the
  /// device ID, the used-identity verifiers, publication history and
  /// normalisation skips in place, as the spec requires; the next pairing is a
  /// fresh attach. Contrast [wipeStore], which destroys the store for every
  /// device; the local half of the two is shared ([_clearAttachment]) and the
  /// difference is entirely in what is sent.
  Future<void> detach() async {
    if (!paired || _detaching) return;
    _detaching = true;
    _debounceTimer?.cancel();
    _dirty = false;
    try {
      await _runExclusive(_clearAttachment);
    } finally {
      _detaching = false;
    }
    _forgetAttachment();
  }

  /// Erases everything that ties this device to its store, in one transaction
  /// so a failure leaves the device fully attached.
  ///
  /// Shared by [detach] and [wipeStore]: the local half of forgetting a store
  /// is identical whether the store still exists or has just been destroyed.
  /// The sync ID is erased rather than tombstoned, since a tombstone keeps the
  /// phrase on disk.
  Future<void> _clearAttachment() => _syncLocal.transaction((tx) async {
    await tx.clearOnDetach();
    await _settings.remove(kSyncIdKey, permanent: true);
    await _settings.remove(kSyncEndpointKey, permanent: true);
    await _settings.remove(kSyncLastSuccessAtKey, permanent: true);
  });

  /// Drops the in-memory state belonging to the store just forgotten.
  ///
  /// Called only after [_clearAttachment] has committed: while the clear is
  /// still pending the device is still attached, and reporting otherwise would
  /// offer *Connect* — a pairing completing in that window would have the sync
  /// ID it just wrote deleted by the clear.
  void _forgetAttachment() {
    _syncId = null;
    _endpoint = null;
    _lastSuccessAt = null;
    _lastResult = null;
    _mergedDuplicates = 0;
    _notices = const [];
    _replacementPending = false;
    _notify();
  }

  /// This device's own protocol identifier, or null when none has been minted.
  ///
  /// Minted lazily by `ConfiguredSyncCoordinatorFactory` the first time a
  /// coordinator is built, and deliberately left in place by [detach]. A null
  /// here means this device has never published a manifest, so its id cannot
  /// appear in the store's `devices` either — which is why the exclusion below
  /// is still correct when it excludes nothing.
  Future<String?> _selfDeviceId() async {
    final raw = await _settings.get(kSyncDeviceIdKey);
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// The other devices attached to this store (spec §3.3, §5).
  ///
  /// A read, so it does **not** take the writer boundary: a pass running
  /// concurrently changes nothing this fetch decides, and the list is re-read
  /// on every visit rather than cached, so a removal made elsewhere shows up.
  Future<SyncDeviceListResult> listStoreDevices() async {
    final admin = _deviceAdmin();
    if (admin == null) {
      return const SyncDeviceListResult(outcome: SyncAdminOutcome.notPaired);
    }
    try {
      final response = (await admin.getStore(previouslyUsed: true)).response;
      if (response.kind == SyncResponseKind.notFound) {
        return const SyncDeviceListResult(
          outcome: SyncAdminOutcome.storeMissing,
        );
      }
      if (!response.isSuccess) {
        return const SyncDeviceListResult(outcome: SyncAdminOutcome.failed);
      }
      final devices = _decodeDeviceIds(response.body);
      if (devices == null) {
        return const SyncDeviceListResult(outcome: SyncAdminOutcome.failed);
      }
      final self = await _selfDeviceId();
      return SyncDeviceListResult(
        outcome: SyncAdminOutcome.done,
        devices: List.unmodifiable(devices.where((id) => id != self)),
      );
    } on Object catch (error, stack) {
      // Type only, as `trigger` does: a transport failure's message can carry
      // the request URI, and the diagnostics redactor keeps HTTPS URLs, so the
      // message would put the sync endpoint into an exported bundle.
      logCaughtErrorTypeOnly(
        error,
        stack,
        source: 'sync_controller.listStoreDevices',
      );
      return const SyncDeviceListResult(outcome: SyncAdminOutcome.failed);
    } finally {
      admin.close?.call();
    }
  }

  /// Removes one peer's manifest from the store (spec §3.3), freeing its device
  /// slot and letting the aliases only it listed retire on the next pass.
  ///
  /// Runs inside the writer boundary, and that is load-bearing rather than
  /// tidy: a pass in step 3 fetches every peer manifest in `devices`, and a
  /// `DELETE` landing mid-pass makes that fetch answer `404`, which the
  /// coordinator reports to the user as a malformed peer manifest. Gating the
  /// control on [running] does not close this — [running] tracks this
  /// controller's own in-flight count, while the boundary disposes the
  /// coordinator and awaits whatever pass the isolate is actually running.
  ///
  /// Not gated on the §6.12 connection policy: this is a single small request
  /// the user just asked for, not a pass, and deferring it to WiFi would leave
  /// a device the user is trying to retire in the store.
  Future<SyncAdminOutcome> removeDevice(String deviceId) async {
    if (deviceId.isEmpty) return SyncAdminOutcome.refused;
    // Belt and braces behind the list's own exclusion: removing this device's
    // manifest is a different action with a different meaning (it does not
    // detach, and the next pass would republish it), so it is refused here
    // rather than quietly done.
    if (deviceId == await _selfDeviceId()) return SyncAdminOutcome.refused;
    final admin = _deviceAdmin();
    if (admin == null) return SyncAdminOutcome.notPaired;
    var outcome = SyncAdminOutcome.failed;
    try {
      await _runExclusive(() async {
        final response = await admin.deleteManifest(deviceId);
        outcome = switch (response.kind) {
          // The server answers 204 whether or not the manifest was there, so a
          // repeat of a removal that already happened is a success, not an
          // error the user should be asked to retry.
          SyncResponseKind.success => SyncAdminOutcome.done,
          // A 404 on this route means the *store* is gone, not the manifest.
          SyncResponseKind.notFound => SyncAdminOutcome.storeMissing,
          _ => SyncAdminOutcome.failed,
        };
      });
    } on Object catch (error, stack) {
      logCaughtErrorTypeOnly(
        error,
        stack,
        source: 'sync_controller.removeDevice',
      );
      return SyncAdminOutcome.failed;
    } finally {
      admin.close?.call();
    }
    return outcome;
  }

  /// Destroys the whole store server-side and detaches this device (spec
  /// glossary *wipe*, §5.3, §7.3). Not reversible, and it affects every device
  /// at once.
  ///
  /// The local clear is part of the contract, not a convenience: wipe's
  /// headline purpose is the remedy for a leaked sync phrase, and a device left
  /// attached would find the store missing on its very next pass and be offered
  /// the §6.3 replacement dialog — that is, offered to re-create the store under
  /// the phrase that leaked. Peers still follow the §6.3 missing-store flow,
  /// which is the intended behaviour for them.
  ///
  /// A failed wipe changes nothing locally: the device stays attached, so the
  /// user can try again. Between the successful `DELETE` and the local clear
  /// there is no atomicity — a crash there leaves the store gone and this
  /// device attached, which the next pass resolves into the ordinary
  /// missing-store flow.
  ///
  /// Like [removeDevice], not gated on the §6.12 connection policy: a wipe
  /// prompted by a leaked phrase must not wait for WiFi. It is deliberately
  /// offered beside *Disconnect this device* rather than from any quota or
  /// error surface — spec §5.3 requires that a destructive wipe never be the
  /// first thing offered in response to a `507`.
  Future<SyncAdminOutcome> wipeStore() async {
    if (!paired || _detaching) return SyncAdminOutcome.notPaired;
    final admin = _deviceAdmin();
    if (admin == null) return SyncAdminOutcome.notPaired;
    // Held for the same reason [detach] holds it: a pass that finishes while
    // this runs belongs to the store being destroyed, and recording it would
    // restore a last-success time for a store that no longer exists.
    _detaching = true;
    _debounceTimer?.cancel();
    _dirty = false;
    var wiped = false;
    try {
      await _runExclusive(() async {
        final response = await admin.deleteStore();
        // A store that is already gone is the end state the user asked for,
        // so it detaches too rather than reporting a failure they cannot act
        // on. This is the first production consumer of `notFound`.
        wiped =
            response.kind == SyncResponseKind.success ||
            response.kind == SyncResponseKind.notFound;
        if (!wiped) return;
        await _clearAttachment();
      });
    } on Object catch (error, stack) {
      logCaughtErrorTypeOnly(error, stack, source: 'sync_controller.wipeStore');
      return SyncAdminOutcome.failed;
    } finally {
      _detaching = false;
      admin.close?.call();
    }
    if (!wiped) return SyncAdminOutcome.failed;
    _forgetAttachment();
    return SyncAdminOutcome.done;
  }

  /// The `devices` array from a `GET /v1/store` body, or null when the body is
  /// not the documented shape. Validated exactly as the coordinator validates
  /// the same field, so a malformed store answer cannot reach the surface as a
  /// list of anything.
  static List<String>? _decodeDeviceIds(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
      if (decoded is! Map) return null;
      final devices = decoded['devices'];
      if (devices is! List || devices.any((device) => device is! String)) {
        return null;
      }
      return [for (final device in devices) device as String];
    } on FormatException {
      // diagnostics: silent — a malformed store answer is surfaced to the user
      // as a failed listing, which is the only thing they can act on.
      return null;
    }
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
