// The mapping from `SyncReportCode` to the notice a user actually reads.
//
// Written because #1347's `withheldUnreadableRecord` is the first code added
// since the mapping existed, and the mapping had no test at all: its exhaustive
// switch guarantees the build fails for an UNHANDLED code, which is a different
// thing from the code being wired to the right notice. A wrong arm compiles
// perfectly and tells the user to go and check a device that is fine.
//
// The first round of these tests covered the new code plus a sweep asserting
// every code resolved to some non-empty, distinct notice — which a wrong arm
// also satisfies, since the wrong group's text is non-empty too. `_expected`
// below is the standing half: it states the intended group per condition, and
// requires a row for every code, so the next code cannot arrive miswired
// without failing here.
import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/settings/sync_notice_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SyncReport _report(SyncReportCode code, {String? peerId}) => SyncReport(
  code: code,
  peerId: peerId,
  message: 'diagnostic english for ${code.name}',
);

/// One condition `syncNoticeGroupFor` distinguishes, and the group it must
/// produce for it.
typedef _Case = ({SyncReportCode code, String? peerId, SyncNoticeGroup group});

/// The intended mapping, written out rather than derived, so that the test
/// disagrees with the code when the code changes and the intent has not.
///
/// Keyed by condition, not by code, because `quarantinedRecord` answers two: a
/// null `peerId` is this device's own row, a set one is a peer's. A table keyed
/// by code alone would have to pick one of them and would leave the other arm
/// unguarded — which is the shape of the hole this file exists to close.
const _expected = <_Case>[
  (
    code: SyncReportCode.newerWireVersion,
    peerId: 'peer-1',
    group: SyncNoticeGroup.newerVersion,
  ),
  (
    code: SyncReportCode.equalUpdatedAt,
    peerId: 'peer-1',
    group: SyncNoticeGroup.divergence,
  ),
  (
    code: SyncReportCode.unseenLocalCreation,
    peerId: null,
    group: SyncNoticeGroup.keptLocalCreation,
  ),
  (
    code: SyncReportCode.malformedRecord,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  (
    code: SyncReportCode.nonCanonicalWireBody,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  (
    code: SyncReportCode.invalidClassification,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  (
    code: SyncReportCode.unresolvedBlob,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  (
    code: SyncReportCode.blobIdentityMismatch,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  (
    code: SyncReportCode.unresolvedReference,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  // Both halves of the one code that splits. Getting these the wrong way round
  // sends the user to the other device's app version for their own clock, or
  // to their own clock for a peer's record.
  (
    code: SyncReportCode.quarantinedRecord,
    peerId: null,
    group: SyncNoticeGroup.quarantinedLocal,
  ),
  (
    code: SyncReportCode.quarantinedRecord,
    peerId: 'peer-1',
    group: SyncNoticeGroup.skippedRecord,
  ),
  (
    code: SyncReportCode.clockSuspect,
    peerId: 'peer-1',
    group: SyncNoticeGroup.clock,
  ),
  (
    code: SyncReportCode.concurrentLocalChange,
    peerId: 'peer-1',
    group: SyncNoticeGroup.deferredInbound,
  ),
  // Always names the peer that is not taking the records: the notice is per
  // device.
  (
    code: SyncReportCode.unreflectedPublication,
    peerId: 'peer-1',
    group: SyncNoticeGroup.unreflectedPublication,
  ),
  // Always a null peerId by the code's own contract: the unreadable row is on
  // this device and no peer is involved.
  (
    code: SyncReportCode.withheldUnreadableRecord,
    peerId: null,
    group: SyncNoticeGroup.withheldUnreadableLocal,
  ),
];

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('a withheld unreadable record maps to its own local notice', () {
    expect(
      syncNoticeGroupFor(_report(SyncReportCode.withheldUnreadableRecord)),
      SyncNoticeGroup.withheldUnreadableLocal,
    );
  });

  test('its notice is not the inbound skipped-record copy', () {
    // The whole reason for a separate code. `settingsSyncNoticeSkippedRecord`
    // says the records came "from another device" and tells the user to check
    // that device's app version — false in both halves for a row stored here,
    // and the reuse a future simplification would reach for.
    final text = syncNoticeText(
      l10n,
      SyncNoticeGroup.withheldUnreadableLocal,
      recordCount: 0,
    );

    expect(text, isNotEmpty);
    expect(text, isNot(equals(l10n.settingsSyncNoticeSkippedRecord)));
    expect(text, isNot(equals(l10n.settingsSyncNoticeQuarantinedLocal)));
  });

  test('it renders as a notice group, so a report reaches the surface', () {
    expect(
      syncNoticeGroups([_report(SyncReportCode.withheldUnreadableRecord)]),
      contains(SyncNoticeGroup.withheldUnreadableLocal),
    );
  });

  group('a peer on a newer app version', () {
    test('is its own notice, not the generic skipped-record one', () {
      // The generic notice tells the user to check their *other* devices.
      // A newer envelope is never their fault: this device is the one to
      // update.
      expect(
        syncNoticeText(l10n, SyncNoticeGroup.newerVersion, recordCount: 4),
        'Another device is using a newer version of the app. Update the app '
        'on this device to receive 4 items.',
      );
    });

    test('says so without a count when no record could be named', () {
      expect(
        syncNoticeText(l10n, SyncNoticeGroup.newerVersion, recordCount: 0),
        l10n.settingsSyncNoticeNewerVersionUncounted,
      );
    });

    test('needs you, and is shown once rather than per device', () {
      // Its remedy is on this device, whichever device raised it.
      expect(syncNoticeNeedsYou(SyncNoticeGroup.newerVersion), isTrue);
      expect(syncNoticeIsPerDevice(SyncNoticeGroup.newerVersion), isFalse);
    });

    test('the needs-you groups are exactly the newer version and a device '
        'not taking changes', () {
      expect(
        [
          for (final group in SyncNoticeGroup.values)
            if (syncNoticeNeedsYou(group)) group,
        ],
        [SyncNoticeGroup.newerVersion, SyncNoticeGroup.unreflectedPublication],
      );
    });
  });

  group('every code maps to the group it is meant to', () {
    // The switch being exhaustive makes an UNHANDLED code fail the build. An
    // arm pointed at the wrong group compiles perfectly and shows the user a
    // plausible false notice: `malformedRecord` renders "records from another
    // device couldn't be used ... check that your other devices are running the
    // same app version", which sends someone to a device that is fine if it is
    // ever attached to a local-only condition. Nothing but this table catches
    // that.
    for (final expected in _expected) {
      final peer = expected.peerId == null ? 'local' : 'from a peer';
      test('${expected.code.name} ($peer)', () {
        expect(
          syncNoticeGroupFor(_report(expected.code, peerId: expected.peerId)),
          expected.group,
        );
      });
    }

    test('the table covers every code, so a new one cannot slip in', () {
      // The half that makes this a standing guard rather than a snapshot. A
      // code added with a wrong arm passes the build; it fails here only
      // because adding it without a table row fails here first.
      expect(
        {for (final c in _expected) c.code},
        SyncReportCode.values.toSet(),
        reason:
            'every SyncReportCode needs a row stating the group it must map '
            'to; add one when you add a code',
      );
    });

    test('the table reaches every group, so none is left orphaned', () {
      // Catches the other direction: an arm redirected away from a group can
      // leave that group unreachable, so a condition the surface was built to
      // report stops being reported at all while every per-code assertion
      // above still passes.
      expect({
        for (final c in _expected) c.group,
      }, SyncNoticeGroup.values.toSet());
    });
  });

  test('every report code still resolves to a distinct, non-empty notice', () {
    // Guards the mapping the new code joined, rather than only the new code:
    // the build catches an unhandled arm, nothing catches an arm pointed at
    // the wrong group or a group pointed at an empty string.
    // A per-device group's text needs the device; any will do here.
    String text(SyncNoticeGroup group) => syncNoticeText(
      l10n,
      group,
      recordCount: 0,
      device: syncNoticeIsPerDevice(group) ? (tag: 'k7mQ2x', count: 2) : null,
    );
    for (final code in SyncReportCode.values) {
      final group = syncNoticeGroupFor(_report(code));
      expect(text(group), isNotEmpty, reason: code.name);
    }
    final texts = {for (final group in SyncNoticeGroup.values) text(group)};
    expect(
      texts,
      hasLength(SyncNoticeGroup.values.length),
      reason: 'two groups sharing one string would make them indistinguishable',
    );
  });

  group('a device that is syncing but not taking changes', () {
    SyncReport refused(String peerId, String recordId) => SyncReport(
      code: SyncReportCode.unreflectedPublication,
      kind: SyncRecordKind.dance,
      recordId: recordId,
      peerId: peerId,
      message: 'diagnostic',
    );

    test('needs you, and is the one group shown per device', () {
      expect(
        syncNoticeNeedsYou(SyncNoticeGroup.unreflectedPublication),
        isTrue,
      );
      for (final group in SyncNoticeGroup.values) {
        final perDevice = group == SyncNoticeGroup.unreflectedPublication;
        expect(syncNoticeIsPerDevice(group), perDevice, reason: group.name);
      }
    });

    test('lists each device it names once, in report order', () {
      expect(
        syncNoticePeerIds(SyncNoticeGroup.unreflectedPublication, [
          refused('peer-b', 'dance-1'),
          refused('peer-a', 'dance-1'),
          refused('peer-b', 'dance-2'),
          _report(SyncReportCode.malformedRecord, peerId: 'peer-c'),
        ]),
        ['peer-b', 'peer-a'],
      );
    });

    test('names the device by tag and says how many changes it is not '
        'taking', () {
      expect(
        syncNoticeText(
          l10n,
          SyncNoticeGroup.unreflectedPublication,
          recordCount: 0,
          device: (tag: '7c02Lm', count: 4),
        ),
        "Device 7c02Lm is syncing but isn't taking 4 changes from this device. "
        "They're safe here. That device may need an app update, or this device's "
        "date and time may be wrong.",
      );
    });
  });
}
