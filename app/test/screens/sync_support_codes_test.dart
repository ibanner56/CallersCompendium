// The codes "Copy details" puts on the clipboard, and the rejected-upload
// advice split by which server the device uses.
import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/settings/sync_failure_labels.dart';
import 'package:compendium_app/src/screens/settings/sync_notice_labels.dart';
import 'package:compendium_app/src/screens/settings/sync_support_codes.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('support codes', () {
    test('a failure is its cause, then its step and status when known', () {
      expect(
        syncFailureSupportCode(
          const SyncFailure(
            SyncFailureCause.rejected,
            step: SyncFailureStep.upload,
            statusCode: 422,
          ),
        ),
        'SYNC-REFUSED upload 422',
      );
      expect(
        syncFailureSupportCode(const SyncFailure(SyncFailureCause.internal)),
        'SYNC-INTERNAL',
      );
    });

    test('every cause has its own code', () {
      final codes = {
        for (final cause in SyncFailureCause.values)
          syncFailureCauseCode(cause),
      };
      expect(codes, hasLength(SyncFailureCause.values.length));
    });

    test('a status that is not a problem has no code', () {
      expect(
        syncPassSupportCode(const SyncPassResult(SyncPassStatus.completed)),
        isNull,
      );
      expect(
        syncPassSupportCode(const SyncPassResult(SyncPassStatus.paused)),
        'SYNC-PAUSED',
      );
    });

    test('a notice code counts the records, and names no record', () {
      final reports = [
        for (final id in ['a', 'b', 'c', 'd'])
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            kind: SyncRecordKind.dance,
            recordId: 'record-$id',
            peerId: 'peer-secret',
            message: 'GET /v1/blobs/abc',
          ),
      ];
      final code = syncNoticeSupportCode(SyncNoticeGroup.newerVersion, reports);
      expect(code, 'SYNC-NEWER-VERSION ×4');
      expect(
        syncNoticeSupportCode(SyncNoticeGroup.newerVersion, const [
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            peerId: 'peer-secret',
            message: 'manifest',
          ),
        ]),
        'SYNC-NEWER-VERSION',
      );
    });

    test('a notice that also has a report naming no record gives no count, '
        'since the count would understate it', () {
      expect(
        syncNoticeSupportCode(SyncNoticeGroup.newerVersion, const [
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            kind: SyncRecordKind.dance,
            recordId: 'd1',
            peerId: 'peer-a',
            message: 'blob',
          ),
          SyncReport(
            code: SyncReportCode.newerWireVersion,
            peerId: 'peer-b',
            message: 'manifest',
          ),
        ]),
        'SYNC-NEWER-VERSION',
      );
    });

    test('the quota code rounds down, never overstating use', () {
      expect(
        syncQuotaSupportCode(
          const SyncStoreQuota(
            blobs: 899,
            bytes: 0,
            maxBlobs: 1000,
            maxBytes: 1,
          ),
        ),
        'SYNC-QUOTA 89%',
      );
    });
  });

  group('a refused upload points at the side that has to act', () {
    test('on the project server, nothing for the user to do', () {
      expect(
        syncFailureAdvice(l10n, SyncFailureCause.rejected, customServer: false),
        l10n.settingsSyncFailureRejectedAdviceDefaultServer,
      );
    });

    test('on their own server, update it', () {
      expect(
        syncFailureAdvice(l10n, SyncFailureCause.rejected, customServer: true),
        l10n.settingsSyncFailureRejectedAdviceCustomServer,
      );
    });

    test('which server is decided by origin, and an unknown one is the '
        'default', () {
      expect(syncUsesCustomServer(null), isFalse);
      expect(syncUsesCustomServer(Uri.parse(kDefaultSyncEndpoint)), isFalse);
      expect(
        syncUsesCustomServer(Uri.parse('https://sync.example.test/')),
        isTrue,
      );
    });
  });
}
