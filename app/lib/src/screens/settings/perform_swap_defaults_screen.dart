// Settings ▸ Program ▸ Perform mode ▸ Swap a dance (#2346).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/settings_keys.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/app_spacing.dart';

/// **Swap a dance**: which of the four seeded **Keep** items are on when
/// Perform's swap sheet opens. Figures to keep always start off.
///
/// The value is read when the screen opens, and each switch writes the whole
/// value at once ([PerformSwapDefaults.toJson]), keeping what this build does
/// not understand. A value saved by a newer build
/// ([PerformSwapDefaultsRead.isNewer]) is shown as the defaults, read-only,
/// with a notice: an edit here would overwrite choices this build cannot
/// read.
class PerformSwapDefaultsScreen extends StatefulWidget {
  const PerformSwapDefaultsScreen({super.key});

  @override
  State<PerformSwapDefaultsScreen> createState() =>
      _PerformSwapDefaultsScreenState();
}

class _PerformSwapDefaultsScreenState extends State<PerformSwapDefaultsScreen> {
  /// Null until the stored value is read; the switches wait for it, so a
  /// late read can never overwrite a change.
  PerformSwapDefaultsRead? _read;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kPerformSwapDefaultsKey)
        .then((stored) {
          if (!mounted) return;
          setState(() => _read = readPerformSwapDefaults(stored));
        })
        .catchError((Object error, StackTrace stackTrace) {
          logCaughtError(
            error,
            stackTrace,
            source: 'perform_swap_defaults_screen.read',
          );
          if (!mounted) return;
          // As the swap sheet does after a failed read: every item on.
          setState(
            () => _read = (
              defaults: PerformSwapDefaults.defaults,
              isNewer: false,
            ),
          );
        });
  }

  Future<void> _set(PerformSwapKeepItem item, bool on) async {
    final read = _read;
    if (read == null || read.isNewer) return;
    final next = read.defaults.withItem(item, on);
    setState(() => _read = (defaults: next, isNewer: false));
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kPerformSwapDefaultsKey,
      next.toJson(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final read = _read;
    final defaults = read?.defaults ?? PerformSwapDefaults.defaults;
    final editable = read != null && !read.isNewer;

    Widget item(PerformSwapKeepItem which, String title, {String? subtitle}) =>
        SwitchListTile(
          key: ValueKey('perform-swap-default-${which.name}'),
          value: defaults.isOn(which),
          onChanged: editable ? (on) => _set(which, on) : null,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPerformSwapTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          ListTile(title: Text(l10n.settingsPerformSwapSubtitle)),
          if (read != null && read.isNewer)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Card(
                key: const ValueKey('perform-swap-defaults-newer'),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.settingsPerformSwapNewerVersion),
                ),
              ),
            ),
          item(
            PerformSwapKeepItem.formation,
            l10n.settingsPerformSwapFormation,
          ),
          item(
            PerformSwapKeepItem.levelOrEasier,
            l10n.settingsPerformSwapLevel,
          ),
          item(
            PerformSwapKeepItem.sameType,
            l10n.settingsPerformSwapType,
            subtitle: l10n.settingsPerformSwapTypeSubtitle,
          ),
          item(
            PerformSwapKeepItem.notInProgram,
            l10n.performSwapKeepNotInProgram,
          ),
        ],
      ),
    );
  }
}
