// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'dart:async';

import 'package:compendium_core/compendium_core.dart' show EventRuleOrder;
import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../diagnostics/error_log.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/settings_dropdown_row.dart';
import '../../data/backup_io.dart';
import '../../data/event_rules_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/show_glossary_scope.dart';
import '../../data/show_repertoire_scope.dart';
import '../../data/weekends_and_series_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/section_header.dart';
import '../glossary/custom_figures_screen.dart';
import 'calling_card_section.dart';
import 'developer_options_section.dart';
import 'device_sync_section.dart';
import 'event_rules_screen.dart';
import 'suggestion_settings_screen.dart';

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
        const _RepertoireSection(),
        const SuggestionsSection(),
        const EventRulesSection(),
        const WeekendsAndSeriesSection(),
        const CallingCardSection(),
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

/// The Event rules section (#2340): a switch, off by default, and once it is
/// on, **Manage rules**. Settings ▸ Program links to the same manager while
/// the switch is on; the switch itself is only here.
class EventRulesSection extends StatelessWidget {
  const EventRulesSection({super.key});

  Future<void> _onChanged(BuildContext context, bool value) async {
    // Flip the live notifier first so the builder and Settings ▸ Program
    // update at once, then persist.
    EventRulesEnabledScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kEventRulesEnabledKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = EventRulesEnabledScope.of(context);
    return CollapsibleSection(
      sectionKey: const ValueKey('event-rules-section'),
      title: l10n.settingsExperimentalEventRulesHeader,
      expanded: enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            key: const ValueKey('experimental-event-rules'),
            secondary: const Icon(Icons.rule),
            value: enabled,
            onChanged: (value) => _onChanged(context, value),
            title: Text(l10n.settingsExperimentalEventRulesTitle),
            subtitle: Text(l10n.settingsExperimentalEventRulesSubtitle),
            isThreeLine: true,
          ),
          if (enabled)
            ListTile(
              key: const ValueKey('experimental-manage-event-rules'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.eventRulesManageTitle),
              subtitle: Text(l10n.eventRulesManageSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EventRulesScreen(),
                ),
              ),
            ),
          if (enabled) const _EventRuleOrderTile(),
        ],
      ),
    );
  }
}

/// The Weekends and series section (#2349): one switch, off by default. While
/// it is on, the Programs list's ⋮ menu offers **Select programs**, whose
/// selection bar opens the combined view of several programs.
class WeekendsAndSeriesSection extends StatelessWidget {
  const WeekendsAndSeriesSection({super.key});

  Future<void> _onChanged(BuildContext context, bool value) async {
    // Flip the live notifier first so the Programs list updates at once, then
    // persist.
    WeekendsAndSeriesScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kWeekendsAndSeriesEnabledKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = WeekendsAndSeriesScope.of(context);
    return CollapsibleSection(
      sectionKey: const ValueKey('weekends-and-series-section'),
      title: l10n.settingsExperimentalSeriesHeader,
      expanded: enabled,
      child: SwitchListTile(
        key: const ValueKey('experimental-weekends-and-series'),
        secondary: const Icon(Icons.table_chart_outlined),
        value: enabled,
        onChanged: (value) => _onChanged(context, value),
        title: Text(l10n.settingsExperimentalSeriesTitle),
        subtitle: Text(l10n.settingsExperimentalSeriesSubtitle),
        isThreeLine: true,
      ),
    );
  }
}

/// **Rule order** (#2341): how a program's rule picker lists the rules, **My
/// order** (Manage rules' order, the default) or **Most used**. Reads and
/// writes `event_rule_order` itself; the picker reads it when it opens.
class _EventRuleOrderTile extends StatefulWidget {
  const _EventRuleOrderTile();

  @override
  State<_EventRuleOrderTile> createState() => _EventRuleOrderTileState();
}

class _EventRuleOrderTileState extends State<_EventRuleOrderTile> {
  EventRuleOrder _order = EventRuleOrder.manual;

  /// Re-reads the order after any write to `settings`, so a value that
  /// arrives by Device Sync or a restore shows while the section is open.
  StreamSubscription<Set<TableUpdate>>? _watch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_watch != null) return;
    final db = RepositoriesScope.of(context).db;
    _watch = db
        .tableUpdates(TableUpdateQuery.onAllTables([db.settings]))
        .listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final stored = await RepositoriesScope.of(
        context,
      ).settings.get(kEventRuleOrderKey);
      if (!mounted) return;
      final order = EventRuleOrder.fromStored(stored);
      if (order != _order) setState(() => _order = order);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'event_rule_order._load');
    }
  }

  Future<void> _set(EventRuleOrder order) {
    setState(() => _order = order);
    return persistSetting(
      RepositoriesScope.of(context).settings,
      kEventRuleOrderKey,
      order.name,
      source: 'event_rule_order._set',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsDropdownRow(
      tileKey: const ValueKey('experimental-event-rule-order'),
      title: Text(l10n.eventRulesOrderTitle),
      subtitle: Text(switch (_order) {
        EventRuleOrder.manual => l10n.eventRulesOrderManualSubtitle,
        EventRuleOrder.mostUsed => l10n.eventRulesOrderMostUsedSubtitle,
      }),
      isThreeLine: true,
      dropdownBuilder: (expanded) => AppDropdownField<EventRuleOrder>(
        key: const ValueKey('experimental-event-rule-order-field'),
        compact: true,
        fillWidth: expanded,
        value: _order,
        onChanged: (order) => unawaited(_set(order)),
        entries: [
          AppDropdownEntry(
            value: EventRuleOrder.manual,
            label: l10n.eventRulesOrderManual,
            key: const ValueKey('experimental-event-rule-order-manual'),
          ),
          AppDropdownEntry(
            value: EventRuleOrder.mostUsed,
            label: l10n.eventRulesOrderMostUsed,
            key: const ValueKey('experimental-event-rule-order-most-used'),
          ),
        ],
      ),
    );
  }
}

/// The Repertoire section (#2357): a switch that adds a Repertoire item to
/// Collection's More actions menu. It adds no navigation destination.
class _RepertoireSection extends StatelessWidget {
  const _RepertoireSection();

  Future<void> _onChanged(BuildContext context, bool value) async {
    // Flip the live notifier first so Collection's menu updates at once, then
    // persist.
    ShowRepertoireScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kShowRepertoireDashboardKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final show = ShowRepertoireScope.of(context);
    return CollapsibleSection(
      sectionKey: const ValueKey('repertoire-section'),
      title: l10n.settingsExperimentalRepertoireHeader,
      expanded: show,
      child: SwitchListTile(
        key: const ValueKey('experimental-show-repertoire'),
        secondary: const Icon(Icons.insights_outlined),
        value: show,
        onChanged: (value) => _onChanged(context, value),
        title: Text(l10n.settingsExperimentalShowRepertoireTitle),
        subtitle: Text(l10n.settingsExperimentalShowRepertoireSubtitle),
        isThreeLine: true,
      ),
    );
  }
}
