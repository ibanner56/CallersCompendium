import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../theme/app_spacing.dart';
import '../widgets/color_edit_dialog.dart';
import '../widgets/section_header.dart';
import '../widgets/tag_chip.dart';

/// Settings screen for the user's per-tag chip colours (issue #786).
///
/// Mirrors the formation-colours screen (issue #367): a list of the things that
/// can carry a colour, each row previewing the exact chip the rest of the app
/// renders, tapping a row opens the shared [ColorEditDialog], and a coloured
/// row exposes a reset action. Colour is override-only — a tag with no colour
/// renders exactly as it always has, so this screen has no on/off switch: the
/// off state is simply not assigning a colour.
///
/// This is deliberately *only* colours. Tags still have no rename or delete UI
/// anywhere in the app; adding them is a separate piece of work with its own
/// design questions (merging on a rename collision, what a delete tells the
/// user about the dances that lose the tag).
class TagColorsScreen extends StatefulWidget {
  const TagColorsScreen({super.key});

  @override
  State<TagColorsScreen> createState() => _TagColorsScreenState();
}

class _TagColorsScreenState extends State<TagColorsScreen> {
  late CompendiumRepositories _repos;
  bool _started = false;

  List<Tag> _tags = [];
  bool _loading = true;
  Object? _loadError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repos = RepositoriesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    try {
      final tags = await _repos.tags.listAll();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _setColor(Tag tag, int? color) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final updated = tag.withColor(color);
    try {
      await _repos.tags.upsert(updated);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsTagColoursSaveError)),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _tags = [
        for (final t in _tags)
          if (t.id == tag.id) updated else t,
      ];
    });
  }

  Future<void> _edit(Tag tag) async {
    // Seed from the tag's current colour, else the theme's primary so the user
    // starts from an on-theme colour rather than plain black.
    final seed = tag.color == null
        ? Theme.of(context).colorScheme.primary
        : Color(tag.color!);
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorEditDialog(title: tag.name, initial: seed),
    );
    if (picked == null || !mounted) return;
    // Stored fully opaque, matching what the picker produces and what
    // `normalizeArgb` guarantees for every colour that reaches storage.
    await _setColor(tag, picked.toARGB32() | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTagColoursTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(l10n.settingsTagColoursLoadError),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: Text(
                    l10n.settingsTagColoursIntro,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (_tags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      l10n.settingsTagColoursEmpty,
                      key: const ValueKey('tag-colours-empty'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else ...[
                  SectionHeader(title: l10n.settingsTagColoursListHeader),
                  for (final tag in _tags)
                    _TagColorTile(
                      tag: tag,
                      onEdit: () => _edit(tag),
                      onReset: () => _setColor(tag, null),
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
    );
  }
}

class _TagColorTile extends StatelessWidget {
  const _TagColorTile({
    required this.tag,
    required this.onEdit,
    required this.onReset,
  });

  final Tag tag;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final coloured = tag.color != null;
    return ListTile(
      key: ValueKey('tag-color-${tag.id}'),
      // Preview the exact chip the collection and dance detail render, so what
      // the user picks here is what they get there.
      title: Align(
        alignment: Alignment.centerLeft,
        child: TagChip(name: tag.name, color: tag.color),
      ),
      subtitle: Text(
        coloured
            ? l10n.settingsTagColoursCustom
            : l10n.settingsTagColoursNoColour,
      ),
      trailing: coloured
          ? IconButton(
              key: ValueKey('tag-color-reset-${tag.id}'),
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: l10n.settingsTagColoursResetTooltip(tag.name),
              onPressed: onReset,
            )
          : const Icon(Icons.edit_outlined),
      onTap: onEdit,
    );
  }
}
