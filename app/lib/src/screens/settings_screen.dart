import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';

/// Key used to persist and load the active dialect.
const String kActiveDialectKey = 'active_dialect';

/// Settings screen.  Currently hosts the active-dialect selection; designed
/// to accommodate additional settings rows in future phases.
///
/// Changes take effect immediately (live update via [ActiveDialectScope]).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Dialect _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected = ActiveDialectScope.of(context);
  }

  Future<void> _onDialectChanged(Dialect dialect) async {
    // Persist first so a crash between update and save is harmless — the
    // notifier update is effectively fire-and-forget from the user's view.
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kActiveDialectKey, dialect.name);
    if (!mounted) return;
    // Update live: all descendants of ActiveDialectScope rebuild.
    ActiveDialectScope.notifierOf(context).value = dialect;
    setState(() => _selected = dialect);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(title: 'Dialect'),
          RadioGroup<Dialect>(
            groupValue: _selected,
            onChanged: (d) {
              if (d != null) _onDialectChanged(d);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in Dialect.presets)
                  RadioListTile<Dialect>(
                    key: ValueKey('dialect-${preset.name}'),
                    title: Text(preset.name),
                    subtitle: _dialectSubtitle(preset),
                    value: preset,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Text? _dialectSubtitle(Dialect preset) {
    if (preset.roles.isEmpty) return null;
    final terms = preset.roles.values.map((r) => r.plural).join(' / ');
    return Text(terms);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
