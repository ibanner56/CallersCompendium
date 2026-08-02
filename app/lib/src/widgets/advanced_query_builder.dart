import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/collection_query.dart';
import '../search/collection_query_labels.dart';
import '../search/facet_labels.dart';
import 'responsive_autocomplete.dart';

/// The "Advanced" boolean-tree query builder (`docs/design/search.md`
/// "Query-builder UX"). Edits the mutable [BuilderGroup] [root] in place and
/// calls [onChanged] after every edit so the parent recompiles and re-runs the
/// search. Uses plain language ("All of / Any of / None of", "Has figure",
/// "then") rather than raw AST names.
class AdvancedQueryBuilder extends StatelessWidget {
  const AdvancedQueryBuilder({
    super.key,
    required this.root,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderGroup root;
  final Taxonomy taxonomy;
  
  /// Active dialect, so figure-param choices are labelled with the user's
  /// role terminology exactly as the dance editor labels them (issue #741).
  /// Threaded explicitly rather than read from `ActiveDialectScope` so this
  /// widget has no hidden inherited dependency.
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _GroupView(
      group: root,
      taxonomy: taxonomy,
      dialect: dialect,
      sectionLabels: sectionLabels,
      onChanged: onChanged,
      onRemove: null,
      depth: 0,
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({
    required this.group,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
    required this.onRemove,
    required this.depth,
  });

  final BuilderGroup group;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: depth.isEven ? 0.3 : 0.15,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  label: l10n.collectionQueryMatchLabel,
                  child: DropdownButton<GroupKind>(
                    key: ValueKey('group-kind-${group.id}'),
                    value: group.kind,
                    onChanged: (kind) {
                      if (kind != null) {
                        group.kind = kind;
                        onChanged();
                      }
                    },
                    items: [
                      for (final kind in GroupKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(groupKindLabel(l10n, kind)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.collectionQueryTheseConditions,
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    key: ValueKey('remove-${group.id}'),
                    tooltip: l10n.collectionQueryRemoveGroup,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      onRemove!();
                      onChanged();
                    },
                  ),
              ],
            ),
            if (group.children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  l10n.collectionQueryEmptyGroup,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final child in group.children) _childView(child),
            Align(
              alignment: Alignment.centerLeft,
              child: _AddMenu(
                id: group.id,
                onAdd: (node) {
                  group.children.add(node);
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _childView(BuilderNode child) {
    void remove() => group.children.remove(child);
    switch (child) {
      case BuilderGroup():
        return _GroupView(
          group: child,
          taxonomy: taxonomy,
          dialect: dialect,
          sectionLabels: sectionLabels,
          onChanged: onChanged,
          onRemove: remove,
          depth: depth + 1,
        );
      case BuilderFigure():
        return _FigureRow(
          figure: child,
          taxonomy: taxonomy,
          dialect: dialect,
          sectionLabels: sectionLabels,
          onChanged: onChanged,
          onRemove: () {
            remove();
            onChanged();
          },
        );
      case BuilderThen():
        return _ThenRow(
          node: child,
          taxonomy: taxonomy,
          dialect: dialect,
          sectionLabels: sectionLabels,
          onChanged: onChanged,
          onRemove: () {
            remove();
            onChanged();
          },
        );
    }
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.id, required this.onAdd});

  final String id;
  final ValueChanged<BuilderNode> onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: ValueKey('add-menu-$id'),
      tooltip: l10n.collectionQueryAddCondition,
      onSelected: (value) => onAdd(switch (value) {
        'figure' => BuilderFigure(),
        'then' => BuilderThen(),
        _ => BuilderGroup(),
      }),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'figure',
          child: Text(l10n.collectionQueryHasFigure),
        ),
        PopupMenuItem(
          value: 'then',
          child: Text(l10n.collectionQuerySequenceThen),
        ),
        PopupMenuItem(
          value: 'group',
          child: Text(l10n.collectionQueryConditionGroup),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 18),
            const SizedBox(width: 4),
            Text(l10n.collectionQueryAddButton),
          ],
        ),
      ),
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.figure,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
    required this.onRemove,
  });

  final BuilderFigure figure;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 8),
            child: Text(l10n.collectionQueryHasFigure),
          ),
          Expanded(
            child: _FigureEditor(
              figure: figure,
              taxonomy: taxonomy,
              dialect: dialect,
              sectionLabels: sectionLabels,
              onChanged: onChanged,
            ),
          ),
          IconButton(
            key: ValueKey('remove-${figure.id}'),
            tooltip: l10n.collectionQueryRemoveFigure,
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ThenRow extends StatelessWidget {
  const _ThenRow({
    required this.node,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
    required this.onRemove,
  });

  final BuilderThen node;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.collectionQueryThenFirst,
                  style: theme.textTheme.labelSmall,
                ),
                _FigureOperandEditor(
                  node: node.before,
                  onReplace: (r) {
                    node.before = r;
                    onChanged();
                  },
                  taxonomy: taxonomy,
                  dialect: dialect,
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l10n.collectionQueryThenConnector,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                Text(
                  l10n.collectionQueryThenLater,
                  style: theme.textTheme.labelSmall,
                ),
                _FigureOperandEditor(
                  node: node.after,
                  onReplace: (r) {
                    node.after = r;
                    onChanged();
                  },
                  taxonomy: taxonomy,
                  dialect: dialect,
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('remove-${node.id}'),
            tooltip: l10n.collectionQueryRemoveSequence,
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Renders one operand of a [BuilderThen]: either a single [BuilderFigure]
/// leaf with a "Group figures" affordance, or a [BuilderFigureGroup] editor
/// with a "Single figure" affordance to collapse back.
///
/// [onReplace] is invoked when the operand type switches between a single
/// figure (leaf) and a group; the caller swaps in the new node and is
/// responsible for triggering a rebuild (it calls [onChanged]).
class _FigureOperandEditor extends StatelessWidget {
  const _FigureOperandEditor({
    required this.node,
    required this.onReplace,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderFigureNode node;

  /// Called when the user wants to replace this operand with a different
  /// [BuilderFigureNode] (e.g. wrapping a leaf in a group, or flattening a
  /// single-child group back to a leaf). The caller swaps in the replacement
  /// and then calls [onChanged] to rebuild/re-run the search.
  final ValueChanged<BuilderFigureNode> onReplace;

  final Taxonomy taxonomy;
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => switch (node) {
    final BuilderFigure figure => _buildLeaf(context, figure),
    final BuilderFigureGroup group => _buildGroup(context, group),
  };

  Widget _buildLeaf(BuildContext context, BuilderFigure figure) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FigureEditor(
          figure: figure,
          taxonomy: taxonomy,
          dialect: dialect,
          sectionLabels: sectionLabels,
          onChanged: onChanged,
        ),
        TextButton.icon(
          key: ValueKey('group-${figure.id}'),
          onPressed: () => onReplace(BuilderFigureGroup(children: [figure])),
          icon: const Icon(Icons.account_tree_outlined, size: 16),
          label: Text(l10n.collectionQueryGroupFigures),
        ),
      ],
    );
  }

  Widget _buildGroup(BuildContext context, BuilderFigureGroup group) {
    // Offer a "Single figure" flatten only when the group has exactly one
    // leaf child — collapsing a multi-child or nested group is lossy.
    final canFlatten =
        group.children.length == 1 && group.children.single is BuilderFigure;
    return _FigureGroupEditor(
      group: group,
      taxonomy: taxonomy,
      dialect: dialect,
      sectionLabels: sectionLabels,
      onChanged: onChanged,
      onFlatten: canFlatten
          ? () => onReplace(group.children.single as BuilderFigure)
          : null,
    );
  }
}

/// Edits a [BuilderFigureGroup]: kind picker, per-child figure rows, and an
/// "Add figure" button. Recursive: nested [BuilderFigureGroup] children are
/// rendered via the same widget (model supports arbitrary depth; UI exposes
/// at least one level of nesting).
class _FigureGroupEditor extends StatelessWidget {
  const _FigureGroupEditor({
    required this.group,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
    this.onFlatten,
  });

  final BuilderFigureGroup group;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  /// When non-null, a "Single figure" button is shown to collapse a
  /// single-leaf group back to a plain [BuilderFigure].
  final VoidCallback? onFlatten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              label: l10n.collectionQueryFigureGroupMatch,
              child: DropdownButton<GroupKind>(
                key: ValueKey('fig-group-kind-${group.id}'),
                value: group.kind,
                onChanged: (kind) {
                  if (kind != null) {
                    group.kind = kind;
                    onChanged();
                  }
                },
                items: [
                  for (final kind in GroupKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(groupKindLabel(l10n, kind)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.collectionQueryOfTheseFigures,
              style: theme.textTheme.bodySmall,
            ),
            const Spacer(),
            if (onFlatten != null)
              TextButton(
                key: ValueKey('flatten-${group.id}'),
                onPressed: onFlatten,
                child: Text(l10n.collectionQuerySingleFigure),
              ),
          ],
        ),
        for (final child in group.children) _buildChildRow(l10n, child),
        TextButton.icon(
          key: ValueKey('add-fig-${group.id}'),
          onPressed: () {
            group.children.add(BuilderFigure());
            onChanged();
          },
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.collectionQueryAddFigure),
        ),
      ],
    );
  }

  Widget _buildChildRow(AppLocalizations l10n, BuilderFigureNode child) {
    switch (child) {
      case BuilderFigure():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FigureEditor(
                  figure: child,
                  taxonomy: taxonomy,
                  dialect: dialect,
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
              ),
              IconButton(
                key: ValueKey('remove-fig-${child.id}'),
                tooltip: l10n.collectionQueryRemoveFigure,
                icon: const Icon(Icons.close),
                onPressed: () {
                  group.children.remove(child);
                  onChanged();
                },
              ),
            ],
          ),
        );
      case BuilderFigureGroup():
        // Nested group — rendered recursively. No flatten affordance for
        // nested groups (they're added programmatically, not via the UI).
        return Padding(
          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FigureGroupEditor(
                  group: child,
                  taxonomy: taxonomy,
                  dialect: dialect,
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
              ),
              IconButton(
                key: ValueKey('remove-fig-group-${child.id}'),
                tooltip: l10n.collectionQueryRemoveFigureGroup,
                icon: const Icon(Icons.close),
                onPressed: () {
                  group.children.remove(child);
                  onChanged();
                },
              ),
            ],
          ),
        );
    }
  }
}

