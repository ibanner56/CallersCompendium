import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../../l10n/app_localizations.dart';

/// Which batch operation the dialog is picking tags for.
enum BatchTagMode { add, remove }

/// Shows the batch-tag picker for the Collection multi-select flow
/// (`docs/design/ux.md` §1).
///
/// - [BatchTagMode.add] lists **all** existing tags and offers inline creation
///   of a new tag (minted with [uuidV4] and persisted via
///   [TagRepository.upsert]); the returned set is the tags to union into every
///   selected dance.
/// - [BatchTagMode.remove] lists only [presentTags] (the tags currently on the
///   selected dances); the returned set is subtracted from every selected
///   dance.
///
/// Returns the chosen tag ids, or `null` if the user cancelled. Selection uses
/// [CheckboxListTile] so state is exposed to assistive tech (checkbox role +
/// checked state) and paired with a text label — never color alone.
Future<Set<String>?> showBatchTagDialog(
  BuildContext context, {
  required BatchTagMode mode,
  required List<Tag> tags,
  Set<String>? presentTagIds,
}) {
  final visible = mode == BatchTagMode.remove
      ? tags.where((t) => presentTagIds?.contains(t.id) ?? false).toList()
      : List<Tag>.of(tags);
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => _BatchTagDialog(mode: mode, initialTags: visible),
  );
}

class _BatchTagDialog extends StatefulWidget {
  const _BatchTagDialog({required this.mode, required this.initialTags});

  final BatchTagMode mode;
  final List<Tag> initialTags;

  @override
  State<_BatchTagDialog> createState() => _BatchTagDialogState();
}

class _BatchTagDialogState extends State<_BatchTagDialog> {
  late List<Tag> _tags = List.of(widget.initialTags)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final _selected = <String>{};
  final _newTagController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty || _creating) return;
    // Reuse an existing tag with the same (case-insensitive) name instead of
    // minting a duplicate.
    Tag? existing;
    for (final t in _tags) {
      if (t.name.toLowerCase() == name.toLowerCase()) {
        existing = t;
        break;
      }
    }
    if (existing != null) {
      final reused = existing;
      setState(() {
        _selected.add(reused.id);
        _newTagController.clear();
      });
      return;
    }
    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final minted = Tag(id: uuidV4(), name: name);
    final Tag tag;
    try {
      // The repository may adopt a soft-deleted tag holding this name and
      // return its id instead of the minted one (schema v25, #898), so build
      // the local Tag from what it actually wrote.
      tag = Tag(id: await repos.tags.upsert(minted), name: name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _creating = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.collectionCreateTagError)),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _tags = [..._tags, tag]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selected.add(tag.id);
      _newTagController.clear();
      _creating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdd = widget.mode == BatchTagMode.add;
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('batch-tag-dialog'),
      title: Text(isAdd ? l10n.collectionAddTags : l10n.collectionRemoveTags),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  isAdd
                      ? l10n.collectionBatchTagEmptyAdd
                      : l10n.collectionBatchTagEmptyRemove,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in _tags)
                      CheckboxListTile(
                        key: ValueKey('batch-tag-option-${tag.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(tag.id),
                        onChanged: (checked) => setState(() {
                          if (checked ?? false) {
                            _selected.add(tag.id);
                          } else {
                            _selected.remove(tag.id);
                          }
                        }),
                        secondary: const Icon(Icons.label_outline),
                        title: Text(tag.name),
                      ),
                  ],
                ),
              ),
            if (isAdd) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('batch-new-tag-field'),
                      controller: _newTagController,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.collectionCreateTagLabel,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _createTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('batch-create-tag'),
                    tooltip: l10n.collectionCreateTagButton,
                    icon: const Icon(Icons.add),
                    onPressed: _creating ? null : _createTag,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('batch-tag-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('batch-tag-confirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<String>.of(_selected)),
          child: Text(
            isAdd
                ? l10n.collectionBatchTagAddConfirm
                : l10n.collectionBatchTagRemoveConfirm,
          ),
        ),
      ],
    );
  }
}
