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
      ],
    );
  }
}

/// The Glossary and Custom Figures section (issues #695, #709): a switch that
/// adds or removes the Glossary navigation destination, and nested under it a
/// switch for the user's own compound figures.
///
/// The nested switch stays visible but disabled while the Glossary is off,
/// keeping its value, as the figure-shorthands entry does under free-text
/// entry: turning the Glossary back on restores it as it was.
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
      expanded: show,
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
            onChanged: show
                ? (value) => _onCustomChanged(context, value)
                : null,
            title: Text(l10n.settingsExperimentalShowCustomFiguresTitle),
            subtitle: Text(
              show
                  ? l10n.settingsExperimentalShowCustomFiguresSubtitle
                  : l10n.settingsExperimentalShowCustomFiguresNeedsGlossary,
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}