/// The reusable move + section + params editor for a single [BuilderFigure].
class _FigureEditor extends StatelessWidget {
  const _FigureEditor({
    required this.figure,
    required this.taxonomy,
    required this.dialect,
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderFigure figure;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  MoveDef? get _move =>
      figure.move == null ? null : taxonomy.resolve(figure.move!);

  @override
  Widget build(BuildContext context) {
    final move = _move;
    final paramSpecs = move?.params ?? const <String, ParamSpec>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: _MoveField(
                key: ValueKey('move-${figure.id}'),
                figure: figure,
                taxonomy: taxonomy,
                onChanged: onChanged,
              ),
            ),
            _SectionDropdown(
              figure: figure,
              sectionLabels: sectionLabels,
              onChanged: onChanged,
            ),
          ],
        ),
        if (paramSpecs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in paramSpecs.entries)
                  if (figureParamChoices(entry.value) case final choices?)
                    _ParamDropdown(
                      figure: figure,
                      paramKey: entry.key,
                      spec: entry.value,
                      choices: choices,
                      dialect: dialect,
                      onChanged: onChanged,
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MoveField extends StatelessWidget {
  const _MoveField({
    super.key,
    required this.figure,
    required this.taxonomy,
    required this.onChanged,
  });

  final BuilderFigure figure;
  final Taxonomy taxonomy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final current = figure.move == null
        ? ''
        : (taxonomy.resolve(figure.move!)?.displayName ?? figure.move!);
    return MoveTypeAheadField(
      initialText: current,
      taxonomy: taxonomy,
      // New capability (this call site had no ValueKeys before, so there's
      // no existing test dependency to preserve — see PR body): lets the
      // narrow-layout sheet's field/options be found by key like every
      // other picker, and gives assistive tech a stable identity per figure.
      fieldKey: 'has-figure-${figure.id}',
      onSelected: (m) {
        if (figure.move != m.id) {
          figure.move = m.id;
          figure.params.clear();
          onChanged();
        }
      },
      onCleared: () {
        if (figure.move != null) {
          figure.move = null;
          figure.params.clear();
          onChanged();
        }
      },
    );
  }
}

/// A reusable move type-ahead: a [ResponsiveAutocomplete] over the
/// [Taxonomy]'s moves (matching display name, id, or search keywords),
/// rendered as a dense outlined [TextField]. Shared by the Advanced builder's
/// "has figure" rows and the By-Phrase panel so both search moves identically.
///
/// [onSelected] fires when the user picks a move; [onCleared] (optional) fires
/// when the field is emptied. Multi-select callers (e.g. the By-Phrase panel)
/// show chosen moves as chips and remount this field with a fresh [initialText]
/// after each pick so the input is ready for the next entry.
class MoveTypeAheadField extends StatelessWidget {
  const MoveTypeAheadField({
    super.key,
    required this.taxonomy,
    required this.onSelected,
    this.initialText = '',
    this.onCleared,
    this.labelText,
    this.hintText,
    this.fieldKey,
  });

