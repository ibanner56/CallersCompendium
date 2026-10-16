import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../glossary/cc_term_import.dart';

/// The opt-in step, after a Caller's Companion file is imported, that offers
/// its terms for the user's Glossary (#1023, maintainer decision 7), each as a
/// [CcTermDraft] the user can edit first.
///
/// A term is ticked when it can be added: it has a name, a definition and a
/// description (#709), and its name is free. As the maintainer decided
/// (2026-10-16):
/// - its description starts as its definition;
/// - one with no definition is offered unticked, and says so, until the user
///   gives it one;
/// - one whose name is taken ([nameTaken], or an earlier term in the file)
///   can't be ticked, and says so: it can be left out, or renamed and added.
///   It is never added to be marked *Rename needed*.
///
/// Pops the drafts to add; empty when the user skips.
class ImportCcTermsScreen extends StatefulWidget {
  const ImportCcTermsScreen({
    super.key,
    required this.terms,
    required this.nameTaken,
  });

  final List<CcTerm> terms;

  /// Whether [name], as typed, is taken by anything outside this file: a
  /// shipped figure, a dialect's name for one, a shorthand, or an entry of
  /// the user's own.
  final bool Function(String name) nameTaken;

  @override
  State<ImportCcTermsScreen> createState() => _ImportCcTermsScreenState();
}

class _ImportCcTermsScreenState extends State<ImportCcTermsScreen> {
  late final List<CcTermDraft> _drafts = [
    for (final term in widget.terms) CcTermDraft.of(term),
  ];
  final Set<int> _ticked = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _drafts.length; i++) {
      if (_addable(i)) _ticked.add(i);
    }
  }

  /// Whether the term at [index] has a name another has: outside the file,
  /// or an earlier term in it.
  bool _taken(int index) {
    final name = normalizeGlossaryName(_drafts[index].name);
    if (widget.nameTaken(_drafts[index].name)) return true;
    for (var i = 0; i < index; i++) {
      if (normalizeGlossaryName(_drafts[i].name) == name) return true;
    }
    return false;
  }

  bool _addable(int index) => _drafts[index].complete && !_taken(index);

  /// Unticks every term that can no longer be added, as after an edit
  /// renames an earlier term to a later one's name.
  void _settle() => _ticked.removeWhere((i) => !_addable(i));

  Future<void> _edit(int index) async {
    final edited = await showDialog<CcTermDraft>(
      context: context,
      builder: (_) => _EditTermDialog(draft: _drafts[index]),
    );
    if (edited == null || !mounted) return;
    setState(() {
      _drafts[index] = edited;
      _settle();
      if (_addable(index)) _ticked.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importCcTermsTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.importCcTermsIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          for (var i = 0; i < _drafts.length; i++) _tile(context, i),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                key: const ValueKey('cc-term-import-skip'),
                onPressed: () =>
                    Navigator.of(context).pop(const <CcTermDraft>[]),
                child: Text(l10n.importCcTermsSkip),
              ),
              FilledButton(
                key: const ValueKey('cc-term-import-confirm'),
                onPressed: _ticked.isEmpty
                    ? null
                    : () => Navigator.of(context).pop([
                        for (var i = 0; i < _drafts.length; i++)
                          if (_ticked.contains(i)) _drafts[i],
                      ]),
                child: Text(l10n.importCcTermsConfirm(_ticked.length)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final draft = _drafts[index];
    final taken = _taken(index);
    final problems = {
      if (taken) 'taken': l10n.importCcTermsNameTaken,
      if (draft.definition.trim().isEmpty)
        'needs-definition': l10n.importCcTermsNeedsDefinition,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          key: ValueKey('cc-term-import-$index'),
          value: _ticked.contains(index),
          onChanged: _addable(index)
              ? (value) => setState(
                  () => value == true
                      ? _ticked.add(index)
                      : _ticked.remove(index),
                )
              : null,
          title: Text(draft.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (draft.definition.trim().isNotEmpty) Text(draft.definition),
              if (draft.source case final source?)
                Text(
                  l10n.glossaryTermSource(source),
                  style: theme.textTheme.bodySmall,
                ),
              if (draft.notes case final notes?)
                Text(
                  '${l10n.glossaryNotes}: $notes',
                  style: theme.textTheme.bodySmall,
                ),
              for (final MapEntry(key: kind, value: problem)
                  in problems.entries)
                Text(
                  problem,
                  key: ValueKey('cc-term-import-$kind-$index'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 56, bottom: 8),
          child: TextButton.icon(
            key: ValueKey('cc-term-import-edit-$index'),
            onPressed: () => _edit(index),
            icon: const Icon(Icons.edit_outlined),
            // Named, so a screen reader says which term it edits.
            label: Semantics(
              label: l10n.importCcTermsEditLabel(draft.name),
              excludeSemantics: true,
              child: Text(l10n.commonEdit),
            ),
          ),
        ),
      ],
    );
  }
}

/// Edits a draft's name, definition and description before it is added.
class _EditTermDialog extends StatefulWidget {
  const _EditTermDialog({required this.draft});

  final CcTermDraft draft;

  @override
  State<_EditTermDialog> createState() => _EditTermDialogState();
}

class _EditTermDialogState extends State<_EditTermDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.draft.name,
  );
  late final TextEditingController _definition = TextEditingController(
    text: widget.draft.definition,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.draft.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _definition.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.importCcTermsEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('cc-term-edit-name'),
              controller: _name,
              maxLength: maxUserGlossaryNameLength,
              decoration: InputDecoration(labelText: l10n.compoundEditorName),
            ),
            TextField(
              key: const ValueKey('cc-term-edit-definition'),
              controller: _definition,
              minLines: 1,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.compoundEditorDefinition,
              ),
            ),
            TextField(
              key: const ValueKey('cc-term-edit-description'),
              controller: _description,
              minLines: 1,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.compoundEditorDescription,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('cc-term-edit-save'),
          onPressed: () => Navigator.of(context).pop(
            widget.draft.copyWith(
              name: _name.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
              definition: _definition.text,
              description: _description.text,
            ),
          ),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
