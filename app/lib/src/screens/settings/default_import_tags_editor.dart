import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/display_defaults.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/app_spacing.dart';

/// Picks the tags added to dances imported on their own (issue #1476), stored
/// under [kDefaultImportTagNamesKey].
///
/// Shows every live tag as a toggle chip. Only tags that still exist are shown
/// as selected, and every save writes back just those, so a name left behind by
/// a deleted tag is dropped the next time the selection changes. Once
/// [kMaxDefaultImportTags] are chosen the remaining chips are disabled, so the
/// stored list never silently drops a visible selection.
class DefaultImportTagsEditor extends StatefulWidget {
  const DefaultImportTagsEditor({super.key});

  @override
  State<DefaultImportTagsEditor> createState() =>
      _DefaultImportTagsEditorState();
}

class _DefaultImportTagsEditorState extends State<DefaultImportTagsEditor> {
  List<Tag>? _tags;
  Set<String> _selected = {};
  bool _loaded = false;
  bool _userSet = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load(RepositoriesScope.of(context));
  }

  Future<void> _load(CompendiumRepositories repos) async {
    try {
      final tags = await repos.tags.listAll();
      final stored = tryDecodeDefaultImportTagNames(
        await repos.settings.get(kDefaultImportTagNamesKey),
      );
      if (!mounted || _userSet) return;
      final idByName = {for (final tag in tags) tag.name: tag.id};
      setState(() {
        _tags = tags;
        _selected = {
          for (final name in stored ?? const <String>[]) ?idByName[name],
        };
      });
    } catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'DefaultImportTagsEditor._load');
      if (mounted && !_userSet) setState(() => _tags = const []);
    }
  }

  Future<void> _toggle(Tag tag, bool selected) async {
    final tags = _tags;
    if (tags == null) return;
    final repos = RepositoriesScope.of(context);
    setState(() {
      _userSet = true;
      if (selected) {
        _selected.add(tag.id);
      } else {
        _selected.remove(tag.id);
      }
    });
    // List order, not insertion order, so the stored value is stable.
    final names = [
      for (final t in tags)
        if (_selected.contains(t.id)) t.name,
    ];
    await persistSetting(
      repos.settings,
      kDefaultImportTagNamesKey,
      encodeDefaultImportTagNames(names),
      source: 'DefaultImportTagsEditor._toggle',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = _tags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsDefaultsImportTagsTitle),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsDefaultsImportTagsSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (tags != null && tags.isEmpty)
            Text(l10n.settingsDefaultsImportTagsEmpty)
          else if (tags != null)
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final tag in tags)
                  FilterChip(
                    key: ValueKey('defaults-import-tag-${tag.id}'),
                    label: Text(tag.name),
                    selected: _selected.contains(tag.id),
                    onSelected:
                        _selected.contains(tag.id) ||
                            _selected.length < kMaxDefaultImportTags
                        ? (value) => _toggle(tag, value)
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