  final Taxonomy taxonomy;
  final ValueChanged<MoveDef> onSelected;
  final String initialText;
  final VoidCallback? onCleared;
  final String? labelText;
  final String? hintText;

  /// Optional key stem for the inner [TextField] (`<fieldKey>-input`) and
  /// each option row (`<fieldKey>-option-<moveId>`).
  ///
  /// This call site previously had NO `ValueKey`s at all (it used
  /// [Autocomplete]'s default overlay, un-keyed) and no test targets them —
  /// so threading this through is a new capability the migration to
  /// [ResponsiveAutocomplete] adds, not a rename of anything pre-existing.
  final String? fieldKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = labelText ?? l10n.collectionQueryMoveLabel;
    return ResponsiveAutocomplete<MoveDef>(
      initialValue: TextEditingValue(text: initialText),
      displayStringForOption: (m) => m.displayName,
      // Reuses the field's own label as the sheet's a11y announcement (e.g.
      // "Move"), matching the pattern in `MoveAutocomplete`.
      sheetSemanticLabel: label,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<MoveDef>.empty();
        return taxonomy.moves.values
            .where((m) {
              return m.displayName.toLowerCase().contains(q) ||
                  m.id.toLowerCase().contains(q) ||
                  m.searchKeywords.any((k) => k.toLowerCase().contains(q));
            })
            .take(8);
      },
      onSelected: (m) {
        onSelected(m);
      },
      optionTileBuilder: (context, m, onSelected) {
        return ListTile(
          key: fieldKey == null ? null : ValueKey('$fieldKey-option-${m.id}'),
          dense: true,
          title: Text(m.displayName),
          onTap: onSelected,
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: fieldKey == null ? null : ValueKey('$fieldKey-input'),
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText ?? l10n.collectionQueryMoveHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (text) {
            // Clearing the field clears the move.
            if (text.trim().isEmpty) onCleared?.call();
          },
          onSubmitted: (_) => onSubmit(),
        );
      },
    );
  }
}

