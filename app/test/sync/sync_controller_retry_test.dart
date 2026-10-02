// The automatic retry after a transient failure, the resume trigger and the
// store-quota latch (spec §5.2, §6.12): the parts of `SyncController` that act
// on a pass's outcome after it has been recorded.

import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/noop_sync_transport.dart';
import '../support/test_repositories.dart';

final class _Network implements SyncNetworkClassifier {
  SyncNetworkKind kind = SyncNetworkKind.unmetered;
  @override
  Future<SyncNetworkKind> current() async => kind;
}

/// Answers each trigger with the next scripted result (the last repeats) and
/// records which trigger asked, so a test can tell a retry from a resume.
final class _ScriptedCoordinator extends SyncCoordinator {
  _ScriptedCoordinator(CompendiumRepositories repos, this.results)
    : super(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
      );

  final List<SyncPassResult> results;
  final triggers = <SyncTrigger>[];

  @override
  Future<SyncPassResult> trigger(SyncTrigger trigger) async {
    triggers.add(trigger);
    return results.length > 1 ? results.removeAt(0) : results.single;
  }
}

SyncPassResult _failed(
  SyncFailureCause cause, {
  Duration? retryAfter,
  SyncStoreQuota? quota,
}) => SyncPassResult(
  SyncPassStatus.failed,
  failure: SyncFailure(cause, retryAfter: retryAfter),
  quota: quota,
);

const _completed = SyncPassResult(SyncPassStatus.completed);

