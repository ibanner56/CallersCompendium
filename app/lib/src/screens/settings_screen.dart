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
    // Update UI and the live notifier immediately so the selection feels
    // instant, then persist in the background.
    ActiveDialectScope.notifierOf(context).value = dialect;
    setState(() => _selected = dialect);
    // Fire-and-forget: store the selection; if the app crashes between here
    // and storage completing the write, the in-memory notifier was already
    // correct for this session.
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kActiveDialectKey, dialect.name);
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
