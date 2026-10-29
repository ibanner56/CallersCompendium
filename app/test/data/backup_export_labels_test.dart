import 'dart:io';

import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/data/backup_export_labels.dart';
import 'package:compendium_app/src/data/backup_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('the size limit names both sizes', () {
    expect(
      backupExportFailureMessage(
        l10n,
        const BackupExportTooLargeException(
          sizeBytes: 60 * 1024 * 1024,
          maxBytes: 50 * 1024 * 1024,
        ),
      ),
      l10n.backupExportTooLarge('60.0', '50.0'),
    );
  });

  test('no room to replace a backup names what it needs and what is free', () {
    expect(
      backupExportFailureMessage(
        l10n,
        const BackupDiskFullException(
          requiredBytes: 31 * 1024 * 1024,
          availableBytes: 12 * 1024 * 1024,
        ),
      ),
      l10n.backupExportDiskFull('31.0', '12.0'),
    );
  });

  test('anything else is the generic failure, never the raw error', () {
    for (final error in <Object>[
      const FileSystemException('No space left on device', '/Users/me/b.json'),
      StateError('boom'),
    ]) {
      expect(backupExportFailureMessage(l10n, error), l10n.backupExportFailed);
    }
  });
}
