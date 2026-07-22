import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../editor/figure_draft.dart';
import '../widgets/figure_list_editor.dart';

/// Full-screen editor for a single shorthand → figure(s) mapping (issue #420),
/// modeled on `dialect_editor_screen.dart`. A shorthand [token] (left) is typed
/// into a text field; the ordered figure(s) it expands to (right) are authored
/// with the SAME structured [FigureListEditor] used for normal figure entry, so
/// params and taxonomy validation are identical to hand-built figures — there
/// is no separate lightweight picker to keep in sync.
///
/// On Save the token is validated (non-empty, bounded length, and unique
/// case-insensitively against [existingTokens]) and the drafts are committed to
/// figures; the edited [ShorthandMapping] is returned via [Navigator.pop] (or
/// `null` on cancel / back).
class ShorthandMappingEditorScreen extends StatefulWidget {
  const ShorthandMappingEditorScreen({
    super.key,
    this.initial,
    this.existingTokens = const {},
  });

  /// The mapping being edited, or `null` when creating a new one.
  final ShorthandMapping? initial;

  /// Normalized ([normalizeShorthandToken]) tokens of OTHER mappings, used to
  /// reject a case-insensitive duplicate token on Save.
  final Set<String> existingTokens;

  @override
  State<ShorthandMappingEditorScreen> createState() =>
      _ShorthandMappingEditorScreenState();
}

class _ShorthandMappingEditorScreenState
    extends State<ShorthandMappingEditorScreen> {
  final _tokenController = TextEditingController();

  /// The live draft list backing the target-figure builder. Seeded from the
  /// mapping being edited (if any).
  late final List<FigureDraft> _drafts;

  /// The current validation error shown inline above the editor, or `null`.
  String? _error;

  @override
  void initState() {
    super.initState();
    _tokenController.text = widget.initial?.token ?? '';
    _drafts = [
      for (final figure in widget.initial?.figures ?? const <Figure>[])
        FigureDraft.fromFigure(figure),
    ];
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  /// Commits the current drafts to figures, dropping blank (move-less) rows.
  List<Figure> _figures() => [for (final d in _drafts) ?d.toFigure()];

  /// Validates the token + figures and returns the edited mapping, or surfaces
  /// an inline error and keeps the editor open.
  void _save() {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Enter a shorthand token.');
      return;
    }
    if (token.length > maxShorthandTokenLength) {
      setState(
        () => _error =
            'Shorthand is too long (max $maxShorthandTokenLength characters).',
      );
      return;
    }
    if (widget.existingTokens.contains(normalizeShorthandToken(token))) {
      setState(
        () => _error =
            'Another shorthand already uses "$token" '
            '(shorthands are matched case-insensitively).',
      );
      return;
    }
    final figures = _figures();
    if (figures.isEmpty) {
      setState(
        () => _error =
            'Add at least one figure for this shorthand to expand '
            'to.',
      );
      return;
    }
    Navigator.of(context).pop(ShorthandMapping(token: token, figures: figures));
  }

  void _onFiguresChanged() => setState(() => _error = null);

  void _addFigure() {
    setState(() {
      _drafts.add(FigureDraft());
      _error = null;
    });
  }

  void _deleteFigure(FigureDraft draft) {
    setState(() {
      _drafts.remove(draft);
      _error = null;
    });
  }

  void _duplicateFigure(FigureDraft draft) {
    setState(() {
      final index = _drafts.indexOf(draft);
      if (index == -1) return;
      _drafts.insert(index + 1, draft.clone());
      _error = null;
    });
  }

  void _reorderFigure(int oldIndex, int newIndex) {
    setState(() {
      final draft = _drafts.removeAt(oldIndex);
      _drafts.insert(newIndex, draft);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.initial == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New shorthand' : 'Edit shorthand'),
        actions: [
          TextButton(
            key: const ValueKey('shorthand-editor-save'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _error!,
                key: const ValueKey('shorthand-validation-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const ValueKey('shorthand-token-field'),
              controller: _tokenController,
              maxLength: maxShorthandTokenLength,
              autofocus: isNew,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(
                labelText: 'Shorthand',
                helperText:
                    'Type this exact line during free-text entry to insert '
                    'the figures below. Matched case-insensitively.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Expands to',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'The figure(s) this shorthand inserts, in order. Built exactly '
              'like a normal figure, so parameters and validation are the same.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FigureListEditor(
              drafts: _drafts,
              taxonomy: contraTaxonomy,
              phraseStructure: PhraseStructure.standard,
              dialect: ActiveDialectScope.of(context),
              onChanged: _onFiguresChanged,
              onAdd: _addFigure,
              onDelete: _deleteFigure,
              onDuplicate: _duplicateFigure,
              onReorder: _reorderFigure,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
