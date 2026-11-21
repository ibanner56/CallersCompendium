import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/data/file_dialog_labels.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/diagnostics/crash_log_io.dart';
import 'package:compendium_app/src/update/artifact_destination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(FileDialogLabels.unbind);

  test(
    'file-dialog filter names are English until the app binds a language',
    () {
      expect(backupJsonTypeGroup().label, 'Backup (JSON)');
      expect(importJsonTypeGroup().label, 'Compendium share');
      expect(importUsrTypeGroup().label, "Caller's Companion .USR");
      expect(crashLogTypeGroup().label, 'Diagnostics log');
      expect(macosUpdateTypeGroup().label, "Caller's Compendium update");
    },
  );

  test('file-dialog filter names follow the bound language', () async {
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    FileDialogLabels.bind(ja);

    expect(backupJsonTypeGroup().label, ja.fileDialogTypeBackupJson);
    expect(importJsonTypeGroup().label, ja.fileDialogTypeCompendiumShare);
    expect(importUsrTypeGroup().label, ja.fileDialogTypeCompanionUsr);
    expect(crashLogTypeGroup().label, ja.fileDialogTypeDiagnosticsLog);
    expect(macosUpdateTypeGroup().label, ja.fileDialogTypeMacosUpdate);
    expect(backupJsonTypeGroup().label, isNot('Backup (JSON)'));
    expect(crashLogTypeGroup().label, '診断ログ');
  });
}
