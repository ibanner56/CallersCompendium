import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/walkthrough_snippet_library_scope.dart';

/// Manager for the user's personal walkthrough snippet library (#411), reached
/// from Settings › Defaults. Lists each saved per-figure snippet (a readable
/// figure label + its step text) with edit / delete actions. Editing updates
/// the GLOBAL default used wherever that figure appears; deleting removes the
/// default (dances keep any walkthrough text already written).
///
/// All snippet text is user-authored free text: it is rendered plainly (no
/// markup) and soft-clamped by the core [WalkthroughSnippetLibrary].
class WalkthroughSnippetsScreen extends StatelessWidget {
  const WalkthroughSnippetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = WalkthroughSnippetLibraryScope.of(context);
    final dialect = ActiveDialectScope.of(context);
    final renderer = FigureRenderer(contraTaxonomy);
    final l10n = AppLocalizations.of(context);

    // Precompute each snippet's display label ONCE (describeFigureSignature
    // parses + renders), then sort — instead of recomputing labels inside the
    // O(n log n) comparator, which is expensive with up to 2000 entries.
    final entries =
        controller.library.snippets.entries
            .map(
              (e) => (
                signature: e.key,
                text: e.value,
                label: describeFigureSignature(
                  e.key,
                  contraTaxonomy,
                  renderer,
                  dialect,
                ),
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsWalkthroughSnippetsHeader)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.settingsWalkthroughSnippetsDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.settingsWalkthroughSnippetsEmpty,
                key: const ValueKey('walkthrough-snippets-empty'),
              ),
            )
          else
            for (final entry in entries)
              _SnippetRow(
                key: ValueKey('walkthrough-snippet-${entry.signature}'),
                label: entry.label,
                text: renderer.renderFreeText(entry.text, dialect),
                onEdit: () => _edit(context, entry.signature, entry.text),
                onDelete: () => _delete(context, entry.signature),
              ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    String signature,
    String current,
  ) async {
    final controller = WalkthroughSnippetLibraryScope.controllerOf(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditSnippetDialog(initial: current),
    );
    if (result == null) return;
    await controller.setSnippet(signature, result);
  }

  Future<void> _delete(BuildContext context, String signature) async {
    final controller = WalkthroughSnippetLibraryScope.controllerOf(context);
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsWalkthroughSnippetDeleteTitle),
        content: Text(l10n.settingsWalkthroughSnippetDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('walkthrough-snippet-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(MaterialLocalizations.of(ctx).deleteButtonTooltip),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await controller.removeSnippet(signature);
    }
  }
}

class _SnippetRow extends StatelessWidget {
  const _SnippetRow({
    super.key,
    required this.label,
    required this.text,
    required this.onEdit,
    required this.onDelete,
  });

  final String label;
  final String text;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
      onTap: onEdit,
      trailing: IconButton(
        key: ValueKey('walkthrough-snippet-delete-$label'),
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
      ),
    );
  }
}

class _EditSnippetDialog extends StatefulWidget {
  const _EditSnippetDialog({required this.initial});

  final String initial;

  @override
  State<_EditSnippetDialog> createState() => _EditSnippetDialogState();
}

class _EditSnippetDialogState extends State<_EditSnippetDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsWalkthroughSnippetEditTitle),
      content: TextField(
        key: const ValueKey('walkthrough-snippet-edit-field'),
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        maxLength: kMaxWalkthroughSnippetLength,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('walkthrough-snippet-edit-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(MaterialLocalizations.of(context).saveButtonLabel),
        ),
      ],
    );
  }
}