class _SectionDropdown extends StatelessWidget {
  const _SectionDropdown({
    required this.figure,
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderFigure figure;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.collectionQuerySectionLabel,
      child: DropdownButton<String?>(
        key: ValueKey('section-${figure.id}'),
        value: figure.section,
        hint: Text(l10n.collectionQueryAnySection),
        onChanged: (value) {
          figure.section = value;
          onChanged();
        },
        items: [
          DropdownMenuItem(
            value: null,
            child: Text(l10n.collectionQueryAnySection),
          ),
          for (final label in sectionLabels)
            DropdownMenuItem(value: label, child: Text(label)),
        ],
      ),
    );
  }
}

class _ParamDropdown extends StatelessWidget {
  const _ParamDropdown({
    required this.figure,
    required this.paramKey,
    required this.spec,
    required this.choices,
    required this.dialect,
    required this.onChanged,
  });

  final BuilderFigure figure;
  final String paramKey;

  /// The parameter's spec. Needed to label its values the way the dance editor
  /// labels them: dancer kinds route through the dialect, everything else is
  /// humanized.
  final ParamSpec spec;

  /// The parameter's full DOMAIN, as [figureParamChoices] reports it — which
  /// may include [ParamVocab.unspecified]. Not the same thing as the list the
  /// user may pick from; see [build].
  final List<String> choices;
  final Dialect dialect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = figure.params[paramKey] as String?;
    return Semantics(
      label: paramKey,
      child: DropdownButton<String?>(
        key: ValueKey('param-${figure.id}-$paramKey'),
        value: value,
        hint: Text(l10n.collectionQueryAnyParam(paramKey)),
        onChanged: (v) {
          v == null
              ? figure.params.remove(paramKey)
              : figure.params[paramKey] = v;
          onChanged();
        },
        items: [
          DropdownMenuItem(
            value: null,
            child: Text(l10n.collectionQueryAnyParam(paramKey)),
          ),
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text(choice)),
        ],
      ),
    );
  }
}
