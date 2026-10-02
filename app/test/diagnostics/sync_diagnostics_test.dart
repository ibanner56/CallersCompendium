// The Device Sync section of the diagnostics export: what it says, and — the
// half that matters more — what it must never say. The section goes into the
// *scrubbed* export without passing through the redactor, so its own content
// is the only thing keeping the sync phrase, the server, device and record
// identifiers and report messages (which can carry wire paths) out of a file
// the user may send to someone.
import 'package:compendium_app/src/diagnostics/sync_diagnostics.dart';
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/sync/sync_runtime.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/noop_sync_transport.dart';
import '../support/test_repositories.dart';

const _phrase = 'correct horse battery staple';
const _endpoint = 'https://private-sync.example.test/';
const _peer = 'peer-0f3a9c';
const _recordId = 'dance-7d1e22';
const _message = 'GET /v1/blobs/abc123 returned a newer envelope';

final class _Network implements SyncNetworkClassifier {
  @override
  Future<SyncNetworkKind> current() async => SyncNetworkKind.unmetered;
}

Future<SyncController> _controller(
  CompendiumRepositories repos,
  SyncPassResult result,
) async {
  await repos.settings.set(kSyncEnabledKey, true);
  await repos.settings.set(kSyncIdKey, _phrase);
  await repos.settings.set(kSyncEndpointKey, _endpoint);
  final coordinator = SyncCoordinator(
    syncId: 'configured',
    deviceId: 'device',
    store: CompendiumSyncCoordinatorStore(repos),
    transport: NoopSyncCoordinatorTransport(),
    passOperation: ({initialStore}) async => result,
  );
  addTearDown(coordinator.dispose);
  final controller = SyncController(
    settings: repos.settings,
    syncLocal: repos.syncLocal,
    coordinator: () => coordinator,
    reconfigure: ({bool startPass = true}) async {},
    classifier: _Network(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CompendiumRepositories repos;

  setUp(() => repos = openTestRepositories());

  test('says nothing while sync is off and nothing has happened', () async {
    final controller = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => null,
      reconfigure: ({bool startPass = true}) async {},
      classifier: _Network(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(syncDiagnosticsSection(controller), isNull);
    expect(syncDiagnosticsSection(null), isNull);
  });

  test('names the last failure by cause, step and status, and lists notice '
      'codes with record kinds and counts', () async {
    final controller = await _controller(
      repos,
      const SyncPassResult(
        SyncPassStatus.failed,
        failure: SyncFailure(
          SyncFailureCause.rejected,
          step: SyncFailureStep.upload,
          statusCode: 422,
        ),
        quota: SyncStoreQuota(
          blobs: 90,
          bytes: 1,
          maxBlobs: 100,
          maxBytes: 100,
        ),
        reports: [
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            kind: SyncRecordKind.dance,
            recordId: _recordId,
            peerId: _peer,
            message: _message,
          ),
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            kind: SyncRecordKind.tag,
            recordId: 'tag-1',
            peerId: _peer,
            message: _message,
          ),
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            peerId: _peer,
            message: _message,
          ),
        ],
      ),
    );
    await controller.syncNow();

    final section = syncDiagnosticsSection(controller)!;
    expect(section, contains('Device Sync'));
    expect(section, contains('Last attempt: failed (SYNC-REFUSED upload 422)'));
    expect(
      section,
      contains('Cause: rejected; step: upload; HTTP status: 422'),
    );
    expect(section, contains('Store usage: SYNC-QUOTA 90%'));
    expect(section, contains('newerWireVersion: 3 (dance ×1, tag ×1)'));
  });

  test('never carries the phrase, the server, an identifier or a report '
      'message', () async {
    final controller = await _controller(
      repos,
      const SyncPassResult(
        SyncPassStatus.completed,
        reports: [
          SyncReport(
            code: SyncReportCode.equalUpdatedAt,
            kind: SyncRecordKind.dance,
            recordId: _recordId,
            peerId: _peer,
            message: _message,
          ),
        ],
      ),
    );
    await controller.syncNow();

    final section = syncDiagnosticsSection(controller)!;
    for (final secret in [
      _phrase,
      ..._phrase.split(' '),
      _endpoint,
      'private-sync',
      _peer,
      _recordId,
      _message,
      '/v1/',
    ]) {
      expect(section, isNot(contains(secret)), reason: secret);
    }
    expect(section, contains('equalUpdatedAt: 1 (dance ×1)'));
  });
}
