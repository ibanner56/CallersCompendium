// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/backup_io.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/show_glossary_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/section_header.dart';
import '../glossary/custom_figures_screen.dart';
import 'developer_options_section.dart';
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
        const _GlossarySection(),
        DeviceSyncSection(backupSaver: backupSaver),
        const DeveloperOptionsSection(),
      ],
    );
  }
}

/// The Glossary and Custom Figures section (issues #695, #709): a switch that
/// adds or removes the Glossary navigation destination, and a switch for the
/// user's own figures with, once it is on, a row that opens them to be added
/// and edited, as the figure-shorthands row does under free-text entry.
///
/// The two switches are independent: your own figures work with the Glossary
/// off, so the row is the way to reach them then.
class _GlossarySection extends StatelessWidget {
  const _GlossarySection();

  Future<void> _onChanged(BuildContext context, bool value) async {
    // Flip the live notifier first so the shell's destinations update
    // immediately, then persist.
    ShowGlossaryScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kShowGlossaryKey, value);
  }

  Future<void> _onCustomChanged(BuildContext context, bool value) async {
    ShowCustomFiguresScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kShowCustomFiguresKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final show = ShowGlossaryScope.of(context);
    final custom = ShowCustomFiguresScope.of(context);
    return CollapsibleSection(
      sectionKey: const ValueKey('glossary-section'),
      title: l10n.settingsExperimentalGlossaryHeader,
      expanded: show || custom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            key: const ValueKey('experimental-show-glossary'),
            secondary: const Icon(Icons.menu_book_outlined),
            value: show,
            onChanged: (value) => _onChanged(context, value),
            title: Text(l10n.settingsExperimentalShowGlossaryTitle),
            subtitle: Text(l10n.settingsExperimentalShowGlossarySubtitle),
            isThreeLine: true,
          ),
          SwitchListTile(
            key: const ValueKey('experimental-show-custom-figures'),
            secondary: const Icon(Icons.dashboard_customize_outlined),
            value: custom,
            onChanged: (value) => _onCustomChanged(context, value),
            title: Text(l10n.settingsExperimentalShowCustomFiguresTitle),
            subtitle: Text(l10n.settingsExperimentalShowCustomFiguresSubtitle),
            isThreeLine: true,
          ),
          ListTile(
            key: const ValueKey('experimental-custom-figures-open'),
            enabled: custom,
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.settingsExperimentalCustomFiguresManageTitle),
            subtitle: Text(
              l10n.settingsExperimentalCustomFiguresManageSubtitle,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: custom
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CustomFiguresScreen(),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
