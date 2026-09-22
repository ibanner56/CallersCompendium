import 'dart:async';

import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/controllable_sync_transport.dart';
import '../support/noop_sync_transport.dart';
import '../support/test_repositories.dart';

final class _FixedNetwork implements SyncNetworkClassifier {
  _FixedNetwork(this.kind);
  SyncNetworkKind kind;
  @override
  Future<SyncNetworkKind> current() async => kind;
}

/// A coordinator whose pass operation counts calls and never reaches a network.
SyncCoordinator _coordinator(
  CompendiumRepositories repos,
  List<int> passes, {
  SyncPassStatus status = SyncPassStatus.completed,
}) => SyncCoordinator(
  syncId: 'configured',
  deviceId: 'device',
  store: CompendiumSyncCoordinatorStore(repos),
  transport: NoopSyncCoordinatorTransport(),
  passOperation: ({initialStore}) async {
    passes.add(1);
    return SyncPassResult(status);
  },
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CompendiumRepositories repos;
  late List<int> passes;
  late _FixedNetwork network;
  late DateTime clock;
  SyncCoordinator? coordinator;

  SyncController build({Duration debounce = const Duration(seconds: 30)}) {
    final controller = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => coordinator,
      reconfigure: () async {},
      classifier: network,
      now: () => clock,
      debounce: debounce,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    repos = openTestRepositories();
    passes = [];
    network = _FixedNetwork(SyncNetworkKind.unmetered);
    clock = DateTime.utc(2026, 9, 21, 12);
    coordinator = _coordinator(repos, passes);
  });

  group('defaults and enablement', () {
    test('sync is off and WiFi-only is on by default', () async {
      final controller = build();
      await controller.load();
      expect(controller.enabled, isFalse);
      expect(controller.wifiOnly, isTrue);
      expect(controller.excludeImports, isFalse);
    });

    test('while disabled no trigger reaches the coordinator', () async {
      final controller = build();
      await controller.load();
      for (final trigger in SyncTrigger.values) {
        expect(await controller.trigger(trigger), SyncGateOutcome.disabled);
      }
      expect(passes, isEmpty);
    });

    test('enabled but unpaired makes no request', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      coordinator = null;
      expect(await controller.onAppStart(), SyncGateOutcome.notPaired);
      expect(passes, isEmpty);
    });

    test('enabling persists consent and asks for reconfiguration', () async {
      var reconfigured = 0;
      final controller = SyncController(
        settings: repos.settings,
        syncLocal: repos.syncLocal,
        coordinator: () => null,
        reconfigure: () async => reconfigured++,
        classifier: network,
      );
      addTearDown(controller.dispose);
      await controller.setEnabled(true);
      expect(await repos.settings.get(kSyncEnabledKey), isTrue);
      await controller.setEnabled(false);
      expect(await repos.settings.get(kSyncEnabledKey), isFalse);
      expect(reconfigured, 2);
    });
  });

  group('§6.12 triggers', () {
    test('a metered connection suppresses automatic passes', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      network.kind = SyncNetworkKind.metered;

      expect(
        await controller.trigger(SyncTrigger.appStart),
        SyncGateOutcome.suppressedMetered,
      );
      expect(
        await controller.trigger(SyncTrigger.debouncedChange),
        SyncGateOutcome.suppressedMetered,
      );
      expect(passes, isEmpty);
      expect(controller.lastSuccessAt, isNull);
    });

    test('a manual attempt on a metered connection routes to the setting '
        'instead of running or failing', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      network.kind = SyncNetworkKind.metered;
      var routed = 0;
      controller.wifiSettingRequests.addListener(() => routed++);

      expect(await controller.syncNow(), SyncGateOutcome.suppressedMetered);
      expect(routed, 1);
      expect(passes, isEmpty);
    });

    test(
      'a suppressed pass runs at the next trigger without user action',
      () async {
        final controller = build();
        await controller.load();
        await controller.setEnabled(true);
        network.kind = SyncNetworkKind.metered;
        await controller.trigger(SyncTrigger.appStart);
        expect(passes, isEmpty);

        network.kind = SyncNetworkKind.unmetered;
        expect(
          await controller.trigger(SyncTrigger.debouncedChange),
          SyncGateOutcome.ran,
        );
        expect(passes, hasLength(1));
      },
    );

    test(
      'setExcludeImports persists and is off by default (spec §6.1)',
      () async {
        final controller = build();
        await controller.load();
        expect(controller.excludeImports, isFalse);

        await controller.setExcludeImports(true);
        expect(controller.excludeImports, isTrue);
        expect(await repos.settings.get(kSyncExcludeImportsKey), isTrue);

        await controller.setExcludeImports(false);
        expect(controller.excludeImports, isFalse);
        expect(await repos.settings.get(kSyncExcludeImportsKey), isFalse);
      },
    );

    test('turning WiFi-only off lets a metered connection sync', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      await controller.setWifiOnly(false);
      network.kind = SyncNetworkKind.metered;

      expect(await controller.syncNow(), SyncGateOutcome.ran);
      expect(passes, hasLength(1));
      expect(await repos.settings.get(kSyncWifiOnlyKey), isFalse);
    });

    test('offline suppresses a pass and records nothing', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      network.kind = SyncNetworkKind.offline;
      expect(await controller.syncNow(), SyncGateOutcome.suppressedOffline);
      expect(passes, isEmpty);
      expect(controller.lastSuccessAt, isNull);
    });

    test('an unknown connection is not treated as metered', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      network.kind = SyncNetworkKind.unknown;
      expect(await controller.syncNow(), SyncGateOutcome.ran);
    });

    test('a completed pass records the last-success time; a failed one does '
        'not', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      coordinator = _coordinator(repos, passes, status: SyncPassStatus.failed);
      await controller.syncNow();
      expect(controller.lastSuccessAt, isNull);

      coordinator = _coordinator(repos, passes);
      await controller.syncNow();
      expect(controller.lastSuccessAt, clock);
      expect(
        await repos.settings.get(kSyncLastSuccessAtKey),
        clock.toIso8601String(),
      );
    });

    test('a coordinator that throws is recorded as a failed pass, not an '
        'unhandled error', () async {
      coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async =>
            throw StateError('sync isolate crashed'),
      );
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);

      // The await itself must not throw: a debounced pass reaches this
      // through `unawaited(trigger(...))`, so an uncaught error here would
      // become an unhandled async error rather than a status the surface
      // can read.
      expect(await controller.syncNow(), SyncGateOutcome.ran);
      expect(controller.lastResult?.status, SyncPassStatus.failed);
      expect(controller.lastSuccessAt, isNull);
    });

    test(
      'changes inside the debounce window share one automatic pass',
      () async {
        final controller = build(debounce: const Duration(milliseconds: 20));
        await controller.load();
        await controller.setEnabled(true);
        controller
          ..notifyLocalChange()
          ..notifyLocalChange()
          ..notifyLocalChange();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(passes, hasLength(1));
      },
    );

    test('local changes while sync is off schedule nothing', () async {
      final controller = build(debounce: const Duration(milliseconds: 10));
      await controller.load();
      controller.notifyLocalChange();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(passes, isEmpty);
    });
  });

  group('in-flight bookkeeping and change notifications', () {
    test(
      'status stays running until every overlapping trigger has finished',
      () async {
        final gate = Completer<void>();
        coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device',
          store: CompendiumSyncCoordinatorStore(repos),
          transport: NoopSyncCoordinatorTransport(),
          passOperation: ({initialStore}) async {
            passes.add(1);
            await gate.future;
            return const SyncPassResult(SyncPassStatus.completed);
          },
        );
        addTearDown(coordinator!.dispose);
        final controller = build();
        await controller.load();
        await controller.setEnabled(true);

        final first = controller.syncNow();
        await Future<void>.delayed(Duration.zero);
        final second = controller.trigger(SyncTrigger.debouncedChange);
        await Future<void>.delayed(Duration.zero);
        expect(controller.running, isTrue);

        // Release the first pass; the coalesced follow-up is still outstanding
        // for the second trigger, so the surface must not report idle yet.
        gate.complete();
        await first;
        if (passes.length < 2) {
          expect(controller.running, isTrue);
        }
        await second;
        expect(controller.running, isFalse);
      },
    );

    test('an edit during a pass is queued as one follow-up pass', () async {
      final controller = build(debounce: const Duration(milliseconds: 10));
      final gate = Completer<void>();
      coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          passes.add(1);
          if (passes.length == 1) await gate.future;
          return const SyncPassResult(SyncPassStatus.completed);
        },
      );
      addTearDown(coordinator!.dispose);
      await controller.load();
      await controller.setEnabled(true);

      final pass = controller.syncNow();
      await Future<void>.delayed(Duration.zero);
      controller
        ..notifyLocalChange()
        ..notifyLocalChange();
      gate.complete();
      await pass;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(passes, hasLength(2));
    });

    test("a pass's own applied-kinds invalidation does not schedule a "
        'follow-up pass', () async {
      // Mirrors production timing exactly: the isolate boundary's
      // `onAppliedKinds` hook (wired through `main.dart` to
      // `expectSyncAppliedInvalidation`) fires, and the resulting
      // `tableUpdates()` notification reaches `notifyLocalChange` — all
      // before the pass's own `passOperation` returns, i.e. while this
      // trigger's `coordinator.trigger()` call is still unresolved.
      final controller = build(debounce: const Duration(milliseconds: 10));
      coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          passes.add(1);
          controller.expectSyncAppliedInvalidation();
          controller.notifyLocalChange();
          return const SyncPassResult(
            SyncPassStatus.completed,
            appliedKinds: [SyncRecordKind.dance],
          );
        },
      );
      addTearDown(coordinator!.dispose);
      await controller.load();
      await controller.setEnabled(true);

      await controller.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        passes,
        hasLength(1),
        reason:
            'the pass reporting its own applied kinds must not queue a '
            'redundant follow-up pass',
      );
    });

    test('a user edit during a pass whose own applied-kinds invalidation also '
        'fires still schedules exactly one follow-up pass', () async {
      final controller = build(debounce: const Duration(milliseconds: 10));
      coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          passes.add(1);
          if (passes.length == 1) {
            // The pass's own self-invalidation...
            controller.expectSyncAppliedInvalidation();
            controller.notifyLocalChange();
            // ...and an independent, genuine local edit landing in the
            // same instant. Only the latter is a reason to run again.
            controller.notifyLocalChange();
          }
          return const SyncPassResult(
            SyncPassStatus.completed,
            appliedKinds: [SyncRecordKind.dance],
          );
        },
      );
      addTearDown(coordinator!.dispose);
      await controller.load();
      await controller.setEnabled(true);

      await controller.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        passes,
        hasLength(2),
        reason: 'the genuine edit still earns exactly one follow-up pass',
      );
    });

    test('an applied-kinds invalidation left pending across a disable does not '
        'swallow the next genuine edit after re-enabling', () async {
      final controller = build(debounce: const Duration(milliseconds: 10));
      await controller.load();
      await controller.setEnabled(true);

      // The hook fires (as it would from a pass's own applied-kinds
      // invalidation)...
      controller.expectSyncAppliedInvalidation();
      // ...but sync is disabled before the resulting table invalidation
      // reaches `notifyLocalChange` (e.g. the applying pass is torn down
      // mid-apply). The early return for a disabled controller must not
      // skip consuming the counter, or it outlives this pass entirely.
      await controller.setEnabled(false);
      controller.notifyLocalChange();

      await controller.setEnabled(true);
      passes.clear();

      // A genuine edit after re-enabling must schedule a pass, not be
      // mistaken for the invalidation that was already accounted for.
      controller.notifyLocalChange();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        passes,
        hasLength(1),
        reason:
            'a stale pending-invalidation counter must not survive a '
            'disable/re-enable cycle and swallow a real edit',
      );
    });

    test('a shareable-settings change schedules a pass, but the controller\'s '
        'own bookkeeping write does not', () async {
      final controller = build(debounce: const Duration(milliseconds: 10));
      await controller.load();
      await controller.setEnabled(true);

      // The enable write's own change notification arrives first, exactly as
      // it would from the real database stream, and must not schedule a pass.
      controller.notifyLocalChange(settingsOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(passes, isEmpty, reason: 'the enable write is not a user edit');

      // A genuine shareable-preference change is a record and must be synced.
      controller.notifyLocalChange(settingsOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(passes, hasLength(1), reason: 'a user preference is a record');

      // The pass that just ran recorded its own success; that settings
      // write's own notification is not a user edit and must not start
      // another pass.
      passes.clear();
      await controller.syncNow();
      passes.clear();
      controller.notifyLocalChange(settingsOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(passes, isEmpty);
    });

    test('the self-write expectation from a disable cannot leak into the next '
        'enabled session', () async {
      final controller = build(debounce: const Duration(milliseconds: 10));
      await controller.load();

      // Enable and consume its own bookkeeping write, exactly as the real
      // settings stream would deliver it.
      await controller.setEnabled(true);
      controller.notifyLocalChange(settingsOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      passes.clear();

      // Disabling also expects a self write, but `notifyLocalChange` bails
      // out before it ever inspects the counter once `enabled` is false —
      // exactly as it does in production — so nothing here consumes it.
      await controller.setEnabled(false);

      // Re-enable and consume this session's own bookkeeping write too.
      await controller.setEnabled(true);
      controller.notifyLocalChange(settingsOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      passes.clear();

      // A genuine user settings-only edit after re-enabling must still
      // schedule a pass. On the leaking code the disable's uncollected
      // expectation is still outstanding and swallows this call instead.
      controller.notifyLocalChange(settingsOnly: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        passes,
        hasLength(1),
        reason: 'a real preference edit after re-enabling is a record',
      );
    });
  });

  group('§6.14 item 4 expiry warning', () {
    test('warns once the last success is 21 days old, not before', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      await repos.settings.set(kSyncIdKey, 'configured');
      await controller.syncNow();
      await controller.load();
      expect(controller.expiryApproaching, isFalse);

      clock = clock.add(const Duration(days: 20, hours: 23));
      expect(controller.expiryApproaching, isFalse);
      clock = clock.add(const Duration(hours: 1));
      expect(controller.expiryApproaching, isTrue);
    });

    test('never warns before a first success', () async {
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      clock = clock.add(const Duration(days: 90));
      expect(controller.expiryApproaching, isFalse);
    });
  });

  group('pass report notices (spec §2 "report")', () {
    /// A coordinator whose pass returns [result] each time, so a test can
    /// walk a sequence of pass outcomes through the real controller.
    SyncCoordinator reporting(SyncPassResult Function() result) =>
        SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device',
          store: CompendiumSyncCoordinatorStore(repos),
          transport: NoopSyncCoordinatorTransport(),
          passOperation: ({initialStore}) async => result(),
        );

    const tie = SyncReport(
      code: SyncReportCode.equalUpdatedAt,
      kind: SyncRecordKind.dance,
      recordId: 'dance-1',
      message: 'Different record bodies have the same updatedAt.',
    );

    Future<SyncController> paired() async {
      await repos.settings.set(kSyncIdKey, 'configured');
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);
      return controller;
    }

    test('reports raised by a pass are kept as notices', () async {
      var result = const SyncPassResult(
        SyncPassStatus.completed,
        reports: [tie],
      );
      coordinator = reporting(() => result);
      final controller = await paired();
      await controller.syncNow();

      expect(controller.notices.map((r) => r.code), [
        SyncReportCode.equalUpdatedAt,
      ]);
    });

    test('duplicate reports are coalesced by their coalescing key', () async {
      // `SyncReportSink` coalesces within one sink, but a fresh attach that
      // continues into a steady pass concatenates two sinks' output verbatim
      // (sync_coordinator.dart, the continuation result), so the same
      // condition can arrive twice in one result.
      var result = const SyncPassResult(
        SyncPassStatus.completed,
        reports: [tie, tie],
      );
      coordinator = reporting(() => result);
      final controller = await paired();
      await controller.syncNow();

      expect(controller.notices.length, 1);
    });

    test('a completed pass that raises nothing clears the notices', () async {
      var result = const SyncPassResult(
        SyncPassStatus.completed,
        reports: [tie],
      );
      coordinator = reporting(() => result);
      final controller = await paired();
      await controller.syncNow();
      expect(controller.notices, isNotEmpty);

      result = const SyncPassResult(SyncPassStatus.completed);
      await controller.syncNow();

      expect(controller.notices, isEmpty);
    });

    test('a pass that did not complete leaves the notices standing', () async {
      var result = const SyncPassResult(
        SyncPassStatus.completed,
        reports: [tie],
      );
      coordinator = reporting(() => result);
      final controller = await paired();
      await controller.syncNow();

      result = const SyncPassResult(SyncPassStatus.failed);
      await controller.syncNow();

      expect(controller.notices.map((r) => r.code), [
        SyncReportCode.equalUpdatedAt,
      ]);
    });

    test(
      'detaching forgets the notices with the rest of the store state',
      () async {
        var result = const SyncPassResult(
          SyncPassStatus.completed,
          reports: [tie],
        );
        coordinator = reporting(() => result);
        final controller = await paired();
        await controller.syncNow();
        expect(controller.notices, isNotEmpty);

        await controller.detach();

        expect(controller.notices, isEmpty);
      },
    );
  });

  group('connectivity classification', () {
    test('maps platform results', () {
      expect(
        classifyConnectivity([ConnectivityResult.wifi]),
        SyncNetworkKind.unmetered,
      );
      expect(
        classifyConnectivity([ConnectivityResult.mobile]),
        SyncNetworkKind.metered,
      );
      expect(
        classifyConnectivity([
          ConnectivityResult.mobile,
          ConnectivityResult.wifi,
        ]),
        SyncNetworkKind.unmetered,
      );
      expect(
        classifyConnectivity([
          ConnectivityResult.mobile,
          ConnectivityResult.vpn,
        ]),
        SyncNetworkKind.metered,
        reason: 'a VPN overlay must not hide a cellular link',
      );
      expect(
        classifyConnectivity([ConnectivityResult.vpn]),
        SyncNetworkKind.unknown,
      );
      expect(
        classifyConnectivity([ConnectivityResult.none]),
        SyncNetworkKind.offline,
      );
      expect(classifyConnectivity([]), SyncNetworkKind.unknown);
      expect(
        classifyConnectivity([ConnectivityResult.other]),
        SyncNetworkKind.unknown,
      );
    });
  });

  group('pairing (spec §6.2, §6.14 items 1, 2, 5)', () {
    test('probeFor builds a live probe for the endpoint it is given', () {
      final controller = build();
      final probe = controller.probeFor(
        'alpha-bravo-charlie-delta',
        Uri.parse(kDefaultSyncEndpoint),
      );
      addTearDown(() => probe.close?.call());
      expect(probe.close, isNotNull);
    });

    test('tryParseSyncEndpoint enforces the spec §8 entry validation', () {
      expect(
        tryParseSyncEndpoint(' https://sync.example.test/ '),
        Uri.parse('https://sync.example.test/'),
      );
      expect(tryParseSyncEndpoint('http://127.0.0.1:33333'), isNotNull);
      for (final rejected in [
        '',
        'sync.example.test',
        'http://sync.example.test/',
        'https://user@sync.example.test/',
        'https://sync.example.test/?q=1',
        'https://sync.example.test/#f',
      ]) {
        expect(tryParseSyncEndpoint(rejected), isNull, reason: rejected);
      }
    });

    test('isDefaultSyncEndpoint compares by origin', () {
      expect(isDefaultSyncEndpoint(Uri.parse(kDefaultSyncEndpoint)), isTrue);
      expect(
        isDefaultSyncEndpoint(
          Uri.parse('https://athenaeum.callerscompendium.com'),
        ),
        isTrue,
      );
      expect(
        isDefaultSyncEndpoint(Uri.parse('https://sync.example.test/')),
        isFalse,
      );
    });

    test('probeFor uses the injected factory over the real client', () {
      final probe = SyncPairingProbe(
        getStore: ({required previouslyUsed}) async =>
            throw UnimplementedError(),
        createStore: () async => throw UnimplementedError(),
      );
      final controller = SyncController(
        settings: repos.settings,
        syncLocal: repos.syncLocal,
        coordinator: () => coordinator,
        reconfigure: () async {},
        pairingProbeFactory: (syncId, endpoint) => probe,
        classifier: network,
      );
      addTearDown(controller.dispose);
      expect(
        identical(
          controller.probeFor(
            'correct horse battery staple',
            Uri.parse('https://sync.example.test/'),
          ),
          probe,
        ),
        isTrue,
      );
    });

    test('completePairing persists the ID and endpoint, marks paired, and '
        'asks for reconfiguration exactly once', () async {
      var reconfigured = 0;
      final controller = SyncController(
        settings: repos.settings,
        syncLocal: repos.syncLocal,
        coordinator: () => coordinator,
        reconfigure: () async => reconfigured++,
        classifier: network,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.paired, isFalse);

      await controller.completePairing(
        'correct horse battery staple',
        Uri.parse('https://sync.example.test/'),
      );

      expect(controller.paired, isTrue);
      expect(controller.endpoint, Uri.parse('https://sync.example.test/'));
      expect(
        await repos.settings.get(kSyncIdKey),
        'correct horse battery staple',
      );
      expect(
        await repos.settings.get(kSyncEndpointKey),
        'https://sync.example.test/',
      );
      expect(reconfigured, 1);
    });

    test('completePairing awaits the fresh-attach pass so lastResult carries '
        'the real W8 duplicate count', () async {
      coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async =>
            const SyncPassResult(SyncPassStatus.completed, duplicateCount: 5),
      );
      addTearDown(() => coordinator?.dispose());
      final controller = build();
      await controller.load();
      await controller.setEnabled(true);

      await controller.completePairing(
        'correct horse battery staple',
        Uri.parse(kDefaultSyncEndpoint),
      );

      expect(
        controller.lastResult?.duplicateCount,
        5,
        reason:
            'reconfigure alone only awaits coordinator construction, not '
            'the app-start pass it schedules unawaited',
      );
    });
  });

  group('detach (spec glossary, §6.2 step 3)', () {
    Future<SyncController> paired({
      Future<void> Function(Future<void> Function() operation)? runExclusive,
    }) async {
      await repos.settings.set(kSyncEnabledKey, true);
      await repos.settings.set(kSyncIdKey, 'correct horse battery staple');
      await repos.settings.set(kSyncEndpointKey, 'https://sync.example.test/');
      await repos.settings.set(kSyncDeviceIdKey, 'device_1');
      await repos.settings.set(kSyncLastUsedFingerprintKey, ['verifier']);
      await repos.settings.set(kSyncLastSuccessAtKey, '2026-09-20T12:00:00Z');
      await repos.syncLocal.replaceBaseline(epoch: 'epoch-1');
      final controller = SyncController(
        settings: repos.settings,
        syncLocal: repos.syncLocal,
        coordinator: () => coordinator,
        reconfigure: () async {},
        runExclusive: runExclusive ?? (operation) => operation(),
        classifier: network,
        now: () => clock,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.paired, isTrue);
      return controller;
    }

    Future<bool> hasRow(String key) async {
      final rows = await repos.db
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ?',
            variables: [Variable.withString(key)],
          )
          .get();
      return rows.isNotEmpty;
    }

    test('erases the sync ID and store-scoped state inside the writer '
        'boundary, and leaves everything the spec keeps', () async {
      var exclusiveRuns = 0;
      late SyncController controller;
      controller = await paired(
        runExclusive: (operation) async {
          exclusiveRuns++;
          expect(
            controller.paired,
            isTrue,
            reason:
                'reporting unpaired here would offer Connect, and a pairing '
                'completing in this window loses the ID it just wrote',
          );
          await operation();
        },
      );

      await controller.detach();

      expect(exclusiveRuns, 1);
      expect(controller.paired, isFalse);
      expect(controller.endpoint, isNull);
      expect(controller.lastSuccessAt, isNull);
      expect(
        await hasRow(kSyncIdKey),
        isFalse,
        reason: 'a tombstone would keep the credential on disk',
      );
      expect(await hasRow(kSyncLastSuccessAtKey), isFalse);
      expect(await hasRow(kSyncEndpointKey), isFalse);
      expect(await repos.syncLocal.getBaselineState(), isNull);

      expect(controller.enabled, isTrue, reason: 'detach is not disable');
      expect(await repos.settings.get(kSyncEnabledKey), isTrue);
      expect(await repos.settings.get(kSyncDeviceIdKey), 'device_1');
      expect(await repos.settings.get(kSyncLastUsedFingerprintKey), [
        'verifier',
      ]);
    });

    test(
      'a detach the writer refuses leaves the device fully attached',
      () async {
        final controller = await paired(
          runExclusive: (operation) async =>
              throw StateError('writer refused during shutdown'),
        );

        await expectLater(controller.detach(), throwsStateError);

        expect(controller.paired, isTrue);
        expect(
          await repos.settings.get(kSyncIdKey),
          'correct horse battery staple',
        );
        expect(
          await repos.settings.get(kSyncEndpointKey),
          'https://sync.example.test/',
        );
        expect(await repos.syncLocal.getBaselineState(), isNotNull);
      },
    );

    test('a pass finishing after the clear does not restore its '
        'last-success time', () async {
      final gate = Completer<void>();
      coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          await gate.future;
          return const SyncPassResult(SyncPassStatus.completed);
        },
      );
      addTearDown(() => coordinator?.dispose());
      late SyncController controller;
      controller = await paired(
        runExclusive: (operation) async {
          final pass = controller.trigger(SyncTrigger.manual);
          await operation();
          gate.complete();
          expect(await pass, SyncGateOutcome.ran);
        },
      );

      await controller.detach();

      expect(controller.lastSuccessAt, isNull);
      expect(await repos.settings.get(kSyncLastSuccessAtKey), isNull);
    });
  });

  group('replacement (spec §6.3 step 1, §6.14 item 6)', () {
    /// A coordinator that reports a missing previously used store on every
    /// trigger until the confirmation's own `POST /v1/store` has actually
    /// happened — so a retried trigger before that reproduces the same
    /// condition, and only a real confirm resolves it.
    SyncCoordinator replacementCoordinator(
      ControllableSyncTransport transport,
    ) => SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device',
      store: CompendiumSyncCoordinatorStore(repos),
      transport: transport,
      passOperation: ({initialStore}) async {
        if (transport.createStoreCalls == 0) {
          return const SyncPassResult(SyncPassStatus.replacementRequired);
        }
        return const SyncPassResult(
          SyncPassStatus.completed,
          duplicateCount: 3,
        );
      },
    );

    test('replacementPending turns on when the coordinator reports a missing '
        'previously used store', () async {
      final transport = ControllableSyncTransport();
      coordinator = replacementCoordinator(transport);
      final controller = build();
      addTearDown(() => coordinator?.dispose());
      controller.attachCoordinator(coordinator);
      await controller.load();
      await controller.setEnabled(true);

      expect(controller.replacementPending, isFalse);
      await controller.syncNow();
      expect(controller.replacementPending, isTrue);
    });

    test(
      'confirm creates once and records the fresh-attach duplicate count',
      () async {
        final transport = ControllableSyncTransport();
        coordinator = replacementCoordinator(transport);
        final controller = build();
        addTearDown(() => coordinator?.dispose());
        controller.attachCoordinator(coordinator);
        await controller.load();
        await controller.setEnabled(true);
        await controller.syncNow();
        expect(controller.replacementPending, isTrue);

        // A double tap must still issue exactly one `POST /v1/store`: the
        // coordinator's own single-flight confirmation guard, exercised
        // through the controller.
        final first = controller.confirmReplacement();
        final second = controller.confirmReplacement();
        final results = await Future.wait([first, second]);

        expect(transport.createStoreCalls, 1);
        expect(controller.replacementPending, isFalse);
        expect(
          results.every((r) => r?.status == SyncPassStatus.completed),
          isTrue,
        );
        expect(controller.lastResult?.duplicateCount, 3);
      },
    );

    test(
      'decline issues no POST and leaves the decision available later',
      () async {
        final transport = ControllableSyncTransport();
        coordinator = replacementCoordinator(transport);
        final controller = build();
        addTearDown(() => coordinator?.dispose());
        controller.attachCoordinator(coordinator);
        await controller.load();
        await controller.setEnabled(true);
        await controller.syncNow();
        expect(controller.replacementPending, isTrue);

        controller.declineReplacement();

        expect(transport.createStoreCalls, 0);
        expect(controller.replacementPending, isFalse);

        // The decision is still available: a later manual sync re-offers it
        // rather than silently having resolved it.
        await controller.syncNow();
        expect(controller.replacementPending, isTrue);
      },
    );

    test(
      'a failed confirmation leaves the decision pending and retryable',
      () async {
        final transport = ControllableSyncTransport()
          ..createStoreResponse = const SyncHttpResponse(
            statusCode: 500,
            kind: SyncResponseKind.serverError,
            headers: {},
            body: [],
          );
        coordinator = replacementCoordinator(transport);
        final controller = build();
        addTearDown(() => coordinator?.dispose());
        controller.attachCoordinator(coordinator);
        await controller.load();
        await controller.setEnabled(true);
        await controller.syncNow();
        expect(controller.replacementPending, isTrue);

        final result = await controller.confirmReplacement();

        expect(result?.status, SyncPassStatus.failed);
        expect(
          controller.replacementPending,
          isTrue,
          reason:
              'the coordinator never emits a fresh replacementRequired event '
              'for a still-pending decision, so clearing this on a failure '
              'would hide it permanently',
        );

        // The decision is retryable once the transport recovers.
        transport.createStoreResponse = const SyncHttpResponse(
          statusCode: 201,
          kind: SyncResponseKind.created,
          headers: {},
          body: [],
        );
        final retry = await controller.confirmReplacement();
        expect(retry?.status, SyncPassStatus.completed);
        expect(controller.replacementPending, isFalse);
      },
    );

    test('attachCoordinator(null) detaches from a disposed coordinator', () {
      final controller = build();
      controller.attachCoordinator(coordinator);
      controller.attachCoordinator(null);
      // No StreamSubscription leak assertion is possible from the outside;
      // this only proves the call is safe to make with no coordinator.
      expect(controller.replacementPending, isFalse);
    });
  });
}
