// The mapping from `SyncReportCode` to the notice a user actually reads.
//
// Written because #1347's `withheldUnreadableRecord` is the first code added
// since the mapping existed, and the mapping had no test at all: its exhaustive
// switch guarantees the build fails for an UNHANDLED code, which is a different
// thing from the code being wired to the right notice. A wrong arm compiles
// perfectly and tells the user to go and check a device that is fine.
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

  test('every report code still resolves to a distinct, non-empty notice', () {
    // Guards the mapping the new code joined, rather than only the new code:
    // the build catches an unhandled arm, nothing catches an arm pointed at
    // the wrong group or a group pointed at an empty string.
    for (final code in SyncReportCode.values) {
      final group = syncNoticeGroupFor(_report(code));
      expect(syncNoticeText(l10n, group), isNotEmpty, reason: code.name);
    }
    final texts = {
      for (final group in SyncNoticeGroup.values) syncNoticeText(l10n, group),
    };
    expect(
      texts,
      hasLength(SyncNoticeGroup.values.length),
      reason: 'two groups sharing one string would make them indistinguishable',
    );
  });
}
