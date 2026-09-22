// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/backup_io.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';
import 'device_sync_section.dart';

/// The Experimental settings section for features still in development.
class ExperimentalSection extends StatelessWidget {
  const ExperimentalSection({super.key, this.backupSaver});

  /// Test seam forwarded to Device Sync pairing's backup offer; defaults to
  /// [saveBackupToFile].
  final BackupSaver? backupSaver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      children: [
        SectionHeader(title: l10n.settingsExperimentalTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(l10n.settingsExperimentalPlaceholder),
        ),
        DeviceSyncSection(backupSaver: backupSaver),
      ],
    );
  }
}
