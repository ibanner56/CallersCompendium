import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../editor/figure_draft.dart';
import '../widgets/figure_list_editor.dart';
import '../widgets/shorthand_shadow_warning.dart';
import '../widgets/app_bar_text_action.dart';

/// Full-screen editor for a single shorthand → figure(s) mapping (issue #420),
/// modeled on `dialect_editor_screen.dart`. A shorthand [token] (left) is typed
/// into a text field; the ordered figure(s) it expands to (right) are authored
/// with the SAME structured [FigureListEditor] used for normal figure entry, so
/// ordinary-figure params and taxonomy validation stay identical to hand-built
/// figures, while bounded `meanwhile`/`modifier` containers use the same
/// structural editor — there is no separate lightweight picker to keep in sync.
///
/// On Save the token is validated (non-empty, bounded length, and unique
/// case-insensitively against [existingTokens]) and the drafts are committed to
/// figures. A token that already reads as a figure when typed is warned about
/// under the field but still saves (#1827). The edited [ShorthandMapping] is
/// returned via [Navigator.pop] (or `null` on cancel / back).
class ShorthandMappingEditorScreen extends StatefulWidget {
  const ShorthandMappingEditorScreen({
    super.key,
    this.initial,
    this.existingTokens = const {},
    this.hiddenTokens = const {},
  });

  /// The mapping being edited, or `null` when creating a new one.
  final ShorthandMapping? initial;

  /// Normalized ([normalizeShorthandToken]) tokens of OTHER mappings, used to
  /// reject a case-insensitive duplicate token on Save.
  final Set<String> existingTokens;

  /// Normalized tokens of compound shorthands (#709) that the shorthands
  /// screen is not showing, because Custom Figures is off. They are taken all
  /// the same, so a clash with one names it rather than a shorthand the user
  /// cannot see.
  final Set<String> hiddenTokens;

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
    final l10n = AppLocalizations.of(context);
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = l10n.shorthandEditorErrorEmpty);
      return;
    }
    if (token.length > maxShorthandTokenLength) {
      setState(
        () =>
            _error = l10n.shorthandEditorErrorTooLong(maxShorthandTokenLength),
      );
      return;
    }
    if (widget.hiddenTokens.contains(normalizeShorthandToken(token))) {
      setState(() => _error = l10n.shorthandEditorErrorDuplicateHidden(token));
      return;
    }
    if (widget.existingTokens.contains(normalizeShorthandToken(token))) {
      setState(() => _error = l10n.shorthandEditorErrorDuplicate(token));
      return;
    }
    final figures = _figures();
    if (figures.isEmpty) {
      setState(() => _error = l10n.shorthandEditorErrorNoFigures);
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

  Future<String?> _addMeanwhile() async {
    final group = FigureDraft(meanwhileSides: [FigureDraft(), FigureDraft()])
      ..params['beats'] = 0;
    setState(() {
      _drafts.add(group);
      _error = null;
    });
    return group.id;
  }

  Future<String?> _addModifier() async {
    final group = FigureDraft(modifierFigures: [FigureDraft(), FigureDraft()])
      ..params['beats'] = 0;
    setState(() {
      _drafts.add(group);
      _error = null;
    });
    return group.id;
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
    final l10n = AppLocalizations.of(context);
    final isNew = widget.initial == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNew ? l10n.shorthandEditorTitleNew : l10n.shorthandEditorTitleEdit,
        ),
        actions: [
          AppBarTextAction(
            key: const ValueKey('shorthand-editor-save'),
            label: l10n.commonSave,
            icon: Icons.check,
            onPressed: _save,
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
              decoration: InputDecoration(
                labelText: l10n.shorthandEditorTokenLabel,
                helperText: l10n.shorthandEditorTokenHelper,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          ShorthandShadowWarning(
            warningKey: const ValueKey('shorthand-shadow-warning'),
            controller: _tokenController,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.shorthandEditorExpandsTo,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              l10n.shorthandEditorExpandsToHelp,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FigureListEditor(
              drafts: _drafts,
              taxonomy: contraTaxonomy,
              phraseStructure: PhraseStructure.standard,
              // A shorthand expands to a snippet, not a whole dance: phrase
              // labels and the beat total belong to dances only (#1830).
              showPhraseStructure: false,
              dialect: ActiveDialectScope.of(context),
              onChanged: _onFiguresChanged,
              onAdd: _addFigure,
              onAddMeanwhile: _addMeanwhile,
              onAddModifier: _addModifier,
              onDelete: _deleteFigure,
              onDuplicate: _duplicateFigure,
              onReorder: _reorderFigure,
              allowModifierSelection: true,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