/// Backoff steps short enough to wait out in a test, and distinct enough that
/// the step taken is readable from [SyncController.pendingRetryDelay].
const _backoff = [
  Duration(milliseconds: 40),
  Duration(milliseconds: 80),
  Duration(milliseconds: 160),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CompendiumRepositories repos;
  late _Network network;
  late DateTime clock;
  late _ScriptedCoordinator coordinator;

  Future<SyncController> paired(
    List<SyncPassResult> results, {
    Future<void> Function(Future<void> Function() operation)? runExclusive,
    bool disposeInTearDown = true,
  }) async {
    coordinator = _ScriptedCoordinator(repos, results);
    await repos.settings.set(kSyncEnabledKey, true);
    await repos.settings.set(kSyncIdKey, 'correct horse battery staple');
    await repos.settings.set(kSyncEndpointKey, 'https://sync.example.test/');
    final controller = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => coordinator,
      reconfigure: ({bool startPass = true}) async {},
      runExclusive: runExclusive ?? (operation) => operation(),
      // Never reaches a network: the wipe below is refused by this fake.
      deviceAdminFactory: (syncId, endpoint) => SyncDeviceAdmin(
        getStore: ({required previouslyUsed}) => throw UnimplementedError(),
        deleteManifest: (_) => throw UnimplementedError(),
        deleteStore: () async => const SyncHttpResponse(
          statusCode: 500,
          kind: SyncResponseKind.serverError,
          headers: {},
          body: [],
        ),
      ),
      classifier: network,
      now: () => clock,
      retryBackoff: _backoff,
    );
    if (disposeInTearDown) addTearDown(controller.dispose);
    await controller.load();
    expect(controller.paired, isTrue);
    return controller;
  }

  setUp(() {
    repos = openTestRepositories();
    network = _Network();
    clock = DateTime.utc(2026, 10, 2, 12);
  });

  group('automatic retry (spec §6.12)', () {
    for (final cause in [
      SyncFailureCause.unreachable,
      SyncFailureCause.timedOut,
      SyncFailureCause.serverError,
      SyncFailureCause.rateLimited,
    ]) {
      test('a ${cause.name} failure schedules a retry', () async {
        final controller = await paired([_failed(cause)]);
        await controller.syncNow();
        expect(controller.pendingRetryDelay, _backoff[0]);
      });
    }

    for (final cause in [
      SyncFailureCause.storeFull,
      SyncFailureCause.tooLarge,
      SyncFailureCause.rejected,
      SyncFailureCause.accessDenied,
      SyncFailureCause.unexpectedResponse,
      SyncFailureCause.peerUnavailable,
      SyncFailureCause.internal,
    ]) {
      test('a ${cause.name} failure is not retried by itself', () async {
        // Spec §5.3: a 507 and a 422 MUST NOT be retried without the user.
        final controller = await paired([_failed(cause)]);
        await controller.syncNow();
        expect(controller.pendingRetryDelay, isNull);
      });
    }

    test('the retry runs a pass of its own when the wait is over', () async {
      final controller = await paired([
        _failed(SyncFailureCause.unreachable),
        _completed,
      ]);
      await controller.syncNow();
      await Future<void>.delayed(_backoff[0] * 3);

      expect(coordinator.triggers, [SyncTrigger.manual, SyncTrigger.retry]);
      expect(controller.lastResult?.status, SyncPassStatus.completed);
      expect(controller.pendingRetryDelay, isNull);
    });

    test('each consecutive failure waits twice as long, up to the last '
        'step, which repeats', () async {
      final controller = await paired([_failed(SyncFailureCause.timedOut)]);
      final delays = <Duration?>[];
      for (var i = 0; i < 5; i++) {
        await controller.syncNow();
        delays.add(controller.pendingRetryDelay);
      }
      expect(delays, [
        _backoff[0],
        _backoff[1],
        _backoff[2],
        _backoff[2],
        _backoff[2],
      ]);
    });

    test('a completed pass resets the backoff', () async {
      final controller = await paired([
        _failed(SyncFailureCause.timedOut),
        _failed(SyncFailureCause.timedOut),
        _completed,
        _failed(SyncFailureCause.timedOut),
      ]);
      await controller.syncNow();
      await controller.syncNow();
      expect(controller.pendingRetryDelay, _backoff[1]);
      await controller.syncNow();
      expect(controller.pendingRetryDelay, isNull);
      await controller.syncNow();
      expect(controller.pendingRetryDelay, _backoff[0]);
    });

    test('Retry-After is a floor on the wait, never a ceiling', () async {
      final controller = await paired([
        _failed(
          SyncFailureCause.rateLimited,
          retryAfter: const Duration(minutes: 7),
        ),
        _failed(
          SyncFailureCause.rateLimited,
          retryAfter: const Duration(milliseconds: 1),
        ),
      ]);
      await controller.syncNow();
      expect(controller.pendingRetryDelay, const Duration(minutes: 7));
      await controller.syncNow();
      expect(
        controller.pendingRetryDelay,
        _backoff[1],
        reason: 'a Retry-After shorter than the backoff does not shorten it',
      );
    });

    test('a Retry-After past the ceiling is held to it', () async {
      final controller = await paired([
        _failed(
          SyncFailureCause.serverError,
          retryAfter: const Duration(days: 365),
        ),
      ]);
      await controller.syncNow();
      expect(controller.pendingRetryDelay, kSyncRetryAfterCeiling);
    });

    test('a needs-you failure cancels a retry already pending', () async {
      final controller = await paired([
        _failed(SyncFailureCause.unreachable),
        _failed(SyncFailureCause.storeFull),
      ]);
      await controller.syncNow();
      expect(controller.pendingRetryDelay, isNotNull);
      await controller.syncNow();
      expect(controller.pendingRetryDelay, isNull);
      await Future<void>.delayed(_backoff[0] * 3);
      expect(coordinator.triggers, [SyncTrigger.manual, SyncTrigger.manual]);
    });

    test(
      'a retry the connection gate suppresses waits for the next trigger',
      () async {
        final controller = await paired([
          _failed(SyncFailureCause.unreachable),
        ]);
        await controller.syncNow();
        network.kind = SyncNetworkKind.offline;
        await Future<void>.delayed(_backoff[0] * 3);

        expect(coordinator.triggers, [SyncTrigger.manual]);
        expect(
          controller.pendingRetryDelay,
          isNull,
          reason: 'a suppressed retry schedules no further one',
        );
      },
    );

    test('an automatic retry on a metered connection is suppressed while '
        'WiFi-only is on', () async {
      final controller = await paired([_failed(SyncFailureCause.unreachable)]);
      await controller.syncNow();
      network.kind = SyncNetworkKind.metered;
      await Future<void>.delayed(_backoff[0] * 3);

      expect(coordinator.triggers, [SyncTrigger.manual]);
      expect(
        controller.wifiSettingRequests.value,
        0,
        reason: 'only a manual attempt is routed to the setting',
      );
    });

    group('is cancelled', () {
      Future<void> expectCancelled(
        SyncController controller,
        Future<void> Function() action,
      ) async {
        await controller.syncNow();
        expect(controller.pendingRetryDelay, isNotNull);
        await action();
        expect(controller.pendingRetryDelay, isNull);
        await Future<void>.delayed(_backoff[0] * 3);
        expect(
          coordinator.triggers.where((t) => t == SyncTrigger.retry),
          isEmpty,
        );
      }

      test('when sync is turned off', () async {
        final controller = await paired([_failed(SyncFailureCause.timedOut)]);
        await expectCancelled(controller, () => controller.setEnabled(false));
      });

      test('when this device disconnects', () async {
        final controller = await paired([_failed(SyncFailureCause.timedOut)]);
        await expectCancelled(controller, controller.detach);
      });

      test('when the store is wiped', () async {
        final controller = await paired([_failed(SyncFailureCause.timedOut)]);
        // The wipe itself fails at the server; the retry is cancelled at the
        // start of the attempt either way.
        await expectCancelled(controller, controller.wipeStore);
      });

      test('when the controller is disposed', () async {
        final controller = await paired([
          _failed(SyncFailureCause.timedOut),
        ], disposeInTearDown: false);
        await controller.syncNow();
        controller.dispose();
        // `trigger` already refuses after dispose, so a leaked timer would run
        // no pass; what dispose owes is not leaving one armed at all.
        expect(controller.pendingRetryDelay, isNull);
        await Future<void>.delayed(_backoff[0] * 3);
        expect(coordinator.triggers, [SyncTrigger.manual]);
      });

      test('when this device pairs with a store', () async {
        final controller = await paired([_failed(SyncFailureCause.timedOut)]);
        // `completePairing` runs its own pass, which fails again here and
        // schedules a retry of its own — from the first step, because pairing
        // reset the backoff along with cancelling the old one.
        await controller.syncNow();
        await controller.syncNow();
        expect(controller.pendingRetryDelay, _backoff[1]);
        await controller.completePairing(
          'correct horse battery staple',
          Uri.parse('https://sync.example.test/'),
        );
        expect(controller.pendingRetryDelay, _backoff[0]);
      });
    });
  });

  group('resume (spec §6.12)', () {
    test('coming back to the foreground runs a pass', () async {
      final controller = await paired([_completed]);
      expect(await controller.onAppResumed(), SyncGateOutcome.ran);
      expect(coordinator.triggers, [SyncTrigger.resume]);
    });

    test('runs at most once per interval, counted from any pass', () async {
      final controller = await paired([_completed]);
      await controller.syncNow();
      clock = clock.add(kSyncResumeInterval - const Duration(seconds: 1));
      expect(await controller.onAppResumed(), isNull);
      clock = clock.add(const Duration(seconds: 1));
      expect(await controller.onAppResumed(), SyncGateOutcome.ran);
      expect(await controller.onAppResumed(), isNull);
      expect(coordinator.triggers, [SyncTrigger.manual, SyncTrigger.resume]);
    });

    test(
      'a resume the gate suppressed does not count against the interval',
      () async {
        final controller = await paired([_completed]);
        network.kind = SyncNetworkKind.offline;
        expect(
          await controller.onAppResumed(),
          SyncGateOutcome.suppressedOffline,
        );
        network.kind = SyncNetworkKind.unmetered;
        expect(await controller.onAppResumed(), SyncGateOutcome.ran);
      },
    );

    test('does nothing while sync is off', () async {
      final controller = await paired([_completed]);
      await controller.setEnabled(false);
      expect(await controller.onAppResumed(), isNull);
      expect(coordinator.triggers, isEmpty);
    });
  });

  group('store quota (spec §5.2)', () {
    const nearlyFull = SyncStoreQuota(
      blobs: 85,
      bytes: 0,
      maxBlobs: 100,
      maxBytes: 100,
    );

    test('a pass reporting a nearly full store raises the warning', () async {
      final controller = await paired([
        const SyncPassResult(SyncPassStatus.completed, quota: nearlyFull),
      ]);
      expect(controller.quotaNearlyFull, isFalse);
      await controller.syncNow();
      expect(controller.quotaNearlyFull, isTrue);
    });

    test(
      'a pass that never read the store keeps the last known usage',
      () async {
        final controller = await paired([
          const SyncPassResult(SyncPassStatus.completed, quota: nearlyFull),
          _failed(SyncFailureCause.unreachable),
        ]);
        await controller.syncNow();
        await controller.syncNow();
        expect(controller.quotaNearlyFull, isTrue);
      },
    );

    test('a later reading below the threshold clears it', () async {
      final controller = await paired([
        const SyncPassResult(SyncPassStatus.completed, quota: nearlyFull),
        const SyncPassResult(
          SyncPassStatus.completed,
          quota: SyncStoreQuota(
            blobs: 10,
            bytes: 0,
            maxBlobs: 100,
            maxBytes: 100,
          ),
        ),
      ]);
      await controller.syncNow();
      await controller.syncNow();
      expect(controller.quotaNearlyFull, isFalse);
    });

    test('disconnecting forgets it', () async {
      final controller = await paired([
        const SyncPassResult(SyncPassStatus.completed, quota: nearlyFull),
      ]);
      await controller.syncNow();
      await controller.detach();
      expect(controller.storeQuota, isNull);
      expect(controller.quotaNearlyFull, isFalse);
    });
  });
}
