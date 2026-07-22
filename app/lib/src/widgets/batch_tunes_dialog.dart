import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shows the batch **add tunes** picker for the Collection multi-select flow.
///
/// Mirrors the tag *add* model: the returned set is the tunes to **union** into
/// every selected dance (existing tunes are preserved; nothing is removed —
/// removal is a separate "clear tunes" action). The user types free-text tune
/// names and adds each to a pending list; blanks and case-sensitive duplicates
/// are ignored, matching the single-dance edit path.
///
/// Returns the tunes to add, or `null` if the user cancelled. Each pending tune
/// is a [ListTile] with a labelled remove button, so state is exposed to
/// assistive tech with text — never color alone.
Future<Set<String>?> showBatchTunesDialog(BuildContext context) {
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => const _BatchTunesDialog(),
  );
}

class _BatchTunesDialog extends StatefulWidget {
  const _BatchTunesDialog();

  @override
  State<_BatchTunesDialog> createState() => _BatchTunesDialogState();
}

class _BatchTunesDialogState extends State<_BatchTunesDialog> {
  // Order-preserving pending list; duplicates are rejected on add.
  final List<String> _tunes = [];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTune() {
    final tune = _controller.text.trim();
    if (tune.isEmpty || _tunes.contains(tune)) {
      _controller.clear();
      return;
    }
    setState(() {
      _tunes.add(tune);
      _controller.clear();
    });
  }

  void _removeTune(String tune) => setState(() => _tunes.remove(tune));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('batch-tunes-dialog'),
      title: Text(l10n.collectionAddTunes),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tunes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.collectionBatchTunesEmpty),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tune in _tunes)
                      ListTile(
                        key: ValueKey('batch-tunes-item-$tune'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.music_note_outlined),
                        title: Text(tune),
                        trailing: IconButton(
                          key: ValueKey('batch-tunes-remove-$tune'),
                          tooltip: l10n.collectionBatchTunesRemove(tune),
                          icon: const Icon(Icons.close),
                          onPressed: () => _removeTune(tune),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('batch-tunes-field'),
                    controller: _controller,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.collectionBatchTunesFieldLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTune(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('batch-tunes-add'),
                  tooltip: l10n.collectionBatchTunesAddButton,
                  icon: const Icon(Icons.add),
                  onPressed: _addTune,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('batch-tunes-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('batch-tunes-confirm'),
          onPressed: _tunes.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<String>.of(_tunes)),
          child: Text(l10n.collectionBatchTunesConfirm),
        ),
      ],
    );
  }
}
